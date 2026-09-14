// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
// ZENON palette — single source of truth, mirrors ~/.config/nvim/lua/zenon.lua

pragma Singleton

import QtQuick
import "../oracle"

QtObject {
  // base
  readonly property color black:   "#000000"
  readonly property color surface: "#20242a"   // lblack

  // The chrome border every morpheus surface draws around itself: the pill,
  // its tooltips, its menus, the now-playing card. Solid, it was the one part
  // of those surfaces that admitted nothing — a hard dark line around a ground
  // that is mostly the blurred desktop showing through.
  //
  // Held ABOVE hyprland's ignore_alpha 0.5 deliberately, for the same reason
  // panelBg is: a border under that floor is a 1px ring of SHARP desktop
  // around an otherwise blurred surface, which is worse than the hard line it
  // was meant to soften. Not a setting — this is the shell's edge, not a
  // preference.
  readonly property color surfaceBorder:
    Qt.rgba(surface.r, surface.g, surface.b, 0.70)
  readonly property color white:   "#dfdfdd"
  readonly property color muted:   "#6a707f"   // bright_black

  // accents
  readonly property color red:     "#e78284"
  readonly property color green:   "#b6e0a4"
  readonly property color yellow:  "#fab387"
  readonly property color blue:    "#9fcbfc"
  readonly property color magenta: "#c8a4e0"
  readonly property color cyan:    "#9bbfbf"
  readonly property color pink:    "#eebebe"   // bright_red
  readonly property color sand:    "#e0d8a4"   // bright_yellow

  // derived surfaces — alpha over black so the compositor blur reads through
  //
  // hyprland refuses to blur under a pixel below its ignore_alpha, which is
  // 0.5 in rules.lua. That floor is the reason every ground in this file sits
  // where it does — layerBg at 0.80, menuBg opaque, even hoverTint chosen so
  // the row it tints composites to ~0.56 rather than falling under.
  //
  // The pill is the one surface a person can drive UNDER the floor by hand:
  // Bar opacity starts at exactly 0.50 and its slider goes down to 0.10. Every
  // step towards transparent used to hand back the blur and show the desktop
  // through sharp, which is the opposite of what asking for a see-through bar
  // is asking for. barBlur decides which side of the floor it may land on.
  // ignore_alpha in rules.lua: the alpha hyprland will not blur under.
  readonly property real blurFloor: 0.52

  readonly property color panelBg: Qt.rgba(0, 0, 0,
    Oracle.barBlur ? Math.max(Oracle.barOpacity, blurFloor) : Oracle.barOpacity)

  readonly property color panelBgDeep: "#b3000000"
  readonly property color dim:        "#506060"   // muted cyan, inactive workspace

  // Module titles — CPU, GPU, RAM. Deliberately not an accent: the labels are
  // furniture, and the readings are what you look at.
  readonly property color title:      muted

  readonly property color sparkFill: "#339bbfbf"

  // ── a layer's own furniture ──────────────────────────────────────────
  // Every popup layer was carrying its own copy of these four hexes. They are
  // one palette, not twelve, so they live here: layerBg is a layer's ground,
  // headBg the strip its title sits on, msgBorder the hairline under it, and
  // selBg the fill of a selected or pressed row. keyInk is the ink a hint's
  // KEY is set in, against Zenon.muted for the word beside it.
  readonly property color layerBg:   Qt.rgba(0, 0, 0, Oracle.panelOpacity)
  // A MENU's ground, which is a different question from a layer's. A layer
  // is a panel belonging to the bar and the blur behind it is most of how it
  // looks; a menu is a small card floating over whatever you were reading,
  // and at the layers' alpha the text underneath reads straight through its
  // rows. Opaque by default for that reason, and its own setting because
  // "how solid is a panel" and "how solid is a menu" are two answers.
  readonly property color menuBg:    Qt.rgba(0, 0, 0, Oracle.menuOpacity)

  // ── WHAT A MENU CARD IS ───────────────────────────────────────────────
  // There are four menus on this desktop — icarus' desktop menu, the tray's,
  // terminus' right-click menu, and CardMenu, which picasso and the settings
  // dropdowns wear — and they are meant to be one object, not four takes on
  // one idea. They had drifted: three different row heights, two separator
  // heights, two grounds, radii hardcoded in some and read from the setting
  // in others. Every one of them now reads these, so the four cannot come
  // apart again without someone editing this block.
  //
  // Routed through Zenon rather than read from Oracle directly, because
  // terminus does not import oracle and should not have to: a token is what
  // Zenon is for.
  readonly property int menuRadius:    Oracle.menuRadius
  readonly property int menuWidth:     Oracle.menuWidth
  readonly property int menuRowHeight: Oracle.menuRowHeight
  readonly property int menuSepHeight: 7
  readonly property int menuCardPad:   4    // the column's inset in the card
  // The air between a row's icon and its label. The icon sits in a 16px box
  // and most Font Awesome glyphs do not fill it, so the gap reads narrower
  // than the number suggests — 8 had the two touching on the wider marks.
  readonly property int menuIconGap:   12
  readonly property color menuSepInk:  msgBorder

  // A MENU INSIDE A WINDOW, which cannot be frosted and so is not translucent.
  //
  // The layer menus — icarus', the tray's, picasso's — sit on the desktop, and
  // hyprland blurs what is behind a surface, so lowering menuOpacity there
  // frosts the wallpaper. Terminus' right-click menu is an item INSIDE the
  // terminus window: what is behind it is terminus' own rows, which no
  // compositor rule can reach. Translucent, it is a card with sharp text
  // showing through it rather than a frosted one.
  //
  // So it is solid, which is what a menu over your own work wants anyway.
  readonly property color menuBgSolid: Qt.rgba(0, 0, 0, 1)

  // A DIALOG's corner, which is not a menu's. Terminus' cards — properties,
  // permissions, confirmations, the path bar, the app picker — are larger
  // surfaces that sit in the middle of your work, and they have always used
  // 10 where a menu uses 6. Written out seven times, and their shadows were
  // told 6 regardless: with a hollow shadow that cuts the hole SMALLER than
  // the card at each corner, leaving four dark slivers inside them.
  readonly property int dialogRadius: 10

  // WHERE A CARD THAT HANGS OFF ANOTHER ONE GOES: its parent's right side if
  // there is room, its left if not, and clamped only when neither side fits.
  //
  // One definition. There were four — CardMenu's, and a copy in each of the
  // three icarus submenus that predate it — and the copies are where two of
  // this shell's placement bugs lived: one clamped against the SHADOW's
  // padding instead of a screen margin and held every menu 80px off the
  // edges, and one used NaN as a sentinel that a QML real does not carry.
  //
  // `gap` is how close a card may come to a screen edge. Not the shadow's
  // padding — that is decoration and may clip against the edge.
  function hingeX(parentLeft, parentW, w, screenW, gap) {
    const right = parentLeft + parentW;
    if (right + w <= screenW - gap) return right;
    const left = parentLeft - w;
    if (left >= gap) return left;
    return Math.max(gap, Math.min(right, screenW - w - gap));
  }

  // HOW A MENU ARRIVES. Every menu on this desktop grows out of its own
  // top-left corner rather than appearing at full size, so a card unfolds FROM
  // the thing that opened it instead of expanding around its own middle. The
  // numbers were written out identically in five places and the tray had none
  // of them at all — it simply blinked into existence.
  readonly property int  menuFade: fast
  readonly property real menuScaleFrom: 0.94
  function menuScale(shade) {
    return menuScaleFrom + (1 - menuScaleFrom) * shade;
  }
  readonly property color headBg:    "#66282f36"
  readonly property color msgBorder: "#4d45505c"
  readonly property color selBg:     "#4d45505c"
  readonly property color keyInk:    "#a2a8bc"
  // Hover tint for menu rows. A light scrim rather than a fill: on a dark
  // translucent panel a *darker* overlay reads as a shadow, and an opaque one
  // punches a sharp unblurred block into an otherwise blurred surface. At this
  // alpha the row composites to ~0.56 over panelBg — above hyprland's
  // ignore_alpha 0.5, so the blur still carries, and the backdrop shows through.
  readonly property color hoverTint: Qt.rgba(1, 1, 1, 0.12)

  // ── spacing ──────────────────────────────────────────────────────────
  // Four values, and only four. padModule is a module's own breathing room,
  // gap is the space between two neighbours, padBar is the pill's end caps,
  // padScreen is the pill's clearance from the screen edge.
  // A Divider carries a gap on each side itself, so it never needs spacers.
  readonly property int padModule: Oracle.barPadModule
  readonly property int gap:       Oracle.barGap
  readonly property int padBar:    Oracle.barPadBar
  // the clearance the pill keeps from the screen edge. Every layer reuses it,
  // so a layer spawned on a monitor that has no pill still sits exactly where
  // it would have sat morphed into one.
  readonly property int padScreen:  Oracle.barScreenPad
  // Every module occupies a slot of this height, and BarText fills it, so a
  // short label beside a taller sibling still sits on the bar's centre line.
  readonly property int slot:      Oracle.barSlot
  // the bar's type size; every module reads it through BarText
  readonly property int textSize:  Oracle.barTextSize
  // the pill and every layer's corner radius — uniform on all four corners, no
  // morph. A single token so the bar, cynosure, and all other layers stay even
  // without duped literals, and one setting moves all of them together.
  readonly property int pillRadius: Oracle.barRadius

  // ── how wide a layer may be ──────────────────────────────────────────
  // Every layer used to write 1000 into its own panel, and shell.qml wrote it
  // a second time into the width it gives the morphed pill. Those two numbers
  // MUST agree: morphed, a layer scales itself by pill width over panel width,
  // so a pill that was told 900 while the panel still believed 1000 does not
  // narrow the layer, it squashes it by a tenth.
  //
  // So there is one number, and one function that applies it. A layer asks for
  // the width it wants; both sides call this with the same argument and cannot
  // come out different.
  readonly property int layerMax: Oracle.barMaxWidth
  function layerWidth(want) {
    // EVEN, ALWAYS. Every layer is centred — the pill by its own margins,
    // the rest by anchors.horizontalCenter — and centring an ODD width
    // inside an even-width monitor puts the whole panel on a half pixel.
    //
    // That is not a cosmetic half pixel. Each of these panels clips through
    // a ClippingRectangle to keep square children inside its rounded
    // corners, and a clipped subtree is drawn through a texture: sampled
    // half a pixel off, the texture is resampled and every glyph in it goes
    // soft at once. Measured side by side — the same string in the same
    // clipped box at x and at x + 0.5 — and the second is visibly smeared.
    //
    // Most widths here are literals and already even. The ones that are not
    // are the shrink-wrapped ones: cynosure's content width, chronos'
    // calendar grid, artemis' panel. Rounding down to even here fixes all of
    // them in one place. Panels that position themselves explicitly round
    // their own x instead — see OraclePopup and ZeusPopup.
    const w = Math.min(layerMax, want);
    return 2 * Math.floor(w / 2);
  }

  // ── THE SHELL'S TYPE ─────────────────────────────────────────────────
  // One family, three cuts, and every one of them derived from a single
  // setting. Nerd Fonts ship a proportional cut, a strictly monospaced one,
  // and the plain one in between; this shell uses all three — labels are
  // proportional, the lock's clock and the mark are monospaced, and the
  // column-aligned tables in zeus and terminus need the plain fixed cut —
  // and they must be the SAME family or a panel looks like two fonts.
  //
  // The family name was written out 279 times before this. That is 279
  // places to edit to change the shell's type, and 279 chances for one of
  // them to be missed, which is exactly the kind of thing that leaves one
  // label in a corner still set in the old face.
  readonly property string face:      Oracle.fontFamily + " Propo"
  readonly property string faceMono:  Oracle.fontFamily + " Mono"
  readonly property string faceFixed: Oracle.fontFamily

  // ── the clock's face ─────────────────────────────────────────────────
  // A seven-segment LCD, the way an old bedside clock renders. DSEG covers
  // digits, the colon and a rough alphabet, but none of the nerd glyphs the
  // rest of the bar uses — so it is named here rather than set on BarText,
  // and only the clock ever asks for it.
  readonly property string clockFamily: "DSEG7 Classic"
  // DSEG's digits stand taller than JetBrains' at the same nominal size, so
  // the clock is set two pixels smaller and still reads level with the rest
  // of the bar. Expressed against textSize rather than written out, so the
  // two cannot drift if the bar's type changes again.
  readonly property int clockSize: textSize - 2

  // ── elevation ────────────────────────────────────────────────────────
  // What a layer's drop shadow is made of. Tuned in one place so the whole
  // set stays consistent — morpheus itself casts none: the pill is the ground
  // floor, and a shadow under it would make the layers it morphs into look
  // like they were peeling off it.
  //
  // Spoot's numbers, adapted: spoot grow 10 blur 64 drop 14 alpha
  // 0.34 on a 28px lift panel. Quickshell's pill sits only 6px off
  // the edge, so the full 88px pad would be clipped. Grow 4 blur
  // 24 drop 6 alpha 0.60 keeps the same soft, present read but
  // stays inside the overlay window and shows on a dark desktop.
  readonly property color shadowInk:  Qt.rgba(0, 0, 0, Oracle.shadowStrength)
  readonly property int   shadowGrow: 4
  readonly property int   shadowBlur: 24
  readonly property int   shadowDrop: 6
  readonly property int   shadowPad: shadowGrow + shadowBlur + shadowDrop

  // ── the shadow a MENU's BORDER casts ──
  //
  // It hangs off the EDGE, not off the body: MenuShadow is hollow, so what
  // these describe is a ring. As dark and as wide as it can be without
  // crossing the one line that matters.
  //
  // THE LIMIT IS THE INK, NOT THE SIZE. hyprland blurs any pixel above
  // ignore_alpha (0.5 in rules.lua) and cannot tell a shadow from a ground —
  // one alpha channel, one surface — so a shadow over that line gets the
  // desktop blurred behind it, and against a card too transparent to be
  // blurred itself that reads as a frosted ring. UNDER the line none of that
  // happens at any size, which is why Shadow is capped at 0.48
  // and the geometry below is not.
  //
  // SAME INK AS A PANEL'S, one setting for both, because one desktop should
  // be lit by one lamp. The GEOMETRY differs and has to: a panel is a layer
  // surface sitting a few pixels off a screen edge, so a shadow this wide
  // would be clipped by its own window and never drawn. A menu floats in the
  // middle of the screen with room around it, so it gets the full spread.
  //
  // GROW IS MOST OF WHAT MAKES IT DARK. A blurred rounded rect is only about
  // half covered at the edge of its own shape, so with a small grow the ring
  // never reaches the ink it was given — it peaked near half of it. Twenty
  // pixels of full strength before the falloff starts is the part you
  // actually see against a bright wallpaper.
  readonly property color menuShadowInk:  shadowInk
  readonly property int   menuShadowGrow: 20   // full strength this far out
  readonly property int   menuShadowBlur: 50   // then a long, smooth falloff
  readonly property int   menuShadowDrop: 10   // and a direction for the light
  readonly property int   menuShadowPad: menuShadowGrow + menuShadowBlur + menuShadowDrop

  // ── motion ──
  // Shared timings and curve, so every module and every layer eases
  // identically. OutQuint rather than OutCubic: it puts more
  // of the travel in the first third and lands softer, so the same move reads
  // as both quicker off the mark and gentler on arrival.
  //
  // Each is its own number times Oracle's one multiplier, so the whole shell
  // slows down or speeds up together — a layer easing at a different rate from
  // the pill it is morphing out of is the one way this shell can look broken
  // rather than merely different. At a scale of 0 they are all zero, which Qt
  // reads as "no animation": every Behavior in here then lands on frame one.
  readonly property int fast:   Math.round(110 * Oracle.motionScale)
  readonly property int normal: Math.round(140 * Oracle.motionScale)
  readonly property int slow:   Math.round(170 * Oracle.motionScale)
  readonly property int ease:   Easing.OutQuint

  // THE CURVE FOR SOMETHING THAT TRAVELS, as opposed to something that
  // appears. `ease` above is quintic, which is right for a panel arriving:
  // it is over almost at once and the tail is not really seen.
  //
  // A thing moving ACROSS a surface is seen the whole way, and quintic puts
  // seven tenths of the distance in the first fifth of the time — a handful
  // of frames carrying nearly all the movement, then a long crawl. It reads
  // as a lurch followed by drift, which is exactly what it is. Cubic spends
  // the time far more evenly, so each frame carries a similar distance and
  // the move lands instead of settling.
  readonly property int travelEase: Easing.OutCubic


  // ── the arrival ──────────────────────────────────────────────────────
  // Moved to Arrival.qml. When the session's first animation plays is a
  // question about the boot, not a design token, and it had grown a frame
  // clock and a trace file that had no business living in the palette.

  // An item inside a layer-shell surface has window-local coordinates. This
  // is that window's own top-left in screen space, so the two can be added.
  // Written once: every popout that anchors to a bar module needs it, and the
  // one that skipped it landed a side-margin off.
  function winOrigin(w, screen) {
    if (!w || !screen) return Qt.point(0, 0);
    return Qt.point(
      w.anchors.left ? w.margins.left : screen.width - w.margins.right - w.width,
      w.anchors.top ? w.margins.top : screen.height - w.margins.bottom - w.height);
  }

  // ── WHICH EDGE THE BAR LIVES ON ──────────────────────────────────────
  // One boolean, read by the pill, by every layer that opens out of it, by
  // the toast stack and by the tooltips. They must all agree: a layer that
  // stayed at the bottom while the pill moved to the top would be opening out
  // of nothing, and a tooltip that still pointed upwards would be pointing at
  // the bar it was trying to get out from under.
  readonly property bool barTop: Oracle.barPosition === "top"

  // How far a layer's near edge sits from the screen edge the bar is on. One
  // definition for every layer, so a layer opened on a monitor that has no
  // pill lands at exactly the offset it would have had morphed into one. On
  // the pill's own screen, and not morphed into it, it additionally clears
  // the pill.
  //
  // Named for the EDGE rather than for the bottom: it was bottomLift while
  // the bottom was the only place the bar could be, and a function called
  // bottomLift feeding a topMargin is a lie that someone will eventually
  // believe.
  function edgeLift(morphed, screen, statusbar) {
    if (morphed) return padScreen;
    const onPill = screen && statusbar && statusbar.screen
      && screen.name === statusbar.screen.name;
    return padScreen + (onPill ? statusbar.height : 0);
  }

  // Unlit meter notch: the accent dimmed, so a meter reads as one colour
  // whether its segments are lit or not. Kept well clear of the lit segment
  // in both brightness and alpha — but not so faint that the meter's own
  // shape disappears, which is what the first pass at these numbers did.
  function trough(c) {
    return Qt.rgba(c.r * 0.62, c.g * 0.62, c.b * 0.62, 0.42);
  }

  // 6-digit hex for markup that needs a string (StyledText <font color=...>);
  // QML's color->string gives #AARRGGBB, which Qt's rich text won't parse
  function hex(c) {
    const b = (v) => Math.round(v * 255).toString(16).padStart(2, "0");
    return "#" + b(c.r) + b(c.g) + b(c.b);
  }
}
