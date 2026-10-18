"""Clean controlled six-page print form. No sample scan or signature graphics."""
from io import BytesIO
from xml.sax.saxutils import escape
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import Paragraph, Table, TableStyle
from reportlab.graphics.shapes import Drawing
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics import renderPDF

SLOTS = (
    ('Organization President', 'Prepared by'),
    ('Organization Moderator', 'Reviewed by'),
    ('Organization Moderator', 'Reviewed by'),
    ('College Dean', 'Reviewed by'),
    ('SDS Coordinator/Activity Officer', 'Reviewed by'),
    ('SAS Director', 'Noted by'),
    ('Assistant VPAA', 'Endorsed by'),
    ('VPAA', 'Recommending Approval'),
    ('University President', 'Approved by'),
)
STYLE = ParagraphStyle('sap', fontName='Helvetica', fontSize=9, leading=12)


def signature_slots(details):
    slots = list(SLOTS)
    slots[0] = (details['organization_name'] + ' President', slots[0][1])
    slots[1] = (details['organization_name'] + ' Moderator', slots[1][1])
    slots[2] = (details['organization_name'] + ' Moderator', slots[2][1])
    slots[3] = (details['department'] + ' Dean', slots[3][1])
    return slots


def text(value):
    if isinstance(value, list):
        value = ', '.join(map(str, value))
    return Paragraph(escape(str(value or '')).replace('\n', '<br/>'), STYLE)


