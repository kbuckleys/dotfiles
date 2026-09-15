// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┘┴└─┘
// https://github.com/kbuckleys/
//
// THE WALL THE NOTES ARE ON — one surface per screen, every note drawn on
// every screen it reaches.
//
// A LAYER SURFACE BELONGS TO AN OUTPUT. The protocol fixes it at creation and
// has no request to change it, so a note cannot be carried across a seam the
// way a window is: moving one means destroying its surface and building
// another, and a surface that goes takes the pointer grab with it — which is
// why a drag across a monitor boundary had to be started again on the far
// side. So nothing is ever moved between outputs. Each screen's surface draws
// the whole wall and shows the part of it that lands on that screen. A note
// crossing a seam is already drawn on the far side before it gets there.
//
// THE INPUT REGION IS BUILT FROM THE MODEL. That is the part that looked
// impossible: a mask is a declared Region and the notes are a list. Masked to
// the item holding them the surface claimed the whole screen and swallowed
// every click on the desktop; masked to nothing it heard none at all. A
// Region's `regions` takes a list, and an Instantiator can build one Region
// per note — so the region really is the notes, and only the notes.
//
// Which also brings back what one surface per note could not have: a note you
// click comes to the FRONT, because they are items in one scene again rather
// than separate surfaces whose stacking is fixed at creation.
//
// ON THE BOTTOM LAYER, and declared after icarus' desktop catcher in
// shell.qml — that catcher masks the whole screen, and within one layer the
// later surface is the one on top.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Wayland
import "../morpheus"
import "clio.js" as Scribe

