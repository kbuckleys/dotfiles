// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ORACLE's face — the settings panel, drawn entirely from Oracle.schema.
//
// There is no per-setting UI anywhere in this file. A row knows it is a bool,
// a number, one of a list, a line of text or a button, and draws itself
// accordingly; which settings exist, what they are called and what they may be
// set to is Oracle's business alone. Adding a setting is a property and a spec
// over there, and nothing at all here.
//
// NOT A MORPH LAYER, and deliberately the only one in this shell that is not.
//
// Every other panel here is the pill wearing a different shape: it belongs to
// the bar, it opens where the bar is, and it closes back down into it. That is
// right for a thing you glance at — a calendar, a mixer, a notification list —
// because the bar is where you were already looking.
//
// Settings are not that. You come here to change the bar itself, and half the
// controls in here move the pill while you are holding them: the corner
// radius, the row height, the module switches, the animation speed. A panel
// that WAS the pill would have been resizing itself under the pointer on every
// one of those. So it stands free in the middle of the screen, on its own, and
// you can drag it out of the way of whatever you are watching it change.
//
// And because it is free, it is MOUSE-FIRST. The other layers are keyboard
// instruments with a hint strip along the bottom teaching you the chords —
// they are opened, used and dismissed in a second. This one is read and
// poked at. Every control answers to a click or a drag, there is a close
// button rather than a key to learn, and the strip of hints is gone.

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "oracle.js" as Ora
import "../morpheus"

