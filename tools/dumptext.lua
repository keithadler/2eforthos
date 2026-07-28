-- Dump the Apple II text screen, zero page, and the Forth dictionary state
-- out of emulated memory.  Reading characters off a screenshot is guesswork;
-- this prints the actual bytes.
--
--   mame ... -seconds_to_run 40 -autoboot_script tools/dumptext.lua
--
-- The dump fires when the machine stops, so it always lands at the end of the
-- run no matter how long -seconds_to_run is.

-- Symbol addresses, from build/forth.lbl.  Override if the build moves them.
local DP_ADDR     = tonumber(os.getenv("DP_ADDR")     or "0x665D")
local LATEST_ADDR = tonumber(os.getenv("LATEST_ADDR") or "0x666B")
local STATE_ADDR  = tonumber(os.getenv("STATE_ADDR")  or "0x6647")

local function dump()
    local mem = manager.machine.devices[":maincpu"].spaces["program"]
    local function w(a) return mem:read_u8(a) | (mem:read_u8(a + 1) << 8) end

    print("---8<--- TEXT SCREEN ---8<---")
    for row = 0, 23 do
        -- text memory is interleaved like hi-res, just coarser
        local base = 0x400 + 0x80 * (row % 8) + 0x28 * (row // 8)
        local chars = {}
        for col = 0, 39 do
            local b = mem:read_u8(base + col) & 0x7F
            if b < 0x20 then b = b + 0x40 end   -- inverse/flash map low
            chars[#chars + 1] = string.char(b)
        end
        print(string.format("%02d|%s|", row, table.concat(chars)))
    end

    local zp = {}
    for a = 0x50, 0xD7 do
        if (a - 0x50) % 16 == 0 then zp[#zp + 1] = string.format("\n%02X:", a) end
        zp[#zp + 1] = string.format(" %02X", mem:read_u8(a))
    end
    print("ZP" .. table.concat(zp))

    print(string.format("DP=$%04X  LATEST=$%04X  STATE=$%04X",
                        w(DP_ADDR), w(LATEST_ADDR), w(STATE_ADDR)))

    -- walk the dictionary and check the chain terminates
    local p, n, seen = w(LATEST_ADDR), 0, {}
    while p ~= 0 and n < 400 do
        if seen[p] then
            print(string.format("CHAIN LOOPS at $%04X after %d links", p, n))
            break
        end
        seen[p] = true
        n = n + 1
        p = w(p)
    end
    if p == 0 then print("CHAIN OK, " .. n .. " words") end

    -- newest definitions first: the first name is whatever was being
    -- compiled if STATE is non-zero
    local q, names = w(LATEST_ADDR), {}
    for _ = 1, 14 do
        if q == 0 then break end
        local len = mem:read_u8(q + 2) & 0x3F
        local s = ""
        for i = 0, len - 1 do s = s .. string.char(mem:read_u8(q + 3 + i)) end
        names[#names + 1] = s
        q = w(q)
    end
    print("NEWEST WORDS: " .. table.concat(names, " "))
    print("---8<--- END ---8<---")
end

-- Held in globals on purpose: a notifier subscription unsubscribes itself if
-- it is ever garbage collected, and the callback would silently stop firing.
STOP_SUB = emu.add_machine_stop_notifier(function()
    local ok, err = pcall(dump)
    if not ok then print("DUMP FAILED: " .. tostring(err)) end
end)
