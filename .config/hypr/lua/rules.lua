-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

hl.window_rule({ match = { class = "org.quickshell", title = "terminus" },         float = true })
hl.window_rule({ match = { class = "org.quickshell", title = "terminus-picker" },  float = true })
hl.window_rule({ match = { class = "org.quickshell", title = "ceres" },            float = true })
hl.window_rule({ match = { class = "steam", title = "Steam Settings" },            float = true })
hl.window_rule({ match = { class = "kitty", title = "cynosure" },                  float = true, size = { 1000, 1000 }})
hl.window_rule({ match = { class = "kitty",title = "sysmon" },                     float = true, size = { 1000, 1100 }})
hl.window_rule({ match = { class = "swayimg" },                                    float = true })
hl.window_rule({ match = { class = "mpv" },                                        float = true })

-- GLOBAL BLUR
hl.layer_rule({ match = { namespace = ".*" }, blur = true, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "morpheus-bar" }, animation = "none" })

-- SPECIAL WORKSPACE
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- FIREFOX
hl.window_rule({ match = { class = "firefox", title = "Firefox - Choose a profile" },  float = true })
hl.window_rule({ match = { class = "firefox", title = "About Mozilla Firefox" },       float = true })
hl.window_rule({ match = { class = "firefox", title = "Choose Application" },          float = true })
hl.window_rule({ match = { class = "firefox", title = "Library" },                     float = true, size = { 1000, 1000 }})
