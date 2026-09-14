// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SHADOW A MENU CARD CASTS. One definition, worn by all four menus on
// this desktop — icarus', the tray's, terminus' right-click menu, and
// CardMenu — so they are the same object rather than four takes on one idea.
//
// It goes BEHIND its card as a sibling, never as a child: a card that clips
// (most of them do, to keep their content inside their rounded corners)
// would clip its own shadow away.
//
//     MenuShadow { panel: menuCard }
//
// IT IS A RING, NOT A BLOCK. RectangularShadow is a filled shape — like the
// CSS box-shadow it is modelled on, it paints its own interior, not only the
// falloff outside it. Behind an opaque card that costs nothing, because the
// card hides it. Behind a translucent one it reads straight through, the card
// composites to near solid, and the menu's own opacity stops meaning
// anything. So the card's footprint is punched out and what is left is the
// part that was ever meant to be seen: the edge.
//
// GEOMETRY, NOT ANCHORS, and that is not a style choice. `anchors.fill` onto
// a sibling inside a layer-shell window is resolved before quickshell has
// reparented either item into the window's content item, and Qt refuses it
// once with "Cannot anchor to an item that isn't a parent or sibling" and
// never tries again — leaving the shadow at zero size. Every icarus menu had
// one and none of them drew anything. Plain bindings have no such rule.

import QtQuick
import QtQuick.Effects
import "."

Item {
  id: root

  // the card this falls behind — tracked, so it follows every resize
  required property Item panel
  // THE CARD'S radius, not a number that happens to match it today. The hole
  // is cut to this, so a radius smaller than the card's leaves four dark
  // slivers inside its corners.
  property real cornerRadius: Zenon.menuRadius

  // EXACTLY the card's box, and that is load-bearing: every caller drives
  // this with `transformOrigin: Item.TopLeft` and `scale: card.scale` so the
  // shadow unfolds with the card. Grow the root to fit the falloff and that
  // origin would no longer be the card's corner, and the two would open out
  // of different points.
  x: root.panel ? root.panel.x : 0
  y: root.panel ? root.panel.y : 0
  width: root.panel ? root.panel.width : 0
  height: root.panel ? root.panel.height : 0
  z: -1

  // How far the shadow reaches past the card — the same number every caller
  // already leaves around a card inside its window, so nothing here can fall
  // outside the room reserved for it.
  property int reach: Zenon.menuShadowPad

  // WHAT IS CAST, as opposed to where. A menu casts a dark drop; howler's
  // critical toast casts red light with no offset at all. Same ring, same
  // punched-out middle, different lamp — so this stays one component rather
  // than growing a second one that differs by four numbers. Every default is
  // the menu's, so the four menus that ask for none of them are unchanged.
  property color ink: Zenon.menuShadowInk
  property real softness: Zenon.menuShadowBlur
  property real grow: Zenon.menuShadowGrow
  property real drop: Zenon.menuShadowDrop

  Item {
    id: group
    x: -root.reach
    y: -root.reach
    width: root.width + root.reach * 2
    height: root.height + root.reach * 2

    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: hole
      // The stencil marks the card. INVERTED, so what it marks is what goes
      // away and the edge around it is what stays.
      maskInverted: true
      maskThresholdMin: 0.5
    }

    RectangularShadow {
      x: root.reach
      y: root.reach
      width: root.width
      height: root.height
      radius: root.cornerRadius
      blur: root.softness
      spread: root.grow
      offset: Qt.vector2d(0, root.drop)
      color: root.ink
    }
  }

  // The card's footprint, in the group's own coordinates. Never drawn — it is
  // a texture the mask reads, which is why it carries a layer of its own and
  // why `visible: false` does not stop it existing.
  Item {
    id: hole
    x: group.x
    y: group.y
    width: group.width
    height: group.height
    visible: false
    layer.enabled: true

    Rectangle {
      x: root.reach
      y: root.reach
      width: root.width
      height: root.height
      radius: root.cornerRadius
      color: "white"
    }
  }
}
