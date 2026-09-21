// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
// ICARUS — desktop context menu, tray-menu styled, floating on focused monitor

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../oracle"
import "icarus.js" as Icarus

Item {
  id: root

  // shell passes focusedScreen here (like other popups)
  property var screen: null
  property point anchorPos: Qt.point(0, 0)
  property bool shown: false
  property string cwd: Quickshell.env("HOME") || "/"
  property var fileRows: []
  property string pendingConfirmId: ""
  property string childMenu: "" // "" | "apps" | "file" | "session" | "trash"

  // ── the trash ─────────────────────────────────────────────────────────
  // XDG's trash, wherever XDG_DATA_HOME points — not a path written out here.
  readonly property string trashDir:
    (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/Trash"
  property int trashCount: 0
  // Emptying is not undoable, so it takes two clicks: the row arms first and
  // says so. The confirm submenu this menu already has is wired to the session
  // entries by index, and generalising it was more surgery than one red row.
  property bool trashArmed: false
  // ── WHERE EACH SUBMENU HANGS FROM ───────────────────────────────────
  // Every row that has children reports its own offset inside the root card,
  // and its menu is placed against that. Read off the ROW rather than
  // computed, because an index times a row height is wrong the moment a row
  // above it is switched off in oracle — and because there is no single row
  // height anyway, separators being 7 and rows 30.
  //
  // This replaces three different rules that had grown up side by side:
  // trash and shell were already row-anchored; apps, home and recent pinned
  // themselves to the TOP of the root card regardless of which row they
  // belonged to; and session used `4 + 30 + 1 + 8 + 1`, a constant that was
  // true when session was the second thing in the menu and has been wrong
  // since — most recently by a whole Shell row. That constant is what made
  // the session menu open above its own row.
  // ASKED OF THE CARD, not reported by its rows. Every row used to push its
  // own y up here through noteRowY, because the card was hand-built and only
  // a delegate knew where it had landed. rootMenu is a CardMenu now and can
  // simply be asked — which also retires the whole reporting mechanism and
  // the stale-value bug it carried, where a row that stopped existing left
  // its last offset behind.
  function rowIndexOf(kind) {
    for (let i = 0; i < root.rootModel.length; ++i)
      if (root.rootModel[i].kind === kind) return i;
    return -1;
  }

  // The top margin a submenu belonging to `kind` should take, clamped so a
  // long one cannot hang off the bottom or the top of the screen. `bgH` is
  // the card's own height, without the shadow padding around it.
  function submenuTop(kind, bgH) {
    if (!root.screen) return 0;
    const pad = Zenon.menuShadowPad;
    const gap = Zenon.padScreen;
    const i = root.rowIndexOf(kind);
    let bgY = rootMenu.cardY + (i >= 0 ? rootMenu.rowY(i) : 0);
    if (bgY + bgH > root.screen.height - gap) bgY = root.screen.height - bgH - gap;
    if (bgY < gap) bgY = gap;
    return bgY - pad;
  }

  // ── WHAT ARTEMIS HAS LEARNED ──────────────────────────────────────────
  // The finder keeps a frecency map — path to how often you have opened it —
  // and it is the most useful list of paths on this machine. It lived behind
  // opening artemis and typing; here it is a submenu off the desktop.
  //
  // Read from artemis's own state file rather than asked for over IPC: there
  // is nothing to ask, the file IS the answer, and a menu that has to wait for
  // a round trip before it can draw its rows is a menu that flickers.
  FileView {
    id: artemisState
    path: Quickshell.statePath("artemis.json")
    blockLoading: true
    printErrors: false
  }

  readonly property var recentEntries: {
    let freq = ({});
    try {
      const j = JSON.parse(artemisState.text() || "{}");
      freq = j.freq || ({});
    } catch (e) {
      return [];
    }
    const keys = [];
    for (const k in freq) keys.push(k);
    // The same order artemis shows them in: most reached for first, and the
    // path itself breaking ties so the list does not shuffle between opens.
    keys.sort((a, b) => (freq[b] - freq[a]) || (a < b ? -1 : 1));
    const out = [];
    const cap = Oracle.menuRecentCount;
    for (let i = 0; i < keys.length && out.length < cap; ++i) {
      const p = keys[i];
      const bare = p.replace(/\/+$/, "");
      const cut = bare.lastIndexOf("/");
      out.push({ path: p, isDir: /\/$/.test(p),
                 text: cut < 0 ? bare : bare.slice(cut + 1) });
    }
    return out;
  }
  // ── the shell's own menu ─────────────────────────────────────────────
  // Restarting the panels used to sit at the bottom of the session list,
  // because that is where the "start something over" verbs were. It is not a
  // session action: ending a session and reloading a bar have nothing in
  // common but a vague sense of beginning again, and the SETTINGS — which
  // belong beside it — had no home in that list at all.
  //
  // Both are about this shell, so they are a menu about this shell. Neither
  // confirms: one opens a panel, and the other is over in a second with
  // nothing lost.
  // Backgrounds come first: it is the lightest thing here, it opens a panel
  // and changes nothing on its own, and it used to sit out on the root menu
  // among the PLACES — which is a list of things to open, not a list of
  // things to change. Still behind its own setting, which is why this is
  // built rather than written out.
  property var shellEntries: {
    const out = [];
    if (Oracle.menuShowBackground)
      out.push({ id: "background", text: "Set background", icon: "\uF03E",
                 cmd: "qs ipc call Picasso toggle" });
    // A note is made from here because here is where you are when you want
    // one: the desktop, with nothing else open. It needs no panel of its own
    // — the note IS the panel.
    out.push({ id: "note", text: "New note", icon: "\uF24A",
               cmd: "qs ipc call Clio add" });
    return out;
  }

  // ── AND THE TWO THAT ARE ABOUT THE SHELL ITSELF ───────────────────────
  // Set background and New note act on the desktop in front of you, so they
  // stay out on the root menu where a click reaches them. These two act on
  // the shell drawing that desktop — one opens its settings, the other
  // throws it away and starts it again — and that is a different subject
  // and a heavier one. Behind a door, where a mis-click cannot reach them.
  readonly property var shellOnlyEntries: [
    { id: "settings", text: "Settings", icon: "\uF013",
      cmd: "qs ipc call Oracle toggle" },
    // `qs kill` before the relaunch, in that order, in a shell that has
    // already been detached — so the replacement is never a child of the
    // instance it replaces. `-d` stays for exactly that reason: unlike the
    // hypr autostart, where there is no controlling terminal to detach
    // from and the flag buys nothing, here it is load-bearing.
    //
    // `-n` is the guard: if `qs kill` did not take, the relaunch declines
    // rather than leaving two shells fighting over the same layer surfaces
    // and the same state files under by-shell/<hash>.
    { id: "restart", text: "Restart Shell", icon: "\uF01E",
      cmd: "qs kill; sleep 0.4; qs -n -d" }
  ]

  property var sessionEntries: [
    { id: "lockscreen", text: "Lock",  icon: "\uF023", cmd: "sleep 0.35 && qs ipc call Cerberus lock", confirm: false },
    { id: "logout",     text: "Logout",      icon: "\uF08B", cmd: "hyprshutdown -p 'loginctl terminate-session " + (Quickshell.env("XDG_SESSION_ID") || "") + "'", confirm: true },
    { id: "suspend",    text: "Suspend",     icon: "\uF186", cmd: "systemctl suspend", confirm: true },
    { id: "reboot",     text: "Reboot",      icon: "\uF021", cmd: "hyprshutdown -p 'systemctl reboot'", confirm: true },
    { id: "shutdown",   text: "Shutdown",    icon: "\uF011", cmd: "hyprshutdown -p 'systemctl poweroff'", confirm: true }
  ]

  // for grab
  readonly property var grabWindows: {
    const out = [rootMenu];
    if (appsMenu.visible) out.push(appsMenu);
    if (fileMenu.visible) out.push(fileMenu);
    if (sessionMenu.visible) out.push(sessionMenu);
    if (shellMenu.visible) out.push(shellMenu);
    if (trashMenu.visible) out.push(trashMenu);
    if (recentMenu.visible) out.push(recentMenu);
    if (confirmMenu.visible) out.push(confirmMenu);
    return out;
  }

  // ── ONE ICON FAMILY, AND WHY IT MATTERS ──────────────────────────────
  // Every glyph in this menu — these rows, the session list, the shell list,
  // the chevrons, the per-application icon — comes from Nerd Fonts' Font
  // Awesome range, U+F000 to U+F2FF, and nothing else may be added from
  // anywhere else.
  //
  // This menu had collected four families: Font Awesome, Codicons (U+EAxx),
  // Material Design (U+F0xxx) and one bare Unicode power symbol. They are
  // drawn on different em squares, so at a single font.pixelSize they come
  // out at visibly different sizes — the Material ones oversized, the
  // Codicons small — and a column of icons that are meant to read as one
  // column instead reads as a ransom note. Nothing is wrong with any
  // individual glyph; the problem is only ever the mixture.
  //
  // centred model for root: files, recent, apps, home, trash, then this
  // shell — which is where backgrounds live now — and the session it is
  // running in.
  //
  // BUILT rather than written out, because three of these rows are switches in
  // oracle now. A literal list with `enabled: false` on a switched-off row
  // would still DRAW it — greyed out and unreachable, which reads as "this is
  // broken" where the truth is "you asked for it not to be here". So a row
  // that is off is not in the list at all, and the SEPARATORS are placed
  // around whatever survived rather than written between fixed rows:
  // switching off the last row of a group otherwise leaves a rule with
  // nothing under it.
  readonly property var rootModel: {
    const rows = [];
    const sep = () => {
      // never lead with a rule, and never two in a row
      if (rows.length === 0) return;
      if (rows[rows.length - 1].isSeparator) return;
      rows.push({ text: "", icon: "", hasChildren: false,
                  isSeparator: true, enabled: false });
    };

    // First, because it is the thing this menu is most often opened to reach.
    // No children: it opens a window, so there is no menu level to walk into.
    if (Oracle.menuShowFiles)
      rows.push({ text: "Files", icon: "\uF114", hasChildren: false,
                  kind: "terminus", isSeparator: false, enabled: true });
    // What artemis has learned you open. The finder ranks by how often you
    // reach for a thing, and that ranking is the most useful list of paths on
    // this machine — and it was reachable only by opening artemis and typing.
    // Muted when it has learned nothing yet, the way the trash is.
    if (Oracle.menuShowRecent)
      rows.push({ text: "Recent", icon: "\uF1DA", hasChildren: true,
                  kind: "recent", isSeparator: false,
                  enabled: root.recentEntries.length > 0 });
    sep();
    if (Oracle.menuShowApps)
      rows.push({ text: "Apps", icon: "\uF009", hasChildren: true,
                  kind: "apps", isSeparator: false, enabled: true });
    if (Oracle.menuShowHome)
      rows.push({ text: "Home", icon: "\uF46D", hasChildren: true,
                  kind: "file", isSeparator: false, enabled: true });
    // Muted when there is nothing in it — an empty trash is still worth
    // SEEING, so you know where it is and that it is empty, but there is
    // nothing to open and nothing to empty, and a row offering both would
    // be lying about what it can do.
    if (Oracle.menuShowTrash)
      rows.push({ text: root.trashCount > 0
                    ? "Trash (" + root.trashCount + ")" : "Trash",
                  icon: "\uF014", hasChildren: false, kind: "trash",
                  isSeparator: false, enabled: root.trashCount > 0 });
    sep();
    // ── THE SHELL'S OWN ENTRIES, ON THE MENU ITSELF ────────────────────
    // They were behind a "Shell" row that opened a card with four things in
    // it. A submenu earns its place by holding more than fits or more than
    // you want to read at once; this held a note, a background, the settings
    // and a restart — four leaves behind one door, each one a click further
    // away than it needed to be.
    //
    // Built from the same shellEntries the card was built from, so what is
    // offered and what it does are still written down once.
    for (let i = 0; i < root.shellEntries.length; ++i) {
      const e = root.shellEntries[i];
      rows.push({ text: e.text, icon: e.icon, hasChildren: false,
                  kind: "shellcmd", cmd: e.cmd,
                  isSeparator: false, enabled: true });
    }
    // A RULE OF ITS OWN. Everything above acts on this desktop — open a
    // thing, set a background, write a note. Below are the two subjects that
    // are about the machinery instead: the shell drawing the desktop, and
    // the session the whole lot runs in.
    sep();
    // The shell's own pair, behind their own door — see shellOnlyEntries.
    rows.push({ text: "Shell", icon: "\uF120", hasChildren: true,
                kind: "shell", isSeparator: false, enabled: true });
    rows.push({ text: "Session", icon: "\uF2C0", hasChildren: true,
                kind: "session", isSeparator: false, enabled: true });
    return rows;
  }

  function openAt(pos, clickedScreen) {
    // clickedScreen is the monitor where the right-click landed. The spec
    // says "on focused monitor" — the click focuses that monitor, so by the
    // time the handler fires focusedScreen === clickedScreen. Honour the
    // explicit screen to avoid a one-frame race where the binding hasn't
    // caught up yet.
    if (clickedScreen) root.screen = clickedScreen;
    root.anchorPos = pos;
    // keep cwd fresh
    root.cwd = Quickshell.env("HOME") || root.cwd;
    root.pendingConfirmId = "";
    root.childMenu = "";
    // artemis writes this as you use it, so it is re-read on the way in
    artemisState.reload();
    root.shown = true;
    root.stopBranches("");
    refreshFiles();
    refreshTrash();
  }

  // Where the pointer actually is, for the keybind path. The desktop catcher
  // hands over its own click point; opening from IPC had nothing to hand over
  // and used the middle of the screen — the one place a context menu should
  // never appear.
  //
  // hyprctl rather than a cursor property: quickshell's Hyprland module does
  // not expose one. A subprocess, but only on the open, and nothing is drawn
  // until the answer is back.
  function openAtCursor() {
    cursorProc.running = true;
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // "2186, 774", in hyprland's global logical space
        const m = String(text).trim().match(/(-?\d+)\s*,\s*(-?\d+)/);
        if (!m) {
          root.openAt(Qt.point(root.screen ? root.screen.width / 2 : 200,
                               root.screen ? root.screen.height / 2 : 200), root.screen);
          return;
        }
        const gx = parseInt(m[1], 10);
        const gy = parseInt(m[2], 10);
        // which monitor that global point is on, and where it sits inside it
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; ++i) {
          const sc = screens[i];
          if (gx >= sc.x && gx < sc.x + sc.width && gy >= sc.y && gy < sc.y + sc.height) {
            root.openAt(Qt.point(gx - sc.x, gy - sc.y), sc);
            return;
          }
        }
        root.openAt(Qt.point(gx, gy), root.screen);
      }
    }
  }

  function onAppChosen(entry) {
    if (!entry || !entry.id) return;
    // Desktop.launchCommand, for the Terminal=true entries gtk-launch drops on
    // the floor — and because quoting a shell argument by hand here was a
    // fourth copy of the function Strings exists to be.
    Quickshell.execDetached(["sh", "-c", Desktop.launchCommand(entry.id, "")]);
    root.closeAll();
  }

  function closeAll() {
    root.shown = false;
    root.childMenu = "";
    root.pendingConfirmId = "";
  }

  function execCmd(cmd) {
    Quickshell.execDetached(["sh", "-c", cmd + " >/dev/null 2>&1 &"]);
  }

  function refreshFiles() {
    listProc.command = ["sh", "-c", Icarus.listCommand(root.cwd)];
    listProc.running = true;
  }

  function refreshTrash() {
    root.trashArmed = false;
    trashProc.command = ["sh", "-c",
      "ls -A1 " + Strings.shellQuote(root.trashDir + "/files") + " 2>/dev/null | wc -l"];
    trashProc.running = true;
  }

  // ── WHAT A ROW OF THE ROOT MENU DOES ──────────────────────────────────
  // Lifted out of the row delegate when the card became a CardMenu. A branch
  // arms its hover timer and puts away whatever else was open; a target opens
  // nothing and closes the branches, because a row you are about to click is
  // not a row you are browsing past.
  function rowEntered(m) {
    if (!m) return;
    if (m.kind === "trash" || m.kind === "shellcmd") {
      root.stopBranches("");
      if (root.childMenu !== "trash") root.childMenu = "";
    } else if (m.kind === "apps") {
      root.stopBranches("apps");
      root.armBranch("apps");
    } else if (m.kind === "file") {
      root.stopBranches("file");
      root.armBranch("file");
    } else if (m.kind === "session") {
      root.stopBranches("session");
      root.armBranch("session");
    } else if (m.kind === "shell") {
      root.stopBranches("shell");
      root.armBranch("shell");
    } else if (m.kind === "recent") {
      root.stopBranches("recent");
      root.armBranch("recent");
    }    else if (m.kind === "terminus") {
      root.stopBranches("");
      root.childMenu = "";
    }
  }

  // The LEFT button's answer. CardMenu has already flashed the row by the
  // time this runs — the flash is its reply to the click, and the action is
  // what happens at the end of it — so nothing here fires one.
  function rowChosen(m) {
    if (!m) return;
    if (m.kind === "trash") { root.openTrash(); return; }
    if (m.kind === "shellcmd") {
      root.execCmd(m.cmd);
      root.closeAll();
      return;
    }
    if (m.kind === "apps")        root.childMenu = "apps";
    else if (m.kind === "file")   root.childMenu = "file";
    else if (m.kind === "session") root.childMenu = "session";
    else if (m.kind === "shell")  root.childMenu = "shell";
    else if (m.kind === "recent") root.childMenu = "recent";
    else if (m.kind === "terminus") {
      // Reveal, not navigate — see revealTerminus.
      root.revealTerminus();
      root.closeAll();
    }
  }

  function openTrash() {
    // TERMINUS, not whatever xdg-open hands a directory to. Every other place
    // icarus opens — a recent folder, a browsed one — goes to terminus, and
    // the trash is a folder like any other.
    root.openInTerminus(root.trashDir + "/files");
    root.closeAll();
  }

  // Both halves: the files themselves and the .trashinfo records pointing at
  // them. Deleting only one leaves a trash no file manager agrees about.
  function emptyTrash() {
    const files = Strings.shellQuote(root.trashDir + "/files");
    const info = Strings.shellQuote(root.trashDir + "/info");
    root.execCmd("rm -rf -- " + files + "/* " + files + "/.[!.]* "
      + info + "/* " + info + "/.[!.]* 2>/dev/null; true");
    root.trashCount = 0;
    root.closeAll();
  }

  Process {
    id: trashProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.trashCount = parseInt(String(text).trim(), 10) || 0
    }
  }

  function goParent() {
    const p = Icarus.dirname(root.cwd);
    if (p !== root.cwd) {
      root.cwd = p;
      root.pendingConfirmId = "";
    }
  }

  // A SECOND WINDOW IF ONE IS ALREADY UP. `open` reuses window 0, which is
  // right when terminus is put away and wrong when it is on screen — asking
  // for a file manager while looking at one means you want another, not that
  // one navigated out from under you. `windows` reports each window's state,
  // so the shell picks between the two verbs.
  // ── WHAT SUPER+E DOES, AND NOTHING ELSE ──────────────────────────────
  // The Files entry used to hand Terminus the desktop's current directory.
  // That is a destination, so the window always arrived somewhere instead
  // of coming back where you left it — and openInTerminus spawns a second
  // window when one is already up, so "Files" kept making new ones.
  //
  // SUPER+E sends no path at all, and the manager treats that as a reveal
  // rather than a navigation: a hidden window is still where it was. This
  // is the same call, so the two entry points cannot drift.
  //
  // openInTerminus below keeps taking a path, because its other callers —
  // the trash, and a directory you picked out of the browser — are asking
  // for somewhere specific.
  function revealTerminus() {
    root.execCmd("qs ipc call Terminus spawn ''");
  }

  function openInTerminus(where) {
    const q = Strings.shellQuote(where);
    root.execCmd(
      "if qs ipc call Terminus windows 2>/dev/null | grep -q ' shown '; "
      + "then qs ipc call Terminus spawn " + q + "; "
      + "else qs ipc call Terminus open " + q + "; fi");
  }

  function onFileChosen(entry) {
    if (entry.isParent) {
      goParent();
      return;
    }
    if (entry.isDir) {
      root.cwd = entry.path;
      return;
    }
    root.execCmd(Icarus.openCommand(entry.path));
    root.closeAll();
  }

  function onSessionChosen(entry) {
    if (!entry) return;
    if (entry.confirm) {
      root.pendingConfirmId = entry.id;
      // keep session menu open, show confirm as its child
      return;
    }
    root.execCmd(entry.cmd);
    root.closeAll();
  }

  // Every branch row opens its own submenu and closes the other four. That was
  // five copies of the same four stop() calls, one of which had to be edited
  // each time a branch was added — and adding Shell would have made it six
  // copies of five. One list, named by the branch that is being kept.
  // ── OPENING A BRANCH ON HOVER ─────────────────────────────────────────
  // A submenu that opened the instant the pointer crossed its row would
  // flicker open and shut all the way down a menu. It waits instead, and the
  // wait is cancelled by moving onto anything else.
  //
  // ONE timer. There were five, identical but for the kind they opened, and
  // every caller had to remember to stop the other four.
  readonly property int branchDelay: 140
  property string pendingBranch: ""

  Timer {
    id: branchTimer
    interval: root.branchDelay
    onTriggered: if (root.pendingBranch !== "") root.childMenu = root.pendingBranch;
  }

  function armBranch(kind) {
    root.pendingBranch = kind;
    branchTimer.restart();
  }

  function stopBranches(keep) {
    if (root.pendingBranch !== keep) {
      root.pendingBranch = "";
      branchTimer.stop();
    }
  }

  function sessionEntryById(id) {
    for (let i = 0; i < root.sessionEntries.length; ++i)
      if (root.sessionEntries[i].id === id) return root.sessionEntries[i];
    return null;
  }

  // ── autofit + directional placement helpers ──────────────────────────
  function availBelow(anchor, screenH, pad) { return Math.max(0, screenH - anchor - pad); }
  function availAbove(anchor, pad) { return Math.max(0, anchor - pad); }
  function chooseY(anchor, bgH, screenH, pad) {
    const below = availBelow(anchor, screenH, pad);
    const above = availAbove(anchor, pad);
    if (bgH <= below) return anchor;
    if (bgH <= above) return anchor - bgH;
    // not enough space either side — clamp to screen and reduce height elsewhere
    return Math.max(pad, Math.min(anchor, screenH - bgH - pad));
  }
  function chooseX(anchor, bgW, screenW, pad) {
    const right = Math.max(0, screenW - anchor - pad);
    const left = Math.max(0, anchor - pad);
    if (bgW <= right) return anchor;
    if (bgW <= left) return anchor - bgW;
    return Math.max(pad, Math.min(anchor, screenW - bgW - pad));
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const rows = Icarus.parseLsOutput(text, root.cwd);
        // prepend ".." parent entry
        const parentEntry = { name: "..", path: Icarus.dirname(root.cwd), isDir: true, isParent: true, isHidden: false };
        root.fileRows = [parentEntry].concat(rows);
      }
    }
  }

  onCwdChanged: refreshFiles()

  // ── WHAT A DRAG IS CARRYING ─────────────────────────────────────────
  // Off screen and never seen directly: it exists to be photographed. The
  // labels are filled in, the picture is taken, and the drag carries the
  // photograph — the same card terminus and artemis put beside the cursor.
  //
  // Without it a drag out of here was an invisible one: the menu is gone the
  // moment you drop, and between picking a row up and letting go there was
  // nothing on screen saying which row it was.
  property string dragLabel: ""
  property string dragGlyph: ""
  property color dragInk: Zenon.white
  // The grab result is HELD, not discarded. It owns the image the compositor
  // is still reading from; let it go and the drag can end up carrying nothing.
  property var dragGrab: null

  // A failed grab is not a reason to refuse the drag; it just goes without a
  // picture, which is what it did before there was one.
  function dragPicture(label, glyph, ink, then) {
    root.dragLabel = label;
    root.dragGlyph = glyph;
    root.dragInk = ink;
    if (!dragCard.grabToImage(function(res) { root.dragGrab = res; then(res.url); }))
      then("");
  }

  // ── THE ROW FLASHES, THEN THE THING HAPPENS ───────────────────────────
  // Lifted whole from terminus' context menu, which is where the argument
  // for it is: a menu that disappears on mouse-down leaves you unsure which
  // row you hit, and for the entries that log you out that is a bad moment
  // to be unsure in. The delay is long enough to see and short enough that
  // it is not a wait.
  //
  // A row hands its work over rather than doing it — `fire(act)` — so the
  // action runs on the far side of the flash and every row that does
  // something confirms itself the same way. Rows that merely open a submenu
  // do NOT use this: nothing has happened yet, and 190ms between pointing at
  // a branch and seeing it is a menu that feels slow.
  component ChosenFlash: Item {
    id: flash
    anchors.fill: parent
    z: 3
    property var pending: null
    property real chosen: 0
    readonly property bool running: flashAnim.running

    function fire(act) {
      flash.pending = act;
      flashAnim.restart();
    }

    SequentialAnimation {
      id: flashAnim
      NumberAnimation { target: flash; property: "chosen"; to: 1;
                        duration: 60; easing.type: Easing.OutQuad }
      NumberAnimation { target: flash; property: "chosen"; to: 0;
                        duration: 130; easing.type: Easing.InQuad }
      ScriptAction {
        script: {
          const act = flash.pending;
          flash.pending = null;
          if (act) act();
        }
      }
    }

    Rectangle {
      anchors.fill: parent
      visible: flash.chosen > 0
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                     0.55 * flash.chosen)
    }
  }

  // ── root menu ────────────────────────────────────────────────────────
  CardMenu {
    id: rootMenu
    screen: root.screen
    model: root.rootModel
    cardWidth: Zenon.menuWidth
    open: root.shown

    // OPENED AT THE POINTER, so it flips around it rather than clamping: a
    // menu near an edge should open the other way, not slide across the
    // cursor that asked for it. chooseX/chooseY are icarus' own and know
    // about the space above and below; CardMenu is handed the answer.
    at: {
      if (!root.screen) return Qt.point(0, 0);
      const gap = Zenon.padScreen;
      return Qt.point(
        root.chooseX(root.anchorPos.x, Zenon.menuWidth, root.screen.width, gap),
        root.chooseY(root.anchorPos.y, rootMenu.contentH, root.screen.height, gap));
    }

    // The branch whose card is open stays lit while you are inside it. This
    // was six `kind === ... && childMenu === ...` clauses spelled out.
    activeIndex: {
      if (!root.childMenu) return -1;
      for (let i = 0; i < root.rootModel.length; ++i)
        if (root.rootModel[i].kind === root.childMenu) return i;
      return -1;
    }

    onHovered: i => root.rowEntered(root.rootModel[i])
    onChosen: i => root.rowChosen(root.rootModel[i])
    // The trash row is the one with two answers: its card on the right
    // button, the folder itself on the left.
    onSecondary: i => {
      const m = root.rootModel[i];
      if (!m || m.kind !== "trash") return;
      root.trashArmed = false;
      root.childMenu = "trash";
    }

    HyprlandFocusGrab {
      windows: root.grabWindows
      active: root.shown
      onCleared: root.closeAll()
    }

    Item {
      id: rootMenuContent
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: (e) => { e.accepted = true; root.closeAll(); }
      Keys.onLeftPressed: (e) => { e.accepted = true; root.childMenu = ""; }
      Keys.onRightPressed: (e) => {
        e.accepted = true;
        if (root.childMenu === "") root.childMenu = "file";
      }
    }

    Item {
      id: dragCard
      opacity: 0
      z: -100
      x: -4000
      height: 38

      // SIZED FROM THE TEXT rather than from a laid-out row, and anchored
      // rather than positioned, because grabToImage reads the width in the
      // same tick the labels are filled in — a Row would not have set its own
      // width yet, and the first drag of every session would carry a card cut
      // to a few pixels.
      readonly property real pad: 12
      width: dragCard.pad * 2 + dragCardGlyph.implicitWidth
        + (root.dragGlyph !== "" ? 8 : 0) + dragCardLabel.implicitWidth

      Rectangle {
        anchors.fill: parent
        radius: Zenon.menuRadius
        color: Zenon.layerBg
        border.width: 1
        border.color: Zenon.cyan
      }

      Text {
        id: dragCardGlyph
        anchors.left: parent.left
        anchors.leftMargin: dragCard.pad
        anchors.verticalCenter: parent.verticalCenter
        text: root.dragGlyph
        color: root.dragInk
        font.family: Zenon.faceFixed
        font.pixelSize: 16
      }

      Text {
        id: dragCardLabel
        anchors.left: dragCardGlyph.right
        anchors.leftMargin: root.dragGlyph !== "" ? 8 : 0
        anchors.verticalCenter: parent.verticalCenter
        text: root.dragLabel
        color: Zenon.white
        font.family: Zenon.face
        font.pixelSize: 15
      }
    }
  }

  // ── trash context menu ──────────────────────────────────────────
  // The trash's own menu, on right-click. Placed against the trash ROW rather
  // than the pointer, the way every other submenu here is placed against the
  // row it belongs to.
  CardMenu {
    id: trashMenu
    screen: root.screen
    cardWidth: 180
    open: root.shown && root.childMenu === "trash"
    hinged: true
    flipFrom: rootMenu.margins.left + Zenon.menuShadowPad + Zenon.menuWidth
    flipParentLeft: rootMenu.margins.left + Zenon.menuShadowPad
    at: Qt.point(0, root.submenuTop("trash", trashMenu.contentH)
                    + Zenon.menuShadowPad)

    // Emptying cannot be undone, so the row arms on the first click and acts
    // on the second. `danger` turns it red while it is armed — arming is not
    // an event, so it does not flash; the row going red is the reply.
    model: [
      { text: "Open" },
      { text: "Empty Trash", danger: root.trashArmed, asks: !root.trashArmed }
    ]

    onChosen: index => {
      if (index === 0) { root.openTrash(); return; }
      if (!root.trashArmed) { root.trashArmed = true; return; }
      root.emptyTrash();
    }
    // moving off the armed row disarms it, so it cannot sit primed waiting
    // for a stray click later
    onUnhovered: index => { if (index === 1) root.trashArmed = false; }
  }

  // ── artemis's recent paths ──────────────────────────────────────
  // The finder's own ranking, as a submenu. Same shape as the trash menu it
  // sits below — placed against its row, closing the whole stack when
  // something is chosen — because a submenu that behaves differently from the
  // one above it is a second thing to learn.
  CardMenu {
    id: recentMenu
    screen: root.screen
    cardWidth: 300
    open: root.shown && root.childMenu === "recent"
    // recentEntries carry a path and a name but no glyph — the same folder
    // and file marks the file browser uses, so a recent place and the same
    // place found by browsing read identically.
    model: root.recentEntries.map(e => ({
      text: e.text, icon: e.isDir ? "\udb80\ude4b" : "\uf15b"
    }))
    hinged: true
    flipFrom: rootMenu.margins.left + Zenon.menuShadowPad + Zenon.menuWidth
    flipParentLeft: rootMenu.margins.left + Zenon.menuShadowPad
    at: Qt.point(0, root.submenuTop("recent", recentMenu.contentH)
                    + Zenon.menuShadowPad)

    onChosen: index => {
      const e = root.recentEntries[index];
      if (!e) return;
      if (e.isDir) root.openInTerminus(e.path);
      else root.execCmd(Icarus.openCommand(e.path));
      root.closeAll();
    }
  }

  // ── apps submenu ────────────────────────────────────────────────
  PanelWindow {
    // OVERLAY, like every other popup this shell puts up. These eight set no
    // layer at all, which left the desktop menu on Top while the pill's
    // panels sat on Overlay above it — a menu opened over a panel went
    // behind it. Within a layer the last surface mapped is the top one, and
    // a menu maps when you open it, so this puts it where it belongs.
    WlrLayershell.layer: WlrLayer.Overlay
    id: appsMenu
    property bool wanted: root.shown && root.childMenu === "apps"
    property real shade: 0
    onWantedChanged: appsMenu.shade = appsMenu.wanted ? 1 : 0
    Behavior on shade {
      NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
    }
    visible: appsMenu.wanted || appsMenu.shade > 0.01
    focusable: false
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region { item: appsBg }
    anchors { top: true; left: true }
    screen: root.screen
    implicitWidth: 300 + Zenon.menuShadowPad * 2
    implicitHeight: {
      if (!root.screen) return 300 + Zenon.menuShadowPad * 2;
      const maxBgH = root.screen.height - Zenon.menuShadowPad * 2;
      return Math.min(appsContent.implicitHeight + 8, maxBgH) + Zenon.menuShadowPad * 2;
    }

    margins.left: {
      if (!root.screen || !rootMenu.visible) return 0;
      return Math.round(Zenon.hingeX(
        rootMenu.cardX, Zenon.menuWidth, 300,
        root.screen.width, Zenon.padScreen)) - Zenon.menuShadowPad;
    }
    margins.top: root.submenuTop("apps",
      appsMenu.implicitHeight - Zenon.menuShadowPad * 2)

    ClippingRectangle {
      id: appsBg
      anchors.fill: parent
      anchors.margins: Zenon.menuShadowPad
      transformOrigin: Item.TopLeft
      scale: Zenon.menuScale(appsMenu.shade)
      opacity: appsMenu.shade
      color: Zenon.menuBg
      border.color: Zenon.surfaceBorder
      border.width: 1
      radius: Zenon.menuRadius
      topLeftRadius: 0
      topRightRadius: Zenon.menuRadius
      bottomLeftRadius: 0
      bottomRightRadius: Zenon.menuRadius

      Column {
        id: appsContent
        anchors.fill: parent
        anchors.margins: Zenon.menuCardPad
        spacing: 0

        // ── the scroll, and why it is an overlay ──────────────────────
        // A WheelHandler declared inside a Flickable NEVER FIRES. Flickable's
        // default property parents non-Item children to contentItem as a plain
        // QObject, so the handler is registered on no item at all and is never
        // offered an event — verified with a logging handler inside the very
        // view the wheel was visibly scrolling, which logged nothing while a
        // console.log elsewhere logged fine. The 5.6x speed this asked for had
        // therefore never once applied; what you felt was Qt's built-in wheel
        // step, and the code saying otherwise sat here looking correct.
        //
        // A MouseArea over the view does get them. NoButton is what makes it
        // safe to lay over everything: it never takes a press, so clicking and
        // hovering the rows underneath are untouched.
        //
        // The wrapper exists because the MouseArea cannot be a CHILD of the
        // Flickable for the same reason the handler failed — anything Item
        // shaped goes into contentItem and scrolls away with the content.
        Item {
          width: parent.width
          height: {
            if (!root.screen) return Math.min(500, appsRepeaterHolder.childrenRect.height);
            const maxH = root.screen.height - Zenon.menuShadowPad * 2 - 12;
            return Math.min(appsRepeaterHolder.childrenRect.height, Math.max(120, maxH - 6));
          }

        Flickable {
          id: appsFlick
          // Finder's rubber band and the smooth wheel notch, one rule for
          // the whole shell — see morpheus/Elastic.qml. Inside the view
          // rather than over it: it pins itself to the viewport.
          ElasticScroll { view: appsFlick }
          anchors.fill: parent
          clip: false
          contentWidth: width
          contentHeight: appsRepeaterHolder.childrenRect.height
          boundsBehavior: Flickable.StopAtBounds
          flickDeceleration: 1800
          maximumFlickVelocity: 2800

          Column {
            id: appsRepeaterHolder
            width: parent.width
            spacing: 0

            Repeater {
              id: appsRepeater
              model: DesktopEntries.applications

              delegate: Item {
                id: appEntry
                required property var modelData
                required property int index
                width: appsRepeaterHolder.width
                height: Zenon.menuRowHeight

                Rectangle {
                  anchors.fill: parent
                  radius: 0
                  color: appHover.containsMouse ? Zenon.headBg : "transparent"
                }

                Item {
                  anchors.fill: parent
                  anchors.leftMargin: 12
                  anchors.rightMargin: 10

                  // NO GLYPH. Every row here carried the same one — a generic
                  // \uF108 standing in for an icon this menu does not look
                  // up — so it was a column of identical marks saying nothing
                  // about the thing beside it. A list of names is a list of
                  // names.
                  Text {
                    id: appLabel
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignLeft
                    text: modelData.name || ""
                    elide: Text.ElideRight
                    color: Zenon.white
                    font.family: Zenon.face
                    font.weight: Font.Medium
                    font.pixelSize: 16
                  }
                }

                ChosenFlash { id: appFlash }

                MouseArea {
                  id: appHover
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !appFlash.running
                  onClicked: appFlash.fire(() => root.onAppChosen(appEntry.modelData))
                }
              }
            }
          }
        }

          MouseArea {
            anchors.fill: parent
            z: 1
            acceptedButtons: Qt.NoButton
            onWheel: (w) => {
              const dy = w.angleDelta.y;
              if (dy === 0) { w.accepted = w.angleDelta.x !== 0; return; }
              const most = Math.max(0, appsFlick.contentHeight - appsFlick.height);
              appsFlick.contentY = Math.max(0, Math.min(most,
                appsFlick.contentY + (dy > 0 ? -1 : 1) * 90 * 5.6));
              w.accepted = true;
            }
          }
        }
      }
    }

    MenuShadow {
      panel: appsBg
      opacity: appsMenu.shade
      transformOrigin: Item.TopLeft
      scale: appsBg.scale
    }
  }

  // ── file browser submenu ──────────────────────────────────────────
  PanelWindow {
    // OVERLAY, like every other popup this shell puts up. These eight set no
    // layer at all, which left the desktop menu on Top while the pill's
    // panels sat on Overlay above it — a menu opened over a panel went
    // behind it. Within a layer the last surface mapped is the top one, and
    // a menu maps when you open it, so this puts it where it belongs.
    WlrLayershell.layer: WlrLayer.Overlay
    id: fileMenu
    property bool wanted: root.shown && root.childMenu === "file"
    property real shade: 0
    onWantedChanged: fileMenu.shade = fileMenu.wanted ? 1 : 0
    Behavior on shade {
      NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
    }
    visible: fileMenu.wanted || fileMenu.shade > 0.01
    focusable: false
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region { item: fileBg }
    anchors { top: true; left: true }
    screen: root.screen
    implicitWidth: 300 + Zenon.menuShadowPad * 2
    implicitHeight: {
      if (!root.screen) return 300 + Zenon.menuShadowPad * 2;
      const maxBgH = root.screen.height - Zenon.menuShadowPad * 2;
      return Math.min(fileContent.implicitHeight + 8, maxBgH) + Zenon.menuShadowPad * 2;
    }

    // autofit + no gap — try right of parent, else left; also shift up if off-screen bottom
    margins.left: {
      if (!root.screen || !rootMenu.visible) return 0;
      return Math.round(Zenon.hingeX(
        rootMenu.cardX, Zenon.menuWidth, 300,
        root.screen.width, Zenon.padScreen)) - Zenon.menuShadowPad;
    }
    margins.top: root.submenuTop("file",
      fileMenu.implicitHeight - Zenon.menuShadowPad * 2)

    ClippingRectangle {
      id: fileBg
      anchors.fill: parent
      anchors.margins: Zenon.menuShadowPad
      transformOrigin: Item.TopLeft
      scale: Zenon.menuScale(fileMenu.shade)
      opacity: fileMenu.shade
      color: Zenon.menuBg
      border.color: Zenon.surfaceBorder
      border.width: 1
      radius: Zenon.menuRadius
      topLeftRadius: 0
      topRightRadius: Zenon.menuRadius
      bottomLeftRadius: 0
      bottomRightRadius: Zenon.menuRadius

      Column {
        id: fileContent
        anchors.fill: parent
        anchors.margins: Zenon.menuCardPad
        spacing: 0

        // file list — autofit, 5.6× scroll speed (2×), aware of available space
        // ── the scroll, and why it is an overlay ──────────────────────
        // A WheelHandler declared inside a Flickable NEVER FIRES. Flickable's
        // default property parents non-Item children to contentItem as a plain
        // QObject, so the handler is registered on no item at all and is never
        // offered an event — verified with a logging handler inside the very
        // view the wheel was visibly scrolling, which logged nothing while a
        // console.log elsewhere logged fine. The 5.6x speed this asked for had
        // therefore never once applied; what you felt was Qt's built-in wheel
        // step, and the code saying otherwise sat here looking correct.
        //
        // A MouseArea over the view does get them. NoButton is what makes it
        // safe to lay over everything: it never takes a press, so clicking and
        // hovering the rows underneath are untouched.
        //
        // The wrapper exists because the MouseArea cannot be a CHILD of the
        // Flickable for the same reason the handler failed — anything Item
        // shaped goes into contentItem and scrolls away with the content.
        Item {
          width: parent.width
          height: {
            if (!root.screen) return Math.min(500, fileRepeaterHolder.childrenRect.height);
            const maxH = root.screen.height - Zenon.menuShadowPad * 2 - 12;
            return Math.min(fileRepeaterHolder.childrenRect.height, Math.max(120, maxH - 6));
          }

        Flickable {
          id: fileFlick
          // Finder's rubber band and the smooth wheel notch, one rule for
          // the whole shell — see morpheus/Elastic.qml. Inside the view
          // rather than over it: it pins itself to the viewport.
          ElasticScroll { view: fileFlick }
          anchors.fill: parent
          clip: false
          contentWidth: width
          contentHeight: fileRepeaterHolder.childrenRect.height
          boundsBehavior: Flickable.StopAtBounds
          flickDeceleration: 1800
          maximumFlickVelocity: 2800

          Column {
            id: fileRepeaterHolder
            width: parent.width
            spacing: 0

            Repeater {
              id: fileRepeater
              model: root.fileRows

              delegate: Item {
                id: fileEntry
                required property var modelData
                required property int index
                width: fileRepeaterHolder.width
                height: Zenon.menuRowHeight

                // drag support for both files and dirs (not parent)
                // NOT BOUND TO THE HANDLER, and that is the whole reason the
                // drag card could never appear: a binding starts the drag the
                // instant the handler activates, which is a frame before
                // grabToImage can answer, so Drag.imageSource was still empty
                // when the compositor read it. Set by hand in the callback.
                Drag.active: false
                Drag.source: fileEntry
                Drag.keys: ["text/uri-list"]
                Drag.mimeData: {"text/uri-list": "file://" + modelData.path + "\r\n"}
                Drag.supportedActions: Qt.CopyAction
                Drag.dragType: Drag.Automatic
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2
                Drag.onDragFinished: function(dropAction) {
                  // cleared by hand now that nothing binds it
                  fileEntry.Drag.active = false;
                  if (dropAction === Qt.CopyAction) root.closeAll();
                }

                Rectangle {
                  anchors.fill: parent
                  radius: 0
                  color: fileHover.containsMouse ? Zenon.headBg : "transparent"
                }

                Item {
                  anchors.fill: parent
                  anchors.leftMargin: 12
                  anchors.rightMargin: 10

                  Text {
                    id: fileIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    text: modelData.isDir ? "󰉋" : ""
                    color: Zenon.white
                    font.family: Zenon.face
                    font.pixelSize: 15
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    visible: !modelData.isParent
                  }

                  Text {
                    id: fileLabel
                    anchors.left: fileIcon.visible ? fileIcon.right : parent.left
                    anchors.leftMargin: fileIcon.visible ? 8 : 0
                    anchors.right: fileArrow.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignLeft
                    text: modelData.isParent ? "" : modelData.name
                    elide: Text.ElideMiddle
                    color: Zenon.white
                    font.family: Zenon.face
                    font.weight: Font.Medium
                    font.pixelSize: 16
                  }

                  Text {
                    id: fileArrow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    visible: (modelData.isDir || false) && !modelData.isParent
                    text: "\uF054"
                    // White, like the label it belongs to. Muted put it a
                    // shade below the row it is part of, which read as though
                    // the arrow were disabled rather than as punctuation.
                    color: Zenon.white
                    font.family: Zenon.face
                    // The label beside it is 16. An arrow a point smaller sat
                    // slightly below the line of the text it belongs to.
                    font.pixelSize: 16
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                  }
                }

                DragHandler {
                  id: dragHandler
                  enabled: !modelData.isParent
                  target: null
                  onActiveChanged: {
                    if (!active) return;
                    // the picture is made BEFORE the drag is offered — see
                    // Drag.active above
                    root.dragPicture(fileEntry.modelData.name, fileIcon.text,
                                     Zenon.white, function(url) {
                      fileEntry.Drag.imageSource = url;
                      fileEntry.Drag.active = true;
                    });
                  }
                }

                ChosenFlash { id: fileFlash }

                MouseArea {
                  id: fileHover
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !fileFlash.running
                  // Walking INTO a directory is not an event this menu has
                  // finished with — the card stays up and redraws — so it
                  // goes straight through. Opening something is the event.
                  onClicked: {
                    const e = fileEntry.modelData;
                    if (e.isParent || e.isDir) { root.onFileChosen(e); return; }
                    fileFlash.fire(() => root.onFileChosen(e));
                  }
                }
              }
            }
          }
        }

          MouseArea {
            anchors.fill: parent
            z: 1
            acceptedButtons: Qt.NoButton
            onWheel: (w) => {
              const dy = w.angleDelta.y;
              if (dy === 0) { w.accepted = w.angleDelta.x !== 0; return; }
              const most = Math.max(0, fileFlick.contentHeight - fileFlick.height);
              fileFlick.contentY = Math.max(0, Math.min(most,
                fileFlick.contentY + (dy > 0 ? -1 : 1) * 90 * 5.6));
              w.accepted = true;
            }
          }
        }
      }
    }

    MenuShadow {
      panel: fileBg
      opacity: fileMenu.shade
      transformOrigin: Item.TopLeft
      scale: fileBg.scale
    }
  }

  // ── session submenu ───────────────────────────────────────────────
  CardMenu {
    id: sessionMenu
    screen: root.screen
    cardWidth: Zenon.menuWidth
    open: root.shown && root.childMenu === "session"
    hinged: true
    flipFrom: rootMenu.margins.left + Zenon.menuShadowPad + Zenon.menuWidth
    flipParentLeft: rootMenu.margins.left + Zenon.menuShadowPad
    at: Qt.point(0, root.submenuTop("session", sessionMenu.contentH)
                    + Zenon.menuShadowPad)

    // The ones that ask first carry `asks`, so they open their card and flash
    // nothing: the question is the reply. They also carry `hasChildren`, for
    // the chevron — a row that opens something has to say so, and with no
    // flash either there would be nothing at all to connect the card that
    // appears to the row it came from.
    model: root.sessionEntries.map(e => ({
      text: e.text, icon: e.icon,
      asks: e.confirm || false, hasChildren: e.confirm || false
    }))

    // The row whose confirm card is up stays lit, the way every branch row in
    // icarus and terminus does.
    activeIndex: {
      if (!root.pendingConfirmId) return -1;
      for (let i = 0; i < root.sessionEntries.length; ++i)
        if (root.sessionEntries[i].id === root.pendingConfirmId) return i;
      return -1;
    }

    onChosen: index => {
      const e = root.sessionEntries[index];
      if (!e) return;
      if (e.confirm) { root.pendingConfirmId = e.id; return; }
      root.onSessionChosen(e);
    }
  }

  // ── shell submenu ─────────────────────────────────────────────────
  // The settings, and putting the panels back. Placed against its own ROW
  // rather than at a fixed offset down the root menu, the way the trash menu
  // is: rows above it come and go with the switches in oracle, so an offset
  // measured in row heights would be wrong the moment one of them went.
  CardMenu {
    id: shellMenu
    screen: root.screen
    model: root.shellOnlyEntries
    cardWidth: 200
    open: root.shown && root.childMenu === "shell"

    // Hinged off the root menu: to its right where there is room, to its left
    // otherwise, squaring whichever corner ends up against it.
    hinged: true
    flipFrom: rootMenu.margins.left + Zenon.menuShadowPad + Zenon.menuWidth
    flipParentLeft: rootMenu.margins.left + Zenon.menuShadowPad

    // Against its own ROW rather than a fixed offset down the root menu: the
    // rows above it come and go with the switches in oracle, so an offset
    // measured in row heights would be wrong the moment one of them went.
    at: Qt.point(0, root.submenuTop("shell", shellMenu.contentH)
                    + Zenon.menuShadowPad)

    onChosen: index => {
      const e = root.shellOnlyEntries[index];
      if (!e) return;
      root.execCmd(e.cmd);
      root.closeAll();
    }
  }

  // ── confirm submenu (tertiary, to the right of session) ──────────
  PanelWindow {
    // OVERLAY, like every other popup this shell puts up. These eight set no
    // layer at all, which left the desktop menu on Top while the pill's
    // panels sat on Overlay above it — a menu opened over a panel went
    // behind it. Within a layer the last surface mapped is the top one, and
    // a menu maps when you open it, so this puts it where it belongs.
    WlrLayershell.layer: WlrLayer.Overlay
    id: confirmMenu
    property bool wanted: root.shown && root.childMenu === "session" && root.pendingConfirmId !== ""
    property real shade: 0
    onWantedChanged: confirmMenu.shade = confirmMenu.wanted ? 1 : 0
    Behavior on shade {
      NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
    }
    visible: confirmMenu.wanted || confirmMenu.shade > 0.01
    focusable: false
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region { item: confirmBg }
    anchors { top: true; left: true }
    screen: root.screen
    implicitWidth: 160 + Zenon.menuShadowPad * 2
    implicitHeight: {
      if (!root.screen) return 160 + Zenon.menuShadowPad * 2;
      const maxBgH = root.screen.height - Zenon.menuShadowPad * 2;
      return Math.min(confirmContent.implicitHeight + 8, maxBgH) + Zenon.menuShadowPad * 2;
    }

    property var pendingEntry: root.sessionEntryById(root.pendingConfirmId)

    margins.left: {
      if (!root.screen || !sessionMenu.visible) return 0;
      return Math.round(Zenon.hingeX(
        sessionMenu.cardX, sessionMenu.cardWidth, 160,
        root.screen.width, Zenon.padScreen)) - Zenon.menuShadowPad;
    }
    margins.top: {
      if (!root.screen || !sessionMenu.visible) return 0;
      const pad = Zenon.menuShadowPad;
      const parentBgY = sessionMenu.margins.top + pad;
      // the session card's own rows, not numbers that match them today
      let idx = -1;
      for (let i = 0; i < root.sessionEntries.length; ++i) if (root.sessionEntries[i].id === root.pendingConfirmId) { idx = i; break; }
      const rowH = Zenon.menuRowHeight;
      const bgH = confirmMenu.implicitHeight - pad * 2;
      let bgY = parentBgY + Zenon.menuCardPad + idx * rowH;
      if (bgY + bgH > root.screen.height - pad) bgY = root.screen.height - bgH - pad;
      if (bgY < pad) bgY = pad;
      return bgY - pad;
    }

    ClippingRectangle {
      id: confirmBg
      anchors.fill: parent
      anchors.margins: Zenon.menuShadowPad
      transformOrigin: Item.TopLeft
      scale: Zenon.menuScale(confirmMenu.shade)
      opacity: confirmMenu.shade
      color: Zenon.menuBg
      border.color: Zenon.surfaceBorder
      border.width: 1
      radius: Zenon.menuRadius
      topLeftRadius: 0
      topRightRadius: Zenon.menuRadius
      bottomLeftRadius: 0
      bottomRightRadius: Zenon.menuRadius

      Column {
        id: confirmContent
        anchors.fill: parent
        anchors.margins: Zenon.menuCardPad
        spacing: 0

        Item {
          width: parent.width
          height: Zenon.menuRowHeight
          Rectangle {
            anchors.fill: parent
            radius: 0
            color: confirmHover.containsMouse ? Zenon.headBg : "transparent"
          }
          Text {
            id: confirmLabel
            anchors.centerIn: parent
            text: " Confirm"
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Medium
            font.pixelSize: 16
          }
          ChosenFlash { id: confirmFlash }

          MouseArea {
            id: confirmHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: !confirmFlash.running
            onClicked: confirmFlash.fire(() => {
              const e = confirmMenu.pendingEntry;
              if (e) root.execCmd(e.cmd);
              root.closeAll();
            })
          }
        }

        Item {
          width: parent.width
          height: Zenon.menuRowHeight
          Rectangle {
            anchors.fill: parent
            radius: 0
            color: cancelHover.containsMouse ? Zenon.headBg : "transparent"
          }
          Text {
            id: cancelLabel
            anchors.centerIn: parent
            text: " Cancel"
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Medium
            font.pixelSize: 16
          }
          ChosenFlash { id: cancelFlash }

          MouseArea {
            id: cancelHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: !cancelFlash.running
            onClicked: cancelFlash.fire(() => root.pendingConfirmId = "")
          }
        }
      }
    }

    MenuShadow {
      panel: confirmBg
      opacity: confirmMenu.shade
      transformOrigin: Item.TopLeft
      scale: confirmBg.scale
    }
  }

  // clicking outside root but inside screen should also be caught by grab;
  // fallback transparent catcher when no menu child
  // (grab handles it — no extra MouseArea needed)

  IpcHandler {
    target: "Icarus"
    function toggle(): void { if (root.shown) root.closeAll(); else root.openAtCursor(); }
    function openAt(x: int, y: int): void { root.openAt(Qt.point(x, y), root.screen); }
    function hide(): void { root.closeAll(); }
  }
}
