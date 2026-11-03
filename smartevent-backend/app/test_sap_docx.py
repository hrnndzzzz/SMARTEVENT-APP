"""The Word form the printout is made from: every value lands in its own cell."""
import re
import shutil
import subprocess
import threading
import time
import zipfile
from io import BytesIO
from pathlib import Path
from unittest.mock import Mock

import pytest
from docx import Document
from docx.oxml.ns import qn
from docx.text.paragraph import Paragraph as DocxParagraph
from pypdf import PdfReader
from reportlab.pdfgen.canvas import Canvas

from app.services import sap_pdf
from app.services.sap_pdf import fill_form
from app.test_sap import fixture_data


def cell_after(doc, label):
    for table in doc.tables:
        for row in table.rows:
            cells = list(dict.fromkeys(row.cells))
            for i, cell in enumerate(cells[:-1]):
                if cell.text.strip().startswith(label):
                    return cells[i + 1].text
    raise LookupError(label)


def docx_text(docx):
    xml = zipfile.ZipFile(BytesIO(docx)).read('word/document.xml').decode('utf8')
    return '\n'.join(''.join(re.findall(r'<w:t(?: [^>]*)?>([^<]*)</w:t>', p))
                     for p in re.findall(r'<w:p[ >].*?</w:p>', xml, re.S))


def test_long_rationale_and_program_flow_stay_in_their_cells():
    data = fixture_data()
    data['details']['rationale'] = ('Long rationale sentence. ' * 72)[:1800]
    data['collections']['program-flow'] = [{'start': '08:00', 'end': '09:00', 'activity': 'Opening'},
                                           {'start': '09:00', 'end': '11:00', 'activity': 'Seminar'}]
    doc = Document(BytesIO(fill_form(data)))
    assert cell_after(doc, 'Rationale:') == data['details']['rationale']
    assert cell_after(doc, 'Program Flow:') == '08:00 - 09:00  Opening\n09:00 - 11:00  Seminar'


def test_ticks_and_blanks():
    data = fixture_data()
    data['details'] |= {'modality': 'hybrid', 'school_year': '2026-2027',
                        'activity_types': ['Co-Curricular'], 'program_types': ['Team Building', 'Academic']}
    text = docx_text(fill_form(data))
    assert '(X) Hybrid' in text and 'S.Y. 2026-2027' in text
    assert 'Date of Proposal:' + str(data['details']['proposal_date']) in text
    assert '(X) College' in text and '(X) Co-Curricular' in text and '(X) Team Building' in text
    assert '(X) Others:Academic' in text
    assert '(X) Courage' in text and '(X) Community-Oriented' in text and '(  ) Humility' in text
    assert '(X) EGA 1:' in text and '(X) EGA 3:' in text and '(  ) EGA 2:' in text


def test_control_characters_are_dropped():
    data = fixture_data()
    data['details']['rationale'] = 'First\nSecond\x0bThird\x0c'
    assert cell_after(Document(BytesIO(fill_form(data))), 'Rationale:') == 'First\nSecondThird'


def test_empty_values_leave_the_form_blank():
    data = fixture_data()
    data['collections']['program-flow'] = []
    data['details']['attire'] = None
    doc = Document(BytesIO(fill_form(data)))
    assert cell_after(doc, 'Program Flow:') == ''
    assert cell_after(doc, 'Attire:') == ''


def cell_with(doc, text):
    return next(c for t in doc.tables for r in t.rows for c in r.cells if text in c.text)


def test_support_requests_fill_their_blanks():
    data = fixture_data()
    data['collections']['support-requests'] = [
        {'type': 'microphone', 'quantity': 3, 'specify': ''},
        {'type': 'room', 'quantity': 1, 'specify': 'AVR 2'},
        {'type': 'chairs', 'quantity': 40, 'specify': ''}, {'type': 'tables', 'quantity': 4, 'specify': ''},
        {'type': 'other', 'quantity': 1, 'specify': 'Extension cords'}]
    doc = Document(BytesIO(fill_form(data)))
    text = docx_text(fill_form(data))
    assert '(X) MICROPHONE [QTY.:3]' in text and 'ROOM/VENUE:AVR 2' in text
    chairs = cell_with(doc, 'CHAIRS AND TABLES')
    # Chairs and tables share one box, so each count says which it is.
    assert '(X) CHAIRS AND TABLES' in text and 'Chairs: 40' in chairs.text and 'Tables: 4' in chairs.text
    assert 'Extension cords' in cell_with(doc, 'OTHERS:').text


