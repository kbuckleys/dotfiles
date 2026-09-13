// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A scrollbar for any Flickable — a ListView, a GridView, a plain Flickable.
//
// Every list in this shell was a keyboard instrument: you filtered it down
// until the thing you wanted was on screen, and the scroll position was
// something the selection dragged along behind it. Nothing needed to SAY how
// far down a list went, because you were never meant to be looking for the
// bottom of one by hand.
//
// The panels that are driven by a pointer are a different proposition. A list
// you scroll with a wheel and no scrollbar has two problems at once: there is
// nothing saying more exists below the fold, and there is nothing to grab when
// the wheel is the slow way to get somewhere.
//
// Used as:
//
//     Scrollbar { flick: list; anchors.right: parent.right
//                 anchors.top: parent.top; anchors.bottom: parent.bottom }
//
// It draws nothing when everything already fits, so a short section is not
// given a full-height bar saying "you are at the top of all of it".

import QtQuick
import "."

Item {
  id: root

  // the ListView, GridView or Flickable this reports on
  property Flickable flick: null

  // What is PAINTED, and what can be GRABBED, are two different numbers.
  //
  // They used to be one: a 10px-wide item drawing a 4px line, with the mouse
  // area grown sideways by negative margins to about the same 10. Aiming at
  // that meant hitting a ten-pixel column hard against the panel's edge, in
  // order to catch a line four pixels wide — and missing it does nothing at
  // all, which is indistinguishable from the thing being broken.
  //
  // So the item is as wide as the target, the bar is drawn against its right
  // edge, and the space to the left of the bar is grabbable too. No negative
  // margins anywhere: the hit area is simply the item.
  property int thickness: 12
  property int grabPad: 14
  // how much of the bar the thumb is: never less than this, so a very long
  // list still leaves something big enough to grab
  property int minThumb: 28

  readonly property real overflow:
    root.flick ? Math.max(0, root.flick.contentHeight - root.flick.height) : 0
  readonly property bool scrollable: root.overflow > 1

  width: root.thickness + root.grabPad
  visible: root.scrollable
  // A scrollbar on a list that fits is furniture pretending to be
  // information. It is not merely hidden, it takes no width either — the
  // list beside it gets those pixels back.
  opacity: root.scrollable ? 1 : 0
  Behavior on opacity {
    NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
  }

  // 0..1 — how far down the content is
  readonly property real progress:
    root.overflow > 0 ? Math.max(0, Math.min(1, root.flick.contentY / root.overflow)) : 0

  readonly property real thumbH: {
    if (!root.scrollable) return 0;
    const frac = root.flick.height / root.flick.contentHeight;
    return Math.max(root.minThumb, Math.round(root.height * frac));
  }
  readonly property real travel: Math.max(0, root.height - root.thumbH)

  // True while the thumb is being dragged. The owner needs to know: on a
  // layer-shell surface with an input mask, a drag that wanders outside the
  // mask is input "outside the window" as far as the compositor is
  // concerned, and it takes the focus grab away mid-gesture. See
  // OraclePopup.capturing.
  readonly property bool dragging: ma.dragging
  // where the thumb's top currently is, for anything that needs to reason
  // about the bar from outside it — the interaction tests do
  readonly property real thumbY: Math.round(root.travel * root.progress)

  // the groove, which is what says there is a length to this at all
  Rectangle {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: 4
    anchors.bottomMargin: 4
    anchors.rightMargin: 3
    width: root.thickness - 6
    radius: width / 2
    // it lights up under the pointer, so it says it is a control before you
    // commit to grabbing it
    color: (ma.containsMouse || ma.dragging)
      ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05)
    Behavior on color {
      ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
    }
  }

  Rectangle {
    id: thumb
    x: root.width - root.thickness + 3
    // POSITION FROM THE CONTENT, never the other way round. The drag below
    // writes contentY and lets this follow: writing y here would have
    // replaced the binding with a number the first time it was dragged, and
    // the bar would then have stopped tracking the wheel for good.
    y: root.thumbY
    width: root.thickness - 6
    height: root.thumbH
    radius: width / 2
    color: ma.dragging ? Zenon.cyan
      : Qt.rgba(Zenon.muted.r, Zenon.muted.g, Zenon.muted.b, 0.85)
    Behavior on color {
      ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
    }
  }

  // ── ONE HANDLER FOR THE WHOLE BAR ─────────────────────────────────────
  // It used to be two: a MouseArea on the thumb for dragging, and a second
  // one behind it at z -1 for paging the groove. Nothing about that
  // arrangement worked — the thumb's area was anchored to a 4px-wide
  // rectangle and grown sideways by negative margins, the groove's sat at a
  // negative z under a sibling that painted over it, and between them they
  // left a bar that could be neither dragged nor clicked.
  //
  // There is no reason for two. The bar knows where its own thumb is, so one
  // area over the whole strip can tell a press on the thumb from a press off
  // it — and a press off it does the thing every modern scrollbar does:
  // jumps there AND carries on as a drag, so a click that missed by a few
  // pixels is not a wasted click.
  MouseArea {
    id: ma
    // THE WHOLE ITEM. No negative margins — the item was made wide enough to
    // be the target, so the target is the item.
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.scrollable
    // Once this has the press it keeps it. Without it a drag that wandered
    // sideways out of the strip could be taken by whatever it wandered over.
    preventStealing: true

    // WHERE THE PRESS WAS, and what the content was showing then. The drag
    // is a DELTA from those two, never a position derived from where the
    // thumb currently is.
    //
    // Reading thumb.y inside the move handler — which is what this did — is
    // self-referential: thumb.y is bound to contentY, which the handler is
    // itself setting, so every event computes its answer from the answer to
    // the previous one. It tracks correctly only while every single event
    // arrives. Drop one and the error is kept forever, which is the thumb
    // sliding out from under the cursor.
    //
    // From a fixed anchor it is exact and self-correcting: move the pointer
    // the length of the travel and the list moves exactly its overflow, so
    // the thumb stays under the hotspot wherever the pointer goes.
    property real pressY: 0
    property real startContent: 0
    property bool dragging: false

    function contentForTop(top) {
      if (root.travel <= 0) return 0;
      return Math.max(0, Math.min(root.overflow,
        (top / root.travel) * root.overflow));
    }

    onPressed: (m) => {
      const top = thumb.y;
      if (m.y < top || m.y > top + root.thumbH) {
        // landed on the groove: take the thumb there first, centred under
        // the pointer, and drag on from where it ended up
        root.flick.contentY = ma.contentForTop(m.y - root.thumbH / 2);
      }
      ma.pressY = m.y;
      ma.startContent = root.flick.contentY;
      ma.dragging = true;
    }

    onPositionChanged: (m) => {
      if (!ma.dragging || root.travel <= 0) return;
      const dy = m.y - ma.pressY;
      root.flick.contentY = Math.max(0, Math.min(root.overflow,
        ma.startContent + (dy / root.travel) * root.overflow));
    }

    onReleased: ma.dragging = false
    onCanceled: ma.dragging = false

    // the wheel works over the bar too, because a pointer that is already
    // there should not have to move back onto the list to nudge it
    onWheel: (w) => {
      const step = root.flick.height * 0.25;
      root.flick.contentY = Math.max(0, Math.min(root.overflow,
        root.flick.contentY + (w.angleDelta.y > 0 ? -step : step)));
      w.accepted = true;
    }
  }

}
