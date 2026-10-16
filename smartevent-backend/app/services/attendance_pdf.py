"""Printable attendance sheet; generating it never records attendance."""
from html import escape
from io import BytesIO
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Table, TableStyle

# Reuse the application's font for Filipino names (including accented characters).
FONT_PATH = Path(__file__).resolve().parents[3] / "fonts" / "Lexend-Regular.ttf"
FONT = "AttendanceLexend" if FONT_PATH.is_file() else "Helvetica"
if FONT != "Helvetica" and FONT not in pdfmetrics.getRegisteredFontNames():
    pdfmetrics.registerFont(TTFont(FONT, str(FONT_PATH)))


def render_attendance(event, organization, destination, participants):
    output = BytesIO()
    width, height = A4
    margin, usable = 36, width - 72
    normal = ParagraphStyle("Attendance", fontName=FONT, fontSize=10, leading=14, splitLongWords=True)
    heading = ParagraphStyle("AttendanceTitle", parent=normal, fontSize=16, leading=21)
    small = ParagraphStyle("AttendanceSmall", parent=normal, fontSize=8, leading=11)
    metadata = [
        Paragraph("ATTENDANCE SHEET", small),
        Paragraph(escape(event.title), heading),
        Paragraph(escape(organization or "Organization not recorded"), normal),
        Paragraph(f"Activity date: {escape(str(event.event_date or 'Not recorded'))}", normal),
        Paragraph("Venue: " + escape(destination or "Not recorded"), normal),
        Paragraph("Sign beside your name to confirm your attendance.", small),
    ]
    heights = [paragraph.wrap(usable, height)[1] for paragraph in metadata]
    header_height = sum(heights) + 40

    def page_frame(canvas, doc):
        canvas.saveState()
        y = height - margin
        for paragraph, size in zip(metadata, heights):
            y -= size
            paragraph.drawOn(canvas, margin, y)
            y -= 4
        canvas.setFont(FONT, 8)
        canvas.setFillColor(colors.HexColor("#50645c"))
        canvas.drawString(margin, 22, "SMARTEVENT | Participant signature record")
        canvas.drawRightString(width - margin, 22, f"Page {doc.page}")
        canvas.restoreState()

    rows = [[Paragraph(value, small) for value in ["No.", "Student number", "Participant name", "Signature"]]]
    rows += [[str(index), Paragraph(escape(student.student_number), normal),
              Paragraph(escape(student.full_name), normal), ""]
             for index, student in enumerate(participants, 1)]
    table = Table(rows, colWidths=[30, 100, usable - 300, 170], repeatRows=1,
                  minRowHeights=[26] + [34] * len(participants))
    table.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (-1, -1), FONT), ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e9f0ec")),
        ("GRID", (0, 0), (-1, -1), .5, colors.HexColor("#83988e")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 7), ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    SimpleDocTemplate(output, pagesize=A4, leftMargin=margin, rightMargin=margin,
        topMargin=margin + header_height, bottomMargin=42,
        title="Attendance - " + event.title, author="SMARTEVENT").build(
        [table], onFirstPage=page_frame, onLaterPages=page_frame)
    return output.getvalue()
