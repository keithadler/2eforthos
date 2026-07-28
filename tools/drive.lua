-- Type lines into the running Forth at a pace it can keep up with, then dump
-- the machine state.
--
-- MAME's -autoboot_command types at a fixed rate.  The Apple II keyboard has
-- no buffer -- a new keypress simply overwrites the last -- so anything typed
-- while Forth is busy interpreting is lost.  This posts one line, waits, then
-- posts the next.
--
--   DRIVE='line one;;line two' START=1600 GAP=200 \
--     mame ... -autoboot_script tools/drive.lua
--
-- Rather than guessing when the system is ready, this watches the kernel's
-- bootstrap source pointer (SRC+1 at $CF).  Cold start sets it non-zero and
-- the interpreter zeroes it when the built-in source runs out and it turns to
-- the keyboard -- exactly the moment the prompt appears.  GAP is the frames
-- between lines; widen it for lines that repaint or touch the disk.

local GAP    = tonumber(os.getenv("GAP")    or "220")
local SETTLE = tonumber(os.getenv("SETTLE") or "120")
local READY  = tonumber(os.getenv("READY")  or "0xCF")
-- The system boots straight into the desktop event loop, which never returns
-- to the interpreter, so the ready flag may never clear.  Start anyway after
-- this many frames.
local READYMAX = tonumber(os.getenv("READYMAX") or "2600")

local lines = {}
for chunk in ((os.getenv("DRIVE") or "") .. ";;"):gmatch("(.-);;") do
    if #chunk > 0 then lines[#lines + 1] = chunk end
end

local DP_ADDR     = tonumber(os.getenv("DP_ADDR")     or "0x665D")
local LATEST_ADDR = tonumber(os.getenv("LATEST_ADDR") or "0x666B")
local STATE_ADDR  = tonumber(os.getenv("STATE_ADDR")  or "0x6647")

local PEEK = os.getenv("PEEK")

local function dump()
    local mem = manager.machine.devices[":maincpu"].spaces["program"]
    local function w(a) return mem:read_u8(a) | (mem:read_u8(a + 1) << 8) end

    print("---8<--- TEXT SCREEN ---8<---")
    for row = 0, 23 do
        local base = 0x400 + 0x80 * (row % 8) + 0x28 * (row // 8)
        local chars = {}
        for col = 0, 39 do
            local b = mem:read_u8(base + col) & 0x7F
            if b < 0x20 then b = b + 0x40 end
            chars[#chars + 1] = string.char(b)
        end
        print(string.format("%02d|%s|", row, table.concat(chars)))
    end
    if PEEK then
        local out = {}
        for spec in (PEEK .. ","):gmatch("(.-),") do
            if #spec > 0 then
                local a = tonumber(spec)
                out[#out+1] = string.format("$%04X=%02X", a, mem:read_u8(a))
            end
        end
        print("PEEK " .. table.concat(out, " "))
    end
    print(string.format("DP=$%04X  LATEST=$%04X  STATE=$%04X",
                        w(DP_ADDR), w(LATEST_ADDR), w(STATE_ADDR)))
    print("---8<--- END ---8<---")
end

local frames, sent = 0, 0
local armed, start = false, nil     -- armed once the pointer goes non-zero

-- Both subscriptions live in globals: a notifier unsubscribes itself if it is
-- ever garbage collected, and the callback would silently stop firing.
FRAME_SUB = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if not start then
        local byte = manager.machine.devices[":maincpu"].spaces["program"]
                         :read_u8(READY)
        if not armed then
            armed = byte ~= 0                   -- the kernel is running
        elseif byte == 0 then
            start = frames + SETTLE             -- and has reached the prompt
            print(string.format("[drive] system ready at frame %d", frames))
        elseif frames >= READYMAX then
            start = frames + SETTLE
            print(string.format("[drive] ready flag never cleared; "
                                .. "starting anyway at frame %d", frames))
        end
        return
    end
    if sent < #lines and frames >= start + sent * GAP then
        sent = sent + 1
        print(string.format("[drive] frame %d: %s", frames, lines[sent]))
        emu.keypost(lines[sent] .. "\n")
    end
end)

STOP_SUB = emu.add_machine_stop_notifier(function()
    local ok, err = pcall(dump)
    if not ok then print("DUMP FAILED: " .. tostring(err)) end
end)
