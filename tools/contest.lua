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

local LATESTV = tonumber(os.getenv("LATESTV") or "0")
local READY   = tonumber(os.getenv("READYMAX") or "5400")
local SCRIPT  = os.getenv("TEST") or ""

local SYMS = {}
for pair in (os.getenv("SYMS") or ""):gmatch("[^,]+") do
    local n, a = pair:match("([%w_]+)=(%d+)")
    if n then SYMS[n] = tonumber(a) end
end

local mem, frames, phase = nil, 0, "wait"
local steps, at, timer = {}, 1, 0
local posting = false                   -- a line is still being typed in
local passes, failures = 0, 0

for line in SCRIPT:gmatch("[^\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" then steps[#steps+1] = line end
end

local function w(a) return mem:read_u8(a) | (mem:read_u8(a+1) << 8) end
local function signed(v) return v >= 0x8000 and v - 0x10000 or v end

-- Walk the definition chain the way FIND does.  A VARIABLE's code field is
-- JSR DOVAR, so its cell is three bytes past the name.  This runs before the
-- dictionary necessarily exists, so every link is bounds checked.
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
    elseif op == "wait" then
        timer = tonumber(rest)
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
        print(string.format("     console up at frame %d", frames))
        phase, timer = "run", 60
        return
    end
    if phase ~= "run" then return end
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
