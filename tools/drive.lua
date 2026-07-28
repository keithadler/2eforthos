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
-- START is the frame to begin at (60 frames per emulated second; the disk
-- boot plus bootstrap needs about 1500).  GAP is the frames between lines.

local START = tonumber(os.getenv("START") or "1600")
local GAP   = tonumber(os.getenv("GAP")   or "220")

local lines = {}
for chunk in ((os.getenv("DRIVE") or "") .. ";;"):gmatch("(.-);;") do
    if #chunk > 0 then lines[#lines + 1] = chunk end
end

local DP_ADDR     = tonumber(os.getenv("DP_ADDR")     or "0x665D")
local LATEST_ADDR = tonumber(os.getenv("LATEST_ADDR") or "0x666B")
local STATE_ADDR  = tonumber(os.getenv("STATE_ADDR")  or "0x6647")

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
    print(string.format("DP=$%04X  LATEST=$%04X  STATE=$%04X",
                        w(DP_ADDR), w(LATEST_ADDR), w(STATE_ADDR)))
    print("---8<--- END ---8<---")
end

local frames, sent = 0, 0

-- Both subscriptions live in globals: a notifier unsubscribes itself if it is
-- ever garbage collected, and the callback would silently stop firing.
FRAME_SUB = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if sent < #lines and frames >= START + sent * GAP then
        sent = sent + 1
        print(string.format("[drive] frame %d: %s", frames, lines[sent]))
        emu.keypost(lines[sent] .. "\n")
    end
end)

STOP_SUB = emu.add_machine_stop_notifier(function()
    local ok, err = pcall(dump)
    if not ok then print("DUMP FAILED: " .. tostring(err)) end
end)
