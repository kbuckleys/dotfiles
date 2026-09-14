// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE VOLUME OSD — the one thing howler shows that nobody sent it.
//
// IT IS THE BAR'S VOLUME TOOLTIP, MOVED. Same fill, same border, same radius,
// same 20/10 padding and the same bold sixteen — see morpheus/Tooltip, whose
// metrics these are copied from rather than approximated. The tooltip itself
// is a CursorAnchor and follows the pointer, which is the one thing an OSD
// must not do; everything else about it is right, so everything else about it
// is here.
//
// It rides in the toast stack at the end nearest the bar, so a volume change
// and a notification arrive in the same place rather than in two overlays
// that drift apart by a few pixels.
//
// IT DOES NOT SHOW ON THE FIRST BINDING. Volume.level arrives once when
// Pipewire is first read, and an OSD that took that for a change would greet
// every login with a volume bar nobody asked for.

import QtQuick
import "../morpheus"

Item {
  id: osd

  property bool atTop: false
  property bool active: false
  // Where it comes in from, handed down by the stack so the OSD and a toast
  // travel the same way for the same corner.
  property real slideX: 0
  property real slideY: 0

  implicitWidth: card.implicitWidth
  // COLLAPSED ON A CURVE, not on the frame `active` goes false. Cutting the
  // height to zero destroyed the card before its fade and its slide had a
  // frame to run in — the open animated and the close did not exist. The
  // height now travels with them, and the item stays alive until all three
  // have finished.
  implicitHeight: osd.active ? card.implicitHeight : 0
  Behavior on implicitHeight {
    NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
  }
  visible: osd.implicitHeight > 0.5

  // The first value is the state of the machine, not news about it.
  property bool primed: false

  Connections {
    target: Volume
    function onLevelChanged() { osd.bump(); }
    function onMutedChanged() { osd.bump(); }
  }

  function bump() {
    if (!Volume.ready) return;
    if (!osd.primed) { osd.primed = true; return; }
    osd.active = true;
    hold.restart();
  }

  Timer {
    id: hold
    interval: 1400
    onTriggered: osd.active = false
  }

  Rectangle {
    id: card
    implicitWidth: content.implicitWidth + 56
    implicitHeight: content.height + 28
    // NOT CENTRED IN ITS PARENT, and this was the whole of "the OSD has no
    // background": the card's implicit size is measured from `content`, so
    // anchoring `content` to the card is a size that depends on itself. QML
    // breaks that loop by calling it zero — a rectangle of no size paints no
    // fill and no border, while the Row inside it, which is centred on that
    // zero, carries on drawing. The meter and the text with nothing behind
    // them was a binding loop, not a missing colour.
    x: 0
    y: 0

    // A TOAST'S SKIN. Same ground, same border, same corners, same
    // transparency — it shares their stack, so it is one of them.
    color: Zenon.panelBgDeep
    border.color: Zenon.surface
    border.width: Howler.borderSize
    radius: Howler.radius * 2

    opacity: osd.active ? 1 : 0
    Behavior on opacity {
      NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
    }

    // COPIED FROM morpheus/NowPlayingPanel's volume row, verbatim — the
    // horizontal green meter, its glyph and its percentage. Not approximated
    // from the bar's vertical six-notch version, which is a different widget
    // for a different place.
    // THE SAME ARRIVAL A TOAST MAKES — it shares their stack, so it shares
    // their motion rather than being the one thing in the corner that simply
    // appears.
    transform: Translate {
      id: osdSlide
      x: osd.active ? 0 : osd.slideX
      y: osd.active ? 0 : osd.slideY
      Behavior on x {
        NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase }
      }
      Behavior on y {
        NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase }
      }
    }

    Row {
      id: content
      x: 28
      y: 14
      // AN EXPLICIT HEIGHT, for the same reason the card is not centred in.
      // Its children anchor to this Row's verticalCenter, and a Row measures
      // itself FROM its children — so leaving the height implicit made the
      // children's position depend on a height that depended on them, and
      // that loop resolved to zero all the way up to the card.
      height: 28
      spacing: 10

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Volume.muted ? "" : ""
        color: Volume.muted ? Zenon.red : Zenon.green
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: 18
      }

      Meter {
        anchors.verticalCenter: parent.verticalCenter
        vertical: false
        segCount: 14
        thickness: 9
        segLength: 6
        segGap: 2
        value: Volume.muted ? 0 : Volume.level
        accent: Volume.muted ? Zenon.red : Zenon.green
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: 52
        horizontalAlignment: Text.AlignRight
        text: Volume.muted ? "muted" : Volume.percent + "%"
        color: Volume.muted ? Zenon.red : Zenon.white
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: 17
      }
    }
  }
}
