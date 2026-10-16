"""Generate a synthetic multi-page attendance sample for PDF layout QA."""
from datetime import date
from pathlib import Path
from types import SimpleNamespace
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services.attendance_pdf import render_attendance

event = SimpleNamespace(title="Museum Learning Visit - Philippine History and Cultural Heritage", event_date=date(2026, 10, 4))
students = [SimpleNamespace(student_number=f"2026-{index:04d}", full_name=f"Participant {index:02d} Dela Cruz") for index in range(1, 54)]
students[0].full_name = "María Peña & Juan <Dela Cruz>"
students[1].full_name = "A deliberately long participant name to verify readable wrapping inside the name column"
target = Path(__file__).resolve().parents[1] / "output/pdf/attendance-sample.pdf"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(render_attendance(event, "Sample Student Organization", "Local Heritage Museum, Bulacan", students))
print(target)
