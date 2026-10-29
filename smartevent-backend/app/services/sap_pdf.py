"""Render SAP data onto the controlled SAS-SDS-FO-020 form."""
import re
import subprocess
from copy import deepcopy
import tempfile
import threading
from io import BytesIO
from pathlib import Path

from docx import Document
from docx.oxml.ns import qn
from docx.shared import Inches, Pt
from docx.text.paragraph import Paragraph as DocxParagraph
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
        (details['department'] + ' Dean', 'Reviewed by'),
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
            rest.append(f'Quantity: {quantity}')
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


def fill_form(snapshot, *, review=None, signer_name=None, signature_strokes=None, signed=False):
    """The official Word form with the proposal written into its cells, as .docx bytes."""
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
    if _remarks(review):
        sds.add_paragraph(_clean('\n'.join(_remarks(review))))
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


def _watermark(canvas):
    canvas.saveState()
    canvas.setFillColor(colors.red)
    canvas.setFillAlpha(0.11)
    canvas.translate(306, 396)
    canvas.rotate(35)
    canvas.setFont('Helvetica-Bold', 25)
    canvas.drawCentredString(0, 0, 'SIGNED AND APPROVED BY SDS OFFICE')
    canvas.restoreState()


def _footer(canvas, revision, verification_url, signed):
    canvas.saveState()
    canvas.setFont('Helvetica', 6)
    line = f'SAP revision {revision}' + (' | SDS signed' if signed else ' | Unsigned')
    if verification_url:
        line += ' | Verify: ' + verification_url
    # One line between Word's body (ends at y=72) and its footer rule (near y=57).
    canvas.drawString(72, 63, line)
    if signed:
        _watermark(canvas)
    canvas.restoreState()


def _remarks(review):
    if not review:
        return []
    rows = []
    if review.get('overall_remarks'):
        rows.append('SDS: ' + review['overall_remarks'])
    labels = {
        'activity_details': 'Activity details', 'budget': 'Budget',
        'support_requests': 'Support requests', 'additional_information': 'Other details',
        'clearance': 'SDS clearance', 'other': 'Other',
    }
    rows.extend(f"{labels.get(key, key)}: {value}" for key, value in review.get('section_remarks', {}).items())
    return rows


_WORD_LOCK = threading.Lock()
# shortcut: needs Windows + Word; if the backend moves to Linux, swap in soffice --headless --convert-to pdf
_WORD_SCRIPT = (
    "$w = New-Object -ComObject Word.Application; "
    "$w.Visible = $false; $w.DisplayAlerts = 0; "
    "try {{ $d = $w.Documents.Open('{src}', $false, $true); $d.ExportAsFixedFormat('{dst}', 17); $d.Close(0) }} "
    "finally {{ $w.Quit() }}"
)


def docx_to_pdf(docx):
    """Word turns the filled form into a PDF, one document at a time."""
    with tempfile.TemporaryDirectory() as folder, _WORD_LOCK:
        src, dst = Path(folder) / 'form.docx', Path(folder) / 'form.pdf'
        src.write_bytes(docx)
        quoted = lambda path: str(path).replace("'", "''")  # PowerShell single-quoted string
        try:
            subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-Command',
                            _WORD_SCRIPT.format(src=quoted(src), dst=quoted(dst))],
                           timeout=120, check=True, capture_output=True)
            return dst.read_bytes()
        except (OSError, subprocess.SubprocessError) as exc:
            raise RuntimeError(f'Could not convert the SAP form to PDF: {exc}') from exc


def _stamp(pdf, revision, verification_url, signed):
    """The revision line, the verify link and, once signed, the watermark, on every page Word made."""
    writer = PdfWriter(clone_from=PdfReader(BytesIO(pdf)))
    for page in writer.pages:
        layer = BytesIO()
        canvas = Canvas(layer, pagesize=(float(page.mediabox.width), float(page.mediabox.height)))
        _footer(canvas, revision, verification_url, signed)
        canvas.save()
        page.merge_page(PdfReader(layer).pages[0])
        for key in ('/Annots', '/AA'):
            if key in page:
                del page[key]
    out = BytesIO()
    writer.write(out)
    return out.getvalue()


def render_proposal(snapshot, revision, verification_url=None, *, review=None, signer_name=None, signature_strokes=None, signed=False):
    docx = fill_form(snapshot, review=review, signer_name=signer_name, signature_strokes=signature_strokes, signed=signed)
    return _stamp(docx_to_pdf(docx), revision, verification_url, signed)
