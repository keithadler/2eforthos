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
-- JOYAXIS picks which paddle to sweep: "x" moves the pointer across, "y" up
-- and down.  The other axis is held at JOYHOLD.
local AXIS     = os.getenv("JOYAXIS") or "x"
local HOLD     = tonumber(os.getenv("JOYHOLD")  or "128")
local FROM     = tonumber(os.getenv("JOYFROM")  or "128")
local TO       = tonumber(os.getenv("JOYTO")    or "250")
local STEP     = tonumber(os.getenv("JOYSTEP")  or "10")
local SETTLE   = tonumber(os.getenv("JOYSETTLE")or "40")

local frames, value, phase = 0, FROM, "wait"
local field

local other
local function find(which)
    for tag, port in pairs(manager.machine.ioport.ports) do
        if tag:find("joystick_1_" .. which) then
            for _, f in pairs(port.fields) do
                if f.is_analog then return f end
            end
        end
    end
end

local function findfield()
    other = find(AXIS == "x" and "y" or "x")
    for tag, port in pairs(manager.machine.ioport.ports) do
        if tag:find("joystick_1_" .. AXIS) then
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
    if other then other:set_value(HOLD) end
    if (frames % SETTLE) == 0 then
        -- MREAD makes x 17/8 of the paddle and y 3/4 of it
        local screen = (AXIS == "x") and (value * 17) // 8 or (value * 3) // 4
        print(string.format("[joy] paddle=%3d  expected %s=%d", value, AXIS, screen))
        manager.machine.video:snapshot()
        value = value + STEP
        if (STEP > 0 and value > TO) or (STEP < 0 and value < TO) then
            phase = "done"
            manager.machine:exit()
        end
    end
end)
