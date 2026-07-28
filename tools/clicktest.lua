-- Put the pointer on a desktop icon and double click it.
--
-- Driving this from the keyboard would take about thirty keypresses to cross
-- the screen; the game port gets there in one step, and it exercises the same
-- MREAD path a mouse uses.  MREAD maps paddle 0 to x as 17/8 and paddle 1 to
-- y as 3/4, so the paddle values here are just those relations inverted.
--
--   TARGETX / TARGETY   where to put the pointer
--   CLICKGAP            frames between the two clicks; the OS counts a double
--                       click within 40 event-loop passes, roughly 16 frames

local READY  = tonumber(os.getenv("READYMAX")  or "1600")
local TX     = tonumber(os.getenv("TARGETX")   or "495")
local TY     = tonumber(os.getenv("TARGETY")   or "30")
local GAP    = tonumber(os.getenv("CLICKGAP")  or "8")

local frames, phase, mark = 0, "wait", 0
local fx, fy

local function analog(which)
    for tag, port in pairs(manager.machine.ioport.ports) do
        if tag:find("joystick_1_" .. which) then
            for _, f in pairs(port.fields) do
                if f.is_analog then return f end
            end
        end
    end
end

SUBSCRIPTION = emu.add_machine_frame_notifier(function()
    frames = frames + 1
    if phase == "wait" then
        if frames < READY then return end
        fx, fy = analog("x"), analog("y")
        if not fx or not fy then print("[click] no analog fields") ; phase="done" ; return end
        print(string.format("[click] aiming at %d,%d", TX, TY))
        phase, mark = "move", frames
    end

    if phase ~= "done" then                     -- hold the stick steady
        fx:set_value(math.floor(TX * 8 / 17))
        fy:set_value(math.floor(TY * 4 / 3))
    end

    if phase == "move" and frames > mark + 90 then
        print("[click] first click")
        manager.machine.natkeyboard:post(" ")
        phase, mark = "click2", frames
    elseif phase == "click2" and frames > mark + GAP then
        print("[click] second click")
        manager.machine.natkeyboard:post(" ")
        phase, mark = "settle", frames
    elseif phase == "settle" and frames > mark + 200 then
        manager.machine.video:snapshot()
        manager.machine.natkeyboard:post("Q")   -- back to the text REPL
        phase, mark = "ask", frames
    elseif phase == "ask" and frames > mark + 120 then
        manager.machine.natkeyboard:post("ISEL @ . CALCON @ . NWIN @ . PTRX .\n")
        phase, mark = "quit", frames
    elseif phase == "quit" and frames > mark + 420 then
        local mem = manager.machine.devices[":maincpu"].spaces["program"]
        local base = {0x400,0x480,0x500,0x580,0x600,0x680,0x700,0x780}
        print("[click] text screen:")
        for row = 0, 23 do
            local a = base[(row % 8) + 1] + (row // 8) * 40
            local line = ""
            for col = 0, 39 do
                local c = mem:read_u8(a + col) & 0x7F
                line = line .. ((c >= 32 and c < 127) and string.char(c) or " ")
            end
            if line:match("%S") then print(string.format("  %02d|%s|", row, line)) end
        end
        phase = "done"
        manager.machine:exit()
    end
end)