def test_clearance_reasons_classes_and_other_details_stay_on_the_form():
    data = fixture_data()
    data['details']['additional_information'] = 'BEGIN ' + 'x ' * 1990 + 'END'
    data['attachments'] = [{'file_name': 'roc.pdf'}]
    doc = Document(BytesIO(fill_form(data)))
    classes = cell_with(doc, 'Academic Class Interruption')
    assert '(X) Yes' in classes.text and 'Remarks:Excuse letters required' in classes.text
    assert 'Professor B' in classes.text and 'Provide letters to affected professors.' in classes.text
    consent = cell_with(doc, 'Consent Form')
    assert '(X) Not Applicable' in consent.text and 'Online activity' in consent.text
    assert 'Ratio:145:3' in cell_with(doc, 'Student-Personnel Ratio').text
    assert 'roc.pdf' in cell_with(doc, 'Attachments:').text
    assert data['details']['additional_information'] in docx_text(fill_form(data))


def test_signed_form_names_the_signer_and_holds_the_signature():
    review = {'overall_remarks': 'Looks complete', 'section_remarks': {}}
    doc = Document(BytesIO(fill_form(fixture_data(), review=review, signer_name='Ana Cruz', signed=True,
                                     signature_strokes=[[{'x': 0, 'y': 0}, {'x': 1, 'y': 1}]])))
    cell = cell_with(doc, 'SDS Coordinator')
    assert 'Ana Cruz' in cell.text and 'Le-Mairre' not in cell.text
    assert 'Looks complete' not in cell.text
    assert len(cell._tc.xpath('.//pic:pic')) == 1


REMARKS = {'overall_remarks': 'Approved with notes.', 'section_remarks': {
    'activity_details': 'Move the start.', 'budget': 'Attach a quotation.', 'support_requests': 'Book the sound system.',
    'additional_information': 'Name the guests.', 'clearance': 'No medical exam.', 'other': 'Bring the letter.'}}


def comments_by_anchor(docx):
    """(author, text, text of the paragraph the comment is anchored in) for every comment on the form."""
    doc = Document(BytesIO(docx))
    anchors = {int(el.get(qn('w:id'))): DocxParagraph(el.getparent(), doc._body).text
               for el in doc.element.body.iter(qn('w:commentRangeStart'))}
    return [(c.author, c.text, anchors[c.comment_id]) for c in doc.comments]


@pytest.mark.parametrize('signed', [False, True])
def test_remarks_never_sit_under_the_signature(signed):
    docx = fill_form(fixture_data(), review=REMARKS, signed=signed, signer_name='Ana Cruz')
    text = cell_with(Document(BytesIO(docx)), 'SDS Coordinator').text
    assert not any(r in text for r in ['Approved', 'Move the start', 'Bring the letter'])
    assert 'word/comments.xml' not in zipfile.ZipFile(BytesIO(docx)).namelist()


def test_each_remark_becomes_a_comment_beside_its_part():
    found = comments_by_anchor(fill_form(fixture_data(), review=REMARKS, comments=True))
    assert {a for a, _, _ in found} == {'SDS Office'}
    assert [(t, p.split(':')[0] if p.startswith('Part') else p) for _, t, p in found] == [
        ('Overall: Approved with notes.', 'Part 4'), ('Move the start.', 'Activity Title:'), ('Attach a quotation.', 'Budget:'),
        ('Book the sound system.', 'Part 2'), ('Name the guests.', 'Part 3'), ('No medical exam.', 'Part 4'),
        ('Bring the letter.', 'Part 4')]


def test_a_remark_without_its_anchor_falls_back_to_the_part_4_heading(monkeypatch):
    monkeypatch.setitem(sap_pdf._ANCHORS, 'budget', 'No such label:')
    found = comments_by_anchor(fill_form(fixture_data(), review=REMARKS, comments=True))
    assert next(p for _, t, p in found if t == 'Attach a quotation.').startswith('Part 4')


def test_no_remarks_means_no_comments():
    for review in (None, {'overall_remarks': '', 'section_remarks': {}}):
        docx = fill_form(fixture_data(), review=review, comments=True)
        assert 'word/comments.xml' not in zipfile.ZipFile(BytesIO(docx)).namelist()


def test_markup_export_asks_word_for_comments(monkeypatch):
    run = Mock(side_effect=lambda cmd, **kw: Path(re.search(r"ExportAsFixedFormat\('([^']+)'", cmd[-1]).group(1)).write_bytes(b'%PDF'))
    monkeypatch.setattr(sap_pdf.subprocess, 'run', run)
    sap_pdf.docx_to_pdf(b'..', markup=True)
    script = run.call_args.args[0][-1]
    assert ", 17, $false, 0, 0, 1, 1, 7)" in script and 'ShowComments = $true' in script and 'Markup = 2' in script
    sap_pdf.docx_to_pdf(b'..')
    assert 'ExportAsFixedFormat' in run.call_args.args[0][-1] and ', 7)' not in run.call_args.args[0][-1]


