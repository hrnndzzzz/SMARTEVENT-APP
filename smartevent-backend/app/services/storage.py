import io
import uuid
import warnings
from urllib.parse import quote, unquote, urlsplit

import httpx
from PIL import Image, ImageOps

from app.config import settings


MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_IMAGE_PIXELS = 20_000_000
SIGNED_URL_SECONDS = 300


class StorageError(Exception):
    pass


def prepare_image_for_upload(file_bytes: bytes) -> tuple[bytes, str]:
    if not file_bytes or len(file_bytes) > MAX_UPLOAD_BYTES:
        raise ValueError("Image must be between 1 byte and 10MB")
    with warnings.catch_warnings():
        warnings.simplefilter("error", Image.DecompressionBombWarning)
        with Image.open(io.BytesIO(file_bytes), formats=["JPEG", "PNG", "WEBP"]) as source:
            if source.width * source.height > MAX_IMAGE_PIXELS:
                raise ValueError("Image resolution is too large")
            source.verify()
        with Image.open(io.BytesIO(file_bytes), formats=["JPEG", "PNG", "WEBP"]) as source:
            image = ImageOps.exif_transpose(source).convert("RGB")
            image.thumbnail((1800, 1800), Image.Resampling.LANCZOS)
            buffer = io.BytesIO()
            image.save(buffer, format="JPEG", quality=85)
    return buffer.getvalue(), "image/jpeg"


def storage_object(url: str, expected_bucket: str | None = None) -> tuple[str, str] | None:
    if not settings.supabase_url:
        return None
    base, parts = urlsplit(settings.supabase_url.rstrip("/")), urlsplit(str(url))
    if (parts.scheme, parts.netloc) != (base.scheme, base.netloc):
        return None
    prefix = base.path.rstrip("/") + "/storage/v1/object/"
    if not parts.path.startswith(prefix):
        return None
    segments = unquote(parts.path[len(prefix):]).split("/")
    if segments[0] in {"public", "authenticated", "sign"}:
        segments = segments[1:]
    allowed = {settings.supabase_receipts_bucket, settings.supabase_proposal_letters_bucket}
    if len(segments) < 2 or segments[0] not in allowed or (expected_bucket and segments[0] != expected_bucket):
        raise ValueError("Invalid storage bucket")
    if any(not segment or segment in {".", ".."} or "\\" in segment for segment in segments):
        raise ValueError("Invalid storage object path")
    return segments[0], "/".join(segments[1:])


def canonical_file_url(url: str, expected_bucket: str | None = None) -> str:
    obj = storage_object(url, expected_bucket)
    if obj is None:
        return str(url)
    bucket, path = obj
    return f"{settings.supabase_url.rstrip('/')}/storage/v1/object/{quote(bucket, safe='')}/{quote(path, safe='/')}"


def _request(method: str, path: str, **kwargs) -> httpx.Response:
    if not settings.supabase_url or not settings.supabase_service_key:
        raise RuntimeError("Supabase Storage is not configured")
    headers = {
        "Authorization": f"Bearer {settings.supabase_service_key}",
        "apikey": settings.supabase_service_key,
        **kwargs.pop("headers", {}),
    }
    try:
        response = httpx.request(method, f"{settings.supabase_url.rstrip('/')}/storage/v1/{path}",
                                 headers=headers, timeout=30.0, follow_redirects=False, **kwargs)
        response.raise_for_status()
        return response
    except httpx.HTTPError:
        raise StorageError("File storage is temporarily unavailable") from None


def signed_file_url(url: str | None, expected_bucket: str | None = None) -> str | None:
    if url is None:
        return None
    obj = storage_object(url, expected_bucket)
    if obj is None:
        return str(url)
    bucket, path = obj
    response = _request("POST", f"object/sign/{quote(bucket, safe='')}/{quote(path, safe='/')}",
                        json={"expiresIn": SIGNED_URL_SECONDS})
    try:
        signed = response.json()["signedURL"]
        if not isinstance(signed, str) or not signed.startswith("/object/sign/"):
            raise ValueError
        result = f"{settings.supabase_url.rstrip('/')}/storage/v1{signed}"
        if storage_object(result, bucket) != obj or not urlsplit(result).query:
            raise ValueError
        return result
    except (ValueError, KeyError, TypeError):
        raise StorageError("File access is temporarily unavailable") from None


def upload_file(file_bytes: bytes, content_type: str, bucket: str, extension: str,
                owner_id: uuid.UUID, organization_id: uuid.UUID) -> str:
    if not file_bytes or len(file_bytes) > MAX_UPLOAD_BYTES:
        raise ValueError("File must be between 1 byte and 10MB")
    if bucket not in {settings.supabase_receipts_bucket, settings.supabase_proposal_letters_bucket}:
        raise ValueError("Invalid storage bucket")
    if extension not in {"jpg", "png", "pdf"}:
        raise ValueError("Invalid file extension")
    response = _request("GET", f"bucket/{quote(bucket, safe='')}")
    try:
        if response.json().get("public") is not False:
            raise StorageError("The file storage bucket must be private")
    except (ValueError, AttributeError):
        raise StorageError("File storage configuration is unavailable") from None
    path = f"{uuid.UUID(str(organization_id))}/{uuid.UUID(str(owner_id))}/{uuid.uuid4()}.{extension}"
    _request("POST", f"object/{quote(bucket, safe='')}/{path}", content=file_bytes,
             headers={"Content-Type": content_type, "x-upsert": "false", "Cache-Control": "no-store"})
    return f"{settings.supabase_url.rstrip('/')}/storage/v1/object/{quote(bucket, safe='')}/{path}"


def upload_receipt_image(file_bytes: bytes, content_type: str, owner_id: uuid.UUID, organization_id: uuid.UUID) -> str:
    return upload_file(file_bytes, content_type, settings.supabase_receipts_bucket, "jpg", owner_id, organization_id)


def upload_proposal_letter(file_bytes: bytes, content_type: str, extension: str,
                           owner_id: uuid.UUID, organization_id: uuid.UUID) -> str:
    return upload_file(file_bytes, content_type, settings.supabase_proposal_letters_bucket, extension, owner_id, organization_id)
