-- Pure Lua port of the SAM renderer (render.c).
-- Converts a phoneme list (phonemeIndexOutput/stressOutput/phonemeLengthOutput)
-- into raw 8-bit PCM samples (22050 Hz) stored in a session buffer.

local M = require("love-sam.tables")

local band = M.band
local bor = M.bor
local bxor = M.bxor

local tab48426 = M.tab48426
local tab47492 = M.tab47492
local amplitudeRescale = M.amplitudeRescale
local blendRank = M.blendRank
local outBlendLength = M.outBlendLength
local inBlendLength = M.inBlendLength
local sampledConsonantFlags = M.sampledConsonantFlags
local freq2data0, freq3data = nil, M.freq3data
local ampl1data = M.ampl1data
local ampl2data = M.ampl2data
local ampl3data = M.ampl3data
local sinus = M.sinus
local rectangle = M.rectangle
local sampleTable = M.sampleTable
local timetable = M.timetable
local mouthFormants5_29 = M.mouthFormants5_29
local throatFormants5_29 = M.throatFormants5_29
local mouthFormants48_53 = M.mouthFormants48_53
local throatFormants48_53 = M.throatFormants48_53

local function safe(t, i)
    if t == nil then error("safe() got nil table at index " .. tostring(i) .. " from " .. debug.getinfo(2, "l").currentline, 2) end
    return t[i] or 0
end

-- C truncates toward zero for signed integer division.
-- Lua 5.1 math.floor/ceil handle negatives; pick toward zero.
local function cdiv(a, b)
    if a < 0 then
        return math.ceil(a / b)
    end
    return math.floor(a / b)
end

local render = {}

-- ---------------------------------------------------------------------------
-- per session state
-- ---------------------------------------------------------------------------

local function zeroFill(n)
    local t = {}
    for i = 0, n do t[i] = 0 end
    return t
end

function render.newSession(opts)
    local ss = {}
    ss.speed = opts.speed or 72
    ss.pitch = opts.pitch or 64
    ss.singmode = opts.singmode or false
    ss.mouth = opts.mouth or 128
    ss.throat = opts.throat or 128

    -- persistent sound output buffer
    ss.buffer = {}
    ss.bufferpos = 0
    ss.oldtimetableindex = 0

    -- mutable per-speech formant tables (SetMouthThroat modifies these)
    ss.freq1data = {}
    ss.freq2data = {}
    for i = 0, 79 do
        ss.freq1data[i] = safe(M.freq1data, i)
        ss.freq2data[i] = safe(M.freq2data, i)
    end

    -- frame arrays (256 entries, mirrors C globals)
    ss.pitches = zeroFill(255)
    ss.frequency1 = zeroFill(255)
    ss.frequency2 = zeroFill(255)
    ss.frequency3 = zeroFill(255)
    ss.amplitude1 = zeroFill(255)
    ss.amplitude2 = zeroFill(255)
    ss.amplitude3 = zeroFill(255)
    ss.sampledConsonantFlag = zeroFill(255)

    return ss
end

-- ---------------------------------------------------------------------------
-- trans() : (mem39212 * mem39213) >> 1  -- 8 bit emulation
-- ---------------------------------------------------------------------------

local function trans(mem39212, mem39213)
    local carry = 0
    local mem39214 = 0
    local mem39215 = 0
    local X = 8
    repeat
        carry = band(mem39212, 1)
        mem39212 = math.floor(mem39212 / 2)
        if carry ~= 0 then
            carry = 0
            local A = mem39215
            A = A + mem39213
            if A > 255 then carry = 1 end
            mem39215 = A % 256
        end
        local temp = band(mem39215, 1)
        mem39215 = bor(math.floor(mem39215 / 2), carry ~= 0 and 128 or 0)
        carry = temp
        X = X - 1
    until X == 0
    local temp = band(mem39214, 128)
    mem39214 = bor((mem39214 * 2) % 256, carry ~= 0 and 1 or 0)
    carry = temp
    temp = band(mem39215, 128)
    mem39215 = bor((mem39215 * 2) % 256, carry ~= 0 and 1 or 0)
    carry = temp
    return mem39215
end

-- ---------------------------------------------------------------------------
-- SetMouthThroat() : recalc formant frequencies 5..29 and 48..53
-- ---------------------------------------------------------------------------

local function setMouthThroat(ss, mouth, throat)
    local newFrequency = 0
    for pos = 5, 29 do
        local initialFrequency = safe(mouthFormants5_29, pos)
        if initialFrequency ~= 0 then newFrequency = trans(mouth, initialFrequency) end
        ss.freq1data[pos] = newFrequency
        initialFrequency = safe(throatFormants5_29, pos)
        if initialFrequency ~= 0 then newFrequency = trans(throat, initialFrequency) end
        ss.freq2data[pos] = newFrequency
    end
    local Y = 0
    for pos = 48, 53 do
        ss.freq1data[pos] = trans(mouth, safe(mouthFormants48_53, Y))
        ss.freq2data[pos] = trans(throat, safe(throatFormants48_53, Y))
        Y = Y + 1
    end
