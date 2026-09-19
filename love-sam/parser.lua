--[[ LOVE-SAM: phoneme parser (port of sam.c: Parser1, Parser2, CopyStress,
     SetPhonemeLength, AdjustLengths, Code41240, InsertBreath, PrepareOutput). ]]

local M = require("love-sam.tables")
local band = M.band
local bor = M.bor

local signInputTable1 = M.signInputTable1
local signInputTable2 = M.signInputTable2
local stressInputTable = M.stressInputTable
local flags = M.flags
local flags2 = M.flags2
local phonemeLengthTable = M.phonemeLengthTable
local phonemeStressedLengthTable = M.phonemeStressedLengthTable

local function safe(t, i)
    return t[i] or 0
end

local parser = {}

function parser.newState()
    local state = {}
    local function zerofill(n)
        local t = {}
        for i = 0, n do t[i] = 0 end
        return t
    end
    state.stress = zerofill(255)
    state.phonemeLength = zerofill(255)
    state.phonemeindex = zerofill(255)
    state.phonemeIndexOutput = zerofill(59)
    state.stressOutput = zerofill(59)
    state.phonemeLengthOutput = zerofill(59)
    return state
end

function parser.samMain(state, inputBytes)
    local input = inputBytes

    local stress = state.stress
    local phonemeLength = state.phonemeLength
    local phonemeindex = state.phonemeindex
    local phonemeIndexOutput = state.phonemeIndexOutput
    local stressOutput = state.stressOutput
    local phonemeLengthOutput = state.phonemeLengthOutput

    local A = 0
    local X = 0
    local Y = 0
    local mem59 = 0

    local function insert(position, mem60, mem59v, mem58)
        for i = 253, position, -1 do
            phonemeindex[i + 1] = phonemeindex[i]
            phonemeLength[i + 1] = phonemeLength[i]
            stress[i + 1] = stress[i]
        end
        phonemeindex[position] = mem60
        phonemeLength[position] = mem59v
        stress[position] = mem58
    end

    local function tail41749(pos, Xv, Ac, includeUW)
        local A2 = Ac
        if includeUW then
            A2 = phonemeindex[Xv]
            if A2 == 53 then
                Y = safe(phonemeindex, (Xv - 1) % 256)
                A2 = band(safe(flags2, Y), 4)
                if A2 == 0 then return pos + 1 end
                phonemeindex[Xv] = 16
                return pos + 1
            end
        end
        if A2 == 42 then
            insert((Xv + 1) % 256, (A2 + 1) % 256, mem59, stress[Xv])
            return pos + 1
        end
        if A2 == 44 then
            insert((Xv + 1) % 256, (A2 + 1) % 256, mem59, stress[Xv])
            return pos + 1
        end
        if A2 ~= 69 and A2 ~= 57 then return pos + 1 end
        if band(safe(flags, safe(phonemeindex, (Xv - 1) % 256)), 128) == 0 then return pos + 1 end
        local X2 = (Xv + 1) % 256
        local A3 = phonemeindex[X2]
        if A3 ~= 0 then
            if band(safe(flags, A3), 128) == 0 then return pos + 1 end
            if stress[X2] ~= 0 then return pos + 1 end
            phonemeindex[pos] = 30
        else
            local A4 = safe(phonemeindex, (X2 + 1) % 256)
            if A4 == 255 then
                A4 = 0
            else
                A4 = band(safe(flags, A4), 128)
            end
            if A4 ~= 0 then phonemeindex[pos] = 30 end
        end
        return pos + 1
    end

    local function parser2()
        local pos = 0
        while true do
            X = pos
            A = phonemeindex[pos]
            if A == 0 then
                pos = (pos + 1) % 256
            elseif A == 255 then
                return
            else
                Y = A
                if band(safe(flags, A), 16) ~= 0 then
                    local mem58 = stress[pos]
                    A = band(safe(flags, Y), 32)
                    if A == 0 then A = 20 else A = 21 end
                    insert((pos + 1) % 256, A, mem59, mem58)
                    X = pos
                    pos = tail41749(pos, X, 0, true)
                else
                    local handled = false
                    A = phonemeindex[X]
                    if A == 78 then
                        A = 24
                        handled = true
                    elseif A == 79 then
                        A = 27
                        handled = true
                    elseif A == 80 then
                        A = 28
                        handled = true
                    end
                    if handled then
                        local mem58 = stress[X]
                        phonemeindex[X] = 13
                        insert((X + 1) % 256, A, mem59, mem58)
                        pos = (pos + 1) % 256
                    else
                        Y = A
                        if band(safe(flags, A), 128) ~= 0 then
                            A = stress[X]
                            if A ~= 0 then
                                X = (X + 1) % 256
                                A = phonemeindex[X]
                                if A == 0 then
                                    X = (X + 1) % 256
                                    Y = phonemeindex[X]
                                    if Y == 255 then
                                        A = 0
                                    else
                                        A = band(safe(flags, Y), 128)
                                    end
                                    if A ~= 0 then
                                        A = stress[X]
                                        if A ~= 0 then
                                            insert(X, 31, mem59, 0)
                                            pos = (pos + 1) % 256
                                            handled = true
                                        end
                                    end
                                end
                            end
                        end
                        if not handled then
                            X = pos
                            A = phonemeindex[pos]
                            if A == 23 then
                                X = (pos - 1) % 256
                                A = safe(phonemeindex, (pos - 1) % 256)
                                if A == 69 then
                                    phonemeindex[(pos - 1) % 256] = 42
                                    pos = tail41749(pos, X, 0, false)
                                elseif A == 57 then
                                    phonemeindex[(pos - 1) % 256] = 44
                                    pos = tail41749(pos, X, 0, false)
                                else
                                    A = band(safe(flags, A), 128)
                                    if A ~= 0 then phonemeindex[pos] = 18 end
                                    pos = (pos + 1) % 256
                                end
                            elseif A == 24 then
                                if band(safe(flags, safe(phonemeindex, (pos - 1) % 256)), 128) == 0 then
                                    pos = (pos + 1) % 256
                                else
                                    phonemeindex[X] = 19
                                    pos = (pos + 1) % 256
                                end
                            elseif A == 32 then
                                if safe(phonemeindex, (pos - 1) % 256) ~= 60 then
                                    pos = (pos + 1) % 256
                                else
                                    phonemeindex[pos] = 38
                                    pos = (pos + 1) % 256
                                end
                            elseif A == 72 then
                                Y = safe(phonemeindex, (pos + 1) % 256)
                                if Y == 255 then
                                    phonemeindex[pos] = 75
                                else
                                    A = band(safe(flags, Y), 32)
                                    if A == 0 then phonemeindex[pos] = 75 end
                                end
                                Y = phonemeindex[pos]
                                A = band(safe(flags, Y), 1)
                                if A == 0 then
                                    pos = tail41749(pos, X, 0, true)
                                else
                                    A = safe(phonemeindex, (pos - 1) % 256)
                                    if A ~= 32 then
                                        A = Y
                                        pos = tail41749(pos, X, Y, false)
                                    else
                                        phonemeindex[pos] = (Y - 12) % 256
                                        pos = (pos + 1) % 256
                                    end
                                end
                            elseif A == 60 then
                                local idx = safe(phonemeindex, (pos + 1) % 256)
                                if idx == 255 then
                                    pos = (pos + 1) % 256
                                elseif band(safe(flags, idx), 32) ~= 0 then
                                    pos = (pos + 1) % 256
                                else
                                    phonemeindex[pos] = 63
                                    pos = (pos + 1) % 256
                                end
                            else
                                Y = phonemeindex[pos]
                                A = band(safe(flags, Y), 1)
                                if A == 0 then
                                    pos = tail41749(pos, X, 0, true)
                                else
                                    A = safe(phonemeindex, (pos - 1) % 256)
                                    if A ~= 32 then
                                        A = Y
                                        pos = tail41749(pos, X, Y, false)
                                    else
                                        phonemeindex[pos] = (Y - 12) % 256
                                        pos = (pos + 1) % 256
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local function copyStress()
        local pos = 0
        while true do
            Y = phonemeindex[pos]
            if Y == 255 then return end
            if band(safe(flags, Y), 64) == 0 then
                pos = (pos + 1) % 256
            else
                Y = phonemeindex[(pos + 1) % 256]
                if Y == 255 then
                    pos = (pos + 1) % 256
                elseif band(safe(flags, Y), 128) == 0 then
                    pos = (pos + 1) % 256
                else
                    Y = stress[(pos + 1) % 256]
                    if Y == 0 then
                        pos = (pos + 1) % 256
                    elseif band(Y, 128) ~= 0 then
                        pos = (pos + 1) % 256
                    else
                        stress[pos] = (Y + 1) % 256
                        pos = (pos + 1) % 256
                    end
                end
            end
        end
    end

    local function setPhonemeLength()
        local position = 0
        while phonemeindex[position] ~= 255 do
            local a = stress[position]
            if a == 0 or band(a, 128) ~= 0 then
                phonemeLength[position] = safe(phonemeLengthTable, phonemeindex[position])
            else
                phonemeLength[position] = safe(phonemeStressedLengthTable, phonemeindex[position])
            end
            position = position + 1
        end
    end

    local function adjustLengths()
        X = 0
        local index = 0
        local loopIndex = 0
        local pass1Done = false
        while not pass1Done do
            index = phonemeindex[X]
            if index == 255 then break end
            if band(safe(flags2, index), 1) == 0 then
                X = (X + 1) % 256
            else
                loopIndex = X
                local exited = false
                while true do
                    X = (X - 1) % 256
                    if X == 0 then
                        exited = true
                        break
                    end
                    index = phonemeindex[X]
                    if index ~= 255 and band(safe(flags, index), 128) == 0 then
                        -- keep scanning backwards
                    else
                        break
                    end
                end
                if exited then
                    pass1Done = true
                else
                    while true do
                        index = phonemeindex[X]
                        if index ~= 255 then
                            if band(safe(flags2, index), 32) == 0 or band(safe(flags, index), 4) ~= 0 then
                                A = safe(phonemeLength, X)
                                A = (math.floor(A / 2)) + A + 1
                                phonemeLength[X] = A % 256
                            end
                        end
                        X = (X + 1) % 256
                        if X == loopIndex then break end
                    end
                    X = (X + 1) % 256
                end
            end
        end

        loopIndex = 0
        while true do
            X = loopIndex
            index = phonemeindex[X]
            if index == 255 then return end
            A = band(safe(flags, index), 128)
            if A ~= 0 then
                X = (X + 1) % 256
                index = phonemeindex[X]
                local mem56
                if index == 255 then
                    mem56 = 65
                else
                    mem56 = safe(flags, index)
                end
                if band(safe(flags, index), 64) == 0 then
                    if index == 18 or index == 19 then
                        X = (X + 1) % 256
                        index = phonemeindex[X]
                        if band(safe(flags, index), 64) ~= 0 then
                            phonemeLength[loopIndex] = (phonemeLength[loopIndex] - 1) % 256
                        end
                        loopIndex = (loopIndex + 1) % 256
                    else
                        loopIndex = (loopIndex + 1) % 256
                    end
                elseif band(mem56, 4) == 0 then
                    if band(mem56, 1) == 0 then
                        loopIndex = (loopIndex + 1) % 256
                    else
                        X = (X - 1) % 256
                        mem56 = math.floor(phonemeLength[X] / 8)
                        phonemeLength[X] = (phonemeLength[X] - mem56) % 256
                        loopIndex = (loopIndex + 1) % 256
                    end
                else
                    A = safe(phonemeLength, (X - 1) % 256)
                    phonemeLength[(X - 1) % 256] = ((math.floor(A / 4)) + A + 1) % 256
                    loopIndex = (loopIndex + 1) % 256
                end
            elseif band(safe(flags2, index), 8) ~= 0 then
                X = (X + 1) % 256
                index = phonemeindex[X]
                local A2
                if index == 255 then
                    A2 = 0
                else
                    A2 = band(safe(flags, index), 2)
                end
                if A2 ~= 0 then
                    phonemeLength[X] = 6
                    phonemeLength[(X - 1) % 256] = 5
                end
                loopIndex = (loopIndex + 1) % 256
            elseif band(safe(flags, index), 2) ~= 0 then
                repeat
                    X = (X + 1) % 256
                    index = phonemeindex[X]
                until index ~= 0
                if index == 255 then
                    loopIndex = (loopIndex + 1) % 256
                elseif band(safe(flags, index), 2) == 0 then
                    loopIndex = (loopIndex + 1) % 256
                else
                    phonemeLength[X] = ((math.floor(phonemeLength[X] / 2)) + 1) % 256
                    X = loopIndex
                    phonemeLength[loopIndex] = ((math.floor(phonemeLength[loopIndex] / 2)) + 1) % 256
                    loopIndex = (loopIndex + 1) % 256
                end
            elseif band(safe(flags2, index), 16) ~= 0 then
                local liquid = safe(phonemeindex, (X - 1) % 256)
                if band(safe(flags, liquid), 2) ~= 0 then
                    phonemeLength[X] = (phonemeLength[X] - 2) % 256
                end
                loopIndex = (loopIndex + 1) % 256
            else
                loopIndex = (loopIndex + 1) % 256
            end
        end
    end

    local function code41240()
        local pos = 0
        while phonemeindex[pos] ~= 255 do
            local index = phonemeindex[pos]
            X = pos
            if band(safe(flags, index), 2) == 0 then
                pos = (pos + 1) % 256
            elseif band(safe(flags, index), 1) == 0 then
                insert((pos + 1) % 256, (index + 1) % 256, safe(phonemeLengthTable, (index + 1) % 256), stress[pos])
                insert((pos + 2) % 256, (index + 2) % 256, safe(phonemeLengthTable, (index + 2) % 256), stress[pos])
                pos = (pos + 3) % 256
            else
                repeat
                    X = (X + 1) % 256
                    A = phonemeindex[X]
                until A ~= 0
                local doInsert = true
                if A ~= 255 then
                    if band(safe(flags, A), 8) ~= 0 then
                        pos = (pos + 1) % 256
                        doInsert = false
                    elseif A == 36 or A == 37 then
                        pos = (pos + 1) % 256
                        doInsert = false
                    end
                end
                if doInsert then
                    insert((pos + 1) % 256, (index + 1) % 256, safe(phonemeLengthTable, (index + 1) % 256), stress[pos])
                    insert((pos + 2) % 256, (index + 2) % 256, safe(phonemeLengthTable, (index + 2) % 256), stress[pos])
                    pos = (pos + 3) % 256
                end
            end
        end
    end

    local function insertBreath()
        local mem54 = 255
        X = (X + 1) % 256
        local mem55 = 0
        local mem66 = 0
        while true do
            X = mem66
            local index = phonemeindex[X]
            if index == 255 then return end
            mem55 = (mem55 + phonemeLength[X]) % 256
            if mem55 < 232 then
                if index ~= 254 then
                    A = band(safe(flags2, index), 1)
                    if A ~= 0 then
                        X = (X + 1) % 256
                        mem55 = 0
                        insert(X, 254, mem59, 0)
                        mem66 = (mem66 + 2) % 256
                    else
                        if index == 0 then mem54 = X end
                        mem66 = (mem66 + 1) % 256
                    end
                else
                    if index == 0 then mem54 = X end
                    mem66 = (mem66 + 1) % 256
                end
            else
                X = mem54
                phonemeindex[X] = 31
                phonemeLength[X] = 4
                stress[X] = 0
                X = (X + 1) % 256
                mem55 = 0
                insert(X, 254, mem59, 0)
                X = (X + 1) % 256
                mem66 = X
            end
        end
    end

    local function prepareOutput()
        A = 0
        X = 0
        Y = 0
        while true do
            A = phonemeindex[X]
            if A == 255 then
                phonemeIndexOutput[Y] = 255
                state.render(state)
                return
            elseif A == 254 then
                X = (X + 1) % 256
                local temp = X
                phonemeIndexOutput[Y] = 255
                state.render(state)
                X = temp
                Y = 0
            elseif A == 0 then
                X = (X + 1) % 256
            else
                phonemeIndexOutput[Y] = A
                phonemeLengthOutput[Y] = phonemeLength[X]
                stressOutput[Y] = stress[X]
                X = (X + 1) % 256
                Y = (Y + 1) % 256
            end
        end
    end

    local function parser1()
        local sign1
        local sign2
        local position = 0
        X = 0
        A = 0
        Y = 0
        for i = 0, 255 do stress[i] = 0 end
        while true do
            sign1 = safe(input, X)
            if sign1 == 155 then
                phonemeindex[position] = 255
                return 1
            end
            X = (X + 1) % 256
            sign2 = safe(input, X)

            local handled = false
            local Yt = 0
            while Yt ~= 81 do
                if safe(signInputTable1, Yt) == sign1 and safe(signInputTable2, Yt) ~= 42 and safe(signInputTable2, Yt) == sign2 then
                    phonemeindex[position] = Yt
                    position = position + 1
                    X = (X + 1) % 256
                    handled = true
                    break
                end
                Yt = Yt + 1
            end

            if not handled then
                local Yw = 0
                while Yw ~= 81 do
                    if safe(signInputTable2, Yw) == 42 and safe(signInputTable1, Yw) == sign1 then
                        phonemeindex[position] = Yw
                        position = position + 1
                        handled = true
                        break
                    end
                    Yw = Yw + 1
                end
            end

            if not handled then
                Y = 8
                while (sign1 ~= safe(stressInputTable, Y)) and (Y > 0) do
                    Y = Y - 1
                end
                if Y == 0 then return 0 end
                stress[(position - 1) % 256] = Y
            end
        end
    end

    -- Init
    for i = 0, 255 do
        stress[i] = 0
        phonemeLength[i] = 0
    end
    for i = 0, 59 do
        phonemeIndexOutput[i] = 0
        stressOutput[i] = 0
        phonemeLengthOutput[i] = 0
    end
    phonemeindex[255] = 32

    -- SAMMain
    if parser1() == 0 then return false end
    parser2()
    copyStress()
    setPhonemeLength()
    adjustLengths()
    code41240()

    repeat
        A = phonemeindex[X]
        if A > 80 then
            phonemeindex[X] = 255
            break
        end
        X = (X + 1) % 256
    until X == 0

    insertBreath()
    prepareOutput()
    return true
end

return parser