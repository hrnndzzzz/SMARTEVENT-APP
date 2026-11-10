"""Render SAP data onto the controlled SAS-SDS-FO-020 form."""
import os
import re
import subprocess
from copy import deepcopy
import tempfile
import textwrap
import threading
from io import BytesIO
from pathlib import Path

from docx import Document
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt
from docx.text.paragraph import Paragraph as DocxParagraph
from docx.text.run import Run
from PIL import Image, ImageDraw
from pypdf import PdfReader, PdfWriter
from reportlab.lib import colors
from reportlab.pdfgen.canvas import Canvas


DOCX_TEMPLATE = Path(__file__).parents[1] / 'templates' / 'SAS-SDS-FO-020-001-STUDENT-ACTIVITY-PROPOSAL-FORM-V.3.docx'
_BOX = re.compile(r'\(\s*\)')
_BLANK = re.compile(r'_{3,}')
_NOT_XML = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f]')


def signature_slots(details):
    return (
        (details['organization_name'] + ' President', 'Prepared by'),
        (details['organization_name'] + ' Moderator', 'Reviewed by'),
        # An organization outside any department has no Dean; the line stays on the paper.
        ((details.get('department') or '') + ' Dean' if details.get('department')
         else 'Dean (not applicable: no department)', 'Reviewed by'),
        ('SDS Coordinator/Activity Officer', 'Reviewed by'),
        ('Director, SAS', 'Noted by'),
        ('Assistant VPAA', 'Endorsed by'),
        ('VPAA', 'Recommending Approval'),
        ('Applicable admins', 'Recommending Approval'),
        ('University President', 'Approved by'),
    )


def _clean(value):
    """Text Word can hold: no None, lists joined, and no control characters pasted in from other apps."""
    if value is None:
        return ''
    if isinstance(value, (list, tuple)):
        value = ', '.join(map(str, value))
    return _NOT_XML.sub('', str(value).replace('\r\n', '\n'))


def _key(label):
    return re.sub(r'[^a-z0-9]+', '_', str(label).casefold()).strip('_')


def _cells(row):
    return list(dict.fromkeys(row.cells))  # merged cells repeat in row.cells


def _value_cell(table, label):
    """The cell right after the one labelled `label`, in the same row."""
    for row in table.rows:
        cells = _cells(row)
        for i, cell in enumerate(cells[:-1]):
            if cell.text.strip().startswith(label):
                return cells[i + 1]
    raise LookupError(label)


def _write(cell, value):
    """One paragraph per line: a line break inside a justified cell stretches the line before it."""
    value = _clean(value)
    if not value:
        return
    paragraph = cell.paragraphs[0]
    for i, line in enumerate(value.splitlines()):
        if i:
            copy = deepcopy(paragraph._p)  # keeps the cell's alignment and spacing
            for child in list(copy):
                if child.tag != qn('w:pPr'):
                    copy.remove(child)
            paragraph._p.addnext(copy)
            paragraph = DocxParagraph(copy, cell)
        paragraph.add_run(line)


def _mark(paragraphs, label):
    """Turn the empty box before `label` into (X); the box may sit in an earlier run of the same paragraph."""
    for p in paragraphs:
        runs = p.runs
        for i, run in enumerate(runs):
            at = run.text.find(label)
            if at < 0:
                continue
            for j in range(i, -1, -1):
                boxes = list(_BOX.finditer(runs[j].text if j < i else run.text[:at]))
                if boxes:
                    b = boxes[-1]
                    runs[j].text = runs[j].text[:b.start()] + '(X)' + runs[j].text[b.end():]
                    return
    raise LookupError(label)  # a changed template fails loudly instead of printing an unticked form


def _tick_matching(paragraphs, labels, values):
    """Tick each label one of `values` names; returns the values the form has no box for."""
    wanted = {_key(v): v for v in (values if isinstance(values, (list, tuple)) else [values]) if v not in (None, '')}
    for label in labels:
        if wanted.pop(_key(label), None) is not None:
            _mark(paragraphs, label)
    return list(wanted.values())


