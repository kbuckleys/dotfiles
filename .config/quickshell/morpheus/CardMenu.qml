// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE CARD every menu on this desktop is. Icarus wrote this shape three times
// over — a root menu, a session submenu, a trash submenu — and terminus wrote
// it again for its own context menu. All four agree on every number, because
// a menu that measured itself differently from the one beside it was the
// loudest thing saying they were different kinds of object. They are not:
// they are one card, drawn wherever a menu is wanted.
//
// So this is that card, driven by a plain array instead of by any particular
// menu's data:
//
//     CardMenu {
//       open: root.menuOpen
//       at: Qt.point(x, y)            // screen coordinates of the top-left
//       model: [ { text: "Open" }, { isSeparator: true }, { text: "Empty" } ]
//       onChosen: (i) => …
//       onDismissed: root.menuOpen = false
//     }
//
// A row is { text, icon, image, hasChildren, isSeparator, enabled, mark,
// danger, asks }. Everything but `text` is optional. `icon` is a font glyph
// and `image` a URL, for the menus whose icons come from applications rather
// than from the font; `mark` is a tick on the right, for the rows that report
// a current choice rather than perform an action; `danger` reddens a row that
// is armed and waiting to be confirmed; `asks` means the row opens a question
// rather than acting, so it does not flash.
//
// IT DOES NOT GRAB FOCUS ITSELF. A menu is almost never alone — a submenu is
// open beside it, and the layer that opened them both is underneath — and a
// grab per card fights every other grab on screen. The OWNER holds one grab
// over all of them; see `window`, which is what it lists.

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Wayland
import "../oracle"
import "."

