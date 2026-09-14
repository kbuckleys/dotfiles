// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE STACK — what is happening now. One toast per live notification, newest
// nearest the bar, capped at maxVisible; the volume OSD rides at the same end
// so the two never drift apart.
//
// MASKED TO THE STACK ITSELF. The window covers the screen so a toast can sit
// anywhere in it, and a covering window that took input would swallow every
// click on the desktop underneath. The mask is the column, so the only
// pixels this surface claims are the ones it is drawing on.

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../morpheus"
import "../oracle"

PanelWindow {
  id: toasts
  WlrLayershell.layer: WlrLayer.Overlay

  property var statusbar: null

  color: "transparent"
  focusable: false
  exclusionMode: ExclusionMode.Ignore
  anchors { left: true; right: true; top: true; bottom: true }
  mask: Region { item: column }

  // WHICH CORNER, not which end — see Oracle.notifCorner. "auto" follows the
  // bar, because a stack at the far end of the screen from the thing that
  // counts them reads as a different application's.
  readonly property string corner: Oracle.notifCorner(Zenon.barTop)
  readonly property bool atTop: toasts.corner.indexOf("top") === 0
  readonly property string side: {
    const c = toasts.corner;
    if (c.indexOf("-left") > 0) return "left";
    if (c.indexOf("-right") > 0) return "right";
    return "center";
  }

  // Only as many as asked for, newest first — the server hands them over
  // oldest first, and the one that just arrived is the one worth reading.
  // THE SERVER'S OWN MODEL, not a copy of it. Howler.trim keeps it inside
  // maxVisible, so there is nothing left for the view to filter — and a view
  // over a real model gets told what was added and what went, which is the
  // whole of what the transitions below need.
  readonly property var rows: Oracle.showNotifications ? Howler.live : null

  // One lane, wide enough for the widest toast, with each card centred in
  // it. The stack has to be a single item for the transitions below to have
  // anything to displace.
  // ── WHICH WAY A TOAST COMES IN ──────────────────────────────────────
  // From the edge it is pinned to, always: a stack in a corner slides in
  // sideways from that corner, and a centred one slides along the axis it
  // hangs from — down from the top, up from the bottom. Nothing ever travels
  // across the screen to reach its place.
  readonly property bool sideways: toasts.side !== "center"
  readonly property real slideX: toasts.side === "right" ? 64
                               : toasts.side === "left" ? -64 : 0
  readonly property real slideY: toasts.sideways ? 0 : (toasts.atTop ? -36 : 36)

  readonly property real stackW: Math.min(Howler.maxWidth,
    Howler.width + Howler.iconSize + Howler.padding * 4 + Howler.borderSize * 2)

  Column {
    id: column
    spacing: Howler.margin
    // The OSD is declared first or last depending on which way the stack
    // grows, so it is always the item nearest the bar.
    // PLACED BY COORDINATE, NOT BY ANCHOR, and that is a bug fix rather
    // than a preference. Naming left, right and horizontalCenter in one
    // anchors block invalidates the whole group — Qt says so and qmllint
    // warns about it — even when the two that do not apply are `undefined`.
    // The group was dropped, the Column fell back to the origin, and every
    // corner setting put the stack in the top left: measured at x=16 y=26
    // for all six values while `atTop` and `side` were computed correctly
    // the whole time.
    readonly property real lift: Howler.lift
      + Zenon.edgeLift(false, toasts.screen, toasts.statusbar)

    x: toasts.side === "left" ? 16
     : toasts.side === "right" ? toasts.width - column.width - 16
     : (toasts.width - column.width) / 2
    y: toasts.atTop ? column.lift : toasts.height - column.height - column.lift

    HowlerOsd {
      id: osd
      atTop: toasts.atTop
      slideX: toasts.slideX
      slideY: toasts.slideY
      visible: toasts.atTop && osd.implicitHeight > 0
      height: toasts.atTop ? implicitHeight : 0
    }

    // A VIEW, NOT A REPEATER, and only for the animations. A Repeater adds
    // and drops items with no notion of before and after: a toast appeared
    // fully formed and the ones under it jumped up the instant one expired.
    // A ListView has add, remove and displaced — so a toast arrives, leaves,
    // and the stack closes the gap behind it.
    ListView {
      id: stack
      width: toasts.stackW
      height: Math.min(contentHeight, toasts.screen ? toasts.screen.height - 120 : 800)
      spacing: Howler.margin
      interactive: false
      model: toasts.rows
      // Newest nearest the bar, whichever edge that is.
      verticalLayoutDirection: toasts.atTop
        ? ListView.TopToBottom : ListView.BottomToTop


      // GOING IS A FADE AND NOTHING ELSE. A toast that slid out would be
      // travelling at the moment the stack closes the gap behind it, and two
      // movements in opposite directions at once is the thing that reads as
      // broken rather than as motion.
      remove: Transition {
        NumberAnimation { property: "opacity"; to: 0
                          duration: Zenon.fast; easing.type: Easing.InQuad }
      }

      // The gap closing is the part that was missing — without it the stack
      // teleports every time the oldest one goes.
      displaced: Transition {
        NumberAnimation { properties: "x,y"
                          duration: Zenon.normal; easing.type: Zenon.travelEase }
      }

      // AN ITEM, WITH THE CARD INSIDE IT. The card clips — its content has
      // to stay inside its rounded corners — and a card that clips clips its
      // own glow away. So the delegate is a plain box the size of the card,
      // the card fills it, and the light is a sibling underneath that is
      // free to spill past the edge. Nothing above this clips either: the
      // view does not, the column does not, and the window's mask only
      // decides which pixels take a click.
      delegate: Item {
        id: toast
        required property var modelData

        readonly property bool critical: !!toast.modelData
          && toast.modelData.urgency === NotificationUrgency.Critical

        readonly property bool hasIcon: Howler.iconsEnabled && toast.source !== ""
        readonly property string source: {
          const r = toast.modelData;
          if (!r) return "";
          if (r.image && r.image !== "") return r.image;
          if (r.appIcon && r.appIcon !== "")
            return String(r.appIcon).indexOf("/") === 0
              ? "file://" + r.appIcon : "image://icon/" + r.appIcon;
          return "";
        }

        // FROM A MUSIC PLAYER, asked of the players actually running rather
        // than of a list of names — the same question the history row stores
        // the answer to. It earns the toast a set of transport controls.
        // RESOLVED ONCE, AT ARRIVAL, and then left alone. The match is by
        // track title, because the client that posts the toast and the one
        // that owns the bus name are different programs — so a toast stops
        // matching the instant the player moves on. Re-asking left the toast
        // you pressed Next FROM with neither its marks nor its transport: a
        // row of blank space where the glyphs had been. What this answers is
        // "was this a track when it arrived", and that does not change.
        property string player: ""

        // ── WHAT THE SENDER PUT IN THE BODY ──────────────────────────
        // spoot writes the artist, a line break, and then the track's status
        // marks — liked, explicit, lyrics. Two different kinds of thing on
        // two lines, so they are drawn as two lines: the marks get a row of
        // their own rather than trailing the artist's name.
        readonly property var bodyLines: {
          const b = String(toast.modelData ? (toast.modelData.body || "") : "");
          const parts = b.split(/<br\s*\/?>|\n/);
          const out = [];
          for (let i = 0; i < parts.length; ++i) {
            const t = parts[i].trim();
            if (t !== "") out.push(t);
          }
          return out;
        }

        // ONLY A PLAYER SPEAKS THAT PROTOCOL. Taking line two as "marks"
        // from every sender stole the update toast's first package and set
        // it in a centred grey row of its own.
        readonly property bool musical: toast.player !== ""
        readonly property string marks:
          toast.musical && toast.bodyLines.length > 1 ? toast.bodyLines[1] : ""

        // ── A BODY THAT IS THE WHOLE MESSAGE ─────────────────────────
        // Everything that is not spoot sends one piece of text, and
        // drawing only its first line turned the update toast — which is
        // the update TOOLTIP's own string, groups, counts, arrows and all
        // — into the words "27 Updates". The blank line between the
        // official group and the AUR group is kept, because the tooltip
        // keeps it.
        readonly property string bodyText: {
          const b = String(toast.modelData ? (toast.modelData.body || "") : "");
          if (toast.musical)
            return toast.bodyLines.length > 0 ? toast.bodyLines[0] : "";
          return Howler.markup ? b.replace(/\r?\n/g, "<br/>") : b;
        }

        // A LIST, not a sentence: more than one line of body with no
        // player behind it.
        readonly property bool multiline: !toast.musical
          && String(toast.modelData ? (toast.modelData.body || "") : "")
             .search(/<br\s*\/?>|\n/) >= 0

        // NO SUMMARY IS A DECISION, not an omission to paper over. The
        // update toast sends an empty one because the body's first line
        // already carries the count; the app-name fallback answered that
        // by writing "waybar-updates" above it. A toast with no title is
        // a toast whose body IS the title, so it is drawn the way the
        // tooltip draws it — white, bold, at the full text size.
        readonly property bool titleless:
          !(toast.modelData && toast.modelData.summary)

        // ── AND THE ACTIONS IT ATTACHED ──────────────────────────────
        // The transport is the notification's OWN actions, namespaced by the
        // sender — `spoot:prev`, `spoot:playpause`, `spoot:next`. Driving a
        // player directly would be howler deciding which player a toast is
        // about; invoking the action it came with is answering the program
        // that sent it.
        //
        // `default` is the spec's name for "the toast itself was clicked",
        // which is how clicking a track opens spoot.
        readonly property var transportActs: {
          const out = [];
          const acts = toast.modelData ? (toast.modelData.actions || []) : [];
          for (let i = 0; i < acts.length; ++i) {
            const id = String(acts[i].identifier || "");
            if (id.indexOf(":") > 0) out.push(acts[i]);
          }
          return out;
        }
        readonly property var defaultAct: {
          const acts = toast.modelData ? (toast.modelData.actions || []) : [];
          for (let i = 0; i < acts.length; ++i)
            if (String(acts[i].identifier || "") === "default") return acts[i];
          return null;
        }

        // The icon's box plus its gutters, the text, and the border on both
        // sides — written out rather than measured, so a toast is the width
        // oracle says and not the width its longest word happens to need.
        //
        // A LIST IS THE EXCEPTION. Its lines do not wrap, so a card of the
        // nominal width would cut "gtk-update-icon-cache 1:4.22.4-1 ..."
        // off at 400px; the tooltip is as wide as its longest line and so
        // is this. Maximum width still has the last word. Measured off a
        // free-standing copy of the text rather than off the drawn one,
        // whose width is this very binding.
        readonly property int lane: Howler.hPadding + Howler.borderSize * 2
          + (toast.hasIcon
             ? Howler.iconPadding + Howler.iconSize + Howler.padding
             : Howler.hPadding)
        // THE DELEGATE IS THE LANE, and the card is centred in it. Setting
        // the delegate's own `x` looked right and did nothing: a vertical
        // ListView positions its delegates on BOTH axes, so the view wrote
        // x back to 0 every time and every toast sat flush against the left
        // of the lane — measured at x=0 against the 48 the binding asked
        // for. What the view does not touch is what a child of the delegate
        // does, so the centring moved one level in.
        width: toasts.stackW
        readonly property int cardW:
          Math.min(Howler.maxWidth, toast.lane + Math.max(Howler.width,
            toast.multiline ? Math.ceil(bodyMetrics.implicitWidth) + 2 : 0))
        // MEASURED FROM THE CONTENT, never from `inner`. inner fills this
        // rectangle, so asking it how tall it wants to be while it is sized
        // by the answer is a loop — and a ListView resolves that loop to a
        // zero-height delegate, which is a stack of nothing at all.
        height: Math.min(Howler.maxHeight,
          Math.max(Howler.minHeight,
            Math.max(iconBox.height + Howler.iconPadding * 2,
                     text.implicitHeight + Howler.padding * 2)))


        // NEVER DRAWN, only asked how wide it wants to be. Anchored to
        // nothing and given no width, so its implicitWidth is the text's
        // natural width and not a reading of the card it is sizing.
        Text {
          id: bodyMetrics
          visible: false
          text: toast.bodyText
          textFormat: Howler.markup ? Text.StyledText : Text.PlainText
          wrapMode: Text.NoWrap
          font.family: Zenon.face
          font.weight: toast.titleless ? Font.Bold : Font.Normal
          font.pixelSize: toast.titleless
            ? Howler.fontSize : Howler.fontSize - 2
        }

        // ARRIVAL IS THE DELEGATE'S OWN, not the view's. A ViewTransition's
        // `from` is an absolute coordinate, so an offset written there means
        // something different for every corner; a Translate is relative by
        // construction and says exactly what it does.
        opacity: 0
        transform: Translate {
          id: slide
          x: toasts.slideX
          y: toasts.slideY
        }
        Component.onCompleted: {
          toast.player = toast.modelData
            ? Howler.playerFor(toast.modelData) : "";
          arrive.start();
        }

        ParallelAnimation {
          id: arrive
          NumberAnimation { target: toast; property: "opacity"; to: 1
                            duration: Zenon.normal; easing.type: Zenon.ease }
          NumberAnimation { target: slide; property: "x"; to: 0
                            duration: Zenon.normal; easing.type: Zenon.travelEase }
          NumberAnimation { target: slide; property: "y"; to: 0
                            duration: Zenon.normal; easing.type: Zenon.travelEase }
        }

        // mako's per-urgency timeouts, straight out of oracle. Zero means it
        // stays until it is answered — that is what "critical" is for. Held
        // while the pointer is on it: a toast you are reading should not go.
        Timer {
          running: !toast.closing && !toastHov.hovered
            && Howler.timeoutFor(toast.modelData.urgency) > 0
          interval: Math.max(1, Howler.timeoutFor(toast.modelData.urgency))
          onTriggered: toast.goAway()
        }

        // ── GOING IS OURS TO DRAW ────────────────────────────────────
        // A ListView's `remove` transition only runs when the model says a
        // ROW went; this one is an object model that reports a reset, so the
        // delegate was destroyed in the same frame and the close was one
        // frame long — measured at 17ms against an 83ms open.
        //
        // So the fade happens FIRST and the notification is expired at the
        // end of it. The toast is still there the whole time it is fading,
        // because nothing has told the server to drop it yet.
        property bool closing: false

        function goAway() {
          if (toast.closing) return;
          toast.closing = true;
          leave.start();
        }

        // THE ARRIVAL, REVERSED. It goes back out the way it came in rather
        // than fading on the spot, so the corner it belongs to is as legible
        // on the way out as on the way in.
        ParallelAnimation {
          id: leave
          NumberAnimation { target: toast; property: "opacity"; to: 0
                            duration: Zenon.fast; easing.type: Easing.InQuad }
          NumberAnimation { target: slide; property: "x"; to: toasts.slideX
                            duration: Zenon.fast; easing.type: Easing.InQuad }
          NumberAnimation { target: slide; property: "y"; to: toasts.slideY
                            duration: Zenon.fast; easing.type: Easing.InQuad }
          onFinished: if (toast.modelData) toast.modelData.expire()
        }

        // ── WHAT A CRITICAL TOAST CASTS ──────────────────────────────
        // Red is already the border's colour; the light is the same red put
        // where a border cannot reach. Cheap when it is off, because the
        // effect goes with it.
        MenuShadow {
          panel: card
          cornerRadius: Howler.radius
          ink: Zenon.red
          reach: Howler.glowReach
          softness: Howler.glowReach
          grow: Howler.borderSize * 2
          drop: 0
          visible: toast.critical
        }

        ClippingRectangle {
          id: card
          anchors.horizontalCenter: parent.horizontalCenter
          width: toast.cardW
          height: parent.height
          radius: Howler.radius
          color: Zenon.panelBgDeep
          border.color: toast.critical ? Zenon.red : Zenon.surface
          border.width: Howler.borderSize

          HoverHandler { id: toastHov }

          Item {
            id: inner
            anchors.fill: parent
            anchors.margins: Howler.padding
            // THE PICTURE DOES NOT WANT THE TEXT'S GUTTER. The wide side inset
            // is what keeps a line of text off the border; spent on the image
            // it just made the image small and the card empty around it. So
            // the box is the plain padding and the text makes up the
            // difference on whichever side has no icon against it.
            readonly property int textInset: Howler.hPadding - Howler.padding

            ClippingRectangle {
              id: iconBox
              anchors.left: parent.left
              // Back OUT of inner's gutter by the difference, so the image sits
              // at its own inset from the card rather than at the text's.
              // ONLY WHEN THERE IS AN IMAGE. With none, the box is still an
              // anchor the text starts from, and pulling an empty box six
              // pixels left took six pixels off the text's left gutter and
              // left them on its right — which a centred line shows as being
              // three pixels off centre, on every toast without an icon.
              anchors.leftMargin: toast.hasIcon
                ? Howler.iconPadding - Howler.padding : 0
              anchors.verticalCenter: parent.verticalCenter
              width: toast.hasIcon ? Howler.iconSize : 0
              height: width
              visible: toast.hasIcon
              radius: Howler.iconRadius
              color: "transparent"

              Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: Howler.iconSize
                sourceSize.height: Howler.iconSize
                source: toast.source
              }
            }

            Column {
              id: text
              anchors.left: iconBox.right
              anchors.leftMargin: iconBox.visible
                ? Howler.padding : inner.textInset
              anchors.right: parent.right
              anchors.rightMargin: inner.textInset
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2

              Text {
                width: parent.width
                horizontalAlignment: Howler.textAlign
                elide: Text.ElideRight
                visible: !toast.titleless
                text: toast.modelData.summary || ""
                color: toast.modelData.urgency === NotificationUrgency.Critical
                  ? Zenon.red : Zenon.white
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Howler.fontSize
              }

              Text {
                width: parent.width
                // Where oracle says, list or not. The tooltip left-aligns
                // because it hangs off a bar module; a toast is its own
                // card and goes by the alignment setting like every other
                // toast does.
                horizontalAlignment: Howler.textAlign
                // NO LINE CAP. A four-line ceiling turned the update toast — a
                // list of packages — into its first four packages and an
                // ellipsis. What bounds a toast is notifMaxHeight, which is a
                // setting, rather than a number buried here.
                wrapMode: toast.multiline ? Text.NoWrap : Text.WordWrap
                visible: text !== ""
                text: toast.bodyText
                textFormat: Howler.markup ? Text.StyledText : Text.PlainText
                color: toast.titleless ? Zenon.white : Zenon.muted
                font.family: Zenon.face
                font.weight: toast.titleless ? Font.Bold : Font.Normal
                font.pixelSize: toast.titleless
                  ? Howler.fontSize : Howler.fontSize - 2
              }

              // ── ONE LINE, TWO JOBS ───────────────────────────────────────
              // The marks and the transport occupy the SAME row: hovering swaps
              // what is drawn there and never what is laid out, so the title
              // does not lift a few pixels every time the pointer crosses the
              // toast.
              Item {
                id: marksRow
                width: parent.width
                height: (toast.marks !== "" || toast.transportActs.length > 0)
                  ? marksText.implicitHeight : 0
                visible: height > 0

                Text {
                  id: marksText
                  anchors.fill: parent
                  horizontalAlignment: Howler.textAlign
                  visible: !transport.visible
                  text: toast.marks
                  textFormat: Howler.markup ? Text.StyledText : Text.PlainText
                  color: Zenon.muted
                  font.family: Zenon.face
                  font.pixelSize: Howler.fontSize - 2
                }

                Row {
                  id: transport
                  anchors.centerIn: parent
                  visible: toast.transportActs.length > 0 && toastHov.hovered
                  spacing: 18

                  Repeater {
                    model: toast.transportActs

                    delegate: Text {
                      required property var modelData
                      // The label the sender gave it, turned into the glyph the
                      // bar uses for the same verb — its own text is "Previous",
                      // which is a word where a row of three needs a shape.
                      readonly property string verb:
                        String(modelData.identifier || "").split(":").pop()
                      text: verb === "prev" ? "\uF04A"
                          : verb === "next" ? "\uF04E"
                          : (NowPlaying.playing ? "\uF04C" : "\uF04B")
                      color: btnHov.hovered ? Zenon.white : Zenon.muted
                      font.family: Zenon.face
                      font.pixelSize: Howler.fontSize
                      // A MouseArea, not a TapHandler: a handler lets the
                      // press through to the card's own tap and pressing
                      // Previous would have opened spoot as well as skipping
                      // back. A MouseArea consumes it.
                      HoverHandler { id: btnHov }
                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        // THE ACTION SAYS WHICH BUTTONS EXIST; it does not get
                        // to say what they do. Invoking one activates it over
                        // the bus, and the spec has the server close a
                        // notification that is not `resident` the moment an
                        // action is activated — so skipping a track took the
                        // toast with it. `resident` is the sender's to set and
                        // read-only here, so the press goes where the bar's own
                        // transport sends it instead, and the toast stays up
                        // to show the track it just moved to.
                        onClicked: {
                          if (parent.verb === "prev") NowPlaying.previous();
                          else if (parent.verb === "next") NowPlaying.next();
                          else NowPlaying.toggle();
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // A click is an answer: the first action if the notification offered
          // one, and otherwise simply "seen". Below the transport, which takes
          // its own taps first.
          // Left is "answer it" — the sender's default action if it offered
          // one, which for a track is what opens spoot. Right is "I have seen
          // it", which is the gesture mako had and the one the hand already
          // knows.
          TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: {
              const n = toast.modelData;
              if (!n) return;
              if (toast.defaultAct) { toast.defaultAct.invoke(); return; }
              const acts = n.actions || [];
              if (acts.length > 0) { acts[0].invoke(); return; }
              n.dismiss();
            }
          }

          TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: toast.goAway()
          }
        }
      }
    }

    HowlerOsd {
      id: osdLow
      atTop: toasts.atTop
      slideX: toasts.slideX
      slideY: toasts.slideY
      visible: !toasts.atTop && osdLow.implicitHeight > 0
      height: !toasts.atTop ? implicitHeight : 0
    }
  }
}