def render_proposal(snapshot, revision, verification_url=None):
    output = BytesIO()
    canvas = Canvas(output, pagesize=(612, 792), pageCompression=1)
    canvas.setTitle('SAS-SDS-FO-020 Student Activity Proposal')
    d, c, items = snapshot['details'], snapshot.get('clearance') or {}, snapshot['collections']
    slots = signature_slots(d)
    y = 0

    def page(number):
        nonlocal y
        if number > 1:
            canvas.showPage()
        canvas.setFont('Helvetica-Bold', 12)
        canvas.drawString(36, 758, 'LA CONSOLACION UNIVERSITY PHILIPPINES')
        canvas.setFont('Helvetica', 9)
        canvas.drawString(36, 742, 'Student Affairs and Services / Student Development Services')
        canvas.setFont('Helvetica-Bold', 11)
        canvas.drawString(36, 722, 'STUDENT ACTIVITY PROPOSAL FORM')
        canvas.setFont('Helvetica', 8)
        canvas.drawString(36, 25, f'SAS-SDS-FO-020 (001) | Revision {revision} | Page {number} of 6')
        canvas.drawRightString(576, 25, 'UNSIGNED PRINTABLE COPY - physical signatures required')
        y = 697

    def heading(title):
        nonlocal y
        canvas.setFont('Helvetica-Bold', 10)
        canvas.drawString(36, y, title)
        y -= 18

    def table(rows, widths=None):
        nonlocal y
        if not rows:
            rows = [['None declared']]
        cells = [[text(cell) for cell in row] for row in rows]
        t = Table(cells, colWidths=widths or [540 / len(rows[0])] * len(rows[0]))
        t.setStyle(TableStyle([('GRID', (0, 0), (-1, -1), .4, colors.grey),
                               ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                               ('LEFTPADDING', (0, 0), (-1, -1), 6),
                               ('RIGHTPADDING', (0, 0), (-1, -1), 6),
                               ('TOPPADDING', (0, 0), (-1, -1), 5),
                               ('BOTTOMPADDING', (0, 0), (-1, -1), 5)]))
        _, height = t.wrap(540, 700)
        if y - height < 50:
            raise ValueError('Content exceeds the controlled six-page form; shorten text or reduce table rows')
        t.drawOn(canvas, 36, y - height)
        y -= height + 10

    def field(label, key):
        table([[label, d.get(key, '')]], [145, 395])

    page(1)
    table([['School year', d['school_year'], 'Department type', d['department_type']],
           ['Proposal date', d['proposal_date'], 'Revision', revision]])
    table([['Off-campus agreement', 'Not Applicable: this workflow supports on-campus and online activities only.']])
    heading('PART 1. ACTIVITY DETAILS')
    for label, key in [('Title', 'title'), ('Organization', 'organization_name')]:
        field(label, key)
    table([['Date', d['activity_date'], 'Time (Asia/Manila)', d['start_time'] + ' - ' + d['end_time']],
           ['Modality', d['modality'], 'Setting', d['setting']],
           ['Course', d.get('course', ''), 'Department', d['department']],
           ['Scope', d['scope'], 'Expected students', d['expected_students']]])
    for label, key in [('Venue / online platform', 'venue'), ('Persons in charge', 'persons_in_charge'),
                       ('Attire', 'attire'), ('Activity types', 'activity_types'), ('Program types', 'program_types')]:
        field(label, key)
    page(2)
    heading('PART 1. ACTIVITY DETAILS (continued)')
    field('Rationale', 'rationale')
    field('Objectives', 'objectives')
    values = ['courage', 'compassion', 'community_oriented', 'humility', 'interiority', 'missionary_spirit']
    table([['Augustinian values', '\n'.join(('[X] ' if v in d['core_values'] else '[ ] ') + v.replace('_', ' ').title() for v in values)]], [145, 395])
    egas = ['Critical and creative thinker', 'Competent Catholic Augustinian Marian professional',
            'Socially responsive steward', 'Transformative lifelong learner']
    table([['Expected Graduate Attributes', '\n'.join(('[X] ' if i in d['egas'] else '[ ] ') + f'EGA {i}: {label}' for i, label in enumerate(egas, 1))]], [145, 395])
    page(3)
    heading('PART 1. PROGRAM FLOW AND SAFETY')
    table([['Start', 'End', 'Activity']] + [[r['start'], r['end'], r['activity']] for r in items.get('program-flow', [])], [70, 70, 400])
    field('Emergency plan', 'emergency_plan')
    field('Budget (PHP)', 'total_budget')
    field('Funding source', 'funding_source')
    page(4)
    heading('PART 2. SCHOOL SUPPORT REQUESTS')
    table([['Type', 'Quantity', 'Specify']] + [[r['type'], r['quantity'], r.get('specify', '')] for r in items.get('support-requests', [])], [110, 60, 370])
    heading('PART 3. ADDITIONAL INFORMATION')
    field('Other details', 'additional_information')
    table([['Budget particulars', 'Amount (PHP)']] + [[r['particulars'], r['amount']] for r in items.get('budget-items', [])] + [['TOTAL (PHP)', d['total_budget']]], [400, 140])
    field('Excuse-letter arrangement', 'excuse_arrangement')
    table([['Year / subject', 'Date / time', 'Professor']] + [[r['year_level'] + ' / ' + r['subject'], r['class_date'] + '\n' + r['start'] + ' - ' + r['end'], r['professor']] for r in items.get('affected-classes', [])], [170, 180, 190])
    page(5)
    heading('PART 4. SDS CLEARANCE (SDS ONLY)')
    rows = []
    for key, label in [('parents_consent', 'Parents consent'), ('attachments', 'Attachments'), ('class_interruption', 'Class interruption'), ('medical_exam', 'Medical examination'), ('report_of_compliance', 'Report of Compliance'), ('student_personnel_ratio', 'Student / personnel ratio')]:
        value = c.get(key, '')
        reason = c.get(key + '_reason', '') or c.get(key + '_remarks', '')
        rows.append([label, str(value) + (': ' + reason if reason else '')])
    table(rows, [160, 380])
    heading('PART 5. SIGNATORIES - NINE PHYSICAL SIGNATURE SLOTS')
    for start in (0, 3, 6):
        table([[f'{i + 1}. {slots[i][1]}\n\n________________________\n{slots[i][0]}\nDate: __________________' for i in range(start, start + 3)]])
    page(6)
    heading('PART 6. EVALUATION (SDS ONLY, AFTER ACTIVITY)')
    table([['[ ] Conducted', '[ ] Canceled'], ['Remarks:\n\n\n\n\n', 'Remarks:\n\n\n\n\n']])
    table([['Evaluated by: __________________________', 'Date: __________________']])
    heading('CONTROLLED COPY / VERIFICATION')
    table([['This copy has no electronic signatures. The final physically signed scan is retained privately by SDS. Verify approval status before relying on this revision.']])
    if verification_url:
        qr = QrCodeWidget(verification_url)
        x1, y1, x2, y2 = qr.getBounds()
        drawing = Drawing(100, 100, transform=[100 / (x2 - x1), 0, 0, 100 / (y2 - y1), 0, 0])
        drawing.add(qr)
        renderPDF.draw(drawing, canvas, 36, y - 110)
        canvas.setFont('Helvetica', 9)
        canvas.drawString(150, y - 50, 'Scan to verify identity, revision and approval status.')
    else:
        table([['DRAFT PREVIEW: no verification token issued until submission.']])
    canvas.save()
    return output.getvalue()
