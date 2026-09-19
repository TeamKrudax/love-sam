--[[ LOVE-SAM
  Text-to-Phoneme converter.
  Verbatim port of sam-ref/src/reciter.c TextToPhonemes (SAM, public domain).
  Uses the byte tables regenerated into reciterTabs.lua, so rule lookups and
  outputs are byte-identical to the reference C reciter.
]]

local tabs    = require("love-sam.reciterTabs")
local tables  = require("love-sam.tables")

local band    = tables.band

local tab36376 = tabs.tab36376
local rules    = tabs.rules
local rules2   = tabs.rules2
local tab37489 = tabs.tab37489
local tab37515 = tabs.tab37515

local reciter = {}

-- C globals: A, X, Y and the mem* scratch registers (all unsigned char in C).
local A, X, Y
local mem56, mem57, mem58, mem59, mem60, mem61, mem62, mem64, mem65, mem66

-- inputtemp = secure copy of the input; input = the C input[] buffer model
-- (holds the phoneme output exactly where the C code wrote it, so the final
-- length can be mirrored from the C strlen()).
local inputtemp = {}
local input = {}

local function getRuleByte(m, yy)
    if m >= 37541 then
        return rules2[(m - 37541) + yy + 1] or 0
    end
    return rules[(m - 32000) + yy + 1] or 0
end

-- Code37055: peek the inputtemp byte before mem59-1 and read its tab36376 flag.
local function code37055(mem59)
    X = (mem59 - 1) % 256
    A = inputtemp[X]
    Y = A
    A = tab36376[Y + 1] or 0
end

-- Code37066: peek the inputtemp byte after mem58 and read its tab36376 flag.
local function code37066(mem58)
    X = (mem58 + 1) % 256
    A = inputtemp[X]
    Y = A
    A = tab36376[Y + 1] or 0
end

local handlers = {}

handlers.pos36554 = function()
    while true do
        mem61 = (mem61 + 1) % 256
        X = mem61
        A = inputtemp[X]
        mem64 = A
        if A == 91 then -- '['
            mem56 = (mem56 + 1) % 256
            X = mem56
            input[X] = 155
            return "done"
        end
        if A ~= 46 then break end -- '.'
        X = (X + 1) % 256
        Y = inputtemp[X]
        A = band(tab36376[Y + 1] or 0, 1)
        if A ~= 0 then break end
        mem56 = (mem56 + 1) % 256
        X = mem56
        input[X] = 46
    end

    -- pos36607
    A = mem64
    Y = A
    A = tab36376[A + 1] or 0
    mem57 = A
    if band(A, 2) ~= 0 then
        mem62 = 37541
        return "pos36700"
    end

    -- pos36630
    A = mem57
    if A ~= 0 then return "pos36677" end

    A = 32
    inputtemp[X] = 32
    mem56 = (mem56 + 1) % 256
    X = mem56
    if X > 120 then return "pos36654" end
    input[X] = A
    return "pos36554"
end

handlers.pos36654 = function()
    input[X] = 155
    return "done"
end

handlers.pos36677 = function()
    A = band(mem57, 128)
    if A == 0 then return "failed" end
    X = (mem64 - 65) % 256
    mem62 = (tab37489[X + 1] or 0) + (tab37515[X + 1] or 0) * 256
    return "pos36700"
end

handlers.pos36700 = function()
    Y = 0
    repeat
        mem62 = (mem62 + 1) % 65536
        A = getRuleByte(mem62, Y)
    until band(A, 128) ~= 0
    Y = (Y + 1) % 256

    while true do
        A = getRuleByte(mem62, Y)
        if A == 40 then break end -- '('
        Y = (Y + 1) % 256
    end
    mem66 = Y

    repeat
        Y = (Y + 1) % 256
        A = getRuleByte(mem62, Y)
    until A == 41 -- ')'
    mem65 = Y

    repeat
        Y = (Y + 1) % 256
        A = band(getRuleByte(mem62, Y), 127)
    until A == 61 -- '='
    mem64 = Y

    X = mem61
    mem60 = X

    Y = (mem66 + 1) % 256
    while true do
        mem57 = inputtemp[X]
        A = getRuleByte(mem62, Y)
        if A ~= mem57 then return "pos36700" end
        Y = (Y + 1) % 256
        if Y == mem65 then break end
        X = (X + 1) % 256
        mem60 = X
    end

    -- pos36787
    mem59 = mem61
    return "pos36791"
end

