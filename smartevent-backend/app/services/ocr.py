"""
Turns receipt data into structured fields using Gemini — two entry
points, two different inputs:

  parse_receipt_text(raw_text)   — text-only. Flutter's on-device ML Kit
                                    already extracted the text; this just
                                    structures it. Used by
                                    POST /expenses/{id}/parse-receipt.

  parse_receipt_image(image_bytes) — multimodal. Sends the photo itself
                                    to Gemini Vision, which does OCR AND
                                    extraction in one call, including
                                    reading spatial layout that
                                    text-only OCR loses (which line is
                                    the total vs. a subtotal, etc.). Also
                                    returns itemized line items. Used by
                                    POST /expenses/scan-receipt, which
                                    runs BEFORE an Expense exists yet —
                                    "snap first, fill later": the officer
                                    scans, reviews/edits the extracted
                                    data in the app, then calls
                                    POST /expenses separately to actually
                                    save it.

Both paths are kept side by side on purpose (not one replacing the
other): parse_receipt_text still works if ML Kit already ran, e.g. for
low-connectivity cases where a smaller text payload matters more than
one round trip. parse_receipt_image is the primary path going forward.
"""

import json
import re
from datetime import date
from typing import Any

from google import genai
from google.genai import types
from pydantic import BaseModel, Field

from app.config import settings


class ReceiptTextExtraction(BaseModel):
    merchant: str | None = Field(default=None, description="The merchant or store name")
    date: str | None = Field(default=None, description="Transaction date in YYYY-MM-DD format")
    amount: float | None = Field(default=None, description="Grand total amount paid")


class ReceiptItemExtraction(BaseModel):
    name: str = Field(description="Name or description of the purchased item")
    amount: float = Field(description="Line amount or price")
    category: str = Field(
        default="consumable",
        description="'asset' for reusable equipment or 'consumable' for single-use supplies",
    )


class ReceiptImageExtraction(BaseModel):
    merchant: str | None = Field(default=None, description="The merchant or store name")
    date: str | None = Field(default=None, description="Transaction date in YYYY-MM-DD format")
    amount: float | None = Field(default=None, description="Grand total amount paid")
    items: list[ReceiptItemExtraction] = Field(
        default_factory=list,
        description="List of itemized lines",
    )


_PROMPT_TEMPLATE = """You are extracting structured data from OCR text scanned from a physical receipt. The OCR text may contain errors, extra whitespace, or misaligned lines - that is expected and not a problem.

Return a JSON object with:
- "merchant": the store/business name, usually near the top of the receipt, or null.
- "date": the transaction date converted to YYYY-MM-DD format, or null.
- "amount": the receipt grand TOTAL (not subtotal or tax line), or null.

OCR text:
---
{raw_text}
---"""


_VISION_PROMPT = """You are extracting structured data from a photo of a physical receipt. The image may be angled, have glare, or show a slightly crumpled receipt - that is expected and not a problem.

Extract:
- "merchant": the store/business name, usually near the top of the receipt, or null.
- "date": the transaction date converted to YYYY-MM-DD format, or null.
- "amount": the receipt grand TOTAL (not subtotal or tax line), or null.
- "items": array of itemized lines. For each item:
  - "name": item name
  - "amount": item price/total
  - "category": "asset" if reusable equipment (chairs, cables, tarps, speakers, tools) or "consumable" if consumable/supplies (food, drinks, paper, tape). If unclear, use "consumable"."""


class ReceiptParseError(Exception):
    """Raised when Gemini's response can't be parsed into the expected shape."""


def _clean_json_text(text: str) -> str:
    """Defensively strips markdown code fences if present."""
    cleaned = (text or "").strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:]
        cleaned = cleaned.strip()
    return cleaned


def _safe_parse_date(raw_date: Any) -> date | None:
    if not raw_date or not isinstance(raw_date, str):
        return None
    cleaned = raw_date.strip()
    try:
        return date.fromisoformat(cleaned)
    except (ValueError, TypeError):
        pass
    # Match YYYY-MM-DD or YYYY/MM/DD
    match = re.search(r"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})", cleaned)
    if match:
        try:
            return date(int(match.group(1)), int(match.group(2)), int(match.group(3)))
        except (ValueError, TypeError):
            pass
    # Match MM-DD-YYYY or DD-MM-YYYY
    match = re.search(r"(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})", cleaned)
    if match:
        try:
            p1, p2, yr = int(match.group(1)), int(match.group(2)), int(match.group(3))
            if p1 <= 12:
                return date(yr, p1, p2)
            return date(yr, p2, p1)
        except (ValueError, TypeError):
            pass
    return None


