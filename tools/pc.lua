-- Sample the program counter once per frame and print the tail.  One sample
-- per frame, not per call: several in a row inside one callback would return
-- the same value, since the CPU is not running while the script is.
local frames, hist = 0, {}
local target = tonumber(os.getenv("FRAMES") or "600")
SUB = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if frames > target - 16 then
        hist[#hist+1] = string.format("%04X",
            manager.machine.devices[":maincpu"].state["PC"].value)
    end
    if frames >= target then
        print("PC: " .. table.concat(hist, " "))
        manager.machine:exit()
    end
end)
