-- Per-layout settings. Active layout is set in look.lua (general.layout).
hl.config({
    dwindle = {
        preserve_split = true,
    },
})

hl.config({
    master = {
        new_status = "master",
    },
})

hl.config({
    scrolling = {
        column_width             = 0.5,                      -- new windows spawn at half screen
        explicit_column_widths   = "0.333, 0.5, 0.667, 1.0", -- presets for colresize +conf / -conf
        fullscreen_on_one_column = false,
        follow_focus             = true,
    },
})
