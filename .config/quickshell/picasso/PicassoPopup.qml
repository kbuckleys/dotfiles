// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The setter. Pick a wallpaper in the grid, then pick where it goes from the
// strip along the bottom — the same two-step shape ideo uses to choose an
// icon and then its format.

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "../morpheus"
import "picasso.js" as Art

PanelWindow {
  id: popup

  WlrLayershell.layer: WlrLayer.Overlay

  property bool shown: false
  property bool morphMode: false
  property real morphFade: 1
  property real showFactor: 0
  property bool collapsing: false
  readonly property real panelX: (popup.collapsing ? 0.985 + 0.015 * popup.showFactor
                        : 0.94 + 0.06 * popup.showFactor)
  readonly property real panelY: (popup.collapsing ? 0.82 + 0.18 * popup.showFactor
                        : 0.90 + 0.10 * popup.showFactor)
  // Math.min, not morphFade alone. Handing the pill straight to another
  // layer leaves morphFade pinned at 1 — the pill never un-morphs, so there
  // is nothing to ease it down — and this layer stayed fully opaque until its
  // window simply blinked out. Its own closeAnim is already easing
  // showFactor to 0, so taking the lower of the two fades it out on the way
  // between layers while leaving the normal open schedule untouched.
  readonly property real contentFade: popup.morphMode
    ? Math.min(popup.morphFade, popup.showFactor) : popup.showFactor

  property var statusbar: null

  readonly property color bgColor: Zenon.layerBg
  readonly property color borderColor: Zenon.surfaceBorder
  readonly property color msgColor: Zenon.headBg
  readonly property color msgBorder: Zenon.msgBorder
  readonly property color fgColor: Zenon.white
  readonly property color headColor: Zenon.cyan
  readonly property color keyColor: Zenon.keyInk
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
  // The pink is kept for the one job it is good at: marking something that is
  // no longer at its default, or already in use. That is a STATE, it wants to
  // be told apart from the cyan at a glance, and it appears in very few
  // places — the sidebar's count, the dot on a changed row, and picasso's
  // tick on a background that is currently up.
  readonly property color highlight: Zenon.cyan
  readonly property color entryColor: Zenon.pink
  readonly property color selColor: Zenon.selBg

  property string query: ""
  property int sel: 0

  // ── the context menu ─────────────────────────────────────────────────
  // Picking a wallpaper used to swap the bottom strip for a row of monitor
  // buttons and a way back — a second MODE, inside a panel that was already
  // a mode. It is a context menu now, the same card icarus opens on the
  // desktop: it appears where you clicked, it does not disturb the grid
  // behind it, and there is nothing to come back from because nothing went
  // away.
  //
  // `menuPath` is what the menu is ABOUT — the wallpaper it was opened on —
  // held rather than read back off the selection, because hovering the grid
  // moves the selection and the menu must not quietly change its mind about
  // which image it is going to set.
  property string menuPath: ""
  property point menuAt: Qt.point(0, 0)
  property bool menuOpen: false
  // which monitor row the submenu is hanging off, -1 for none
  property int menuBranch: -1

  // Filter first, then order: the sort only has to touch what survived, and
  // the two are separate questions the user changes independently.
  readonly property var filtered: Art.sortRows(
    Art.filter(Picasso.files, popup.query, Picasso.dir),
    Picasso.sortMode, Picasso.dir)

  // "All monitors" first, then one entry per connected output. Built from the
  // live screen list, so plugging a monitor in adds its option with no edit.
  readonly property var targets: {
    const out = [{ key: Picasso.fallbackKey, label: "All monitors" }];
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; ++i)
      out.push({ key: screens[i].name, label: screens[i].name });
    return out;
  }

  // The card's rows. A separator under "All monitors", because setting every
  // screen at once is a different kind of act from setting one of them.
  readonly property var menuRows: {
    const out = [];
    for (let i = 0; i < popup.targets.length; ++i) {
      out.push({ text: popup.targets[i].label, hasChildren: true,
                 icon: i === 0 ? "\uF0C9" : "\uF108" });
      if (i === 0) out.push({ isSeparator: true });
    }
    return out;
  }

  // A menu row index back to the target it names — the separator sits between
  // them, so the two lists are not the same length and an index into one is
  // not an index into the other.
  function targetOf(rowIndex) {
    if (rowIndex <= 0) return 0;
    return rowIndex - 1;
  }

  // The branch: what this wallpaper would do on that monitor, and how that
  // monitor fits whatever is on it. Setting the fit does NOT need the
  // wallpaper — a monitor's fit is its own, and changing it without changing
  // the image is the common case once everything is already in place.
  readonly property var branchRows: {
    const out = [{ text: "Set background", icon: "\uF03E" },
                 { isSeparator: true }];
    const t = popup.targets[popup.targetOf(popup.menuBranch)];
    const key = t ? t.key : Picasso.fallbackKey;
    // "All monitors" reports the default; a named one reports its own answer
    const now = key === Picasso.fallbackKey
      ? Picasso.defaultFit : Picasso.fitFor(key);
    for (let i = 0; i < Picasso.fitModes.length; ++i) {
      const m = Picasso.fitModes[i];
      out.push({ text: Picasso.fitLabels[m].replace(/^./, (c) => c.toUpperCase()),
                 mark: m === now });
    }
    return out;
  }

  readonly property int cols: 4
  readonly property int visibleRows: 3
  // The GRID's own width over the columns, not one constant over another. Two
  // things move it: the panel follows Zenon.layerWidth, and the scrollbar
  // takes a strip off the right. A fixed 1000/4 left the last column hanging
  // off the edge as soon as either of them was not what it used to be.
  readonly property int cellW:
    Math.max(80, Math.floor(grid.width / popup.cols))
  readonly property int cellH: 150

  function gridHeight() {
    if (popup.filtered.length === 0) return 90;
    const rows = Math.ceil(popup.filtered.length / popup.cols);
    return Math.max(1, Math.min(rows, popup.visibleRows)) * popup.cellH;
  }

  // One line, and always the same one. The hint strip that used to sit under
  // this taught a set of chords — type, alt s, alt f, return, esc — and every
  // one of them is now a thing on screen you can point at: the two rings are
  // words you click, and a thumbnail opens a menu. A strip explaining the
  // keyboard equivalents of visible controls is a strip teaching you the
  // slower way to do what you were about to do anyway.
  //
  // It no longer changes height either. The monitor row that used to replace
  // it is a card floating over the grid, so the panel underneath stays
  // exactly the size it was — which is the other half of a menu not being a
  // mode.
  //
  // The keys all still work. They are simply no longer the interface.
  function stripHeight() { return 34; }

  function calcHeight() {
    return popup.gridHeight() + popup.stripHeight();
  }

  // Nothing typed, nothing scanning — the line is free to report state rather
  // than to carry a message.
  readonly property bool restingStatus: popup.query === "" && !Picasso.scanning

  // One piece of cycling state, set off from whatever is to its left.
  //
  // DRAWN AS A CHIP, not as a word. These were plain text the same weight and
  // colour as the count beside them, so the two things that can be clicked in
  // this strip looked exactly like the one thing that cannot — the only hint
  // was the cursor changing, and the cursor does not change here any more. A
  // bordered chip says "press me" without a hint bar having to say it.
  component Ring: Item {
    id: ring
    property string label: ""
    property var act: null

    implicitWidth: ringSep.implicitWidth + chip.width
    implicitHeight: 22

    Text {
      id: ringSep
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "  󰇘  "
      color: Qt.rgba(popup.dimColor.r, popup.dimColor.g, popup.dimColor.b, 0.6)
      font.family: Zenon.face
      font.pixelSize: 14
    }

    Rectangle {
      id: chip
      anchors.left: ringSep.right
      anchors.verticalCenter: parent.verticalCenter
      width: ringWord.implicitWidth + 18
      height: 22
      radius: 4
      color: ringMa.pressed
        ? Qt.rgba(popup.highlight.r, popup.highlight.g, popup.highlight.b, 0.26)
        : (ringMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
      border.width: 1
      border.color: ringMa.containsMouse ? popup.highlight : Zenon.msgBorder
      Behavior on color {
        ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
      }
      Behavior on border.color {
        ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
      }

      Text {
        id: ringWord
        anchors.centerIn: parent
        text: ring.label
        color: popup.headColor
        font.family: Zenon.face
        font.weight: 600
        font.pixelSize: 14
      }

      MouseArea {
        id: ringMa
        anchors.fill: parent
        hoverEnabled: true
        onClicked: ring.act()
      }
    }
  }

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
    onFinished: popup.shown = false
  }

  // ONE GRAB OVER ALL THREE SURFACES. A card is its own layer-shell window,
  // so a grab that listed only the panel would treat the card as "somewhere
  // else" and close everything the moment the card appeared. Icarus keeps the
  // same list for the same reason.
  readonly property var grabWindows: {
    const out = [popup];
    if (menuCard.visible) out.push(menuCard);
    if (branchCard.visible) out.push(branchCard);
    return out;
  }

  HyprlandFocusGrab {
    id: grab
    windows: popup.grabWindows
    active: popup.shown
    onCleared: popup.closePopup()
  }

  IpcHandler {
    target: "Picasso"

    function toggle() { popup.toggle(); }
    function rescan(): string { Picasso.scan(); return "scanning"; }
    function status(): string {
      return "dir=" + Picasso.dir + " files=" + Picasso.files.length
        + " assignment=" + JSON.stringify(Picasso.assignment);
    }
  }

  // ---------------------------------------------------------- actions --

  function openPopup() {
    popup.shown = true;
    popup.collapsing = false;
    popup.query = "";
    popup.sel = 0;
    popup.closeMenu();
    popup.menuPath = "";
    Picasso.scan();
    closeAnim.stop();
    popup.showFactor = 0;
    openAnim.restart();
    popup.syncFocus();
  }

  function closePopup() {
    popup.collapsing = true;
    openAnim.stop();
    closeAnim.restart();
  }

  function toggle() {
    if (popup.shown) popup.closePopup();
    else popup.openPopup();
  }

  function syncFocus() {
    Qt.callLater(() => {
      if (!popup.shown) return;
      bgRoot.forceActiveFocus();
    });
  }

  function clampSel() {
    const len = popup.filtered.length;
    if (len === 0) popup.sel = 0;
    else popup.sel = Math.max(0, Math.min(popup.sel, len - 1));
    followSelection();
  }

  function moveSel(delta) {
    const len = popup.filtered.length;
    if (len === 0) return;
    popup.sel = Math.max(0, Math.min(popup.sel + delta, len - 1));
    followSelection();
  }

  function followSelection() {
    Qt.callLater(() => grid.positionViewAtIndex(popup.sel, GridView.Contain));
  }

  // `at` is where the card's corner goes, in SCREEN coordinates. The grid
  // lives inside a layer surface, so a cell's own coordinates are
  // window-local and have to be moved by that window's origin — the same
  // conversion every popout anchored to a bar module makes. See
  // Zenon.winOrigin, which exists because the one that skipped it landed a
  // side-margin off.
  function openMenu(path, at) {
    if (path === "") return;
    popup.menuPath = path;
    popup.menuAt = at;
    popup.menuBranch = -1;
    popup.menuOpen = true;
  }

  // Opened from the keyboard, which has no pointer to put the card under: it
  // goes at the selected cell instead, which is where you were looking.
  function openMenuAtSelection() {
    if (popup.filtered.length === 0) return;
    const i = Math.min(popup.sel, popup.filtered.length - 1);
    const item = grid.itemAtIndex(i);
    const o = Zenon.winOrigin(popup, popup.screen);
    const p = item
      ? item.mapToItem(null, item.width * 0.5, item.height * 0.5)
      : Qt.point(panel.x + panel.width / 2, panel.y + panel.height / 2);
    popup.openMenu(popup.filtered[i].path,
                   Qt.point(o.x + p.x, o.y + p.y));
  }

  function closeMenu() {
    popup.menuOpen = false;
    popup.menuBranch = -1;
  }

  function targetKey(i) {
    const t = popup.targets[i];
    return t ? t.key : Picasso.fallbackKey;
  }

  // THE PICKER STAYS OPEN. Applying a background is not the end of the
  // errand — it is the middle of it: the next thing you do is look at what
  // it actually turned out like and try the one below it, and a picker that
  // shut itself made that two more keypresses every single time. The card
  // goes away, because the card WAS a question and it has been answered;
  // the grid behind it does not.
  //
  // Escape, the close button on the pill, or clicking off the panel are the
  // ways out, and all three are one action.
  function applyBackground(targetIndex) {
    const key = popup.targetKey(targetIndex);
    if (popup.menuPath === "") return;
    if (key === Picasso.fallbackKey) Picasso.setAll(popup.menuPath);
    else Picasso.setFor(key, popup.menuPath);
    popup.closeMenu();
  }

  // Setting a FIT does not close anything. It is a thing you step through
  // while watching the monitor behind the picker change, and a panel that
  // shut on the first step would make comparing two of them impossible.
  function applyFit(targetIndex, fit) {
    const key = popup.targetKey(targetIndex);
    if (key === Picasso.fallbackKey) Picasso.setFitAll(fit);
    else Picasso.setFitFor(key, fit);
  }

  // ------------------------------------------------------------ panel --

  // The surface outside the panel. Innermost first: a card is what a click
  // out here is most likely aimed at putting away, and closing the whole
  // picker instead would be answering a question nobody asked.
  MouseArea {
    anchors.fill: parent
    z: 0
    onClicked: {
      if (popup.menuOpen) popup.closeMenu();
      else popup.closePopup();
    }
  }

  Item {
    id: panel
    width: Zenon.layerWidth(1000)
    height: popup.calcHeight()
    Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
    // Either edge. A layer opens out of the pill, so it has to be on the
    // same one — anchored to whichever it is and given the same lift, with
    // the unused anchor left undefined so the two can never both apply.
    anchors {
      horizontalCenter: parent.horizontalCenter
      top: Zenon.barTop ? parent.top : undefined
      bottom: Zenon.barTop ? undefined : parent.bottom
      topMargin: Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
      bottomMargin: Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
    }
    z: 1
    opacity: popup.contentFade
    transform: Scale {
      origin.x: panel.width / 2
      // grows out of the edge the bar is on, which is the edge it came from
      origin.y: Zenon.barTop ? 0 : panel.height
      xScale: popup.panelX
      yScale: popup.panelY
    }

    // Swallows what no control wanted, so a press on bare panel is not a
    // press on the desktop behind it — and dismisses the card, because bare
    // panel is exactly "somewhere else".
    MouseArea {
      anchors.fill: parent
      onClicked: if (popup.menuOpen) popup.closeMenu()
    }

    LayerShadow {
      panel: bgRoot
      cornerRadius: bgRoot.radius
      morphed: popup.morphMode
    }

    // ClippingRectangle, not Rectangle + clip: true. Qt's own clip is
    // RECTANGULAR — it clips to the bounding box and knows nothing about the
    // radius — so every square child painted to the panel's edge (the bottom
    // strip most visibly) filled in the rounded corners behind it. This one
    // clips to the rounded shape itself.
    ClippingRectangle {
      id: bgRoot
      anchors.fill: parent
      // Grown by its own border: a ClippingRectangle insets its children by
      // border.width on every side, so the content box came out 2px smaller
      // than the panel and any layout measured against the panel's size fell
      // one row or one column short. This hands the content its full box back.
      anchors.margins: -bgRoot.border.width
      color: popup.bgColor
      radius: Zenon.pillRadius
      border.color: popup.borderColor
      border.width: 1
      focus: true

      Keys.onEscapePressed: (event) => {
        event.accepted = true;
        // innermost first, the cascade every layer here uses: the branch, then
        // the card, then the filter, and only then the panel
        if (popup.menuBranch >= 0) popup.menuBranch = -1;
        else if (popup.menuOpen) popup.closeMenu();
        else if (popup.query !== "") popup.query = "";
        else popup.closePopup();
      }

      Keys.onPressed: (event) => {
        // The card is modal over the grid: while it is up nothing behind it
        // moves, so a stray arrow key cannot change which wallpaper the menu
        // is about underneath the menu. Escape is handled above.
        if (popup.menuOpen) return;

        if (event.key === Qt.Key_S && (event.modifiers & Qt.AltModifier)) {
          event.accepted = true;
          Picasso.cycleSort();
          // the row under the cursor is meaningless once the order changes
          popup.sel = 0;
          popup.followSelection();
        } else if (event.key === Qt.Key_F && (event.modifiers & Qt.AltModifier)) {
          // How the image is fitted to a monitor that is not its shape:
          // cropped, fitted, stretched, centred, tiled. Alt, and beside the
          // sort, because it is the same kind of thing — a ring you step
          // through that changes how the list you are looking at is applied
          // rather than which images are in it.
          //
          // The selection is NOT reset the way the sort resets it: the order
          // has not changed, so the row under the cursor is still the row you
          // were on, and the wallpaper already on screen re-fits underneath
          // the picker as you step. That is the point — you are watching it.
          event.accepted = true;
          Picasso.cycleFit();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          event.accepted = true;
          popup.openMenuAtSelection();
        } else if (event.key === Qt.Key_Left) {
          event.accepted = true; popup.moveSel(-1);
        } else if (event.key === Qt.Key_Right) {
          event.accepted = true; popup.moveSel(1);
        } else if (event.key === Qt.Key_Up) {
          event.accepted = true; popup.moveSel(-popup.cols);
        } else if (event.key === Qt.Key_Down) {
          event.accepted = true; popup.moveSel(popup.cols);
        } else if (event.key === Qt.Key_PageUp) {
          event.accepted = true; popup.moveSel(-popup.cols * popup.visibleRows);
        } else if (event.key === Qt.Key_PageDown) {
          event.accepted = true; popup.moveSel(popup.cols * popup.visibleRows);
        } else if (event.key === Qt.Key_Backspace) {
          event.accepted = true;
          if (popup.query.length > 0) {
            const chars = Array.from(popup.query);
            chars.pop();
            popup.query = chars.join("");
            popup.clampSel();
          }
        } else if (event.text && event.text.length > 0 &&
                   !(event.modifiers & Qt.ControlModifier) &&
                   !(event.modifiers & Qt.AltModifier) &&
                   !(event.modifiers & Qt.MetaModifier) &&
                   event.key !== Qt.Key_Escape && event.key !== Qt.Key_Tab) {
          event.accepted = true;
          popup.query += event.text;
          popup.clampSel();
        }
      }

      Column {
        anchors.fill: parent

        // ------------------------------------------------- the grid --
        Item {
          width: parent.width
          height: popup.gridHeight()

          Text {
            anchors.centerIn: parent
            visible: popup.filtered.length === 0
            text: Picasso.scanning ? "scanning…"
              : (Picasso.files.length === 0
                  ? "no backgrounds in " + Picasso.dir
                  : "no match")
            color: popup.dimColor
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 16
          }

          // Three rows of thumbnails at a time and no other sign that there
          // are more below them — the grid is scrolled with a wheel now, so
          // it says how far down it goes and offers something to drag.
          Scrollbar {
            id: gridScroll
            flick: grid
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 4
            anchors.bottomMargin: 4
          }

          GridView {
            id: grid
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            // THE STRIP IS RESERVED WHETHER OR NOT THE BAR IS SHOWING, and
            // that is not laziness. A GridView's contentHeight is a function
            // of its cellWidth — fewer columns, more rows — so giving the grid
            // its width back when nothing needs scrolling closes a circle:
            // width decides cellWidth decides contentHeight decides whether it
            // scrolls decides width. Ten pixels of always-empty gutter is the
            // price of that not being a binding loop.
            //
            // Oracle's list has no such circle — its rows are a fixed height —
            // so there the bar does give its width back.
            anchors.right: gridScroll.left
            clip: true
            visible: popup.filtered.length > 0
            model: popup.filtered
            cellWidth: popup.cellW
            cellHeight: popup.cellH
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              id: cell
              required property var modelData
              required property int index
              width: popup.cellW
              height: popup.cellH

              readonly property bool selected: cell.index === popup.sel

              Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: 6
                color: cell.selected ? popup.selColor : "transparent"
              }

              ClippingRectangle {
                id: thumbBox
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: popup.cellW - 28
                height: popup.cellH - 52
                radius: 5
                color: Zenon.surface

                Image {
                  id: thumb
                  anchors.fill: parent
                  // The cached thumbnail, not the original: these are ~70KB
                  // against 8MB, and the grid rebuilds on every keystroke.
                  // Falls back to the original if a thumbnail could not be
                  // generated, so a picker that cannot thumbnail still works.
                  property bool thumbFailed: false
                  readonly property string thumbPath: cell.modelData.thumb ?? ""
                  source: (thumb.thumbPath !== "" && !thumb.thumbFailed)
                    ? "file://" + thumb.thumbPath
                    : "file://" + cell.modelData.path
                  onStatusChanged: {
                    if (status === Image.Error && !thumb.thumbFailed)
                      thumb.thumbFailed = true;
                  }
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  // Decoded at the size of the box it is drawn in, not at the
                  // size of the file. The thumbnails are 480px square and this
                  // box is 222x98, so without this every cell carries about
                  // five times the pixels it can show — measured over the whole
                  // library that is 193MB of grid against 105MB, and the grid
                  // does not give it back when it scrolls away.
                  //
                  // It matters far more on the fallback line above. A wallpaper
                  // whose thumbnail is missing is shown FROM THE ORIGINAL, and
                  // the originals here run to 7276x4895 — 135MB of RGBA for one
                  // cell 222 pixels wide.
                  //
                  // Both axes, which is safe on Image: it scales to cover the
                  // box with the aspect ratio intact. (AnimatedImage does not —
                  // see the Wall component in PicassoDaemon.qml.)
                  sourceSize.width: Math.ceil(thumbBox.width * thumb.Screen.devicePixelRatio)
                  sourceSize.height: Math.ceil(thumbBox.height * thumb.Screen.devicePixelRatio)
                  // Safe to cache now. The cache filename carries the source's
                  // mtime and size, so a replaced wallpaper is a different URL
                  // — Qt can no longer pin a stale decode failure to it.
                  cache: true
                }

                // An image Qt cannot decode used to leave a plain empty box,
                // indistinguishable from a very dark wallpaper. Say so.
                Text {
                  anchors.centerIn: parent
                  visible: thumb.status === Image.Error
                  text: "\uF071"
                  color: popup.dimColor
                  font.family: Zenon.face
                  font.pixelSize: 22
                }

                Text {
                  anchors.centerIn: parent
                  visible: thumb.status === Image.Loading
                  text: "\uF110"
                  color: popup.dimColor
                  font.family: Zenon.face
                  font.pixelSize: 18
                }
              }

              // a corner tick on whatever is currently on a monitor, so the
              // grid says what is already in use without being opened twice
              Rectangle {
                anchors.right: thumbBox.right
                anchors.top: thumbBox.top
                anchors.margins: 4
                width: 18
                height: 18
                radius: 9
                visible: popup.inUse(cell.modelData.path)
                color: popup.entryColor
                Text {
                  anchors.centerIn: parent
                  text: ""
                  color: "#000000"
                  font.family: Zenon.face
                  font.pixelSize: 11
                }
              }

              Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: popup.cellW - 28
                text: Art.label(cell.modelData.path)
                color: cell.selected ? popup.highlight : popup.dimColor
                font.family: Zenon.face
                font.weight: cell.selected ? Font.Bold : Font.Normal
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
              }

              MouseArea {
                id: cellMa
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                // NO HOVER. The selection used to follow the pointer across
                // the grid, which meant it was never reporting a choice — it
                // was reporting where the mouse happened to be, and it moved
                // under the card the moment you reached for one. It is a
                // choice now: a click puts it somewhere and it stays there,
                // which is also what makes the keyboard's arrows and the
                // pointer agree about what is selected.
                onClicked: (m) => {
                  // A left click while a card is open puts the card away and
                  // does nothing else. It is the click you make to dismiss,
                  // and having it also apply a wallpaper would mean closing a
                  // menu changed your desktop.
                  if (popup.menuOpen && m.button === Qt.LeftButton) {
                    popup.closeMenu();
                    return;
                  }
                  popup.sel = cell.index;

                  if (m.button === Qt.RightButton) {
                    // where the pointer actually is, in screen space: the
                    // cell's own coordinates are window-local, so they are
                    // moved by the surface's origin — see Zenon.winOrigin
                    const o = Zenon.winOrigin(popup, popup.screen);
                    const p = mapToItem(null, m.x, m.y);
                    popup.openMenu(cell.modelData.path,
                                   Qt.point(o.x + p.x, o.y + p.y));
                    return;
                  }

                  // LEFT CLICK IS THE OBVIOUS THING: put this on every
                  // monitor. It is what a picture in a wallpaper picker looks
                  // like it does, it is what the old flow took two steps to
                  // reach, and it is undone by clicking another one — which
                  // is exactly why the picker stays up afterwards. The right
                  // button is for the cases that are not obvious: one
                  // monitor, or how it is fitted.
                  Picasso.setAll(cell.modelData.path);
                }
              }
            }
          }
        }

        // --------------------------------------------- bottom strip --
        Rectangle {
          width: parent.width
          height: popup.stripHeight()
          color: popup.msgColor
          Behavior on height { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: popup.msgBorder
          }

          Column {
            anchors.fill: parent
            topPadding: 6
            bottomPadding: 6
            spacing: -2

            // The count, then the two rings that decide how what you are
            // looking at is ordered and how it is fitted.
            //
            // Both rings are CLICKABLE as well as keyed. alt+s and alt+f stay
            // the fast path, but a word that reports a cycling state and
            // cannot be clicked is a small lie about itself — and the fit in
            // particular is a thing you step through while WATCHING the
            // wallpaper behind the picker change, which is a pointer job.
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: 0

              Item {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: countText.implicitWidth
                implicitHeight: countText.implicitHeight

                Text {
                  id: countText
                  // Doubles as the input, since there is no field — the same
                  // shape howler uses. What you type lands here.
                  text: popup.query !== "" ? popup.query
                    : (Picasso.scanning ? "scanning…"
                        : popup.filtered.length + (popup.filtered.length === 1
                            ? " Background" : " Backgrounds"))
                  color: popup.query !== "" && clearMa.containsMouse
                    ? popup.highlight : popup.headColor
                  font.bold: true
                  font.family: Zenon.face
                  font.weight: 600
                  font.pixelSize: 15
                  Behavior on color {
                    ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                  }
                }

                // Escape empties the filter, and escape was on the strip that
                // is gone. Clicking what you typed empties it too, so there
                // is a way back out of a search that does not need a key.
                MouseArea {
                  id: clearMa
                  anchors.fill: parent
                  anchors.margins: -4
                  enabled: popup.query !== ""
                  hoverEnabled: true
                  onClicked: popup.query = ""
                }
              }

              // Neither ring is shown while you are typing or while the scan
              // is running: the line is carrying one message at a time, and
              // that message is what you typed or what it is doing.
              Ring {
                visible: popup.restingStatus
                anchors.verticalCenter: parent.verticalCenter
                label: Picasso.sortMode
                act: () => {
                  Picasso.cycleSort();
                  // the row under the cursor is meaningless once the order
                  // changes — the same reset alt+s does
                  popup.sel = 0;
                  popup.followSelection();
                }
              }

              Ring {
                visible: popup.restingStatus
                anchors.verticalCenter: parent.verticalCenter
                label: Picasso.fitLabel
                act: () => Picasso.cycleFit()
              }

              // The one thing on the old strip that was not an explanation of
              // a visible control: filtering has nothing on screen to point
              // at, because it IS the line above. So it keeps its hint, and
              // only while there is nothing typed.
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: popup.restingStatus
                text: "    type to filter"
                color: Qt.rgba(popup.dimColor.r, popup.dimColor.g,
                               popup.dimColor.b, 0.7)
                font.family: Zenon.face
                font.pixelSize: 13
              }
            }

          }
        }
      }
    }
  }

  // is this file currently painted on any monitor
  function inUse(path) {
    const a = Picasso.assignment;
    for (const k in a) if (a[k] === path) return true;
    return false;
  }

  // ── the context menu ──────────────────────────────────────────────────
  // Two cards: the monitors, and one monitor's answers. Both are CardMenu,
  // which is icarus' card factored out — same ground, same 30px rows, same
  // arrival, same shadow — so a menu opened on a wallpaper and a menu opened
  // on the desktop are visibly the same object.

  CardMenu {
    id: menuCard
    screen: popup.screen
    open: popup.menuOpen
    at: popup.menuAt
    model: popup.menuRows
    cardWidth: 220

    // The row whose answers are open stays lit while you are inside them —
    // the pointer has by then moved off it onto the child card.
    activeIndex: popup.menuBranch

    // Hovering a monitor opens its answers, clicking it sets the background
    // there. The same pair icarus' rows use: a branch you can also act on.
    onHovered: (i) => popup.menuBranch = i
    onChosen: (i) => popup.applyBackground(popup.targetOf(i))
    onDismissed: popup.closeMenu()
  }

  CardMenu {
    id: branchCard
    screen: popup.screen
    open: popup.menuOpen && popup.menuBranch >= 0
    model: popup.branchRows
    // wide enough for "Set background" and its icon at the card's 16px — the
    // rows below it are single words, so this row is what sets the width
    cardWidth: 210
    // Against its own row of the card it hangs off, and to the right of it
    // where there is room — CardMenu clamps to the screen, so the left is
    // handled by it rather than by a second copy of that arithmetic here.
    at: Qt.point(menuCard.cardX + menuCard.cardWidth,
                 menuCard.cardY + menuCard.rowY(Math.max(0, popup.menuBranch)))
    // Hinged off the card it hangs from: to its right where there is room, to
    // its left otherwise, squaring whichever corner ends up against it.
    hinged: true
    flipFrom: menuCard.cardX + menuCard.cardWidth
    flipParentLeft: menuCard.cardX

    onChosen: (i) => {
      const t = popup.targetOf(popup.menuBranch);
      // row 0 is "set background here", row 1 the separator, then the fits
      if (i === 0) { popup.applyBackground(t); return; }
      const fit = Picasso.fitModes[i - 2];
      if (fit) popup.applyFit(t, fit);
    }
    onDismissed: popup.menuBranch = -1
  }


}
