// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┘┴└─┘
// https://github.com/kbuckleys/
//
// The drop shadow a layer casts on the desktop behind it. One definition, so
// the whole set can be retuned from Zenon rather than layer by layer, and so
// a layer picks it up in a single line:
//
//     LayerShadow { panel: bgRoot; morphed: popup.morphMode }
//
// It goes BEHIND its panel as a sibling, never as a child: a panel that clips
// (most of them do, to keep content inside their rounded corners) would clip
// its own shadow away.
//
// ── IT IS A MenuShadow NOW ──────────────────────────────────────────────
// This used to be its own RectangularShadow with its own tighter geometry,
// and that made a panel's shadow a different object from a menu's — a
// difference you could see wherever the two sat side by side.
//
// Two things came free with the change. The ring does not paint its own
// interior, so a TRANSLUCENT panel no longer sits on a black rectangle that
// reads straight through it. And the position comes from plain geometry
// bindings rather than `anchors.fill`, which inside a layer-shell window is
// resolved before quickshell has reparented either item, refused once with
// "Cannot anchor to an item that isn't a parent or sibling", and never
// retried — leaving the shadow at zero size. See MenuShadow's own note; it
// is the reason it was written that way.

import QtQuick
import "."

MenuShadow {
  id: root

  // A PANEL'S corner, not a menu's. Callers that know better still pass
  // their own, exactly as before.
  cornerRadius: Zenon.pillRadius

  // a layer that is currently wearing the pill must not cast a shadow — it is
  // the pill at that moment, and the pill is the ground floor
  property bool morphed: false

  // And this is where `morphed` was always meant to land. It was wired through
  // from every caller and then never read, so a morphed layer went on casting
  // its full shadow. Morphed, the layer's rect IS the pill's rect and this
  // window sits on the OVERLAY layer, above the bar: so that shadow was not
  // falling under anything, it was painting a black halo on top of the pill
  // and spilling past its border.
  //
  // Eased rather than switched, so handing the pill straight from one layer to
  // another cannot blink it.
  opacity: root.morphed ? 0 : 1
  Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
  visible: root.opacity > 0.01
}
