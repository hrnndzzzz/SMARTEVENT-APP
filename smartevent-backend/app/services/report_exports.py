"""Safe CSV, printable HTML, and PDF rendering of scoped report data.

A report is a title, a few lines saying what it covers (meta), headline
figures, charts, and tables. PDF and print-ready put the figures and charts
first and start the tables on a new page; CSV carries the figures and tables
only, since a CSV cannot hold a chart.
"""
import csv
import re
from decimal import Decimal
from html import escape
from io import BytesIO, StringIO
from typing import NamedTuple

from fastapi.responses import Response
from reportlab.graphics import renderSVG
from reportlab.graphics.charts.barcharts import VerticalBarChart
from reportlab.graphics.charts.legends import Legend
from reportlab.graphics.charts.linecharts import HorizontalLineChart
from reportlab.graphics.charts.piecharts import Pie
from reportlab.graphics.shapes import Drawing, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_RIGHT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.platypus import KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

# The app's own chart colours, so a printed chart looks like the one on screen.
BRAND, BRAND_TINT, ORANGE, MINT, CORAL = "#4D96FF", "#D2E5FF", "#FF8A3D", "#6BCB77", "#FF5964"
ACCENTS = [BRAND, ORANGE, "#FFD93D", MINT, "#B07BFF", "#3FC8C0"]
INK, MUTED, LINE, HEAD = "#1A1A1A", "#5B6472", "#E2E8F0", "#EAF0F4"

CHART_W, CHART_H = 360, 220
PAGE_W = 770  # landscape A4 less the margins


class Chart(NamedTuple):
    """One chart. series is [(name, values, colour)]; a pie uses the first."""
    title: str
    kind: str  # "bar", "line" or "pie"
    labels: list
    series: list
    # Bars in the last series drawn coral, such as events over budget.
    alert: tuple = ()


def pretty(value):
    """registration_fees -> Registration fees."""
    return re.sub(r"_+", " ", _text(value)).strip().capitalize()


def income_source_section(report):
    return ("Income by source (excludes pending/rejected receipt reviews)",
            ["Type", "Source", "Count", "Income (PHP)"],
            [[pretty(s.source_type), s.source, s.income_count, s.total_income] for s in report.income_by_source])


def financial_sections(report):
    sections = []
    if report.previous:
        p = report.previous
        sections.append(("Previous period", ["Window", "Income (PHP)", "Expenses (PHP)", "Balance (PHP)"],
                         [[" ".join(_text(v) for v in (p.start_date, p.end_date, p.school_year, p.semester) if v),
                           p.total_income, p.total_expenses, p.net_balance]]))
    sections += [
        ("Events (budget and spent to date cover the whole event, not only this period)",
         ["Event", "Status", "School year", "Semester", "Allocated (PHP)", "Spent to date (PHP)",
          "Variance (PHP)", "Income (PHP)", "Expenses (PHP)", "Balance (PHP)"],
         [[e.title, pretty(e.status), e.school_year, e.semester, e.allocated_budget, e.spent_to_date,
           round(e.allocated_budget - e.spent_to_date, 2), e.total_income, e.total_expenses, e.net_balance]
          for e in report.events]),
        ("Spending by category", ["Category", "Count", "Expenses (PHP)"],
         [[c.category_name, c.expense_count, c.total_expenses] for c in report.expenses_by_category]),
        income_source_section(report),
        ("Ledger", ["Date", "Type", "Event", "Category / source", "Description", "Amount (PHP)", "Counted"],
         [[r.occurred_on, pretty(r.kind), r.event_title or ("General fund" if r.kind == "income" else "No event"),
           r.label, r.description,
           r.amount if r.kind == "income" else -r.amount, "yes" if r.counted else "withheld"]
          for r in report.ledger]),
    ]
    return sections


def _text(value):
    return "" if value is None else str(value)


def _is_money(value):
    return isinstance(value, (float, Decimal)) and not isinstance(value, bool)


def _shown(value, money=False):
    """How a value reads in PDF and HTML: amounts grouped, to the centavo."""
    if money and isinstance(value, (int, float, Decimal)) and not isinstance(value, bool):
        return f"{value:,.2f}"
    return _text(value)


def _figure_text(value):
    """A headline figure: money gets its currency, counts and text stay as they are."""
    return f"PHP {value:,.2f}" if _is_money(value) else _text(value)


def _plain(value):
    """How a value goes into CSV: numbers stay numbers a spreadsheet can read."""
    return f"{value:.2f}" if _is_money(value) else _text(value)


def _money_columns(columns):
    return [index for index, column in enumerate(columns) if "(PHP)" in _text(column)]


def _short(label, size=18):
    label = _text(label)
    return label if len(label) <= size else label[: size - 1] + "…"


