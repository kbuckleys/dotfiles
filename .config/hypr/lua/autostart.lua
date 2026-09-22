-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

hl.on("hyprland.start", function()
    -- -n: exit if a shell for this config is already up, so a reload
    -- of this file cannot leave two shells fighting over the same layer
    -- surfaces and the same state files.
    --
    -- NVIDIA's EGL only. glvnd otherwise loads Mesa's as well, and Mesa
    -- brings its gallium/LLVM software rasteriser into the shell — ~108MB
    -- of RSS, measured on a one-surface probe, for a driver this machine
    -- (one NVIDIA card) never draws with. Restarts from inside the shell
    -- (Oracle, icarus) inherit it; a `qs` started by hand does not.
    --
    -- And two malloc arenas, not one per thread. Qt decodes images on a
    -- pool of worker threads, each of which got an arena of its own that
    -- glibc then never handed back — RSS only ratcheted up. Measured on a
    -- grid of 173 wallpapers opened and put away: 64MB kept afterwards
    -- without this, 28MB with it.
    hl.exec_cmd("env __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json MALLOC_ARENA_MAX=2 qs -n")
    hl.exec_cmd("wl-clip-persist --clipboard regular")
    hl.exec_cmd("dbus-update-activation-environment --all")
    hl.exec_cmd("systemctl --user import-environment")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
