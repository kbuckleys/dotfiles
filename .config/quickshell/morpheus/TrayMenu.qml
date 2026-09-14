// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "."

// THE SYSTEM TRAY'S MENU, which is a CardMenu like every other menu here.
//
// It used to be its own PanelWindow with its own rows, and it drifted: the
// label was centre-aligned where every other menu left-aligns, the type was a
// pixel small, the chevron was a glyph from a different font range, the tail
// column never collapsed, the parent row went dark the moment a submenu
// opened, and there was no open or close animation at all. None of that was
// deliberate — it was simply a second implementation of one object.
//
// What is genuinely its own: the rows come from DBus rather than from an
// array, the icons are image URLs an application supplies rather than font
// glyphs, and a submenu is a whole new TrayMenu because a DBus menu hands its
// children over one level at a time.
CardMenu {
  id: root

  required property var menuHandle
  // The tray icon this hangs off — only the ROOT menu has one. A submenu
  // hangs off a row of its parent card instead, which it can measure directly
  // rather than needing an item to point at.
  property Item anchorItem: null
  property var parentMenu: null
  property int parentRow: -1
  readonly property bool isSubMenu: root.parentMenu !== null

  property var childMenu: null
  signal menuClosed

  cardWidth: Zenon.menuWidth

  QsMenuOpener {
    id: opener
    menu: root.menuHandle
  }

  // DBus entries into the row shape every menu on this desktop speaks. The
  // icon goes in as `image` rather than `icon`: an application's own icon is
  // a URL, and no font glyph can stand in for it.
  model: {
    const kids = opener.children ? opener.children.values : [];
    const out = [];
    for (let i = 0; i < kids.length; ++i) {
      const e = kids[i];
      out.push({
        text: e.text || "",
        image: e.icon || "",
        hasChildren: e.hasChildren || false,
        isSeparator: e.isSeparator || false,
        enabled: e.enabled !== false,
        mark: e.checkState === 2 && !e.hasChildren
      });
    }
    return out;
  }

  // The entry behind a row, for the handlers below.
  function entryAt(i) {
    const kids = opener.children ? opener.children.values : [];
    return (i >= 0 && i < kids.length) ? kids[i] : null;
  }

  // ── where it goes ────────────────────────────────────────────────────
  // The anchor lives inside the bar, which is its own layer-shell surface
  // inset from the screen edges, so the item's coordinates are window-local.
  //
  // THROUGH Zenon.winOrigin, which is the shell's own converter and the same
  // one CursorAnchor uses. Doing it by hand as `margins.left + margins.top`
  // is only right for a window anchored to the TOP-LEFT: the pill is anchored
  // to the BOTTOM, where its origin is `screen.height - margins.bottom -
  // height` and not its top margin at all. Measured from the wrong edge the
  // menu was placed a whole screen away from the icon it belongs to.
  readonly property var srcWin: root.anchorItem ? root.anchorItem.QsWindow.window : null
  readonly property point srcPos: {
    if (!root.srcWin || !root.anchorItem || !root.screen) return Qt.point(0, 0);
    const o = Zenon.winOrigin(root.srcWin, root.screen);
    const p = root.srcWin.contentItem.mapFromItem(root.anchorItem, 0, 0);
    return Qt.point(o.x + p.x, o.y + p.y);
  }

  screen: root.isSubMenu ? root.parentMenu.screen
                         : (root.srcWin ? root.srcWin.screen : null)

  // A submenu hangs off its own row of the card above it; the root menu opens
  // UPWARD out of the bar, which is what it has under it. CardMenu clamps
  // either one into the screen, and flips a submenu that will not fit.
  // The pill's own top edge, which is what the menu has to clear. srcPos.y is
  // the ICON's top, and an icon is centred in the pill — so opening upward
  // from there buried the menu's bottom edge inside the bar instead of
  // standing it on top of it.
  readonly property real barTop: {
    if (!root.srcWin || !root.screen) return 0;
    return Zenon.winOrigin(root.srcWin, root.screen).y;
  }

  at: root.isSubMenu
    ? Qt.point(root.parentMenu.cardX + root.parentMenu.cardWidth,
               root.parentMenu.cardY + root.parentMenu.rowY(root.parentRow))
    // Left edge on the ICON it came from, bottom edge on the PILL it stands
    // on. Anything else and the menu belongs to the bar rather than to the
    // thing you clicked.
    : Qt.point(root.srcPos.x, root.barTop - root.contentH)

  hinged: root.isSubMenu
  flipFrom: root.isSubMenu
    ? root.parentMenu.cardX + root.parentMenu.cardWidth : 0
  flipParentLeft: root.isSubMenu ? root.parentMenu.cardX : 0

  // The row whose submenu is open stays lit while you are inside it.
  activeIndex: {
    if (!root.childMenu) return -1;
    const kids = opener.children ? opener.children.values : [];
    for (let i = 0; i < kids.length; ++i)
      if (kids[i] === root.childMenu.menuHandle) return i;
    return -1;
  }

  // A branch opens on hover and on click; everything else acts and closes.
  onHovered: i => { if (root.entryAt(i)?.hasChildren) root.openChild(i); }
  onChosen: i => {
    const e = root.entryAt(i);
    if (!e) return;
    if (e.hasChildren) { root.openChild(i); return; }
    e.triggered();
    root.closeMenu();
  }

  // ── the grab ─────────────────────────────────────────────────────────
  // Only the root menu owns one, and it covers the whole open submenu chain.
  // A grab per card would fight every other grab on screen.
  readonly property var grabWindows: {
    const out = [root];
    let m = root.childMenu;
    while (m) { out.push(m); m = m.childMenu; }
    return out;
  }

  HyprlandFocusGrab {
    windows: root.grabWindows
    active: root.open && !root.isSubMenu
    onCleared: root.closeMenu()
  }

  onVisibleChanged: { if (!root.visible) root.menuClosed(); }

  // `show`, not `open` — CardMenu already has an `open` PROPERTY, and a
  // function of the same name would shadow it.
  function show() { root.open = true; }

  function openChild(i) {
    const e = root.entryAt(i);
    if (!e) return;
    if (root.childMenu && root.childMenu.menuHandle === e) return;
    if (root.childMenu) { root.childMenu.closeMenu(); root.childMenu.destroy(); }
    const comp = Qt.createComponent("TrayMenu.qml");
    if (comp.status !== Component.Ready) return;
    root.childMenu = comp.createObject(root, {
      menuHandle: e, parentMenu: root, parentRow: i
    });
    if (root.childMenu) root.childMenu.show();
  }

  function closeMenu() {
    if (root.childMenu) {
      root.childMenu.closeMenu();
      root.childMenu.destroy();
      root.childMenu = null;
    }
    root.open = false;
  }
}
