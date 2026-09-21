// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── THE SCROLL RULE ─────────────────────────────────────────────────────
// Finder's rubber band, and the smooth wheel step that goes with it, in one
// place. Every scrollable surface in this shell should reach it through
// here or through ElasticScroll, which wraps it; a second copy of these
// numbers anywhere is the bug this file exists to prevent.
//
// WHY IT IS NOT JUST A boundsBehavior. Flickable overshoots for DRAG and
// FLICK gestures. A wheel event is neither — QQuickFlickable moves contentY
// and clamps it — so on a mouse there is no rubber band at any setting.
// The clamp is where the band lives instead: whatever it throws away is
// exactly how far past the edge the wheel asked to go.
//
// WHY IT IS NOT A WheelHandler. One declared inside a Flickable never fires
// at all: Flickable's default property parents non-Item children to
// contentItem as a plain QObject, so the handler is registered on nothing.
// Verified with a logging handler inside the very view whose wheel events
// were visibly scrolling it. The wheel has to be caught by a MouseArea laid
// over the view — see ElasticScroll.

import QtQuick
import "."

QtObject {
  id: elastic

  // How far one notch travels when the caller does not say. A tenth of the
  // view, floored so a short list still moves usefully.
  function notchFor(v) {
    return Math.max(48, Math.round(v.height * 0.10));
  }

  // ── APPLE'S RUBBER BAND, EXACTLY ──────────────────────────────────────
  //     f(x, d, c) = (x * d * c) / (d + c * x)        c = 0.55
  // x is how far past the edge the wheel has asked to go and d is the
  // height of what is being scrolled, so the first pixels come easily and
  // the hundredth costs almost nothing.
  readonly property real c: 0.55

  function pull(x, d) {
    return (x * d * elastic.c) / (d + elastic.c * x);
  }

  // ── HOW FAR IT MAY GO ─────────────────────────────────────────────────
  // The curve self-limits at d/c, which is nearly twice the viewport. That
  // is right for a finger, which runs out of screen, and wrong for a wheel,
  // which does not: spinning at the edge would wind the content most of the
  // way off and then take the whole settle to bring it back, so the reply
  // to "there is no more" got slower the harder you asked.
  //
  // A tenth of the view says the same thing and lets go at once. Inverting
  // f gives the raw distance that lands exactly on it, so the clamp applies
  // to what the wheel ASKED for — clamp the drawn value instead and `raw`
  // climbs invisibly, and the band then ignores the first several notches
  // of the way back.
  function maxRaw(d) {
    const b = d * 0.10;
    return (b * d) / (elastic.c * (d - b));
  }

  // ── STATE ─────────────────────────────────────────────────────────────
  // One set, not one per view: a wheel belongs to one surface at a time and
  // there is no gesture that can band two at once.
  property var band: null            // the view currently stretched
  property real raw: 0               // what the wheel has asked for, past the edge
  property bool atTop: true

  // ── AN EDGE ANSWERS ONCE ──────────────────────────────────────────────
  // Capping the stretch stopped it growing without bound, and left a worse
  // thing behind: at the end of a list every further notch still began a
  // fresh stretch-and-settle. Measured off a capture of the archive
  // viewer, the settle reads as -16, -12, -10, -6, -3, -1 — 48px back, the
  // cap exactly — and then again, and again, for as long as the wheel
  // turns. Scrolling forward was perfectly steady right up to that point,
  // so what felt like momentum draining away was the band pushing back.
  //
  // A rubber band is a reply to "there is no more", and a reply is worth
  // giving once. Spent after it settles, and only a notch travelling back
  // INTO the content clears it — so the next time you arrive at that edge
  // you get the bounce again, and leaning on the wheel there is quiet.
  property bool spent: false

  // ── THE ONE ENTRY POINT ───────────────────────────────────────────────
  // Every notch, banded or not, goes through here.
  function scroll(v, delta) {
    if (!v) return;
    const most = Math.max(0, v.contentHeight - v.height);
    const from = (anim.running && anim.target === v) ? anim.to : v.contentY;

    // Any movement back into the content means the edge is behind us: the
    // next arrival at one is a new question and deserves an answer.
    if ((elastic.atTop && delta > 0) || (!elastic.atTop && delta < 0))
      elastic.spent = false;

    // ALREADY BANDED means the whole notch belongs to the band. Working it
    // out from `from` would measure it against a contentY the band has
    // already pushed out of bounds and count the stretch twice.
    const banded = elastic.band === v && elastic.raw > 0;
    let to, lost;
    if (banded) {
      to = elastic.atTop ? 0 : most;
      lost = delta;
    } else {
      const asked = from + delta;
      to = Math.max(0, Math.min(most, asked));
      lost = asked - to;
    }

    // ── IT TRAVELS THERE, IT DOES NOT ARRIVE ────────────────────────────
    // The banded position is just another target for the same animation.
    // Writing contentY outright instead — while ordinary scrolling went
    // through the animation — made the notch that reached the edge stop
    // mid-flight and teleport to the stretch: a scroll, a hitch, then a
    // band. That gap is what reads as snappy, and it is not the settle's
    // fault.
    let want = to;
    if (most > 0 && (lost !== 0 || banded)) {
      const b = elastic.take(v, lost, to);
      if (b === b) want = b;          // NaN when the band declined it
    }

    if (want === v.contentY && !anim.running) return;
    anim.stop();
    anim.target = v;
    anim.to = want;
    anim.start();
  }

  // `lost` is the distance the clamp discarded — negative past the top,
  // positive past the bottom. Returns the contentY the band wants, or NaN
  // when it has nothing to say and the plain clamped target should stand.
  function take(v, lost, clamped) {
    const banded = elastic.band === v && elastic.raw > 0;
    if (lost === 0 && !banded) return NaN;
    // Already answered at this edge — see `spent`.
    if (elastic.spent && !banded) return NaN;
    // A different surface under the wheel: let the old one go rather than
    // dragging its band along.
    if (elastic.band && elastic.band !== v) elastic.letGo();

    settle.stop();
    if (elastic.band !== v) {
      elastic.band = v;
      elastic.raw = 0;
      // Which edge, recorded once: contentY is about to be driven past it
      // and can no longer be asked.
      elastic.atTop = clamped <= 0.5;
    }

    // Past the top the clamp loses a NEGATIVE amount, and the band there
    // pulls the content down — so the sign is folded into "how far out",
    // which is always positive.
    const next = elastic.raw + (elastic.atTop ? -lost : lost);
    if (next <= 0) { elastic.letGo(); return NaN; }

    const d = Math.max(1, v.height);
    elastic.raw = Math.min(next, elastic.maxRaw(d));
    idle.restart();
    const b = elastic.pull(elastic.raw, d);
    const bound = elastic.atTop ? 0 : Math.max(0, v.contentHeight - v.height);
    return bound + (elastic.atTop ? -b : b);
  }

  function letGo() {
    const v = elastic.band;
    elastic.raw = 0;
    elastic.band = null;
    idle.stop();
    // Exactly on the bound, and only when nothing is still animating it:
    // settle calls this on the frame it finishes, and writing contentY out
    // from under an animation that is winding down ends the scroll with a
    // twitch.
    if (v && !settle.running && !anim.running) {
      const most = Math.max(0, v.contentHeight - v.height);
      v.contentY = Math.max(0, Math.min(most, v.contentY));
    }
  }

  // ── THE WHEEL MOVES RATHER THAN JUMPS ─────────────────────────────────
  // Setting contentY outright covers the distance instantly, and at a tenth
  // of a view per notch that reads as a teleport: nothing travels, so there
  // is nothing for the eye to follow and you arrive having lost your place.
  //
  // ONE animation, retargeted, rather than one per view — two racing on the
  // same property is how a list ends up stuttering. Consecutive notches
  // accumulate from where it is GOING, not from where it is, or spinning
  // the wheel restarts the journey every notch and covers a fraction of
  // what was asked for.
  readonly property Timer _idle: Timer {
    id: idle
    // Just longer than the stretch itself, so the band reaches full
    // stretch before it starts coming back rather than being cut off
    // halfway and reversed. A wheel has no "finger lifted"; a short
    // silence is the end of the gesture.
    interval: 150
    onTriggered: {
      const v = elastic.band;
      if (!v) return;
      anim.stop();
      settle.target = v;
      settle.to = elastic.atTop ? 0 : Math.max(0, v.contentHeight - v.height);
      settle.restart();
    }
  }

  readonly property NumberAnimation _anim: NumberAnimation {
    id: anim
    property: "contentY"
    duration: 130
    easing.type: Easing.OutCubic
  }

  // The settle, on contentY directly — the same property the stretch was
  // animated on, so letting go continues that motion rather than starting a
  // second one against it. See Zenon.elastic for the duration, and why the
  // curve has to spend it rather than front-load it.
  readonly property NumberAnimation _settle: NumberAnimation {
    id: settle
    property: "contentY"
    duration: Zenon.elastic
    easing.type: Easing.OutCubic
    onFinished: {
      // The edge has now given its answer. Leaning on the wheel from here
      // does nothing until the content has been scrolled back into.
      elastic.spent = true;
      elastic.letGo();
    }
  }
}
