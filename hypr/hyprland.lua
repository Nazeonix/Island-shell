-- ~/.config/hypr/hyprland.lua  (entry point)
-- Modules live in ~/.config/hypr/hyprland/*.lua
-- Order matters: later config overrides earlier; window rules apply in creation order.

local function load(name)
    local ok, err = pcall(require, "hyprland." .. name)
    if not ok then
        print("[hyprland.lua] module '" .. name .. "' failed: " .. tostring(err))
        pcall(hl.notification.create, { text = "Config module '" .. name .. "' failed:\n" .. tostring(err), duration = 8000 })
    end
end

load("env")
load("monitors")
load("colors")
load("look")
load("layouts")
load("input")
load("misc")
load("floatmode")   -- before rules, so specific rules can override float-all
load("rules")
load("binds")
load("autostart")
