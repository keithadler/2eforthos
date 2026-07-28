-- Sample the program counter once a frame and report where the time goes.
--
-- Guessing at what a boot is spending 28 seconds on has not worked well; this
-- says. One sample per frame is coarse but the run is thousands of frames, so
-- anything that matters shows up.  Map the addresses to symbols with the
-- linker's label file afterwards.
--
--   PROFFROM   frame to start sampling (skip the disk load)
--   PROFTO     frame to stop and report

local FROM = tonumber(os.getenv("PROFFROM") or "400")
local TO   = tonumber(os.getenv("PROFTO")   or "2200")

local frames, counts, total = 0, {}, 0

SUBSCRIPTION = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if frames < FROM then return end
    if frames > TO then
        if total > 0 then
            print("PROFILE " .. total .. " samples")
            for pc, n in pairs(counts) do
                print(string.format("PC %04X %d", pc, n))
            end
            total = 0
            manager.machine:exit()
        end
        return
    end
    local pc = manager.machine.devices[":maincpu"].state["PC"].value
    counts[pc] = (counts[pc] or 0) + 1
    total = total + 1
end)