end

-- ---------------------------------------------------------------------------
-- Render()  (Code47574)
-- ---------------------------------------------------------------------------

function render.render(ss, phonemeIndexOutput, stressOutput, phonemeLengthOutput)
    if (phonemeIndexOutput[0] or 0) == 255 then return end

    local A, X, Y = 0, 0, 0
    local mem44 = 0
    local mem47 = 0
    local mem49 = 0
    local mem39 = 0
    local mem50 = 0
    local mem51 = 0
    local mem53 = 0
    local mem56 = 0
    local mem38 = 0
    local mem40 = 0
    local mem48 = 0
    local mem66 = 0
    local phase1 = 0
    local phase2 = 0
    local phase3 = 0
    local speedcounter = 0

    local TABLE = {
        [168] = ss.pitches,
        [169] = ss.frequency1,
        [170] = ss.frequency2,
        [171] = ss.frequency3,
        [172] = ss.amplitude1,
        [173] = ss.amplitude2,
        [174] = ss.amplitude3,
    }

    local function readMem(p, y)
        return safe(TABLE[p], y % 256)
    end
    local function writeMem(p, y, v)
        TABLE[p][y % 256] = v % 256
    end

    local function output8BitAry(index, ary)
        ss.bufferpos = ss.bufferpos + timetable[ss.oldtimetableindex][index]
        ss.oldtimetableindex = index
        local base = math.floor(ss.bufferpos / 50)
        for k = 0, 4 do
            ss.buffer[base + k] = ary[k]
        end
        if os.getenv("LOVESAM_TRACE") then
            io.stderr:write("O " .. tostring(index) .. " " .. tostring(ss.bufferpos) .. " " .. tostring(ss.oldtimetableindex) .. "\n")
        end
        if os.getenv("LOVESAM_DUMPARY") then
            io.stderr:write("W " .. tostring(base) .. " " .. tostring(ary[0]) .. " " .. tostring(ary[1]) .. " " .. tostring(ary[2] or 0) .. " " .. tostring(ary[3] or 0) .. " " .. tostring(ary[4] or 0) .. " " .. tostring(index) .. "\n")
        end
    end
    local function output8Bit(index, byte)
        output8BitAry(index, { [0] = byte, [1] = byte, [2] = byte, [3] = byte, [4] = byte })
    end

    -- Create a rising(1)/falling(255) inflection 30 frames prior to X.
    local function addInflection(mem48val)
        mem49 = X
        local atemp = X
        local A2 = (X - 30) % 256
        if atemp <= 30 then A2 = 0 end
        X = A2
        local A3 = readMem(168, X)
        while A3 == 127 do
            X = (X + 1) % 256
            A3 = readMem(168, X)
        end
        while true do
            A3 = (A3 + mem48val) % 256
            local ph1 = A3
            ss.pitches[X] = A3
            while true do
                X = (X + 1) % 256
                if X == mem49 then return end
                if ss.pitches[X] ~= 255 then break end
            end
            A3 = ph1
        end
    end

    -- Render a sampled sound from the sampleTable (Code48227).
    -- Uses shared upvalues: mem39, Y, mem44, mem49, mem66.
    local function renderSample()
        mem49 = Y
        A = band(mem39, 7)
        X = (A - 1) % 256
        mem56 = X
        mem53 = safe(tab48426, X)
        mem47 = X

        if band(mem39, 248) == 0 then
            -- voiced phoneme: Z*, ZH, V*, DH
            A = math.floor(safe(ss.pitches, mem49) / 16)
            local phase1v = bxor(A % 256, 255)
            Y = mem66
            repeat
                mem56 = 8
                A = safe(sampleTable, mem47 * 256 + Y)
                repeat
                    local tempA = A
                    A = (A * 2) % 256
                    if band(tempA, 128) ~= 0 then
                        X = 26
                        output8Bit(3, 160)
                    else
                        X = 6
                        output8Bit(4, 96)
                    end
                    mem56 = mem56 - 1
                until mem56 == 0
                Y = (Y + 1) % 256
                phase1v = (phase1v + 1) % 256
            until phase1v == 0
            A = 1
            mem44 = 1
            mem66 = Y
            Y = mem49
            return
        end

        -- unvoiced phoneme
        Y = bxor(band(mem39, 248), 255)
        repeat
            mem56 = 8
            A = safe(sampleTable, mem47 * 256 + Y)
            repeat
                local tempA = A
                A = (A * 2) % 256
                if band(tempA, 128) == 0 then
                    X = mem53
                    output8Bit(1, band(X, 15) * 16)
                else
                    output8Bit(2, 80)
                end
                X = 0
                mem56 = mem56 - 1
            until mem56 == 0
            Y = (Y + 1) % 256
        until Y == 0
        mem44 = 1
        Y = mem49
    end

    -- ------------------------------------------------------------------
    -- CREATE FRAMES
    -- ------------------------------------------------------------------
    A = 0
    X = 0
    mem44 = 0
    repeat
        Y = mem44
        A = safe(phonemeIndexOutput, mem44) or 0
        mem56 = A
        if A == 255 then break end

        if A == 1 then
            -- period: rising inflection
            addInflection(1)
        elseif A == 2 then
            -- question mark: falling inflection
            addInflection(255)
        end

        phase1 = safe(tab47492, safe(stressOutput, Y) + 1)
        phase2 = safe(phonemeLengthOutput, Y)
        Y = mem56

        repeat
            X = X % 256
            ss.frequency1[X] = safe(ss.freq1data, Y)
            ss.frequency2[X] = safe(ss.freq2data, Y)
            ss.frequency3[X] = safe(freq3data, Y)
            ss.amplitude1[X] = safe(ampl1data, Y)
            ss.amplitude2[X] = safe(ampl2data, Y)
            ss.amplitude3[X] = safe(ampl3data, Y)
            ss.sampledConsonantFlag[X] = safe(sampledConsonantFlags, Y)
            ss.pitches[X] = (ss.pitch + phase1) % 256
            X = (X + 1) % 256
            phase2 = (phase2 - 1) % 256
        until phase2 == 0
        mem44 = (mem44 + 1) % 256
    until mem44 == 0

    -- ------------------------------------------------------------------
    -- CREATE TRANSITIONS
    -- ------------------------------------------------------------------
    mem44 = 0
    mem49 = 0
    X = 0
    while true do
        Y = safe(phonemeIndexOutput, X)
        A = safe(phonemeIndexOutput, (X + 1) % 256)
        X = (X + 1) % 256
        if A == 255 then break end

        X = A
        mem56 = safe(blendRank, A)
        A = safe(blendRank, Y)

        if A == mem56 then
            phase1 = safe(outBlendLength, Y)
            phase2 = safe(outBlendLength, X)
        elseif A < mem56 then
            phase1 = safe(inBlendLength, X)
            phase2 = safe(outBlendLength, X)
        else
            phase1 = safe(outBlendLength, Y)
            phase2 = safe(inBlendLength, Y)
        end

        Y = mem44
        A = (mem49 + safe(phonemeLengthOutput, mem44)) % 256
        mem49 = A
        A = (A + phase2) % 256
        speedcounter = A
        mem47 = 168
        phase3 = (mem49 - phase1) % 256
        A = (phase1 + phase2) % 256
        mem38 = A

        X = (A - 2) % 256
        if band(X, 128) == 0 then
            repeat
                mem40 = mem38
                if mem47 == 168 then
                    -- pitch interpolates from center to center
                    local mem36 = math.floor(safe(phonemeLengthOutput, mem44) / 2)
                    local mem37 = math.floor(safe(phonemeLengthOutput, (mem44 + 1) % 256) / 2)
                    mem40 = (mem36 + mem37) % 256
                    mem37 = (mem37 + mem49) % 256
                    mem36 = (mem49 - mem36) % 256
                    A = readMem(mem47, mem37)
                    Y = mem36
                    mem53 = (A - readMem(mem47, mem36)) % 256
                else
                    A = readMem(mem47, speedcounter)
                    Y = phase3
                    mem53 = (A - readMem(mem47, phase3)) % 256
                end

                -- Code47503: signed difference divided by length
                local m53 = mem53
                if m53 >= 128 then m53 = m53 - 256 end
                mem50 = band(mem53, 128)
                local m53abs = math.abs(m53)
                if mem40 == 0 then
                    mem51 = 0
                    mem53 = 0
                else
                    mem51 = m53abs % mem40
                    mem53 = (cdiv(m53, mem40)) % 256
                end

                X = mem40
                Y = phase3
                mem56 = 0
                -- linearly interpolate
                while true do
                    A = (readMem(mem47, Y) + mem53) % 256
                    mem48 = A
                    Y = (Y + 1) % 256
                    X = (X - 1) % 256
                    if X == 0 then break end
                    mem56 = (mem56 + mem51) % 256
                    if mem56 >= mem40 then
                        mem56 = (mem56 - mem40) % 256
                        if band(mem50, 128) == 0 then
                            if mem48 ~= 0 then mem48 = (mem48 + 1) % 256 end
                        else
                            mem48 = (mem48 - 1) % 256
                        end
                    end
                    writeMem(mem47, Y, mem48)
                end

                mem47 = (mem47 + 1) % 256
            until mem47 == 175
        end

        mem44 = (mem44 + 1) % 256
        X = mem44
    end

    mem48 = (mem49 + safe(phonemeLengthOutput, mem44)) % 256

    -- ASSIGN PITCH CONTOUR
    if not ss.singmode then
        for i = 0, 255 do
            ss.pitches[i] = (ss.pitches[i] - math.floor(safe(ss.frequency1, i) / 2)) % 256
        end
    end

    -- RESCALE AMPLITUDE
    for i = 255, 0, -1 do
        ss.amplitude1[i] = safe(amplitudeRescale, ss.amplitude1[i])
        ss.amplitude2[i] = safe(amplitudeRescale, ss.amplitude2[i])
        ss.amplitude3[i] = safe(amplitudeRescale, ss.amplitude3[i])
    end

    phase1 = 0
    phase2 = 0
    phase3 = 0

    mem49 = 0
    speedcounter = 72

    Y = 0
    A = safe(ss.pitches, 0)
    mem44 = A
    X = A
    mem38 = (A - math.floor(A / 4)) % 256

    -- PROCESS THE FRAMES
    while true do
        A = safe(ss.sampledConsonantFlag, Y)
        mem39 = A

        local jumpedTo155 = false
        if band(A, 248) ~= 0 then
            -- unvoiced sampled phoneme
            renderSample()
            Y = (Y + 2) % 256
            mem48 = (mem48 - 2) % 256
        else
            -- glottal pulse and formants
            local p1 = phase1 * 256
            local p2 = phase2 * 256
            local p3 = phase3 * 256
            local ary = {}
            for k = 0, 4 do
                local sp1 = safe(sinus, band(math.floor(p1 / 256), 255))
                local sp2 = safe(sinus, band(math.floor(p2 / 256), 255))
                local rp3 = safe(rectangle, band(math.floor(p3 / 256), 255))
                if rp3 >= 128 then rp3 = rp3 - 256 end
                local sin1 = sp1 * band(safe(ss.amplitude1, Y), 15)
                local sin2 = sp2 * band(safe(ss.amplitude2, Y), 15)
                local rect = rp3 * band(safe(ss.amplitude3, Y), 15)
                local mux = cdiv(sin1 + sin2 + rect, 32)
                mux = (mux + 128) % 256
                ary[k] = mux
                p1 = (p1 + safe(ss.frequency1, Y) * 64) % 4294967296
                p2 = (p2 + safe(ss.frequency2, Y) * 64) % 4294967296
                p3 = (p3 + safe(ss.frequency3, Y) * 64) % 4294967296
            end
            output8BitAry(0, ary)
            speedcounter = (speedcounter - 1) % 256
            if speedcounter ~= 0 then
                jumpedTo155 = true -- goto pos48155
            else
                Y = (Y + 1) % 256
                mem48 = (mem48 - 1) % 256
            end
        end

        if not jumpedTo155 then
            if mem48 == 0 then return end
            speedcounter = ss.speed % 256
        end

        -- pos48155
        mem44 = (mem44 - 1) % 256
        if mem44 == 0 then
            -- pos48159 new glottal pulse
            A = safe(ss.pitches, Y)
            mem44 = A
            A = (A - math.floor(A / 4)) % 256
            mem38 = A
            phase1 = 0
            phase2 = 0
            phase3 = 0
        else
            mem38 = (mem38 - 1) % 256
            if mem38 ~= 0 or mem39 == 0 then
                phase1 = (phase1 + safe(ss.frequency1, Y)) % 256
                phase2 = (phase2 + safe(ss.frequency2, Y)) % 256
                phase3 = (phase3 + safe(ss.frequency3, Y)) % 256
            else
                -- voiced sampled phoneme interleave
                renderSample()
                -- goto pos48159
                A = safe(ss.pitches, Y)
                mem44 = A
                A = (A - math.floor(A / 4)) % 256
                mem38 = A
                phase1 = 0
                phase2 = 0
                phase3 = 0
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Init / getBytes
-- ---------------------------------------------------------------------------

function render.init(ss)
    setMouthThroat(ss, ss.mouth, ss.throat)
    ss.bufferpos = 0
    ss.buffer = {}
    ss.oldtimetableindex = 0
end

render.setMouthThroat = setMouthThroat

-- returns the raw samples as an array of 0..255 bytes
function render.getBytes(ss)
    local len = math.floor(ss.bufferpos / 50)
    local out = {}
    for i = 0, len - 1 do
        out[i] = ss.buffer[i] or 0
    end
    out.n = len
    return out
end

return render
