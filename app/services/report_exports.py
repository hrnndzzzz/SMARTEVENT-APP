"""Safe CSV, printable HTML, and PDF rendering of scoped report data."""
import csv
from html import escape
from io import BytesIO, StringIO
from fastapi.responses import Response
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle


def _text(value):
    return "" if value is None else str(value)


def render_export(title, sections, format, filename):
    """Sections are (heading, column labels, rows); all user-controlled text is escaped."""
    headers = {"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"}
    if format == "csv":
        output = StringIO(newline="")
        writer = csv.writer(output)
        def safe(value):
            text = _text(value)
            # Excel/Sheets may execute formula-looking strings, even inside CSV quotes.
            if isinstance(value, str) and (text.lstrip().startswith(("=", "+", "-", "@")) or text.startswith(("\t", "\r", "\n"))):
                return "'" + text
            return text
        writer.writerow([title])
        for heading, columns, rows in sections:
            writer.writerow([])
            writer.writerow([heading])
            writer.writerow(columns)
            for row in rows:
                writer.writerow([safe(value) for value in row])
        content = ("\ufeff" + output.getvalue()).encode("utf-8")
        media_type = "text/csv"
    elif format == "html":
        tables = []
        for heading, columns, rows in sections:
            cells = "".join("<th>" + escape(_text(c)) + "</th>" for c in columns)
            body = "".join("<tr>" + "".join("<td>" + escape(_text(v)) + "</td>" for v in row) + "</tr>" for row in rows)
            tables.append(f"<section><h2>{escape(heading)}</h2><table><thead><tr>{cells}</tr></thead><tbody>{body}</tbody></table></section>")
        content = ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
                   f'<title>{escape(title)}</title><style>'
                   'body{font:12px Arial,sans-serif;color:#17324d;margin:24px}table{border-collapse:collapse;width:100%;margin-bottom:24px}'
                   'th,td{border:1px solid #ccc;padding:6px;text-align:left;overflow-wrap:anywhere}thead{display:table-header-group}'
                   '@media print{.print-help{display:none}body{margin:0}tr{break-inside:avoid}}@page{size:A4 landscape;margin:12mm}'
                   '</style></head><body>' + f'<h1>{escape(title)}</h1>'
                   '<p class="print-help">Use your browser Print command (Ctrl+P) to print or save as PDF.</p>'
                   + ''.join(tables) + '</body></html>')
        media_type = "text/html"
        headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"
    else:
        output = BytesIO()
        styles = getSampleStyleSheet()
        story = [Paragraph(escape(title), styles["Title"])]
        for heading, columns, rows in sections:
            story.extend([Spacer(1, 12), Paragraph(escape(heading), styles["Heading2"])])
            data = [[Paragraph(escape(_text(v)), styles["Normal"]) for v in row] for row in [columns, *rows]]
            table = Table(data, colWidths=[770 / len(columns)] * len(columns), repeatRows=1)
            table.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#eaf0f4")),
                                      ("GRID", (0, 0), (-1, -1), .4, colors.lightgrey),
                                      ("VALIGN", (0, 0), (-1, -1), "TOP")]))
            story.append(table)
        SimpleDocTemplate(output, pagesize=landscape(A4), leftMargin=36, rightMargin=36,
                          title=title, author="SMARTEVENT").build(story)
        content = output.getvalue()
        media_type = "application/pdf"
    disposition = "inline" if format == "html" else "attachment"
    headers["Content-Disposition"] = f'{disposition}; filename="{filename}.{format}"'
    return Response(content=content, media_type=media_type, headers=headers)