PanelWindow {
  id: popup

  WlrLayershell.layer: WlrLayer.Overlay

  property bool shown: false
  property real showFactor: 0
  property bool collapsing: false

  readonly property color bgColor: Zenon.layerBg
  readonly property color borderColor: Zenon.surfaceBorder
  readonly property color fgColor: Zenon.white
  readonly property color headColor: Zenon.cyan
  readonly property color dimColor: Zenon.muted
  // WHAT YOU ARE TOUCHING, and what has been CHANGED, are two different
  // facts and now wear two different colours.
  //
  // Everything interactive used to light up in the pink — a focused field, an
  // open dropdown, a pressed button, a grabbed knob — and against the dark
  // panel that reads as a red alert rather than as "this one is live". Cyan
  // is the accent the rest of the shell already uses for the thing in hand:
  // the section you are standing in, a slider's filled track, the lit cell in
  // the corner picker.
  //
  // A SECOND colour is kept for the one job it is good at: marking a setting
  // that is no longer at its default. That is a STATE rather than an action,
  // it wants to be told apart from the cyan at a glance, and it appears in
  // exactly three places — the sidebar's per-section count, the "n changed"
  // badge in the head, and the dot at the start of a changed row.
  //
  // Yellow rather than the light red it was. Against this ground the pink
  // read as a warning — a changed setting is not a problem, it is a choice —
  // and yellow sits far enough from the cyan to separate at a glance without
  // claiming something has gone wrong. Not sand, which is the RAM meter's
  // and terminus' "modified" ink, and is close enough to the white text here
  // to lose the dot entirely.
  readonly property color highlight: Zenon.cyan
  readonly property color changedColor: Zenon.yellow
  readonly property color errColor: Zenon.red

  readonly property string face: Zenon.face

  // Whose shell this is. Written here rather than in the string below so the
  // name and the address it points at cannot drift apart.
  readonly property string authorName: "Buck"
  readonly property string authorUrl: "https://github.com/kbuckleys"

  // ── what is on screen ─────────────────────────────────────────────────
  // `section` is where you are standing; `query` suspends it. A search is the
  // case where you do not know which section a setting is filed under — that
  // is why you are typing — so a non-empty query searches all of them and the
  // sidebar goes quiet rather than lying about which one you are in.
  property string section: "bar"
  // The last section that actually HAS settings in it. "Reset one section"
  // lives in the about section, so `section` at the moment it is clicked is
  // always "about" — which holds nothing but actions, so the reset would be a
  // button that reliably does nothing. This is what it means instead: the
  // section you were in before you came here.
  property string lastRealSection: "bar"
  property string query: ""
  // the key of the text setting currently being typed into, "" for none. Only
  // ever one: a text row takes the keyboard from the search field while it is
  // open and gives it back on return or escape.
  property string editingKey: ""

  readonly property bool searching: popup.query !== ""

  // ── THE DROPDOWN ──────────────────────────────────────────────────────
  // One card, shared by every enum row, opened where the row's control is.
  // A card per row would be one layer-shell surface per enum setting — there
  // are eight of them — and only ever one can be open.
  //
  // `enumKey` is which setting it belongs to; "" is closed.
  property string enumKey: ""
  property point enumAt: Qt.point(0, 0)
  readonly property var enumSpec: popup.enumKey === ""
    ? null : Oracle.spec(popup.enumKey)

  // Where a corner value sits in the six-cell screen. Lives here rather than
  // in the control because both the closed chip and the open card draw it.
  function cornerCell(v) {
    const t = String(v) === "auto" ? Oracle.notifCorner(Zenon.barTop) : String(v);
    return { row: t.indexOf("top") === 0 ? 0 : 1,
             col: t.indexOf("-left") >= 0 ? 0
                : (t.indexOf("-right") >= 0 ? 2 : 1) };
  }

  // A spec that names a PLACE gets the grid; everything else gets the list.
  readonly property bool enumIsGrid:
    popup.enumSpec !== null && popup.enumSpec.pictogram === "corner"

  // the grid's current cell, and whether the non-place answer is the one
  readonly property bool enumAutoOn: {
    Oracle.revision;
    return popup.enumSpec !== null
      && String(Oracle.get(popup.enumSpec.key)) === "auto";
  }
  readonly property var enumCell: {
    Oracle.revision;
    if (!popup.enumSpec) return { row: -1, col: -1 };
    return popup.cornerCell(Oracle.get(popup.enumSpec.key));
  }

  // Turn a grid cell back into the value that names it. Derived from the
  // spec's own options rather than rebuilt from strings here, so the two
  // cannot describe different sets of corners.
  function valueForCell(r, c) {
    const sp = popup.enumSpec;
    if (!sp) return "";
    const opts = sp.options || [];
    for (let i = 0; i < opts.length; ++i) {
      const v = opts[i].value;
      if (v === "auto") continue;
      const cell = popup.cornerCell(v);
      if (cell.row === r && cell.col === c) return v;
    }
    return "";
  }

  readonly property var enumRows: {
    const sp = popup.enumSpec;
    if (!sp) return [];
    Oracle.revision;
    const now = Oracle.get(sp.key);
    const opts = sp.options || [];
    const out = [];
    for (let i = 0; i < opts.length; ++i) {
      out.push({ text: opts[i].label,
                 mark: opts[i].value === now,
                 cell: sp.pictogram === "corner"
                   ? popup.cornerCell(opts[i].value) : null });
    }
    return out;
  }

  function openEnumMenu(key, at) {
    popup.enumKey = key;
    popup.enumAt = at;
  }

  function closeEnumMenu() { popup.enumKey = ""; }

  readonly property var rows: Ora.filterSchema(Oracle.schema, popup.section, popup.query)

  readonly property int headH: 52
  readonly property int bodyH: 460
  readonly property int sideW: 240
  readonly property int rowH: 64
  // ── CONTROLS HANG OFF THE RIGHT EDGE ──────────────────────────────────
  // Every control ENDS at the same x, hard against the scrollbar, and each
  // one takes only the width it actually needs. Two things follow from that,
  // and both are the point:
  //
  //   they line up. A column of switches, buttons and dropdowns all flush
  //   right reads as one column, where before they sat in slots of three
  //   different widths all anchored right — so their left edges stepped in
  //   and out down the page.
  //
  //   and a switch gives its room back. A bool needs 44px; it used to
  //   reserve 300 and leave the description to elide against thin air. The
  //   label column runs to whatever the control did not take, so the short
  //   controls buy the long descriptions their space.
  //
  // The widest control decides nothing about the others — see controlSlot,
  // which measures the one it actually loaded.
  readonly property int controlW: 260

  function calcHeight() {
    return popup.headH + popup.bodyH;
  }

  // Not Zenon.layerWidth: that token exists so a layer and the PILL IT IS
  // WEARING cannot disagree about a width, and this panel wears nothing. It
  // answers to the screen instead, which is the only thing that can actually
  // constrain it — and it must, because the bar's maximum width is one of the
  // settings inside it and dragging that slider must not resize the panel
  // holding the slider.
  function calcWidth() {
    const avail = (popup.screen ? popup.screen.width : 1920) - 80;
    return Math.max(560, Math.min(1000, avail));
  }

  // ── where it stands ───────────────────────────────────────────────────
  // Centred until it is dragged, and then wherever it was put — for the rest
  // of the session, not just this open. Moving a window out of the way of the
  // thing you are watching it change is a decision about the next few minutes,
  // not about the next five seconds, and re-centring it on the next open would
  // undo that decision every time.
  property bool placed: false
  property real placedX: 0
  property real placedY: 0

  // THE SCREEN'S SIZE, NOT THE WINDOW'S, and this is not a stylistic choice.
  // The surface is torn down whenever the panel is not on screen — `visible`
  // is false between opens — and an unmapped layer-shell window reports a
  // placeholder size. Clamping against that turned every close into a silent
  // reset of wherever you had dragged the panel to: reopen it and it was back
  // in the top-left corner. The screen this window covers is the same size
  // whether or not the window currently exists, so it is what both the
  // centring and the clamp are measured against.
  readonly property real surfaceW: popup.screen ? popup.screen.width : popup.width
  readonly property real surfaceH: popup.screen ? popup.screen.height : popup.height

  readonly property real restX: popup.placed
    ? popup.placedX : (popup.surfaceW - panel.width) / 2
  readonly property real restY: popup.placed
    ? popup.placedY : (popup.surfaceH - panel.height) / 2

  // A monitor can change under a placed panel — unplugged, rotated, or simply
  // a smaller one on the next open — and a position that was on screen when it
  // was chosen is not necessarily on screen now. Half the panel may hang off;
  // the head bar may not.
  function clampPlace() {
    if (!popup.placed) return;
    const maxX = Math.max(0, popup.surfaceW - panel.width);
    const maxY = Math.max(0, popup.surfaceH - panel.height);
    popup.placedX = Math.max(0, Math.min(maxX, popup.placedX));
    popup.placedY = Math.max(0, Math.min(maxY, popup.placedY));
  }
  onSurfaceWChanged: popup.clampPlace()
  onSurfaceHChanged: popup.clampPlace()

  // ── which monitor it stands on ────────────────────────────────────────
  // Latched when it opens, exactly as zeus latches its own. Every other layer
  // follows the focused monitor, which is right for something you open, use
  // and dismiss — but with focus following the mouse, glancing at the other
  // screen would carry a panel you had deliberately placed across with it, and
  // drop it somewhere else on a monitor of a different size.
  property var liveScreen: null
  property var homeScreen: null

  visible: popup.showFactor > 0.01
  color: "transparent"

  anchors { left: true; right: true; top: true; bottom: true }
  focusable: true
  exclusionMode: ExclusionMode.Ignore

  NumberAnimation {
    id: openAnim
    target: popup; property: "showFactor"
    to: 1; duration: Zenon.slow; easing.type: Zenon.ease
  }

  NumberAnimation {
    id: closeAnim
    target: popup; property: "showFactor"
    to: 0; duration: Zenon.slow; easing.type: Zenon.ease
    onFinished: {
      popup.shown = false;
      // let it pick again next time; the PLACE it was dragged to is kept, and
      // clampPlace puts that on the new monitor if it does not fit
      popup.homeScreen = null;
    }
  }

  // Cleared by clicking away, and clicking away no longer closes anything —
  // so the grab is RELEASED instead, and the panel stays up without holding
  // the keyboard hostage. That is the whole point of a settings window you can
  // drag out of the way: you are meant to be able to go and use the thing you
  // are configuring while it is open.
  //
  // `holdKeys` rather than re-asserting `active` on its own: a grab that
  // re-grabs the instant it is cleared is a fight with the compositor, and the
  // visible half of that fight is focus flickering between two windows.
  property bool holdKeys: true

  // The card is its own layer-shell surface, so a grab listing only the
  // panel would treat a click on the dropdown as a click "somewhere else".
  readonly property var grabWindows: {
    const out = [popup];
    if (enumMenu.visible) out.push(enumMenu);
    if (cornerMenu.visible) out.push(cornerMenu);
    return out;
  }

  HyprlandFocusGrab {
    id: grab
    windows: popup.grabWindows
    active: popup.shown && popup.holdKeys
    onCleared: {
      popup.holdKeys = false;
      popup.closeEnumMenu();
    }
  }

  IpcHandler {
    // "Oracle", like every other layer's own name — the settings STORE answers
    // to "OracleSettings" so that this one can.
    target: "Oracle"
    function toggle() { popup.toggle(); }
    function open() { popup.openPopup(""); }
    // open standing in a named section, for a keybind that goes straight to
    // the notifications or the lock rather than to wherever it was left
    function at(section: string) { popup.openPopup(section); }
    function close() { popup.closePopup(); }
    // put it back in the middle, for when it has been dragged somewhere the
    // monitor it was dragged on no longer exists
    function center(): string {
      popup.placed = false;
      return "centered";
    }
  }

  // ── open and close ────────────────────────────────────────────────────

  function openPopup(section) {
    const cold = !popup.shown;
    popup.shown = true;
    popup.collapsing = false;
    popup.holdKeys = true;
    closeAnim.stop();
    if (cold) {
      // where you are looking, once — read from the unlatched value so a close
      // that has not finished animating cannot hand back a stale screen
      popup.homeScreen = popup.liveScreen;
      // A settings panel is not a launcher: it opens where it was left, so
      // that changing two things in one section is not two walks back to it.
      // Only the query is session state.
      popup.query = "";
      filterInput.text = "";
      popup.editingKey = "";
      popup.clampPlace();
    }
    if (section && section !== "") popup.goToSection(section);
    openAnim.restart();
    if (cold) {
      focusRetry.counter = 0;
      focusRetry.restart();
    }
    popup.syncFocus();
  }

  function closePopup() {
    popup.collapsing = true;
    popup.editingKey = "";
    popup.closeEnumMenu();
    openAnim.stop();
    closeAnim.restart();
  }

  function toggle() {
    if (popup.shown && !popup.collapsing) popup.closePopup();
    else popup.openPopup("");
  }

  // The search field holds the keyboard so that typing works without clicking
  // into it first. That is not a keyboard interface — it is the one thing a
  // pointer cannot do for you, and everything else in here is a click.
  function syncFocus() {
    Qt.callLater(() => {
      if (!popup.shown) return;
      if (popup.editingKey === "") filterInput.forceActiveFocus();
    });
  }

  Timer {
    id: focusRetry
    interval: 60
    repeat: true
    property int counter: 0
    onTriggered: {
      if (!popup.shown) { stop(); return; }
      popup.syncFocus();
      if (filterInput.activeFocus) stop();
      if (focusRetry.counter++ > 12) stop();
    }
  }

  // ── moving about ──────────────────────────────────────────────────────

  function goToSection(id) {
    // Clicking a section is also the way OUT of a search: the sidebar is
    // quiet while filtering precisely because the rows on screen are no
    // longer that section's, so a click on it has to mean "show me this one".
    popup.query = "";
    filterInput.text = "";
    if (popup.section !== "about") popup.lastRealSection = popup.section;
    popup.section = id;
    popup.editingKey = "";
    popup.closeEnumMenu();
    Qt.callLater(() => list.positionViewAtBeginning());
    popup.syncFocus();
  }

  function sectionLabel(id) {
    for (let i = 0; i < Oracle.sections.length; ++i)
      if (Oracle.sections[i].id === id) return Oracle.sections[i].label;
    return id;
  }

  // ── controls ──────────────────────────────────────────────────────────
  // One component per kind of thing a setting can be. Each is handed its spec
  // and its live value and reports back through Oracle.set — none of them
  // keeps a copy of the value it is showing, so a reset or an IPC write lands
  // on screen with nothing needing to be told.
  //
  // None of them lights up on hover. A control that changes colour when the
  // pointer merely passes over it is reporting where the mouse is, which you
  // already know; the reply that matters is the value moving, and every one of
  // these gives you that on the frame you click.

  // A track and a knob. The whole control is the hit area, because a switch
  // that only answers to its own 18 pixels is a switch you miss.
  component BoolControl: Item {
    id: sw
    property var spec: null
    property bool value: false
    width: 44
    height: 24

    Rectangle {
      id: track
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: 44
      height: 22
      radius: height / 2
      // ON is the same fact every other lit control reports — the thing in
      // hand — so it wears the same cyan rather than a green of its own. A
      // second accent that appears only on switches makes a column of them
      // read as a different kind of control from everything beside it.
      color: sw.value
        ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.30)
                      : Qt.rgba(1, 1, 1, 0.07)
      border.width: 1
      border.color: sw.value ? popup.highlight : Zenon.msgBorder
      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      Behavior on border.color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      Rectangle {
        width: 16
        height: 16
        radius: 8
        y: 3
        x: sw.value ? track.width - width - 3 : 3
        color: sw.value ? popup.highlight : popup.dimColor
        Behavior on x { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
        Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      }
    }

    // only over the switch itself, not the whole empty column beside it
    MouseArea {
      anchors.fill: track
      anchors.margins: -10
      onClicked: Oracle.set(sw.spec.key, !sw.value)
    }
  }

  // A track, the part of it that is filled, a knob, and the reading. Dragging
  // anywhere on the track jumps to that point and then follows the pointer —
  // the knob is not a separate thing to grab, which on a 4px track it would
  // be far too easy to miss. The wheel steps it, for the settings where you
  // want one notch rather than a position.
  component NumControl: Item {
    id: sl
    property var spec: null
    property real value: 0
    width: popup.controlW
    height: 26
    // the reading is flush right and the track runs back from it

    readonly property real frac: sl.spec ? Ora.fraction(sl.spec, sl.value) : 0

    Rectangle {
      id: bar
      anchors.right: reading.left
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      width: 168
      height: 4
      radius: 2
      color: Qt.rgba(1, 1, 1, 0.10)

      Rectangle {
        width: Math.round(bar.width * sl.frac)
        height: parent.height
        radius: 2
        color: popup.headColor
      }

      Rectangle {
        width: 12
        height: 12
        radius: 6
        y: -4
        x: Math.round(bar.width * sl.frac) - 6
        color: drag.pressed ? popup.highlight : popup.headColor
        border.width: 2
        border.color: Zenon.black
        Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      }
    }

    Text {
      id: reading
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      // fixed, so the tracks line up too rather than each starting wherever
      // its own number happened to end
      width: 74
      horizontalAlignment: Text.AlignRight
      text: sl.spec ? Ora.display(sl.spec, sl.value) : ""
      color: popup.fgColor
      font.family: popup.face
      font.weight: Font.Medium
      font.pixelSize: 16
      elide: Text.ElideRight
    }

    MouseArea {
      id: drag
      // Reaches past the track vertically so a press a few pixels high or low
      // still lands on it, and past the left end so the zero position is
      // actually reachable rather than being half a knob outside the control.
      x: -6
      y: -8
      width: bar.width + 12
      height: sl.height + 16
      // the panel's mask has to stand down for this too — a slider dragged
      // past the panel's edge would lose the grab the same way
      onPressed: (m) => { popup.sliderDragging = true; drag.apply(m.x); }
      onPositionChanged: (m) => { if (drag.pressed) drag.apply(m.x); }
      onReleased: popup.sliderDragging = false
      onCanceled: popup.sliderDragging = false
      // The wheel belongs to the LIST everywhere except here, over the track
      // itself — a settings list you cannot scroll past a slider would be
      // worse than a slider you cannot wheel.
      onWheel: (w) => {
        Oracle.nudge(sl.spec.key, w.angleDelta.y > 0 ? 1 : -1);
        w.accepted = true;
      }
      function apply(mx) {
        Oracle.set(sl.spec.key, Ora.fromFraction(sl.spec, (mx - 6) / bar.width));
      }
    }
  }

  // A BUTTON THAT OPENS A LIST, not a ring you step through.
  //
  // A ring is fine for two or three values and hopeless past that: the toast
  // position has seven, and finding "Bottom left" meant clicking until it
  // came round, with no way to see what else was on offer. A dropdown shows
  // the whole set at once and takes one click to reach any of it.
  //
  // The chip still reports the current value, and still draws its pictogram
  // where the spec asks for one — so the closed control and the row you
  // picked in the open card are visibly the same thing.
  component EnumControl: Item {
    id: en
    property var spec: null
    property var value: null
    width: 164
    height: 26

    readonly property bool hasPicto: en.spec && en.spec.pictogram === "corner"
    readonly property bool open: en.spec && popup.enumKey === en.spec.key

    Rectangle {
      id: chip
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: 164
      height: 26
      radius: 4
      color: (en.open || chipMa.pressed)
        ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.18)
        : Qt.rgba(1, 1, 1, 0.06)
      border.width: 1
      border.color: en.open ? popup.highlight : Zenon.msgBorder
      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      Behavior on border.color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      // the same six-cell screen the card's rows draw
      Item {
        id: picto
        visible: en.hasPicto
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? 22 : 0
        height: 15

        readonly property var cell: en.hasPicto
          ? popup.cornerCell(en.value) : null

        Rectangle {
          anchors.fill: parent
          radius: 2
          color: "transparent"
          border.width: 1
          border.color: Zenon.msgBorder
        }

        Grid {
          anchors.fill: parent
          anchors.margins: 2
          columns: 3
          rows: 2
          spacing: 1
          Repeater {
            model: 6
            Rectangle {
              required property int index
              width: (picto.width - 6) / 3
              height: (picto.height - 5) / 2
              radius: 1
              readonly property bool lit: picto.cell
                && Math.floor(index / 3) === picto.cell.row
                && (index % 3) === picto.cell.col
              color: lit ? popup.headColor : Qt.rgba(1, 1, 1, 0.10)
              Behavior on color {
                ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
              }
            }
          }
        }
      }

      Text {
        anchors.left: en.hasPicto ? picto.right : parent.left
        anchors.leftMargin: en.hasPicto ? 8 : 10
        anchors.right: caret.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
        text: en.spec ? Ora.display(en.spec, en.value) : ""
        color: popup.fgColor
        font.family: popup.face
        font.weight: Font.Medium
        font.pixelSize: en.hasPicto ? 14 : 15
      }

      // the one mark that says this opens rather than cycles
      Text {
        id: caret
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: popup.dimColor
        font.family: popup.face
        font.pixelSize: 11
      }

      MouseArea {
        id: chipMa
        anchors.fill: parent
        onClicked: {
          if (en.open) { popup.closeEnumMenu(); return; }
          // the card hangs off the chip's bottom-left, in screen space: this
          // is inside a layer surface, so the item's own coordinates are
          // window-local and have to be moved by the window's origin
          const o = Zenon.winOrigin(popup, popup.screen);
          const p = chip.mapToItem(null, 0, chip.height + 4);
          popup.openEnumMenu(en.spec.key, Qt.point(o.x + p.x, o.y + p.y));
        }
        // the wheel still steps it, for the two-value ones where opening a
        // card to pick between Bottom and Top would be a ceremony
        onWheel: (w) => {
          Oracle.nudge(en.spec.key, w.angleDelta.y > 0 ? 1 : -1);
          w.accepted = true;
        }
      }
    }
  }

  // A line of text, edited in place. It does NOT write on every keystroke: a
  // half-typed path is a real path that picasso would go and scan, so the
  // value is committed on return or on losing focus, and escape puts back
  // whatever was there.
  component TextControl: Item {
    id: tx
    property var spec: null
    property string value: ""
    property bool editing: false
    width: popup.controlW
    height: 28

    onEditingChanged: {
      if (tx.editing) {
        field.text = tx.value;
        field.forceActiveFocus();
        field.selectAll();
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: 4
      color: tx.editing ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
      border.width: 1
      border.color: tx.editing ? popup.highlight : Zenon.msgBorder
      Behavior on border.color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      Text {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        visible: !tx.editing
        verticalAlignment: Text.AlignVCenter
        // From the LEFT: these are mostly paths, and the end of a path is the
        // part that tells you which one it is.
        elide: Text.ElideLeft
        // Empty is a real answer for most of these — no keyboard, no named
        // monitor, no folder chosen — and an em-dash says only "nothing here".
        // The placeholder says what happens instead, which is the thing you
        // actually want to know before deciding whether to type anything.
        text: tx.value !== "" ? tx.value
          : ((tx.spec && tx.spec.placeholder) ? tx.spec.placeholder : "—")
        color: tx.value === "" ? popup.dimColor : popup.fgColor
        font.family: popup.face
        font.pixelSize: 15
      }

      TextInput {
        id: field
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        visible: tx.editing
        verticalAlignment: TextInput.AlignVCenter
        color: popup.highlight
        selectionColor: Zenon.selBg
        selectedTextColor: popup.fgColor
        font.family: popup.face
        font.pixelSize: 15
        clip: true

        onAccepted: {
          Oracle.set(tx.spec.key, field.text);
          popup.editingKey = "";
          popup.syncFocus();
        }
        Keys.onEscapePressed: (e) => {
          e.accepted = true;
          popup.editingKey = "";
          popup.syncFocus();
        }
        // Losing focus is not cancelling. Clicking elsewhere while a path is
        // half-typed should keep what was typed, the way any other text field
        // on this desktop behaves. Escape above is the one that discards, and
        // it has already cleared `editing` by the time this runs.
        onActiveFocusChanged: {
          if (!field.activeFocus && tx.editing) {
            Oracle.set(tx.spec.key, field.text);
            popup.editingKey = "";
          }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: !tx.editing
      onClicked: popup.editingKey = tx.spec.key
    }
  }

  // A fact about the running shell, shown and not settable. Wider than the
  // other controls and elided from the LEFT, because the only one so far is a
  // path and the end of a path is the part that identifies it.
  component InfoControl: Item {
    id: nfo
    property var spec: null
    property string value: ""
    width: popup.controlW + 60
    height: 28

    Text {
      anchors.fill: parent
      verticalAlignment: Text.AlignVCenter
      // LEFT, like every control beside it. It was right-aligned against the
      // panel edge, which put a column of facts and a column of buttons on
      // two different margins.
      horizontalAlignment: Text.AlignRight
      // A path identifies itself by its end and a list of outputs by its
      // start, so which end gets cut is the spec's to say.
      elide: (nfo.spec && nfo.spec.elideLeft) ? Text.ElideLeft : Text.ElideRight
      text: nfo.value
      color: popup.dimColor
      font.family: popup.face
      font.pixelSize: 14
    }
  }

  component ActionControl: Item {
    id: ac
    property var spec: null
    // only as wide as its own button, so the description beside it gets the
    // rest — see controlSlot, which measures this
    width: btn.width
    height: 28

    Rectangle {
      id: btn
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(110, verb.implicitWidth + 28)
      height: 28
      radius: 4
      // PRESSED, not hovered. A button has to answer when you use it; it does
      // not have to announce itself when you pass by.
      color: btnMa.pressed
        ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.28)
        : Qt.rgba(1, 1, 1, 0.06)
      border.width: 1
      border.color: Zenon.msgBorder
      Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      Text {
        id: verb
        anchors.centerIn: parent
        // A context action names the section it would act on. Generic rather
        // than a special case for one key: any action may declare itself
        // context-bound, and the button then stops being a promise you have to
        // take on trust.
        text: {
          if (!ac.spec) return "";
          const v = ac.spec.verb || "Run";
          return ac.spec.context
            ? v + " " + popup.sectionLabel(popup.lastRealSection) : v;
        }
        color: popup.fgColor
        font.family: popup.face
        font.weight: Font.Medium
        font.pixelSize: 15
      }

      MouseArea {
        id: btnMa
        anchors.fill: parent
        onClicked: Oracle.run(ac.spec.key, popup.lastRealSection)
      }
    }
  }

  // ── the surface ───────────────────────────────────────────────────────

  // ONLY THE PANEL TAKES INPUT. The surface is the whole screen, so without
  // this mask the transparent part of it would swallow every click on the
  // desktop underneath — which was survivable while a click outside closed the
  // panel, because the click that got eaten was the one that dismissed it.
  // There is a close button now, so a click outside is meant to reach whatever
  // it landed on, and the mask is what lets it.
  // ── THE MASK, AND WHY A DRAG SUSPENDS IT ──────────────────────────────
  // Only the panel takes input, so a click on the desktop beside it reaches
  // the desktop rather than this full-screen surface. That is right when
  // nothing is being dragged.
  //
  // IT IS WRONG DURING ONE. The panel is 512px tall and the scrollbar's thumb
  // travels some 350 of them, so dragging it to the bottom of a long section
  // takes the pointer past the panel's own bottom edge — which every person
  // who has ever used a scrollbar does without thinking. The moment it leaves
  // the mask the compositor sees input outside this surface: it clears the
  // focus grab, HyprlandFocusGrab.onCleared drops holdKeys, and the pointer
  // stream stops. The thumb freezes where it was and the panel loses the
  // keyboard — exactly the two things that go wrong together.
  //
  // A drag owns the pointer until it is released; that is what a drag IS. So
  // while one is in progress the whole surface takes input and the mask comes
  // back when it ends.
  readonly property bool capturing:
    scroller.dragging || dragArea.pressed || popup.sliderDragging
  // set by NumControl, which is created per row and cannot be reached by id
  property bool sliderDragging: false

  Region { id: panelRegion; item: panel }
  mask: popup.capturing ? null : panelRegion

  Item {
    id: panel
    width: popup.calcWidth()
    height: popup.calcHeight()
    // ROUNDED TO WHOLE PIXELS, and this is not a nicety.
    //
    // bgRoot is a ClippingRectangle, which draws its children through a
    // texture. A texture sampled at a half-pixel offset is resampled, and
    // resampled text is blurred text — every label in the panel goes soft at
    // once. Measured: the same string in the same clipped box, one at x and
    // one at x + 0.5, and the second is visibly smeared.
    //
    // Centred, the arithmetic happens to come out whole on most monitors. The
    // moment the panel is DRAGGED it does not: wayland reports pointer motion
    // in 24.8 fixed point, so the deltas accumulated into placedX are
    // fractional, and the panel has been sitting on a half pixel ever since
    // you first moved it.
    //
    // The accumulator itself stays fractional — rounding that would make a
    // slow drag stutter as it swallowed sub-pixel movement — so the rounding
    // is here, at the one place the number becomes a position.
    x: Math.round(popup.restX)
    y: Math.round(popup.restY)
    z: 1
    opacity: popup.showFactor
    // Out of its own middle, because that is where it stands. Every other
    // layer grows off its bottom edge, which is where the pill is — this one
    // has no pill under it to grow out of.
    transform: Scale {
      origin.x: panel.width / 2
      // ITS OWN MIDDLE, and it does not follow the bar to the other edge the
      // way the morph layers do. This panel is not attached to the pill —
      // it stands free in the centre of the screen — so there is no edge for
      // it to have come out of.
      origin.y: panel.height / 2
      xScale: popup.collapsing ? 0.98 + 0.02 * popup.showFactor
                               : 0.96 + 0.04 * popup.showFactor
      yScale: popup.collapsing ? 0.98 + 0.02 * popup.showFactor
                               : 0.96 + 0.04 * popup.showFactor
    }

    // Clicking the panel takes the keyboard back after it has been given away
    // to another window. Passive — TakeOverForbidden means it watches the press
    // without claiming it — so every control underneath still gets the click
    // that reached it.
    TapHandler {
      acceptedButtons: Qt.AllButtons
      grabPermissions: PointerHandler.TakeOverForbidden
      // ON RELEASE, NEVER ON PRESS — and only when the keyboard has actually
      // gone somewhere else.
      //
      // This used to run at the START of every press anywhere in the panel,
      // and both halves of it disturb a gesture that is still in flight:
      //
      //   syncFocus() calls forceActiveFocus() through Qt.callLater, so it
      //   lands one event-loop turn into the press — and a focus change
      //   there can cancel the pointer grab.
      //
      //   holdKeys re-arms the compositor-side focus grab, and the
      //   compositor re-taking input mid-press interrupts the stream the
      //   same way.
      //
      // Waiting for the release costs nothing: you get the keyboard back
      // when you finish the click rather than when you begin it, and a drag
      // that began on a control now runs to the end without anything
      // reaching in and taking the pointer away from it.
      onPressedChanged: {
        if (pressed) return;
        if (popup.holdKeys && filterInput.activeFocus) return;
        popup.holdKeys = true;
        popup.syncFocus();
      }
    }

    // and a floor under the controls, so a press on bare panel is not a press
    // on the desktop behind it — and bare panel is exactly "somewhere else"
    // as far as an open dropdown is concerned
    MouseArea {
      anchors.fill: parent
      onClicked: popup.closeEnumMenu()
    }

    LayerShadow {
      panel: bgRoot
      cornerRadius: Zenon.pillRadius
    }

    // ClippingRectangle, not Rectangle + clip: true — Qt's own clip knows
    // nothing about the radius, so a square child painted to the panel's edge
    // fills in the rounded corners behind it.
    ClippingRectangle {
      id: bgRoot
      anchors.fill: parent
      // a ClippingRectangle insets its children by border.width on every side;
      // this hands the content its full box back
      anchors.margins: -bgRoot.border.width
      color: popup.bgColor
      radius: Zenon.pillRadius
      topLeftRadius: Zenon.pillRadius
      topRightRadius: Zenon.pillRadius
      bottomLeftRadius: Zenon.pillRadius
      bottomRightRadius: Zenon.pillRadius
      border.color: popup.borderColor
      border.width: 1
      focus: true

      Column {
        anchors.fill: parent

        // ── the head, which is also the handle ───────────────────────
        // What this is, where you are standing in it, what you have typed,
        // and the way out. It is a title bar in the ordinary sense: the
        // whole strip drags the panel, and the controls sitting on it take
        // their own clicks first because they are above it.
        Rectangle {
          id: headBar
          width: parent.width
          height: popup.headH
          color: Zenon.headBg

          // FIRST CHILD, so everything below is above it. A press that no
          // control wanted is a press on the handle — the same rule zeus'
          // drag area follows, and the reason the search field and the close
          // button still work normally.
          // NO CURSOR CHANGE, here or on any control in this panel. A pointer
          // that turns into a hand over every clickable thing is telling you
          // what you already worked out from the control being a switch, a
          // slider or a button — and on a panel that is almost entirely
          // controls it means the cursor is changing shape constantly as you
          // cross it, which reads as flicker rather than as feedback.
          MouseArea {
            id: dragArea
            anchors.fill: parent

            property real px: 0
            property real py: 0

            onPressed: (m) => {
              dragArea.px = m.x;
              dragArea.py = m.y;
              // Latch the position it is being dragged FROM. Until the first
              // drag the panel is centred by a binding, and writing to
              // placedX while that binding still owned the position would
              // have made the first pixel of the first drag jump to 0,0.
              if (!popup.placed) {
                popup.placedX = panel.x;
                popup.placedY = panel.y;
                popup.placed = true;
              }
            }

            onPositionChanged: (m) => {
              if (!dragArea.pressed) return;
              // by the delta, which keeps the pointer where it was pressed
              // inside the bar rather than snapping the corner to it
              popup.placedX += m.x - dragArea.px;
              popup.placedY += m.y - dragArea.py;
              popup.clampPlace();
            }

            // A double click puts it back in the middle, so a panel dragged
            // somewhere awkward has an obvious way home that does not involve
            // finding the exact centre by hand.
            onDoubleClicked: popup.placed = false
          }

          Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: popup.borderColor
          }

          Text {
            id: title
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            text: "Settings"
            color: popup.headColor
            font.family: popup.face
            font.weight: 700
            font.pixelSize: 16
          }

          Text {
            anchors.left: title.right
            anchors.leftMargin: 14
            anchors.right: queryBox.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: {
              if (popup.searching)
                return popup.rows.length + (popup.rows.length === 1
                  ? " setting matches" : " settings match");
              for (let i = 0; i < Oracle.sections.length; ++i)
                if (Oracle.sections[i].id === popup.section)
                  return Oracle.sections[i].blurb;
              return "";
            }
            color: popup.dimColor
            font.family: popup.face
            font.pixelSize: 14
          }

          // NOT A SEARCH BOX. There is nowhere to click and nothing to
          // focus — the panel already holds the keyboard from the moment it
          // opens, so the field was chrome around a thing that was going to
          // happen anyway. What is left is the one piece a box was actually
          // carrying: telling you that typing does something.
          //
          // The hint becomes what you typed. Clicking any section clears it,
          // which is the mouse's way back out, and escape is the keyboard's.
          Item {
            id: queryBox
            anchors.right: changedTag.visible ? changedTag.left : closeBtn.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(hint.implicitWidth, 110)
            height: 24

            Text {
              id: hint
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: popup.searching ? popup.query : "type to filter"
              color: popup.searching ? popup.highlight
                : Qt.rgba(popup.dimColor.r, popup.dimColor.g,
                          popup.dimColor.b, 0.7)
              font.family: popup.face
              font.weight: popup.searching ? Font.Medium : Font.Normal
              font.pixelSize: 14
              elide: Text.ElideLeft
            }

            // The field itself is never seen. It exists because a TextInput is
            // what turns keystrokes into a string, and nothing else in QML
            // does that for you — but `hint` above is what is actually drawn.
            //
            // TRANSPARENT, NOT INVISIBLE. Qt refuses active focus to an item
            // whose `visible` is false, so a hidden field would have taken no
            // keys at all and typing would simply have done nothing. Zero
            // opacity is not the same thing: the item is still there, still
            // focusable, and paints nothing.
            TextInput {
              id: filterInput
              width: 1
              height: 1
              opacity: 0
              activeFocusOnTab: false
              // so escape reaches the one handler that decides what it means
              Keys.forwardTo: bgRoot

              onTextChanged: {
                popup.query = filterInput.text;
                Qt.callLater(() => list.positionViewAtBeginning());
              }

              function clear() {
                filterInput.text = "";
                popup.query = "";
              }
            }
          }

          // How much of this shell is no longer at its defaults. It is the
          // one number a settings panel owes you on the way in: whether what
          // you are looking at is stock.
          Rectangle {
            id: changedTag
            anchors.right: closeBtn.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: changedText.implicitWidth + 16
            height: 22
            radius: 11
            visible: popup.totalChanged > 0
            color: Qt.rgba(popup.changedColor.r, popup.changedColor.g,
                           popup.changedColor.b, 0.16)

            Text {
              id: changedText
              anchors.centerIn: parent
              text: popup.totalChanged + " changed"
              color: popup.changedColor
              font.family: popup.face
              font.weight: Font.Medium
              font.pixelSize: 13
            }
          }

          // The way out, since there is no strip along the bottom teaching
          // you that escape is one. Escape still works; it is just no longer
          // the only thing that does.
          Item {
            id: closeBtn
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26

            Text {
              anchors.centerIn: parent
              text: ""
              color: closeMa.pressed ? popup.errColor : popup.dimColor
              font.family: popup.face
              font.pixelSize: 15
              Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
            }

            MouseArea {
              id: closeMa
              anchors.fill: parent
              onClicked: popup.closePopup()
            }
          }
        }

        // ── the body ─────────────────────────────────────────────────
        Item {
          width: parent.width
          height: popup.bodyH

          // sidebar
          Item {
            id: sidebar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: popup.sideW
            // Dimmed rather than removed while searching: the sections are
            // still where these settings live, and a sidebar that vanished
            // would make a search feel like a different screen.
            opacity: popup.searching ? 0.45 : 1
            Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

            Column {
              // No top inset. A list of sections starts where the list
              // starts; an 8px gap above the first row read as a missing row
              // rather than as breathing space, and left the marker on the
              // current section floating clear of the rule above it.
              anchors.fill: parent
              spacing: 0

              Repeater {
                model: Oracle.sections

                delegate: Item {
                  id: sectionRow
                  required property var modelData
                  required property int index
                  width: sidebar.width
                  height: 40

                  readonly property bool here: !popup.searching
                    && popup.section === sectionRow.modelData.id
                  // Depends on revision for the same reason every row does:
                  // changedIn is a call, not a binding.
                  readonly property int nChanged: {
                    Oracle.revision;
                    return Oracle.changedIn(sectionRow.modelData.id);
                  }

                  // Only where you ARE. Nothing lights up under the pointer:
                  // the section you are standing in is a fact about the panel,
                  // and where the mouse happens to be is not.
                  Rectangle {
                    anchors.fill: parent
                    color: sectionRow.here ? Zenon.selBg : "transparent"
                    Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
                  }

                  Text {
                    id: sectionIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    text: sectionRow.modelData.icon
                    color: sectionRow.here ? popup.headColor : popup.dimColor
                    font.family: popup.face
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
                  }

                  Text {
                    anchors.left: sectionIcon.right
                    anchors.leftMargin: 10
                    anchors.right: sectionDot.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: sectionRow.modelData.label
                    elide: Text.ElideRight
                    color: sectionRow.here ? popup.fgColor : popup.dimColor
                    font.family: popup.face
                    font.weight: sectionRow.here ? Font.DemiBold : Font.Medium
                    font.pixelSize: 16
                    Behavior on color { ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
                  }

                  // A count, not a dot: "3" says how much of this section you
                  // have moved, and a dot would only have said "something".
                  Text {
                    id: sectionDot
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    visible: sectionRow.nChanged > 0
                    text: String(sectionRow.nChanged)
                    color: popup.changedColor
                    font.family: popup.face
                    font.weight: Font.DemiBold
                    font.pixelSize: 13
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: popup.goToSection(sectionRow.modelData.id)
                  }
                }
              }
            }
          }

          Rectangle {
            anchors.left: sidebar.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: popup.borderColor
          }

          // the settings themselves
          Item {
            anchors.left: sidebar.right
            anchors.leftMargin: 1
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            // ── the mark ──────────────────────────────────────────
            // Only over the About section, and not while searching — a
            // search is a flat list across every section, and a banner
            // belonging to one of them sitting on top of it would be
            // claiming the whole list was about that section.
            Item {
              id: markBox
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              visible: popup.section === "about" && !popup.searching
              height: visible ? 132 : 0

              Column {
                anchors.centerIn: parent
                spacing: 0

                Repeater {
                  model: Oracle.mark
                  Text {
                    required property var modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData
                    color: popup.headColor
                    // MONO, not the propo face the rest of the panel is set
                    // in. The figure is three lines of exactly 24 columns and
                    // the whole of it is the grid lining up; a proportional
                    // face closes the gaps between the strokes and it stops
                    // being letters at all.
                    font.family: Zenon.faceMono
                    font.pixelSize: 17
                    // Box-drawing joins edge to edge, so the lines have to
                    // sit exactly one line-height apart or the verticals
                    // break between rows.
                    lineHeight: 1.0
                  }
                }

                // The byline belongs TO the mark, not under it — the gap
                // was reading as a separator between two unrelated things.
                Item { width: 1; height: 6 }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  // StyledText, not RichText: it is one anchor in one line
                  // and StyledText parses <a href> perfectly well, without
                  // pulling in a whole rich-text document to lay out.
                  textFormat: Text.StyledText
                  text: "a desktop suite by <a href=\"" + popup.authorUrl
                    + "\">" + popup.authorName + "</a>"
                  color: popup.dimColor
                  linkColor: popup.headColor
                  font.family: popup.face
                  font.pixelSize: 14

                  // The link opens in whatever the desktop uses for a URL.
                  // execDetached rather than Qt.openUrlExternally: this is a
                  // layer-shell surface with no QDesktopServices behind it,
                  // and xdg-open is what every other outward link in this
                  // shell already goes through.
                  onLinkActivated: (url) => Quickshell.execDetached(
                    ["xdg-open", url])

                  // A link that does not say it is one is a decoration. The
                  // cursor is the only affordance a single word has here, and
                  // it is worth the exception to the panel's no-cursor rule
                  // because nothing else on the page navigates anywhere.
                  HoverHandler {
                    cursorShape: parent.hoveredLink !== ""
                      ? Qt.PointingHandCursor : Qt.ArrowCursor
                  }
                }
              }

              Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                height: 1
                color: Qt.rgba(Zenon.msgBorder.r, Zenon.msgBorder.g,
                               Zenon.msgBorder.b, 0.5)
              }
            }

            Text {
              anchors.centerIn: parent
              visible: popup.rows.length === 0
              text: popup.searching ? "nothing matches “" + popup.query + "”"
                                    : "nothing to set here"
              color: popup.dimColor
              font.family: popup.face
              font.weight: Font.Medium
              font.pixelSize: 16
            }

            // The bar takes its width out of the list rather than floating
            // over it: a control sitting at the right edge of a row would
            // otherwise be under the thumb, and the sliders reach almost to
            // that edge. It is only there when there is something to scroll,
            // and the margin goes with it.
            Scrollbar {
              id: scroller
              flick: list
              anchors.right: parent.right
              anchors.top: markBox.bottom
              anchors.bottom: parent.bottom
              anchors.topMargin: 2
              anchors.bottomMargin: 2
            }

            ListView {
              id: list
              anchors.left: parent.left
              anchors.top: markBox.bottom
              anchors.bottom: parent.bottom
              anchors.right: scroller.scrollable ? scroller.left : parent.right
              clip: true
              model: popup.rows
              visible: popup.rows.length > 0
              boundsBehavior: Flickable.StopAtBounds

              delegate: Item {
                id: settingRow
                required property var modelData
                required property int index
                width: list.width
                height: popup.rowH

                readonly property var spec: settingRow.modelData
                // get() is a function call and therefore not a dependency;
                // revision is the dependency taken in its place, so a reset or
                // an IPC write repaints this row without it being told.
                // Ora.stored: an action is a button and an info row is a
                // readout, and neither has a value to read back or to compare
                // against a default.
                readonly property bool holds: Ora.stored(settingRow.spec)
                readonly property var live: {
                  Oracle.revision;
                  return settingRow.holds
                    ? Oracle.get(settingRow.spec.key) : null;
                }
                readonly property bool moved: {
                  Oracle.revision;
                  return settingRow.holds
                    && !Oracle.isDefault(settingRow.spec.key);
                }

                // A hairline between rows, which is what separates them now
                // that nothing lights up under the pointer. Not on the last
                // one: a rule with nothing below it is an edge, not a divider.
                Rectangle {
                  anchors.bottom: parent.bottom
                  anchors.left: parent.left
                  anchors.leftMargin: 20
                  anchors.right: parent.right
                  anchors.rightMargin: 20
                  height: 1
                  visible: settingRow.index < popup.rows.length - 1
                  color: Qt.rgba(Zenon.msgBorder.r, Zenon.msgBorder.g,
                                 Zenon.msgBorder.b, 0.35)
                }

                Column {
                  id: labels
                  anchors.left: parent.left
                  anchors.leftMargin: 24
                  anchors.right: controlSlot.left
                  anchors.rightMargin: 18
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 2

                  Row {
                    spacing: 8
                    width: parent.width

                    // A changed setting says so in its own name. A dot in the
                    // gutter was a second thing to find; the label is already
                    // where the eye lands, and it is the widest target in the
                    // row, so it is also what you click to put the setting
                    // back. Nothing moves when it changes colour.
                    Text {
                      id: rowLabel
                      text: settingRow.spec.label
                      color: settingRow.moved ? popup.changedColor : Zenon.white
                      font.family: popup.face
                      font.weight: Font.Medium
                      font.pixelSize: 17

                      MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: settingRow.moved
                        hoverEnabled: enabled
                        onClicked: Oracle.reset(settingRow.spec.key)
                      }

                      // The one thing hover still does, and it is not an
                      // effect — it is the only place the old value is
                      // written down, and without it the colour says a
                      // setting moved but not from what, and gives no hint
                      // that the name is a way back.
                      Tooltip {
                        anchorItem: rowLabel
                        cursorArea: resetMa
                        text: "was " +
                          Ora.display(settingRow.spec, Oracle.defaults[settingRow.spec.key]) +
                          " · click to put it back"
                        show: resetMa.containsMouse
                      }
                    }

                    // Only while searching. Standing in a section the badge
                    // would say the name already at the top of the panel on
                    // every single row.
                    Rectangle {
                      visible: popup.searching
                      width: sectionBadge.implicitWidth + 12
                      height: 19
                      radius: 3
                      anchors.verticalCenter: parent.verticalCenter
                      color: Qt.rgba(1, 1, 1, 0.07)
                      Text {
                        id: sectionBadge
                        anchors.centerIn: parent
                        text: popup.sectionLabel(settingRow.spec.section)
                        color: popup.dimColor
                        font.family: popup.face
                        font.pixelSize: 12
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    visible: text !== ""
                    text: settingRow.spec.help || ""
                    elide: Text.ElideRight
                    // The help line is not a footnote — it is the half of the
                    // row that says what the setting actually does, and at 12
                    // against a 17px label it read as one.
                    color: popup.dimColor
                    font.family: popup.face
                    font.pixelSize: 14
                  }
                }

                Item {
                  id: controlSlot
                  anchors.right: parent.right
                  anchors.rightMargin: 20
                  anchors.verticalCenter: parent.verticalCenter
                  // WHAT THE CONTROL ACTUALLY NEEDS, measured off the one
                  // that got loaded rather than reserved for the widest kind
                  // there is. This is what hands a bool row's 200 spare
                  // pixels to its description.
                  width: ctl.item ? ctl.item.width : popup.controlW
                  height: 30

                  Loader {
                    id: ctl
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: {
                      const t = settingRow.spec.type;
                      if (t === "bool") return boolComp;
                      if (t === "enum") return enumComp;
                      if (t === "text") return textComp;
                      if (t === "action") return actionComp;
                      if (t === "info") return infoComp;
                      return numComp;
                    }
                  }

                  Component { id: boolComp
                    BoolControl { spec: settingRow.spec
                                  value: settingRow.live === true } }
                  Component { id: numComp
                    NumControl { spec: settingRow.spec
                                 value: Number(settingRow.live) } }
                  Component { id: enumComp
                    EnumControl { spec: settingRow.spec; value: settingRow.live } }
                  Component { id: textComp
                    TextControl { spec: settingRow.spec
                                  value: String(settingRow.live)
                                  editing: popup.editingKey === settingRow.spec.key } }
                  Component { id: actionComp
                    ActionControl { spec: settingRow.spec } }
                  Component { id: infoComp
                    InfoControl { spec: settingRow.spec
                                  // revision AND shown: the first catches a
                                  // reload that moves the file, the second a
                                  // monitor plugged in while the panel was
                                  // closed — neither is a property, so
                                  // neither is a dependency on its own
                                  value: (Oracle.revision, popup.shown,
                                          Oracle.info(settingRow.spec.key)) } }
                }
              }
            }
          }
        }
      }

      // ── the one key ──────────────────────────────────────────────────
      // Escape, and nothing else. Everything this panel does is a click, and
      // a strip of chords along the bottom would have been teaching a
      // keyboard interface that is no longer here — but escape closing a
      // panel is not a chord, it is what escape does everywhere, and taking
      // it away would be its own surprise.
      Keys.onEscapePressed: (event) => {
        event.accepted = true;
        // innermost first: put away what you have built up, and only close
        // once there is nothing left — the same cascade every layer uses
        if (popup.enumKey !== "") {
          popup.closeEnumMenu();
        } else if (popup.editingKey !== "") {
          popup.editingKey = "";
          popup.syncFocus();
        } else if (popup.searching) {
          filterInput.clear();
        } else {
          popup.closePopup();
        }
      }
    }
  }

  // How many settings, everywhere, are off their defaults. Bound here rather
  // than in the badge so the count is computed once per revision instead of
  // once per repaint of a Text.
  readonly property int totalChanged: {
    Oracle.revision;
    return Oracle.changedIn("");
  }



  // ── the dropdown ──────────────────────────────────────────────────────
  // icarus' card, shared by every enum row. It is a separate layer surface,
  // so it is in the focus grab above; without that, opening it would read as
  // a click outside the panel and take the panel down with it.
  CardMenu {
    id: enumMenu
    screen: popup.screen
    open: popup.enumKey !== "" && !popup.enumIsGrid
    at: popup.enumAt
    model: popup.enumRows
    cardWidth: 200

    onChosen: (i) => {
      const sp = popup.enumSpec;
      if (!sp) return;
      const opts = sp.options || [];
      if (i >= 0 && i < opts.length) Oracle.set(sp.key, opts[i].value);
      popup.closeEnumMenu();
    }
    onDismissed: popup.closeEnumMenu()
  }

  // The same dropdown for the settings that name a place: the screen itself,
  // with six cells you click. See CornerPicker.
  CornerPicker {
    id: cornerMenu
    screen: popup.screen
    open: popup.enumKey !== "" && popup.enumIsGrid
    at: popup.enumAt
    cellRow: popup.enumCell.row
    cellCol: popup.enumCell.col
    autoOn: popup.enumAutoOn
    autoLabel: "Follow bar"

    onPicked: (r, c) => {
      const v = popup.valueForCell(r, c);
      if (v !== "" && popup.enumSpec) Oracle.set(popup.enumSpec.key, v);
      popup.closeEnumMenu();
    }
    onPickedAuto: {
      if (popup.enumSpec) Oracle.set(popup.enumSpec.key, "auto");
      popup.closeEnumMenu();
    }
    onDismissed: popup.closeEnumMenu()
  }


}
