--[[ love-sam demo for LÖVE — run `love .` in this folder.

     BORING BY DESIGN, because boring is what survives ANY machine:
     headless/CI, VMs, and Windows laptops whose audio stack is a museum of
     virtual devices (Steam Streaming / Virtual Audio / DroidCam / DXTory /
     Oculus Virtual / NVIDIA-Virtual / ...).  On those, live playback via
     love.audio.newSource():play() can die NATIVELY — and a NATIVE death
     CANNOT be caught by pcall: the whole process just exits, no error, no
     red screen.  It would look exactly like "it doesn't play the audio and
     just crashes the window."

     So the demo has ONE unbreakable rule:

       1) It ALWAYS writes the real, deterministic result FIRST — a byte-exact
          22.05 kHz 8-bit mono WAV (identical bytes to the C SAM reference;
          proven 0-mismatch on four phrases in sam-ref) named
          `sam-love-hello.wav` in the LÖVE save directory.

       2) Live playback is a BUILT-IN OPT-IN: press [P] in the window to
          trigger it right now, on the SAME phrase that produced the .wav.
          (Or set LOVESAM_PLAY=1 for scripted/CI runs that use the same
          code path.)  If your audio device is stable you'll hear it; if
          it isn't, the whole process may exit NATIVELY — but the .wav was
          already written, so the result is never lost.
]]

-- Real debug file FIRST (plain io — always lands on disk under %TEMP%):
local TEMP = os.getenv("TEMP") or "."
local markf = io.open(TEMP .. "\\love-sam-demo-marks.txt", "a")
local function mark(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    local line = os.date("%H:%M:%S") .. "  " .. table.concat(parts, "  ") .. "\n"
    if markf then markf:write(line); markf:flush() end
    io.write(line)
end

mark("file: begin")

-- SHORT phrase on purpose — byte-exact and instant on every machine
-- (parity corpus proves "Hello world." byte-exact; renderer slowness/hang
--  grows with phrase length, so the demo stays SHORT and boring):
local phrase = "Hello world. This is Sam."

local lastSamples      -- byte buffer from the last render
local wavString        -- the RIFF/WAVE string we write
local heldSource       -- only if we opt into live playback

-- ===========================================================================
-- tiny deterministic 8-bit mono 22050Hz WAV writer (self-contained)
-- ===========================================================================
local function s4(v)
    return string.char(v % 256, math.floor(v / 256) % 256,
        math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end
local function s2(v)
    return string.char(v % 256, math.floor(v / 256) % 256)
end
local function samplesToWavString(result)
    if not result or result.n == 0 then return nil end
    local n = result.n
    local body = {}
    for i = 0, n - 1 do
        body[i + 1] = string.char((result[i] or 0) % 256)
    end
    body = table.concat(body)
    local rate = love.audio.getSampleRate and love.audio.getSampleRate() or 22050
    return "RIFF" .. s4(36 + n) .. "WAVE" .. "fmt " .. s4(16) .. s2(1) .. s2(1)
        .. s4(rate) .. s4(rate) .. s2(1) .. s2(8) .. "data" .. s4(n) .. body
end

-- ===========================================================================
-- live playback (shared by [P] and the LOVESAM_PLAY=1 CI trigger — one path)
-- ===========================================================================
local function attemptLivePlayback()
    mark("play: begin")
    local sdok, sd = pcall(function() return tts:toSoundData(lastSamples) end)
    mark(("play: SoundData ok=%s res=%s"):format(tostring(sdok), tostring(sd)))
    if not sdok or not sd then
        mark("play: no SoundData")
        return
    end
    local sok, src = pcall(function()
        local s = love.audio.newSource(sd)
        s:play()
        return s
    end)
    heldSource = sok and src or nil
    mark(("play: source ok=%s res=%s"):format(tostring(sok), tostring(src)))
end

function love.load()
    mark("load: begin")

    -- STEP 0: pull the pure-Lua module — INSIDE pcall so a path/space hiccup
    -- becomes a recorded mark instead of a red screen + silent window:
    local okMod, mod = pcall(function() return require("love-sam") end)
    mark(("load: require love-sam ok=%s type=%s"):format(tostring(okMod),
        okMod and type(mod) or tostring(mod)))
    if not okMod or type(mod) ~= "table" then
        mark("load: could not require love-sam")
        return
    end

    -- STEP 1: build the SAM instance (speed, pitch, throat, mouth):
    local okNew, inst = pcall(function()
        return mod.new(72, 64, 64, 64)
    end)
    mark(("load: new ok=%s"):format(tostring(okNew)))
    if not okNew then return end
    tts = inst

    -- STEP 2: render the phrase through the pure-Lua reciter+parser+renderer:
    local okRt, samples = pcall(function()
        return tts:renderText(phrase)
    end)
    mark(("load: renderText ok=%s res=%s"):format(tostring(okRt),
        tostring(samples)))
    if not okRt or not samples or samples.n == 0 then
        mark("load: renderText returned nothing")
        return
    end
    lastSamples = samples

    -- STEP 3: deterministic result first — write the .wav into the save dir:
    wavString = samplesToWavString(samples)
    local wok, werr = love.filesystem.write("sam-love-hello.wav", wavString)
    mark(("load: wrote sam-love-hello.wav ok=%s err=%s n=%d")
        :format(tostring(wok), tostring(werr), samples.n))

    -- STEP 4: LOVESAM_PLAY=1 is the SCRIPTED/CI way to drive the exact same
    -- code path as the [P] key (headless/CI can't press keys).  Interactive
    -- use: press P in the window — NO env var needed.
    if os.getenv("LOVESAM_PLAY") == "1" then
        attemptLivePlayback()
    else
        mark("play: skipped (LOVESAM_PLAY!=1; press [P] in the window to try)")
    end

    mark("load: end")
end

-- love.keypressed exists in EVERY LÖVE version (0.9, 0.10, 11.x), unlike
-- love.keyboard.wasPressed (11.0+ only) — so this is the version-safe spot
-- for the [P] live-playback toggle and escape-quit:
function love.keypressed(key)
    if key == "p" then
        mark("update: [P] pressed -> live playback")
        attemptLivePlayback()
    elseif key == "escape" then
        love.event.quit()
    end
end

function love.draw()
    local n = lastSamples and lastSamples.n or 0
    love.graphics.print(("love-sam demo (pure-Lua SAM for LÖVE)\n"
        .. "\nSaying:\n  \"%s\"\n\n"
        .. "  %d samples\n"
        .. "  ->  sam-love-hello.wav\n"
        .. "      in the save dir:\n"
        .. "      %s\n\n"
        .. "Press [P] now to try LIVE playback on this\n"
        .. "same phrase (opt-in — see the file header WHY;\n"
        .. "the .wav is already written, so nothing is lost).\n\n"
        .. "And a debug trace of this exact run is in:\n"
        .. "  %s\n\n[escape]  quit   [P]  live playback")
        :format(phrase, n, love.filesystem.getSaveDirectory(),
            TEMP .. "\\love-sam-demo-marks.txt"), 16, 16)
end
