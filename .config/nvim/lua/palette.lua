-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

-- Single source of truth for the zenon palette
return {
  black           = "#000000",

  -- Surface colour for every overlay (floats, which-key, yazi, fzf). Reads as
  -- black, but is deliberately one step off it: kitty decides translucency by
  -- comparing a cell's background against the *value* of the default one --
  -- cell_vertex.glsl's background_opacity_for() is "opacity if bg == colorval
  -- else 1", with slot 0 holding the default bg. zenon.conf sets that default
  -- to #000000, so a literal-black overlay matches and inherits kitty's 0.80
  -- alpha no matter how explicitly nvim paints it. #010101 misses the compare
  -- and renders fully opaque.
  layer           = "#010101",

  lblack          = "#20242a",
  red             = "#e78284",
  green           = "#b6e0a4",
  yellow          = "#fab387",
  blue            = "#9fcbfc",
  magenta         = "#c8a4e0",
  cyan            = "#9bbfbf",
  white           = "#dfdfdd",
  bright_black    = "#6a707f",
  bright_red      = "#eebebe",
  bright_green    = "#c1e8ac",
  bright_yellow   = "#e0d8a4",
  bright_blue     = "#b3d4fd",
  bright_magenta  = "#d4b7e8",
  bright_cyan     = "#a8caca",
  bright_white    = "#dfdfdd",
}
