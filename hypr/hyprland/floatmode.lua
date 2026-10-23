-- Floating window manager mode.
--
--   SUPER + T   toggle floating mode (all new windows float; existing ones float too)
--
-- How it works:
--   * a catch-all window rule (float = true) that is only enabled while the mode is on
--   * on toggle, every existing window is floated/unfloated via hl.dispatch
--   * extra binds (move/resize/cycle/center) that are only enabled while the mode is on
--   * state is stored in $XDG_RUNTIME_DIR/hypr-floatmode so `hyprctl reload` keeps the mode
--     (read it from the bar if you want an indicator: "1" = on, "0" = off)
--
-- Always-floating windows (satty, thunar dialogs) are listed in floatlist.lua.
-- Mouse: SUPER+LMB drag / SUPER+RMB resize already come from binds.lua.

local floatlist = require("hyprland.floatlist")

local STATE_FILE   = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-floatmode"
local BORDER_FLOAT = 0    -- border while floating mode is on (nil = don't touch borders)
local BORDER_TILED = 0    -- must match general.border_size in look.lua
local MOVE_STEP    = 40
local SIZE_STEP    = 40

local M = { active = false }

-- ---- state file ----------------------------------------------------------

local function read_state()
    local ok, on = pcall(function()
        local f = io.open(STATE_FILE, "r")
        if not f then return false end
        local s = f:read("*l")
        f:close()
        return s == "1"
    end)
    return ok and on
end

local function write_state(on)
    pcall(function()
        local f = io.open(STATE_FILE, "w")
        if f then f:write(on and "1" or "0"); f:close() end
    end)
end

-- ---- catch-all rule (disabled until the mode is on) -----------------------

local floatRule = hl.window_rule({
    name  = "floatmode-float-all",
    match = { class = ".*" },
    float = true,
})
floatRule:set_enabled(false)

-- ---- mode-only binds ------------------------------------------------------

local handles = {}

local function fbind(keys, action, opts)
    local h
    if opts then h = hl.bind(keys, action, opts) else h = hl.bind(keys, action) end
    h:set_enabled(false)
    table.insert(handles, h)
end

fbind("SUPER + TAB", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end)

fbind("SUPER + C", hl.dsp.window.center({}))

local dirs = {
    left  = { -1,  0 },
    right = {  1,  0 },
    up    = {  0, -1 },
    down  = {  0,  1 },
}
for name, d in pairs(dirs) do
    -- SUPER + SHIFT + arrow: move
    fbind("SUPER + SHIFT + " .. name,
        hl.dsp.window.move({ x = d[1] * MOVE_STEP, y = d[2] * MOVE_STEP, relative = true }),
        { repeating = true })
    -- SUPER + SHIFT + CTRL + arrow: resize
    fbind("SUPER + SHIFT + CTRL + " .. name,
        hl.dsp.window.resize({ x = d[1] * SIZE_STEP, y = d[2] * SIZE_STEP, relative = true }),
        { repeating = true })
end

-- ---- apply / toggle -------------------------------------------------------

local function set_all_windows(floating)
    for _, w in ipairs(hl.get_windows()) do
        if floating then
            hl.dispatch(hl.dsp.window.float({ action = "set", window = w }))
        elseif not floatlist.is_always_float(w) then
            hl.dispatch(hl.dsp.window.float({ action = "unset", window = w }))
        end
    end
end

local function apply(on, touch_windows)
    M.active = on
    floatRule:set_enabled(on)
    for _, h in ipairs(handles) do h:set_enabled(on) end

    if BORDER_FLOAT then
        pcall(hl.config, { general = { border_size = on and BORDER_FLOAT or BORDER_TILED } })
    end
    if touch_windows then set_all_windows(on) end

    write_state(on)
end

function M.toggle()
    apply(not M.active, true)
    pcall(hl.notification.create, { text = "Floating mode: " .. (M.active and "ON" or "OFF"), duration = 2000 })
end

hl.bind("SUPER + T", M.toggle)

-- restore after reload (windows are already in the right state)
if read_state() then apply(true, false) end

return M
