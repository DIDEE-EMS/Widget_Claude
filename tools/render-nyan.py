import os, mido, numpy as np, wave

# Rend le MIDI Nyan Cat en WAV chiptune (synthé onde carrée, sans soundfont).
# Le WAV est ensuite embarqué en base64 dans ClaudeUsageWidget.ps1.
#   pip install --user mido numpy
#   python tools/render-nyan.py
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "nyan-cat.mid")
OUT = os.path.join(HERE, "..", "nyan.wav")
SR = 22050

# --- collect note events with absolute times (seconds) ---
mid = mido.MidiFile(SRC)
print("length_sec:", round(mid.length, 2))
events = []          # (start, end, note, vel, channel)
active = {}          # (channel, note) -> (start, vel)
t = 0.0
for msg in mid:      # iterating the file yields real-time delta in msg.time
    t += msg.time
    if msg.type == 'note_on' and msg.velocity > 0:
        active[(msg.channel, msg.note)] = (t, msg.velocity)
    elif msg.type == 'note_off' or (msg.type == 'note_on' and msg.velocity == 0):
        key = (msg.channel, msg.note)
        if key in active:
            start, vel = active.pop(key)
            events.append((start, t, msg.note, vel, msg.channel))
total = max((e[1] for e in events), default=0.0)
print("notes:", len(events), "duration:", round(total, 2))

buf = np.zeros(int((total + 0.1) * SR) + 1, dtype=np.float32)

def square(freq, n):
    ph = np.arange(n) * (freq / SR)
    return np.sign(np.sin(2 * np.pi * ph)).astype(np.float32)

for start, end, note, vel, ch in events:
    i0 = int(start * SR)
    dur = max(0.04, end - start)
    n = int(dur * SR)
    if n <= 0:
        continue
    amp = (vel / 127.0) * 0.22
    if ch == 9:  # percussion -> short noise burst
        wav = (np.random.rand(n).astype(np.float32) * 2 - 1)
        amp *= 0.6
    else:
        wav = square(440.0 * 2 ** ((note - 69) / 12.0), n)
    # envelope: 5ms attack, 30ms release to avoid clicks
    env = np.ones(n, dtype=np.float32)
    a = min(int(0.005 * SR), n // 2)
    r = min(int(0.030 * SR), n // 2)
    if a: env[:a] = np.linspace(0, 1, a)
    if r: env[-r:] = np.linspace(1, 0, r)
    seg = wav * env * amp
    buf[i0:i0 + n] += seg

# normalize
peak = np.max(np.abs(buf))
if peak > 0:
    buf = buf / peak * 0.89
pcm = (buf * 32767).astype(np.int16)

with wave.open(OUT, 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print("WROTE:", OUT)
