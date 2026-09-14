// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A DROPDOWN THAT IS A PICTURE OF THE SCREEN.
//
// Some settings name a place, and a list of words is the wrong shape for
// one: "Bottom right" has to be read and then turned back into a corner,
// and picking between six of them means comparing six phrases. The screen
// itself, with six cells you click, is the same choice with the reading
// taken out.
//
// It wears CardMenu's card — the same ground, border, radius, arrival and
// shadow — because it opens the same way off the same kind of control, and a
// dropdown that looked like a different species would be a second thing to
// learn. It is not a CardMenu because a menu is a column of rows, and this
// is deliberately not one.
//
//     CornerPicker {
//       open: …; at: Qt.point(x, y)
//       cellRow: 1; cellCol: 2          // which one is lit, -1 for none
//       autoOn: false                   // is the follow row the current pick
//       onPicked: (r, c) => …
//       onPickedAuto: …
//     }

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "../oracle"
import "."

PanelWindow {
  id: root

  // Overlay, for the reason CardMenu is: `aboveWindows` orders against
  // ordinary windows and says nothing about another layer surface, and the
  // panel this opens out of is itself an overlay.
  WlrLayershell.layer: WlrLayer.Overlay

  property bool open: false
  // the card's top-left, in screen coordinates
  property point at: Qt.point(0, 0)

  // which cell is the current choice, -1 -1 for none
  property int cellRow: -1
  property int cellCol: -1

  // the row under the grid: an answer that is not a place
  property bool autoShown: true
  property bool autoOn: false
  property string autoLabel: "Follow bar"

  signal picked(int row, int col)
  signal pickedAuto()
  signal dismissed()

  readonly property int cols: 3
  readonly property int rows: 2
  readonly property int cellW: 46
  readonly property int cellH: 30
  readonly property int gap: 3
  readonly property int pad: 10

  readonly property int gridW: root.cols * root.cellW + (root.cols - 1) * root.gap
  readonly property int gridH: root.rows * root.cellH + (root.rows - 1) * root.gap
  readonly property int cardW: root.gridW + root.pad * 2
  readonly property int cardH: root.gridH + root.pad * 2
    + (root.autoShown ? 1 + 30 : 0)

  // ── the arrival, as every card on this desktop does it ───────────────
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

  implicitWidth: root.cardW + Zenon.menuShadowPad * 2
  implicitHeight: root.cardH + Zenon.menuShadowPad * 2

  margins.left: {
    if (!root.screen) return 0;
    const p = Zenon.menuShadowPad;
    const x = Math.max(p, Math.min(root.at.x, root.screen.width - root.cardW - p));
    return Math.round(x - p);
  }
  margins.top: {
    if (!root.screen) return 0;
    const p = Zenon.menuShadowPad;
    const y = Math.max(p, Math.min(root.at.y, root.screen.height - root.cardH - p));
    return Math.round(y - p);
  }

  ClippingRectangle {
    id: bg
    anchors.fill: parent
    anchors.margins: Zenon.menuShadowPad
    transformOrigin: Item.TopLeft
    scale: Zenon.menuScale(root.shade)
    opacity: root.shade
    color: Zenon.menuBg
    border.color: Zenon.surfaceBorder
    border.width: 1
    radius: Zenon.menuRadius

    // ── the screen ──────────────────────────────────────────────────
    Grid {
      id: grid
      x: root.pad
      y: root.pad
      columns: root.cols
      rows: root.rows
      spacing: root.gap

      Repeater {
        model: root.cols * root.rows

        Rectangle {
          id: cell
          required property int index
          readonly property int r: Math.floor(cell.index / root.cols)
          readonly property int c: cell.index % root.cols
          // Lit only when the AUTO row is not the answer: two things
          // claiming to be the current choice at once is a picker that does
          // not know its own state.
          readonly property bool chosen: !root.autoOn
            && cell.r === root.cellRow && cell.c === root.cellCol

          width: root.cellW
          height: root.cellH
          radius: 3
          color: cell.chosen
            ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.30)
            : (cellMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12)
                                    : Qt.rgba(1, 1, 1, 0.05))
          border.width: 1
          border.color: cell.chosen ? Zenon.cyan
            : (cellMa.containsMouse ? Zenon.keyInk : Zenon.msgBorder)
          Behavior on color {
            ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
          }
          Behavior on border.color {
            ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
          }

          // A toast, drawn where a toast would actually go — so the cell is
          // a picture of the answer rather than a box that means it.
          Rectangle {
            width: parent.width - 14
            height: 6
            radius: 2
            x: 7
            y: cell.r === 0 ? 6 : parent.height - height - 6
            color: cell.chosen ? Zenon.cyan
              : Qt.rgba(Zenon.muted.r, Zenon.muted.g, Zenon.muted.b, 0.7)
            Behavior on color {
              ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
            }
          }

          MouseArea {
            id: cellMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.picked(cell.r, cell.c)
          }
        }
      }
    }

    Rectangle {
      id: rule
      visible: root.autoShown
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      y: root.pad * 2 + root.gridH
      height: 1
      color: Zenon.msgBorder
    }

    // ── the answer that is not a place ──────────────────────────────
    Item {
      visible: root.autoShown
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: rule.bottom
      height: 30

      Rectangle {
        anchors.fill: parent
        anchors.margins: Zenon.menuCardPad
        radius: 3
        color: autoMa.containsMouse ? Zenon.headBg : "transparent"
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.autoLabel
        color: root.autoOn ? Zenon.white : Zenon.muted
        font.family: Zenon.face
        font.weight: Font.Medium
        font.pixelSize: 15
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        visible: root.autoOn
        text: ""
        color: Zenon.cyan
        font.family: Zenon.face
        font.pixelSize: 13
      }

      MouseArea {
        id: autoMa
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.pickedAuto()
      }
    }
  }

  MenuShadow {
    panel: bg
    opacity: root.shade
    transformOrigin: Item.TopLeft
    scale: bg.scale
  }
}
