"""Deterministic theory features derived from a chord-symbol sequence."""

import re
from typing import Any, Dict, Iterable, List, Optional, Tuple


ROOT_TO_PC = {
    "C": 0, "B#": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3,
    "E": 4, "Fb": 4, "E#": 5, "F": 5, "F#": 6, "Gb": 6, "G": 7,
    "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11, "Cb": 11,
}
PC_TO_NAME = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
MAJOR_SCALE = (0, 2, 4, 5, 7, 9, 11)
MINOR_SCALE = (0, 2, 3, 5, 7, 8, 10)
MAJOR_ROMANS = ("I", "ii", "iii", "IV", "V", "vi", "vii°")
MINOR_ROMANS = ("i", "ii°", "III", "iv", "v", "VI", "VII")

_CHORD_RE = re.compile(
    r"^(?P<root>[A-Ga-g](?:#|b)?)(?P<quality>.*?)(?:/(?P<bass>[A-Ga-g](?:#|b)?))?$"
)


class MusicTheoryEngine:
    """Turn imperfect tab chord labels into compact, model-friendly facts."""

    def build(self, song: Dict[str, Any]) -> Dict[str, Any]:
        raw_chords = song.get("chords") or []
        chords = [self.parse_chord(str(chord)) for chord in raw_chords]
        chords = [chord for chord in chords if chord is not None]
        supplied_key = self._parse_key(song.get("key"))
        inferred_key = supplied_key or self._infer_key(chords)

        structured: Dict[str, Any] = {
            "title": song.get("title"),
            "artist": song.get("artist"),
            "bpm": song.get("bpm"),
            "tempo": song.get("tempo"),
            "time_signature": song.get("time_signature"),
            "source_chords": [chord["symbol"] for chord in chords],
            "normalized_chords": chords,
            "chord_count": len(chords),
            "unique_chords": self._unique_symbols(chords),
            "quality_counts": self._quality_counts(chords),
            "likely_key": inferred_key["name"] if inferred_key else None,
            "key_confidence": inferred_key["confidence"] if inferred_key else 0,
            "roman_numerals": self._roman_numerals(chords, inferred_key),
            "progression_intervals": self._progression_intervals(chords),
            "functions": self._functions(chords, inferred_key),
        }
        return structured

    @staticmethod
    def parse_chord(symbol: str) -> Optional[Dict[str, Any]]:
        cleaned = symbol.strip().replace("♯", "#").replace("♭", "b")
        cleaned = cleaned.replace(":maj", "").replace(":min", "m")
        if not cleaned or cleaned.upper() in {"N", "N.C.", "NC", "♫̸"}:
            return None
        match = _CHORD_RE.match(cleaned)
        if not match:
            return None
        root = match.group("root")[0].upper() + match.group("root")[1:]
        root_pc = ROOT_TO_PC.get(root)
        if root_pc is None:
            return None
        quality_text = match.group("quality").lower()
        quality = "major"
        if "dim" in quality_text or "°" in quality_text:
            quality = "diminished"
        elif "aug" in quality_text or "+" in quality_text:
            quality = "augmented"
        elif "sus" in quality_text:
            quality = "suspended"
        elif "m" in quality_text and "maj" not in quality_text:
            quality = "minor"
        elif "7" in quality_text:
            quality = "dominant_seventh"
        return {
            "symbol": cleaned,
            "root": root,
            "root_pc": root_pc,
            "quality": quality,
            "bass": match.group("bass"),
            "extension": quality_text,
        }

    def _infer_key(self, chords: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        if not chords:
            return None
        candidates = []
        for mode, scale, romans in (
            ("major", MAJOR_SCALE, MAJOR_ROMANS),
            ("minor", MINOR_SCALE, MINOR_ROMANS),
        ):
            for tonic in range(12):
                score = 0.0
                for chord in chords:
                    degree = (chord["root_pc"] - tonic) % 12
                    if degree not in scale:
                        score -= 2
                        continue
                    index = scale.index(degree)
                    expected_minor = romans[index].islower()
                    if chord["quality"] == "minor" and expected_minor:
                        score += 3
                    elif chord["quality"] in ("major", "dominant_seventh") and not expected_minor:
                        score += 3
                    elif chord["quality"] == "diminished" and "°" in romans[index]:
                        score += 3
                    else:
                        score += 1
                candidates.append((score, tonic, mode))
        candidates.sort(reverse=True)
        score, tonic, mode = candidates[0]
        second_score = candidates[1][0] if len(candidates) > 1 else score
        confidence = round(max(0.0, min(1.0, (score - second_score + 1) / 6)), 2)
        return {
            "name": f"{PC_TO_NAME[tonic]} {'minor' if mode == 'minor' else 'major'}",
            "tonic_pc": tonic,
            "mode": mode,
            "scale": MINOR_SCALE if mode == "minor" else MAJOR_SCALE,
            "romans": MINOR_ROMANS if mode == "minor" else MAJOR_ROMANS,
            "confidence": confidence,
        }

    @staticmethod
    def _parse_key(value: Any) -> Optional[Dict[str, Any]]:
        if not isinstance(value, str) or not value.strip() or value.strip() == "—":
            return None
        match = re.match(r"^([A-Ga-g](?:#|b)?)\s*(major|minor|maj|min|m)?", value.strip(), re.I)
        if not match:
            return None
        root = match.group(1)[0].upper() + match.group(1)[1:]
        tonic = ROOT_TO_PC.get(root)
        if tonic is None:
            return None
        mode = "minor" if (match.group(2) or "").lower() in {"minor", "min", "m"} else "major"
        return {
            "name": f"{PC_TO_NAME[tonic]} {'minor' if mode == 'minor' else 'major'}",
            "tonic_pc": tonic,
            "mode": mode,
            "scale": MINOR_SCALE if mode == "minor" else MAJOR_SCALE,
            "romans": MINOR_ROMANS if mode == "minor" else MAJOR_ROMANS,
            "confidence": 1.0,
        }

    @staticmethod
    def _unique_symbols(chords: Iterable[Dict[str, Any]]) -> List[str]:
        result = []
        for chord in chords:
            if chord["symbol"] not in result:
                result.append(chord["symbol"])
        return result

    @staticmethod
    def _quality_counts(chords: Iterable[Dict[str, Any]]) -> Dict[str, int]:
        counts: Dict[str, int] = {}
        for chord in chords:
            quality = chord["quality"]
            counts[quality] = counts.get(quality, 0) + 1
        return counts

    @staticmethod
    def _roman_numerals(chords: List[Dict[str, Any]], key: Optional[Dict[str, Any]]) -> List[str]:
        if not key:
            return []
        result = []
        for chord in chords:
            degree = (chord["root_pc"] - key["tonic_pc"]) % 12
            if degree in key["scale"]:
                result.append(key["romans"][key["scale"].index(degree)])
            else:
                result.append("chromatic")
        return result

    @staticmethod
    def _progression_intervals(chords: List[Dict[str, Any]]) -> List[int]:
        return [
            (current["root_pc"] - previous["root_pc"]) % 12
            for previous, current in zip(chords, chords[1:])
        ]

    def _functions(self, chords: List[Dict[str, Any]], key: Optional[Dict[str, Any]]) -> List[str]:
        if not key:
            return []
        functions = []
        for roman in self._roman_numerals(chords, key):
            degree = roman.replace("°", "").lower()
            if degree in {"i", "i" if key["mode"] == "minor" else "i"}:
                functions.append("tonic")
            elif degree in {"iv", "ii"}:
                functions.append("predominant")
            elif degree in {"v", "vii"}:
                functions.append("dominant")
            else:
                functions.append("diatonic color")
        return functions
