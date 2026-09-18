---
name: backend-connection-setup
description: >-
  Use this skill when configuring the connection to a real Python backend, changing host IP, switching off mock mode, or troubleshooting network communication with the backend.
---

# Backend Connection Setup Runbook

Follow these steps to transition Sonic Pulse from offline mock mode to a live Python backend.

## Step 1: Configure Network Endpoint
Edit `lib/config/api_config.dart`:

```dart
class ApiConfig {
  // Set to false to send real HTTP requests to the backend:
  static const bool useMockResponses = false;

  // Set to your backend host address:
  // - For physical phone on same Wi-Fi: "http://<YOUR_LAN_IP>:5001" (e.g. http://192.168.1.100:5001)
  // - For USB ADB reverse tethering: "http://127.0.0.1:5001"
  // - For Android Emulator: "http://10.0.2.2:5001"
  static const String baseUrl = 'http://192.168.1.100:5001';
}
```

## Step 2: Enable USB Port Forwarding (Physical Phone via ADB)
If testing on a physical phone connected via USB cable without Wi-Fi LAN access:
```bash
adb reverse tcp:5001 tcp:5001
```
Then keep `baseUrl = 'http://127.0.0.1:5001'`.

## Step 3: Python Backend Requirements
The Python backend should expose a `POST /api/recognize` route accepting multipart form data:

```python
from fastapi import FastAPI, UploadFile, File
import uvicorn

app = FastAPI()

@app.post("/api/recognize")
async def recognize(file: UploadFile = File(...)):
    audio_bytes = await file.read()
    # Run model analysis...
    return {
        "id": "trk_100",
        "title": "Detected Track",
        "artist": "Artist",
        "key": "A Minor",
        "bpm": 120,
        "confidence": 0.95,
        "chords": ["Am", "F", "C", "G"],
        "mood": ["Energetic"],
        "camelot": "8A",
        "time_sig": "4/4"
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5001)
```

## Step 4: Verification
Test network reachability from the host:
```bash
curl -F "file=@/dev/null" http://127.0.0.1:5001/api/recognize
```
