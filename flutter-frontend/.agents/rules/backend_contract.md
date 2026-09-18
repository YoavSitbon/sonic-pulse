# Sonic Pulse — Backend API Contract & Communication Rules

## Endpoint: POST `/api/recognize`

Used by `RecognitionService` to submit an audio sample recorded from the phone microphone for analysis.

### HTTP Request
- **Method**: `POST`
- **Path**: `/api/recognize`
- **Content-Type**: `multipart/form-data`
- **Fields**:
  - `file`: (Binary audio stream, e.g., `.m4a` or `.wav`)
  - `timestamp`: (Optional, ISO-8601 string)

### HTTP Response (200 OK)
```json
{
  "id": "trk_001",
  "title": "Neon Horizons",
  "artist": "Aura Pulse",
  "album": "Synthwave Reverie",
  "cover_url": "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=500",
  "key": "B Minor",
  "bpm": 105,
  "confidence": 0.985,
  "chords": ["Bm", "G", "D", "A"],
  "mood": ["Atmospheric", "Nostalgic"],
  "camelot": "10A",
  "time_sig": "4/4"
}
```

### Response Fields Description
- `id` (String): Unique identifier for the track.
- `title` (String): Song title.
- `artist` (String): Artist or band name.
- `album` (String?): Album name.
- `cover_url` (String?): Optional image URL for album artwork.
- `key` (String): Musical key (e.g., "B Minor", "C Major", "F# Minor").
- `bpm` (int): Detected tempo in beats per minute.
- `confidence` (double): Recognition confidence value between `0.0` and `1.0`.
- `chords` (List<String>): Sequence of primary chords detected (e.g. `["Bm", "G", "D", "A"]`).
- `mood` (List<String>): Descriptive mood tags.
- `camelot` (String?): Camelot harmonic mixing key notation (e.g. "10A", "8B").
- `time_sig` (String?): Time signature (e.g. "4/4", "3/4", "6/8").

### Mock Fallback Mode
When `ApiConfig.useMockResponses == true`:
- Network requests are skipped.
- A synthetic `TrackResult` is generated with varied realistic songs and a simulated 2.5-second processing delay.
- Enables offline testing, UI styling, and automated agent verification.
