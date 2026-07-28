-- Drive the desktop and check what it did.
--
-- Assertions are made against the OS's own variables, not against pixels.
-- Those variables are Forth words created at run time, so they have no fixed
-- address; this walks the dictionary the same way FIND does and works out
-- where a VARIABLE's cell lives:
--
--   header: link(2) bucketlink(2) len|flags(1) name(len) then the code field,
--   and a VARIABLE's code field is JSR DOVAR, so its cell is 3 bytes further.
--
-- Steps come from the TEST environment variable, one per line:
--
--   point X Y        put the pointer there through the game port
--   click            press and release the game port button
--   key C            post a character
--   wait N           idle for N frames
--   shot             take a snapshot
--   check VAR VALUE  assert a Forth variable equals a value
--   show VAR         print a variable without asserting

local LATESTV = tonumber(os.getenv("LATESTV") or "0")
local READY   = tonumber(os.getenv("READYMAX") or "5400")
local SCRIPT  = os.getenv("TEST") or ""
-- Assembly symbols, passed in as NAME=ADDR pairs.  Some things the tests care
-- about are kernel variables rather than Forth ones -- the pointer position is
-- read through a word, not stored in a dictionary cell.
local SYMS = {}
for pair in (os.getenv("SYMS") or ""):gmatch("[^,]+") do
    local n, a = pair:match("(%w+)=(%d+)")
    if n then SYMS[n] = tonumber(a) end
end

local mem, frames, phase = nil, 0, "wait"
local steps, at, timer = {}, 1, 0
local passes, failures = 0, 0
local fx, fy, btn
-- A value written to an ioport field does not necessarily stay written, so
-- the wanted state is held here and reapplied every frame.  Without that a
-- click lands or is missed depending on which frame it fell on, which looked
-- exactly like the OS dropping clicks.
local wantx, wanty, wantbtn = 128, 128, 0

