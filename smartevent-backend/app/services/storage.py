"""
Prepares and uploads files to Supabase Storage — receipt photos and,
now, proposal letter documents, sharing one underlying upload function
against different buckets.

Talks to Supabase's Storage REST API directly via httpx rather than the
supabase-py SDK, to keep dependencies minimal.
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


def upload_file(file_bytes: bytes, content_type: str, bucket: str, extension: str = "jpg") -> str:
    """
    Uploads bytes to the given Supabase Storage bucket and returns a
    public URL. Each upload gets a random UUID filename.

    Raises:
        RuntimeError    if Supabase Storage isn't configured.
        StorageError    if the upload itself fails (bad response from
                        Supabase — wrong bucket name, expired key, etc).
    """
    if not settings.supabase_url or not settings.supabase_service_key:
        raise RuntimeError("Supabase Storage is not configured")

    object_path = f"{uuid.uuid4()}.{extension}"
    upload_url = f"{settings.supabase_url}/storage/v1/object/{bucket}/{object_path}"

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

    return f"{settings.supabase_url}/storage/v1/object/public/{bucket}/{object_path}"


def upload_receipt_image(file_bytes: bytes, content_type: str) -> str:
    """Thin wrapper: upload_file targeted at the receipts bucket."""
    return upload_file(file_bytes, content_type, settings.supabase_receipts_bucket, extension="jpg")


def upload_proposal_letter(file_bytes: bytes, content_type: str, extension: str) -> str:
    """Thin wrapper: upload_file targeted at the proposal-letters bucket."""
    return upload_file(
        file_bytes, content_type, settings.supabase_proposal_letters_bucket, extension=extension
    )
