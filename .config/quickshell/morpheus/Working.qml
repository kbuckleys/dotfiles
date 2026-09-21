// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THREE DOTS, BREATHING IN TURN — the shell's one way of saying "out, and
// not back yet".
//
// It replaces the word. "scanning…" and "looking up…" are a status line
// reporting on itself: they take a line of the panel, they are read once
// and then ignored, and when the answer lands the text changes under your
// eye in a way that reads as a glitch rather than as an arrival. A mark
// that MOVES says the same thing with no words, and stopping is the whole
// message.
//
// No progress in it, deliberately. Neither a directory walk nor an HTTP
// round trip knows how far along it is, and a bar that fills at a guessed
// rate is a lie told smoothly.
//
// Used as:
//
//     Working { running: Picasso.scanning }
//     Working { running: popup.dictLoading; ink: Zenon.cyan; dot: 5 }
//
// It occupies no space when it is not running, so a Row it sits in closes
// up rather than leaving a hole where the dots were.

import QtQuick
import "."

Item {
  id: root

  // whether there is something to wait for
  property bool running: false
  property color ink: Zenon.muted
  // the diameter of one dot, and the gap between them
  property int dot: 4
  property int gap: 5
  // one dot's whole cycle; the three are a third of it apart
  property int period: 900
  readonly property real lowest: 0.18

  readonly property int count: 3

  visible: root.running
  implicitWidth: root.running
    ? root.count * root.dot + (root.count - 1) * root.gap : 0
  implicitHeight: root.dot

  Row {
    anchors.centerIn: parent
    spacing: root.gap

    Repeater {
      model: root.count

      delegate: Rectangle {
        id: pip
        required property int index
        width: root.dot
        height: root.dot
        radius: root.dot / 2
        color: root.ink
        opacity: root.lowest

        // ON THE RENDER THREAD. OpacityAnimator rather than a
        // NumberAnimation on the same property: these run while a
        // directory walk is landing rows into a view, which is exactly
        // when the GUI thread is too busy to animate anything — and a
        // stuttering "please wait" is worse than no animation at all.
        // The same rule the cursor follows, see qml-animator notes.
        // THE OFFSET IS OUTSIDE THE LOOP. Putting it inside made every
        // cycle pay it again, and the last dot's remaining pause came out
        // negative — which Qt says out loud. Each dot now runs the same
        // one-second loop and simply starts later than the one before it,
        // so the three read as a wave passing rather than three lamps
        // blinking together.
        SequentialAnimation on opacity {
          running: root.running

          PauseAnimation {
            duration: Math.round(root.period / root.count) * pip.index
          }

          SequentialAnimation {
            loops: Animation.Infinite

            OpacityAnimator {
              target: pip
              from: root.lowest; to: 1
              duration: Math.round(root.period / 3)
              easing.type: Easing.InOutSine
            }
            OpacityAnimator {
              target: pip
              from: 1; to: root.lowest
              duration: Math.round(root.period / 3)
              easing.type: Easing.InOutSine
            }
            PauseAnimation { duration: Math.round(root.period / 3) }
          }
        }
      }
    }
  }
}
