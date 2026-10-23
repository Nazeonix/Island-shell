-- Workspace + window rules.
local floatlist = require("hyprland.floatlist")

for i = 1, 5 do
    hl.workspace_rule({ workspace = tostring(i), persistent = true })
end

-- "Smart gaps" (uncomment to use):
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({ name = "no-gaps-wtv1", match = { float = false, workspace = "w[tv1]" }, border_size = 0, rounding = 0 })
-- hl.window_rule({ name = "no-gaps-f1",   match = { float = false, workspace = "f[1]"   }, border_size = 0, rounding = 0 })

local suppressMaximizeRule = hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-- Always-floating windows (see floatlist.lua)
for _, class in ipairs(floatlist.classes) do
    hl.window_rule({
        name  = "float-" .. class,
        match = { class = class },
        float = true,
        center = true,
        suppress_event = "fullscreen",
    })
end

for _, title in ipairs(floatlist.thunar_titles) do
    hl.window_rule({
        name  = "float-thunar-" .. title:lower():gsub("%s+", "-"),
        match = { class = "thunar", title = "^" .. title },
        float = true,
        center = true,
    })
end

-- Layer rules also return a handle:
-- local overlayLayerRule = hl.layer_rule({
--     name = "no-anim-overlay", match = { namespace = "^my-overlay$" }, no_anim = true,
-- })
