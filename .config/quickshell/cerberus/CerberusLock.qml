// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CERBERUS — the session lock, in place of hyprlock. Every value below came
// from ~/.config/hypr/hyprlock.conf, quoted beside the property it became.
//
// The lock lives inside the running shell rather than in a process of its
// own, so `locked` is just a property. That also means the escape hatch is
// `qs ipc call Cerberus unlock` from a VT — which already costs an
// authenticated login, so it gives a physical attacker nothing they did not
// already have, and it is the difference between a bad night and a lost
// session if PAM ever breaks under you.

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Widgets
import "../morpheus"
import "../oracle"

Scope {
  id: root

  // ── hyprlock.conf, ported ────────────────────────────────────────────
  //   $font = JetBrainsMono Nerd Font Mono Medium
  readonly property string fontFamily: Zenon.faceMono
  readonly property int fontWeight: Font.Medium
  //   $monitor = DP-1 — the input field and both labels named this monitor;
  //   every other output gets background only. Named rather than fixed: which
  //   output you actually look at first is a fact about the desk, not about
  //   this shell, and effectiveWidgetMonitor below still catches a name that
  //   is not plugged in.
  readonly property string widgetMonitor: Oracle.lockWidgetMonitor
  //   general { hide_cursor = true }
  readonly property bool hideCursor: Oracle.lockHideCursor

  //   background { color = rgba(0,0,0,0.6), blur_size = 12, blur_passes = 5 }
  readonly property real shadeAlpha: Oracle.lockShade
   //   blur_size 12 over 5 passes is an enormous blur — the result is colour
  //   smears with no legible text left. Qt's MultiEffect could not reach it:
  //   its radius caps at 64px, which across a 2560px output still left text
  //   readable, which on a lock screen is the entire point missed. So the
  //   blur happens once at capture instead of every frame on the GPU —
  //   downsample, blur, upsample, which is what those five passes are.
   //   The two resizes are each other's inverse, so the shot comes back at the
   //   size it went in at whatever the strength is set to: shrink to N%, blur,
   //   then blow back up by 100/N. Written as arithmetic rather than as two
   //   numbers, because two numbers can be set so they do not undo each other,
   //   and the result of that is a lock screen at the wrong resolution.
   readonly property string blurPipeline:
     "-resize " + Oracle.lockBlurStrength + "% -blur 0x10 -resize "
     + Math.round(10000 / Math.max(1, Oracle.lockBlurStrength)) + "%"

  //   input-field { font_color / check_color / fail_color = rgba(223,223,221,1) }
  readonly property color fg: Zenon.white
  //   the date label's own colour = rgba(160,160,155,1)
  // THE LOCK SCREEN'S SECOND VOICE. The clock, the title and the play glyph
  // are the first — clockFg, white at 0.85. This is everything standing one
  // step behind them: the date, in both places it is drawn, and the artist
  // under the track. One value, because they are one role; it was a slightly
  // different grey from the artist's until the two were asked to match, which
  // is the kind of difference nobody chooses on purpose.
  readonly property color dateFg: "#969daf"
  //   input-field { size = 20%, 10%; outline_thickness = 0; inner_color = transparent }
  readonly property real fieldWidthFrac: Oracle.lockFieldWidth
  readonly property real fieldHeightFrac: 0.10
  //   dots_size = 0.2, dots_spacing = 0.4 — both relative to the field height
  readonly property real dotsSize: 0.2
  readonly property real dotsSpacing: 0.4
  //   placeholder_text — the lock, shown while the field is empty. Read as a
  //   blank value the first time round because the terminal could not draw it;
  //   it is the same U+F456 erebus wears on its own lock button.
  readonly property string placeholderGlyph: "\uF456"
  //   fade_on_empty = false: an empty field keeps the placeholder rather than
  //   fading itself out, so there is always something on screen to aim at.
  readonly property bool fadeOnEmpty: false
  //   dots_text_format / check_text / fail_text.
  //   The first two are above the BMP (U+F09DE dot, U+F051B stopwatch) and are
  //   written as literal characters. They were "\u{...}" escapes, which is
  //   valid ES6 but NOT what QML's own string lexer accepts — it only takes the
  //   four-digit form — so both were silently becoming something else and the
  //   stopwatch never appeared. A four-digit escape cannot express them either:
  //   "\uF09DE" reads as U+F09D followed by "E". Literal characters are the one
  //   form with no trap in it.
  readonly property string dotGlyph: "󰧞"
  readonly property string failGlyph: "\uF00D"
  readonly property string unlockedGlyph: "\uF52A"

  //   label { text = $TIME, font_size = 16, position = 0,47, valign = bottom }
  //   ...and two pixels larger than hyprlock had it, now that it is drawn
  //   as segments rather than as type.
  readonly property int clockSize: Oracle.lockClockSize
  readonly property color clockFg: Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.85)
  // The bar's clock face, worn here too. Named from Zenon rather than restated,
  // so there is one answer to "what does a clock look like in this shell".
  // Only the time takes it — DSEG has no month names in it.
  readonly property color ghostFg:
    Qt.rgba(root.clockFg.r, root.clockFg.g, root.clockFg.b, 0.13)
  //   ...lifted from hyprlock's 47 to open the gap between the segments and
  //   the date under them, which the larger clock had closed up.
  readonly property int clockBottom: 64
  //   label { date, font_size = 12, position = 0,25, valign = bottom }
  //   ...also two larger than hyprlock had it, to keep its weight against the
  //   segments above it.
  readonly property int dateSize: Oracle.lockDateSize
  readonly property int dateBottom: 25

  // hyprlock drew the placeholder, check and fail glyphs at half the field
  // height. The field is 10% of the output, so on a 1440p screen that is a
  // 72px lock standing in the middle of the desktop. The same three symbols
  // still read from across the room at this size without dominating it.
  readonly property real glyphScale: 0.28
  // Nerd Font draws these at different heights inside the same em box. Inked
  // at a common size the lock stands 76 units tall and the stopwatch only 70,
  // which is why the stopwatch read as the smaller icon even though both were
  // set at the same pixelSize. Compensated so the two agree on screen.

  // ── motion ───────────────────────────────────────────────────────────
  // No fade — the lock appears and vanishes as a hard cut. Instant is
  // safer than a transition on a security surface: nothing is left
  // half-visible and the session is never shown through a fading layer.
  property bool covering: false
  property real reveal: root.covering ? 1 : 0


  // ── now playing awareness ────────────────────────────────────────
  // When a track is active (playing or paused) the lock's footer splits:
  // time/date slide to the bottom-right (rtl) and the track's art +
  // metadata stay on the bottom-left (ltr). Otherwise the clock stays
  // centred as before.
  readonly property bool hasTrack: NowPlaying.active && NowPlaying.title !== ""

  // ── state ────────────────────────────────────────────────────────────
  // One password buffer for the whole lock, not one per surface: every
  // output carries a key handler so typing works wherever the compositor
  // happens to have put focus, and they must all be filling the same field.
  property string pw: ""
  // "input" | "checking" | "fail" | "success"
  property string phase: "input"

  // ── the lock's ears ──────────────────────────────────────────────────
  // How many lock surfaces currently hold the keyboard. Counted rather than
  // held as a flag because the surfaces come and go with the outputs, and
  // because nothing on the way in says "your surface stopped being the
  // keyboard's" — it simply stops getting keys. Zero while locked is the one
  // state a lock screen must never be able to sit in: it renders perfectly
  // and answers nothing, which is what resuming from suspend leaves behind.
  property int keyboardHere: 0
  // Written to the trail on the EDGE, not from the guard: earGuard runs four
  // times a second while the lock is deaf, and a line each would bury the one
  // line that says when it went deaf.
  onKeyboardHereChanged: root.note("keyboard=" + root.keyboardHere)
  // every surface takes its focus back
  signal reclaim()

  // ── the way out ──────────────────────────────────────────────────────
  // pam_faillock is in this machine's system-auth stack, so a run of wrong
  // passwords stops the lock accepting the RIGHT one for unlock_time — which
  // on a lock screen means being shut out of your own session with no way to
  // say so. `faillock --reset` clears that, and needs no root here: the tally
  // is /var/run/faillock/$USER, owned by you and mode 0660.
  //
  // Offered only once the counter is actually spent. A permanently visible
  // "press this to clear your failures" is an instruction to a stranger.
  //   faillock.conf: deny= is unset, so 3 is pam_faillock's own default — and
  //   this number has to AGREE with pam's, not replace it. Setting it higher
  //   than pam's deny does not buy more attempts; it only stops the reset
  //   button appearing while the stack is already refusing you. Lower is safe
  //   and simply offers the reset early.
  readonly property int failDeny: Oracle.lockFailLimit
  property int failTally: 0
  readonly property bool lockedOut: root.failTally >= root.failDeny

  // The table's last column is V while a failure still counts against you,
  // and I on one that has aged out past fail_interval.
  function countValid(out) {
    let n = 0;
    for (const line of String(out || "").split("\n")) {
      if (/\sV\s*$/.test(line)) ++n;
    }
    return n;
  }

  Process {
    id: tallyProc
    command: ["faillock"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.failTally = root.countValid(text)
    }
  }

  Process {
    id: resetProc
    command: ["faillock", "--reset"]
    // re-read rather than assuming: if it failed, the hint must stay up
    onExited: tallyProc.running = true
  }

  // socordia watches this to know when it can let a suspend proceed
  readonly property alias locked: sessionLock.locked

  readonly property string shotDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/cerberus"

  // ── the trail ────────────────────────────────────────────────────────
  // Everything that goes wrong with this lock goes wrong at the one moment
  // nobody can read a log. The screen is black or it is deaf, the only way
  // out is the power button, and a reboot takes XDG_RUNTIME_DIR — and the
  // shell's own log inside it — along with the evidence of what happened.
  // Three years of "it did the thing again" and nothing to look at.
  //
  // So the dozen lines that matter go somewhere that survives the reboot you
  // had to perform to get out of it. Only the sleep edges and the lock's own
  // lifecycle, never anything typed.
  readonly property string trail:
    (Quickshell.env("HOME") || "/tmp") + "/.cache/cerberus.log"

  // How many keys the lock has been handed since it went up. The one number
  // that separates "the lock is deaf" from "the password is wrong", and it
  // cannot be read off anything else: a lock that receives nothing looks
  // exactly like a lock nobody has typed into.
  property int keysSeen: 0

  // Numbered, because each line is written by a shell of its own and two of
  // them racing to the same file land in whatever order they finish in. Four
  // events inside one second is normal here — that is the entire resume — and
  // a trail whose order cannot be trusted answers none of the questions it
  // was written to answer. The clock says when; the counter says after what.
  property int seq: 0

  function note(what) {
    root.seq++;
    Quickshell.execDetached(["sh", "-c",
      "printf '%s %04d %s\n' \"$(date -Is)\" " + root.seq + " "
        + Strings.shellQuote(String(what))
        + " >> " + Strings.shellQuote(root.trail)]);
  }

  // The monitor hyprlock named may not be plugged in. Falling back to the
  // first screen rather than rendering no input field anywhere, which would
  // be a locked session with nothing to type into.
  readonly property string effectiveWidgetMonitor: {
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; ++i)
      if (screens[i].name === root.widgetMonitor) return root.widgetMonitor;
    return screens.length > 0 ? screens[0].name : root.widgetMonitor;
  }

  function submit() {
    if (root.phase !== "input") return;
    root.phase = "checking";
    if (!pam.start()) {
      // the stack would not even load; do not sit on a spinner forever
      root.phase = "fail";
      failReset.restart();
    }
  }

  function clearPassword() {
    root.pw = "";
  }

  function resetFaillock() {
    resetProc.running = true;
  }

  // ── caps lock ────────────────────────────────────────────────────────
  // The commonest reason a correct password is refused, and until now the lock
  // answered it with a shake and nothing else: the same cross you get for a
  // genuinely wrong password, with no way to tell the two apart.
  //
  // Asked of HYPRLAND, not of the keyboard LEDs. `hyprctl devices` reports
  // capsLock per keyboard, which is the compositor's own xkb state — the same
  // state that decides what this field actually receives. /sys/class/leds
  // holds the kernel's copy, one node per device, named by an input number
  // that changes when a keyboard is replugged; this machine has two of them
  // and nine keyboards.
  //
  // Read at three moments and not otherwise. Caps can only change when the key
  // is pressed and the lock sees every press, so polling would be asking a
  // question whose answer cannot have changed: once when the lock appears,
  // because it may already be on; once when Caps Lock is pressed; and once on
  // a refusal, which is the moment the answer is worth having.
  property bool capsOn: false

  Process {
    id: capsProc
    stdout: StdioCollector {
      id: capsOut
      waitForEnd: true
      onStreamFinished: root.capsOn = String(capsOut.text).trim() === "1";
    }
  }

  function readCaps() {
    capsProc.running = false;
    capsProc.command = ["sh", "-c",
      "hyprctl devices -j 2>/dev/null | grep -q '\"capsLock\": *true'"
      + " && echo 1 || echo 0"];
    capsProc.running = true;
  }

  // ONLY WHILE IT IS ON, which is the whole reason this is affordable.
  //
  // Turning caps off has to take the warning with it, and the three read
  // moments above all depend on the Caps Lock key arriving here as a key
  // event. It should — but a modifier the compositor decides to keep for
  // itself would leave the warning standing over a keyboard that is no longer
  // shifted, which is worse than never having shown it.
  //
  // So while the warning is up, and only then, the answer is checked again a
  // few times a second. Caps off is the ordinary state and costs nothing; caps
  // on is rare, brief, and already the case where being right matters.
  Timer {
    id: capsWatch
    interval: 400
    repeat: true
    running: true   // PROBE: normally root.locked && root.capsOn
    onTriggered: root.readCaps()
  }

  function engage() {
    sessionLock.locked = true;
    root.covering = true;
    root.keysSeen = 0;
    root.readCaps();
    root.note("lock:engage screens=" + Quickshell.screens.length);
  }

  function release() {
    root.note("lock:release keys=" + root.keysSeen
      + " keyboard=" + root.keyboardHere);
    root.pollUptime = false;
    root.covering = false;
    sessionLock.locked = false;
    root.shotReady = false;
    wipeProc.running = true;
  }

  PamContext {
    id: pam
    // hyprlock's own /etc/pam.d/hyprlock was a one-liner including this same
    // stack, and it went away with the package
    config: "system-auth"

    onPamMessage: {
      if (pam.responseRequired) pam.respond(root.pw);
    }

    onCompleted: (result) => {
      if (result === PamResult.Success) {
        root.clearPassword();
        root.phase = "success";
        successReset.restart();
        return;
      }
      root.clearPassword();
      root.phase = "fail";
      failReset.restart();
      // the one moment the answer is worth having: if this is why, say so
      root.readCaps();
      tallyProc.running = true;
    }

    onError: (err) => {
      root.clearPassword();
      root.phase = "fail";
      failReset.restart();
    }
  }

  Timer {
    id: failReset
    // long enough to read the cross, short enough not to feel punitive
    interval: 1400
    onTriggered: if (root.phase === "fail") root.phase = "input";
  }

  Timer {
    id: successReset
    interval: 400
    onTriggered: {
      if (root.phase === "success") {
        root.phase = "input";
        root.release();
      }
    }
  }

  // Runs the whole time the lock is up, fast while it is provably deaf and
  // slow otherwise. The slow half is the fix for the bug that survived the
  // first version of this guard.
  //
  // Resuming from suspend is where the lock goes deaf. The outputs come back
  // through a modeset and the USB keyboards through a re-enumeration, both
  // underneath a lock that never went away, and the surface Qt had made active
  // can return with no focus item in it. Everything still paints; nothing you
  // type lands.
  //
  // The first version only ran `while (locked && keyboardHere === 0)`, and that
  // predicate cannot see the failure it was written for. `keyboardHere` counts
  // Qt's own `activeFocus`, which is a CLIENT-side belief: it says which item
  // this process would route a key to, not whether the compositor is still
  // sending any. After a modeset the two disagree — Qt goes on reporting a
  // focused catcher on a surface the seat has moved on from — so the count
  // stays at one, the guard never runs, and the lock sits there deaf with its
  // recovery timer switched off. Which is exactly what was reported.
  //
  // So it runs regardless of what keyboardHere says, and asking is free:
  // forceActiveFocus() on an item that already has it does nothing at all.
  // Two speeds only so that the provably-broken case recovers in a quarter
  // second while the healthy case costs one no-op every two seconds.
  //
  // REGARDLESS OF THE COUNT, NOT REGARDLESS OF THE LOCK. Dropping the
  // `keyboardHere === 0` half of the old predicate was the fix; dropping the
  // `locked` half with it was not. Unlocked there is no lock surface to hold
  // focus, so the count is legitimately zero — which put the timer on its
  // 250ms footing forever, reclaiming four times a second and logging every
  // one of them, for the whole life of the session rather than the life of a
  // lock. The log this was written to stay legible in was the one it buried.
  Timer {
    id: earGuard
    interval: root.keyboardHere === 0 ? 250 : 2000
    repeat: true
    running: root.locked
    onTriggered: {
      // Only says so when it can actually tell something is wrong. The
      // two-second heartbeat is the case where nothing here CAN tell, and a
      // line every two seconds for the length of every lock would bury the
      // log it is meant to be legible in.
      if (root.keyboardHere === 0)
        console.log("cerberus: lock has no keyboard, reclaiming");
      root.reclaim();
    }
  }

  // The resume edge itself, handed over by socordia the moment logind says
  // PrepareForSleep(false). The heartbeat above would get there on its own
  // within two seconds, but two seconds of a lock screen ignoring your
  // password is the whole complaint — and the outputs are still coming back
  // during it, so one nudge at the instant of resume would land before the
  // surfaces it needs to nudge exist. Hence a burst across the modeset.
  function wake() {
    if (!sessionLock.locked) return;
    root.note("wake:begin keyboard=" + root.keyboardHere
      + " secure=" + sessionLock.secure
      + " screens=" + Quickshell.screens.length);
    wakeBurst.left = 20;
    wakeBurst.restart();
    root.reclaim();
  }

  Timer {
    id: wakeBurst
    interval: 150
    repeat: true
    property int left: 0
    onTriggered: {
      if (!sessionLock.locked || wakeBurst.left <= 0) {
        wakeBurst.stop();
        if (sessionLock.locked)
          root.note("wake:end keyboard=" + root.keyboardHere
            + " secure=" + sessionLock.secure
            + " screens=" + Quickshell.screens.length);
        return;
      }
      wakeBurst.left--;
      root.reclaim();
    }
  }

  // The other way the lock goes deaf. `checking` swallows keystrokes on
  // purpose — a password half-typed into a check in flight would be a mess —
  // so a PAM stack that never answers leaves a lock that cannot be typed into
  // at all. PAM has no timeout of its own; this is it. Long enough that a
  // slow stack finishes on its own, short enough that you are not locked out
  // of your own session waiting for it.
  Timer {
    id: checkGuard
    interval: 30000
    running: root.phase === "checking"
    onTriggered: {
      console.log("cerberus: pam did not answer in 30s, releasing the field");
      root.clearPassword();
      root.phase = "fail";
      failReset.restart();
    }
  }

  // ── the shot behind the blur ─────────────────────────────────────────
  //   background { path = screenshot }
  // Captured BEFORE the lock surfaces map — a capture taken afterwards would
  // photograph the lock itself. Written to XDG_RUNTIME_DIR, which is tmpfs and
  // mode 700, and wiped on unlock.

  // Stage one: the raw grab. Must finish BEFORE the lock surfaces map, or it
  // photographs the lock instead of the desktop — so its cost is the cost of
  // locking, and it is paid every single time.
  //
  // It used to be two sequential `grim -o … .png`, measured at 1.15s for these
  // two outputs, essentially all of it libpng deflating 11MB of pixels nobody
  // was ever going to look at un-blurred. Written as ppm and run in parallel
  // the same capture takes 27ms. That was the delay when locking.
  Process {
    id: shotProc
    onExited: {
      lockDelay.stop();
      root.engage();
      blurProc.running = true;
    }
  }

  // Stage two: the blur, which costs the better part of a second per output.
  // Deliberately AFTER the lock is up rather than before it — nothing slow
  // belongs between you and a locked screen. The surfaces are opaque black
  // until this lands, so nothing shows through in the meantime.
  Process {
    id: blurProc
    onExited: root.shotReady = true
  }

  Process {
    id: wipeProc
    // Quoted, with the globs OUTSIDE the quotes so they still expand. It is
    // one `rm -f` away from a path that came out of the environment —
    // XDG_RUNTIME_DIR — and an unquoted one with a space in it removes
    // something else entirely.
    command: ["sh", "-c", "rm -f " + Strings.shellQuote(root.shotDir) + "/*.png "
      + Strings.shellQuote(root.shotDir) + "/*.ppm"]
  }

  // the blurred shot only exists once stage two has finished; until then the
  // Image must not be pointed at a file that is not there, or it latches on
  // an error and never retries
  property bool shotReady: false

  Timer {
    id: lockDelay
    // A screenshot must never be what stands between you and a locked
    // screen. If grim has not finished by now, lock without one. It now
    // finishes in ~27ms, so this is a guard against a wedged grim rather
    // than something the eye is ever meant to reach.
    interval: 250
    onTriggered: root.engage()
  }

  function lock() {
    root.pollUptime = true;
    if (sessionLock.locked) return;
    root.pw = "";
    root.phase = "input";
    tallyProc.running = true;
    root.shotReady = false;
    const screens = Quickshell.screens;
    const grabs = [];
    const blurs = [];
    for (let i = 0; i < screens.length; ++i) {
      const n = screens[i].name;
      const raw = root.shotDir + "/" + n + ".ppm";
      const out = root.shotDir + "/" + n + ".png";
      // backgrounded and waited on, so two outputs cost what one does
      grabs.push("grim -t ppm -o '" + n + "' '" + raw + "' 2>/dev/null &");
      blurs.push("{ magick '" + raw + "' " + root.blurPipeline + " '" + out
        + "' 2>/dev/null; rm -f '" + raw + "'; } &");
    }
    shotProc.command = ["sh", "-c",
      "mkdir -p " + Strings.shellQuote(root.shotDir) + "; "
        + grabs.join(" ") + " wait"];
    blurProc.command = ["sh", "-c",
      blurs.length === 0 ? "true" : blurs.join(" ") + " wait"];
    shotProc.running = true;
    lockDelay.restart();
  }

  IpcHandler {
    target: "Cerberus"

    function lock(): string { root.lock(); return "locking"; }
    // the escape hatch described at the top of this file
    function unlock(): string {
      root.clearPassword();
      root.release();
      return "unlocked";
    }
    function status(): string {
      return "locked=" + sessionLock.locked + " secure=" + sessionLock.secure
        + " phase=" + root.phase
        + " keyboard=" + root.keyboardHere
        + " keys=" + root.keysSeen
        + " screens=" + Quickshell.screens.length;
    }
  }

  // ── the lock itself ──────────────────────────────────────────────────

  WlSessionLock {
    id: sessionLock

    onSecureChanged: root.note("lock:secure=" + sessionLock.secure)

    surface: WlSessionLockSurface {
      id: surf

      // A surface torn down and not replaced is a black output with no
      // keyboard on it, which is one of the two things this lock is reported
      // to do after a resume. If that is what happens, it says so here.
      //
      // Reported when the SCREEN arrives rather than when the surface
      // completes: quickshell assigns it a moment later, so onCompleted only
      // ever wrote "surface:+?" — a line that says one appeared without
      // saying where, which on a two-output resume is the whole question.
      // Said once per output, not once per notification: the screen property
      // settles over two changes and a trail that reports every surface twice
      // is a trail you have to count before you can read.
      property string noted: ""
      onScreenChanged: {
        if (!surf.screen || surf.screen.name === surf.noted) return;
        surf.noted = surf.screen.name;
        root.note("surface:+" + surf.noted);
      }
      Component.onDestruction: root.note("surface:-"
        + (surf.screen ? surf.screen.name : "?"))
      // Transparent, because the opaque floor now lives INSIDE the faded
      // content — a surface that painted its own black would have nothing to
      // fade from, and the lock would still arrive in a single frame.
      color: "transparent"

      readonly property bool showsWidgets:
        surf.screen && surf.screen.name === root.effectiveWidgetMonitor


      //   general { hide_cursor = true }
      // Outside the fade: the pointer must be gone the instant the lock is
      // up, not eased away over a quarter of a second.
      MouseArea {
        anchors.fill: parent
        cursorShape: root.hideCursor ? Qt.BlankCursor : Qt.ArrowCursor
        acceptedButtons: Qt.NoButton
      }

      // Every surface takes keys, not just the one with the widgets: the
      // compositor decides which output has focus, and typing into a blank
      // one must still reach the field. Outside the fade for the same reason
      // as the cursor — the keyboard is live from frame one.
      Item {
        id: catcher
        anchors.fill: parent
        focus: true

        // Reported to the root, which is the only place that can tell whether
        // ANY surface still has the keyboard. Idempotent through `counted`:
        // a surface torn down with the focus still on it must decrement once
        // and not twice, and onActiveFocusChanged may or may not have fired
        // by the time it goes.
        property bool counted: false
        function sync() {
          if (catcher.activeFocus === catcher.counted) return;
          catcher.counted = catcher.activeFocus;
          root.keyboardHere += catcher.counted ? 1 : -1;
        }
        onActiveFocusChanged: catcher.sync()
        Component.onCompleted: catcher.sync()
        Component.onDestruction: if (catcher.counted) {
          catcher.counted = false;
          root.keyboardHere--;
        }

        Connections {
          target: root
          // Unconditional, deliberately. The guarded version — only asking
          // when activeFocus was already false — could not repair the one
          // state that matters, because in that state Qt believes the focus
          // is here and the seat disagrees. Every surface claiming a focus
          // ITEM does not fight over the keyboard either: forceActiveFocus is
          // per-window, so all this does is guarantee that whichever window
          // the compositor hands the seat to has somewhere to put the keys.
          function onReclaim() { catcher.forceActiveFocus(); }
        }

        Keys.onPressed: (event) => {
          event.accepted = true;
          root.keysSeen++;
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit();
          } else if (event.key === Qt.Key_Backspace) {
            if (root.pw.length > 0) {
              const chars = Array.from(root.pw);
              chars.pop();
              root.pw = chars.join("");
            }
          } else if (event.key === Qt.Key_CapsLock) {
            // the compositor has already applied it by the time this arrives
            root.readCaps();
          } else if (event.key === Qt.Key_Escape) {
            root.clearPassword();
          } else if (root.lockedOut && event.key === Qt.Key_R
                     && (event.modifiers & Qt.MetaModifier)) {
            // only once the counter is spent, so this cannot be leaned on as
            // a way to make failures free
            root.resetFaillock();
          } else if (event.text && event.text.length > 0 &&
                     !(event.modifiers & Qt.ControlModifier) &&
                     !(event.modifiers & Qt.MetaModifier)) {
            if (root.phase !== "checking") root.pw += event.text;
          }
        }
      }

      // everything with a picture on it, faded as one
      Item {
        id: content
        anchors.fill: parent
        opacity: root.reveal

        // an opaque floor, so a missing or slow screenshot can never leave
        // the desktop showing through once the fade has finished
        Rectangle {
          anchors.fill: parent
          color: "black"
        }

        Image {
          id: shot
          anchors.fill: parent
          source: (root.shotReady && surf.screen)
            ? "file://" + root.shotDir + "/" + surf.screen.name + ".png" : ""
          fillMode: Image.PreserveAspectCrop
          cache: false
          // it arrives a beat after the lock does; fading is kinder than a snap
          opacity: shot.status === Image.Ready ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
        }

        //   background { color = rgba(0,0,0,0.6) } — over the blur, not instead
        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(0, 0, 0, root.shadeAlpha)
        }


        // ── the widgets, on $monitor only ──────────────────────────────
        Item {
          id: field
          visible: surf.showsWidgets
          anchors.centerIn: parent
          //   input-field { size = 20%, 10% }
          // Floored, because every glyph in here is sized as a fraction of
          // this box: on the frame before the surface is configured its width
          // and height are still 0, and a font.pixelSize of 0 does not come
          // back when the real size arrives — it stays at Qt's minimum.
          width: Math.max(240, surf.width * root.fieldWidthFrac)
          height: Math.max(88, surf.height * root.fieldHeightFrac)

          //   outline_thickness = 0, inner_color = rgba(0,0,0,0): the field
          //   itself paints nothing at all — only what is in it.

          // a rejected password shoves the field aside rather than just
          // swapping a glyph; it is the one interaction that has to be felt
          // without being read
          transform: Translate { id: shake }

          SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: shake; property: "x"; to:  11; duration: 55; easing.type: Easing.OutSine }
            NumberAnimation { target: shake; property: "x"; to: -11; duration: 90; easing.type: Easing.InOutSine }
            NumberAnimation { target: shake; property: "x"; to:   7; duration: 80; easing.type: Easing.InOutSine }
            NumberAnimation { target: shake; property: "x"; to:  -4; duration: 70; easing.type: Easing.InOutSine }
            NumberAnimation { target: shake; property: "x"; to:   0; duration: 60; easing.type: Easing.OutSine }
          }

          Connections {
            target: root
            function onPhaseChanged() {
              if (root.phase === "fail") shakeAnim.restart();
            }
          }

          Text {
            // NOT `state`. Every Item already has a `state` property, so that
            // id resolved to the enclosing item's state string instead of to
            // this Text — `state.pulse` came back undefined, opacity went NaN,
            // and neither the stopwatch nor the cross was ever drawn.
            id: verdict
            anchors.centerIn: parent
            //   check_text / fail_text / unlocked
            //   fail_text / unlocked. The WAIT is not a glyph any more — see
            //   the ripple below.
            text: root.phase === "fail" ? root.failGlyph : root.unlockedGlyph
            color: root.fg
            font.family: root.fontFamily
            font.weight: root.fontWeight
            font.pixelSize: field.height * root.glyphScale

            opacity: (root.phase === "input" || root.phase === "checking") ? 0 : 1
            visible: opacity > 0.01
            scale: (root.phase === "input" || root.phase === "checking") ? 0.7 : 1

            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
          }

          // ── the wait, as a RIPPLE ────────────────────────────────────
          // It was a stopwatch, pulsing. A stopwatch is a picture of waiting,
          // which is an odd thing to draw at somebody about an operation that
          // takes a quarter of a second — it promises a delay, and then the
          // pulse has to work to prove the thing is still alive.
          //
          // What is wanted is something that says "working" without asking to
          // be looked at, and without the spinning every other program reaches
          // for: a throbber's whole idea is a rate, and there is no rate here
          // to report. Rings leaving the centre and fading as they widen say
          // the same thing and claim nothing. Nothing rotates, so there is no
          // motion for the eye to lock onto and no false sense of progress
          // being measured.
          //
          // Three, evenly out of phase, so the field is never empty and never
          // crowded. A circle is a Rectangle with a radius of half its width,
          // which is one node each — a shader for this would be extravagant.
          Item {
            id: ripple
            anchors.centerIn: parent
            width: field.height * root.glyphScale
            height: ripple.width
            // NOT THE INSTANT CHECKING BEGINS.
            //
            // A correct password comes back in well under a tenth of a second,
            // so showing the rings the moment pam is asked meant a successful
            // unlock flashed them for a frame or two on its way to the open
            // lock — a burst of movement that says "working" about something
            // that has already finished, and reads as a stutter rather than as
            // feedback. A refusal is the slow case, because pam makes it slow
            // on purpose.
            //
            // So the rings are what appears when the answer does NOT come
            // straight back. A quarter of a second is past the point where a
            // success could still be pending and well short of where a wait
            // starts to feel unanswered.
            visible: root.rippleDue

            Repeater {
              model: 3

              delegate: Rectangle {
                id: ring
                required property int index
                anchors.centerIn: parent
                width: ripple.width
                height: ripple.width
                radius: ring.width / 2
                color: "transparent"
                border.width: 2
                border.color: root.fg
                opacity: 0
                scale: 0.35

                SequentialAnimation {
                  running: ripple.visible
                  loops: Animation.Infinite
                  // the stagger, so the three are evenly spread through one
                  // ring's lifetime rather than arriving together
                  PauseAnimation { duration: ring.index * 500 }
                  ParallelAnimation {
                    NumberAnimation {
                      target: ring; property: "scale"
                      from: 0.35; to: 1.0
                      duration: 1500; easing.type: Easing.OutCubic
                    }
                    // In quickly and out slowly: a ring that faded evenly
                    // spent its first moments as a hard edge appearing from
                    // nothing, which reads as a flash rather than a swell.
                    SequentialAnimation {
                      NumberAnimation {
                        target: ring; property: "opacity"
                        from: 0; to: 0.55; duration: 320
                      }
                      NumberAnimation {
                        target: ring; property: "opacity"
                        to: 0; duration: 1180; easing.type: Easing.InCubic
                      }
                    }
                  }
                }
              }
            }
          }

          // ── caps lock, under the lock ───────────────────────────────
          // The GLYPH ALONE, and in red. It said "caps lock is on" in the
          // warning orange below the field, which put a sentence where the
          // rest of this surface says everything in one symbol — and put it
          // far enough from the thing you are looking at to be missed.
          //
          // Under the lock rather than beside it, and measured off the field's
          // centre rather than off any one of the three glyphs that live
          // there: the placeholder, the verdict and the dots all occupy that
          // centre in turn, and anchoring to whichever happens to be showing
          // would move the warning as the phase changed.
          //
          // Red, which this shell reserves for what cannot be undone or what
          // is actively wrong. A password refused because of this IS wrong,
          // and the orange below is already spoken for by the lockout.
          //
          // It arrives and leaves rather than blinking — pressing the key
          // again re-reads the state and the fade runs the other way.
          Text {
            id: caps
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: field.height * root.glyphScale * 0.85
            text: "󰌎"
            color: Zenon.red
            opacity: root.capsOn ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
              NumberAnimation { duration: 180; easing.type: Easing.OutQuint }
            }
            font.family: root.fontFamily
            font.weight: root.fontWeight
            // Roughly half the lock above it: large enough to read at a
            // glance, small enough that the lock stays the thing in the middle.
            font.pixelSize: field.height * root.glyphScale * 0.45
          }

          //   placeholder_text — only while there is nothing typed yet
          Text {
            id: placeholder
            anchors.centerIn: parent
            text: root.placeholderGlyph
            color: root.fg
            //   fade_on_empty = false: an empty field keeps this rather than
            //   fading itself out
            opacity: (root.phase === "input" && root.pw.length === 0
              && !root.fadeOnEmpty) ? 1 : 0
            visible: opacity > 0.01
            scale: opacity > 0.5 ? 1 : 0.7
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            font.family: root.fontFamily
            font.weight: root.fontWeight
            // the same size the check and fail glyphs use; all three are the
            // one symbol standing in the middle of the field
            font.pixelSize: field.height * root.glyphScale
          }

          Row {
            id: dots
            anchors.centerIn: parent
            opacity: (root.phase === "input" && root.pw.length > 0) ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuint } }

            // The whole row breathes on each keystroke — a quick swell and
            // settle so feedback carries even when the row is long and one
            // more dot at the end is easy to miss. Backspace triggers it too.
            property real kick: 1
            scale: dots.kick
            // keep the row crisp while it scales
            transformOrigin: Item.Center

            SequentialAnimation {
              id: kickAnim
              NumberAnimation { target: dots; property: "kick"; to: 1.10; duration: 85; easing.type: Easing.OutQuad }
              NumberAnimation { target: dots; property: "kick"; to: 1.0;  duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            }

            Connections {
              target: root
              function onPwChanged() {
                if (root.pw.length > 0) kickAnim.restart();
              }
            }
            //   dots_spacing = 0.4, relative to the dot size
            spacing: field.height * root.dotsSize * root.dotsSpacing

            Repeater {
              model: root.pw.length

              delegate: Text {
                id: dot
                required property int index
                //   dots_text_format
                text: root.dotGlyph
                color: root.fg
                font.family: root.fontFamily
                font.weight: root.fontWeight
                //   dots_size = 0.2 of the field height
                font.pixelSize: field.height * root.dotsSize

                // Horizontal fade-slide-bounce: each dot slides in from the
                // left with a single OutBack overshoot (one bounce, no
                // rebound/oscillation) while fading in — crisp horizontal
                // motion instead of the previous vertical drop. Uses a
                // Translate so Row's own x layout is not fought.
                property real tx: -field.height * root.dotsSize * 0.85
                transform: Translate { x: dot.tx }
                scale: 0.7
                opacity: 0
                property real stagger: dot.index * 12
                Component.onCompleted: {
                  Qt.callLater(() => {
                    dot.scale = 1;
                    dot.opacity = 1;
                    dot.tx = 0;
                  });
                }
                Behavior on scale {
                  NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                }
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                Behavior on tx {
                  NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                }
              }
            }
          }
        }

        // Only on screen once the counter is spent. Zenon's orange, the same
        // ink the bar's bell and updates count wear — the colour this shell
        // uses for "something needs you". A permanently visible "press this to
        // clear your failures" is an instruction to a stranger.
        Text {
          visible: surf.showsWidgets && root.lockedOut
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: field.bottom
          anchors.topMargin: 8
          text: "too many attempts  \u00b7  super + r  clears the counter"
          color: Zenon.yellow
          font.family: root.fontFamily
          font.weight: root.fontWeight
          font.pointSize: root.dateSize
        }

        //   label { text = $TIME, position = 0,47, valign = bottom }
        //   Seven-segment, with every unlit segment showing behind the live
        //   ones — which is what the panel of a real clock is doing.
        //   Centred when no track; pushed to the bottom-right (rtl) when a
        //   track is active so the bottom-left can host the now-playing.
        // The clock and the uptime are centred AS A PAIR rather than the clock
        // being centred with something hung off it — otherwise adding the
        // second reading pushes the first off the middle of the screen, which
        // is the one thing its placement was about.
        Row {
          visible: surf.showsWidgets && !root.hasTrack
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.clockBottom
          spacing: 16

          // UPTIME FIRST, THEN THE CLOCK — the order the other lock layout
          // has always used, over on the right when a track is playing. The
          // two were mirror images of each other for no reason anyone chose.
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.uptimeText !== ""
            text: root.uptimeText
            color: root.clockFg
            font.family: Zenon.clockFamily
            font.weight: Font.Bold
            font.pointSize: root.clockSize
          }

          // THE CLOCK'S OWN FACE, not a footnote beside it. Two readings of
          // the same kind — how long, and when — so they are set the same way
          // and the glyph between them is what says they are different
          // questions. Nothing at all until it has been read, so the pair does
          // not jump sideways a moment after the lock appears.
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.uptimeText !== ""
            text: root.uptimeSep
            // THE SAME INK AS THE DIGITS EITHER SIDE OF IT. It was drawn in
            // ghostFg — the unlit-segment colour — which made the separator
            // read as part of the clock's backing rather than as a mark
            // between two readings.
            color: root.clockFg
            font.family: root.fontFamily
            font.pixelSize: root.sepSize
          }

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(lockGhost.implicitWidth, lockTime.implicitWidth)
            height: lockTime.implicitHeight

            Text {
              id: lockGhost
              anchors.centerIn: parent
              text: "88:88"
              color: root.ghostFg
              font.family: Zenon.clockFamily
              font.weight: Font.Bold
              font.pointSize: root.clockSize
            }

            Text {
              id: lockTime
              anchors.centerIn: parent
              text: Qt.formatDateTime(clock.date, "HH:mm")
              color: root.clockFg
              font.family: Zenon.clockFamily
              font.weight: Font.Bold
              font.pointSize: root.clockSize
            }
          }
        }

        //   label { cmd[update:60000] date +"%A, %d %B %Y", position = 0,25 }
        Text {
          visible: surf.showsWidgets && !root.hasTrack
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.dateBottom
          text: Qt.formatDateTime(clock.date, "dddd, dd MMMM yyyy")
          color: root.dateFg
          font.family: root.fontFamily
          font.weight: root.fontWeight
          font.pointSize: root.dateSize
        }

        // ── now-playing footer ─────────────────────────────────────
        // Active track: art + metadata on the bottom-left (ltr), clock/date
        // on the bottom-right (rtl). Mirrors the mpris tooltip palette:
        // track green, artist white, album muted.
        Item {
          id: npLeft
          visible: surf.showsWidgets && root.hasTrack
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.leftMargin: 40
          anchors.bottomMargin: 30
          width: Math.min(520, surf.width * 0.46)
          height: 92

          Row {
            id: npRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            // The sleeve is a solid block of artwork and the text beside it is
            // now nearly as tall, so they need real air between them or they
            // read as one object. 14 was set against much smaller type.
            spacing: 22

            ClippingRectangle {
              id: npArtBox
              width: 84
              height: 84
              radius: 6
              color: Zenon.surface
              border.color: Qt.rgba(1,1,1,0.08)
              border.width: 1
              anchors.verticalCenter: parent.verticalCenter

              Image {
                id: npArt
                anchors.fill: parent
                source: NowPlaying.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                // same bound as the bar's copy in morpheus/NowPlayingPanel.qml:
                // the player decides how big the art is, this box decides how
                // much of it is worth decoding
                sourceSize.width: Math.ceil(npArt.width * npArt.Screen.devicePixelRatio)
                sourceSize.height: Math.ceil(npArt.height * npArt.Screen.devicePixelRatio)
                cache: false
                visible: status === Image.Ready
              }
              Text {
                anchors.centerIn: parent
                visible: npArt.status !== Image.Ready
                text: ""
                color: Zenon.muted
                font.family: root.fontFamily
                font.pixelSize: 28
              }
            }

            // ── AS TALL AS THE COVER BESIDE IT ───────────────────────
            // Three rows at 15/13/12 with 2px between them came to about 58
            // against an 84px sleeve, so the text sat as a small block halfway
            // up a large square. Sized up until the column fills the art it is
            // standing next to — the sleeve is the thing setting the scale
            // here, and the type should answer to it rather than the other way
            // round.
            Column {
              anchors.verticalCenter: parent.verticalCenter
              // What is left after the sleeve and the gap, rather than a
              // number that happened to equal them — those two have moved
              // twice now and this did not follow either time.
              width: npLeft.width - npArtBox.width - npRow.spacing
              spacing: 6

              Row {
                width: parent.width
                spacing: 6

                Text {
                  id: playIcon
                  anchors.verticalCenter: parent.verticalCenter
                  // The clock's white, not a flat one: the lock screen's text
                  // all sits at the same weight against the wallpaper, and a
                  // fully opaque title beside a 0.85 clock reads as the louder
                  // of the two for no reason.
                  text: NowPlaying.playing ? "" : ""
                  color: root.clockFg
                  font.family: Zenon.face
                  // with the title, not with what it used to sit beside
                  font.pixelSize: 17
                }

                Text {
                  id: titleText
                  width: Math.min(implicitWidth, parent.width - playIcon.implicitWidth - parent.spacing)
                  text: NowPlaying.title
                  color: root.clockFg
                  font.family: root.fontFamily
                  font.weight: Font.Bold
                  font.pixelSize: 19
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignLeft
                  verticalAlignment: Text.AlignVCenter
                }
              }

              Text {
                width: parent.width
                visible: NowPlaying.artist !== ""
                text: NowPlaying.artist
                // Between the title's white and the album's muted, so the
                // three rows read as a hierarchy rather than as two whites and
                // a grey. The same ink the date is set in — see dateFg.
                color: root.dateFg
                font.family: root.fontFamily
                font.pixelSize: 16
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
              }
              Text {
                width: parent.width
                visible: NowPlaying.album !== ""
                text: NowPlaying.album
                color: Zenon.muted
                font.family: root.fontFamily
                font.pixelSize: 14
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
              }
            }
          }
        }

        Item {
          id: clockRight
          visible: surf.showsWidgets && root.hasTrack
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: 40
          anchors.bottomMargin: root.dateBottom
          width: rightCol.implicitWidth
          height: rightCol.implicitHeight

          Column {
            id: rightCol
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 12

            // The clock and the uptime as one right-aligned pair, the same way
            // the centred layout treats them — this corner is the other place
            // the time lives, and a reading that only appears in one of them
            // is a reading you cannot rely on being there.
            Row {
              anchors.right: parent.right
              spacing: 12

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.uptimeText !== ""
                text: root.uptimeText
                color: root.clockFg
                font.family: Zenon.clockFamily
                font.weight: Font.Bold
                font.pointSize: root.clockSize
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.uptimeText !== ""
                text: root.uptimeSep
                color: root.clockFg
                font.family: root.fontFamily
                font.pixelSize: root.sepSize
              }

            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(ghostR.implicitWidth, timeR.implicitWidth)
              height: timeR.implicitHeight
              Text {
                id: ghostR
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "88:88"
                color: root.ghostFg
                font.family: Zenon.clockFamily
                font.weight: Font.Bold
                font.pointSize: root.clockSize
                horizontalAlignment: Text.AlignRight
              }
              Text {
                id: timeR
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: root.clockFg
                font.family: Zenon.clockFamily
                font.weight: Font.Bold
                font.pointSize: root.clockSize
                horizontalAlignment: Text.AlignRight
              }
            }
            }

            Text {
              anchors.right: parent.right
              text: Qt.formatDateTime(clock.date, "dddd, dd MMMM yyyy")
              color: root.dateFg
              font.family: root.fontFamily
              font.weight: root.fontWeight
              font.pointSize: root.dateSize
              horizontalAlignment: Text.AlignRight
            }
          }
        }
      }
    }
  }

  // ── HOW LONG THIS MACHINE HAS BEEN UP ─────────────────────────────────
  // Beside the time, because the two answer the same shape of question and
  // the lock screen is where you most often want the second one: you came
  // back to a machine and the first thing worth knowing is whether it is the
  // one you left.
  //
  // From /proc/uptime rather than `uptime -p`, which says "up 3 days, 4 hours,
  // 12 minutes" — a sentence, next to a seven-segment clock. Two units is as
  // much as anyone reads off a glance.
  property string uptimeText: ""
  // The mark between the two readings. Dimmed to the unlit-segment ink, so it
  // separates without competing with either number.
  readonly property string uptimeSep: "󱑼"
  readonly property int sepSize: 20

  // WRITTEN FOR A SEVEN-SEGMENT FACE, because that is the face it wears.
  //
  // DSEG7 has no "m" — seven segments cannot make one, and it comes out as an
  // "n". So the unit is carried by a single letter the display CAN form, used
  // as the separator between the two numbers rather than as a suffix after
  // each: "3h41" and "2d07" instead of "3h 41m". It reads as a duration
  // precisely because a clock never has a letter in the middle of it.
  function formatUptime(secs) {
    const s = Math.max(0, Math.floor(secs));
    if (!isFinite(s)) return "";
    const pad = (n) => (n < 10 ? "0" + n : String(n));
    const d = Math.floor(s / 86400);
    const h = Math.floor((s % 86400) / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (d > 0) return d + "d" + pad(h);
    return h + "h" + pad(m);
  }

  Process {
    id: uptimeProc
    command: ["sh", "-c", "cut -d. -f1 /proc/uptime"]
    stdout: StdioCollector {
      id: uptimeOut
      waitForEnd: true
      onStreamFinished:
        root.uptimeText = root.formatUptime(parseInt(String(uptimeOut.text).trim(), 10))
    }
  }

  // True once `checking` has lasted long enough to be worth drawing — see the
  // ripple. Cleared the moment the phase moves on, so a refusal followed by a
  // second attempt starts the wait over rather than showing the rings at once.
  property bool rippleDue: false

  Timer {
    id: rippleDelay
    interval: 250
    onTriggered: root.rippleDue = (root.phase === "checking")
  }

  Connections {
    target: root
    function onPhaseChanged() {
      if (root.phase === "checking") {
        root.rippleDue = false;
        rippleDelay.restart();
      } else {
        rippleDelay.stop();
        root.rippleDue = false;
      }
    }
  }

  // Only while the lock is up, and only once a minute — it is measured in
  // hours and nothing on this surface is watching the seconds.
  // Driven by a plain property that lock() and release() set, NOT by a
  // binding on sessionLock.locked. That binding evaluated false and never
  // moved — the surface's own lock flag does not notify this far out — so the
  // timer never started and the reading was never taken. A bool this file
  // owns and writes is the one thing certain to report a change.
  property bool pollUptime: false

  Timer {
    interval: 60000
    repeat: true
    triggeredOnStart: true
    running: root.pollUptime
    onTriggered: uptimeProc.running = true
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    enabled: true
  }
}
