-- Drive the console and check what the system made of it.
--
-- Assertions are made against machine state, not against the screen: what
-- matters is what the system believes, and the data stack says that exactly.
-- X is the stack pointer, and the top level parks it in XSAV before it waits
-- for a line, so while the prompt is up the whole stack can be read.
--
-- Steps come from the TEST environment variable, one per line:
--
--   type <text>       type a line and press return
--   wait N            idle for N frames
--   shot              take a snapshot
--   stack v1 v2 ..    assert the data stack, top of stack first
--   depth N           assert how many cells are on it
--   check VAR VALUE   assert a Forth variable's cell
--   show VAR          print one without asserting
--   mem ADDR VALUE    assert one byte of memory
--   nonzero ADDR N    assert N bytes from ADDR are not all zero
--   screen            print the 80-column text screen, to see what it said

local LATESTV = tonumber(os.getenv("LATESTV") or "0")
local READY   = tonumber(os.getenv("READYMAX") or "5400")
local SCRIPT  = os.getenv("TEST") or ""

local SYMS = {}
for pair in (os.getenv("SYMS") or ""):gmatch("[^,]+") do
    local n, a = pair:match("([%w_]+)=(%d+)")
    if n then SYMS[n] = tonumber(a) end
end

-- The game port, for anything that reads a pointer.  A value written to an
-- ioport field does not necessarily stay written, so the wanted state is
-- held here and reapplied every frame.
local fx, fy, btn
local wantx, wanty, wantbtn = 128, 128, 0

local function analog(which)
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

local mem, frames, phase = nil, 0, "wait"
local basefiles = nil    -- how many files the disk booted with
local steps, at, timer = {}, 1, 0
local posting = false                   -- a line is still being typed in
local passes, failures = 0, 0

