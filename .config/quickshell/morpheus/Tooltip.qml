// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "../oracle"
import "."
import "helpers.js" as Helpers

CursorAnchor {
  id: popup

  // Every hover text in the bar comes through here, so this is the one place
  // the switch has to be. NowPlayingPanel is a CursorAnchor too and is NOT
  // caught by it, which is right: it is a panel with transport controls in
  // it, not a label telling you what you are pointing at.
  suppressed: !Oracle.barTooltips

  required property string text
  property bool styled: false
  // Left by default, because most tooltips here are label/value lists and
  // ragged-right is what makes those scannable. A tooltip that is a couple of
  // short standalone lines reads better centred, and says so.
  property int align: Text.AlignLeft
  // Zero or more sparklines under the text, each { values, line, fill }.
  // A list rather than one series plus a colour pair: network has two
  // channels to plot, and a second set of history/historyLineColor/... would
  // have been a parallel way of saying the same thing.
  property var series: []

  // only the ones with enough points to draw; a Sparkline needs two
  readonly property var liveSeries: {
    const out = [];
    const src = popup.series ?? [];
    for (let i = 0; i < src.length; ++i) {
      const s = src[i];
      if (s && s.values && s.values.length >= 2) out.push(s);
    }
    return out;
  }

  // Room all round for the shadow, and the card inset into the middle of
  // it — see CursorAnchor.pad, which keeps the CARD the same distance
  // from the pointer rather than the surface.
  pad: Zenon.menuShadowPad
  implicitWidth: background.implicitWidth + Zenon.menuShadowPad * 2
  implicitHeight: background.implicitHeight + Zenon.menuShadowPad * 2

  // Behind the card as a sibling, never inside it.
  MenuShadow {
    panel: background
    cornerRadius: background.radius
    opacity: popup.showFactor
  }

  Rectangle {
    id: background
    x: Zenon.menuShadowPad
    y: Zenon.menuShadowPad
    implicitWidth: layout.width
    implicitHeight: layout.height
    opacity: popup.showFactor
    color: Zenon.panelBg
    border.color: Zenon.surfaceBorder
    border.width: 1
    radius: 6

    Column {
      id: layout
      width: Math.max(content.implicitWidth,
        sparks.visible ? sparks.implicitWidth + 40 : content.implicitWidth)
      height: content.implicitHeight
        + (sparks.visible ? sparks.implicitHeight + 10 + 6 : 0)
      spacing: 0

      Text {
        id: content
        width: parent.width
        leftPadding: 20
        rightPadding: 20
        topPadding: 10
        bottomPadding: sparks.visible ? 6 : 10
        text: popup.styled ? Helpers.tooltip(popup.text) : popup.text
        textFormat: popup.styled ? Text.StyledText : Text.PlainText
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: 16
        horizontalAlignment: popup.align
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.NoWrap
      }

      Column {
        id: sparks
        visible: popup.liveSeries.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4

        // Modelled on the COUNT, not on the list itself. The list is rebuilt
        // every time its data changes — four times a second for network — and
        // a Repeater handed a new array destroys and recreates every delegate,
        // which is what made the traces flicker. A count that stays 2 leaves
        // the delegates alone and lets their bindings update in place.
        Repeater {
          model: popup.liveSeries.length

          delegate: Sparkline {
            required property int index
            readonly property var cfg: popup.liveSeries[index] ?? null
            width: Math.max(160, content.implicitWidth - 20)
            height: 32
            values: cfg ? cfg.values : []
            lineColor: cfg ? cfg.line : Zenon.cyan
            // most callers want the fill to be the line's own colour
            fillColor: cfg ? (cfg.fill ?? cfg.line) : Zenon.cyan
            fillOpacity: 0.18
          }
        }
      }

      Item { width: 1; height: sparks.visible ? 10 : 0 }
    }
  }
}
