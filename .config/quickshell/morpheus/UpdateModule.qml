// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Io
import "helpers.js" as Helpers
import "../oracle"
import "."

Collapsible {
  id: root
  // Turned off in oracle this eases to zero width exactly as it does when
  // there is nothing pending — the pill shrink-wraps around what is left
  // rather than the module disappearing out of a layout mid-frame.
  active: Oracle.showUpdates && root.hasUpdates
  openWidth: row.implicitWidth

  property bool hasUpdates: false
  property string countText: ""
  property string tooltipText: ""
  property int officialCount: 0
  property int aurCount: 0
  property bool hovered: false

  property string notified: ""

  FileView {
    id: notifiedFile
    path: Quickshell.statePath("updates-notified")
    blockLoading: true
    printErrors: false
  }

  function updateKey(o) {
    return (o.text ?? "") + "\u0000" + (o.tooltip ?? "");
  }

  function announce(o) {
    const key = root.updateKey(o);
    if (!root.hasUpdates) {
      if (root.notified !== "") {
        root.notified = "";
        notifiedFile.setText("");
      }
      return;
    }
    if (key === root.notified) return;
    // The key is still recorded when the toast is switched off, so turning it
    // back on does not announce a set of updates that has been sitting there
    // all along — only the next genuinely new one.
    root.notified = key;
    notifiedFile.setText(key);
    if (!Oracle.updateNotify) return;
    // The SAME body the hover tooltip shows — buildTooltip(), not the raw list
    // waybar-updates hands over. It is the same information either way, but the
    // tooltip's version is grouped into official and AUR, counted, and laid out;
    // the toast used to be an unsorted dump of package lines. Safe to call
    // here: tooltipText and the counts are both set from this same reply before
    // announce() is reached.
    //
    // WITH ITS MARKUP, so the toast IS the tooltip rather than a plainer
    // retelling of it. The inks were stripped back when the daemon could not
    // draw them; howler advertises body-markup and renders StyledText, so the
    // greyed old version and the amber arrow arrive intact. One builder, one
    // body, nothing to keep in step.
    //
    // No summary. It only ever carried the total — "14 updates available" —
    // over a body whose first line already says "13 Updates" and whose second
    // group says "1 AUR Update". Two counts of the same thing, the redundant
    // one set in bold at the top. An empty summary is a summary the toast
    // simply does not draw.
    Quickshell.execDetached([
      "notify-send", "-a", "waybar-updates", "-u", "normal",
      "",
      root.buildTooltip()
    ]);
  }

  function parseCounts(tt) {
    const officialMatch = tt.match(/\s*(\d+)/);
    const aurMatch = tt.match(/\s*(\d+)/);
    root.officialCount = officialMatch ? parseInt(officialMatch[1]) || 0 : 0;
    root.aurCount = aurMatch ? parseInt(aurMatch[1]) || 0 : 0;
  }

  function buildTooltip() {
    const lines = [];
    const tt = root.tooltipText;
    if (!tt) return "";
    const parts = tt.split("\n\n");
    const pkgLines = parts[1] ? parts[1].split("\n") : [];

    let officialPkgs = [];
    let aurPkgs = [];
    for (let i = 0; i < pkgLines.length; ++i) {
      const line = pkgLines[i].trim();
      if (!line) continue;
      if (i < root.officialCount) officialPkgs.push(line);
      else aurPkgs.push(line);
    }

    const LIMIT = 5;

    function fmtPkgs(pkgs, limit) {
      const show = pkgs.slice(0, limit);
      const out = show.map(p => {
        const arrow = p.indexOf("->");
        if (arrow > 0) {
          const before = p.substring(0, arrow).trim();
          const after = p.substring(arrow + 2).trim();
          const nameEnd = before.lastIndexOf(" ");
          const name = before.substring(0, nameEnd);
          const oldVer = before.substring(nameEnd + 1);
          return name + " <font color='#6b7089'>" + oldVer + "</font> <font color='#fab387'>\u2192</font> " + after;
        }
        return p;
      });
      if (pkgs.length > limit) out.push("    <font color='#6b7089'>...</font>");
      return out;
    }

    if (root.officialCount > 0) {
      const word = root.officialCount === 1 ? "Update" : "Updates";
      lines.push("<font color='#7aa2f7'></font>  " + root.officialCount + " " + word);
      for (const p of fmtPkgs(officialPkgs, LIMIT)) {
        lines.push("    " + p);
      }
    }
    if (root.aurCount > 0) {
      if (root.officialCount > 0) lines.push("");
      const word = root.aurCount === 1 ? "AUR Update" : "AUR Updates";
      lines.push("<font color='#c099ff'></font>  " + root.aurCount + " " + word);
      for (const p of fmtPkgs(aurPkgs, LIMIT)) {
        lines.push("    " + p);
      }
    }
    return lines.join("\n");
  }

  Row {
    id: row
    anchors.centerIn: parent
    leftPadding: Zenon.padModule
    rightPadding: Zenon.padModule

    Item {
      id: iconBox
      width: (root.hovered && root.hasUpdates ? countBox.implicitWidth : iconGlyph.implicitWidth) + Zenon.padModule * 2
      Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
      height: Zenon.slot
      anchors.verticalCenter: parent.verticalCenter

      BarText {
        id: iconGlyph
        anchors.centerIn: parent
        text: "󰏗"
        color: Zenon.yellow
        numeric: true
        font.pixelSize: Zenon.clockSize
        opacity: !root.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
      }

      Item {
        id: countBox
        anchors.centerIn: parent
        implicitWidth: Math.max(countGhost.implicitWidth, countLabel.implicitWidth)
        implicitHeight: Zenon.slot

        BarText {
          id: countGhost
          anchors.centerIn: parent
          text: "8".repeat(Math.max(1, String(root.countText).length))
          numeric: true
          color: Zenon.trough(Zenon.yellow)
          opacity: root.hovered && root.hasUpdates ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        }

        BarText {
          id: countLabel
          anchors.centerIn: parent
          text: root.countText
          numeric: true
          color: Zenon.yellow
          opacity: root.hovered && root.hasUpdates ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onEntered: root.hovered = true
    onExited: root.hovered = false
    onClicked: Quickshell.execDetached(["xdg-terminal-exec", "--title=ZENU", "-e", Paths.home() + "/.config/scripts/ZENU.lua", "update"])
  }

  Tooltip {
    anchorItem: root
    cursorArea: mouse
    text: root.buildTooltip()
    styled: true
    show: mouse.containsMouse && root.hasUpdates
  }

  Timer {
    id: updateTimer
    interval: Oracle.updateCheckMins * 60000
    onTriggered: {
      if (!proc.running) proc.running = true;
    }
  }

  Process {
    id: proc
    // -c is waybar-updates' own poll, in seconds, and it has to agree with the
    // timer above or the slower of the two would be the real interval.
    command: ["waybar-updates", "-d",
              "-c", String(Oracle.updateCheckMins * 60), "-l", "100"]
    stdout: SplitParser {
      onRead: (line) => {
        try {
          const o = JSON.parse(line);
          root.hasUpdates = o.alt === "pending-updates";
          root.countText = o.text ?? "";
          root.tooltipText = o.tooltip ?? "";
          root.parseCounts(o.tooltip ?? "");
          root.announce(o);
        } catch (e) {}
      }
    }
    onRunningChanged: (running) => {
      if (running) updateTimer.stop();
      else updateTimer.start();
    }
  }

  Component.onCompleted: {
    root.notified = notifiedFile.text();
    proc.running = true;
  }
}
