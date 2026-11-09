from time import monotonic

from starlette._utils import get_route_path
from starlette.responses import JSONResponse


PUBLIC_AUTH_PATHS = {
    "/auth/login", "/auth/register", "/auth/verify-otp", "/auth/resend-otp",
    "/auth/forgot-password", "/auth/reset-password",
}
# /auth/refresh is left out on purpose: its 384-bit key cannot be guessed, and a
# campus behind one address would otherwise be sent back to the sign-in screen.


class RequestSecurityMiddleware:
    def __init__(self, app, auth_rate_limits=None, max_body_bytes=12 * 1024 * 1024, max_auth_requests=30):
        self.app = app
        self.auth_rate_limits = auth_rate_limits if auth_rate_limits is not None else {}
        self.max_body_bytes = max_body_bytes
        self.max_auth_requests = max_auth_requests

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)

        async def secure_send(message):
            if message["type"] == "http.response.start":
                message["headers"] = [
                    (key, value) for key, value in message.get("headers", [])
                    if key not in {b"cache-control", b"x-content-type-options", b"referrer-policy"}
                ] + [
                    (b"cache-control", b"no-store"),
                    (b"x-content-type-options", b"nosniff"),
                    (b"referrer-policy", b"no-referrer"),
                ]
            await send(message)

        async def reject(status, detail, headers=None):
            await JSONResponse({"detail": detail}, status_code=status, headers=headers)(scope, receive, secure_send)

        if scope["method"] == "POST" and get_route_path(scope).rstrip("/") in PUBLIC_AUTH_PATHS:
            now = monotonic()
            address = (scope.get("client") or ("unknown",))[0]
            limits = self.auth_rate_limits
            if len(limits) >= 2000:
                for key, (start, _) in list(limits.items()):
                    if now - start >= 60:
                        del limits[key]
                if address not in limits and len(limits) >= 2000:
                    return await reject(429, "Too many authentication requests", {"Retry-After": "60"})
            start, count = limits.get(address, (now, 0))
            if now - start >= 60:
                start, count = now, 0
            if count >= self.max_auth_requests:
                return await reject(429, "Too many authentication requests", {"Retry-After": str(max(1, int(60 - now + start)))})
            # ponytail: per-worker IP limits; enforce aggregate limits at the deployment proxy.
            limits[address] = (start, count + 1)

        if scope["method"] in {"POST", "PUT", "PATCH", "DELETE"}:
            lengths = [value for key, value in scope["headers"] if key == b"content-length"]
            if lengths:
                try:
                    if len(lengths) != 1 or int(lengths[0]) < 0:
                        raise ValueError
                    if int(lengths[0]) > self.max_body_bytes:
                        return await reject(413, "Request body is too large")
                except ValueError:
                    return await reject(400, "Invalid Content-Length")
            messages, size = [], 0
            while True:
                message = await receive()
                if message["type"] == "http.disconnect":
                    return
                size += len(message.get("body", b""))
                if size > self.max_body_bytes:
                    return await reject(413, "Request body is too large")
                messages.append(message)
                if not message.get("more_body", False):
                    break
            iterator = iter(messages)
            original_receive = receive

            async def buffered_receive():
                return next(iterator, None) or await original_receive()

            receive = buffered_receive

        await self.app(scope, receive, secure_send)