def _fill_blank(paragraphs, label, value):
    """Write `value` over the first ____ after `label`. Returns False when there is nothing to write or no such blank."""
    value = _clean(value)
    if not value:
        return False  # an unanswered blank keeps its line on the paper
    for p in paragraphs:
        runs, start = p.runs, None
        for i, run in enumerate(runs):
            if start is None:
                at = run.text.find(label)
                if at < 0:
                    continue
                start = at + len(label)
            blank = _BLANK.search(run.text, start)
            start = 0
            if blank:
                run.text = run.text[:blank.start()] + value + run.text[blank.end():]
                for after in runs[i + 1:]:  # the template splits some blanks over runs: QTY.:___ / _]
                    rest = after.text.lstrip('_')
                    if rest == after.text:
                        break
                    after.text = rest
                    if rest:
                        break
                return True
    return False


def _cell_with(table, text):
    return next(c for row in table.rows for c in _cells(row) if text in c.text)


# Support type -> (the form's label, the blank the quantity goes in, the blank the specify text goes in).
_SUPPORT = {
    'budget': ('BUDGET', None, 'BUDGET :'), 'vehicle': ('VEHICLE', 'NO. OF PASSENGER/S:', None),
    'food': ('FOOD/SNACKS', 'NO. OF PAX:', None), 'room': ('ROOM/VENUE', None, 'ROOM/VENUE:'),
    'sound': ('SOUND SYSTEM', None, None), 'microphone': ('MICROPHONE', 'QTY.:', None),
    'projector': ('LCD PROJECTOR', None, None), 'chairs': ('CHAIRS AND TABLES', None, None),
    'tables': ('CHAIRS AND TABLES', None, None), 'other': ('OTHERS:', None, None),
    'diverse_needs': ('PROVISION FOR STUDENTS WITH DIVERSE NEEDS:', None, None),
}


def _fill_support(table, requests):
    ticked = set()
    for item in requests:
        label, count_at, specify_at = _SUPPORT[item['type']]
        cell = _cell_with(table, label)
        if label not in ticked and _BOX.search(cell.text):  # OTHERS and DIVERSE NEEDS have no box
            _mark(cell.paragraphs, label)
            ticked.add(label)
        quantity, specify = item.get('quantity'), _clean(item.get('specify'))
        rest = []
        if not (count_at and _fill_blank(cell.paragraphs, count_at, quantity)):
            shared = sum(entry[0] == label for entry in _SUPPORT.values()) > 1  # chairs and tables share a box
            rest.append(f"{item['type'].title()}: {quantity}" if shared else f'Quantity: {quantity}')
        if specify and not (specify_at and _fill_blank(cell.paragraphs, specify_at, specify)):
            rest.append(specify)
        if rest:
            cell.add_paragraph(', '.join(rest))


def _fill_clearance(table, snapshot):
    c = snapshot.get('clearance') or {}
    answers = {'yes': 'Yes', 'not_applicable': 'Not Applicable', 'none': 'None'}
    for label, key in (('Consent Form', 'parents_consent'), ('Academic Class Interruption', 'class_interruption'),
                       ('Medical Exam Request', 'medical_exam'), ('Report of Compliance', 'report_of_compliance')):
        cell = _cell_with(table, label)
        _tick_matching(cell.paragraphs, ('Yes', 'Not Applicable', 'None'), answers.get(c.get(key)))
        if c.get(key + '_reason'):
            cell.add_paragraph(_clean(c[key + '_reason']))
    classes = _cell_with(table, 'Academic Class Interruption')
    _fill_blank(classes.paragraphs, 'Remarks:', c.get('class_interruption_remarks'))
    for row in (snapshot.get('collections') or {}).get('affected-classes', []):
        classes.add_paragraph(_clean(f"{row.get('year_level', '')} | {row.get('subject', '')} | "
                                     f"{row.get('class_date', '')} {row.get('start', '')}-{row.get('end', '')} | "
                                     f"{row.get('professor', '')}"))
    if snapshot['details'].get('excuse_arrangement'):
        classes.add_paragraph(_clean(snapshot['details']['excuse_arrangement']))
    _fill_blank(_cell_with(table, 'Student-Personnel Ratio').paragraphs, 'Ratio:', c.get('student_personnel_ratio'))
    names = [a.get('file_name', a.get('display_name', '')) for a in snapshot.get('attachments') or []]
    # Its blank is a line of its own under the label, so take the cell's first blank.
    _fill_blank(_cell_with(table, 'Attachments:').paragraphs, '', [x for x in [c.get('attachments'), *names] if x])