for line in SCRIPT:gmatch("[^\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" then steps[#steps+1] = line end
end

local function w(a) return mem:read_u8(a) | (mem:read_u8(a+1) << 8) end
local function signed(v) return v >= 0x8000 and v - 0x10000 or v end

-- Read the 80-column text screen back as text.
--
-- Worth the trouble: every assertion here is against machine state, which is
-- the right thing to assert on but tells you nothing about *why* a case
-- failed.  The console has usually said exactly why -- NAME?, NOT FOUND, an
-- I/O error -- and until now none of that was visible, which has cost this
-- project more debugging time than any actual bug.
--
-- Eighty columns live in two banks: even columns in auxiliary memory, odd in
-- main, one byte of each per screen position.  MAME exposes no share for the
-- aux RAM, so the only way in is the soft switch the firmware itself uses.
-- It is not RAMRD: with 80STORE on -- which is how the console runs -- RAMRD
-- is ignored for $0400-$07FF and PAGE2 picks the bank instead, which is why
-- reading through $C003 gives main memory twice and a screen of doubled
-- letters.  $C055 banks aux in, $C054 puts main back.
--
-- 80STORE itself is left alone, because there is no way to read it back and
-- guess wrong would leave the machine in a state it did not ask for.  In a
-- mode that has turned it off -- GR does -- this reads main twice and the
-- doubled text says so plainly.
--
-- Reads happen between frames with the CPU stopped, and main is restored
-- before it runs again, so no instruction ever executes in the flipped state.
local PAGE2ON, PAGE2OFF = 0xC055, 0xC054

local function rowbase(r) return 0x400 + (r % 8) * 0x80 + (r // 8) * 0x28 end

local function screen()
    local main, aux = {}, {}
    for r = 0, 23 do
        local b = rowbase(r)
        for c = 0, 39 do main[r * 40 + c] = mem:read_u8(b + c) end
    end
    mem:write_u8(PAGE2ON, 0)
    for r = 0, 23 do
        local b = rowbase(r)
        for c = 0, 39 do aux[r * 40 + c] = mem:read_u8(b + c) end
    end
    mem:write_u8(PAGE2OFF, 0)

    local lines = {}
    for r = 0, 23 do
        local s = ""
        for c = 0, 39 do
            -- The screen holds the character with its high bit set for
            -- normal text; inverse and flashing use the low ranges, which
            -- map onto the same glyph.
            local a = aux[r * 40 + c] & 0x7F
            local m = main[r * 40 + c] & 0x7F
            if a < 0x20 then a = a + 0x40 end
            if m < 0x20 then m = m + 0x40 end
            s = s .. string.char(a) .. string.char(m)
        end
        lines[#lines+1] = s:gsub("%s+$", "")
    end
    return lines
end

-- Walk the definition chain the way FIND does.  A VARIABLE's code field is
-- JSR DOVAR, so its cell is three bytes past the name.  This runs before the
-- dictionary necessarily exists, so every link is bounds checked.
local function varaddr(name)
    local p = w(LATESTV)
    local guard = 0
    while p ~= 0 do
        guard = guard + 1
        -- The system's own words are compiled into the language card, so a
        -- header is either in main above the kernel or in the card.
        if guard > 4000 or p < 0x4000 or (p > 0xBFFF and p < 0xD000)
           or p > 0xFFF9 then return nil end
        local len = mem:read_u8(p + 4) & 0x3F
        local s = ""
        for i = 0, len - 1 do s = s .. string.char(mem:read_u8(p + 5 + i)) end
        if s == name then return p + 5 + len + 3 end
        p = w(p)
    end
end

local function dstack()
    local sp = mem:read_u8(SYMS.XSAV)
    local cells = {}
    if sp > SYMS.DSTACK_TOP or sp < SYMS.DSTACK_BOT then return cells, true end
    for a = sp, SYMS.DSTACK_TOP - 2, 2 do
        cells[#cells+1] = signed(w(a))
    end
    return cells, false                 -- cells[1] is the top of stack
end

local function report(ok, text)
    if ok then passes = passes + 1 print("PASS " .. text)
    else failures = failures + 1 print("FAIL " .. text) end
end

local function run(step)
    local op, rest = step:match("^(%S+)%s*(.*)$")
    if op == "type" then
        -- post() types a character at a time over many frames.  Guessing how
        -- long that takes put every assertion a line behind; MAME will say.
        manager.machine.natkeyboard:post(rest .. "\n")
        posting = true
        timer = 5
    elseif op == "clear" then
        -- ABORT empties the data stack, so a test never inherits a depth
        -- from the step before it.
        manager.machine.natkeyboard:post("ABORT\n")
        posting = true
        timer = 5
    elseif op == "load" or op == "loadwith" then
        -- Look the file up in the parsed catalog rather than hard-coding a
        -- number: adding a file to the disk renumbers everything after it.
        -- "load NAME" types "<n> LOAD"; "loadwith NAME WORD" types
        -- "<n> WORD", for the other words that take a catalog number.
        local want, verb = rest, "LOAD"
        if op == "loadwith" then want, verb = rest:match("(%S+)%s+(%S+)") end
        local base = varaddr("CATBUF")
        base = base and w(base)
        local n = varaddr("NFILE")
        n = n and w(n) or 0
        local found = nil
        for i = 0, n - 1 do
            local rec, name = base + i * 36 + 6, ""
            for j = 0, 29 do
                local c = mem:read_u8(rec + j) & 0x7F
                name = name .. string.char(c)
            end
            if name:match("^%s*(.-)%s*$") == want then found = i end
        end
        if not found then
            report(false, "no file called " .. tostring(want))
            timer = 2
        else
            manager.machine.natkeyboard:post(found .. " " .. verb .. "\n")
            posting = true
            timer = 5
        end
    elseif op == "point" then
        -- PADDLE reads 0..255 and the screen is 560 by 192, so x is 17/8 of
        -- the reading and y is 3/4: this is those relations inverted.
        local x, y = rest:match("(%-?%d+)%s+(%-?%d+)")
        wantx = math.floor(tonumber(x) * 8 / 17)
        wanty = math.floor(tonumber(y) * 4 / 3)
        timer = 150
    elseif op == "press" then
        wantbtn = 1; timer = 30
    elseif op == "release" then
        wantbtn = 0; timer = 30
    elseif op == "files" then
        -- Against the count the disk booted with, never an absolute number:
        -- adding or editing any file on the floppy would otherwise break
        -- every test that mentions the catalog.
        local a = varaddr("NFILE")
        local got = a and signed(w(a))
        local want = basefiles and (basefiles + tonumber(rest))
        report(got == want,
               string.format("files = %s (wanted %s, base %s%+d)",
                             tostring(got), tostring(want),
                             tostring(basefiles), tonumber(rest)))
        timer = 2
    elseif op == "wait" then
        timer = tonumber(rest)
    elseif op == "screen" then
        -- Blank trailing rows are dropped: the console is usually near the
        -- bottom and the empty half of the screen is noise.
        local lines = screen()
        while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
        print("     --- screen ---")
        for _, l in ipairs(lines) do print("     |" .. l) end
        timer = 2
    elseif op == "shot" then
        pcall(function() manager.machine.video:snapshot() end)
        timer = 2
    elseif op == "stack" then
        local want = {}
        for v in rest:gmatch("%-?%d+") do want[#want+1] = tonumber(v) end
        local got, bad = dstack()
        local ok = not bad and #got == #want
        if ok then
            for i = 1, #want do if got[i] ~= want[i] then ok = false end end
        end
        report(ok, string.format("stack = %s (wanted %s)%s",
               table.concat(got, " "), rest, bad and " OUT OF RANGE" or ""))
        timer = 2
    elseif op == "show-only" then
        local got = dstack()
        print(string.format("     top of stack = %s", got[1] or "empty"))
        timer = 2
    elseif op == "depth" then
        local got = dstack()
        report(#got == tonumber(rest),
               string.format("depth = %d (wanted %s)", #got, rest))
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
    elseif op == "mem" then
        local addr, want = rest:match("(%w+)%s+(%d+)")
        local a = tonumber(addr, 16)
        local got = mem:read_u8(a)
        report(got == tonumber(want),
               string.format("$%04X = %d (wanted %s)", a, got, want))
        timer = 2
    elseif op == "nonzero" then
        local addr, n = rest:match("(%w+)%s+(%d+)")
        local a = tonumber(addr, 16)
        local sum = 0
        for i = 0, tonumber(n) - 1 do sum = sum + mem:read_u8(a + i) end
        report(sum > 0, string.format("$%04X..+%s holds %d set bytes",
                                      a, n, sum))
        timer = 2
    end
end

SUBSCRIPTION = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if phase == "wait" then
        -- The greeting fills NFREE at the end of the boot source, so a
        -- non-zero NFREE means the console is up and waiting.  Waiting on a
        -- frame count instead would move the finish line every time the
        -- image changed size.
        if frames < 600 then return end
        mem = mem or manager.machine.devices[":maincpu"].spaces["program"]
        if frames % 30 ~= 0 then return end
        local a = varaddr("NFREE")
        if not a or w(a) == 0 then
            if frames < READY then return end
            print("FAIL the console never came up")
            manager.machine:exit()
            return
        end
        fx, fy, btn = analog("x"), analog("y"), button()
        local nf = varaddr("NFILE")
        basefiles = nf and w(nf) or 0
        print(string.format("     console up at frame %d, %d files",
                            frames, basefiles))
        phase, timer = "run", 60
        return
    end
    if phase ~= "run" then return end
    if fx then fx:set_value(wantx) end
    if fy then fy:set_value(wanty) end
    if btn then btn:set_value(wantbtn) end
    if timer > 0 then timer = timer - 1 return end
    if posting then
        if manager.machine.natkeyboard.is_posting then return end
        posting = false
        timer = 60                      -- and let the line run
        return
    end
    if at > #steps then
        print(string.format("RESULT %d passed, %d failed", passes, failures))
        phase = "done"
        manager.machine:exit()
        return
    end
    local step = steps[at]; at = at + 1
    run(step)
end)
