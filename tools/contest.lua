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
--   pcs N             sample the PC and IP for N frames, print the hot pages
--   key N N ...       post raw character codes, without waiting for a prompt
--   drive N           type "N DRIVE" -- the Programs disk is 2
--   filesabs N        assert the absolute file count (for INIT'd disks)
--   rebase            re-anchor the files op's baseline to the current drive

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
local pcframes, pchist = 0, nil
-- A line typed while Forth is busy loses keystrokes: the Apple II keyboard
-- is one byte with no buffer, and a new key lands on top of the old one.
-- Every mangled line this suite has ever produced was this.  So nothing is
-- posted until the program counter has been seen inside ReadLine -- the
-- console's own wait-for-a-line loop -- twice in a row.  The patience
-- counter posts anyway after thirty seconds, so a step that types at
-- something other than the prompt still can.
local pendtext, pendok, pendwait = nil, 0, 0
local assertwait = nil
local ASSERTOPS = { stack=true, depth=true, check=true, mem=true,
                    nonzero=true, files=true, filesabs=true }

local function post(text)
    pendtext, pendok, pendwait = text, 0, 1800
end

local function atprompt()
    local pc = manager.machine.devices[":maincpu"].state["PC"].value
    return pc >= SYMS.ReadLine and pc < SYMS.ReadLine + 0x60
end
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
        -- natkeyboard types a character at a time over many frames; the
        -- posting flag waits that out, and post() waits for the prompt.
        post(rest .. "\n")
        timer = 5
    elseif op == "key" then
        -- A single character posted without waiting for the prompt.  The
        -- prompt gate is right for typing lines at the interpreter, but an
        -- interactive word -- a menu bar, a paged listing -- never shows a
        -- prompt while it is waiting, so nothing could ever be typed into
        -- one.  Codes, not names: 10 and 11 are the down and up arrows,
        -- 13 Return, 27 Escape.
        -- Names go through post_coded, because natkeyboard:post maps
        -- character 10 to Return rather than to the down arrow; numbers
        -- are posted as characters for everything else.
        for tok in rest:gmatch("%S+") do
            if tok:match("^%d+$") then
                manager.machine.natkeyboard:post(string.char(tonumber(tok)))
            else
                manager.machine.natkeyboard:post_coded("{" .. tok .. "}")
            end
        end
        posting = true
        timer = 5
    elseif op == "clear" then
        -- ABORT empties the data stack, so a test never inherits a depth
        -- from the step before it.
        post("ABORT\n")
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
            post(found .. " " .. verb .. "\n")
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
    elseif op == "filesabs" then
        -- The absolute count, for the tests that INIT a disk: an empty
        -- catalog is 0 files whatever the disk booted with, and a delta
        -- against the boot count broke the day files moved between disks.
        local a = varaddr("NFILE")
        local got = a and signed(w(a))
        report(got == tonumber(rest),
               string.format("files = %s (wanted %s, absolute)",
                             tostring(got), rest))
        timer = 2
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
    elseif op == "drive" then
        -- Switch drives the way a user would: type "N DRIVE" and let the
        -- catalog reload.  The load/loadwith steps read the parsed catalog
        -- live, so after this they mean the new disk.
        post(rest .. " DRIVE\n")
        timer = 5
    elseif op == "rebase" then
        -- Re-anchor the files op's baseline to the current drive's count.
        -- The boot baseline is drive 1's; a test that switches to drive 2
        -- and then writes needs its arithmetic against drive 2.
        local nf = varaddr("NFILE")
        basefiles = nf and w(nf) or 0
        print(string.format("     files rebased to %d", basefiles))
        timer = 2
    elseif op == "pcs" then
        -- Sample the program counter for N frames and print the histogram
        -- by page: where the machine actually spends its time, for when a
        -- step takes far longer than it has any right to.
        pcframes = tonumber(rest) or 300
        pchist = {}
        timer = 0
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
    if pcframes > 0 then
        pcframes = pcframes - 1
        local pc = manager.machine.devices[":maincpu"].state["PC"].value
        local page = pc >> 8
        pchist[page] = (pchist[page] or 0) + 1
        -- and the thread being run: IP names the colon word, where PC only
        -- names the primitive it happens to be inside
        local ip = w(0xB0)
        local ipage = 0x1000 + (ip >> 8)        -- keyed apart from PC pages
        pchist[ipage] = (pchist[ipage] or 0) + 1
        if pcframes == 0 then
            local pages = {}
            for k in pairs(pchist) do pages[#pages+1] = k end
            table.sort(pages, function(a, b)
                return pchist[a] > pchist[b] end)
            local out = {}
            for i = 1, math.min(#pages, 12) do
                local k = pages[i]
                out[#out+1] = string.format("%s%02Xxx:%d",
                                            k >= 0x1000 and "ip" or "",
                                            k & 0xFF, pchist[k])
            end
            print("     pc " .. table.concat(out, " "))
        end
        return
    end
    if fx then fx:set_value(wantx) end
    if fy then fy:set_value(wanty) end
    if btn then btn:set_value(wantbtn) end
    if timer > 0 then timer = timer - 1 return end
    if pendtext then
        pendwait = pendwait - 1
        if atprompt() then pendok = pendok + 1 else pendok = 0 end
        if pendok >= 2 or pendwait <= 0 then
            manager.machine.natkeyboard:post(pendtext)
            pendtext = nil
            posting = true
        end
        return
    end
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
    local step = steps[at]
    -- An assertion sampled while a word is still running photographs the
    -- middle of its stack, which has produced every phantom failure this
    -- suite ever chased: the assert ops hold, like typing does, until the
    -- machine is back at the prompt.  The patience cap keeps a hung word
    -- from hanging the test with it.
    local op = step:match("^(%S+)")
    if ASSERTOPS[op] and not atprompt() then
        assertwait = (assertwait or 3600) - 1
        if assertwait > 0 then return end
    end
    assertwait = nil
    at = at + 1
    run(step)
end)
