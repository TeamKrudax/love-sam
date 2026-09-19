# love-sam — pure-Lua SAM for LÖVE

**Byte-exact portable speech synthesis for LÖVE**, ported from the C
SAM reference ([s-macke/SAM](https://github.com/s-macke/SAM)) into a
single dependency-free pure-Lua module. No C, no FFI, no binaries —
it renders spoken text to an 8-bit mono 22.05 kHz sample buffer / WAV
with the **exact same bytes** as the original C implementation.

Tested and proven on four corpus phrases (`Hello world.`, `Hello
there.`, `Sun.`, and a world/phoneme corpus) with **0 byte mismatches**
against the compiled C reference (see `sam-ref/` — the parity harness
lives there, byte-for-byte on `[W]` renderer traces too).

---

## Why "boring by design"

This demo and this README are **boring on purpose**, because boring is
what survives ANY machine: headless/CI, VMs, and Windows laptops whose
audio stack is a museum of virtual devices (Steam Streaming / Virtual
Audio / DroidCam / DXTory / Oculus Virtual / NVIDIA-Virtual / ...).

On those machines, **live playback can die natively**: the OpenAL-based
`love.audio.newSource():play()` path can take the whole process down —
and a *native* death **cannot** be caught by `pcall` (it's below Lua);
the process just exits. No error, no red screen, no trace. It looks
exactly like "it doesn't play the audio and just crashes the window."

So this project always produces the **real, deterministic result first** —
a byte-exact 22.05 kHz 8-bit mono WAV — and treats live playback as an
opt-in you reach for only when your audio device is known-stable.

---

## Install

Drop the `love-sam` folder (the one containing `sam.lua`) somewhere on
your `LÖVE` path next to your `main.lua`:

```
my-game/
  main.lua
  love-sam/          <- this library folder
    init.lua
    sam.lua
    reciter.lua
    parser.lua
    render.lua
    tables.lua
```

Then from `main.lua`:

```lua
local sam = require("love-sam")
local tts = sam.new(72, 64, 64, 64)   -- (speed, pitch, throat, mouth)
```

> `require("love-sam")` resolves to `love-sam/init.lua`, which re-exports
> the SAM instance builder — same name as the LÖVE template, works
> the same way.

---

## Quick start (the demo)

Run `love .` in the repository root. It will:

1. `require` the pure-Lua module and build an instance (pcall-guarded);
2. render a short, parity-proven phrase through the reciter + parser +
   renderer (pure Lua, deterministic, fast);
3. write the **byte-exact result** — `sam-love-hello.wav`, a 22.05 kHz
   8-bit mono WAV — into the LÖVE save directory;
4. skip live playback by default (`LOVESAM_PLAY != 1`).

The `.wav` **is** the demo's result. Open it in any player; the bytes
are identical to the C SAM reference.

To also try live playback — opt-in, only if your audio device is stable:

- **Interactive:** run `love .`, let the window open, **press `[P]`**.
  No env var, no setup — it's built into the demo window.
- **Scripted/CI** (no window/keys): set `LOVESAM_PLAY=1` — it drives
  the exact same code path as the `[P]` key:

```powershell
$env:LOVESAM_PLAY = "1"
love .
```

Both share the *same* opt-in live path (`attemptLivePlayback`), and
neither is ever needed to get the result: the `.wav` is always written
first, every run.

---

## API

### `sam.new(speed, pitch, throat, mouth) -> tts`
Build a SAM instance. All four are 8-bit values (0–255); the defaults
used throughout parity are `sam.new(72, 64, 128, 128)` (speed 72,
pitch 64, throat 128, mouth 128).

### `tts:getSpeed() / tts:getPitch() / tts:getThroat() / tts:getMouth() -> number`
Return the current speed, pitch, throat, or mouth setting (0–255).

### `tts:setSpeed(v) / tts:setPitch(v) / tts:setThroat(v) / tts:setMouth(v) -> tts`
Update one setting. Values wrap to 0–255 (same as `sam.new`) and are
mirrored into the render session, so the next `renderText`/`reset()`
picks them up. Each setter returns `self` for chaining:

```lua
tts:setSpeed(90):setPitch(70)
```

### `tts` — the constructor's return value — *instance object*
Instances are plain Lua tables (no userdata, no class boilerplate) with
the methods below.

### `tts:renderText(text) -> bytes`
Full pipeline: reciter (text → phonemes) → parser → renderer. Returns a
byte buffer with:
- `n` — number of samples (8-bit signed samples, 0-indexed: `bytes[0] .. bytes[n-1]`)
- indexing `bytes[i]` gives the signed sample.

### `tts:renderPhonemes(str) -> bytes`
Same but takes **phoneme strings** directly (`"/H EH4 L OW4 /W ER4 L D"`)
instead of English text — skips the reciter.

### `tts:toSoundData(bytes) -> SoundData | nil`
Convert a byte buffer into LÖVE `SoundData` (8-bit, mono, 22050 Hz).
Returns `nil` outside of LÖVE (or if LÖVE's sound module is unavailable).

### `tts:toWavString(bytes) -> string | nil`
**self-contained RIFF/WAVE writer** — turn any byte buffer into a
byte-correct `.wav` string, no LÖVE required.

### `tts:speak(text) -> Source | nil`
One-shot: render + `toSoundData` + `love.audio.newSource():play()`, and
returns the playing `Source` (keep a reference so it isn't collected).
No-op (returns `nil`) outside LÖVE.

### `tts:newText(text) -> utterance`
Builds a `{ tts, text }` object with a `:speak()` method:

```lua
local utt = tts:newText("Hello world.")
local src = utt:speak()   -- live audio (device permitting)
```

### `tts:reset()`
Reset per-speech renderer state (morph tables etc.).

### `tts.sampleRate`
`22050` — the fixed output rate. Set it before rendering if you need a
different rate (8-bit mono is fixed).

---

## The `.wav` writer

The demo and the module share a tiny self-contained WAV stringer
(`s4`/`s2`/RIFF-header + 8-bit body). If you want the same bytes as a
file without LÖVE's audio stack, write the string with any file API:

```lua
local sam = require("love-sam")
local tts = sam.new(72, 64, 64, 64)
local bytes = tts:renderText("Hello world.")
local wav   = tts:toWavString(bytes)     -- RIFF/WAVE string, byte-exact
love.filesystem.write("ear.wav", wav)    -- save dir
```

---

## Parity proof

`sam-ref/` contains the reference C implementation (`sam.exe`) plus
harnesses that compare, **byte-for-byte**, against the pure-Lua port:

- **Reciter parity** — `reciter.lua` is a verbatim port of
  `reciter.c: TextToPhonemes` (rule tables regenerated into
  `reciterTabs.lua`), so the phoneme bytes from `reciter.translate()`
  equal `recit.exe`'s output exactly.
- **Full pipeline parity** — `renderText` (reciter → parser → renderer)
  reproduces the C SAM sample output sample-for-sample.

On the current corpus (11 punctuation phrases + 30+ extra phrases,
mixed case, digits, apostrophes, hyphenation): **0 mismatches** in both
the phoneme streams and the audio samples.

---

## What "live playback can die natively" means (and why it's opt-in)

LÖVE's audio goes through **OpenAL**, a C library. On Windows machines
whose audio stack is full of *virtual devices* (Steam Streaming, Virtual
Audio, DroidCam, DXTory, Oculus Virtual, NVIDIA-Virtual, ...),
`love.audio.newSource():play()` can die **inside C**, below Lua:

- a Lua `pcall` **cannot** catch it — it's not a Lua error, the VM just exits;
- the process dies with **no error, no red screen, no traceback** —
  indistinguishable from "it crashed without playing."

That is exactly why this project writes the deterministic `.wav` **first**
and makes live playback a `LOVESAM_PLAY=1` opt-in. The `.wav` is the
result; live sound is the optional extra for machines you trust.

---

## License
Port of SAM, which is public domain per the reference
([s-macke/SAM](https://github.com/s-macke/SAM), "public domain").
The pure-Lua port is offered under the same terms as its source
reference.
