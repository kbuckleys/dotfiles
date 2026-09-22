-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

hl.on("hyprland.start", function()
    -- -n: exit if a shell for this config is already up, so a reload
    -- of this file cannot leave two shells fighting over the same layer
    -- surfaces and the same state files.
    --
    -- Through the shell's launcher, which decides the GPU and allocator
    -- environment for whatever machine this is — see scripts/launch.sh.
    hl.exec_cmd(os.getenv("HOME") .. "/.config/quickshell/scripts/launch.sh -n")
    hl.exec_cmd("wl-clip-persist --clipboard regular")
    hl.exec_cmd("dbus-update-activation-environment --all")
    hl.exec_cmd("systemctl --user import-environment")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