def _signature_png(strokes):
    """The SDS signature, drawn the way _draw_signature draws it: x and y run 0 to 1 from the top left."""
    width, height = 540, 52
    image = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    pen = ImageDraw.Draw(image)
    for stroke in strokes:
        points = [(p['x'] * (width - 1), p['y'] * (height - 1)) for p in stroke]
        if len(points) == 1:
            (x, y), = points
            pen.ellipse((x - 2, y - 2, x + 2, y + 2), fill='black')
        else:
            pen.line(points, fill='black', width=3)
    out = BytesIO()
    image.save(out, 'PNG')
    out.seek(0)
    return out


def fill_form(snapshot, *, review=None, signer_name=None, signature_strokes=None, signed=False, comments=False):
    """The official Word form with the proposal written into its cells, as .docx bytes.
    comments=True adds the SDS Office's remarks as Word comments, each on the part it is about."""
    doc = Document(str(DOCX_TEMPLATE))
    d, flow = snapshot['details'], (snapshot.get('collections') or {}).get('program-flow', [])
    every = [DocxParagraph(p, doc._body) for p in doc.element.body.iter(qn('w:p'))]  # text boxes too
    _fill_blank(every, 'S.Y.', d.get('school_year'))
    _fill_blank(every, 'Date of Proposal:', d.get('proposal_date'))

    _tick_matching(_value_cell(doc.tables[0], 'Department:').paragraphs,
                   ('College', 'Alternative Education', 'Graduate Studies', 'Extensions Office', 'COM'),
                   d.get('department_type'))
    if d.get('setting') == 'off_campus' and d.get('off_campus_agreement'):
        sign_box = _cells(doc.tables[1].rows[0])[0]
        sign_box.paragraphs[0].insert_paragraph_before().add_run('X').bold = True

    part1 = doc.tables[2]
    value = lambda label: _value_cell(part1, label)
    for label, key in (('Activity Title:', 'title'), ('Organization:', 'organization_name'),
                       ('Activity Date:', 'activity_date'), ('Program/Course:', 'course'), ('Venue:', 'venue'),
                       ('Department:', 'department'), ('Personnel-In-Charge:', 'persons_in_charge'),
                       ('Attire:', 'attire'), ('No. of Students', 'expected_students'), ('Rationale:', 'rationale'),
                       ('Objective/s:', 'objectives'), ('Emergency Plan:', 'emergency_plan'),
                       ('Budget:', 'total_budget'), ('Source of Budget:', 'funding_source')):
        _write(value(label), d.get(key))
    _write(value('Time:'), f"{_clean(d.get('start_time'))} - {_clean(d.get('end_time'))}")
    _write(value('Program Flow:'), '\n'.join(
        f"{_clean(row.get('start'))} - {_clean(row.get('end'))}  {_clean(row.get('activity'))}" for row in flow))

    _tick_matching(value('Modality:').paragraphs, ('Face-to-face', 'Online', 'Hybrid'), d.get('modality'))
    setting_row = next(r for r in part1.rows if any(c.text.strip() == 'Setting:' for c in r.cells))
    _tick_matching([p for c in _cells(setting_row) for p in c.paragraphs],
                   ('In-Campus', 'Online', 'Off-Campus'),
                   {'on_campus': 'In-Campus', 'off_campus': 'Off-Campus'}.get(d.get('setting'), d.get('setting')))
    _tick_matching(value('Activity Type:').paragraphs,
                   ('Co-Curricular', 'Extra-Curricular', 'Subject-Embedded/Academic'), d.get('activity_types'))
    _tick_matching(value('Scope:').paragraphs,
                   ('Organizational', 'Institutional', 'Regional', 'National', 'Departmental'), d.get('scope'))
    programs = value('Program:').paragraphs
    others = _tick_matching(programs, ('Team Building', 'Leadership Summit', 'General Assembly', 'Competition',
                                       'Press Conference', 'Seminar/Convention'), d.get('program_types'))
    if others:
        _mark(programs, 'Others:')
        named = [p for p in others if _key(p) != 'others']  # the app's bare "Others" choice has nothing to write
        if named:
            _fill_blank(programs, 'Others:', named)
    _tick_matching(value('Applicable Augustinian Core Values:').paragraphs,
                   ('Courage', 'Compassion', 'Community-Oriented', 'Humility', 'Interiority', 'Missionary Spirit'),
                   d.get('core_values'))
    egas = value('Expected Graduates Attribute:').paragraphs
    for n in d.get('egas') or []:
        _mark(egas, f'EGA {n}:')

    _fill_support(doc.tables[3], (snapshot.get('collections') or {}).get('support-requests', []))
    _fill_clearance(doc.tables[4], snapshot)
    details_at = next(i for i, p in enumerate(doc.paragraphs) if p.text.startswith('OTHER DETAILS'))
    if d.get('additional_information'):
        doc.paragraphs[details_at + 1].add_run(_clean(d['additional_information']))

    sds = _cell_with(doc.tables[5], 'SDS Coordinator')
    if comments:
        _add_comments(doc, every, review)
    if signed:
        runs = [r for p in sds.paragraphs for r in p.runs]
        name = runs[next(i for i, r in enumerate(runs) if r.text.startswith('SDS Coordinator')) - 1]
        name.text = _clean(signer_name or 'SDS Staff')
        if signature_strokes:
            picture = DocxParagraph(name._r.getparent(), sds).add_run()
            picture.add_picture(_signature_png(signature_strokes), width=Inches(1.9))
            picture.add_break()
            name._r.addprevious(picture._r)

    # On paper Part 5 starts a new page, pushed there by empty lines; once Parts 1-4 grow those lines
    # land mid-page and split the signatory table. Drop them and break the page instead.
    heading = doc.tables[5]._tbl.getprevious()  # "Part 5: University Clearance (Signatories)"
    spacer = heading.getprevious()
    while spacer is not None and spacer.tag == qn('w:p') and not ''.join(spacer.itertext()).strip():
        spacer, gone = spacer.getprevious(), spacer
        gone.getparent().remove(gone)
    DocxParagraph(heading, doc._body).paragraph_format.page_break_before = True

    # The template ends with empty lines after Part 6; once Part 5 grows they spill onto a blank page.
    # Word needs one paragraph after the last table, so keep one and make it 1pt tall.
    trailing = [el for el in doc.tables[-1]._tbl.itersiblings(qn('w:p')) if not ''.join(el.itertext()).strip()]
    for el in trailing[:-1]:
        el.getparent().remove(el)
    end = DocxParagraph(trailing[-1], doc._body).paragraph_format
    end.line_spacing, end.space_before, end.space_after = Pt(1), Pt(0), Pt(0)

    budget = (snapshot.get('collections') or {}).get('budget-items', [])
    if budget:
        heading = doc.add_paragraph()
        heading.paragraph_format.page_break_before = True
        heading.add_run('Budget breakdown').bold = True
        table = doc.add_table(rows=1, cols=4, style='Table Grid')
        for cell, heading in zip(table.rows[0].cells, ('Particulars', 'Quantity', 'Unit cost (PHP)', 'Amount (PHP)')):
            cell.text = heading
        for item in budget:
            for cell, v in zip(table.add_row().cells, (item.get('particulars'), item.get('quantity', 1),
                                                       item.get('unit_cost'), item.get('amount'))):
                cell.text = _clean(v)

    out = BytesIO()
    doc.save(out)
    return out.getvalue()


