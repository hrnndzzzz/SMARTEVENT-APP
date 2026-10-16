"""Shared academic-year validation for request bodies and report filters."""
import re


def validate_school_year(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{4}", value):
        raise ValueError("school_year must use YYYY-YYYY format")
    start, end = map(int, value.split("-"))
    if start < 1900 or end != start + 1:
        raise ValueError("school_year must contain consecutive years starting at 1900 or later")
    return value
