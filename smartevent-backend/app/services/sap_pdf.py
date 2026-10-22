"""Render SAP data onto the controlled SAS-SDS-FO-020 form."""
from io import BytesIO
from pathlib import Path
from xml.sax.saxutils import escape

from pypdf import PdfReader, PdfWriter
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer


TEMPLATE = Path(__file__).parents[1] / 'templates' / 'SAS-SDS-FO-020-001-STUDENT-ACTIVITY-PROPOSAL-FORM-V.3.pdf'
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


def _paragraph(value, style=BODY):
    if isinstance(value, (list, tuple)):
        value = ', '.join(map(str, value))
    return Paragraph(escape(str(value or '')).replace('\n', '<br/>'), style)


def _watermark(canvas):
    canvas.saveState()
    canvas.setFillAlpha(0.11)
    canvas.setFillColor(colors.red)
    canvas.translate(306, 396)
    canvas.rotate(35)
    canvas.setFont('Helvetica-Bold', 25)
    canvas.drawCentredString(0, 0, 'SIGNED AND APPROVED BY SDS OFFICE')
    canvas.restoreState()


def _footer(canvas, revision, verification_url, signed):
    canvas.saveState()
    canvas.setFont('Helvetica', 6)
    canvas.drawString(72, 65, f'SAP revision {revision}' + (' | SDS signed' if signed else ' | Unsigned'))
    if verification_url:
        canvas.drawString(72, 55, 'Verify: ' + verification_url)
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
            _text(canvas, values('school_year'), 275, 678, 110)
            _tick(canvas, values('department_type').casefold() == 'college', 179, 604)
            _tick(canvas, values('department_type').casefold() == 'alternative education', 227, 604)
            _tick(canvas, values('department_type').casefold() == 'graduate studies', 347, 604)
            _tick(canvas, values('department_type').casefold() == 'extensions office', 446, 604)
            _tick(canvas, values('department_type').casefold() == 'com', 503, 604)
            _text(canvas, str(values('proposal_date')), 150, 576, 120)
            _tick(canvas, values('setting') == 'off_campus' and d.get('off_campus_agreement'), 75, 518)
            _text(canvas, values('title'), 176, 418, 350)
            _text(canvas, values('organization_name'), 176, 403, 175)
            _text(canvas, f"{values('start_time')} - {values('end_time')}", 405, 403, 130)
            _text(canvas, str(values('activity_date')), 176, 388, 170)
            modality = values('modality')
            _tick(canvas, modality == 'face_to_face', 411, 388)
            _tick(canvas, modality == 'online', 497, 388)
            _tick(canvas, modality == 'hybrid', 411, 373)
            _text(canvas, values('course'), 176, 358, 175)
            _text(canvas, values('venue'), 410, 358, 130)
            _text(canvas, values('department'), 176, 343, 175)
            _tick(canvas, values('setting') == 'on_campus', 411, 343)
            _tick(canvas, values('setting') == 'online', 411, 314)
            _tick(canvas, values('setting') == 'off_campus', 476, 343)
            _text(canvas, values('persons_in_charge'), 176, 326, 360)
            for idx, label in enumerate(('co_curricular', 'extra_curricular', 'subject_embedded')):
                _tick(canvas, label in values('activity_types'), 176 if idx != 1 else 285, 284 if idx < 2 else 270)
            _text(canvas, values('attire'), 410, 284, 130)
            for idx, label in enumerate(('organizational', 'institutional', 'regional', 'national', 'departmental')):
                _tick(canvas, label in values('scope'), 176 + (idx % 2) * 145, 255 - (idx // 2) * 14)
            _text(canvas, str(values('expected_students')), 410, 240, 100)
            _text(canvas, values('program_types'), 176, 211, 360)
            _text(canvas, values('rationale'), 176, 179, 360, max_height=29)
            _text(canvas, values('objectives'), 176, 148, 360, max_height=29)
            core = values('core_values')
            for i, (key, x, y) in enumerate([
                ('courage',176,116), ('compassion',247,116), ('community_oriented',357,116),
                ('humility',445,116), ('interiority',498,116), ('missionary_spirit',176,102)
            ]):
                _tick(canvas, key in core, x, y)
        elif page == 1:
            egas = values('egas')
            for i, y in enumerate((709, 694, 680, 665), 1):
                _tick(canvas, i in egas, 176, y)
            flow = collections.get('program-flow', [])
            if flow:
                _text(canvas, 'See Program flow addendum', 150, 650, 390)
                overflow.append(('Program flow', '\n'.join(
                    f"{row.get('start', '')} - {row.get('end', '')}: {row.get('activity', '')}" for row in flow)))
            _text(canvas, values('emergency_plan'), 150, 619, 390, max_height=17)
            _text(canvas, str(values('total_budget')), 127, 601, 145)
            _text(canvas, values('funding_source'), 390, 601, 150)
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
                overflow.append(('Budget breakdown', '\n'.join(
                    f"{item.get('particulars', '')}: PHP {item.get('amount', '')}" for item in budget_rows)))
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
            _tick(canvas, clearance.get('parents_consent') == 'yes', 202, 271)
            _tick(canvas, clearance.get('parents_consent') == 'not_applicable', 260, 271)
            _tick(canvas, clearance.get('class_interruption') == 'yes', 258, 230)
            _tick(canvas, clearance.get('class_interruption') == 'none', 303, 230)
            _tick(canvas, clearance.get('medical_exam') == 'yes', 455, 230)
            _tick(canvas, clearance.get('medical_exam') == 'not_applicable', 512, 230)
            _text(canvas, clearance.get('student_personnel_ratio', ''), 480, 201, 70, style=SMALL)
            _tick(canvas, clearance.get('report_of_compliance') == 'yes', 248, 201)
            _tick(canvas, clearance.get('report_of_compliance') == 'not_applicable', 307, 201)
            names = ', '.join(a.get('file_name', a.get('display_name', '')) for a in attachments)
            _text(canvas, names, 311, 258, 230, style=SMALL, max_height=25, label='Supporting documents')
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
    for page, layer in zip(source.pages, overlay.pages):
        page.merge_page(layer)
        for key in ('/Annots', '/AA'):
            if key in page:
                del page[key]
        writer.add_page(page)
    if overflow:
        appendix = BytesIO()
        doc = SimpleDocTemplate(appendix, pagesize=(612, 792), leftMargin=72, rightMargin=72,
                                topMargin=60, bottomMargin=85)
        heading = ParagraphStyle('sap-heading', parent=BODY, fontName='Helvetica-Bold', fontSize=11, leading=14)
        story = [_paragraph(f'SAP revision {revision} - Form addenda', heading), Spacer(1, 12)]
        for label, value in overflow:
            story.extend([_paragraph(label, heading), Spacer(1, 5), _paragraph(value), Spacer(1, 12)])
        footer = lambda canvas, document: _footer(canvas, revision, verification_url, signed)
        doc.build(story, onFirstPage=footer, onLaterPages=footer)
        for page in PdfReader(BytesIO(appendix.getvalue())).pages:
            writer.add_page(page)
    output = BytesIO()
    writer.write(output)
    return output.getvalue()