handlers.pos36791 = function()
    while true do
        mem66 = (mem66 - 1) % 256
        Y = mem66
        A = getRuleByte(mem62, Y)
        mem57 = A
        if band(A, 128) ~= 0 then return "pos37180" end
        X = band(A, 127)
        A = band(tab36376[X + 1] or 0, 128)
        if A == 0 then break end
        X = (mem59 - 1) % 256
        A = inputtemp[X]
        if A ~= mem57 then return "pos36700" end
        mem59 = X
    end

    -- pos36833
    A = mem57
    if A == 32 then return "pos36895" end
    if A == 35 then return "pos36910" end
    if A == 46 then return "pos36920" end
    if A == 38 then return "pos36935" end
    if A == 64 then return "pos36967" end
    if A == 94 then return "pos37004" end
    if A == 43 then return "pos37019" end
    if A == 58 then return "pos37040" end
    return "failed"
end

handlers.pos36895 = function()
    code37055(mem59)
    A = band(A, 128)
    if A ~= 0 then return "pos36700" end
    return "pos36905"
end

handlers.pos36905 = function()
    mem59 = X
    return "pos36791"
end

handlers.pos36910 = function()
    code37055(mem59)
    A = band(A, 64)
    if A ~= 0 then return "pos36905" end
    return "pos36700"
end

handlers.pos36920 = function()
    code37055(mem59)
    A = band(A, 8)
    if A == 0 then return "pos36700" end
    return "pos36930"
end

handlers.pos36930 = function()
    mem59 = X
    return "pos36791"
end

handlers.pos36935 = function()
    code37055(mem59)
    A = band(A, 16)
    if A ~= 0 then return "pos36930" end
    A = inputtemp[X]
    if A ~= 72 then return "pos36700" end
    X = (X - 1) % 256
    A = inputtemp[X]
    if A == 67 or A == 83 then return "pos36930" end
    return "pos36700"
end

handlers.pos36967 = function()
    code37055(mem59)
    A = band(A, 4)
    if A ~= 0 then return "pos36930" end
    A = inputtemp[X]
    if A ~= 72 then return "pos36700" end
    -- sam-ref/src/reciter.c omits the X++ before the T/C/S check that upstream
    -- SAM has; reproduced verbatim so output stays byte-identical to recit.exe.
    if A ~= 84 and A ~= 67 and A ~= 83 then return "pos36700" end
    mem59 = X
    return "pos36791"
end

handlers.pos37004 = function()
    code37055(mem59)
    A = band(A, 32)
    if A == 0 then return "pos36700" end
    return "pos37014"
end

handlers.pos37014 = function()
    mem59 = X
    return "pos36791"
end

handlers.pos37019 = function()
    X = (mem59 - 1) % 256
    A = inputtemp[X]
    if A == 69 or A == 73 or A == 89 then return "pos37014" end
    return "pos36700"
end

handlers.pos37040 = function()
    while true do
        code37055(mem59)
        A = band(A, 32)
        if A == 0 then return "pos36791" end
        mem59 = X
    end
end

handlers.pos37077 = function()
    X = (mem58 + 1) % 256
    A = inputtemp[X]
    if A ~= 69 then return "pos37157" end -- 'E'
    X = (X + 1) % 256
    Y = inputtemp[X]
    X = (X - 1) % 256
    A = band(tab36376[Y + 1] or 0, 128)
    if A == 0 then return "pos37108" end
    X = (X + 1) % 256
    A = inputtemp[X]
    if A ~= 82 then return "pos37113" end -- 'R'
    return "pos37108"
end

handlers.pos37108 = function()
    mem58 = X
    return "pos37184"
end

handlers.pos37113 = function()
    if A == 83 or A == 68 then return "pos37108" end -- 'S' 'D'
    if A ~= 76 then return "pos37135" end -- 'L'
    X = (X + 1) % 256
    A = inputtemp[X]
    if A ~= 89 then return "pos36700" end -- 'Y'
    return "pos37108"
end

handlers.pos37135 = function()
    if A ~= 70 then return "pos36700" end -- 'F'
    X = (X + 1) % 256
    A = inputtemp[X]
    if A ~= 85 then return "pos36700" end -- 'U'
    X = (X + 1) % 256
    A = inputtemp[X]
    if A == 76 then return "pos37108" end -- 'L'
    return "pos36700"
end

handlers.pos37157 = function()
    if A ~= 73 then return "pos36700" end -- 'I'
    X = (X + 1) % 256
    A = inputtemp[X]
    if A ~= 78 then return "pos36700" end -- 'N'
    X = (X + 1) % 256
    A = inputtemp[X]
    if A == 71 then return "pos37108" end -- 'G'
    return "pos36700"
end

handlers.pos37180 = function()
    mem58 = mem60
    return "pos37184"
end

