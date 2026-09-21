"""
Time signature detection utilities.

This module provides functions for detecting time signatures from beat patterns.
"""

from typing import Dict, List, Optional, Tuple

import numpy as np
from utils.logging import log_debug


def detect_time_signature_from_pattern(pattern: List[int]) -> Optional[int]:
    """
    Detect time signature from a beat pattern.

    Args:
        pattern: List of beat numbers (e.g., [1, 2, 3, 1, 2, 3, ...] or [3, 1, 2, 3, 1, 2, 3, ...] for pickup beats)

    Returns:
        int: Detected time signature (beats per measure) or None if not detected
    """
    if len(pattern) < 6:
        return None

    # Try different cycle lengths from 2 to 12
    for cycle_len in range(2, 13):
        if len(pattern) >= cycle_len * 2:
            # Try different starting offsets to handle irregular beginnings and pickup beats
            for start_offset in range(min(5, len(pattern) - cycle_len * 2)):
                offset_pattern = pattern[start_offset:]

                if len(offset_pattern) >= cycle_len * 2:
                    # Check if the pattern repeats
                    first_cycle = offset_pattern[:cycle_len]
                    second_cycle = offset_pattern[cycle_len:cycle_len*2]

                    # Check if it's a valid beat pattern (starts with 1 and increments)
                    if (first_cycle == second_cycle and
                        first_cycle[0] == 1 and
                        first_cycle == list(range(1, cycle_len + 1))):

                        # Verify with a third cycle if available
                        if len(offset_pattern) >= cycle_len * 3:
                            third_cycle = offset_pattern[cycle_len*2:cycle_len*3]
                            if first_cycle == third_cycle:
                                log_debug(f"Detected {cycle_len}/4 time signature from pattern at offset {start_offset}: {first_cycle}")
                                return cycle_len
                        else:
                            log_debug(f"Detected {cycle_len}/4 time signature from pattern at offset {start_offset}: {first_cycle}")
                            return cycle_len

    # Special case: Handle pickup beat patterns like [3, 1, 2, 3, 1, 2, 3, ...] for 3/4 time
    # Look for patterns where the first beat is the final beat of a cycle, followed by a regular cycle
    for cycle_len in range(2, 13):
        if len(pattern) >= cycle_len + 2:  # Need at least one pickup + one full cycle
            # Check if pattern starts with the final beat of the cycle, then continues with regular cycle
            if pattern[0] == cycle_len:  # First beat is the final beat number
                # Check if the rest follows the regular pattern [1, 2, 3, ..., cycle_len]
                regular_pattern = pattern[1:cycle_len+1]
                expected_pattern = list(range(1, cycle_len + 1))

                if regular_pattern == expected_pattern:
                    # Verify the pattern repeats
                    if len(pattern) >= cycle_len * 2 + 1:
                        next_cycle = pattern[cycle_len+1:cycle_len*2+1]
                        if next_cycle == expected_pattern:
                            log_debug(f"Detected {cycle_len}/4 time signature from pickup pattern: pickup={pattern[0]}, cycle={expected_pattern}")
                            return cycle_len

    return None


def infer_time_signature(
    beat_times: np.ndarray,
    audio: np.ndarray,
    sample_rate: int,
) -> Tuple[str, float, Dict[str, List[float]]]:
    """Estimate the meter from beat spacing and accents in the audio.

    Beat trackers generally identify beat positions, not the meter.  This
    function scores common meters using the relative onset strength at each
    beat.  It is intentionally conservative: the confidence value lets
    callers distinguish a useful estimate from the 4/4 fallback case.

    Returns ``(time_signature, confidence, downbeat_candidates)``.
    ``downbeat_candidates`` contains the beat positions at the start of each
    estimated bar for every candidate meter.
    """
    beats = np.asarray(beat_times, dtype=float)
    candidates = ((2, 4), (3, 4), (4, 4), (6, 8), (9, 8), (12, 8))
    candidate_downbeats = {
        f"{numerator}/{denominator}": beats[::numerator].tolist()
        for numerator, denominator in candidates
    }

    if len(beats) < 12 or sample_rate <= 0 or audio.size == 0:
        return "4/4", 0.0, candidate_downbeats

    try:
        # Use a lightweight onset/energy proxy instead of importing
        # librosa.onset here.  Some deployments use a Numba cache that makes
        # importing that optional module fail even though beat tracking works.
        signal = np.asarray(audio, dtype=float)
        flux = np.abs(np.diff(signal, prepend=signal[0]))
        smoothing_window = max(1, int(sample_rate * 0.025))
        smoothed_flux = np.convolve(
            flux,
            np.ones(smoothing_window, dtype=float) / smoothing_window,
            mode="same",
        )
        beat_strength = []
        beat_interval = float(np.median(np.diff(beats)))
        half_window = max(1, int(sample_rate * beat_interval * 0.2))
        for beat in beats:
            center = int(round(beat * sample_rate))
            start = max(0, center - half_window)
            end = min(len(smoothed_flux), center + half_window + 1)
            beat_strength.append(float(np.max(smoothed_flux[start:end])))
        beat_strength = np.asarray(beat_strength, dtype=float)
        spread = float(np.std(beat_strength))
        if spread < 1e-6:
            return "4/4", 0.0, candidate_downbeats
        beat_strength = (beat_strength - np.mean(beat_strength)) / spread

        scores = []
        for numerator, denominator in candidates:
            # Compound meters usually accent each dotted-quarter group;
            # simple meters primarily accent the first beat of the bar.
            if denominator == 8:
                accent_positions = {0: 1.0}
                for position in range(3, numerator, 3):
                    accent_positions[position] = 0.65
            else:
                accent_positions = {0: 1.0}

            phase_scores = []
            for phase in range(numerator):
                values = []
                for index in range(phase, len(beat_strength) - numerator, numerator):
                    bar = beat_strength[index:index + numerator]
                    if len(bar) != numerator:
                        continue
                    accent = sum(
                        weight * float(bar[position])
                        for position, weight in accent_positions.items()
                    ) / sum(accent_positions.values())
                    non_accent_positions = [
                        position for position in range(numerator)
                        if position not in accent_positions
                    ]
                    contrast = accent - (
                        float(np.mean(bar[non_accent_positions]))
                        if non_accent_positions else 0.0
                    )
                    values.append(contrast)
                if values:
                    phase_scores.append(float(np.mean(values)))
            if phase_scores:
                # Prefer the simpler equivalent meter when the accent evidence
                # is effectively tied (for example, plain 3/4 can otherwise
                # look identical to 12/8 when every third beat is accented).
                raw_score = max(phase_scores)
                adjusted_score = raw_score - (0.015 * numerator)
                scores.append((adjusted_score, numerator, denominator))

        if not scores:
            return "4/4", 0.0, candidate_downbeats

        scores.sort(reverse=True)
        best_score, numerator, denominator = scores[0]
        second_score = scores[1][0] if len(scores) > 1 else best_score
        confidence = float(np.clip((best_score - second_score) / 2.0, 0.0, 1.0))
        signature = f"{numerator}/{denominator}"
        log_debug(
            f"Meter estimate: {signature} confidence={confidence:.2f} "
            f"scores={[(n, d, round(s, 3)) for s, n, d in scores]}"
        )
        return signature, confidence, candidate_downbeats
    except Exception as exc:
        log_debug(f"Meter estimation unavailable; using 4/4 fallback: {exc}")
        return "4/4", 0.0, candidate_downbeats