@pytest.mark.parametrize('review,comments,markup', [(None, True, False), ({'overall_remarks': '', 'section_remarks': {}}, True, False),
                                                    ({'overall_remarks': 'Fine', 'section_remarks': {}}, True, True),
                                                    ({'overall_remarks': 'Fine', 'section_remarks': {}}, False, False)])
def test_the_markup_export_is_for_commented_forms_with_remarks_only(monkeypatch, review, comments, markup):
    seen = []
    monkeypatch.setattr(sap_pdf, 'docx_to_pdf', lambda docx, *, markup=False: seen.append(markup) or b'')
    monkeypatch.setattr(sap_pdf, '_stamp', lambda *args, **kwargs: b'')
    sap_pdf.render_proposal(fixture_data(), 1, review=review, comments=comments)
    assert seen == [markup]


def test_unsigned_form_keeps_the_printed_coordinator():
    cell = cell_with(Document(BytesIO(fill_form(fixture_data()))), 'SDS Coordinator')
    assert 'Le-Mairre' in cell.text and not cell._tc.xpath('.//pic:pic')


def test_budget_breakdown_is_the_only_thing_after_the_form():
    data = fixture_data()
    data['collections']['budget-items'] = [{'particulars': f'Line {i}', 'amount': '1.00'} for i in range(16)]
    last = Document(BytesIO(fill_form(data))).tables[-1]
    assert last.rows[0].cells[0].text == 'Particulars' and len(last.rows) == 17
    assert [c.text for c in last.rows[16].cells] == ['Line 15', '1', '', '1.00']


def test_conversion_failure_raises(monkeypatch):
    monkeypatch.setattr(sap_pdf.subprocess, 'run', Mock(side_effect=subprocess.TimeoutExpired('powershell', 120)))
    with pytest.raises(RuntimeError, match='Could not convert'):
        sap_pdf.docx_to_pdf(b'docx')


