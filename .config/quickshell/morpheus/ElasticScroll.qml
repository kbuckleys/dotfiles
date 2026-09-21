// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── ELASTIC SCROLLING, DROPPED OVER A VIEW ──────────────────────────────
// Lay one of these over a Flickable and its wheel gets Finder's rubber band
// and the smooth notch that goes with it. All the behaviour is in Elastic;
// this is only the part that catches the event.
//
//     ListView { id: rows; ... }
//     ElasticScroll { anchors.fill: rows; view: rows }
//
// DECLARED AFTER the view, and anchored to it rather than parented into it:
// a child of a Flickable is parented to its contentItem and scrolls away
// with the rows, and a handler put there never sees a wheel event at all —
// see the note at the top of Elastic.
//
// SAFE TO LAY OVER ANYTHING. NoButton means it never takes a press, so
// clicks, drags, hovers and rubber-band selection underneath are untouched;
// a wheel it does not want is declined and falls through to the view, which
// goes on scrolling exactly as before.

import QtQuick
import "."

MouseArea {
  id: shell

  // The view to scroll. When one overlay serves several — a split pane, a
  // miller column set — leave this null and give `pick` instead.
  property var view: null
  // function(x, y) -> Flickable, in this item's coordinates.
  property var pick: null

  // ── IT PINS ITSELF TO THE VIEWPORT ────────────────────────────────────
  // Declared INSIDE the view, which is the safe place to put it: one line
  // after the opening brace, with no need to find the matching close or to
  // guess the nesting of whatever the view is sitting in.
  //
  // A child of a plain Flickable is parented to its contentItem, so
  // `parent` is the whole scrolled content: it travels with the rows, and
  // cancelling that with contentX/contentY is what keeps this over the
  // visible part.
  //
  // ── BUT ONLY IF THAT IS WHERE WE LANDED ───────────────────────────────
  // A child declared inside a LIST VIEW is parented to the view itself,
  // not to its contentItem — measured, not assumed: with the view's own
  // screen y fixed at 144, this item's climbed 166 → 549 as contentY grew.
  // It was already in viewport coordinates, and the offset pushed it DOWN
  // out of the viewport by exactly the distance scrolled.
  //
  // The effect is a scroll that dies the further you go: the overlay slides
  // off the pointer, the wheel stops landing on it, and what is left is the
  // view's own handling. It needs enough content to push the overlay past
  // the pointer before it shows, which is why it looked like a property of
  // tall previews — archives first, then any long folder.
  //
  // So the offset is applied only when we are genuinely in the content.
  // A caller that would rather lay it over the view as a SIBLING sets
  // anchors instead, and these bindings are simply replaced.
  readonly property bool inContent:
    !!shell.view && shell.parent === shell.view.contentItem
  x: shell.inContent ? shell.view.contentX : 0
  y: shell.inContent ? shell.view.contentY : 0
  width: shell.view ? shell.view.width : 0
  height: shell.view ? shell.view.height : 0

  // First refusal on the event, for a module that wants the wheel for
  // something else: ctrl+wheel zooming, a horizontal strip, a slider.
  // function(wheelEvent) -> bool, true when it has taken it.
  property var intercept: null

  // How far one notch travels. 0 lets Elastic decide from the view's own
  // height, which is the right answer for anything without a row grid.
  property real step: 0

  readonly property Elastic elastic: Elastic {}

  acceptedButtons: Qt.NoButton
  // Not hoverEnabled: hover belongs to whatever is underneath, and taking
  // it here is how an overlay starts swallowing things it was promised not
  // to.
  hoverEnabled: false
  z: 6

  onWheel: (w) => {
    if (shell.intercept && shell.intercept(w)) { w.accepted = true; return; }
    const v = shell.pick ? shell.pick(w.x, w.y) : shell.view;
    if (!v) { w.accepted = false; return; }
    const notches = w.angleDelta.y / 120;
    if (notches === 0) { w.accepted = false; return; }
    w.accepted = true;
    const d = shell.step > 0 ? shell.step : shell.elastic.notchFor(v);
    shell.elastic.scroll(v, -notches * d);
  }
}
