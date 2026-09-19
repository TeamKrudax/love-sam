--[[ LOVE-SAM: pure Lua SAM speech synthesis for LÖVE.
  Public API:
    local sam = require "love-sam"
    local tts = sam.new(speed, pitch, throat, mouth)   -- defaults 72, 64, 128, 128
    tts:newText("Hello world"):speak()                 -- fire and forget
    tts:speak("Hello world")                           -- plays and returns the Source
    local sd  = tts:toSoundData(tts:renderText("Hello"))
    local src = love.audio.newSource(sd)
]]

local parser = require("love-sam.parser")
local reciter = require("love-sam.reciter")
local render = require("love-sam.render")
local tables = require("love-sam.tables")

local signInputTable1 = tables.signInputTable1
local signInputTable2 = tables.signInputTable2

local SAMPLE_RATE = 22050

local function safe(t, i)
    return t[i] or 0
end

-- name -> phoneme index, built from the SAM phoneme symbol tables
local phonemeMap
local function buildPhonemeMap()
    if phonemeMap then return phonemeMap end
    phonemeMap = {}
    for i = 0, 80 do
        local c1 = string.char(safe(signInputTable1, i))
        local c2 = safe(signInputTable2, i)
        local name = (c2 ~= 42) and (c1 .. string.char(c2)) or c1
        phonemeMap[name] = i
    end
    return phonemeMap
end

-- Convert a S-A-M phoneme string ("/H EH4 L OW4") into the raw byte stream
-- that Parser1 consumes (155 = end token). Multi-phoneme sequences such as
-- "AAR"/"AXR" expand to their individual characters, exactly like the
-- reference reciter emits them: the parser reads them as AA+R / AX+R.
local function phonemeStringToBytes(str)
    local map = buildPhonemeMap()
    local out = {}
    local n = 0
    for token in string.gmatch(str, "%S+") do
        local base, stress = token:match("^(.-)([0-8]*)$")
        local idx = map[base]
        if not idx then
            error("unknown SAM phoneme: " .. token)
        end
        out[n] = safe(signInputTable1, idx)
        n = n + 1
        local c2 = safe(signInputTable2, idx)
        if c2 ~= 42 then
            out[n] = c2
            n = n + 1
        end
        if stress ~= "" then
            out[n] = string.byte(stress)
            n = n + 1
        end
    end
    out[n] = 155
    n = n + 1
    out.n = n
    return out
end

local function bytesToString(arr)
    local n = arr.n or 0
    local parts = {}
    for i = 0, n - 1 do
        local b = arr[i] or 0
        if b < 0 then b = b + 256 end
        parts[i + 1] = string.char(b % 256)
    end
    return table.concat(parts)
end

local sam = {}

sam.sampleRate = SAMPLE_RATE

function sam.new(speed, pitch, throat, mouth)
    local self = setmetatable({}, { __index = sam })
    self.speed = ((speed ~= nil) and speed % 256) or 72
    self.pitch = ((pitch ~= nil) and pitch % 256) or 64
    self.throat = ((throat ~= nil) and throat % 256) or 128
    self.mouth = ((mouth ~= nil) and mouth % 256) or 128
    self.ss = render.newSession(self)
    self.state = parser.newState()
    self.state.render = function(st)
        render.render(self.ss, st.phonemeIndexOutput, st.stressOutput, st.phonemeLengthOutput)
    end
    return self
end

-- Parameter getters
function sam:getSpeed()
    return self.speed
end

function sam:getPitch()
    return self.pitch
end

function sam:getThroat()
    return self.throat
end

function sam:getMouth()
    return self.mouth
end

-- Parameter setters. Values wrap to 0..255 (like sam.new) and are mirrored
-- into the render session so the next renderText/reset picks them up
-- (render.init re-applies mouth/throat; render.render reads speed/pitch live).
-- Each setter returns self for chaining.
function sam:setSpeed(v)
    self.speed = (v ~= nil) and v % 256 or 72
    self.ss.speed = self.speed
    return self
end

function sam:setPitch(v)
    self.pitch = (v ~= nil) and v % 256 or 64
    self.ss.pitch = self.pitch
    return self
end

function sam:setThroat(v)
    self.throat = (v ~= nil) and v % 256 or 128
    self.ss.throat = self.throat
    return self
end

function sam:setMouth(v)
    self.mouth = (v ~= nil) and v % 256 or 128
    self.ss.mouth = self.mouth
    return self
end

-- Reset per-speech render state (buffer, mouth/throat formants)
function sam:reset()
    render.init(self.ss)
end

-- Render a phoneme list; returns an array of 0..255 samples (or nil on failure).
function sam:renderPhonemes(str)
    local bytes = phonemeStringToBytes(str)
    self:reset()
    if not parser.samMain(self.state, bytes) then return nil end
    return render.getBytes(self.ss)
end

-- Render an already encoded byte stream (test/parity helper).
function sam:_renderPhonemeBytes(bytes)
    self:reset()
    if not parser.samMain(self.state, bytes) then return nil end
    return render.getBytes(self.ss)
end

-- Convert text to phonemes first (verbatim reciter port), then render.
function sam:renderText(text)
    local bytes = reciter.translate(text)
    if not bytes then return nil end
    return self:_renderPhonemeBytes(bytes)
end

-- Build a SoundData from a sample array. Returns nil outside LÖVE.
--
-- WHY the byte-floats (a real gotcha, now fixed):  love.sound.newSoundData
-- has NO "array of numbers" overload — it takes either a filename/File/
-- FileData/Decoder to DECODE, or a count+rate+depth+channels to allocate an
-- EMPTY buffer.  Feeding it a raw string or a numeric Lua table throws
-- "(filename, File, or FileData expected)" at runtime.  So we do the
-- LÖVE-0.6-era portable thing: allocate the empty mono buffer, then fill it
-- one 8-bit byte at a time with sd:setSample(i, (byte-128)/128).
function sam:toSoundData(bytes)
    if not bytes then return nil end
    local love = rawget(_G, "love")
    if love and love.sound and love.sound.newSoundData then
        local n = bytes.n or 0
        if n == 0 then return nil end
        local sdok, sd = pcall(function()
            local sd = love.sound.newSoundData(n, SAMPLE_RATE, 8, 1)
            for i = 0, n - 1 do
                sd:setSample(i, ((bytes[i] or 0) - 128) / 128)
            end
            return sd
        end)
        if sdok then return sd end
    end
    return nil
end

-- Speech helper for one-shot playback. Returns the Source or nil.
function sam:speak(text)
    local sd = self:toSoundData(self:renderText(text))
    if sd then
        local love = rawget(_G, "love")
        if love and love.audio and love.audio.newSource then
            local src = love.audio.newSource(sd)
            src:play()
            return src
        end
    end
    return nil
end

-- Build a text utterance object:  utt = tts:newText("hello"); utt:speak()
function sam:newText(text)
    return {
        tts = self,
        text = text,
        speak = function(o)
            return o.tts:speak(o.text)
        end,
    }
end

return sam