handlers.pos37184 = function()
    while true do
        Y = (mem65 + 1) % 256
        if Y == mem64 then return "pos37455" end
        mem65 = Y
        A = getRuleByte(mem62, Y)
        mem57 = A
        X = A
        A = band(tab36376[X + 1] or 0, 128)
        if A == 0 then return "pos37226" end
        X = (mem58 + 1) % 256
        A = inputtemp[X]
        if A ~= mem57 then return "pos36700" end
        mem58 = X
    end
end

handlers.pos37226 = function()
    A = mem57
    if A == 32 then return "pos37295" end
    if A == 35 then return "pos37310" end
    if A == 46 then return "pos37320" end
    if A == 38 then return "pos37335" end
    if A == 64 then return "pos37367" end
    if A == 94 then return "pos37404" end
    if A == 43 then return "pos37419" end
    if A == 58 then return "pos37440" end
    if A == 37 then return "pos37077" end -- '%'
    return "failed"
end

handlers.pos37295 = function()
    code37066(mem58)
    A = band(A, 128)
    if A ~= 0 then return "pos36700" end
    return "pos37305"
end

handlers.pos37305 = function()
    mem58 = X
    return "pos37184"
end

handlers.pos37310 = function()
    code37066(mem58)
    A = band(A, 64)
    if A ~= 0 then return "pos37305" end
    return "pos36700"
end

handlers.pos37320 = function()
    code37066(mem58)
    A = band(A, 8)
    if A == 0 then return "pos36700" end
    return "pos37330"
end

handlers.pos37330 = function()
    mem58 = X
    return "pos37184"
end

handlers.pos37335 = function()
    code37066(mem58)
    A = band(A, 16)
    if A ~= 0 then return "pos37330" end
    A = inputtemp[X]
    if A ~= 72 then return "pos36700" end
    X = (X + 1) % 256
    A = inputtemp[X]
    if A == 67 or A == 83 then return "pos37330" end
    return "pos36700"
end

handlers.pos37367 = function()
    code37066(mem58)
    A = band(A, 4)
    if A ~= 0 then return "pos37330" end
    A = inputtemp[X]
    if A ~= 72 then return "pos36700" end
    -- same sam-ref transcription quirk as the back-context '@' handler above.
    if A ~= 84 and A ~= 67 and A ~= 83 then return "pos36700" end
    mem58 = X
    return "pos37184"
end

handlers.pos37404 = function()
    code37066(mem58)
    A = band(A, 32)
    if A == 0 then return "pos36700" end
    return "pos37414"
end

handlers.pos37414 = function()
    mem58 = X
    return "pos37184"
end

handlers.pos37419 = function()
    X = (mem58 + 1) % 256
    A = inputtemp[X]
    if A == 69 or A == 73 or A == 89 then return "pos37414" end
    return "pos36700"
end

handlers.pos37440 = function()
    while true do
        code37066(mem58)
        A = band(A, 32)
        if A == 0 then return "pos37184" end
        mem58 = X
    end
end

handlers.pos37455 = function()
    Y = mem64
    mem61 = mem60
    return "pos37461"
end

handlers.pos37461 = function()
    while true do
        A = getRuleByte(mem62, Y)
        mem57 = A
        A = band(A, 127)
        if A ~= 61 then -- '='
            mem56 = (mem56 + 1) % 256
            X = mem56
            input[X] = A
        end
        if band(mem57, 128) ~= 0 then return "pos36554" end
        Y = (Y + 1) % 256
    end
end

local function run()
    local state = "pos36554"
    while state ~= "done" and state ~= "failed" do
        state = handlers[state]()
    end
    return state == "done"
end

--[[ translate(text) -> byte array or nil
   Mirrors the reference pipeline (recit.c + TextToPhonemes + strlen):
   ASCII-uppercase the text, append '[' as the end marker, run the rule
   engine, and return exactly the bytes that the C strlen() would have
   written. The returned table is 0-indexed with .n set.
]]
function reciter.translate(text)
    local n = 0
    for i = 1, #text do
        local b = string.byte(text, i)
        if b >= 97 and b <= 122 then b = b - 32 end
        input[i - 1] = b
        n = i
    end
    input[n] = 91 -- '['
    for i = n + 1, 255 do input[i] = 0 end

    inputtemp[0] = 32
    X = 1
    Y = 0
    repeat
        A = band(input[Y], 127)
        if A >= 112 then
            A = band(A, 95)
        elseif A >= 96 then
            A = band(A, 79)
        end
        inputtemp[X] = A
        X = X + 1
        Y = Y + 1
    until Y == 255
    inputtemp[255] = 27

    mem61 = 255
    mem56 = 255

    if not run() then return nil end

    local len = 256
    for i = 0, 255 do
        if input[i] == 0 then len = i break end
    end

    local out = {}
    for i = 0, len - 1 do out[i] = input[i] end
    out.n = len
    return out
end

return reciter