# Run SMARTEVENT: backend and phone app

A step-by-step guide for running the backend on a Windows laptop and the app on
an Android phone connected by USB. Every command is for **Command Prompt**
(`cmd`) and can be copied as is.

The app file is in this folder: **[SMARTEVENT-arm64-v8a.apk](SMARTEVENT-arm64-v8a.apk)**
(a release build of `develop`, for 64-bit Android phones, which is nearly all
phones from the last few years).

---

## 1. Before the first run (once per laptop)

You need:

- **Python 3** (the backend has been run on 3.14): check with `python --version`.
- **Android platform-tools (adb)**: installed with Android Studio, at
  `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`.
- **The project**, cloned somewhere. The commands below assume
  `C:\SMARTEVENT-APP`; replace that path with yours.
- **`smartevent-backend\.env`**: copy `.env.example` to `.env` and fill in the
  values from a teammate (`DATABASE_URL`, `JWT_SECRET_KEY` and the rest; see
  `smartevent-backend\SETUP.md`). Never commit it.

Create the backend's virtual environment and install its packages:

```cmd
cd /d "C:\SMARTEVENT-APP\smartevent-backend"
python -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
```

---

## 2. Get the latest code

```cmd
cd /d "C:\SMARTEVENT-APP"
git checkout develop
git pull origin develop
```

If `requirements.txt` changed since your last run, run the `pip install` line
from step 1 again.

---

## 3. Start the backend

Open a **new** Command Prompt window and paste:

```cmd
cd /d "C:\SMARTEVENT-APP\smartevent-backend"
.venv\Scripts\python.exe -m uvicorn app.main:app --port 8000 --reload
```

Wait for `Application startup complete.` Then open
**http://127.0.0.1:8000/docs** in a browser: the API page means it is working.

Leave this window open while you use the app. Press `Ctrl+C` in it to stop the
backend.

---

## 4. Connect the phone

1. On the phone, turn on **Developer options → USB debugging**.
2. Plug the phone into the laptop and tap **Allow** on the "Allow USB
   debugging?" prompt.
3. In a second Command Prompt window, paste:

```cmd
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" devices
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" reverse tcp:8000 tcp:8000
```

The first line should list your phone as `device`. The second makes the
phone's `127.0.0.1:8000` reach the laptop's backend over the USB cable, which
is the address the app uses by default.

Run the `reverse` line again whenever you unplug and replug the phone.

---

## 5. Install the app

With the phone still connected, paste:

```cmd
cd /d "C:\SMARTEVENT-APP"
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" install -r downloads\SMARTEVENT-arm64-v8a.apk
```

`Success` means it is installed. `-r` replaces an older SMARTEVENT and keeps
its data.

**Without a cable:** copy `SMARTEVENT-arm64-v8a.apk` to the phone (or download
it from this folder on GitHub), open it, and allow installing from that source
when Android asks. Without the USB tunnel the app cannot reach `127.0.0.1`, so:

1. Start the backend with `--host 0.0.0.0` added to the uvicorn line in step 3.
2. In the app's **Settings**, set the server address to the laptop's address on
   the same Wi-Fi, for example `http://192.168.1.20:8000` (find it with
   `ipconfig`, under "IPv4 Address").

---

## 6. Every time after that

1. Command Prompt window 1: start the backend (step 3).
2. Command Prompt window 2: `adb reverse tcp:8000 tcp:8000` (step 4).
3. Open SMARTEVENT on the phone.

---

## Problems

| What you see | What to do |
|---|---|
| `adb devices` lists nothing, or `unauthorized` | Replug the cable and tap **Allow** on the phone; check USB debugging is on. |
| The app says it cannot reach the backend | Check the backend window is still running, then run the `adb reverse` line again. |
| `No module named uvicorn` | Run the `pip install` line from step 1. |
| The backend window shows a database connection error | Check the laptop's internet connection and `DATABASE_URL` in `.env`. |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | The phone has a SMARTEVENT signed with a different key. Uninstall it on the phone first (this deletes the app's local data), then install again. |
| `INSTALL_FAILED_NO_MATCHING_ABIS` (older 32-bit phone) | Build its file with `flutter build apk --release --split-per-abi` and install `build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk`. |