def _watermark(canvas, text):
    canvas.saveState()
    canvas.setFillColor(colors.red)
    canvas.setFillAlpha(0.11)
    canvas.translate(306, 396)
    canvas.rotate(35)
    canvas.setFont('Helvetica-Bold', 25)
    canvas.drawCentredString(0, 0, text)
    canvas.restoreState()


def _footer(canvas, revision, verification_url, signed, rejected=False):
    canvas.saveState()
    canvas.setFont('Helvetica', 6)
    line = f'SAP revision {revision}' + (' | SDS signed' if signed else ' | Rejected by SDS' if rejected else ' | Unsigned')
    if verification_url:
        line += ' | Verify: ' + verification_url
    # One line between Word's body (ends at y=72) and its footer rule (near y=57).
    canvas.drawString(72, 63, line)
    if signed:
        _watermark(canvas, 'SIGNED AND APPROVED BY SDS OFFICE')
    elif rejected:
        _watermark(canvas, 'REJECTED BY THE SDS OFFICE')
    canvas.restoreState()


_PART_4 = 'Part 4: SDS Office Clearance'
_ANCHORS = {  # the paragraph each section remark's comment sits on; the overall remark sits on _PART_4
    'activity_details': 'Activity Title:', 'budget': 'Budget:', 'support_requests': 'Part 2: School Support (Requests)',
    'additional_information': 'Part 3: Additional Information', 'clearance': _PART_4, 'other': _PART_4,
}


