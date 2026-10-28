"""Render SAP data onto the controlled SAS-SDS-FO-020 form."""
import re
from io import BytesIO
from pathlib import Path
from xml.sax.saxutils import escape

from docx import Document
from docx.oxml.ns import qn
from docx.shared import Inches
from docx.text.paragraph import Paragraph as DocxParagraph
from PIL import Image, ImageDraw
from pypdf import PdfReader, PdfWriter
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, LongTable, TableStyle


TEMPLATE = Path(__file__).parents[1] / 'templates' / 'SAS-SDS-FO-020-001-STUDENT-ACTIVITY-PROPOSAL-FORM-V.3.pdf'
DOCX_TEMPLATE = TEMPLATE.with_suffix('.docx')
_BOX = re.compile(r'\(\s*\)')
_BLANK = re.compile(r'_{3,}')
_NOT_XML = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f]')
BODY = ParagraphStyle('sap-body', fontName='Helvetica', fontSize=8, leading=9)
SMALL = ParagraphStyle('sap-small', fontName='Helvetica', fontSize=7, leading=8)


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
    value = _clean(value)
    if value:
        cell.paragraphs[0].add_run(value)


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

    budget = (snapshot.get('collections') or {}).get('budget-items', [])
    if budget:
        doc.add_page_break()
        doc.add_paragraph().add_run('Budget breakdown').bold = True
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


def _paragraph(value, style=BODY):
    if isinstance(value, (list, tuple)):
        value = ', '.join(map(str, value))
    return Paragraph(escape(str(value or '')).replace('\n', '<br/>'), style)


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
    canvas.drawString(72, 72, f'SAP revision {revision}' + (' | SDS signed' if signed else ' | Unsigned'))
    if verification_url:
        canvas.drawString(72, 62, 'Verify: ' + verification_url)
    if signed:
        _watermark(canvas)
    canvas.restoreState()


def _tick(canvas, yes, x, y):
    if yes:
        canvas.setFont('Helvetica-Bold', 10)
        canvas.drawString(x, y, 'X')


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


