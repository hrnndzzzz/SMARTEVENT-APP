"""The Word form the printout is made from: every value lands in its own cell."""
import re
import zipfile
from io import BytesIO

from docx import Document

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
