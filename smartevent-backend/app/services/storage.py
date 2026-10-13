"""
Prepares and uploads receipt photos to Supabase Storage.

Two responsibilities kept in one small module since they're always used
together in this app:
  1. prepare_image_for_upload - fixes EXIF rotation and downsizes large
     phone-camera photos before they go anywhere.
  2. upload_receipt_image - sends the processed bytes to Supabase
     Storage's REST API and returns a public URL.

Talks to Supabase's Storage REST API directly via httpx rather than the
supabase-py SDK, to keep dependencies minimal - this is the only thing
this app needs Supabase Storage for.
"""

import io
import uuid

import httpx
from PIL import Image, ImageOps

from app.config import settings


class StorageError(Exception):
    """Raised when the upload to Supabase Storage fails."""


def prepare_image_for_upload(file_bytes: bytes) -> tuple[bytes, str]:
    """
    Fixes EXIF rotation and downsizes large phone-camera photos before
    upload. Returns (processed_jpeg_bytes, "image/jpeg").

    Phone photos are often 3000x4000px+ and carry EXIF orientation data
    that most viewers respect but raw pixel data does not - without this
    step, some photos would show up sideways or upside-down wherever the
    URL gets displayed later. Downsizing keeps upload size (and later,
    OCR input size) reasonable with no visible quality loss for reading
    text on a receipt.
    """
    image = Image.open(io.BytesIO(file_bytes))
    image = ImageOps.exif_transpose(image)  # bakes rotation into pixels

    if image.mode != "RGB":
        image = image.convert("RGB")  # JPEG doesn't support alpha/palette modes

    max_dimension = 1800
    if max(image.size) > max_dimension:
        image.thumbnail((max_dimension, max_dimension), Image.LANCZOS)

    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=85)
    return buffer.getvalue(), "image/jpeg"


def upload_receipt_image(file_bytes: bytes, content_type: str) -> str:
    """
    Uploads image bytes to the configured Supabase Storage bucket and
    returns a public URL for the uploaded file.

    Each upload gets a random UUID filename - receipts aren't named
    after anything guessable, and collisions are effectively impossible.

    Raises:
        RuntimeError    if Supabase Storage isn't configured.
        StorageError    if the upload itself fails (bad response from
                        Supabase - wrong bucket name, expired key, etc).
    """
    if not settings.supabase_url or not settings.supabase_service_key:
        raise RuntimeError("Supabase Storage is not configured")

    object_path = f"{uuid.uuid4()}.jpg"

    upload_url = (
        f"{settings.supabase_url}/storage/v1/object/"
        f"{settings.supabase_receipts_bucket}/{object_path}"
    )

    response = httpx.post(
        upload_url,
        content=file_bytes,
        headers={
            "Authorization": f"Bearer {settings.supabase_service_key}",
            "Content-Type": content_type,
            "x-upsert": "false",
        },
        timeout=30.0,
    )

    if response.status_code not in (200, 201):
        raise StorageError(
            f"Supabase Storage upload failed ({response.status_code}): {response.text}"
        )

    return (
        f"{settings.supabase_url}/storage/v1/object/public/"
        f"{settings.supabase_receipts_bucket}/{object_path}"
    )