_LABELS = {  # each section's name as the app shows it (SapRemarkSection), printed before its remark
    'activity_details': 'Activity details', 'budget': 'Budget', 'support_requests': 'School support',
    'additional_information': 'Additional information', 'clearance': 'Clearance', 'other': 'Other',
}


def _remarks(review):
    """(anchor label, section name, remark) for each saved remark: the overall one first, then the sections."""
    review = review or {}
    rows = [(_PART_4, 'Overall', review['overall_remarks'])] if (review.get('overall_remarks') or '').strip() else []
    return rows + [(_ANCHORS.get(key, _PART_4), _LABELS.get(key, key), text)
                   for key, text in (review.get('section_remarks') or {}).items() if text.strip()]


def _add_comments(doc, paragraphs, review):
    """One Word comment per saved remark, named for its section, just before its part's label;
    a missing label falls back to the Part 4 heading."""
    find = lambda label: next((p for p in paragraphs if p.text.strip().startswith(label) and p.runs), None)
    for anchor, name, text in _remarks(review):  # no remarks: no comments part, so the printed page keeps its normal width
        paragraph = find(anchor) or find(_PART_4)
        runs = paragraph.runs
        if not _USE_WORD:
            # LibreOffice paints over the text a comment is attached to, so it gets an empty run before the label.
            # Not for Word: it keeps the labels readable and drops some comments attached to an empty run.
            point = OxmlElement('w:r')
            next((r for r in runs if r.text), runs[0])._r.addprevious(point)
            runs = [Run(point, paragraph)]
        # Word clips a margin comment at about 870 characters, so a long remark is several comments on the same part.
        # The name, 690 characters and the " (n/m)" label (6 characters up to 9 parts) stay within 700.
        parts = textwrap.wrap(_clean(text), 690 - len(name) - 2, replace_whitespace=False)
        for number, part in enumerate(parts, 1):
            doc.add_comment(runs, text=f'{name}: {part}' + (f' ({number}/{len(parts)})' if len(parts) > 1 else ''),
                            author='SDS Office', initials='SDS')


def _comment_links(page, review):
    """(label point, box point) for each comment LibreOffice printed in this page's margin, to the label it is about."""
    width, pieces = float(page.mediabox.width), []
    page.extract_text(visitor_text=lambda text, cm, tm, *_: text.strip() and pieces.append(
        (text.strip(), tm[4] * cm[0] + cm[4], tm[5] * cm[3] + cm[5])))
    links = []
    for anchor, name, _ in _remarks(review):
        boxes = [(x, y) for text, x, y in pieces if x > width * 0.7 and text.startswith(name + ':')]
        labels = [sorted((x, y) for text, x, y in pieces if x <= width * 0.7 and text.startswith(label))
                  for label in (anchor, _PART_4)]  # the Part 4 heading, as in _add_comments, when the label is missing
        label = labels[0] or labels[1]
        links += [(label[0], box) for box in boxes if label]
    return links


