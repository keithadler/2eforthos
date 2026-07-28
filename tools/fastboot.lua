-- Boot fast, then hand the machine back at its real speed.
--
-- Running the whole session at 8x makes typing unusable: the //e repeats keys
-- in hardware, and at 8x a normal-length keypress crosses the repeat
-- threshold and sends the character several times.  The boot is the only part
-- worth hurrying, so speed is dropped back to 1x once the desktop is up.
--
--   BOOTSPEED    multiplier while booting
--   BOOTFRAMES   frames to hold it for (60 = one emulated second)

local FAST   = tonumber(os.getenv("BOOTSPEED")  or "8")
local UNTIL  = tonumber(os.getenv("BOOTFRAMES") or "2000")

local frames = 0
manager.machine.video.throttle_rate = FAST

SUBSCRIPTION = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if frames == UNTIL then
        manager.machine.video.throttle_rate = 1.0
        print(string.format("[fastboot] %dx for %d frames, now real speed",
                            FAST, UNTIL))
    end
end)
