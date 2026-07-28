-- Drive the game port from the host, to exercise the same path a mouse takes.
--
-- Note: MAME numbers snapshots 0000, 0001, ... and never overwrites, so a
-- stale 0000.png survives every later run.  Clear the directory before a
-- session or you will read an old frame and believe nothing happened.
--
-- The pointer follows the joystick through MREAD, and that is the path the
-- ghost arrow shows up on; the keyboard path draws cleanly.  Sweeping the
-- analog value here reproduces it without needing a hand on a mouse.
--
--   JOYFROM/JOYTO   paddle 0 range to sweep, 0..255
--   JOYSTEP         how much to move per stop
--   JOYSETTLE       frames to hold at each stop
--   SNAPAT          comma-separated paddle values to photograph

local READY    = tonumber(os.getenv("READYMAX") or "2700")
local FROM     = tonumber(os.getenv("JOYFROM")  or "128")
local TO       = tonumber(os.getenv("JOYTO")    or "250")
local STEP     = tonumber(os.getenv("JOYSTEP")  or "10")
local SETTLE   = tonumber(os.getenv("JOYSETTLE")or "40")

local frames, value, phase = 0, FROM, "wait"
local field

local function findfield()
    for tag, port in pairs(manager.machine.ioport.ports) do
        if tag:find("joystick_1_x") then
            for _, f in pairs(port.fields) do
                if f.is_analog then return f end
            end
        end
    end
end

SUBSCRIPTION = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if phase == "wait" then
        if frames >= READY then
            field = findfield()
            if not field then print("[joy] no analog field found") ; phase = "done" ; return end
            print("[joy] sweeping paddle 0 from " .. FROM .. " to " .. TO)
            phase = "sweep"
        end
        return
    end
    if phase ~= "sweep" then return end

    field:set_value(value)
    if (frames % SETTLE) == 0 then
        -- x on screen is 17/8 of the paddle, which is what MREAD computes
        print(string.format("[joy] paddle=%3d  expected x=%d", value, (value * 17) // 8))
        manager.machine.video:snapshot()
        value = value + STEP
        if value > TO then
            phase = "done"
            manager.machine:exit()
        end
    end
end)