def _link_comments(pdf, review):
    """A dashed line from each part's label to its comment box, which LibreOffice leaves unjoined (Word draws its own)."""
    writer = PdfWriter(clone_from=PdfReader(BytesIO(pdf)))
    for page in writer.pages:
        try:
            links = _comment_links(page, review)
        except Exception:  # a line is a reading aid; a page it cannot be found on still prints
            continue
        if not links:
            continue
        layer = BytesIO()
        canvas = Canvas(layer, pagesize=(float(page.mediabox.width), float(page.mediabox.height)))
        canvas.setStrokeColor(colors.HexColor('#2F6FD0'))
        canvas.setFillColor(colors.HexColor('#2F6FD0'))
        canvas.setLineWidth(0.7)
        canvas.setDash(2, 2)
        for (label_x, label_y), (box_x, box_y) in links:
            start = (label_x - 4, label_y - 2)  # just under the start of the label
            canvas.circle(*start, 1.6, stroke=0, fill=1)
            path = canvas.beginPath()
            path.moveTo(*start)
            path.lineTo(box_x - 10, start[1])  # along the row to the form's edge, then up or down to the box
            path.lineTo(box_x - 2, box_y + 3)
            canvas.drawPath(path, stroke=1, fill=0)
        canvas.save()
        page.merge_page(PdfReader(layer).pages[0])
    out = BytesIO()
    writer.write(out)
    return out.getvalue()


_WORD_LOCK = threading.Lock()
_WORD_WAIT = 30  # seconds a print waits for the one before it; a print takes about 5 s
_WORD_TIMEOUT = 60  # wait + timeout stay under the app's 120 s patience, so its user sees this error
_USE_WORD = os.name == 'nt'  # Windows laptops print with Word; the Linux server (Dockerfile) uses LibreOffice
# One LibreOffice profile, made ready in the Dockerfile: a fresh one per print is a slow first start on a small server.
# Prints take turns under _WORD_LOCK, so they never share it at the same time.
_LIBREOFFICE_PROFILE = Path(tempfile.gettempdir()) / 'smartevent-libreoffice'
# COM starts Word outside powershell's process tree, so the script notes Word's process id for a timeout.
_WORD_SCRIPT = (
    "$before = @(Get-Process WINWORD -ErrorAction SilentlyContinue).Id; "
    "$w = New-Object -ComObject Word.Application; "
    "@(Get-Process WINWORD -ErrorAction SilentlyContinue).Id | Where-Object {{ $before -notcontains $_ }} "
    "| Set-Content '{pid}'; "
    "$w.Visible = $false; $w.DisplayAlerts = 0; "
    "try {{ $d = $w.Documents.Open('{src}', $false, $true); {export}; $d.Close(0) }} "
    "finally {{ $w.Quit([ref]0) }}"  # 0: close without saving; Word's Quit takes it by reference
)
_PLAIN_EXPORT = "$d.ExportAsFixedFormat('{dst}', 17)"
# Print view with the comments in the margin ("with markup"); the last argument, 7, is wdExportDocumentWithMarkup.
_MARKUP_EXPORT = (
    "$d.ActiveWindow.View.Type = 3; $d.ActiveWindow.View.ShowComments = $true; "
    "$d.ActiveWindow.View.RevisionsFilter.Markup = 2; $d.ActiveWindow.View.MarkupMode = 0; "
    "$d.ExportAsFixedFormat('{dst}', 17, $false, 0, 0, 1, 1, 7)"
)