def _compact(value):
    value = float(value)
    if abs(value) >= 1_000_000:
        return f"{value / 1_000_000:.1f}M"
    if abs(value) >= 1000:
        return f"{value / 1000:.0f}k" if abs(value) >= 10_000 else f"{value / 1000:.1f}k"
    return f"{value:.0f}"


def _has_data(chart):
    return bool(chart.labels) and any(float(v or 0) > 0 for _, values, _ in chart.series for v in values)


def _drawing(chart, titled=True):
    """The chart as a reportlab drawing: drawn into the PDF, and turned into SVG for HTML."""
    drawing = Drawing(CHART_W, CHART_H)
    if titled:  # HTML captions it instead, in a font the browser has
        drawing.add(String(4, CHART_H - 14, chart.title, fontName="Helvetica-Bold", fontSize=11, fillColor=colors.HexColor(INK)))
    names = [(colors.HexColor(colour), name) for name, _, colour in chart.series]

    if chart.kind == "pie":
        _, values, _ = chart.series[0]
        pairs = [(label, float(v)) for label, v in zip(chart.labels, values) if float(v or 0) > 0]
        total = sum(v for _, v in pairs)
        pie = Pie()
        pie.x, pie.y, pie.width, pie.height = 14, 22, 150, 150
        pie.data = [v for _, v in pairs]
        pie.labels = None
        pie.slices.strokeColor = colors.HexColor(INK)
        pie.slices.strokeWidth = 1
        for index in range(len(pairs)):
            pie.slices[index].fillColor = colors.HexColor(ACCENTS[index % len(ACCENTS)])
        drawing.add(pie)
        names = [(colors.HexColor(ACCENTS[i % len(ACCENTS)]), f"{_short(label, 22)}  {v / total:.0%}")
                 for i, (label, v) in enumerate(pairs)]
        legend_x, legend_y = 186, 160
    else:
        plot = VerticalBarChart() if chart.kind == "bar" else HorizontalLineChart()
        plot.x, plot.y, plot.width, plot.height = 42, 58, CHART_W - 56, CHART_H - 96
        plot.data = [[float(v or 0) for v in values] for _, values, _ in chart.series]
        labels = [_short(label, 14) for label in chart.labels]
        if len(labels) > 12:  # a label on every day of a month is unreadable
            step = -(-len(labels) // 8)
            labels = [label if index % step == 0 else "" for index, label in enumerate(labels)]
        plot.categoryAxis.categoryNames = labels
        plot.categoryAxis.labels.fontSize = 7
        plot.categoryAxis.labels.fontName = "Helvetica"
        plot.categoryAxis.labels.angle = 30 if chart.kind == "bar" and len(labels) > 3 else 0
        plot.categoryAxis.labels.boxAnchor = "ne" if plot.categoryAxis.labels.angle else "n"
        plot.valueAxis.valueMin = 0
        plot.valueAxis.labels.fontSize = 7
        plot.valueAxis.labels.fontName = "Helvetica"
        plot.valueAxis.labelTextFormat = _compact
        plot.valueAxis.gridStrokeColor = colors.HexColor(LINE)
        plot.valueAxis.visibleGrid = True
        if chart.kind == "bar":
            plot.groupSpacing = 8
            plot.barSpacing = 2
            plot.bars.strokeColor = colors.HexColor(INK)
            plot.bars.strokeWidth = 0.8
            for index, (_, _, colour) in enumerate(chart.series):
                plot.bars[index].fillColor = colors.HexColor(colour)
            for index in chart.alert:
                plot.bars[(len(chart.series) - 1, index)].fillColor = colors.HexColor(CORAL)
            if chart.alert:
                names.append((colors.HexColor(CORAL), "Over budget"))
        else:
            for index, (_, _, colour) in enumerate(chart.series):
                plot.lines[index].strokeColor = colors.HexColor(colour)
                plot.lines[index].strokeWidth = 2
        drawing.add(plot)
        legend_x, legend_y = 42, 12

    legend = Legend()
    legend.x, legend.y = legend_x, legend_y
    legend.alignment = "right"
    legend.fontSize = 8
    legend.fontName = "Helvetica"
    legend.columnMaximum = 8 if chart.kind == "pie" else 1
    legend.boxAnchor = "nw" if chart.kind == "pie" else "sw"
    legend.dx = legend.dy = 7
    legend.deltax = 70
    legend.strokeColor = colors.HexColor(INK)
    legend.colorNamePairs = names
    drawing.add(legend)
    return drawing


def _svg(chart, index):
    """The chart as inline SVG: no prolog, and a clip id of its own so charts on one page cannot share one."""
    text = renderSVG.drawToString(_drawing(chart, titled=False))
    text = text[text.find("<svg"):]
    return text.replace('id="clip"', f'id="clip{index}"').replace("url(#clip)", f"url(#clip{index})")


def _csv(title, sections, meta, figures):
    output = StringIO(newline="")
    writer = csv.writer(output)

    def safe(value):
        text = _plain(value)
        if isinstance(value, str) and (text.lstrip().startswith(("=", "+", "-", "@")) or text.startswith(("\t", "\r", "\n"))):
            return "'" + text
        return text

    writer.writerow([safe(title)])
    for line in meta:
        writer.writerow([safe(line)])
    if figures:
        writer.writerow([])
        writer.writerow(["Summary"])
        writer.writerow(["Figure", "Value"])
        for label, value in figures:
            # The PDF and HTML say "PHP" beside the amount; here it goes in the label.
            writer.writerow([safe(f"{label} (PHP)" if _is_money(value) else label), safe(value)])
    for heading, columns, rows in sections:
        writer.writerow([])
        writer.writerow([safe(heading)])
        writer.writerow([safe(column) for column in columns])
        for row in rows:
            writer.writerow([safe(value) for value in row])
    return ("﻿" + output.getvalue()).encode("utf-8")


def _html(title, sections, meta, figures, charts):
    cards = "".join(f'<div class="figure"><span>{escape(_text(label))}</span><b>{escape(_figure_text(value))}</b></div>'
                    for label, value in figures)
    chart_part = ""
    if charts:
        art = "".join(f"<figure><figcaption>{escape(chart.title)}</figcaption>{_svg(chart, index)}</figure>"
                      for index, chart in enumerate(charts))
        chart_part = f'<section class="charts"><h2>Charts</h2><div class="grid">{art}</div></section>'
    tables = []
    for heading, columns, rows in sections:
        money = set(_money_columns(columns))
        cells = "".join(f'<th{" class=num" if i in money else ""}>{escape(_text(c))}</th>' for i, c in enumerate(columns))
        body = "".join("<tr>" + "".join(f'<td{" class=num" if i in money else ""}>{escape(_shown(v, i in money))}</td>'
                                        for i, v in enumerate(row)) + "</tr>" for row in rows)
        tables.append(f'<section><h2>{escape(heading)}</h2><div class="wide"><table><thead><tr>{cells}</tr></thead>'
                      f"<tbody>{body}</tbody></table></div></section>")
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light">'
            f'<title>{escape(title)}</title><style>'
            # A document: white on any device, as it is on paper.
            f':root{{color-scheme:light}}body{{font:12px Arial,sans-serif;color:{INK};background:#fff;margin:24px}}h1{{margin:0 0 4px}}.meta{{margin:0;color:{MUTED}}}'
            '.figures{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:18px 0}'
            f'.figure{{border:1.5px solid {INK};border-radius:8px;padding:10px}}.figure span{{display:block;color:{MUTED};font-size:11px}}'
            '.figure b{display:block;font-size:16px;margin-top:4px}'
            '.charts .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px}'
            f'.charts figure{{margin:0;border:1px solid {LINE};border-radius:8px;padding:8px}}.charts svg{{width:100%;height:auto}}'
            '.charts figcaption{font-weight:bold;margin-bottom:4px}.charts svg text{font-family:Arial,Helvetica,sans-serif!important}'
            # A wide table scrolls in its own box on a phone rather than crushing its text columns.
            '.wide{overflow-x:auto;margin-bottom:24px}table{border-collapse:collapse;width:100%}'
            f'th,td{{border:1px solid #ccc;padding:6px;text-align:left;overflow-wrap:break-word}}th{{background:{HEAD}}}'
            'tbody tr:nth-child(even){background:#f7f9fb}.num{text-align:right;white-space:nowrap}thead{display:table-header-group}'
            '@media print{.print-help{display:none}body{margin:0}.wide{overflow:visible}tr,figure{break-inside:avoid}.charts{break-after:page}}'
            '@page{size:A4 landscape;margin:12mm}'
            f'</style></head><body><h1>{escape(title)}</h1>'
            + "".join(f'<p class="meta">{escape(_text(line))}</p>' for line in meta)
            + '<p class="print-help">Use your browser Print command (Ctrl+P) to print or save as PDF.</p>'
            + (f'<div class="figures">{cards}</div>' if cards else "")
            + chart_part + "".join(tables) + "</body></html>").encode("utf-8")


