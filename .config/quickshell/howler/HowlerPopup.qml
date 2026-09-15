// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE BELL'S PANEL — what has already happened. The toasts are the present
// tense and this is the past one, which is why it reads `Howler.history` and
// not the server: a row here may well belong to an application that has since
// exited, and nothing in it can be dismissed because it is already gone.
//
// It opens from the bell in the bar, and it is a morph layer like every other
// panel — see panelX/panelY and contentFade, which are the shared shape of
// one growing out of the pill rather than appearing over it.

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "../morpheus"
import "../oracle"

PanelWindow {
  id: popup
  WlrLayershell.layer: WlrLayer.Overlay

  property bool shown: false
  property bool morphMode: false
  property real morphFade: 1
  property real showFactor: 0
  property bool collapsing: false
  property var statusbar: null

  readonly property real panelX: (popup.collapsing ? 0.985 + 0.015 * popup.showFactor
                        : 0.94 + 0.06 * popup.showFactor)
  readonly property real panelY: (popup.collapsing ? 0.82 + 0.18 * popup.showFactor
                        : 0.90 + 0.10 * popup.showFactor)
  readonly property real contentFade: popup.morphMode
    ? Math.min(popup.morphFade, popup.showFactor) : popup.showFactor

  visible: popup.showFactor > 0.01
  color: "transparent"
  anchors { left: true; right: true; top: true; bottom: true }
  focusable: true
  exclusionMode: ExclusionMode.Ignore

  // Filtering is a view, not a change — nothing is removed from the history
  // by narrowing it, and clearing the filter brings it all back.
  property string appFilter: ""

  readonly property var apps: {
    const seen = ({}); const out = [];
    for (let i = 0; i < Howler.history.length; ++i) {
      const a = String(Howler.history[i].appName || "");
      if (a === "" || seen[a]) continue;
      seen[a] = true; out.push(a);
    }
    return out;
  }

  readonly property var rows: {
    if (popup.appFilter === "") return Howler.history;
    const out = [];
    for (let i = 0; i < Howler.history.length; ++i)
      if (String(Howler.history[i].appName || "") === popup.appFilter)
        out.push(Howler.history[i]);
    return out;
  }
  readonly property int rowH: 64

  // Tall enough for what it holds, then capped — a history of two hundred is
  // a scroll, not a panel the height of the screen. shell.qml asks for this
  // by name to size the morph.
  function calcHeight() {
    const n = Math.max(1, popup.rows.length);
    return Math.min(Oracle.notifMaxHeight + 96,
                    96 + n * popup.rowH + 12);
  }

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

  HyprlandFocusGrab {
    id: grab
    windows: [ popup ]
    active: popup.shown
    onCleared: popup.closePopup()
  }

  // The four the bar, the keybind and the terminal all reach for. Each answers
  // with what it did rather than nothing, so `qs ipc call Howler stat` is
  // useful from a script and not only from a menu.
  IpcHandler {
    target: "Howler"

    function toggle(): void { popup.toggle(); }

    function stat(): string {
      const live = Howler.live ? Howler.live.values.length : 0;
      return live + " showing, " + Howler.history.length + " kept, "
        + Howler.unread + " unread";
    }

    function dismiss(): string {
      const live = Howler.live ? Howler.live.values.length : 0;
      Howler.dismissAll();
      return "dismissed " + live;
    }

    function clear(): string {
      const n = Howler.history.length;
      Howler.dismissAll();
      Howler.clearHistory();
      return "cleared " + n;
    }
  }

  function openPopup() {
    popup.shown = true;
    popup.collapsing = false;
    // Opening the panel IS reading it — the bell goes quiet the moment the
    // list is on screen rather than when a row is clicked, because there is
    // nothing here to click through to.
    Howler.markRead();
    openAnim.restart();
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

  MouseArea {
    anchors.fill: parent
    z: 0
    onClicked: popup.closePopup()
  }

  Item {
    id: panel
    width: Zenon.layerWidth(800)
    height: popup.calcHeight()
    Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
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
      origin.y: Zenon.barTop ? 0 : panel.height
      xScale: popup.panelX
      yScale: popup.panelY
    }

    MouseArea { anchors.fill: parent }

    LayerShadow {
      panel: bgRoot
      cornerRadius: Zenon.pillRadius
      morphed: popup.morphMode
    }

    ClippingRectangle {
      id: bgRoot
      anchors.fill: parent
      // Transparent while morphing: the pill underneath is already drawing
      // the ground, and two grounds compositing read as a darker card that
      // lightens as it settles.
      color: popup.morphMode ? "transparent" : Zenon.layerBg
      border.color: Zenon.surfaceBorder
      border.width: 1
      radius: Zenon.pillRadius

      // ── the head ────────────────────────────────────────────────────
      Item {
        id: head
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 44

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          text: popup.rows.length === 0 ? "Notifications"
              : "Notifications  " + popup.rows.length
          color: Zenon.blue
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: 16
        }

        // ── WHAT THE BAR HOLDS ON THE RIGHT ──────────────────────────
        // A Row rather than two things anchored to the same edge: `clear`
        // comes and goes with the list, and anything anchored beside it
        // would have to know that. A Row skips what is not there and closes
        // the gap itself.
        Row {
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          spacing: 12

          // ── TRACK MUSIC, OR DO NOT ─────────────────────────────────
          // It was a chip in the filter row reading "music tracked" /
          // "music ignored" — a sentence, sitting among the app filters as
          // though it were one of them. It is not a filter: the filters say
          // which of these notifications to show, and this says whether a
          // whole kind of them is ever kept at all. So it belongs on the
          // bar with `clear`, which is the other thing here that changes
          // what the list IS rather than what of it you are looking at.
          //
          // A GLYPH RATHER THAN A SENTENCE, lit when it is on — the same way
          // the bar's own mute reads, and it says it in a quarter the width.
          Rectangle {
            id: musicBtn
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 22
            radius: 11
            color: Howler.trackMusic
              ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.18)
              : (musicHov.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
            border.width: 1
            border.color: Howler.trackMusic ? Zenon.cyan : Zenon.surface
            Behavior on color { ColorAnimation { duration: Zenon.fast } }
            Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

            Text {
              anchors.centerIn: parent
              text: "\uF001"
              color: Howler.trackMusic ? Zenon.cyan
                : (musicHov.hovered ? Zenon.white : Zenon.keyInk)
              font.family: Zenon.face
              font.pixelSize: 12
              Behavior on color { ColorAnimation { duration: Zenon.fast } }
            }

            HoverHandler { id: musicHov }
            TapHandler { onTapped: Howler.toggleMusicTracking() }
          }

          Text {
            id: clearBtn
            anchors.verticalCenter: parent.verticalCenter
            visible: popup.rows.length > 0
            text: "clear"
            color: clearHov.hovered ? Zenon.red : Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 13
            HoverHandler { id: clearHov }
            TapHandler {
              onTapped: { Howler.dismissAll(); Howler.clearHistory(); }
            }
          }
        }

        Rectangle {
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: Zenon.msgBorder
        }
      }

      // Nothing to show is worth saying once, in the middle, rather than
      // leaving an empty card that reads as a panel that failed to load.
      // CENTRED ON THE LIST, not on the card. The head is 44 tall and sits
      // above it, so centring in the whole card pushed this down by half of
      // that — which reads as "nearly centred", the worst kind.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: chips.bottom
        anchors.bottom: parent.bottom
        verticalAlignment: Text.AlignVCenter
        visible: popup.rows.length === 0
        text: "nothing yet"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: 15
      }

      // ── THE CHIP ──────────────────────────────────────────────────
      // One shape for both jobs: a switch that is on or off, and a filter
      // that is chosen or not. `on` is the state, `lit` is the pointer.
      component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        readonly property bool lit: chipHov.hovered
        signal picked()

        width: chipText.implicitWidth + 20
        height: 24
        radius: 12
        color: chip.on ? Qt.rgba(Zenon.sand.r, Zenon.sand.g, Zenon.sand.b, 0.20)
                       : "transparent"
        border.color: chip.on ? Zenon.sand : Zenon.surface
        border.width: 1

        Text {
          id: chipText
          anchors.centerIn: parent
          text: chip.label
          color: chip.on ? Zenon.sand : (chip.lit ? Zenon.white : Zenon.keyInk)
          font.family: Zenon.face
          font.pixelSize: 12
        }

        HoverHandler { id: chipHov }
        TapHandler { onTapped: chip.picked() }
      }

      Flickable {
        id: chips
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        // COLLAPSED WHEN EMPTY. The music toggle used to be in here, so the
        // row always had something in it; with only app filters left, a
        // history from one application has nothing to put here and a 24px
        // strip of nothing above the list is not a filter bar.
        anchors.topMargin: chips.height > 0 ? 10 : 0
        height: chipRow.width > 0 ? 24 : 0
        visible: chips.height > 0
        contentWidth: chipRow.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Row {
          id: chipRow
          spacing: 8

          Chip {
            visible: popup.appFilter !== ""
            label: "all"
            on: false
            onPicked: popup.appFilter = ""
          }

          Repeater {
            model: popup.apps
            delegate: Chip {
              required property var modelData
              label: modelData
              on: popup.appFilter === modelData
              onPicked: popup.appFilter =
                (popup.appFilter === modelData ? "" : modelData)
            }
          }
        }
      }

      ListView {
        id: list
        anchors.top: chips.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: 10
        anchors.bottomMargin: 6
        clip: true
        model: popup.rows
        boundsBehavior: Flickable.StopAtBounds
        spacing: 0

        delegate: Item {
          id: row
          required property var modelData
          required property int index
          width: list.width
          height: popup.rowH

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            radius: Howler.radius
            color: rowHov.hovered ? Zenon.headBg : "transparent"
          }
          HoverHandler { id: rowHov }

          // The row's own icon, at the size oracle asks for — the image the
          // application sent if it survived being written down, and its
          // themed icon if it did not. See howler.js for which is which.
          ClippingRectangle {
            id: shot
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            width: Howler.iconsEnabled ? 40 : 0
            height: 40
            visible: Howler.iconsEnabled
            radius: Howler.iconRadius
            color: "transparent"

            Image {
              anchors.fill: parent
              fillMode: Image.PreserveAspectCrop
              cache: true
              asynchronous: true
              sourceSize.width: 80
              sourceSize.height: 80
              source: {
                const r = row.modelData;
                if (r.image && r.image !== "") return r.image;
                if (r.appIcon && r.appIcon !== "")
                  return r.appIcon.indexOf("/") === 0
                    ? "file://" + r.appIcon : "image://icon/" + r.appIcon;
                return "";
              }
            }
          }

          Text {
            id: appLine
            anchors.left: shot.right
            anchors.leftMargin: Howler.iconsEnabled ? 14 : 20
            anchors.right: stamp.left
            anchors.rightMargin: 10
            anchors.top: parent.top
            anchors.topMargin: 12
            elide: Text.ElideRight
            text: row.modelData.summary !== "" ? row.modelData.summary
                : row.modelData.appName
            color: row.modelData.urgency === 2 ? Zenon.red : Zenon.white
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 14
          }

          Text {
            anchors.left: appLine.left
            anchors.right: appLine.right
            anchors.top: appLine.bottom
            anchors.topMargin: 2
            elide: Text.ElideRight
            visible: text !== ""
            text: row.modelData.body || ""
            textFormat: Howler.markup ? Text.StyledText : Text.PlainText
            color: Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 13
          }

          // Where it came from and when, in the one place the eye is not
          // reading — the right edge, dimmest thing on the row.
          Text {
            id: stamp
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.top: parent.top
            anchors.topMargin: 12
            text: Qt.formatDateTime(new Date(row.modelData.time || 0), "HH:mm")
            color: Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 12
          }

          Text {
            anchors.right: stamp.right
            anchors.top: stamp.bottom
            anchors.topMargin: 2
            text: row.modelData.appName || ""
            color: Zenon.dim
            font.family: Zenon.face
            font.pixelSize: 11
          }

          TapHandler { onTapped: Howler.forget(row.modelData.id) }
        }
      }
    }
  }
}