def _safe_parse_float(raw_amount: Any) -> float | None:
    if raw_amount is None:
        return None
    if isinstance(raw_amount, (int, float)):
        return float(raw_amount)
    if isinstance(raw_amount, str):
        cleaned = re.sub(r"[^\d.-]", "", raw_amount.replace(",", ""))
        try:
            return float(cleaned)
        except (ValueError, TypeError):
            return None
    return None


def parse_receipt_text(raw_text: str) -> dict:
    """
    Sends raw OCR text to Gemini and returns:
        {"merchant": str | None, "date": date | None, "amount": float | None}
    """
    if not settings.gemini_api_key:
        raise RuntimeError("GEMINI_API_KEY is not configured")

    client = genai.Client(api_key=settings.gemini_api_key)

    response = client.models.generate_content(
        model=settings.gemini_model,
        contents=_PROMPT_TEMPLATE.format(raw_text=raw_text),
        config=types.GenerateContentConfig(
            temperature=0,
            response_mime_type="application/json",
            response_schema=ReceiptTextExtraction,
        ),
    )

    text = _clean_json_text(response.text)

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ReceiptParseError(f"Gemini did not return valid JSON: {exc}") from exc

    if not isinstance(parsed, dict):
        raise ReceiptParseError("Gemini's response did not match the expected shape")

    raw_merchant = parsed.get("merchant")
    merchant = str(raw_merchant).strip() if raw_merchant is not None else None
    if merchant == "":
        merchant = None

    parsed_date = _safe_parse_date(parsed.get("date"))
    amount = _safe_parse_float(parsed.get("amount"))

    return {"merchant": merchant, "date": parsed_date, "amount": amount}


def parse_receipt_image(image_bytes: bytes, mime_type: str = "image/jpeg") -> dict:
    """
    Sends a receipt photo directly to Gemini Vision with structured output schema:
        {
            "merchant": str | None,
            "date": date | None,
            "amount": float | None,
            "items": [{"name": str, "amount": float, "category": "asset" | "consumable"}, ...]
        }
    """
    if not settings.gemini_api_key:
        raise RuntimeError("GEMINI_API_KEY is not configured")

    client = genai.Client(api_key=settings.gemini_api_key)

    response = client.models.generate_content(
        model=settings.gemini_model,
        contents=[
            types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
            _VISION_PROMPT,
        ],
        config=types.GenerateContentConfig(
            temperature=0,
            response_mime_type="application/json",
            response_schema=ReceiptImageExtraction,
        ),
    )

    text = _clean_json_text(response.text)

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ReceiptParseError(f"Gemini did not return valid JSON: {exc}") from exc

    if not isinstance(parsed, dict):
        raise ReceiptParseError("Gemini's response did not match the expected shape")

    raw_merchant = parsed.get("merchant")
    merchant = str(raw_merchant).strip() if raw_merchant is not None else None
    if merchant == "":
        merchant = None

    parsed_date = _safe_parse_date(parsed.get("date"))
    amount = _safe_parse_float(parsed.get("amount"))

    raw_items = parsed.get("items")
    if not isinstance(raw_items, list):
        raw_items = []

    items = []
    for raw_item in raw_items:
        if not isinstance(raw_item, dict):
            continue
        item_name = str(raw_item.get("name") or "").strip()
        if not item_name:
            continue
        item_amount = _safe_parse_float(raw_item.get("amount"))
        if item_amount is None:
            item_amount = 0.0

        raw_category = str(raw_item.get("category") or "").strip().lower()
        item_category = "asset" if raw_category == "asset" else "consumable"

        items.append({
            "name": item_name,
            "amount": item_amount,
            "category": item_category,
        })

    return {"merchant": merchant, "date": parsed_date, "amount": amount, "items": items}