def test_conversions_run_one_at_a_time(monkeypatch):
    live = peak = 0

    def fake_run(*args, **kwargs):
        nonlocal live, peak
        live += 1
        peak = max(peak, live)
        time.sleep(0.05)
        live -= 1
        raise subprocess.CalledProcessError(1, 'powershell')

    monkeypatch.setattr(sap_pdf.subprocess, 'run', fake_run)
    threads = [threading.Thread(target=pytest.raises, args=(RuntimeError, sap_pdf.docx_to_pdf, b'x')) for _ in range(3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert peak == 1


def test_signed_form_prints_no_blank_page():
    # The signature makes Part 5 taller; the template's trailing empty lines must not spill onto a page of their own.
    pdf = sap_pdf.render_proposal(fixture_data(), 1, review={'overall_remarks': '', 'section_remarks': {}},
                                  signer_name='SDS Staff', signed=True,
                                  signature_strokes=[[{'x': 0.1, 'y': 0.2}, {'x': 0.8, 'y': 0.7}]])
    for number, page in enumerate(PdfReader(BytesIO(pdf)).pages, 1):
        content = [line for line in page.extract_text().splitlines()
                   if line.strip() and not line.strip().isdigit()
                   and not line.startswith(('SAP revision', 'Verify:', 'SAS-SDS-FO-020', 'SIGNED AND APPROVED'))]
        assert content, f'page {number} is blank'


def test_each_line_is_its_own_paragraph():
    # A line break inside a justified cell stretches the line before it right across the cell.
    data = fixture_data()
    data['details']['rationale'] = 'First paragraph\nSecond paragraph'
    data['collections']['program-flow'] = [{'start': '08:00', 'end': '09:00', 'activity': 'Opening'},
                                           {'start': '09:00', 'end': '11:00', 'activity': 'Seminar'}]
    doc = Document(BytesIO(fill_form(data)))
    for label in ('Rationale:', 'Program Flow:'):
        cell = sap_pdf._value_cell(doc.tables[2], label)
        assert len(cell.paragraphs) == 2 and not cell._tc.xpath('.//w:br'), label


def test_stamp_sits_between_the_form_body_and_words_footer():
    # Word's body ends at y=72 (1in margin); its footer rule sits near y=57.
    blank = BytesIO()
    canvas = Canvas(blank, pagesize=(612, 792))
    canvas.showPage()
    canvas.save()
    pdf = sap_pdf._stamp(blank.getvalue(), 1, 'https://example.org/sap/verify/x', False)
    found = []
    PdfReader(BytesIO(pdf)).pages[0].extract_text(
        visitor_text=lambda text, cm, tm, *_: text.strip() and found.append((text, tm[5] * cm[3] + cm[5])))
    assert found and all(60 <= y <= 66 for _, y in found), found


def test_signatories_stay_on_one_page():
    # The paper starts Part 5 on a page of its own; long Parts 1-4 must not split the signatory table.
    data = fixture_data()
    data['details']['rationale'] = ('This seminar builds awareness of responsible digital citizenship '
                                    'and ethical hacking among students. ' * 20)[:1800]
    data['details']['objectives'] = 'Understand digital safety. Practise safe password habits. Recognise phishing attempts.'
    data['collections']['program-flow'] = [
        {'start': '08:00:00', 'end': '08:15:00', 'activity': 'Opening prayer and national anthem'},
        {'start': '08:15:00', 'end': '08:30:00', 'activity': 'Welcome remarks'},
        {'start': '08:30:00', 'end': '09:30:00', 'activity': 'Talk 1: Threats students face online'},
        {'start': '09:30:00', 'end': '10:15:00', 'activity': 'Talk 2: Ethical hacking as a career'},
        {'start': '10:15:00', 'end': '10:45:00', 'activity': 'Open forum'},
        {'start': '10:45:00', 'end': '11:00:00', 'activity': 'Closing remarks and photo'}]
    data['collections']['support-requests'] = [{'type': 'microphone', 'quantity': 2, 'specify': ''},
                                               {'type': 'projector', 'quantity': 1, 'specify': ''}]
    pages = [page.extract_text() for page in PdfReader(BytesIO(sap_pdf.render_proposal(data, 1))).pages]
    signatories = next(text for text in pages if 'Prepared by:' in text)
    assert 'University President' in signatories


def test_a_timeout_kills_the_word_it_started(monkeypatch):
    # Word runs outside powershell's process tree, so killing powershell on a timeout leaves Word running.
    killed = []

    def fake_run(args, **kwargs):
        if args[0] == 'taskkill':
            killed.append(args[args.index('/PID') + 1])
            return Mock(returncode=0)
        Path(re.search(r"Set-Content '([^']+)'", args[-1]).group(1)).write_text('4242')
        raise subprocess.TimeoutExpired('powershell', 60)

    monkeypatch.setattr(sap_pdf.subprocess, 'run', fake_run)
    with pytest.raises(RuntimeError, match='Could not convert'):
        sap_pdf.docx_to_pdf(b'docx')
    assert killed == ['4242']


def test_a_held_temp_file_does_not_hide_the_conversion_error(monkeypatch):
    # A hung Word keeps form.docx open; failing to clean up the folder must not replace the real error.
    held = []

    def fake_run(args, **kwargs):
        if args[0] == 'taskkill':
            return Mock(returncode=0)
        held.append(open(re.search(r"Open\('([^']+)'", args[-1]).group(1), 'rb'))
        raise subprocess.TimeoutExpired('powershell', 60)

    monkeypatch.setattr(sap_pdf.subprocess, 'run', fake_run)
    try:
        with pytest.raises(RuntimeError, match='Could not convert'):
            sap_pdf.docx_to_pdf(b'docx')
    finally:
        for handle in held:
            handle.close()
            shutil.rmtree(Path(handle.name).parent, ignore_errors=True)


def test_words_own_error_reaches_the_message(monkeypatch):
    error = subprocess.CalledProcessError(1, 'powershell', stderr=b'New-Object : Class not registered')
    monkeypatch.setattr(sap_pdf.subprocess, 'run', Mock(side_effect=error))
    with pytest.raises(RuntimeError, match='Class not registered'):
        sap_pdf.docx_to_pdf(b'docx')


def test_a_busy_printer_fails_fast_instead_of_queueing(monkeypatch):
    monkeypatch.setattr(sap_pdf, '_WORD_WAIT', 0.05)
    monkeypatch.setattr(sap_pdf.subprocess, 'run', Mock(side_effect=subprocess.CalledProcessError(1, 'powershell')))
    outcome = []
    sap_pdf._WORD_LOCK.acquire()
    try:
        worker = threading.Thread(target=lambda: outcome.append(
            pytest.raises(RuntimeError, sap_pdf.docx_to_pdf, b'x').value))
        worker.start()
        worker.join(timeout=2)
        finished = not worker.is_alive()
    finally:
        sap_pdf._WORD_LOCK.release()
        worker.join()
    assert finished and 'busy' in str(outcome[0])
