// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Base for every popout that hangs off a bar module: tooltips and the
// calendar. It owns one thing — where the window lands — so the two cannot
// drift apart the way they had. Derived components supply only their own
// content and its implicit size.

import QtQuick
import Quickshell
import "."

PanelWindow {
  id: anchorRoot

  // the bar item this popout belongs to; its window is the coordinate system
  // everything below converts out of
  required property Item anchorItem
  // the hovering MouseArea; the popout rides its pointer. Without one it
  // falls back to sitting centred over the anchor item.
  property MouseArea cursorArea: null
  property bool show: false
  // Held shut regardless of `show`. The caller owns "is the pointer on me";
  // this is for whoever owns "are these wanted at all" — see Tooltip, which
  // is the one that answers to a setting. Kept out here rather than folded
  // into `show` so a caller's own binding is never fought over.
  property bool suppressed: false
  // pointer clearance: how far the popout's bottom edge sits above the cursor
  property int gap: 5

  // ── THE SURFACE MAY BE BIGGER THAN THE THING YOU SEE ──────────────
  // A card that casts a shadow needs its surface grown all round to give
  // the shadow somewhere to fall, and the card then sits inset by that
  // much. The positioning below aims the SURFACE, so without knowing the
  // inset it would hold the surface the right distance from the pointer
  // and leave the card `pad` further away than asked.
  //
  // Zero by default: a surface with no shadow is its own card, and
  // CornerPicker — which pads itself — has always been placed this way.
  property int pad: 0

  // A popout you can move the pointer INTO. Two things follow from that: it
  // has to take input, and it has to stop riding the cursor once it is up —
  // a panel that keeps following walks out from under the hand reaching for
  // it. Plain tooltips leave this false and keep tracking.
  property bool interactive: false
  // what the pointer may land on; only meaningful when interactive
  property Item hitArea: null

  readonly property var srcWin: anchorRoot.anchorItem
    ? anchorRoot.anchorItem.QsWindow.window : null

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  aboveWindows: true
  screen: anchorRoot.srcWin?.screen ?? null

  // A tooltip names no hitArea and stays fully clickthrough; a panel names
  // one and takes the pointer over exactly that item.
  mask: Region { item: anchorRoot.hitArea }

  anchors { top: true; left: true }

  // fade instead of popping; the window has to outlive the fade, so
  // visibility follows the factor rather than `show` directly
  property real showFactor: (anchorRoot.show && !anchorRoot.suppressed
                             && anchorRoot.srcWin !== null) ? 1 : 0
  Behavior on showFactor {
    NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
  }
  visible: anchorRoot.showFactor > 0.01

  // Pointer in screen coordinates, falling back to the anchor item's top
  // centre. The bar is its own layer-shell surface inset from the screen
  // edges, so item coordinates are window-relative; Zenon.winOrigin converts
  // them back — without it every popout lands one side-margin too far left.
  readonly property point livePoint: {
    if (!anchorRoot.srcWin || !anchorRoot.anchorItem || !anchorRoot.screen)
      return Qt.point(0, 0);
    const src = anchorRoot.cursorArea ? anchorRoot.cursorArea : anchorRoot.anchorItem;
    const lx = anchorRoot.cursorArea ? anchorRoot.cursorArea.mouseX
                                     : anchorRoot.anchorItem.width / 2;
    const ly = anchorRoot.cursorArea ? anchorRoot.cursorArea.mouseY : 0;
    const o = Zenon.winOrigin(anchorRoot.srcWin, anchorRoot.screen);
    const p = anchorRoot.srcWin.contentItem.mapFromItem(src, lx, ly);
    return Qt.point(o.x + p.x, o.y + p.y);
  }

  // Bound for a tooltip, latched for an interactive panel: the assignment
  // below replaces this binding the first time one opens, and re-runs on
  // every open after that, so the panel is placed once and then holds still.
  property point hotspot: anchorRoot.livePoint
  // Only something that was riding the pointer needs latching. A popout with
  // no cursorArea is placed off its anchor item, and that anchor moves — the
  // pill recentres itself as modules come and go — so it stays bound.
  onShowChanged: {
    if (anchorRoot.interactive && anchorRoot.cursorArea && anchorRoot.show)
      anchorRoot.hotspot = anchorRoot.livePoint;
  }

  // Pinned to the pointer and clamped so it never leaves the screen — ABOVE
  // it normally, and below it when the bar is at the top. A tooltip belonging
  // to a bar module has to open away from that bar: above the pointer with
  // the bar overhead, the clamp would pin it to y=0 and it would come up
  // underneath the very module it was describing.
  // ── THE CLAMPS KEEP THE CARD ON SCREEN, NOT THE SURFACE ──────────
  // With a shadow, the surface is `pad` bigger than the card on every
  // side, and that margin is transparent. Clamping the SURFACE to the
  // screen therefore pushed the card `pad` inward from every edge — and
  // against a bar at the bottom the bottom clamp is the binding one, so
  // a tooltip that should have sat on the pointer floated well above it.
  // Measured: 80px of daylight where 5 was asked for.
  //
  // Letting the surface hang off the edge by its own padding is exactly
  // right: there is nothing in that region but shadow, and the part
  // beyond the screen is not drawn.
  margins.left: !anchorRoot.srcWin || !anchorRoot.screen ? 0 :
    Math.round(Math.max(-anchorRoot.pad,
      Math.min(anchorRoot.hotspot.x - anchorRoot.implicitWidth / 2,
        anchorRoot.screen.width - anchorRoot.implicitWidth + anchorRoot.pad)))
  margins.top: !anchorRoot.srcWin || !anchorRoot.screen ? 0 :
    Math.round(Math.max(-anchorRoot.pad, Math.min(
      Zenon.barTop ? anchorRoot.hotspot.y + anchorRoot.gap - anchorRoot.pad
        : anchorRoot.hotspot.y - anchorRoot.gap
            - anchorRoot.implicitHeight + anchorRoot.pad,
      anchorRoot.screen.height - anchorRoot.implicitHeight + anchorRoot.pad)))
}