Variants {
  model: Quickshell.screens

  PanelWindow {
    id: board
    required property var modelData

    screen: board.modelData
    readonly property real originX: board.screen ? board.screen.x : 0
    readonly property real originY: board.screen ? board.screen.y : 0

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "clio"
    // A note is typed into, so the surface has to be able to hold the
    // keyboard — but only while one is being edited.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }
    visible: Clio.shown && Clio.count > 0

    // Which note has the keyboard, "" for none. Board-local: the notes are
    // shared between screens, the keyboard is not.
    property string editing: ""

    // ── THE REGION, ONE RECTANGLE PER NOTE ─────────────────────────────
    // Built rather than declared — see the note above. Positioned exactly as
    // the cards are, so what takes a click is what draws.
    //
    // ALWAYS THE NOTES, even while one is being edited. It used to drop the
    // mask entirely so that clicking OFF a note was a click this surface
    // received — and that is a trap: clio then swallows the click, so
    // whatever would have taken the focus away never gets it, the state
    // never clears, and the surface keeps the whole screen for good. One
    // note touched and icarus could not be opened on that monitor again.
    //
    // Leaving insert is therefore not something this surface watches for. It
    // is told — see onActiveChanged, which fires when the click it did NOT
    // take lands on something else.
    Instantiator {
      id: shapes
      model: Clio.rows

      delegate: Region {
        required property string key
        readonly property var n: Clio.noteFor(key)
        x: n ? Math.round(n.x - board.originX) : 0
        y: n ? Math.round(n.y - board.originY) : 0
        width: n ? n.w : 0
        height: n ? n.h : 0
      }
    }

    mask: noteMask



    Region {
      id: noteMask
      // ZERO-SIZED ON ITS OWN. A Region combines its own rectangle with its
      // children's, and one with no geometry of its own does not mean "no
      // rectangle" — so the union came out as the whole surface and clio
      // swallowed every click on any screen that had a note on it. Which is
      // why making a note stopped icarus opening on that monitor.
      x: 0
      y: 0
      width: 0
      height: 0
      regions: {
        const out = [];
        for (let i = 0; i < shapes.count; i++) out.push(shapes.objectAt(i));
        return out;
      }
    }

    // ── THE CLICK THAT WENT SOMEWHERE ELSE ─────────────────────────────
    // The mechanism this shell already has for exactly this, and which zeus
    // and icarus both use: a grab reports the clicks that land outside its
    // windows WITHOUT taking them. That distinction is the whole problem —
    // widening the mask to catch the click swallowed it, so nothing else
    // could take the focus, so the state never cleared and the monitor was
    // lost to icarus for good. Asking the window whether it was still
    // active was the other way round: nothing ever told it.
    //
    // Held only while a note is being edited, so the desktop is untouched
    // the rest of the time.
    HyprlandFocusGrab {
      windows: [ board ]
      active: board.editing !== ""
      onCleared: wall.forceActiveFocus()
    }

    Item {
      id: wall
      anchors.fill: parent


      // ADDRESSED BY KEY, never by position — see Clio.rows. A delegate
      // that finds its note by index is a delegate that becomes a different
      // note the moment one earlier in the list goes; addressed by key it
      // stays the note it was, and the one that went is the one destroyed.
      Repeater {
        model: Clio.rows

        delegate: Item {
          id: slot
          required property string key

          readonly property var note: Clio.noteFor(slot.key)
          readonly property string noteId: slot.key
          readonly property color hue:
            slot.note ? Clio.ink(slot.note.hue) : Zenon.sand
          readonly property bool active: body.activeFocus

          // BOUND, not owned. A gesture writes the note on every frame and
          // this follows — which is how the copy of this note on the next
          // screen keeps up with a drag happening on this one.
          x: slot.note ? slot.note.x - board.originX : 0
          y: slot.note ? slot.note.y - board.originY : 0
          width: slot.note ? slot.note.w : 260
          height: slot.note ? slot.note.h : 220

          // The one you touched is the one in front. Stacking is an item's
          // `z` again, which is the whole reason these share a surface.
          z: slot.note ? slot.note.z : 0

          visible: slot.note !== null
          property bool busy: false


          // ARRIVING. Once, when the note is made — which now happens only
          // when a note is genuinely made.
          opacity: 0
          scale: 0.94
          Component.onCompleted: {
            slot.opacity = 1;
            slot.scale = 1;
          }
          Behavior on opacity {
            NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease }
          }
          Behavior on scale {
            NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase }
          }

          // The shadow every card on this desktop casts. A sibling of the
          // card and never a child: the card clips, and a card that clips
          // clips its own shadow away.
          MenuShadow {
            panel: card
            cornerRadius: card.radius
            ink: slot.active ? Zenon.menuShadowInk
              : Qt.rgba(Zenon.menuShadowInk.r, Zenon.menuShadowInk.g,
                        Zenon.menuShadowInk.b, Zenon.menuShadowInk.a * 0.45)
            softness: slot.active
              ? Zenon.menuShadowBlur : Zenon.menuShadowBlur * 0.45
            grow: slot.active ? Zenon.menuShadowGrow : 0
            drop: slot.active
              ? Zenon.menuShadowDrop : Zenon.menuShadowDrop * 0.4
            Behavior on softness {
              NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
            }
            Behavior on drop {
              NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
            }
            Behavior on ink { ColorAnimation { duration: Zenon.fast } }
          }

          ClippingRectangle {
            id: card
            anchors.fill: parent
            radius: 8
            color: slot.note ? Clio.wash(slot.note.hue) : "transparent"
            border.width: 1
            border.color: Qt.rgba(slot.hue.r, slot.hue.g, slot.hue.b, 0.55)

            HoverHandler { id: noteHov }

            // ── THE HEAD IS THE HANDLE ───────────────────────────────
            // The whole note is not draggable, because the whole note but
            // this strip is a text field — a drag starting in the body is a
            // selection, and guessing which was meant is how an editor loses
            // a sentence.
            Rectangle {
              id: head
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              height: slot.active ? 32 : 0
              visible: head.height > 0.5
              clip: true
              color: Qt.rgba(slot.hue.r, slot.hue.g, slot.hue.b, 0.22)
              Behavior on height {
                NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
              }

              MouseArea {
                id: drag
                anchors.fill: parent
                property real grabX: 0
                property real grabY: 0

                onPressed: (m) => {
                  drag.grabX = m.x;
                  drag.grabY = m.y;
                  // Keeps the note active while it is being dragged: the head
                  // is shown by the body having focus, and a press on the
                  // head is not a press on the body.
                  slot.busy = true;
                  body.forceActiveFocus();
                  Clio.raise(slot.noteId);
                }
                onPositionChanged: (m) => {
                  if (!drag.pressed) return;
                  Clio.place(slot.noteId,
                    slot.note.x + (m.x - drag.grabX),
                    slot.note.y + (m.y - drag.grabY),
                    slot.note.w, slot.note.h);
                }
                // Recorded on release rather than per frame: the position is
                // not news until the gesture is over, and a file rewritten
                // sixty times a second to record one drag is sixty writes
                // for one fact.
                onReleased: slot.busy = false
              }

              // ── WHAT THE HEAD HOLDS ──────────────────────────────
              // Only while you are on the note. A wall of stickies covered
              // in buttons is a control panel; the buttons are for when you
              // have reached for one.
              readonly property bool armed: slot.active

              // ── WHAT FITS, IN THE ORDER IT IS MISSED LEAST ───────
              // A note can be dragged down to 180px and the bar cannot: at
              // full strength it needs about three hundred. So it gives way
              // instead of piling up — the swatches go first, then the size
              // stepper, and the close never does. Measured against what the
              // rows actually want rather than against thresholds written
              // out here, so changing a glyph cannot put the numbers wrong.
              readonly property real freeForSwatches:
                head.width - fmtRow.width - close.width - 34
              readonly property bool roomForSwatches:
                head.freeForSwatches >= swatchRow.implicitWidth
              readonly property bool roomForSize:
                head.width - close.width - 34 >= fmtRow.implicitWidth

              Row {
                id: fmtRow
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                opacity: head.armed ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity {
                  NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                }

                // Bold, italic and underline, applied to the SELECTION when
                // there is one and to the whole note when there is not —
                // which is what pressing bold with nothing selected means.
                Repeater {
                  model: [["\uF032", "b"], ["\uF033", "i"], ["\uF0CD", "u"]]

                  delegate: Rectangle {
                    id: fmt
                    required property var modelData
                    width: 26
                    height: 22
                    radius: 4
                    color: fmtHov.hovered
                      ? Qt.rgba(1, 1, 1, 0.16) : "transparent"

                    HoverHandler { id: fmtHov }

                    Text {
                      anchors.centerIn: parent
                      text: fmt.modelData[0]
                      color: Zenon.white
                      font.family: Zenon.face
                      font.pixelSize: 14
                    }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: card.mark(fmt.modelData[1])
                    }
                  }
                }

                // ── AND HOW BIG IT IS ──────────────────────────────
                // A mark saying what the two buttons beside it are about,
                // then down and up. The mark is not a button: a label you can
                // press is a label that has to say what pressing it does, and
                // "text size" already has two answers to that on either side.
                //
                // Each end dims when there is nowhere further to go, so the
                // control says it has run out rather than silently ignoring
                // you — see Scribe.stepSize, which clamps rather than wraps.
                Item { width: 5; height: 1; visible: head.roomForSize }

                // MINUS, THE MARK, PLUS — read as a sentence, with the thing
                // being changed in the middle and the two directions either
                // side of it. One Repeater rather than a button, a label and
                // another button: the middle entry is the one with nowhere to
                // step, which is what makes it the label.
                Repeater {
                  model: [["\uF068", -1], ["\uE659", 0], ["\uF067", 1]]

                  delegate: Rectangle {
                    id: step
                    required property var modelData
                    readonly property bool isMark: step.modelData[1] === 0
                    visible: head.roomForSize
                    readonly property bool canGo: !step.isMark && slot.note
                      && Scribe.stepSize(slot.note.size, step.modelData[1])
                         !== slot.note.size
                    width: step.isMark ? 20 : 26
                    height: 22
                    radius: 4
                    color: !step.isMark && stepHov.hovered && step.canGo
                      ? Qt.rgba(1, 1, 1, 0.16) : "transparent"

                    HoverHandler { id: stepHov }

                    Text {
                      anchors.centerIn: parent
                      text: step.modelData[0]
                      color: Zenon.white
                      opacity: step.isMark ? 1 : (step.canGo ? 1 : 0.3)
                      font.family: Zenon.face
                      font.pixelSize: step.isMark ? 14 : 12
                    }

                    MouseArea {
                      anchors.fill: parent
                      enabled: step.canGo
                      onClicked: Clio.set(slot.noteId, "size",
                        Scribe.stepSize(slot.note.size, step.modelData[1]))
                    }
                  }
                }
              }

              // The colours, as the note's own hue repeated in every other.
              Row {
                id: swatchRow
                anchors.right: close.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                opacity: head.armed ? 1 : 0
                visible: opacity > 0.01 && head.roomForSwatches
                Behavior on opacity {
                  NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                }

                Repeater {
                  model: Scribe.HUES

                  delegate: Rectangle {
                    id: swatch
                    required property var modelData
                    width: 13
                    height: 13
                    radius: 6.5
                    color: Clio.ink(swatch.modelData)
                    // The one it wears is ringed rather than missing from the
                    // row: a gap would move every other swatch each time you
                    // changed colour.
                    border.width: slot.note
                      && slot.note.hue === swatch.modelData ? 2 : 0
                    border.color: Zenon.white
                    opacity: swatchHov.hovered || (slot.note
                      && slot.note.hue === swatch.modelData) ? 1 : 0.55

                    HoverHandler { id: swatchHov }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: Clio.set(slot.noteId, "hue", swatch.modelData)
                    }
                  }
                }
              }

              Text {
                id: close
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "\uF00D"
                color: closeHov.hovered ? Zenon.red : Zenon.white
                opacity: head.armed ? 1 : 0
                visible: opacity > 0.01
                font.family: Zenon.face
                font.pixelSize: 15
                Behavior on opacity {
                  NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                }

                HoverHandler { id: closeHov }
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -4
                  onClicked: Clio.remove(slot.noteId)
                }
              }
            }

            // ── AND THE NOTE ITSELF ──────────────────────────────────
            Flickable {
              anchors.top: head.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 10
              clip: true
              contentWidth: width
              contentHeight: body.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              TextEdit {
                id: body
                width: parent.width
                // RICH TEXT, because the formatting buttons are edits rather
                // than properties — see card.mark. Plain text would render
                // the tags they insert as the characters they are made of.
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                persistentSelection: true
                // SET ONCE, NEVER BOUND. Assigning text to a TextEdit puts
                // the caret at the start, so a binding would have moved it
                // there on every keystroke. The model is written TO from here
                // and read back only when this slot takes on another note.
                Component.onCompleted: body.text = slot.note ? slot.note.text : ""
                color: Zenon.white
                selectionColor: Qt.rgba(1, 1, 1, 0.25)
                selectedTextColor: Zenon.white
                font.family: Zenon.face
                font.pixelSize: slot.note ? slot.note.size : 14

                // Stored as the body's contents rather than as Qt's whole
                // HTML document — see Scribe.fragment — and as nothing at
                // all when the note is empty, which is otherwise six hundred
                // bytes of boilerplate saying so.
                onTextChanged: {
                  if (!slot.note) return;
                  const t = body.length === 0 ? "" : Scribe.fragment(body.text);
                  if (t !== slot.note.text)
                    Clio.set(slot.noteId, "text", t);
                }
                onActiveFocusChanged: {
                  if (activeFocus) {
                    board.editing = slot.noteId;
                    Clio.raise(slot.noteId);
                  } else if (board.editing === slot.noteId) {
                    board.editing = "";
                  }
                }

                // BACK TO NORMAL. Giving the focus up is the whole of it:
                // the head, the buttons and the card's own handle all read
                // `slot.active`, which is this having the keyboard.
                Keys.onEscapePressed: (e) => {
                  e.accepted = true;
                  body.deselect();
                  body.focus = false;
                  wall.forceActiveFocus();
                }
              }
            }

            // The placeholder, which is not the TextEdit's own: a rich-text
            // edit has no ghost, and an empty note that says nothing at all
            // looks broken rather than blank.
            Text {
              anchors.top: head.bottom
              anchors.left: parent.left
              anchors.topMargin: 10
              anchors.leftMargin: 10
              visible: body.length === 0 && !body.activeFocus
              text: "note\u2026"
              color: Qt.rgba(1, 1, 1, 0.35)
              font.family: Zenon.face
              font.pixelSize: slot.note ? slot.note.size : 14
            }

            // ── NORMAL MODE ──────────────────────────────────────────
            // A note you have not clicked into is an editor in normal mode:
            // no edits, only motion. So the whole card is the handle and the
            // text under it is inert — which is why this sits ABOVE the body
            // and is disabled the moment the body has the keyboard.
            //
            // A CLICK AND A DRAG ARE THE SAME GESTURE until the pointer
            // moves. Under the threshold it was a click and the note goes
            // into insert; over it, it was a drag and the note was moved,
            // which is not a request to start typing in it. Five pixels, the
            // same figure terminus tells a tab click from a tab drag by.
            MouseArea {
              anchors.fill: parent
              enabled: !slot.active
              property real grabX: 0
              property real grabY: 0
              property bool moved: false

              onPressed: (m) => {
                grabX = m.x;
                grabY = m.y;
                moved = false;
                slot.busy = true;
                Clio.raise(slot.noteId);
              }
              onPositionChanged: (m) => {
                if (!pressed) return;
                if (!moved
                    && Math.abs(m.x - grabX) < 5 && Math.abs(m.y - grabY) < 5)
                  return;
                moved = true;
                Clio.place(slot.noteId,
                  slot.note.x + (m.x - grabX),
                  slot.note.y + (m.y - grabY),
                  slot.note.w, slot.note.h);
              }
              onReleased: {
                slot.busy = false;
                if (!moved) body.forceActiveFocus();
              }
            }

            // ── THE CORNER YOU PULL ──────────────────────────────────
            MouseArea {
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              width: 26
              height: 26
              cursorShape: Qt.SizeFDiagCursor
              // Grown with the glyph: the mark and the thing you grab are the
              // same corner, and a 22px glyph inside a 20px box would have
              // been drawn past the edge of what answers the pointer.
              property real grabW: 0
              property real grabH: 0
              property real grabX: 0
              property real grabY: 0

              // MEASURED IN THE WALL, never in this box. `m.x` is relative
              // to this MouseArea, and this MouseArea is anchored to the
              // card's right and bottom edges — the very edges the drag is
              // moving. So the origin the pointer was measured from slid out
              // from under it on every frame, and the note grew in fits.
              // Reading the pointer off a thing the pointer is moving is a
              // feedback loop; the wall holds still.
              onPressed: (m) => {
                const p = mapToItem(wall, m.x, m.y);
                grabW = slot.note.w;
                grabH = slot.note.h;
                grabX = p.x;
                grabY = p.y;
                slot.busy = true;
                Clio.raise(slot.noteId);
              }
              onPositionChanged: (m) => {
                if (!pressed) return;
                const p = mapToItem(wall, m.x, m.y);
                Clio.place(slot.noteId, slot.note.x, slot.note.y,
                  Scribe.clamp(grabW + (p.x - grabX),
                               Scribe.MIN_W, Scribe.MAX_W),
                  Scribe.clamp(grabH + (p.y - grabY),
                               Scribe.MIN_H, Scribe.MAX_H));
              }
              onReleased: slot.busy = false

              Text {
                anchors.centerIn: parent
                text: "\uDB81\uDC5D"
                color: Qt.rgba(1, 1, 1, noteHov.hovered ? 0.45 : 0)
                font.family: Zenon.face
                font.pixelSize: 22
                Behavior on color { ColorAnimation { duration: Zenon.fast } }
              }
            }

            // ── BOLD, ITALIC, UNDERLINE ──────────────────────────────
            // An EDIT, not a property. TextEdit's font is document-wide, so
            // there is no per-selection bold to set — the selection is
            // replaced with itself inside the tag, which is what a rich-text
            // editor does underneath. With nothing selected the whole note is
            // wrapped, because that is what pressing bold on an empty
            // selection means.
            // THROUGH Scribe.inline, and that is the whole of why this
            // works now. getFormattedText hands back a whole HTML document —
            // doctype, head, stylesheet and a paragraph — so wrapping its
            // result in <b> put the tag around the DOCTYPE and left the words
            // exactly as they were. Reduced to the run of inline markup
            // inside it, the tag lands on the text.
            function mark(tag) {
              const from = body.selectionStart;
              const to = body.selectionEnd;
              const had = from !== to;
              const a = had ? from : 0;
              const b = had ? to : body.length;
              if (b <= a) return;
              const run = Scribe.inline(body.getFormattedText(a, b));
              if (run === "") return;
              // A TOGGLE, NOT A STAMP. Pressing bold on bold text is how you
              // ask for it not to be bold — a one-shot left the only way back
              // being undo, and pressing it twice nested one <b> inside
              // another and grew the document for nothing.
              const next = Scribe.marked(run, tag)
                ? Scribe.unmark(run, tag)
                : "<" + tag + ">" + run + "</" + tag + ">";
              body.remove(a, b);
              body.insert(a, next);
              // The selection is put back so the next button acts on the same
              // words — bold then italic is one thought, not two selections.
              if (had) body.select(a, body.selectionEnd);
              body.forceActiveFocus();
            }
          }
        }
      }
    }
  }
}
