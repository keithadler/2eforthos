-- Print every name in the live dictionary, for coverage checking.
--
-- WORDS on the machine scrolls past faster than it can be read and wraps at
-- eighty columns; this walks the definition chain in memory instead and
-- prints the lot on one line, with a star on the immediate ones.
--
--   LATESTV    address of the kernel's LATEST variable, from build/forth.lbl
--   READYFRAME when to look; the dictionary has to be finished being built

local LATESTV = tonumber(os.getenv("LATESTV") or "0")
local READY   = tonumber(os.getenv("READYFRAME") or "2400")
local frames, done = 0, false

SUB = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if done or frames < READY then return end
    local mem = manager.machine.devices[":maincpu"].spaces["program"]
    local function w(a) return mem:read_u8(a) | (mem:read_u8(a+1) << 8) end
    local p, list, guard = w(LATESTV), {}, 0
    while p ~= 0 and guard < 5000 do
        guard = guard + 1
        -- main above the kernel, or the language card
        if p < 0x4000 or (p > 0xBFFF and p < 0xD000) or p > 0xFFF9 then break end
        local f = mem:read_u8(p + 4)
        local len = f & 0x3F
        local s = ""
        for i = 0, len - 1 do s = s .. string.char(mem:read_u8(p + 5 + i)) end
        if s ~= "" then list[#list+1] = s .. ((f & 0x80) ~= 0 and "*" or "") end
        p = w(p)
    end
    print("WORDCOUNT " .. #list)
    print("WORDS " .. table.concat(list, " "))
    done = true
    manager.machine:exit()
end)
