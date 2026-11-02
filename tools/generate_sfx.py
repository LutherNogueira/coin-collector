"""Generates the game's sound effects as small WAV files, so no third-party audio is needed.

Each effect is a few synthesized notes (square, triangle, saw or noise) with a pitch sweep and a decay.
Usage: python tools/generate_sfx.py   (writes assets/sounds/*.wav)
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "sounds"


def voice(shape: str, f_start: float, f_end: float, seconds: float, volume: float, attack: float = 0.004, rng=None) -> list[float]:
    """One note: `shape` is square/triangle/saw/noise; pitch glides from f_start to f_end; volume decays to zero."""
    samples = []
    phase = 0.0
    count = int(seconds * RATE)
    for i in range(count):
        progress = i / max(count - 1, 1)
        freq = f_start + (f_end - f_start) * progress
        phase = (phase + freq / RATE) % 1.0
        if shape == "square":
            value = 1.0 if phase < 0.5 else -1.0
        elif shape == "triangle":
            value = 4.0 * abs(phase - 0.5) - 1.0
        elif shape == "saw":
            value = 2.0 * phase - 1.0
        else:
            value = rng.uniform(-1.0, 1.0)
        envelope = min(i / (attack * RATE), 1.0) * (1.0 - progress) ** 1.5
        samples.append(value * envelope * volume)
    return samples


def mix(*tracks: list[float]) -> list[float]:
    length = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(length)]


def concat(*parts: list[float]) -> list[float]:
    return [s for part in parts for s in part]


def lowpass(samples: list[float], alpha: float) -> list[float]:
    """One-pole low-pass filter (smaller alpha = darker, more muffled)."""
    out = []
    state = 0.0
    for s in samples:
        state += alpha * (s - state)
        out.append(state)
    return out


def delay(samples: list[float], seconds: float) -> list[float]:
    return [0.0] * int(seconds * RATE) + samples


def write(name: str, samples: list[float]) -> None:
    peak = max(abs(s) for s in samples) or 1.0
    scale = 0.6 / peak   # leave headroom
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT_DIR / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))
    print(f"{name}.wav: {len(samples) / RATE:.2f} s")


def main() -> None:
    rng = random.Random(7)   # fixed seed, so the noise in `death` is the same on every run

    write("jump", voice("square", 260, 620, 0.16, 1.0))

    # A bite into a fruit: three soft crunches (filtered noise bursts), then a juicy "pop" gliding upward.
    crunch_rng = random.Random(11)   # its own generator, so it never changes the noise used by `death`
    crunches = [
        delay(lowpass(voice("noise", 0, 0, 0.035, volume, attack=0.001, rng=crunch_rng), 0.4), start)
        for start, volume in [(0.0, 1.0), (0.045, 0.8), (0.085, 0.55)]
    ]
    pop = delay(voice("triangle", 350, 900, 0.09, 0.9), 0.12)
    write("collect", mix(*crunches, pop))

    write("death", mix(voice("saw", 440, 90, 0.45, 1.0), voice("noise", 0, 0, 0.30, 0.45, rng=rng)))

    notes = [523, 659, 784, 1047]   # C5 E5 G5 C6
    arpeggio = concat(*[voice("square", f, f, 0.10, 0.8) for f in notes])
    held = mix(voice("square", 1047, 1047, 0.45, 0.8), voice("triangle", 523, 523, 0.45, 0.9))
    write("win", concat(arpeggio, held))


if __name__ == "__main__":
    main()
