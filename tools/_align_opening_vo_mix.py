# -*- coding: utf-8 -*-
"""Align F5 VO into 精校 mix; sentence cues + energy timeline."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

WORK = Path(r"c:\Users\WXH\Pictures\eve自走棋")
MIX = WORK / "8月1日(1) 合成精校.mp3"
VO = WORK / "eve_bush_parody_f5edit.wav"
OUT = Path(r"H:\game_dev\cg-director-studio\projects\eveautochess-opening\_review\opening_audio")

# Sentence plan from render_f5_edit.py CHUNKS (absolute on VO timeline)
SENTENCES = [
    {
        "id": 1,
        "t0": 0.00,
        "t1": 13.30,
        "en": (
            "At my allurement, elements of the New Eden unmanned expedition, as well "
            "as key titans of the United Four Races, are arriving today to take up "
            "interfighting positions in Sleeper control regions."
        ),
        "zh_func": "授意钩子 · 兵力开场（无人远征 / 四族泰坦抵达休眠者控制区）",
        "nail": False,
    },
    {
        "id": 2,
        "t0": 13.30,
        "t1": 19.30,
        "en": (
            "I took this action to assist the Sleeper Authority government in the "
            "rebirth of its homeworld."
        ),
        "zh_func": "动机句 · 协助休眠者当局「重生母星」",
        "nail": False,
    },
    {
        "id": 3,
        "t0": 19.30,
        "t1": 34.60,
        "en": (
            "No one commits New Eden's four great races to a dangerous mission lightly, "
            "but after perhaps irresistible opportunistic allurement and exhausting "
            "every great race's patience, it became necessary they take the bite."
        ),
        "zh_func": "钉死长句 · 四族调动不易 → 终句 take the bite",
        "nail": True,
        "zh_nail_display": "没人能这么轻易的调动新伊甸四族的舰队",
        "nail_core_vo_abs": (19.74, 23.64),  # "No one ... lightly" on Bush words
    },
]


def load_mono(path: Path, sr: int = 16000) -> tuple[np.ndarray, int]:
    import librosa

    y, _ = librosa.load(str(path), sr=sr, mono=True)
    return y.astype(np.float32), sr


def find_offset(mix: np.ndarray, vo: np.ndarray, sr: int) -> float:
    # Search VO onset in first 15s of mix using coarse correlation on envelopes
    win = int(8.0 * sr)
    vo_seg = vo[:win]
    mix_search = mix[: int(20.0 * sr)]
    # Downsample envelopes
    hop = 160  # 10ms
    def env(x):
        n = len(x) // hop
        x = x[: n * hop].reshape(n, hop)
        return np.sqrt((x * x).mean(axis=1) + 1e-12)

    e_m, e_v = env(mix_search), env(vo_seg)
    # Correlate
    corr = np.correlate(e_m - e_m.mean(), e_v - e_v.mean(), mode="valid")
    lag = int(np.argmax(corr))
    return lag * hop / sr


def per_sec_rms(y: np.ndarray, sr: int) -> list[dict]:
    out = []
    for s in range(int(np.ceil(len(y) / sr))):
        a, b = s * sr, min((s + 1) * sr, len(y))
        chunk = y[a:b]
        out.append({"s": s, "rms": float(np.sqrt(np.mean(chunk * chunk) + 1e-12))})
    return out


def music_end(y: np.ndarray, sr: int) -> float:
    # Last time RMS (100ms hop) stays above 5% of peak in last half
    hop = int(0.1 * sr)
    n = len(y) // hop
    rms = np.array(
        [np.sqrt(np.mean(y[i * hop : (i + 1) * hop] ** 2) + 1e-12) for i in range(n)]
    )
    peak = float(rms.max())
    thr = max(0.02 * peak, 0.005)
    active = np.where(rms > thr)[0]
    if len(active) == 0:
        return 0.0
    return float((active[-1] + 1) * hop / sr)


def whisper_vo_words(path: Path) -> list[dict]:
    from faster_whisper import WhisperModel

    model = WhisperModel("medium.en", device="cpu", compute_type="int8")
    segments, _ = model.transcribe(
        str(path),
        language="en",
        word_timestamps=True,
        vad_filter=False,
        beam_size=5,
    )
    words = []
    for seg in segments:
        for w in seg.words or []:
            words.append({"w": w.word.strip(), "s": round(w.start, 3), "e": round(w.end, 3)})
    return words


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    OUT.mkdir(parents=True, exist_ok=True)

    print("loading mix/vo…")
    mix, sr = load_mono(MIX)
    vo, _ = load_mono(VO, sr)
    print(f"mix={len(mix)/sr:.3f}s vo={len(vo)/sr:.3f}s")
    off = find_offset(mix, vo, sr)
    print(f"VO offset in mix ≈ {off:.3f}s")

    mend = music_end(mix, sr)
    print(f"music_end ≈ {mend:.3f}s")
    vo_end_mix = off + len(vo) / sr
    # Trim silent tail of VO
    vo_tail = vo
    thr = 0.01 * float(np.max(np.abs(vo)))
    nz = np.where(np.abs(vo) > thr)[0]
    vo_speech_end = float(nz[-1] / sr) if len(nz) else len(vo) / sr
    print(f"VO speech end (file) ≈ {vo_speech_end:.3f}s → mix {off+vo_speech_end:.3f}s")

    print("whisper word align on VO…")
    words = whisper_vo_words(VO)
    (OUT / "vo_f5edit_words.json").write_text(
        json.dumps(words, ensure_ascii=False, indent=1), encoding="utf-8"
    )
    for w in words:
        print(f"  {w['s']:6.2f}-{w['e']:6.2f}  {w['w']}")

    # Map sentences onto mix
    cues = []
    for s in SENTENCES:
        item = {
            **s,
            "mix_t0": round(off + s["t0"], 3),
            "mix_t1": round(off + s["t1"], 3),
        }
        if s.get("nail_core_vo_abs"):
            a, b = s["nail_core_vo_abs"]
            item["nail_core_mix"] = [round(off + a, 3), round(off + b, 3)]
        cues.append(item)

    # Refine sentence ends from whisper words if available
    report = {
        "mix": str(MIX),
        "vo": str(VO),
        "mix_duration_s": round(len(mix) / sr, 3),
        "vo_duration_s": round(len(vo) / sr, 3),
        "vo_offset_in_mix_s": round(off, 3),
        "vo_speech_end_file_s": round(vo_speech_end, 3),
        "vo_speech_end_mix_s": round(off + vo_speech_end, 3),
        "bgm_end_mix_s": round(mend, 3),
        "prev_plan_vo_end": 33.0,
        "prev_plan_bgm_end": 64.0,
        "delta_vo_end_s": round(off + vo_speech_end - 33.0, 3),
        "delta_bgm_end_s": round(mend - 64.0, 3),
        "sentences": cues,
        "per_sec_rms": per_sec_rms(mix, sr),
        "whisper_word_count": len(words),
    }
    (OUT / "mix_align_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps({k: report[k] for k in report if k != "per_sec_rms" and k != "sentences"}, indent=2))
    print("SENTENCES ON MIX:")
    for c in cues:
        print(f"  S{c['id']} {c['mix_t0']:6.2f}-{c['mix_t1']:6.2f}  {c['zh_func']}")
    print("wrote", OUT / "mix_align_report.json")


if __name__ == "__main__":
    main()
