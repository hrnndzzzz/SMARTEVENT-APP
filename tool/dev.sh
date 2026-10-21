#!/usr/bin/env bash
#
# Start the backend and point the phone at it.
#
# The app's backend address is set on the device now (Settings → Backend),
# not baked into the APK, so changing networks no longer means rebuilding
# and reinstalling. This script does the other half: it starts the backend,
# works out which address the phone can actually reach it on, and bridges
# the USB cable when one is plugged in.
#
#   tool/dev.sh            start the backend and print the address
#   tool/dev.sh --install  also build and install a release APK
#
set -uo pipefail

BACKEND_DIR="${SMARTEVENT_BACKEND_DIR:-$HOME/backend-work/smartevent-backend}"
PORT="${SMARTEVENT_PORT:-8001}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER="${FLUTTER_BIN:-$HOME/development/flutter/bin/flutter}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
warn() { printf '\033[33m%s\033[0m\n' "$1"; }
fail() { printf '\033[31m%s\033[0m\n' "$1"; }

# --- backend ---------------------------------------------------------------

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  bold "Backend already listening on :$PORT"
else
  if [[ ! -d "$BACKEND_DIR" ]]; then
    fail "No backend at $BACKEND_DIR"
    echo "Set SMARTEVENT_BACKEND_DIR to where it lives."
    exit 1
  fi
  UVICORN="$BACKEND_DIR/.venv/bin/uvicorn"
  [[ -x "$UVICORN" ]] || UVICORN="uvicorn"
  bold "Starting backend on :$PORT"
  # 0.0.0.0, not 127.0.0.1: a phone on the same Wi-Fi has to be able to
  # reach it, and a loopback bind refuses everything that is not this Mac.
  (cd "$BACKEND_DIR" && nohup "$UVICORN" app.main:app --host 0.0.0.0 \
    --port "$PORT" </dev/null >/tmp/smartevent-backend.log 2>&1 &)
  for _ in $(seq 1 30); do
    sleep 1
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 && break
  done
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    bold "Started. Log: /tmp/smartevent-backend.log"
  else
    fail "Backend did not come up. Last lines:"
    tail -15 /tmp/smartevent-backend.log 2>/dev/null
    exit 1
  fi
fi

# --- how the phone can reach it -------------------------------------------

echo
bold "Addresses to try in the app (Settings → Backend)"

adb start-server </dev/null >/dev/null 2>&1
DEVICE="$(adb devices </dev/null 2>/dev/null | awk 'NR>1 && $2=="device" {print $1; exit}')"

if [[ -n "$DEVICE" ]]; then
  # A reverse tunnel is the one address that survives every network
  # change, because it never touches the network at all.
  if adb -s "$DEVICE" reverse tcp:"$PORT" tcp:"$PORT" </dev/null >/dev/null 2>&1; then
    echo "  127.0.0.1:$PORT   (over the USB cable — survives any Wi-Fi change)"
  else
    warn "  Cable present but the tunnel failed; use a LAN address below."
  fi
else
  warn "  No phone on USB, so no cable route."
fi

# Every IPv4 this Mac holds, minus loopback. The phone needs to be on the
# same network as whichever one you pick.
while read -r ip; do
  [[ -z "$ip" ]] && continue
  echo "  $ip:$PORT"
done < <(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2}')

echo
echo "Type one into Settings → Backend, then press Save and test."

# --- optional build --------------------------------------------------------

if [[ "${1:-}" == "--install" ]]; then
  if [[ -z "$DEVICE" ]]; then
    fail "Nothing to install to — no phone on USB."
    exit 1
  fi
  echo
  bold "Building release APK"
  # Release, not debug: 21MB against 182MB, which matters a great deal on
  # a cable that drops under sustained transfer.
  (cd "$APP_DIR" && "$FLUTTER" build apk --release \
    --target-platform android-arm64) || exit 1
  bold "Installing"
  adb -s "$DEVICE" install -r "$APP_DIR/build/app/outputs/flutter-apk/app-release.apk" \
    || { fail "Install failed. If it mentions signatures, uninstall first:"
         echo "  adb uninstall com.lcup.smartevent.smartevent"; exit 1; }
  adb -s "$DEVICE" shell monkey -p com.lcup.smartevent.smartevent \
    -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  bold "Installed and launched."
fi