PanelWindow {
  id: root

  // ON THE OVERLAY LAYER, and it has to be said out loud.
  //
  // `aboveWindows` is about ordinary application windows; it says nothing
  // about where this sits relative to another LAYER surface. Picasso is an
  // overlay, and a card left on the default layer was drawn underneath it —
  // the rows were genuinely there, faintly legible through the translucent
  // panel on top of them, which is a very confusing way to fail.
  //
  // A menu is the topmost thing on screen by definition, so this is the
  // default rather than something each caller has to remember; within one
  // layer wlroots stacks by creation order, and a card's surface is created
  // when it first opens, which is always after whatever opened it.
  WlrLayershell.layer: WlrLayer.Overlay

  property var model: []
  property bool open: false
  // the card's top-left, in screen coordinates. Clamped to the screen below,
  // so a caller may hand over a position that does not quite fit.
  property point at: Qt.point(0, 0)
  property int cardWidth: 220

  // Chosen and dismissed are deliberately separate: a caller usually wants to
  // put the whole stack of menus away on a choice, and that is its decision
  // rather than this card's.
  signal chosen(int index)
  signal dismissed()

  // What a submenu needs to place itself against a row of this one, and what
  // an owner needs to include this card in its focus grab.
  readonly property alias card: bg
  function rowY(i) {
    let y = 4;
    for (let k = 0; k < i && k < root.model.length; ++k)
      y += root.rowHeight(root.model[k]);
    return y;
  }
  // The same row every menu on this desktop uses, so a card opened on a
  // wallpaper and one opened on the desktop measure identically.
  function rowHeight(m) {
    return (m && m.isSeparator) ? Zenon.menuSepHeight : Zenon.menuRowHeight;
  }

  readonly property int contentH: {
    let h = 8;
    for (let i = 0; i < root.model.length; ++i) h += root.rowHeight(root.model[i]);
    return h;
  }

  // ── the arrival, as terminus' context menu does it ──────────────────
  // 0 closed, 1 open. The opacity and the scale are both functions of this
  // one number, and the card is kept alive through the fade OUT — a menu that
  // vanishes on the frame you click it never shows you which row you clicked.
  property real shade: 0
  onOpenChanged: root.shade = root.open ? 1 : 0
  Behavior on shade {
    NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
  }

  visible: root.open || root.shade > 0.01
  focusable: false
  aboveWindows: true
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  mask: Region { item: bg }
  anchors { top: true; left: true }

  implicitWidth: root.cardWidth + Zenon.menuShadowPad * 2
  implicitHeight: {
    if (!root.screen) return root.contentH + Zenon.menuShadowPad * 2;
    const maxH = root.screen.height - Zenon.menuShadowPad * 2;
    return Math.min(root.contentH, maxH) + Zenon.menuShadowPad * 2;
  }

  // The card is inset inside its own window by the shadow's padding, so the
  // window goes menuShadowPad further up and left than the card does.
  // A SUBMENU FLIPS; A ROOT CARD CLAMPS.
  //
  // Set `flipFrom` to the right edge of the card this one hangs off and it
  // will go there if it fits, to that card's other side if it does not, and
  // only clamp if neither side has room. Clamping alone was fine for a menu
  // opened at a pointer, but a submenu that clamps slides back OVER its own
  // parent and hides the row you opened it from.
  //
  // `hinged` is an explicit BOOLEAN and not a NaN sentinel. A QML `real` does
  // not reliably carry NaN — coerced to 0 it makes isNaN() false, the flip
  // branch runs with an edge of 0, and the card lands against the left of the
  // screen. Every card that did NOT want a hinge was one coercion away from
  // being thrown across the display.
  property bool hinged: false
  property real flipFrom: 0
  property real flipParentLeft: 0

  // HOW CLOSE A CARD MAY COME TO A SCREEN EDGE. Not the shadow's padding:
  // that is 80px of decoration, and reserving it meant a menu standing on the
  // pill was shoved up by whatever the pill did not leave underneath it —
  // 42px of daylight between the menu and the bar it was supposed to sit on.
  // The CARD is what has to stay on screen; the shadow may clip against the
  // edge, which is what a shadow at a screen edge does anyway.
  readonly property int edgeGap: Zenon.padScreen

  readonly property real placedX: {
    if (!root.screen) return 0;
    const pad = root.edgeGap;
    const w = root.cardWidth;
    const limit = root.screen.width - pad;
    if (root.hinged) {
      return Math.round(Zenon.hingeX(root.flipParentLeft,
        root.flipFrom - root.flipParentLeft, w, root.screen.width, pad));
    }
    return Math.round(Math.max(pad, Math.min(root.at.x, limit - w)));
  }

  margins.left: root.placedX - Zenon.menuShadowPad

  // Which side a hinged card landed on.
  readonly property bool onRight: root.hinged
    && root.placedX >= root.flipFrom - 0.5
  margins.top: {
    if (!root.screen) return 0;
    const pad = Zenon.menuShadowPad;
    const h = root.implicitHeight - pad * 2;
    const gap = root.edgeGap;
    const y = Math.max(gap, Math.min(root.at.y, root.screen.height - h - gap));
    return Math.round(y - pad);
  }

  // where the card actually ended up, for a submenu to measure against
  readonly property real cardX: root.margins.left + Zenon.menuShadowPad
  readonly property real cardY: root.margins.top + Zenon.menuShadowPad

  // The flash a row gives when it is clicked, and the reason the card
  // outlives the click: the action runs at the END of it.
  component ChosenFlash: Item {
    id: flash
    anchors.fill: parent
    z: 3
    property var pending: null
    property real chosen: 0
    readonly property bool running: flashAnim.running

    function fire(act) {
      flash.pending = act;
      flashAnim.restart();
    }

    SequentialAnimation {
      id: flashAnim
      NumberAnimation { target: flash; property: "chosen"; to: 1;
                        duration: 60; easing.type: Easing.OutQuad }
      NumberAnimation { target: flash; property: "chosen"; to: 0;
                        duration: 130; easing.type: Easing.InQuad }
      ScriptAction {
        script: {
          const act = flash.pending;
          flash.pending = null;
          if (act) act();
        }
      }
    }

    Rectangle {
      anchors.fill: parent
      visible: flash.chosen > 0
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                     0.55 * flash.chosen)
    }
  }

  ClippingRectangle {
    id: bg
    anchors.fill: parent
    anchors.margins: Zenon.menuShadowPad
    // Grows out of its own top-left corner rather than appearing at full
    // size, so the card unfolds FROM the thing it belongs to.
    transformOrigin: Item.TopLeft
    scale: Zenon.menuScale(root.shade)
    opacity: root.shade
    // Opaque, like terminus' card: a menu sits ON what is behind it, not in
    // it, and a translucent ground let the wallpaper read through the rows.
    color: Zenon.menuBg
    border.color: Zenon.surfaceBorder
    border.width: 1
    radius: Zenon.menuRadius
    // Square where it meets its parent, round everywhere else — so a submenu
    // reads as hinged off the row that opened it rather than as a second card
    // that happens to be touching. Only when there IS a parent: a root card
    // opened at a pointer keeps all four corners.
    topLeftRadius:     root.hinged &&  root.onRight ? 0 : bg.radius
    bottomLeftRadius:  root.hinged &&  root.onRight ? 0 : bg.radius
    topRightRadius:    root.hinged && !root.onRight ? 0 : bg.radius
    bottomRightRadius: root.hinged && !root.onRight ? 0 : bg.radius

    Column {
      anchors.fill: parent
      anchors.margins: Zenon.menuCardPad
      spacing: 0

      Repeater {
        model: root.model

        delegate: Item {
          id: row
          required property var modelData
          required property int index
          width: bg.width - 8
          height: root.rowHeight(row.modelData)

          readonly property bool sep: row.modelData.isSeparator || false
          readonly property bool on: row.modelData.enabled !== false && !row.sep
          // `danger` is for a row that is ARMED — one that has been clicked
          // once and is waiting to be confirmed. Arming is not an event, so it
          // does not flash; the row going red is the reply.
          readonly property color ink: !row.on ? Zenon.muted
            : ((row.modelData.danger || false) ? Zenon.red : Zenon.white)
          // Lit by the pointer, OR because the card it opened is still up.
          // A branch you are standing inside is still the row you came from,
          // and the pointer has by then moved off it onto the child.
          readonly property bool lit: row.on
            && (hover.containsMouse || row.index === root.activeIndex)

          Rectangle {
            anchors.fill: parent
            color: row.lit ? Zenon.headBg : "transparent"
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            height: 1
            color: Zenon.msgBorder
            visible: row.sep
          }

          Item {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            visible: !row.sep

            // A row's mark is EITHER a glyph or an image, never both. Most of
            // this shell's menus draw icons from the font, but a tray menu's
            // come from the application as image URLs, and an application's
            // own icon is not something a font can stand in for.
            Item {
              id: icon
              anchors.verticalCenter: parent.verticalCenter
              width: 16
              height: 16
              visible: icon.glyph !== "" || icon.src !== ""
              readonly property string glyph: row.modelData.icon || ""
              readonly property string src: row.modelData.image || ""

              Text {
                anchors.fill: parent
                visible: icon.glyph !== ""
                text: icon.glyph
                color: row.ink
                font.family: Zenon.face
                font.pixelSize: 15
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
              }

              Image {
                anchors.fill: parent
                visible: icon.glyph === "" && icon.src !== ""
                source: icon.src
                sourceSize.width: 16
                sourceSize.height: 16
                // An application's icon is its own; dimming it for a disabled
                // row is the only thing done to it.
                opacity: row.on ? 1 : 0.45
              }
            }

            Text {
              anchors.left: icon.visible ? icon.right : parent.left
              anchors.leftMargin: icon.visible ? Zenon.menuIconGap : 0
              anchors.right: tail.left
              anchors.rightMargin: tail.width > 0 ? 8 : 0
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignLeft
              text: row.modelData.text || ""
              elide: Text.ElideRight
              color: row.ink
              font.family: Zenon.face
              font.weight: Font.Medium
              font.pixelSize: 16
            }

            // The chevron on a row that has children, or the tick on one that
            // reports a current choice. Never both — a row is a branch or an
            // answer, and one that looked like both would be lying about one.
            Text {
              id: tail
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              // COLLAPSES when it has nothing to show. A row with neither a
              // chevron nor a tick was still reserving 24px for one, so the
              // longest label in a card was elided by a column that was not
              // there — and the only fix available to a caller was to guess a
              // wider card. A plain row now gets that width back.
              width: tail.text === "" ? 0 : 16
              height: 16
              text: (row.modelData.hasChildren || false) ? ""
                : ((row.modelData.mark || false) ? "" : "")
              color: (row.modelData.mark || false) ? Zenon.cyan : Zenon.muted
              font.family: Zenon.face
              font.pixelSize: (row.modelData.mark || false) ? 13 : 15
              verticalAlignment: Text.AlignVCenter
              horizontalAlignment: Text.AlignHCenter
            }
          }

          ChosenFlash { id: flash }

          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            enabled: row.on && !flash.running
            onEntered: root.hovered(row.index)
            onExited: root.unhovered(row.index)
            // A row that ASKS does not flash. The flash is the reply to an
            // action, and a row that opens a question has not done anything
            // yet — the question is the reply. Everything else flashes, and
            // the action runs at the end of it.
            onClicked: (event) => {
              if (event.button === Qt.RightButton) {
                // No flash: a right click on a row is a second question about
                // it, not the row doing its job.
                root.secondary(row.index);
                return;
              }
              if (row.modelData.asks || false) root.chosen(row.index);
              else flash.fire(() => root.chosen(row.index));
            }
          }
        }
      }
    }
  }

  // A row was pointed at. Separate from `chosen` because a branch opens on
  // hover and acts on click, and only the owner knows which rows are branches.
  signal hovered(int index)
  // And pointed away from — which is how an armed row disarms, so it cannot
  // sit primed waiting for a stray click later.
  signal unhovered(int index)

  // A row was RIGHT-clicked. Some rows carry two answers — icarus' trash row
  // opens the folder on a left click and its own card on a right one — and a
  // menu that swallowed the second button made that impossible to express.
  // Owners that have nothing to say to it simply do not connect it.
  signal secondary(int index)

  // The row whose own card is currently open, which stays lit while you are
  // inside that card. The owner knows which row that is; this card cannot,
  // because the child is a separate window. -1 for none. Both icarus' desktop
  // menu and terminus' context menu have always done this; a CardMenu that
  // did not was the one menu on the desktop whose parent row went dark the
  // moment its child appeared.
  property int activeIndex: -1

  MenuShadow {
    panel: bg
    opacity: root.shade
    transformOrigin: Item.TopLeft
    scale: bg.scale
  }
}
