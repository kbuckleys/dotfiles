-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

hl.window_rule({ match = { class = "org.quickshell", title = "terminus" },         float = true })
hl.window_rule({ match = { class = "org.quickshell", title = "terminus-picker" },  float = true })
hl.window_rule({ match = { class = "steam", title = "Steam Settings" },            float = true })
hl.window_rule({ match = { class = "kitty", title = "cynosure" },                  float = true, size = { 1000, 1000 }})
hl.window_rule({ match = { class = "kitty",title = "sysmon" },                     float = true, size = { 1000, 1100 }})
hl.window_rule({ match = { class = "kitty",title = "ZENU" },                       float = true, size = { 1000, 1100 }})
hl.window_rule({ match = { class = "swayimg" },                                    float = true })
hl.window_rule({ match = { class = "mpv" },                                        float = true })

-- BORDERS
-- the unfocused value — see general.col in base.lua
hl.window_rule({ match = { fullscreen = true },  rounding = 5 })
hl.window_rule({ match = { float = true },       rounding = 5 })

-- DISABLE SHADOWS FOR TILES
hl.window_rule({ match = { float = false }, no_shadow = true })
hl.window_rule({ match = { class = "^$" }, no_shadow = false })

-- GLOBAL BLUR
hl.layer_rule({ match = { namespace = ".*" }, blur = true, ignore_alpha = 0.5 })
-- THE BAR ANIMATES ITSELF, SO HYPRLAND MUST NOT
--
-- morpheus' pill morphs into a panel by animating a rectangle inside a
-- surface that snaps between two sizes once per morph. hyprland was playing
-- the `layers` animation (speed 1, easeOutQuint = 100ms) over that snap,
-- scaling the pill's whole buffer down and back inside the animated rect --
-- glyphs and all, which is a thing QML cannot do and so could only have been
-- the compositor. Two animators, two curves, two durations, one object.
--
-- The shell's own morph is 75ms and owns every pixel of this surface, so
-- there is nothing here for the compositor to add. `morpheus-bar` is the
-- namespace shell.qml gives the pill precisely so this rule can name it
-- without touching the other quickshell layers, which still animate.
hl.layer_rule({ match = { namespace = "morpheus-bar" }, animation = "none" })

-- SPECIAL WORKSPACE
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- FIREFOX
hl.window_rule({ match = { class = "firefox", title = "Firefox - Choose a profile" },  float = true })
hl.window_rule({ match = { class = "firefox", title = "About Mozilla Firefox" },       float = true })
hl.window_rule({ match = { class = "firefox", title = "Choose Application" },          float = true })
hl.window_rule({ match = { class = "firefox", title = "Library" },                     float = true, size = { 1000, 1000 }})