for line in SCRIPT:gmatch("[^\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" then steps[#steps+1] = line end
end

local function w(a) return mem:read_u8(a) | (mem:read_u8(a+1) << 8) end

-- Find a VARIABLE's cell by walking the definition chain.  The chain is
-- walked before the dictionary necessarily exists, so every link is bounds
-- checked rather than trusted.
local function varaddr(name)
    local p = w(LATESTV)
    local guard = 0
    while p ~= 0 do
        guard = guard + 1
        if guard > 4000 or p < 0x4000 or p > 0xBEFF then return nil end
        local len = mem:read_u8(p + 4) & 0x3F
        local s = ""
        for i = 0, len - 1 do s = s .. string.char(mem:read_u8(p + 5 + i)) end
        if s == name then return p + 5 + len + 3 end
        p = w(p)
    end
end

local function field(which)
    for tag, port in pairs(manager.machine.ioport.ports) do
        if tag:find("joystick_1_" .. which) then
            for _, f in pairs(port.fields) do
                if f.is_analog then return f end
            end
        end
    end
end

local function button()
    for tag, port in pairs(manager.machine.ioport.ports) do
        if tag:find("joystick_buttons") then
            for name, f in pairs(port.fields) do
                if name == "P1 Button 1" then return f end
            end
        end
    end
end

local function report(ok, text)
    if ok then passes = passes + 1 print("PASS " .. text)
    else failures = failures + 1 print("FAIL " .. text) end
end

-- Signed 16-bit, since -1 is how Forth spells true.
local function signed(v) return v >= 0x8000 and v - 0x10000 or v end

local function run(step)
    local op, rest = step:match("^(%S+)%s*(.*)$")
    if op == "point" then
        local x, y = rest:match("(%-?%d+)%s+(%-?%d+)")
        -- MREAD makes x 17/8 of the paddle and y 3/4 of it
        wantx = math.floor(tonumber(x) * 8 / 17)
        wanty = math.floor(tonumber(y) * 4 / 3)
        timer = 150                     -- both axes read on alternate passes
    elseif op == "click" then
        wantbtn = 1; timer = 30
    elseif op == "unclick" then
        wantbtn = 0; timer = 30
    elseif op == "key" then
        manager.machine.natkeyboard:post(rest); timer = 60
    elseif op == "wait" then
        timer = tonumber(rest)
    elseif op == "shot" then
        manager.machine.video:snapshot(); timer = 2
    -- WINS is a CREATE word, so its data field sits where a VARIABLE's cell
    -- would: that is the window array, ten bytes a record.
    elseif op == "checkwin" then
        local idx, fld, want, tol = rest:match("(%d+)%s+(%w+)%s+(%-?%d+)%s*(%d*)")
        tol = tonumber(tol) or 0
        local off = ({X1 = 0, X2 = 2, Y1 = 4, Y2 = 6})[fld]
        local base = varaddr("WINS")
        if not base or not off then
            report(false, "cannot reach window " .. rest)
        else
            local got = signed(w(base + tonumber(idx) * 10 + off))
            report(math.abs(got - tonumber(want)) <= tol,
                   string.format("win%s.%s = %d (wanted %s+-%d)",
                                 idx, fld, got, want, tol))
        end
        timer = 2
    elseif op == "checka" or op == "checkab" then
        -- An optional third number is a tolerance.  The pointer is quantised
        -- by the paddle, so asking for an exact pixel is asking too much.
        local name, want, tol = rest:match("(%S+)%s+(%-?%d+)%s*(%d*)")
        tol = tonumber(tol) or 0
        local a = SYMS[name]
        if not a then report(false, name .. " is not a known symbol")
        else
            local got = (op == "checkab") and mem:read_u8(a) or signed(w(a))
            report(math.abs(got - tonumber(want)) <= tol,
                   string.format("%s = %d (wanted %s+-%d)", name, got, want, tol))
        end
        timer = 2
    elseif op == "showa" or op == "showab" then
        local a = SYMS[rest]
        local v = a and (op == "showab" and mem:read_u8(a) or signed(w(a)))
        print(string.format("     %s = %s", rest, v and tostring(v) or "?"))
        timer = 2
    elseif op == "check" then
        local name, want = rest:match("(%S+)%s+(%-?%d+)")
        local a = varaddr(name)
        if not a then report(false, name .. " not in the dictionary")
        else
            local got = signed(w(a))
            report(got == tonumber(want),
                   string.format("%s = %d (wanted %s)", name, got, want))
        end
        timer = 2
    elseif op == "show" then
        local a = varaddr(rest)
        print(string.format("     %s = %s", rest,
              a and tostring(signed(w(a))) or "?"))
        timer = 2
    end
end

SUBSCRIPTION = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if phase == "wait" then
        -- Waiting a fixed number of frames meant every change to the image
        -- moved the finish line: a slightly longer boot and the first steps
        -- were played into the splash screen and lost.  DESK sets RUNF when
        -- the desktop is live, so wait for that instead.
        if frames < 600 then return end
        mem = mem or manager.machine.devices[":maincpu"].spaces["program"]
        if frames % 30 ~= 0 then return end
        local r = varaddr("RUNF")
        if not r or signed(w(r)) ~= -1 then
            if frames < READY then return end
            print("FAIL desktop never came up")
            manager.machine:exit()
            return
        end
        -- RUNF goes up before DESK paints the desktop for the first time,
        -- and a click during that paint is never seen.
        print(string.format("     desktop up at frame %d", frames))
        timer = 150
        fx, fy, btn = field("x"), field("y"), button()
        if not (fx and fy and btn) then
            print("FAIL game port fields missing")
            manager.machine:exit()
            return
        end
        phase = "run"
        return
    end
    if phase ~= "run" then return end
    fx:set_value(wantx)
    fy:set_value(wanty)
    btn:set_value(wantbtn)
    if timer > 0 then timer = timer - 1 return end
    if at > #steps then
        print(string.format("RESULT %d passed, %d failed", passes, failures))
        phase = "done"
        manager.machine:exit()
        return
    end
    local step = steps[at]; at = at + 1
    run(step)
end)
