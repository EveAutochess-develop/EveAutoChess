# -*- coding: utf-8 -*-
"""RMS / silence probe for opening CG mix (VO+BGM)."""
from __future__ import annotations

import json
import struct
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

SRC = Path(r"c:\Users\WXH\Pictures\eve自走棋\8月1日(1) 合成精校.mp3")
OUT_DIR = Path(r"H:\game_dev\cg-director-studio\projects\eveautochess-opening\_review\opening_audio")
WAV = OUT_DIR / "_mix_probe.wav"
REPORT = OUT_DIR / "mix_rms_report.json"


def find_ffmpeg() -> str | None:
    for p in (
        r"H:\ffmpeg\bin\ffmpeg.exe",
        r"C:\ffmpeg\bin\ffmpeg.exe",
        r"C:\ProgramData\chocolatey\bin\ffmpeg.exe",
        "ffmpeg",
    ):
        try:
            r = subprocess.run([p, "-version"], capture_output=True, text=True, timeout=5)
            if r.returncode == 0:
                return p
        except Exception:
            continue
    return None


def decode_with_ffmpeg(ffmpeg: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    cmd = [
        ffmpeg,
        "-y",
        "-i",
        str(SRC),
        "-ac",
        "1",
        "-ar",
        "16000",
        "-sample_fmt",
        "s16",
        str(WAV),
    ]
    subprocess.run(cmd, check=True, capture_output=True)


def decode_with_miniaudio_or_pydub() -> None:
    # Prefer scipy/soundfile if available; else use mutagen+manual fail.
    try:
        import soundfile as sf  # type: ignore

        data, sr = sf.read(str(SRC), always_2d=True)
        mono = data.mean(axis=1).astype(np.float32)
        if sr != 16000:
            # crude resample
            n = int(len(mono) * 16000 / sr)
            x = np.linspace(0, len(mono) - 1, n)
            mono = np.interp(x, np.arange(len(mono)), mono).astype(np.float32)
            sr = 16000
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        pcm = np.clip(mono * 32767, -32768, 32767).astype(np.int16)
        with wave.open(str(WAV), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sr)
            w.writeframes(pcm.tobytes())
        return
    except Exception as e:
        print("soundfile fail:", e)
    try:
        from pydub import AudioSegment  # type: ignore

        OUT_DIR.mkdir(parents=True, exist_ok=True)
        seg = AudioSegment.from_file(str(SRC)).set_channels(1).set_frame_rate(16000)
        seg.export(str(WAV), format="wav")
        return
    except Exception as e:
        print("pydub fail:", e)
        raise


def load_wav(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as w:
        assert w.getnchannels() == 1 and w.getsampwidth() == 2
        sr = w.getframerate()
        n = w.getnframes()
        raw = w.readframes(n)
    samples = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    return samples, sr


def frame_rms(samples: np.ndarray, sr: int, win_ms: float = 50.0, hop_ms: float = 25.0):
    win = int(sr * win_ms / 1000)
    hop = int(sr * hop_ms / 1000)
    n = 1 + max(0, (len(samples) - win) // hop)
    rms = np.empty(n, dtype=np.float32)
    times = np.empty(n, dtype=np.float32)
    for i in range(n):
        a = i * hop
        b = a + win
        chunk = samples[a:b]
        rms[i] = float(np.sqrt(np.mean(chunk * chunk) + 1e-12))
        times[i] = a / sr
    return times, rms


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    print("src", SRC, "size", SRC.stat().st_size)
    ffmpeg = find_ffmpeg()
    if ffmpeg:
        print("ffmpeg", ffmpeg)
        decode_with_ffmpeg(ffmpeg)
    else:
        print("no ffmpeg; fallback")
        decode_with_miniaudio_or_pydub()

    samples, sr = load_wav(WAV)
    dur = len(samples) / sr
    print(f"decoded dur={dur:.3f}s sr={sr}")
    times, rms = frame_rms(samples, sr)
    # Speech-ish: mid-high RMS with more HF energy via short-window variance
    # Also compute spectral flatness-ish via zero-crossing rate
    hop = int(sr * 0.025)
    win = int(sr * 0.050)
    zcr = np.empty_like(rms)
    for i in range(len(rms)):
        a = i * hop
        chunk = samples[a : a + win]
        if len(chunk) < 2:
            zcr[i] = 0
            continue
        zcr[i] = float(np.mean(np.abs(np.diff(np.sign(chunk)))) * 0.5)

    # Adaptive thresholds
    p50, p80, p90, p95 = np.percentile(rms, [50, 80, 90, 95])
    print(f"rms p50={p50:.4f} p80={p80:.4f} p90={p90:.4f} p95={p95:.4f}")

    # Voice typically higher ZCR than pad music; music may be loud too.
    # Heuristic: find last sustained high-ZCR+high-RMS region in first 45s
    speech_score = rms * (0.3 + zcr)
    # Smooth
    k = 7
    kernel = np.ones(k) / k
    speech_s = np.convolve(speech_score, kernel, mode="same")
    rms_s = np.convolve(rms, kernel, mode="same")

    # Candidate speech frames: top quartile of speech_s among first 45s
    mask45 = times <= 45.0
    thr = float(np.percentile(speech_s[mask45], 70)) if mask45.any() else float(np.percentile(speech_s, 70))
    speech_frames = speech_s >= thr
    # Find contiguous regions
    regions = []
    i = 0
    while i < len(speech_frames):
        if not speech_frames[i]:
            i += 1
            continue
        j = i
        while j < len(speech_frames) and speech_frames[j]:
            j += 1
        t0, t1 = float(times[i]), float(times[min(j - 1, len(times) - 1)] + 0.05)
        if t1 - t0 >= 0.4:
            regions.append((t0, t1, float(speech_s[i:j].mean())))
        i = j

    # Music end: last time rms_s stays above quiet floor
    quiet = float(np.percentile(rms_s, 15))
    active = rms_s > max(quiet * 3.0, 0.01)
    music_end = float(times[np.where(active)[0][-1]] + 0.05) if active.any() else dur

    # VO end: end of last speech region starting before 45s
    vo_regions = [r for r in regions if r[0] < 45]
    vo_end = vo_regions[-1][1] if vo_regions else None
    vo_start = vo_regions[0][0] if vo_regions else None

    # Per-second energy table (first 75s)
    per_sec = []
    for s in range(int(dur) + 1):
        m = (times >= s) & (times < s + 1)
        if not m.any():
            continue
        per_sec.append(
            {
                "s": s,
                "rms": float(rms_s[m].mean()),
                "speech": float(speech_s[m].mean()),
                "zcr": float(zcr[m].mean()),
            }
        )

    report = {
        "src": str(SRC),
        "duration_s": dur,
        "vo_start_est": vo_start,
        "vo_end_est": vo_end,
        "music_end_est": music_end,
        "speech_regions": [{"t0": a, "t1": b, "score": c} for a, b, c in regions],
        "per_sec": per_sec,
        "thresholds": {"speech_thr": thr, "quiet": quiet},
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("vo_start_est", vo_start)
    print("vo_end_est", vo_end)
    print("music_end_est", music_end)
    print("speech_regions:")
    for a, b, c in regions:
        print(f"  {a:6.2f}-{b:6.2f} score={c:.4f}")
    print("wrote", REPORT)


if __name__ == "__main__":
    main()
