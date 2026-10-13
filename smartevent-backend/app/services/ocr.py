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
from datetime import date

from google import genai
from google.genai import types

from app.config import settings

_PROMPT_TEMPLATE = """You are extracting structured data from OCR text scanned from a physical receipt. The OCR text may contain errors, extra whitespace, or misaligned lines - that is expected and not a problem.

Return ONLY a JSON object with exactly these three keys and nothing else (no markdown fences, no explanation, no extra keys):
{{
  "merchant": string or null,
  "date": string in YYYY-MM-DD format or null,
  "amount": number or null
}}

Rules:
- "merchant" is the store/business name, usually near the top of the receipt.
- "date" is the transaction date, converted to YYYY-MM-DD.
- "amount" is the receipt's grand TOTAL - not the subtotal, not an individual line item, not a tax line.
- If a field cannot be confidently determined, use null for that field. Do not guess.

OCR text:
---
{raw_text}
---"""


class ReceiptParseError(Exception):
    """Raised when Gemini's response can't be parsed into the expected shape."""


def parse_receipt_text(raw_text: str) -> dict:
    """
    Sends raw OCR text to Gemini and returns:
        {"merchant": str | None, "date": date | None, "amount": float | None}

    Raises:
        RuntimeError        if GEMINI_API_KEY isn't configured.
        ReceiptParseError   if Gemini's response isn't valid JSON in the
                            expected shape.
        Exception           (from the Gemini SDK) on network/auth/API
                            failures - left unwrapped so the caller can
                            decide how to report it.
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
        ),
    )

    text = (response.text or "").strip()

    # Defensive: strip markdown fences if the model adds them anyway,
    # despite response_mime_type="application/json". Cheap insurance
    # against a format drift breaking every request.
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
        text = text.strip()

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ReceiptParseError(f"Gemini did not return valid JSON: {exc}") from exc

    if not isinstance(parsed, dict) or set(parsed.keys()) - {"merchant", "date", "amount"}:
        raise ReceiptParseError("Gemini's response did not match the expected shape")

    merchant = parsed.get("merchant")
    if merchant is not None and not isinstance(merchant, str):
        raise ReceiptParseError("'merchant' must be a string or null")

    raw_date = parsed.get("date")
    parsed_date = None
    if raw_date is not None:
        try:
            parsed_date = date.fromisoformat(raw_date)
        except (TypeError, ValueError) as exc:
            raise ReceiptParseError(
                f"'date' was not in YYYY-MM-DD format: {raw_date!r}"
            ) from exc

    amount = parsed.get("amount")
    if amount is not None:
        try:
            amount = float(amount)
        except (TypeError, ValueError) as exc:
            raise ReceiptParseError(f"'amount' was not a number: {amount!r}") from exc

    return {"merchant": merchant, "date": parsed_date, "amount": amount}


_VISION_PROMPT = """You are extracting structured data from a photo of a physical receipt. The image may be angled, have glare, or show a slightly crumpled receipt - that is expected and not a problem.

Return ONLY a JSON object with exactly these four keys and nothing else (no markdown fences, no explanation, no extra keys):
{
  "merchant": string or null,
  "date": string in YYYY-MM-DD format or null,
  "amount": number or null,
  "items": array of objects, or empty array if no line items are readable
}

Each object in "items" must have exactly these three keys:
{
  "name": string,
  "amount": number,
  "category": "asset" or "consumable"
}

Rules:
- "merchant" is the store/business name, usually near the top of the receipt.
- "date" is the transaction date, converted to YYYY-MM-DD.
- "amount" is the receipt's grand TOTAL - not the subtotal, not an individual line item, not a tax line.
- For each line item, classify "category" as:
    "asset" - a physical, reusable, trackable item an organization would keep in inventory
              (e.g. extension cord, tarpaulin, speaker, chairs, tools, equipment)
    "consumable" - something used up / not meaningfully tracked as standing inventory
              (e.g. food, drinks, printing paper, tape, single-use supplies, fuel)
  If genuinely unclear, default to "consumable" - inventory should only gain items
  Gemini is confident are actually reusable trackable assets.
- If a field cannot be confidently determined, use null (or an empty array for items).
  Do not guess."""


def parse_receipt_image(image_bytes: bytes, mime_type: str = "image/jpeg") -> dict:
    """
    Sends a receipt photo directly to Gemini Vision (one multimodal
    call does OCR + extraction + per-item asset/consumable
    classification together) and returns:
        {
            "merchant": str | None,
            "date": date | None,
            "amount": float | None,
            "items": [{"name": str, "amount": float, "category": "asset" | "consumable"}, ...]
        }

    This does NOT save anything or create an Expense — it's a pure
    parse function. The caller (POST /expenses/scan-receipt) decides
    what to do with the result; the officer reviews/edits it in the app
    before a separate POST /expenses call actually creates the record.

    Raises the same exception types as parse_receipt_text, for the same
    reasons — see that function's docstring.
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
        ),
    )

    text = (response.text or "").strip()

    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
        text = text.strip()

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ReceiptParseError(f"Gemini did not return valid JSON: {exc}") from exc

    expected_keys = {"merchant", "date", "amount", "items"}
    if not isinstance(parsed, dict) or set(parsed.keys()) - expected_keys:
        raise ReceiptParseError("Gemini's response did not match the expected shape")

    merchant = parsed.get("merchant")
    if merchant is not None and not isinstance(merchant, str):
        raise ReceiptParseError("'merchant' must be a string or null")

    raw_date = parsed.get("date")
    parsed_date = None
    if raw_date is not None:
        try:
            parsed_date = date.fromisoformat(raw_date)
        except (TypeError, ValueError) as exc:
            raise ReceiptParseError(
                f"'date' was not in YYYY-MM-DD format: {raw_date!r}"
            ) from exc

    amount = parsed.get("amount")
    if amount is not None:
        try:
            amount = float(amount)
        except (TypeError, ValueError) as exc:
            raise ReceiptParseError(f"'amount' was not a number: {amount!r}") from exc

    raw_items = parsed.get("items", [])
    if not isinstance(raw_items, list):
        raise ReceiptParseError("'items' must be a list")

    items = []
    for raw_item in raw_items:
        if not isinstance(raw_item, dict):
            raise ReceiptParseError("each item must be an object")
        item_name = raw_item.get("name")
        item_amount = raw_item.get("amount")
        item_category = raw_item.get("category")

        if not isinstance(item_name, str) or not item_name.strip():
            raise ReceiptParseError(f"item 'name' must be a non-empty string, got {item_name!r}")
        try:
            item_amount = float(item_amount)
        except (TypeError, ValueError) as exc:
            raise ReceiptParseError(f"item 'amount' was not a number: {item_amount!r}") from exc
        if item_category not in ("asset", "consumable"):
            raise ReceiptParseError(
                f"item 'category' must be 'asset' or 'consumable', got {item_category!r}"
            )

        items.append({"name": item_name, "amount": item_amount, "category": item_category})

    return {"merchant": merchant, "date": parsed_date, "amount": amount, "items": items}