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
    NumberAnimation { duration: Howler.closeMs; easing.type: Zenon.ease }
  }
  visible: osd.implicitHeight > 0.5

  // ── THE FIRST VALUE IS THE STATE OF THE MACHINE, NOT NEWS ──────────────
  // Suppressing it by counting signals did not work, and could not: `ready`,
  // `level` and `muted` are three separate bindings off one audio object, so
  // when the sink appears `levelChanged` can arrive while `ready` is still
  // false. That bump returned at the readiness check WITHOUT priming, and the
  // flag was still down when the first real change came — which is the change
  // that got eaten instead. It also failed the other way: a sink whose volume
  // happens to match the null-state defaults emits nothing at all at startup,
  // so nothing primed and the same thing happened.
  //
  // So the guard is the VALUE rather than the count. What was on screen when
  // the sink was first understood is remembered, and a bump that does not
  // differ from it is not news no matter how many signals carried it.
  // AND THE VALUE ALONE IS NOT ENOUGH EITHER. PwObjectTracker only starts
  // streaming a sink's properties once it is being tracked, so the real
  // volume can arrive a moment AFTER `ready` — priming on readiness records
  // the placeholder, and the true value then reads as a change. Which is the
  // OSD that greets a cold start.
  //
  // So readiness opens a settling window instead of arming anything. Whatever
  // pipewire says during it is the state of the machine; the first thing
  // after it is news. Re-armed from scratch if the sink goes away and comes
  // back, because that is a cold start for this purpose too.
  property bool armed: false
  property real seenLevel: 0
  property bool seenMuted: false

  function prime() {
    if (!Volume.ready) return;
    osd.seenLevel = Volume.level;
    osd.seenMuted = Volume.muted;
  }

  Timer {
    id: settle
    interval: 1500
    onTriggered: {
      osd.prime();
      osd.armed = true;
    }
  }

  Connections {
    target: Volume
    function onReadyChanged() {
      osd.armed = false;
      if (Volume.ready) settle.restart();
      else settle.stop();
    }
    // INSIDE THE WINDOW IT IS STATE, AFTER IT, NEWS. Recording and comparing
    // are the two halves of the same fact and only one of them can be true of
    // any given signal — doing both would record the value and then find it
    // unchanged, which is an OSD that never fires at all.
    function onLevelChanged() { osd.armed ? osd.bump() : osd.prime(); }
    function onMutedChanged() { osd.armed ? osd.bump() : osd.prime(); }
  }

  // Belt as well as braces: a signal that carries no change is not news even
  // once the window has closed, and pipewire does emit those.
  function bump() {
    if (!Volume.ready || !osd.armed) return;
    if (Volume.level === osd.seenLevel && Volume.muted === osd.seenMuted)
      return;
    osd.seenLevel = Volume.level;
    osd.seenMuted = Volume.muted;
    osd.active = true;
    hold.restart();
  }

  Component.onCompleted: if (Volume.ready) settle.restart()

  Timer {
    id: hold
    interval: 1400
    onTriggered: osd.active = false
  }

  // It shares the toasts' stack and their skin, so it casts what they
  // cast. The stack's surface is the whole output — see HowlerToasts —
  // so there is already room around it for this to fall into.
  MenuShadow {
    panel: card
    cornerRadius: Howler.radius
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
    // THE TOAST'S OWN SKIN, which is the point of the OSD looking like
    // one — so it follows the same two settings rather than keeping a
    // copy of what they used to say.
    color: Howler.bg
    border.color: Howler.borderInk
    border.width: Howler.borderSize
    radius: Howler.radius * 2

    opacity: osd.active ? 1 : 0
    Behavior on opacity {
      NumberAnimation { duration: Howler.closeMs; easing.type: Zenon.ease }
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
        NumberAnimation { duration: Howler.openMs; easing.type: Zenon.travelEase }
      }
      Behavior on y {
        NumberAnimation { duration: Howler.openMs; easing.type: Zenon.travelEase }
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

      // THE SPEAKER, AND THE MUTE. Both literals were empty — lost when
      // howler was rebuilt — so this drew nothing at all and the only thing
      // saying "muted" was the word at the far end. Written as escapes rather
      // than as the characters themselves, which is how they went missing.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Volume.muted ? "\uF466" : "\uF028"
        color: Volume.muted ? Zenon.red : Zenon.green
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: 18
      }

      // ONE OR THE OTHER, never both — the rule the bar's own meter follows,
      // written down in PulseAudioModule. Muted is not a quiet volume, it is
      // the absence of one, so the glyph says so and the gauge goes away
      // rather than standing beside it drawn empty and red.
      Meter {
        anchors.verticalCenter: parent.verticalCenter
        visible: !Volume.muted
        vertical: false
        segCount: 14
        thickness: 9
        segLength: 6
        segGap: 2
        value: Volume.level
        accent: Zenon.green
      }

      // And the figure goes with it: "muted" was the word doing the glyph's
      // job, which is why there was no glyph to see.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !Volume.muted
        width: 52
        horizontalAlignment: Text.AlignRight
        text: Volume.percent + "%"
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: 17
      }
    }
  }
}
