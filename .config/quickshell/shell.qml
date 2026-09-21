// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
// MORPH PILL BAR - dynamic width max 1000, slide, all layers morph, reserves space

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "morpheus"
import "cynosure"
import "folio"
import "erebus"
import "artemis"
import "lexi"
import "zeus"
import "ideo"
import "calypso"
import "metis"
import "howler"
import "cerberus"
import "socordia"
import "picasso"
import "chronos"
import "icarus"
import "clio"
import "terminus"
import "oracle"

ShellRoot {
  id: root

  // keep popups for logic, but UI will be morphed via bar
  // the notification daemon's on-screen half. Not a morph layer: toasts
  // arrive on their own schedule rather than being opened, so they stack
  // above the pill instead of becoming it.
  HowlerToasts { statusbar: bar; screen: root.focusedScreen }
  // the wallpaper, on its own background layer per monitor
  PicassoDaemon { }
  IcarusPopup { id: icarus; screen: root.focusedScreen }
  IcarusDesktop { id: icarusDesktop; popup: icarus }

  // The notes left on the desktop. Not a morph layer and not on the pill: a
  // note is a thing you put down and walk away from, so it has no opener to
  // become and nothing to open out of.
  //
  // DECLARED AFTER ICARUS' DESKTOP, and that is load-bearing. Both sit on the
  // bottom layer and icarus' catcher masks the WHOLE screen — it is what
  // turns a click on empty desktop into the menu. Within one layer the later
  // surface stacks on top, so declared first the notes sat underneath it and
  // every click aimed at one opened the menu instead: no press, no hover,
  // nothing. A note has to be above the thing whose whole job is catching
  // what misses everything else.
  ClioBoard { }

  // The file manager. NOT in the morph ring and not in the height switch
  // below: it is a real xdg-toplevel, so hyprland owns its size and position
  // the way it owns a terminal's, and the pill has nothing to do with it.
  TerminusManager { id: terminus }

  CerberusLock { id: cerberus }
  // the idle daemon, in place of hypridle. It calls cerberus directly rather
  // than shelling out to `qs ipc` to reach the process it is already inside.
  SocordiaDaemon { lockscreen: cerberus }
  CynosurePopup { id: cynosure; statusbar: bar; screen: root.focusedScreen; morphMode: root.morphedFor("cynosure") && root.morphOnPill; morphFade: root.layerFade; morphRadius: root.pillRadius }
  FolioPopup { id: folio; statusbar: bar; screen: root.focusedScreen; morphMode: root.morphedFor("folio") && root.morphOnPill; morphFade: root.layerFade }
  ErebusPopup { id: erebus; statusbar: bar; screen: root.focusedScreen; morphMode: root.morphedFor("erebus") && root.morphOnPill; morphFade: root.layerFade; morphRadius: root.pillRadius }
  ArtemisPopup { id: artemis; statusbar: bar; screen: root.focusedScreen; morphMode: root.morphedFor("artemis") && root.morphOnPill; morphFade: root.layerFade }
  LexiPopup { id: lexi; statusbar: bar; screen: root.focusedScreen; morphMode: root.morphedFor("lexi") && root.morphOnPill; morphFade: root.layerFade }
  // `&& !zeus.pinned`: torn off the pill, zeus is a window rather than the
  // pill's current shape, so it must stop drawing itself as one — otherwise it
  // keeps the pill's transparent ground and scales out of a bar it is no
  // longer standing on.
  // `screen`: zeus alone does not follow the focused monitor while it is open.
  // Every other layer should — a menu belongs where you are looking — but with
  // focus following the mouse, glancing at the other screen carried the whole
  // panel across with it. It picks its monitor when it opens and keeps it.
  ZeusPopup { id: zeus; statusbar: bar; liveScreen: root.focusedScreen; screen: zeus.homeScreen ? zeus.homeScreen : root.focusedScreen; morphMode: root.morphedFor("zeus") && root.morphOnPill && !zeus.pinned; morphFade: root.layerFade }
  IdeoPopup { id: ideo; statusbar: bar; screen: root.focusedScreen; morphMode: root.morphedFor("ideo") && root.morphOnPill; morphFade: root.layerFade }
  CalypsoPopup { id: calypso; statusbar: bar; screen: root.focusedScreen; morphMode: root.morphedFor("calypso") && root.morphOnPill; morphFade: root.layerFade }
  MetisPopup { id: metis; statusbar: bar; screen: root.focusedScreen; morphMode: root.morphedFor("metis") && root.morphOnPill; morphFade: root.layerFade }
  HowlerPopup { id: howler; statusbar: bar; screen: root.focusedScreen; morphMode: root.morphedFor("howler") && root.morphOnPill; morphFade: root.layerFade }
  PicassoPopup { id: picasso; statusbar: bar; screen: root.focusedScreen; morphMode: root.morphedFor("picasso") && root.morphOnPill; morphFade: root.layerFade }
  ChronosPopup { id: chronos; statusbar: bar; screen: root.focusedScreen; morphMode: root.morphedFor("chronos") && root.morphOnPill; morphFade: root.layerFade }
  // The settings, for every layer above it and for the pill itself.
  //
  // NOT IN THE MORPH RING, and the only layer that is not — so it is absent
  // from the width switch, the height switch and the Connections below, all of
  // which are about a pill wearing a layer's shape. Half the controls in here
  // move the pill while you hold them; a panel that WAS the pill would have
  // been resizing itself under the pointer on every one of them. It stands
  // free in the middle of the screen instead, and can be dragged off it.
  // `screen`: like zeus, it picks its monitor when it opens and keeps it —
  // see homeScreen there. A panel you have dragged into place must not
  // follow your eyes to the other screen.
  OraclePopup { id: oracle; liveScreen: root.focusedScreen; screen: oracle.homeScreen ? oracle.homeScreen : root.focusedScreen }

  // Which monitor the pill lives on. A BINDING now, not a function called
  // once: the name is a setting, and the point of it being a setting is that
  // it can change while the shell is running. Written out as an IIFE it was
  // evaluated at load and never again, so oracle could set it and nothing
  // would move until a restart.
  //
  // Oracle first, then the environment variable that used to be the only
  // answer, then whatever screen there is — the same order, with one door
  // added in front.
  readonly property var statusScreen: {
    const screens = Quickshell.screens;
    // Oracle, then the environment variable that used to be the only answer,
    // and then nothing — NOT a monitor name written into the source. The old
    // fallback was "HDMI-A-1", which is one desk's output: on any machine
    // without it the loop below matched nothing and fell through to the first
    // screen anyway, so the name was doing no work except to look like a
    // decision somebody had made for you.
    const target = Oracle.barMonitor !== "" ? Oracle.barMonitor
      : Quickshell.env("QS_STATUS_SCREEN");
    if (target) {
      for (let i = 0; i < screens.length; ++i)
        if (screens[i].name === target) return screens[i];
    }
    return screens.length ? screens[0] : null;
  }

  // ── MOVING THE PILL TO ANOTHER OUTPUT ─────────────────────────────────
  // A layer-shell surface belongs to the output it was created on and cannot
  // be handed to another one. Rebinding `screen` takes it off the old output
  // without putting it on the new: the pill simply vanished when Monitor was
  // changed in settings, and only a shell restart brought it back.
  //
  // So it is taken down and put back up. One frame down is enough for the
  // compositor to destroy the surface and let quickshell build a fresh one
  // against the screen the binding now names.
  onStatusScreenChanged: {
    if (!root.statusScreen) return;
    bar.visible = false;
    barReattach.restart();
  }

  Timer {
    id: barReattach
    interval: 1
    onTriggered: bar.visible = true
  }

  property string activeLayer: ""
  property bool layerOpen: activeLayer !== ""

  // ── morph state ───────────────────────────────────────────────────────────
  // Two different questions, deliberately answered by two different properties:
  //
  //   activeLayer  — "how big should the pill be". Cleared the instant a close
  //                  BEGINS so the pill starts collapsing on frame one.
  //   morphSource  — "which layer is the pill currently wearing". Held until
  //                  that layer has finished animating out. Without it the
  //                  layer's morphMode dropped at close-start along with
  //                  activeLayer, so it snapped back to its full standalone
  //                  size and background for the whole close — the "grows
  //                  larger before morphing back" jump.
  property string morphSource: ""
  //   morphFading  — the layer that WAS wearing the pill and is still
  //                  animating out while a new one takes over. morphSource is
  //                  a single string, so opening B while A was up overwrote
  //                  it, A's morphMode dropped mid-close, and A snapped to
  //                  its full standalone size for the rest of the animation.
  //                  That snap is the "brief expand" you see going straight
  //                  from one layer to another.
  property string morphFading: ""
  // A layer is wearing the pill if it is the current one OR still leaving.
  function morphedFor(layer) {
    return layer === root.morphSource || layer === root.morphFading;
  }
  // latched at open: did the layer that owns the pill spawn on the pill's own
  // monitor. Latched rather than read live so moving focus to another monitor
  // mid-session can't un-morph a layer halfway through.
  property bool morphOnPill: false
  Timer {
    id: morphRelease
    // one pill-collapse worth of grace plus a couple of frames, so the
    // release can never land before the layer's own close animation ends
    interval: Zenon.slow + 60
    onTriggered: { root.morphSource = ""; root.morphOnPill = false; }
  }
  Timer {
    id: fadeRelease
    interval: Zenon.slow + 60
    onTriggered: root.morphFading = ""
  }
  // A close does NOT collapse the pill on the spot. The very next thing to
  // happen may be another layer opening — the two arrive from one keypress and
  // in either order — and clearing activeLayer in between sends the pill all
  // the way back to morpheus' width before it expands again. Two frames of
  // grace, cancelled by beginMorph, is the difference between a handover and
  // a bounce. A real close is delayed by those two frames and nothing else.
  Timer {
    id: layerRelease
    interval: 40
    property string pending: ""
    onTriggered: {
      if (root.activeLayer === layerRelease.pending) root.activeLayer = "";
      layerRelease.pending = "";
    }
  }
  function beginMorph(layer) {
    morphRelease.stop();
    layerRelease.stop();
    layerRelease.pending = "";
    // hand the pill over rather than yanking it: whatever was wearing it
    // keeps wearing it until its own close animation has finished, so it
    // shrinks and fades into the new layer's shape instead of snapping out
    if (root.morphSource !== "" && root.morphSource !== layer) {
      root.morphFading = root.morphSource;
      fadeRelease.restart();
    }
    root.morphSource = layer;
    root.morphOnPill = root.focusOnPillScreen;
    root.activeLayer = layer;
  }
  function endMorph(layer) {
    if (root.activeLayer === layer) {
      layerRelease.pending = layer;
      layerRelease.restart();
    }
    if (root.morphSource === layer) morphRelease.restart();
  }

  // Single token in Zenon — 8:8 uniform, no morph. Kept as a root
  // property so bg and any morphed layer can still bind to the same value
  // without each importing Zenon directly (and so a future 12:8 is one line).
  property real pillRadius: Zenon.pillRadius

  // 0 = the pill is wearing morpheus, 1 = it is fully wearing the layer.
  // Same duration and easing as every other pill Behavior, so it is an exact
  // stand-in for the pill's own visual progress. Both halves of every
  // crossfade read this one scalar, which is what keeps them from drifting.
  property real morphFactor: root.pillMorphed ? 1 : 0
  // travelEase, not ease. A morph is the pill TRAVELLING into a panel's
  // shape and it is watched the whole way; Zenon.ease is quintic, the curve
  // for something appearing, which puts seven tenths of the change in the
  // first fifth of the time and crawls through the rest.
  //
  // The crossfade below is keyed off this number, which is what made it read
  // as slow rather than merely soft: layerFade opens at 0.55, and quintic is
  // past 0.55 almost at once — so the layer stood there finished while the
  // geometry spent the remaining four fifths of the animation creeping the
  // last few percent. Cubic spends the time evenly, so the schedule below
  // means what it says.
  // THE SAME ANIMATION A DETACHED LAYER PLAYS. Not a curve chosen to feel
  // like it — literally the same duration and the same easing that every
  // popup's own showFactor uses when it opens on a monitor the pill is not
  // on. A morph is that arrival with the pill's rect as its starting shape;
  // anything else here makes it a second, different animation that happens
  // to be about the same thing.
  // LINEAR, and not because linear feels nice. morphFactor drives NOTHING
  // but the crossfade below -- the pill's own geometry snaps now (see the
  // margins block), so the curve that was chosen to match the pill
  // travelling is shaping a pure opacity schedule it no longer has anything
  // to do with.
  //
  // Composing a front-loaded curve with a clamped schedule crushes the first
  // half. Quintic reaches 0.45 at 11% of 170ms = 19ms, so pillRowFade ran
  // 1.00 -> 0.10 -> 0.00: ONE intermediate frame at 60Hz, three at 180Hz.
  // The morpheus row did not fade out, it cut out, and that is the whole of
  // why a morph looked nothing like a detached open.
  //
  // Linear spends the 170ms evenly, so each half of the crossfade gets its
  // own 76ms: 4 intermediate frames at 60Hz and 13 at 180Hz on the way out,
  // and the layer's fade-in lands on 6/16 -- which is what a DETACHED layer's
  // showFactor measures at (5/16). Same duration, same felt rate, finally.
  // ── AND LONG ENOUGH FOR BOTH HALVES TO BE SEEN ────────────────────────
  // The schedule below spends 45% of this on clearing the pill and 45% on
  // bringing the layer up, so at Zenon.slow each half got 76ms — under five
  // frames. Both halves read as cuts however the curve is shaped, because
  // there is not enough time in them to read as anything else.
  //
  // Doubled, each half gets ~153ms, which is what a DETACHED layer's own
  // entrance takes. That is the whole claim this animation makes — that a
  // morph is the same arrival with the pill's rect as its starting shape —
  // and it could not be true while the morph ran in half the time.
  //
  // The Sheet component already reaches for the same multiple, for the same
  // reason: a big object that travels is watched the whole way.
  // ── ONE DURATION FOR THE WHOLE MORPH ─────────────────────────────────
  // The pill's geometry and this crossfade have to be the same length or
  // they are two events: the shape finished growing at 170ms while the
  // layer had not begun appearing until 187ms, so you watched a panel
  // arrive and THEN fill in.
  //
  // Zenon.slow, not a multiple of it. This was doubled while the pill's
  // geometry still snapped — with no travel to watch, the crossfade was
  // the whole animation and needed the room. Now that the shape actually
  // moves, the motion carries it and the extra time only reads as drag.
  // Same duration as every other animation on this desktop, which is the
  // point: a morph should not announce itself as a special event.
  // Zenon.brisk. The morph is the one animation you sit through before you
  // can use what you asked for, so it is the one that should be quickest —
  // every other easing on this desktop is decorating something already on
  // screen. `fast` was still a beat longer than that argument allows, so
  // the scale grew a rung below it rather than this reaching past the scale
  // for a bare number: Oracle's multiplier has to keep reaching the morph or
  // the pill and the layer it becomes ease at different rates.
  readonly property int morphMs: Zenon.brisk
  Behavior on morphFactor {
    NumberAnimation { duration: root.morphMs; easing.type: Easing.Linear }
  }
  // The crossfade schedule, defined once here rather than re-derived in each
  // layer: the pill's own row has finished clearing by 0.45 and a layer only
  // starts appearing at 0.55, so the two can never be on screen together.
  // Both halves are handed the finished number, so they cannot drift apart.
  //
  // ── 30 / 70, WHICH IS MATERIAL'S SPLIT AND NOT A GUESS ─────────────
  // It was 45 out and 45 in with a DEAD ZONE between them: from 0.45 to
  // 0.55 the pill was carrying nothing at all. Ten per cent of the morph
  // spent showing an empty box is not a transition between two things, it
  // is a blink, and no curve fixes a hole.
  //
  // Material's container transform spends the first 30% clearing the
  // outgoing content and the remaining 70% bringing the incoming content
  // up, with the two ABUTTING rather than separated. The asymmetry is the
  // point: what you are leaving should get out of the way quickly, and
  // what you asked for should have room to arrive.
  //
  // ── MEASURED OFF THE PILL, NOT OFF A CLOCK ───────────────────────────
  // These keyed off morphFactor, which is a LINEAR timer, while the pill's
  // shape ran a front-loaded curve over the same duration. Two different
  // curves on one event: one frame into a collapse the shape had travelled
  // 62% of the way while the timer said 10%, so the layer's text was still
  // at 86% opacity over a pill that had already shrunk past it — text
  // hanging in mid-air off both rounded ends. That is the "stretching".
  //
  // morphFactor's own comment said it drives nothing but this crossfade, so
  // linear was safe. That stopped being true the moment the geometry got a
  // curve of its own, and nothing connected the two facts.
  //
  // So the crossfade is now a function of where the pill ACTUALLY IS. The
  // two cannot drift, whatever curve or duration the shape is given, because
  // they are no longer two things.
  readonly property real morphProgress: {
    const a = root.barWidthCollapsed;
    const b = root.morphW;
    // A layer no wider than the pill gives the geometry nothing to measure
    // against, and dividing by that gap would peg this at 0 and leave the
    // layer permanently invisible. Fall back to the timer there — with no
    // shape change there is also nothing for the fade to be out of step
    // with, which is the only reason this property exists.
    if (b - a < 8) return root.morphFactor;
    return Math.max(0, Math.min(1, (bar.pillWidth - a) / (b - a)));
  }

  // MORPHEUS NEVER SPILLS, so its half keeps the generous window: its row
  // is built to the collapsed pill's width, so a growing pill is always
  // bigger than it and a shrinking one arrives at exactly its size. It
  // clears over the first 30% opening and arrives over the last 70%
  // closing, which is Material's split and costs nothing here.
  readonly property real pillRowFade: root.pillMorphed
    ? 1 - Math.min(1, root.morphProgress / 0.30)
    : Math.max(0, Math.min(1, (0.70 - root.morphProgress) / 0.70))

  // ── THE LAYER IS DIFFERENT, AND NOT BY TASTE ────────────────────────
  // A layer's panel is a fixed width — its own, whether that is a literal
  // or shrink-wrapped — and all but cynosure and folio hold it flat through
  // the morph rather than tracking the pill, so for all but the last sliver
  // of the travel their content is WIDER THAN THE CONTAINER. Any opacity it
  // has while that is true is text hanging past the rounded ends.
  //
  // So this is not a schedule, it is a geometric fact, and it reads the
  // same in both directions for that reason: the layer may be visible in
  // proportion to how nearly the pill is full size, and that sentence does
  // not care which way the pill is going. The two CURVES supply the timing
  // instead — the entrance spends its time growing so the layer arrives at
  // the end; the exit holds, so the layer is gone before the shape moves.
  //
  // 0.85 is where the two costs cross. Measured over the real widths:
  //   0.70 -> 30px of overhang, 5.0 frames of fade
  //   0.85 -> 15px of overhang, 3.7 frames of fade
  //   0.95 ->  5px of overhang, 2.2 frames — which is a cut again
  // 15px at half opacity is about one character, ghosted, for one frame.
  readonly property real layerFade:
    Math.max(0, Math.min(1, (root.morphProgress - 0.85) / 0.15))
  // monitor awareness: layers spawn on the focused monitor; they only
  // morph out of the pill when that monitor is the pill's own
  readonly property var focusedScreen: {
    // THE POINTER FIRST, WHEN IT IS OVER THE DESKTOP. Hyprland's focused
    // monitor follows the focused WINDOW, and over bare desktop there is no
    // window to follow — so it keeps naming the screen your last window was
    // on, and a panel opened from the desktop menu spawned there instead of
    // under your cursor. icarusDesktop has a surface on every output and
    // knows where the pointer is; when it says nothing the pointer is over a
    // window, and then the focused monitor is right by definition.
    if (icarusDesktop && icarusDesktop.pointerScreen)
      return icarusDesktop.pointerScreen;
    const m = Hyprland.focusedMonitor;
    if (!m || !m.name) return statusScreen;
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; ++i)
      if (screens[i].name === m.name) return screens[i];
    return statusScreen;
  }
  // the pill only morphs when Hyprland's focused monitor IS the pill's
  // monitor; decided purely from focus (not popup.window.screen, which lags
  // attachment and would let a foreign-monitor spawn morph the morpheus row first)
  readonly property string pillScreenName: bar.screen ? bar.screen.name : ""
  readonly property bool focusOnPillScreen: {
    const m = Hyprland.focusedMonitor;
    return m !== null && m !== undefined && m.name === root.pillScreenName;
  }
  // the pill only morphs when the open layer lives on the pill's monitor;
  // layers spawned elsewhere float independently and leave the morpheus row alone
  readonly property bool pillMorphed: layerOpen && morphOnPill

  // ── startup slide + fade ─────────────────────────────────────────────
  // The pill rises from just below its rested position while fading in, so
  // the shell's first paint reads as an arrival rather than a pop-in.
  // Slightly slower than before for a calmer arrival.
  property real barIntro: 0
  property bool _barIntroInstant: false
  Behavior on barIntro {
    enabled: !root._barIntroInstant
    NumberAnimation { duration: Arrival.duration; easing.type: Easing.OutQuint }
  }
  // interval is set at arm time — on a cold login this is whatever is LEFT of
  // Arrival.onScreenBy, not a fresh wait on top of it. See Arrival.delay().
  Timer {
    id: barIntroTimer
    interval: 60
    onTriggered: { root.barIntro = 1; Arrival.note("played"); }
  }

  // ARMED BY THE PILL'S OWN WINDOW, not by Component.onCompleted.
  //
  // On a cold login `qs` starts from hyprland.start and needs over a second to
  // get a mapped surface in front of anyone: engine startup, the whole config,
  // twenty-odd layer surfaces, a 4K wallpaper decode. Component.onCompleted
  // fires near the beginning of all that, so the 60ms wait and the 750ms slide
  // both ran to completion against a window that had not been shown yet, and
  // the very first frame the compositor ever got was already at rest. Measured
  // on a restart: no pill on screen at 0.3s, 0.6s or 1.0s, fully settled by
  // 2.2s.
  //
  // It looked right on a config reload and on unlock for exactly the reason it
  // was broken here — both of those reuse a process whose surfaces are already
  // up, so the animation and the screen were in step.
  //
  // The trigger is the pill's FIRST PRESENTED FRAME — see bar.framed below.
  // `backingWindowVisible` was the first thing tried and it is still too early:
  // measured on a cold start it goes true at +550ms while the window's first
  // frame reaches the compositor at +700ms, so a sixth of the slide was already
  // spent, and that gap grows with however slow the boot is. A frame is the one
  // event that cannot happen before there is something to see.
  //
  // Latched, so a monitor arriving late (and the surface being remade under it)
  // plays the arrival once and not twice.
  property bool barIntroArmed: false

  function startBarIntro() {
    if (root.barIntroArmed) return;
    // nothing is arriving while the lock is up; parkIntro holds it at 0 and the
    // unlock replay is what plays it
    if (cerberus.locked || cerberus.covering) return;
    root.barIntroArmed = true;
    Arrival.note("armed");
    // A DEADLINE, not a wait. Arrival.delay() subtracts however long getting
    // here took, so arming late no longer pushes the arrival later.
    barIntroTimer.interval = Arrival.delay();
    barIntroTimer.restart();
  }

  // The safety net, for a frame hook that never fires — and it must NOT be a
  // race against a slow boot. Counted from the moment the window EXISTS, not
  // from config load: a real cold login has kitty, two clipboard watchers, a
  // polkit agent and a 4K wallpaper decode all starting at once on a cold page
  // cache, and a plain 3s timer from load could easily beat the first frame to
  // it — arming the intro against a surface that was still not on screen, which
  // is the exact bug this whole mechanism exists to avoid. Gated on the window
  // being up, it can only ever fire when a frame is genuinely not coming.
  Timer {
    interval: 2000
    running: !root.barIntroArmed && bar.backingWindowVisible
    onTriggered: root.startBarIntro()
  }

    // replay wallpaper zoom + pill slide on unlock — the pill/wallpaper
   // sit at 0 while the lock is up (so no static frame shows through
   // the fade), then animate 0→1 once on unlock. No 1→0 reset on
   // unlock itself — that was the static-then-animate double.
    property double _lastUnlock: 0
    function parkIntro() {
    barIntroTimer.stop();
    root._barIntroInstant = true;
    root.barIntro = 0;
    root._barIntroInstant = false;
    Picasso.holdIntro();
  }
  Connections {
    target: cerberus
    function onLockedChanged() {
      if (cerberus.locked) parkIntro();
      else {
        const now = Date.now();
        if (now - root._lastUnlock < 1500) return;
        root._lastUnlock = now;
        root.barIntroArmed = true;
        barIntroTimer.interval = 60;
        barIntroTimer.restart();
        Picasso.replayIntro();
      }
    }
    function onCoveringChanged() {
      if (cerberus.covering) parkIntro();
    }
  }

  // dynamic pill width, max 1000, each layer retains own width
  property int morpheusContentWidth: barLayout ? barLayout.implicitWidth + 24 : 800
  property int barWidthCollapsed: Zenon.layerWidth(morpheusContentWidth)
  property int barWidthExpanded: {
    if (!layerOpen) return barWidthCollapsed;
    try {
      // follow cynosure's shrink-wrapped width exactly rather than freezing
      // the pill at the collapsed morpheus width; the 8px floor is only a guard
      // against a degenerate zero-width pill, never visible padding
      // Every width here goes through Zenon.layerWidth, and so does the
      // layer's OWN panel — the two are the same call with the same argument,
      // which is what stops the pill and the layer inside it from disagreeing
      // about how wide 1000 currently means. See Zenon.layerMax.
      if (activeLayer === "cynosure" && cynosure && cynosure.contentWidth)
        return Zenon.layerWidth(Math.max(8, cynosure.contentWidth))
      // folio shrink-wraps its longest entry the way cynosure shrink-wraps
      // its rows, so the pill has to ask it rather than assume the maximum
      if (activeLayer === "folio" && folio && folio.panelWidth)
        return Zenon.layerWidth(folio.panelWidth)
      if (activeLayer === "erebus") return Zenon.layerWidth(250)
      if (activeLayer === "artemis") return Zenon.layerWidth(artemis.panelWidth)
      // lexi is prose in three of its views and a list of short strings in
      // the other two, and only it knows which one is up
      if (activeLayer === "lexi" && lexi && lexi.panelWidth)
        return Zenon.layerWidth(lexi.panelWidth)
      if (activeLayer === "zeus") return Zenon.layerWidth(1000)
      // ideo is a whole number of emoji cells wide, and how many of those
      // there are depends on how many survived the filter
      if (activeLayer === "ideo" && ideo && ideo.panelWidth)
        return Zenon.layerWidth(ideo.panelWidth)
      if (activeLayer === "calypso") return Zenon.layerWidth(1000)
      if (activeLayer === "metis") return Zenon.layerWidth(600)
      if (activeLayer === "howler") return Zenon.layerWidth(800)
      if (activeLayer === "picasso") return Zenon.layerWidth(1000)
      // chronos is sized by its calendar grid, not stretched to the usual max
      if (activeLayer === "chronos" && chronos && chronos.panelWidth)
        return Zenon.layerWidth(chronos.panelWidth)
    } catch (e) {}
    return Zenon.layerWidth(1000)
  }
  property int currentBarWidth: pillMorphed ? barWidthExpanded : barWidthCollapsed

  // ── WHAT THE PILL IS GROWING TOWARDS ─────────────────────────────────
  // The surface is the whole output now and never changes, so none of this
  // sizes anything — morphProgress is the only reader left. It needs to
  // know how wide the pill is ON ITS WAY to, in order to say how far along
  // it is, and that is not a question barWidthExpanded can answer during a
  // collapse: it falls back to the collapsed width the instant `layerOpen`
  // goes false, which is the first thing closing a layer does. Read live it
  // would make progress jump to 1 at the start of every collapse.
  //
  // So it is LATCHED when the morph begins, and still followed while
  // morphed, because a layer's width is not fixed — cynosure's changes as
  // you filter, and the pill has to keep up with it.
  property int morphW: barWidthCollapsed
  onPillMorphedChanged: if (root.pillMorphed) root.morphW = root.barWidthExpanded
  onBarWidthExpandedChanged: if (root.pillMorphed) root.morphW = root.barWidthExpanded
  // the pill is exactly one slot tall
  property int barHeightCollapsed: Zenon.slot
  property int barHeightExpanded: {
    if (!layerOpen) return barHeightCollapsed;
    try {
      if (activeLayer === "cynosure") return Zenon.slot
      if (activeLayer === "folio" && folio && folio.calcHeight) return folio.calcHeight()
      if (activeLayer === "erebus" && erebus && erebus.calcHeight) return erebus.calcHeight()
      if (activeLayer === "artemis" && artemis && artemis.calcHeight) return artemis.calcHeight()
      if (activeLayer === "lexi" && lexi && lexi.calcHeight) return lexi.calcHeight()
      if (activeLayer === "zeus" && zeus && zeus.calcHeight) return zeus.calcHeight()
      if (activeLayer === "ideo" && ideo && ideo.calcHeight) return ideo.calcHeight()
      if (activeLayer === "calypso" && calypso && calypso.calcHeight) return calypso.calcHeight()
      if (activeLayer === "metis" && metis && metis.calcHeight) return metis.calcHeight()
      if (activeLayer === "howler" && howler && howler.calcHeight) return howler.calcHeight()
      if (activeLayer === "picasso" && picasso && picasso.calcHeight) return picasso.calcHeight()
      if (activeLayer === "chronos" && chronos && chronos.calcHeight) return chronos.calcHeight()
    } catch (e) {}
    return 320
  }

  // ── WHAT THE PILL IS CARRYING ─────────────────────────────────────────
  // Each module switch is honoured where the module itself decides whether it
  // has anything to say — a Collapsible's `active`, or a plain `visible` on
  // the ones that are ordinary Items. A RowLayout leaves an invisible child
  // out of the layout entirely, so switching one off is the same motion the
  // module already makes when it goes quiet: the pill shrink-wraps.
  //
  // The SPACERS are the part that cannot be written per-module. A Gap between
  // two meters should only be there when there is something on each side of
  // it, and which sides those are changes with every switch. So the run is
  // written down once, in layout order, and each gap asks about its own
  // position in it rather than restating the list five times over.
  readonly property var meterRun: [
    Oracle.showNetwork, Oracle.showGpu, Oracle.showCpu,
    Oracle.showMemory, root.audioShown
  ]
  readonly property bool audioShown: Oracle.showVolume || Oracle.showNowPlaying
  readonly property bool metersShown: root.meterRun.indexOf(true) >= 0

  // the gap that FOLLOWS item i of the run
  function meterGap(i) {
    let before = false;
    let after = false;
    for (let k = 0; k <= i; ++k) before = before || root.meterRun[k];
    for (let k = i + 1; k < root.meterRun.length; ++k) after = after || root.meterRun[k];
    return before && after;
  }

  // The bell's hover text: the most recent few, newest first. Built here
  // rather than in the module so the module stays a pure display.
  readonly property string notifTooltip: {
    const h = Howler.history;
    if (h.length === 0) return "No notifications";
    const lines = h.slice(0, 6).map((n) => {
      const app = (n.appName && n.appName !== "") ? n.appName : "unknown";
      return "<b>" + app + "</b>  " + (n.summary ?? "");
    });
    let tip = lines.join("\n");
    if (h.length > 6) tip += "\n… and " + (h.length - 6) + " more";
    return tip;
  }

  // global ipc to set activeLayer
  IpcHandler {
    target: "Morpheus"
    function showLayer(layer: string) { root.beginMorph(layer); }
    function hideLayer() { root.endMorph(root.activeLayer !== "" ? root.activeLayer : root.morphSource); }
  }

  // watch popups' shown to sync activeLayer (when they toggle via their own ipc)
  Connections { target: cynosure; function onShownChanged() { if (cynosure.shown) root.beginMorph("cynosure"); else root.endMorph("cynosure"); } }
  Connections {
    target: folio
    function onShownChanged() { if (folio.shown) root.beginMorph("folio"); else root.endMorph("folio"); }
    // start collapsing the pill the moment the close BEGINS. Waiting for
    // `shown` means waiting for the whole close animation to finish first,
    // which left the pill sitting there expanded and empty afterwards.
    function onCollapsingChanged() { if (folio.collapsing) root.endMorph("folio"); }
  }
  Connections { target: erebus; function onShownChanged() { if (erebus.shown) root.beginMorph("erebus"); else root.endMorph("erebus"); } }
  Connections {
    target: artemis
    function onShownChanged() { if (artemis.shown) root.beginMorph("artemis"); else root.endMorph("artemis"); }
    // start collapsing the pill the moment the close BEGINS. Waiting for
    // `shown` means waiting for the whole close animation to finish first,
    // which left the pill sitting there expanded and empty afterwards.
    function onCollapsingChanged() { if (artemis.collapsing) root.endMorph("artemis"); }
  }
  Connections {
    target: picasso
    function onShownChanged() { if (picasso.shown) root.beginMorph("picasso"); else root.endMorph("picasso"); }
    // start collapsing the pill the moment the close BEGINS. Waiting for
    // `shown` means waiting for the whole close animation to finish first,
    // which left the pill sitting there expanded and empty afterwards.
    function onCollapsingChanged() { if (picasso.collapsing) root.endMorph("picasso"); }
  }

  Connections {
    target: chronos
    function onShownChanged() { if (chronos.shown) root.beginMorph("chronos"); else root.endMorph("chronos"); }
    // start collapsing the pill the moment the close BEGINS. Waiting for
    // `shown` means waiting for the whole close animation to finish first,
    // which left the pill sitting there expanded and empty afterwards.
    function onCollapsingChanged() { if (chronos.collapsing) root.endMorph("chronos"); }
  }
  Connections {
    target: howler
    function onShownChanged() { if (howler.shown) root.beginMorph("howler"); else root.endMorph("howler"); }
    // start collapsing the pill the moment the close BEGINS. Waiting for
    // `shown` means waiting for the whole close animation to finish first,
    // which left the pill sitting there expanded and empty afterwards.
    function onCollapsingChanged() { if (howler.collapsing) root.endMorph("howler"); }
  }
  Connections {
    target: lexi
    function onShownChanged() { if (lexi.shown) root.beginMorph("lexi"); else root.endMorph("lexi"); }
    // start collapsing the pill the moment the close BEGINS. Waiting for
    // `shown` means waiting for the whole close animation to finish first,
    // which left the pill sitting there expanded and empty afterwards.
    function onCollapsingChanged() { if (lexi.collapsing) root.endMorph("lexi"); }
  }
  Connections {
    target: zeus
    function onShownChanged() { if (zeus.shown) root.beginMorph("zeus"); else root.endMorph("zeus"); }
    // start collapsing the pill the moment the close BEGINS. Waiting for
    // `shown` means waiting for the whole close animation to finish first,
    // which left the pill sitting there expanded and empty afterwards.
    function onCollapsingChanged() { if (zeus.collapsing) root.endMorph("zeus"); }
    // Dragged off, it hands the pill straight back: the bar returns to being a
    // bar while the panel carries on somewhere else on the screen.
    function onPinnedChanged() { if (zeus.pinned) root.endMorph("zeus"); }
  }
  Connections {
    target: ideo
    function onShownChanged() { if (ideo.shown) root.beginMorph("ideo"); else root.endMorph("ideo"); }
    // start collapsing the pill the moment the close BEGINS. Waiting for
    // `shown` means waiting for the whole close animation to finish first,
    // which left the pill sitting there expanded and empty afterwards.
    function onCollapsingChanged() { if (ideo.collapsing) root.endMorph("ideo"); }
  }
  Connections {
    target: calypso
    function onShownChanged() { if (calypso.shown) root.beginMorph("calypso"); else root.endMorph("calypso"); }
    // start collapsing the pill the moment the close BEGINS. Waiting for
    // `shown` means waiting for the whole close animation to finish first,
    // which left the pill sitting there expanded and empty afterwards.
    function onCollapsingChanged() { if (calypso.collapsing) root.endMorph("calypso"); }
  }
  Connections {
    target: metis
    function onShownChanged() { if (metis.shown) root.beginMorph("metis"); else root.endMorph("metis"); }
    // start collapsing the pill the moment the close BEGINS. Waiting for
    // `shown` means waiting for the whole close animation to finish first,
    // which left the pill sitting there expanded and empty afterwards.
    function onCollapsingChanged() { if (metis.collapsing) root.endMorph("metis"); }
  }

  PanelWindow {
      id: bar
      // ── ITS OWN NAMESPACE, SO THE COMPOSITOR CAN BE TOLD TO LEAVE IT ──
      // Every quickshell surface without one answers to "quickshell", and
      // this needs a rule of its own: rules.lua turns hyprland's `layers`
      // animation OFF for this name. See the note on implicitHeight — the
      // surface snaps between two sizes once per morph, and hyprland was
      // playing its own 100ms easeOutQuint over that snap, scaling the
      // pill's whole buffer down and back. Two animators, two curves, two
      // durations, one object, and only one of them was in this file.
      WlrLayershell.namespace: "morpheus-bar"
      // Either edge. Both margins are set below regardless, so the one that
      // is not anchored is simply ignored rather than needing a condition of
      // its own.
      // ── AS TALL AS THE SCREEN, BUT ANCHORED TO ONE EDGE ─────────
      // Three edges, not four. The surface still covers the whole output
      // and still never changes size — implicitHeight below is a constant —
      // but the edge it is ANCHORED to is the one the bar lives on, and
      // that matters for more than tidiness.
      //
      // wlr-layer-shell applies a surface's exclusive zone to the edge it
      // is anchored to, and a surface anchored to OPPOSITE edges has no
      // single edge to apply it to, so the zone is ignored outright.
      // Anchoring all four is what silently dropped the bar's reserved
      // space and let tiled windows slide under the pill: exclusiveZone
      // below was still set, still correct, and no longer being read.
      anchors { left: true; right: true
                bottom: !Zenon.barTop; top: Zenon.barTop }
      // ── THE SURFACE DOES NOT MOVE. THE PILL INSIDE IT DOES. ─────────
      // This read `bg.height`, and bg.height was animated — so every frame
      // of a morph resized a WAYLAND LAYER SURFACE. The margins below did
      // the same on the other axis. All three of the morph's animated
      // properties fed the surface and none of them fed anything drawn
      // inside it, which means the morph was not a QML animation at all:
      // it was thirteen configure/ack/commit round trips with the
      // compositor, at 180Hz.
      //
      // A compositor cannot hold that. It resizes the surface at once and
      // crops or stretches the buffer it already has until the client
      // catches up, so what you watch is the last frame being pulled to a
      // size it was not drawn at. THAT is the stretching, and it is why no
      // amount of re-curving fixed it — the jank was never in the easing.
      //
      // So the surface is sized to hold BOTH states and snapped there in
      // one step, and the pill is a rectangle that travels inside it. One
      // configure per morph instead of thirteen, and the motion is scene
      // graph, which Qt renders at the full refresh rate.
      screen: root.statusScreen
      // A CONSTANT, and that is the whole point of it — see the note on
      // bg's width. The surface is sized once, to the output, and never
      // resized again, so the compositor never has a geometry change to
      // animate, crop or lag behind. The pill moves inside it.
      implicitHeight: bar.screen ? bar.screen.height : 1080
      // ── AND THE PILL IS THE ONLY PART THAT TAKES CLICKS ─────────
      // A surface the size of the screen would otherwise swallow every
      // click on the desktop behind it. The mask is the input region, and
      // tracking `bg` means it follows the pill through the morph with no
      // arithmetic here to get wrong.
      mask: Region { item: bg }
      // The reserved strip never changes size. Auto followed the pill's live
      // height, and Ignore released the reservation altogether while morphed
      // — either way every tiled window on this monitor resized the moment a
      // layer opened. Pinned to the collapsed pill instead, so the desktop
      // underneath stays exactly where it is whatever the pill is doing.
      // Ignore releases the reservation altogether, so the pill floats over
      // tiled windows instead of pushing them up. Still pinned to the
      // COLLAPSED height when it is on: see above — following the live height
      // resized every window on the monitor each time a layer opened.
      exclusionMode: Oracle.barReserveSpace
        ? ExclusionMode.Normal : ExclusionMode.Ignore
      // The pill's own height, the gap it keeps under itself, and then
      // whatever is asked for OVER it. The first two are where the pill
      // physically is; the third is empty space nothing draws in, which is
      // the only way to hold a tiled window off a bar that is already as tall
      // as it is going to get.
      exclusiveZone: root.barHeightCollapsed + Zenon.padScreen
        + Oracle.barWindowGap
      color: "transparent"
      // No margins. The surface is the whole output; where the pill sits
      // inside it is bg's own x and y, which is scene graph and costs the
      // compositor nothing.
      // What the pill measures, published on the window so a layer drawing
      // itself at the pill's size can ask for the pill rather than for the
      // surface it now floats in.
      readonly property real pillWidth: bg.width
      readonly property real pillHeight: bg.height
      // AND WHERE IT IS, which size alone cannot say. The surface is the
      // whole output, so a layer asking "where does the bar end" off the
      // WINDOW gets the screen's edge and not the pill's — which is how the
      // tray menu came to open at the top of the screen rather than out of
      // the icon that was clicked. bg.y already knows which edge the bar is
      // on; this is it, published.
      readonly property real pillY: bg.y
      // travelEase on all four of these: they ARE the morph, as far as the
      // eye is concerned — the pill sliding out to a panel's margins and
      // growing to its height. Quintic put seven tenths of that change in the
      // first fifth of the time and crawled through the rest, so the shape
      // arrived nearly right and then spent the remaining four fifths
      // settling the last few pixels. A DETACHED layer has no pill geometry
      // to animate at all, which is why it read as quicker on the same 170ms.
      // ── THE PILL'S GEOMETRY ANIMATES AGAIN, AND IT HAD TO ──────────
      // It was snapped, on the reasoning that the layer draws its own
      // opaque ground so nobody can see the pill move, and that animating
      // it cost a 13x resize every frame. The first half was true and the
      // second no longer is — re-measured over repeated morphs on a 100ms
      // heartbeat: median 100ms, p90 110ms, one 256ms blip. No storm.
      //
      // And snapping it broke two things that were not obvious from here.
      // The morph became a shape appearing at full size with a crossfade
      // inside it, which is the "rough" — there is no travel to watch, so
      // it reads as a cut however the contents are eased. And cynosure
      // stopped easing while morphed: it follows the pill's live width by
      // construction and deliberately does not run its own Behavior on top
      // of it, because the pill "eases toward the same target". Once the
      // pill stopped easing, nothing did, and filtering went jerky.
      //
      // travelEase, not ease: this is a thing crossing a distance and
      // watched the whole way — see the note on morphFactor.
      // No Behavior on margins.bottom either, and for the same reason as
      // the side margins: it is the SURFACE's offset, not the pill's. It is
      // a constant now in any case — the pill grows upward inside a surface
      // whose bottom edge never moves.

    // The pill's own first frame. QQuickWindow.frameSwapped fires once the
    // window has actually handed a buffer over, which is the earliest moment
    // anything in here can have been seen — so it is where the arrival starts.
    //
    // Gated on ARMED, not on "a frame has happened". Latching on the frame
    // meant a first frame that arrived while the lock was up disconnected this
    // for good, and startBarIntro's refusal became permanent — the arrival then
    // never played for that session. Gated this way it simply tries again on
    // the next frame, and the lock states are in the condition so nothing runs
    // at 180Hz through a long lock.
    Connections {
      target: bg.Window.window
      enabled: !root.barIntroArmed && !cerberus.locked && !cerberus.covering
      function onFrameSwapped() { root.startBarIntro(); }
    }

    // ── AND THE PILL CASTS ONE TOO ────────────────────────────────
    // Every other panel in this shell has had a shadow since LayerShadow
    // was written; the bar never did, so the one surface that is always
    // on screen was the one sitting flat on the desktop.
    //
    // No `morphed` here, and that is the difference: morphed is how a
    // POPUP says "I am the pill right now, the pill casts for me". This
    // IS the pill. It casts whatever is morphed out of it, which is what
    // keeps exactly one shadow under it at all times.
    LayerShadow {
      panel: bg
      cornerRadius: root.pillRadius
    }

    Rectangle {
      id: bg
      // ── THE PILL IS THE THING THAT TRAVELS ────────────────────────
      // It used to be `width: parent.width` — the pill WAS the surface, so
      // every frame of the morph was a surface resize and nothing moved
      // inside the scene at all. Now the surface is static (see
      // bar.implicitHeight) and these two are what animate, which is a
      // texture being drawn at a different size: free, and at the full
      // refresh rate.
      width: root.currentBarWidth
      height: root.pillMorphed ? root.barHeightExpanded : root.barHeightCollapsed
      // Centred in the surface and pinned to the screen's edge. Both are
      // DERIVED from the animated size rather than animated themselves, so
      // there is no second curve to drift out of step with the first — a
      // pill whose width and x ease separately grows lopsided.
      //
      // Centred across the output, and held off the edge it lives on by
      // the screen padding the surface's margins used to supply. Measured
      // against bar.width/height, which are now constants — the surface is
      // the output and never moves, so there is no longer any difference
      // between the size we asked for and the size we are drawn in.
      x: Math.round((bar.width - bg.width) / 2)
      y: Zenon.barTop ? Zenon.padScreen
                      : Math.max(0, bar.height - Zenon.padScreen - bg.height)
      // Both axes, or the pill grows sideways and jumps vertically.
      // morphCurve, not travelEase: this is a thing GROWING INTO PLACE
      // rather than crossing a distance — see the note in Zenon.
      // ── OPENING AND CLOSING ARE NOT THE SAME MOVE ────────────────
      // An exit is not an entrance played backwards, and Material names two
      // curves for exactly that reason. Read at the moment the animation
      // starts, which is the moment pillMorphed changes, so each direction
      // gets its own — see the notes on both in Zenon.
      Behavior on width {
        NumberAnimation {
          duration: root.morphMs
          easing.type: Zenon.morphCurve
          easing.bezierCurve: root.pillMorphed
            ? Zenon.morphBezier : Zenon.morphExitBezier
        }
      }
      Behavior on height {
        NumberAnimation {
          duration: root.morphMs
          easing.type: Zenon.morphCurve
          easing.bezierCurve: root.pillMorphed
            ? Zenon.morphBezier : Zenon.morphExitBezier
        }
      }
      // What the pill actually measures right now, for the layers that draw
      // themselves at its size. They read `statusbar.width` before, which
      // was the same number until the surface stopped being the pill.
      readonly property real pillW: bg.width
      readonly property real pillH: bg.height
      color: Zenon.panelBg
      border.color: Zenon.surfaceBorder
      border.width: 1
      // single uniform radius so all four corners stay even during morph
      radius: root.pillRadius
      clip: true
      opacity: root.barIntro
      // Rises INTO the screen from whichever edge it lives on: up from below
      // at the bottom, down from above at the top. A pill at the top that
      // still slid upwards would arrive by leaving.
      transform: Translate {
        y: (Zenon.barTop ? -1 : 1) * (1 - root.barIntro) * 22
      }

      // The now-playing takeover. Drawn at pill level and not inside the
      // module, for two reasons: it has to reach past the bar's own right
      // padding to the pill's edge, and it has to round off with the pill's
      // corner rather than ending in a square one just short of it.
      //
      // Its left edge is summed down the layout chain rather than mapped,
      // because mapFromItem is a function call and would not re-run when a
      // module beside it changes width.
      // Starts just past the divider's rule, not at the module's own left
      // edge. A Divider carries a gap on EACH side, so the module begins a
      // full Zenon.gap right of the 1px line — measuring from there left a
      // strip of bare pill between the divider and the green.
      readonly property real takeoverX:
        Zenon.padBar + audioGroup.x + nowMod.x - Zenon.gap
      // It runs to the pill's edge only when nothing follows it. With the
      // status icons up it stops at the module's own right edge and stays
      // square: taking over the END of the bar is one thing, painting across
      // the mic and recording indicators is another.
      readonly property bool takeoverToEdge: !statusMod.active
      readonly property real takeoverW: bg.takeoverToEdge
        ? Math.max(0, bg.width - bg.takeoverX - bg.border.width)
        // gap on both sides of now playing, plus 1px to sit 0.5px beyond
        // the divider line on the right — otherwise a blank strip shows
        // between the green wash and the status divider when status is up
        : Math.max(0, nowMod.width + Zenon.gap * 2 + 1)
      Rectangle {
        id: takeover
        // Faded rather than switched. BarText already eases its colour, so
        // without this the green vanished in one frame while the text was
        // still crossfading from black — half a beat of black on black.
        visible: nowMod.active && opacity > 0.01
        opacity: root.pillRowFade * (NowPlaying.playing ? 1 : 0)
        Behavior on opacity {
          NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease }
        }
        // A wash the pill takes on, not a block sitting on it — dim enough
        // that the green text keeps its own weight against it. The alpha
        // lives in the colour, not in `opacity`, which is already carrying
        // the fade in and out.
        color: Qt.rgba(Zenon.green.r, Zenon.green.g, Zenon.green.b, 0.18)
        // Inset by the pill's own stroke, and rounded to the INNER curve.
        // Sitting flush to bg's bounds put the green on top of the 1px border
        // with a corner struck at the outer radius, so the two arcs did not
        // nest and the join showed as a sliver.
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: bg.border.width
        anchors.bottomMargin: bg.border.width
        // placed from the left rather than anchored right, because it no
        // longer always ends at the right edge
        x: bg.takeoverX
        width: bg.takeoverW
        topRightRadius: bg.takeoverToEdge
          ? Math.max(0, bg.radius - bg.border.width) : 0
        bottomRightRadius: bg.takeoverToEdge
          ? Math.max(0, bg.radius - bg.border.width) : 0
        Behavior on width {
          NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease }
        }
      }

      // special workspace wash — gap-to-gap, but when update+notifications are
      // collapsed the left gap would leave a 4px strip before the pill's
      // rounded edge. Extend to the pill's edge with inner radius in that case.
      readonly property bool leftHasContent: notifMod.active || updateMod.active
      readonly property real specialX: bg.leftHasContent ? Zenon.padBar + workspacesMod.x - Zenon.gap : bg.border.width
      readonly property real specialW: bg.leftHasContent ? workspacesMod.width + Zenon.gap * 2 : Zenon.padBar + workspacesMod.x + workspacesMod.width + Zenon.gap - bg.border.width
      Rectangle {
        id: specialTakeover
        visible: workspacesMod.visible && workspacesMod.specialWorkspace !== null
                 && opacity > 0.01
        opacity: root.pillRowFade
          * ((workspacesMod.visible && workspacesMod.specialWorkspace !== null) ? 1 : 0)
        Behavior on opacity { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
        color: workspacesMod.specialFocused
          ? Qt.rgba(Zenon.red.r, Zenon.red.g, Zenon.red.b, 0.22)
          : Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.18)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: bg.border.width
        anchors.bottomMargin: bg.border.width
        x: bg.specialX
        // 1px extra on the right so tray mode with special never shows a black strip next to the divider
        width: bg.specialW + 1
        radius: 0
        topLeftRadius: bg.leftHasContent ? 0 : Math.max(0, bg.radius - bg.border.width)
        bottomLeftRadius: bg.leftHasContent ? 0 : Math.max(0, bg.radius - bg.border.width)
      }

      // tray sunrise wash — gap-to-gap like special, but warm and at bg level
      // so it fills the 1px strip on the right that the inner Workspaces wash
      // (clipped to the module) cannot reach in tray mode
      readonly property real trayGlowX: bg.leftHasContent ? Zenon.padBar + workspacesMod.x - Zenon.gap : bg.border.width
      readonly property real trayGlowW: bg.leftHasContent ? workspacesMod.width + Zenon.gap * 2 : Zenon.padBar + workspacesMod.x + workspacesMod.width + Zenon.gap - bg.border.width
      Rectangle {
        id: trayGlow
        visible: workspacesMod.visible && workspacesMod.hasTray && opacity > 0.01
        opacity: root.pillRowFade
          * ((workspacesMod.visible && workspacesMod.hasTray) ? 1 : 0)
        Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: bg.border.width
        anchors.bottomMargin: bg.border.width
        x: bg.trayGlowX
        // 1px extra on the right so tray mode never shows a black strip right next to the divider
        width: bg.trayGlowW + 1
        radius: 0
        topLeftRadius: bg.leftHasContent ? 0 : Math.max(0, bg.radius - bg.border.width)
        bottomLeftRadius: bg.leftHasContent ? 0 : Math.max(0, bg.radius - bg.border.width)
        topRightRadius: 0
        bottomRightRadius: 0
        // bottom half yellow, seamlessly blending into the darker upper half — no hard line
        gradient: Gradient {
          orientation: Gradient.Vertical
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.52; color: "transparent" }
          GradientStop { position: 1.0; color: Qt.rgba(Zenon.yellow.r, Zenon.yellow.g, Zenon.yellow.b, 0.28) }
        }
      }

      // morpheus content - slides out only when a layer morphs ON THIS MONITOR;
      // foreign-monitor layers leave the morpheus row fully intact
      Item {
        id: morpheusContent
        anchors.fill: parent
        visible: opacity > 0.01
        // read straight off the animated scalars — no Behavior of its own.
        // A Behavior here would be a second easing chasing an already-easing
        // target, which is what made the row lag the pill and overlap whatever
        // was fading in on top of it.
        opacity: root.pillRowFade
        x: -18 * root.morphFactor

        RowLayout {
          id: barLayout
          anchors.fill: parent
          anchors.leftMargin: Zenon.padBar
          anchors.rightMargin: Zenon.padBar
          // spacing stays 0 on purpose: every gap is a real item, so a module
          // collapsing takes its own spacing with it instead of snapping shut
          // when the layout finally drops it.
          spacing: 0

          // The updates count leads, then the bell, then the tray: the same
          // kind of thing three times over — a count of something waiting for
          // you — and the first two now wear the same orange. The bell knows
          // nothing about howler; it is handed the numbers and reports the
          // click back, like every other module in this bar.
          UpdateModule { id: updateMod; implicitHeight: Zenon.slot }
          NotificationModule {
            id: notifMod
            implicitHeight: Zenon.slot
            unread: Howler.unread
            total: Howler.history.length
            tooltipText: root.notifTooltip
            onActivated: howler.toggle()
            onCleared: { Howler.dismissAll(); Howler.clearHistory(); }
          }
          // tray lives inside workspaces now — hover to reveal, crossfades and autofits
          Collapsible {
            // and the rule this divider has always followed — something on the
            // left of it — now has a second half, because there is a switch
            // that can empty its right.
            active: (notifMod.active || updateMod.active) && Oracle.showWorkspaces
            openWidth: Zenon.gap * 2 + 1
            Divider { implicitHeight: Zenon.slot }
          }
          Workspaces {
            id: workspacesMod
            implicitHeight: Zenon.slot
            visible: Oracle.showWorkspaces
          }

          Item { Layout.fillWidth: true; implicitHeight: 1 }

          Divider { implicitHeight: Zenon.slot; visible: Oracle.showClock }
          ClockModule {
            implicitHeight: Zenon.slot
            visible: Oracle.showClock
            // the clock opens the calendar, the same way the bell opens howler
            onActivated: chronos.toggle()
          }

          // The meters, in one run. No titles and no temperatures between
          // them: they are told apart by colour — magenta/blue throughput,
          // pink gpu, red cpu, yellow ram, green volume — and a label between two
          // of them would break the row of notches that makes them read as one
          // instrument. The exact numbers are all still in the tooltips.
          // Every meter opens zeus, the way the bell opens howler — and each
          // names the view it is about, so a click lands on what you clicked
          // rather than wherever the panel was left. Clicking the same meter
          // again closes it.
          Divider { implicitHeight: Zenon.slot; visible: root.metersShown }
          NetworkModule {
            implicitHeight: Zenon.slot
            visible: Oracle.showNetwork
            onActivated: zeus.toggleAt("net")
          }
          Gap { visible: root.meterGap(0) }
          GpuModule {
            implicitHeight: Zenon.slot
            visible: Oracle.showGpu
            onActivated: zeus.toggleAt("graphs")
          }
          Gap { visible: root.meterGap(1) }
          CpuModule {
            implicitHeight: Zenon.slot
            visible: Oracle.showCpu
            onActivated: zeus.toggleAt("graphs")
          }
          Gap { visible: root.meterGap(2) }
          MemoryModule {
            implicitHeight: Zenon.slot
            visible: Oracle.showMemory
            onActivated: zeus.toggleAt("graphs")
          }
          Gap { visible: root.meterGap(3) }

          // Volume and the track name are one group with one panel between
          // them. They show the SAME panel, so hovering across from one to the
          // other used to close it and reopen it somewhere else; anchored to
          // the group instead it stays put and simply follows whichever half
          // the pointer is on. The divider keeps them visually apart and eases
          // away with the track name when nothing is playing.
          //
          // No transport glyph in here: the track name glows while something
          // is playing, which is the state that glyph reported, and the
          // controls themselves live in the panel.
          Item {
            id: audioGroup
            implicitWidth: audioRow.implicitWidth
            implicitHeight: Zenon.slot
            visible: root.audioShown
            Layout.preferredWidth: audioRow.implicitWidth
            Layout.preferredHeight: Zenon.slot

            Row {
              id: audioRow
              anchors.verticalCenter: parent.verticalCenter
              PulseAudioModule {
                id: volMod
                implicitHeight: Zenon.slot
                visible: Oracle.showVolume
                onActivated: zeus.toggleAt("sound")
              }
              DividerSlot { active: Oracle.showVolume && nowMod.active }
              NowPlayingModule { id: nowMod; implicitHeight: Zenon.slot }
            }

            NowPlayingPanel {
              anchorItem: audioGroup
              sourceHovered: volMod.hovered || nowMod.hovered
            }
          }

          // mic / screen-share / recording
          DividerSlot { active: statusMod.active }
          StatusModule { id: statusMod; implicitHeight: Zenon.slot }
        }
      }

      // layer content area kept empty – actual layer UI lives in its own
      // PanelWindow (now transparent when morphMode) positioned over this bg,
      // so the bar's bg appears to morph into the layer.
      Item {
        id: layerContent
        anchors.fill: parent
        visible: false
      }
    }
  }
}