def _kill_word(pid_file):
    """Best effort: stop the Word a timed-out conversion started, so hung copies cannot pile up."""
    try:
        for pid in pid_file.read_text().split():
            subprocess.run(['taskkill', '/F', '/PID', pid], capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        pass  # the conversion has already failed; that is the error to report


def _convert_command(folder, src, dst, pid, markup):
    if _USE_WORD:
        quoted = lambda path: str(path).replace("'", "''")  # PowerShell single-quoted string
        export = (_MARKUP_EXPORT if markup else _PLAIN_EXPORT).format(dst=quoted(dst))
        return ['powershell', '-NoProfile', '-NonInteractive', '-Command',
                _WORD_SCRIPT.format(src=quoted(src), pid=quoted(pid), export=export)]
    # LibreOffice's counterpart of Word's markup view: the comments print in the page margin.
    pdf = 'pdf:writer_pdf_Export:{"ExportNotesInMargin":{"type":"boolean","value":"true"}}' if markup else 'pdf'
    return ['soffice', f'-env:UserInstallation={_LIBREOFFICE_PROFILE.as_uri()}', '--headless', '--norestore',
            '--nologo', '--nodefault', '--convert-to', pdf, '--outdir', str(folder), str(src)]


def docx_to_pdf(docx, *, markup=False):
    """Word (or LibreOffice off Windows) turns the filled form into a PDF, one document at a time;
    markup=True prints its comments in the margin."""
    # Bounded, because a waiting request holds a database connection and, for submit and sign, the event row.
    if not _WORD_LOCK.acquire(timeout=_WORD_WAIT):
        raise RuntimeError('SAP printing is busy with another form; try again in a minute.')
    try:
        # A Word that would not die can still hold form.docx; cleanup must not replace the real error.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as folder:
            src, dst, pid = (Path(folder) / name for name in ('form.docx', 'form.pdf', 'word.pid'))
            src.write_bytes(docx)
            done = None
            try:
                done = subprocess.run(_convert_command(Path(folder), src, dst, pid, markup),
                                      timeout=_WORD_TIMEOUT, check=True, capture_output=True)
                return dst.read_bytes()  # soffice can exit 0 without writing it; the OSError is caught below
            except (OSError, subprocess.SubprocessError) as exc:
                if isinstance(exc, subprocess.TimeoutExpired):
                    _kill_word(pid)
                # With no PDF after a clean exit, the reason is in what the finished run printed (soffice uses stdout).
                ran = exc if done is None else done
                said = b' '.join(out for out in (getattr(ran, 'stdout', None), getattr(ran, 'stderr', None))
                                 if isinstance(out, bytes)).decode(errors='replace').strip()[-300:]
                raise RuntimeError(f'Could not convert the SAP form to PDF: {exc} {said}'.strip()) from exc
    finally:
        _WORD_LOCK.release()


def _stamp(pdf, revision, verification_url, signed, rejected=False):
    """The revision line, the verify link and, once signed or rejected, the watermark, on every page Word made."""
    writer = PdfWriter(clone_from=PdfReader(BytesIO(pdf)))
    for page in writer.pages:
        layer = BytesIO()
        canvas = Canvas(layer, pagesize=(float(page.mediabox.width), float(page.mediabox.height)))
        _footer(canvas, revision, verification_url, signed, rejected)
        canvas.save()
        page.merge_page(PdfReader(layer).pages[0])
        for key in ('/Annots', '/AA'):
            if key in page:
                del page[key]
    out = BytesIO()
    writer.write(out)
    return out.getvalue()


def render_proposal(snapshot, revision, verification_url=None, *, review=None, signer_name=None, signature_strokes=None, signed=False, rejected=False, comments=False):
    docx = fill_form(snapshot, review=review, signer_name=signer_name, signature_strokes=signature_strokes, signed=signed,
                     comments=comments)
    # Markup only when there are comments to show: without any, the page stays full width.
    markup = comments and bool(_remarks(review))
    pdf = docx_to_pdf(docx, markup=markup)
    if markup and not _USE_WORD:
        pdf = _link_comments(pdf, review)
    return _stamp(pdf, revision, verification_url, signed, rejected)