def _overlay(snapshot, revision, verification_url, review, signer_name, signature_strokes, signed, page_count):
    output = BytesIO()
    canvas = Canvas(output, pagesize=(612, 792), pageCompression=1)
    d, clearance = snapshot['details'], snapshot.get('clearance') or {}
    collections = snapshot.get('collections') or {}
    comments = _remarks(review)
    attachments = snapshot.get('attachments') or []
    overflow = []
    values = lambda key: d.get(key, '')

    def _text(canvas, value, x, y, width, *, style=BODY, max_height=13, label=None):
        paragraph = _paragraph(value, style)
        _, height = paragraph.wrap(width, max_height)
        if height > max_height:
            label = label or next((key.replace('_', ' ').title() for key, item in d.items()
                                  if item == value), 'Form details')
            overflow.append((label, value))
            paragraph = _paragraph('See addendum: ' + label, SMALL)
            _, height = paragraph.wrap(width, max_height)
            if height > max_height:
                paragraph = _paragraph('See addendum', SMALL)
                _, height = paragraph.wrap(width, max_height)
        paragraph.drawOn(canvas, x, y - height)
        return height

    for page in range(page_count):
        if page == 0:
            canvas.setFont('Helvetica', 9)
            _text(canvas, values('school_year'), 302, 685, 100)
            _tick(canvas, values('department_type').casefold() == 'college', 179, 604)
            _tick(canvas, values('department_type').casefold() == 'alternative education', 227, 604)
            _tick(canvas, values('department_type').casefold() == 'graduate studies', 347, 604)
            _tick(canvas, values('department_type').casefold() == 'extensions office', 446, 604)
            _tick(canvas, values('department_type').casefold() == 'com', 503, 604)
            _text(canvas, str(values('proposal_date')), 150, 585, 120)
            _tick(canvas, values('setting') == 'off_campus' and d.get('off_campus_agreement'), 100, 478)
            _text(canvas, values('title'), 176, 426, 350)
            _text(canvas, values('organization_name'), 176, 411, 175)
            _text(canvas, f"{values('start_time')} - {values('end_time')}", 410, 411, 130)
            _text(canvas, str(values('activity_date')), 176, 388, 170)
            modality = values('modality')
            _tick(canvas, modality == 'face_to_face', 411, 388)
            _tick(canvas, modality == 'online', 497, 388)
            _tick(canvas, modality == 'hybrid', 411, 373)
            _text(canvas, values('course'), 176, 367, 175)
            _text(canvas, values('venue'), 410, 367, 130)
            _text(canvas, values('department'), 176, 351, 175)
            _tick(canvas, values('setting') == 'on_campus', 411, 343)
            _tick(canvas, values('setting') == 'online', 411, 314)
            _tick(canvas, values('setting') == 'off_campus', 476, 343)
            _text(canvas, values('persons_in_charge'), 176, 333, 173, max_height=35)
            for idx, label in enumerate(('co_curricular', 'extra_curricular', 'subject_embedded')):
                _tick(canvas, label in values('activity_types'), 179 if idx != 1 else 288, 284 if idx < 2 else 270)
            _text(canvas, values('attire'), 410, 284, 130)
            for idx, label in enumerate(('organizational', 'institutional', 'regional', 'national', 'departmental')):
                _tick(canvas, label in values('scope'), 179 + (idx % 2) * 81, 255 - (idx // 2) * 14)
            _text(canvas, str(values('expected_students')), 410, 240, 100)
            program_slots = {'team_building': (179, 211), 'leadership_summit': (273, 211),
                             'general_assembly': (377, 211), 'competition': (474, 211),
                             'press_conference': (179, 196), 'seminar_convention': (272, 196)}
            extra_programs = []
            for program in values('program_types'):
                key = program.strip().casefold().replace(' ', '_').replace('/', '_')
                if key in program_slots:
                    _tick(canvas, True, *program_slots[key])
                else:
                    extra_programs.append(program)
            if extra_programs:
                _tick(canvas, True, 378, 196)
                _text(canvas, ', '.join(extra_programs), 420, 204, 115, style=SMALL,
                      max_height=8, label='Other program types')
            _text(canvas, values('rationale'), 176, 179, 360, max_height=29)
            _text(canvas, values('objectives'), 176, 148, 360, max_height=29)
            core = values('core_values')
            for i, (key, x, y) in enumerate([
                ('courage',179,116), ('compassion',232,116), ('community_oriented',301,116),
                ('humility',403,116), ('interiority',454,116), ('missionary_spirit',179,102)
            ]):
                _tick(canvas, key in core, x, y)
        elif page == 1:
            egas = values('egas')
            for i, y in enumerate((709, 694, 680, 665), 1):
                _tick(canvas, i in egas, 179, y)
            flow = collections.get('program-flow', [])
            if flow:
                _text(canvas, 'See Program flow addendum', 176, 650, 360)
                overflow.append(('Program flow', '\n'.join(
                    f"{row.get('start', '')} - {row.get('end', '')}: {row.get('activity', '')}" for row in flow)))
            _text(canvas, values('emergency_plan'), 176, 626, 360, max_height=13)
            _text(canvas, str(values('total_budget')), 176, 609, 145)
            _text(canvas, values('funding_source'), 390, 609, 150)
            requests = collections.get('support-requests', [])
            request_slots = {'budget':(77,545),'vehicle':(311,545),'food':(77,506),'room':(311,506),
                             'sound':(77,482),'microphone':(311,482),'projector':(77,467),'chairs':(311,467),
                             'tables':(311,467),'diverse_needs':(311,452),'other':(77,452)}
            for item in requests:
                pos = request_slots.get(item.get('type'))
                if pos:
                    _tick(canvas, True, *pos)
            budget_rows = collections.get('budget-items', [])
            if budget_rows:
                _text(canvas, 'See Budget breakdown addendum', 90, 532, 210, style=SMALL)
                overflow.append(('Budget breakdown', budget_rows))
            if requests:
                overflow.append(('School support requests', '\n'.join(
                    f"{item.get('type', '')} | Quantity: {item.get('quantity', '')} | {item.get('specify', '')}"
                    for item in requests)))
            classes = collections.get('affected-classes', [])
            if classes:
                overflow.append(('Affected classes', '\n'.join(
                    f"{row.get('year_level', '')} | {row.get('subject', '')} | {row.get('class_date', '')} "
                    f"{row.get('start', '')}-{row.get('end', '')} | {row.get('professor', '')}" for row in classes)))
            if d.get('excuse_arrangement'):
                overflow.append(('Excuse arrangement', d['excuse_arrangement']))
            for field in ('parents_consent_reason', 'medical_exam_reason', 'report_of_compliance_reason',
                          'class_interruption_remarks'):
                if clearance.get(field):
                    overflow.append((field.replace('_', ' ').title(), clearance[field]))
            _text(canvas, values('additional_information'), 72, 360, 460, max_height=65)
            _tick(canvas, clearance.get('parents_consent') == 'yes', 188, 271)
            _tick(canvas, clearance.get('parents_consent') == 'not_applicable', 222, 271)
            _tick(canvas, clearance.get('class_interruption') == 'yes', 211, 230)
            _tick(canvas, clearance.get('class_interruption') == 'none', 245, 230)
            _tick(canvas, clearance.get('medical_exam') == 'yes', 420, 230)
            _tick(canvas, clearance.get('medical_exam') == 'not_applicable', 455, 230)
            _text(canvas, clearance.get('student_personnel_ratio', ''), 487, 208, 70, style=SMALL)
            _tick(canvas, clearance.get('report_of_compliance') == 'yes', 248, 201)
            _tick(canvas, clearance.get('report_of_compliance') == 'not_applicable', 284, 201)
            names = ', '.join(a.get('file_name', a.get('display_name', '')) for a in attachments)
            _text(canvas, names, 311, 265, 225, style=SMALL, max_height=25, label='Supporting documents')
            if comments:
                canvas.setFillColor(colors.white)
                canvas.rect(119, 214, 175, 10, fill=1, stroke=0)
                canvas.setFillColor(colors.black)
                _text(canvas, '\n'.join(comments), 119, 224, 175, style=SMALL, max_height=8, label='SDS review remarks')
        elif page == 2 and signed:
            # Replace only the template's SDS name, leaving other signatories intact.
            canvas.setFillColor(colors.white)
            canvas.rect(76, 552, 151, 16, fill=1, stroke=0)
            canvas.setFillColor(colors.black)
            _text(canvas, signer_name or 'SDS Staff', 78, 565, 148, style=SMALL, max_height=13, label='SDS signer')
            _draw_signature(canvas, signature_strokes or [], 82, 570, 135, 13)
        _footer(canvas, revision, verification_url, signed)
        canvas.showPage()
    canvas.save()
    return output.getvalue(), overflow


def _draw_signature(canvas, strokes, x, y, width, height):
    canvas.saveState()
    canvas.setStrokeColor(colors.black)
    canvas.setLineWidth(1.4)
    for stroke in strokes:
        points = [(x + point['x'] * width, y + (1 - point['y']) * height) for point in stroke]
        if len(points) == 1:
            canvas.circle(points[0][0], points[0][1], 0.8, stroke=1, fill=0)
        else:
            path = canvas.beginPath()
            path.moveTo(*points[0])
            for point in points[1:]:
                path.lineTo(*point)
            canvas.drawPath(path, stroke=1, fill=0)
    canvas.restoreState()


def render_proposal(snapshot, revision, verification_url=None, *, review=None, signer_name=None, signature_strokes=None, signed=False):
    source = PdfReader(str(TEMPLATE), strict=True)
    overlay_bytes, overflow = _overlay(snapshot, revision, verification_url, review, signer_name,
                                      signature_strokes, signed, len(source.pages))
    overlay = PdfReader(BytesIO(overlay_bytes))
    writer = PdfWriter()
    for original, layer in zip(source.pages, overlay.pages):
        page = writer.add_page(original)
        page.merge_page(layer)
        for key in ('/Annots', '/AA'):
            if key in page:
                del page[key]
    if overflow:
        appendix = BytesIO()
        doc = SimpleDocTemplate(appendix, pagesize=(612, 792), leftMargin=72, rightMargin=72,
                                topMargin=60, bottomMargin=85)
        heading = ParagraphStyle('sap-heading', parent=BODY, fontName='Helvetica-Bold', fontSize=11, leading=14)
        story = [_paragraph(f'SAP revision {revision} - Form addenda', heading), Spacer(1, 12)]
        for label, value in overflow:
            story.extend([_paragraph(label, heading), Spacer(1, 5)])
            if label == 'Budget breakdown' and isinstance(value, list):
                rows = [[_paragraph(name) for name in ('Particulars', 'Quantity', 'Unit cost (PHP)', 'Amount (PHP)')]]
                rows.extend([_paragraph(item.get('particulars', '')),
                             _paragraph(str(item.get('quantity', 1))),
                             _paragraph('' if item.get('unit_cost') is None else str(item['unit_cost'])),
                             _paragraph(str(item.get('amount', '')))] for item in value)
                table = LongTable(rows, colWidths=[230, 50, 94, 94], repeatRows=1, hAlign='LEFT')
                table.setStyle(TableStyle([('VALIGN', (0, 0), (-1, -1), 'TOP'),
                                           ('BACKGROUND', (0, 0), (-1, 0), colors.whitesmoke),
                                           ('GRID', (0, 0), (-1, -1), 0.3, colors.grey),
                                           ('TOPPADDING', (0, 0), (-1, -1), 5),
                                           ('BOTTOMPADDING', (0, 0), (-1, -1), 5)]))
                story.append(table)
            else:
                story.append(_paragraph(value))
            story.append(Spacer(1, 12))
        footer = lambda canvas, document: _footer(canvas, revision, verification_url, signed)
        doc.build(story, onFirstPage=footer, onLaterPages=footer)
        for page in PdfReader(BytesIO(appendix.getvalue())).pages:
            writer.add_page(page)
    output = BytesIO()
    writer.write(output)
    return output.getvalue()
