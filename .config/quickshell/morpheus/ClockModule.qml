// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import "helpers.js" as Helpers
import "../chronos/chronos.js" as Chr
import "../chronos"
import "../oracle"
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

    // The live digits sit on top of every segment lit and dimmed. DSEG has no
    // ghosting of its own — you get it by drawing "88:88" behind, which is
    // literally what the panel of a real clock is doing: the unlit segments
    // are still there, you can just about see them.
    //
    // The ghost is built from the SAME shape as the reading — one more group
    // of eights when the seconds are showing — so the two cannot come out
    // different widths and leave the live digits sitting off-centre on their
    // own unlit panel.
    Item {
      width: Math.max(ghost.implicitWidth, label.implicitWidth)
      height: Zenon.slot
      anchors.verticalCenter: parent.verticalCenter

      BarText {
        id: ghost
        anchors.centerIn: parent
        text: Oracle.clockSeconds ? "88:88:88" : "88:88"
        numeric: true
        // the same ink an unlit meter notch uses: it is the same idea, an
        // element of the accent that is present but not lit
        color: Zenon.trough(Zenon.cyan)
      }

      BarText {
        id: label
        anchors.centerIn: parent
        // Padded in both modes, and on purpose: an unpadded 12-hour clock is
        // one digit narrower for eleven hours of the day, and a bar module
        // that changes width every time it strikes ten would push everything
        // beside it sideways. The leading zero is what keeps the pill still.
        text: Helpers.pad(root.shownHour) + ":" + Helpers.pad(clock.minutes)
          + (Oracle.clockSeconds ? ":" + Helpers.pad(clock.seconds) : "")
        numeric: true
        color: Zenon.cyan
      }
    }
  }

  // 13 is 01 on a 12-hour face, and midnight is 12 rather than 00.
  readonly property int shownHour: {
    if (Oracle.clock24h) return clock.hours;
    return ((clock.hours + 11) % 12) + 1;
  }

  SystemClock {
    id: clock
    // Seconds means a repaint a second rather than a repaint a minute, which
    // is sixty times the work for a digit most bars do not carry — so it is
    // only asked for when it is actually being shown.
    precision: Oracle.clockSeconds ? SystemClock.Seconds : SystemClock.Minutes
    enabled: true
  }

  // What today is, in one line. The month grid that used to hang off this
  // hover is a layer now — a calendar you can page through does not belong in
  // something that vanishes when the pointer moves.
  signal activated()

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.activated()
  }

  // ── WHAT IS RUNNING, under the date ───────────────────────────────────
  // A timer you set is a thing you are waiting on, and the clock is what you
  // look at while waiting — but the only place saying how long was left was
  // the panel behind a click. The hover already answers "what day is it"; it
  // may as well answer the other question you came to the clock with.
  //
  // Running ones first and counting down; idle ones after, showing the length
  // they are set to. An idle timer is still something you made on purpose and
  // worth being reminded of, and the two are told apart by the arrow rather
  // than by being in separate lists.
  readonly property string timerLines: {
    const ts = Chronos.timers;
    if (!ts || ts.length === 0) return "";
    const run = [];
    const idle = [];
    for (let i = 0; i < ts.length; ++i) {
      const t = ts[i];
      const name = String(t.label || "timer");
      if (t.running) run.push("\u25b8 " + name + "   " + Chr.clock(t.remaining));
      else idle.push("\u00b7 " + name + "   " + t.minutes + "m");
    }
    const all = run.concat(idle);
    return all.length === 0 ? "" : "\n" + all.join("\n");
  }

  Tooltip {
    anchorItem: root
    cursorArea: mouse
    text: Chr.oneLine(clock.date) + root.timerLines
    align: Text.AlignHCenter
    show: mouse.containsMouse
  }
}
