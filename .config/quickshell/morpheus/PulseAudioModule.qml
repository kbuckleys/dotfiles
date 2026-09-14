// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "."

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: Zenon.slot

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: Zenon.padModule
    rightPadding: Zenon.padModule

    spacing: 6

    BarText {
      // only while muted: unmuted, the meter says everything the glyph would
      visible: Volume.muted
      text: ""
      color: Zenon.red
    }

    Meter {
      anchors.verticalCenter: parent.verticalCenter
      // ONE OR THE OTHER, never both. The glyph above appears only while
      // muted, and the meter used to stay beside it drawn empty and red —
      // which is two things saying the same thing, and the emptier of the two
      // is the one that reads as a level rather than as a state. Muted is not
      // a quiet volume, it is the absence of one, so the bar says so with a
      // glyph and takes the gauge away.
      visible: !Volume.muted
      value: Volume.level
      accent: Zenon.green
    }
  }

  // The panel is not declared here. It belongs to the audio group in
  // shell.qml, which spans this and the track name beside it: two modules
  // showing the same panel from two different anchors meant crossing between
  // them closed one and reopened the other somewhere else.
  property bool hovered: mouse.containsMouse

  // Reported rather than acted on, like every other meter in this bar. This
  // used to spawn a terminal running wiremix; zeus has the mixer now, and a
  // module that knew the name of a package was the one meter that did.
  signal activated

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.activated()
    onPressed: (mouse) => { if (mouse.button === Qt.RightButton) Volume.toggleMute() }
    onWheel: (wheel) => {
      Volume.nudge(wheel.angleDelta.y > 0 ? 0.01 : -0.01);
      wheel.accepted = true;
    }
  }
}
