#!/usr/bin/env python3
"""HARAQ v0.7: real CC0 field recordings for weapons, explosions, footsteps, wind and surf.

Every source below is a Freesound.org upload released under Creative Commons 0 (public domain
dedication; license checked on each sound page). The script downloads the public HQ preview,
decodes it to mono, trims / normalises it and layers it with the procedural desert space from
gen_audio.py, then writes small mono Ogg Vorbis files to assets/audio/ (overwriting the
synthetic versions of the same names). Music stays procedural (gen_audio.py --music-only).

Run:  python3 tools/import_recordings.py [--cache DIR]      (needs numpy + ffmpeg)
"""
import os, sys, subprocess, urllib.request
import numpy as np

os.environ["HARAQ_IMPORTING"] = "1"

sys.path.insert(0, os.path.dirname(__file__))
import gen_audio as ga  # noqa: E402

SR = ga.SR
LICENSE = "CC0 1.0"

# name -> (freesound id, author, title, preview url)
SOURCES = {
    "enfield": (450852, "kyles", "gun lee enfield 303 rifle fire shot loud badass crispy.wav"),
    "mauser": (802675, "Walking.With.Microphones", "Mauser 98k Shooting"),
    "revolver": (683186, "Shark_Anthony", "357 Magnum Revolver Gunshot"),
    "thompson": (258198, "wadaltmon", "Thompson SMG Shot"),
    "smg9": (865993, "db465", "mp5_fire"),
    "explosion": (209769, "Johnnyfarmer", "Explosion Distant"),
    "sand": (384082, "savataivanov", "Foot_Step_grit_Sand.wav"),
    "wind": (112296, "slugzilla", "desertwind1FINAL.wav"),
    "waves": (531015, "Noted451", "Ocean Waves.wav"),
}
PREVIEWS = {}  # filled from sources.txt (id -> preview url); see CREDITS.md


def load_previews():
    path = os.path.join(os.path.dirname(__file__), "recordings_sources.txt")
    for line in open(path, encoding="utf8"):
        line = line.strip()
        if line and not line.startswith("#"):
            sid, url = line.split()[:2]
            PREVIEWS[int(sid)] = url


def fetch(key, cache):
    sid = SOURCES[key][0]
    url = PREVIEWS[sid]
    os.makedirs(cache, exist_ok=True)
    dst = os.path.join(cache, f"{sid}{os.path.splitext(url)[1]}")
    if not os.path.exists(dst):
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (HARAQ asset import)"})
        with urllib.request.urlopen(req, timeout=60) as r, open(dst, "wb") as f:
            f.write(r.read())
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", dst, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def onset(x, thresh=0.25):
    a = np.abs(x)
    i = int(np.argmax(a > thresh * a.max()))
    return max(0, i - int(0.004 * SR))


def fade(x, fin=0.002, fout=0.08):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def cut(x, start, dur):
    i = int(start * SR) if isinstance(start, float) else start
    return x[i:i + int(dur * SR)]


def shot(x, dur, hp=50, lp=None, space=0.18, tail=0.9, synth=None, mix=0.25, sat=1.5):
    """Recorded shot trimmed at the onset, cleaned (DC/rumble, optional darkening), with a touch of
    the procedural desert reverb and optionally a little of the old synthetic shot underneath."""
    y = cut(x, onset(x), dur)
    y = ga.band(y - y.mean(), hp, lp)
    y = fade(ga.norm(y), 0.0015, min(0.25, dur * 0.35))
    y = ga.soft_clip(y, sat) if sat else y
    if synth is not None:
        s = synth[: len(y)] if len(synth) >= len(y) else np.pad(synth, (0, len(y) - len(synth)))
        y = ga.norm(y) + ga.norm(s) * mix
    return ga.norm(ga.desert_reverb(ga.norm(y), tail, space), 0.95)


def best_steps(x, n=4, length=0.34):
    """Pick the n cleanest footstep transients from a walking recording."""
    env = np.convolve(np.abs(x), np.ones(int(0.01 * SR)) / int(0.01 * SR), mode="same")
    picks, used = [], np.zeros(len(x), bool)
    order = np.argsort(env)[::-1]
    for i in order:
        if len(picks) >= n:
            break
        s = max(0, i - int(0.03 * SR))
        if used[max(0, s - int(0.25 * SR)):s + int(length * SR)].any() or s + int(length * SR) >= len(x):
            continue
        used[s:s + int(length * SR)] = True
        picks.append(s)
    return [x[s:s + int(length * SR)] for s in sorted(picks)]


def loop_segment(x, start, dur):
    seg = cut(x, start, dur + 0.5)
    seg = ga.band(seg - seg.mean(), 40, None)
    return seg


def main():
    cache = sys.argv[sys.argv.index("--cache") + 1] if "--cache" in sys.argv else os.path.join(os.path.expanduser("~"), ".cache", "haraq-recordings")
    load_previews()
    src = {k: fetch(k, cache) for k in SOURCES}
    # Weapons: real shots, layered lightly with the old synthetic sub/crack for punch on phones.
    ga.write("shot_enfield", shot(src["enfield"], 0.62, synth=ga.gunshot(160, 9500, 0.014, 0.08, 0.2, 0.62, level=0.0, sub=1.3), mix=0.2, tail=1.3, space=0.2))
    ga.write("shot_webley", shot(src["revolver"], 0.5, synth=ga.gunshot(220, 7000, 0.010, 0.05, 0.2, 0.5, mech=0.4, level=0.0), mix=0.15, tail=0.9, space=0.16))
    ga.write("shot_thompson", shot(src["thompson"], 0.22, tail=0.7, space=0.14, sat=1.8))
    ga.write("shot_mp40", shot(src["smg9"], 0.24, hp=70, tail=0.7, space=0.14, sat=1.8))
    far = shot(src["mauser"], 0.7, hp=70, lp=3800, tail=1.5, space=0.35, sat=None)
    ga.write("shot_enemy", ga.norm(far, 0.85))
    # Artillery: recorded distant explosion, trimmed to its main boom + roll.
    ex = src["explosion"]
    e = cut(ex, onset(ex, 0.4) - int(0.05 * SR), 3.2)
    e = fade(ga.norm(ga.band(e - e.mean(), 25, 7000)), 0.01, 1.0)
    ga.write("explosion", ga.norm(ga.desert_reverb(e, 1.2, 0.15), 0.95))
    # Footstep on sand: the cleanest single step from a grit/sand walking recording.
    steps = best_steps(ga.band(src["sand"], 80, 9000), 4)
    st = steps[1] if len(steps) > 1 else steps[0]
    ga.write("step", ga.norm(fade(st, 0.003, 0.12), 0.8))
    # Ambience loops (22 kHz, crossfaded seamlessly).
    w = src["wind"]
    ga.write("wind_loop", ga.norm(loop_segment(w, 1.0, min(16.0, len(w) / SR - 2.0)), 0.55), quality=1, loop_fade=0.5)
    s = src["waves"]
    ga.write("sea_loop", ga.norm(loop_segment(s, 8.0, 18.0), 0.6), quality=1, loop_fade=0.5)


if __name__ == "__main__":
    main()
