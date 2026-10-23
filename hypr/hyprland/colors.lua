--	hl.config({
--	    general = {
--		col = {
--		    active_border   = "rgba(47464f77)",
--		    inactive_border = "rgba(1b1b2133)",
--		},
--	    },
--	    misc = {
--		background_color = "rgba(131318FF)",
--	    },
--	})

hl.config({
    general = {
        col = {
            active_border   = { colors = {"rgba(c2c1ffee)", "rgba(e9b9d2ee)"}, angle = 45 },
            inactive_border = "rgba(918f9aaa)",
        },
    },
    group = {
        col = {
            border_active        = "rgba(c2c1ffee)",
            border_inactive      = "rgba(918f9aaa)",
            border_locked_active = "rgba(ffb4abee)",
        },
    },
})

--	hl.window_rule({
--	    match        = { pin = 1 },
--	    border_color = "rgba(c2c1ffAA) rgba(c2c1ff77)",
--	})