def _widths(columns, rows):
    """Columns sized to what they hold, within limits, filling the page."""
    sizes = []
    for index, column in enumerate(columns):
        longest = max([len(_text(column))] + [len(_shown(row[index], True)) for row in rows[:200] if index < len(row)])
        sizes.append(min(max(longest, 7) + 2, 42))
    scale = PAGE_W / sum(sizes)
    return [size * scale for size in sizes]


def _pdf(title, sections, meta, figures, charts):
    output = BytesIO()
    styles = getSampleStyleSheet()
    cell = ParagraphStyle("cell", parent=styles["Normal"], fontSize=8, leading=10)
    number = ParagraphStyle("number", parent=cell, alignment=TA_RIGHT)
    head = ParagraphStyle("head", parent=cell, fontName="Helvetica-Bold")
    head_number = ParagraphStyle("head_number", parent=head, alignment=TA_RIGHT)
    small = ParagraphStyle("small", parent=styles["Normal"], fontSize=9, textColor=colors.HexColor(MUTED))
    label = ParagraphStyle("label", parent=small, fontSize=8)
    big = ParagraphStyle("big", parent=styles["Normal"], fontName="Helvetica-Bold", fontSize=13, leading=16)

    story = [Paragraph(escape(title), styles["Title"])]
    story += [Paragraph(escape(_text(line)), small) for line in meta]
    if figures:
        boxes = [[Paragraph(escape(_text(name)), label), Paragraph(escape(_figure_text(value)), big)] for name, value in figures]
        per_row = 4
        grid = [boxes[i:i + per_row] for i in range(0, len(boxes), per_row)]
        grid[-1] += [""] * (per_row - len(grid[-1]))
        table = Table(grid, colWidths=[PAGE_W / per_row] * per_row)
        table.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0, colors.white),
                                   ("INNERGRID", (0, 0), (-1, -1), 6, colors.white),
                                   ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#F4F6F8")),
                                   ("VALIGN", (0, 0), (-1, -1), "TOP"),
                                   ("TOPPADDING", (0, 0), (-1, -1), 8), ("BOTTOMPADDING", (0, 0), (-1, -1), 8)]))
        story += [Spacer(1, 14), table]
    if charts:
        drawings = [_drawing(chart) for chart in charts]
        pairs = [drawings[i:i + 2] + [""] * (2 - len(drawings[i:i + 2])) for i in range(0, len(drawings), 2)]
        story += [Spacer(1, 14), Paragraph("Charts", styles["Heading2"])]
        story += [KeepTogether(Table([pair], colWidths=[PAGE_W / 2] * 2)) for pair in pairs]
    if sections and (charts or figures):
        story.append(PageBreak())  # the tables start on a page of their own
    for heading, columns, rows in sections:
        money = set(_money_columns(columns))
        data = [[Paragraph(escape(_text(c)), head_number if i in money else head) for i, c in enumerate(columns)]]
        data += [[Paragraph(escape(_shown(v, i in money)), number if i in money else cell) for i, v in enumerate(row)]
                 for row in rows]
        table = Table(data, colWidths=_widths(columns, rows), repeatRows=1)
        table.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), colors.HexColor(HEAD)),
                                   ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F7F9FB")]),
                                   ("GRID", (0, 0), (-1, -1), .4, colors.lightgrey),
                                   ("VALIGN", (0, 0), (-1, -1), "TOP")]))
        story += [Spacer(1, 12), Paragraph(escape(heading), styles["Heading2"]), table]

    def footer(canvas, document):
        canvas.saveState()
        canvas.setFont("Helvetica", 8)
        canvas.setFillColor(colors.HexColor(MUTED))
        canvas.drawString(36, 20, title)
        canvas.drawRightString(document.pagesize[0] - 36, 20, f"Page {document.page}")
        canvas.restoreState()

    SimpleDocTemplate(output, pagesize=landscape(A4), leftMargin=36, rightMargin=36, bottomMargin=40,
                      title=title, author="SMARTEVENT").build(story, onFirstPage=footer, onLaterPages=footer)
    return output.getvalue()


def render_export(title, sections, format, filename, *, meta=(), figures=(), charts=()):
    """Sections are (heading, column labels, rows); all user-controlled text is escaped.

    meta is lines saying what the report covers, figures (label, value)
    headline pairs, and charts Chart tuples; charts with nothing to draw
    are left out.
    """
    charts = [chart for chart in charts if _has_data(chart)]
    headers = {"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"}
    if format == "csv":
        content, media_type = _csv(title, sections, meta, figures), "text/csv"
    elif format == "html":
        content, media_type = _html(title, sections, meta, figures, charts), "text/html"
        headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"
    else:
        content, media_type = _pdf(title, sections, meta, figures, charts), "application/pdf"
    disposition = "inline" if format == "html" else "attachment"
    headers["Content-Disposition"] = f'{disposition}; filename="{filename}.{format}"'
    return Response(content=content, media_type=media_type, headers=headers)

