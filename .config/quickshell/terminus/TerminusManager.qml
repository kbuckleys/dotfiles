// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TERMINUS' windows, and the one voice that speaks for them.
//
// There can be several now, which is the whole reason this file exists: two
// TerminusWindows would mean two IpcHandlers claiming the same "Terminus" target,
// and only one of them would win. So the handler lives out here and picks a
// window to act on, and the windows themselves carry no ipc at all.
//
// Window 0 is the one SUPER+E toggles and the one the portal is handed to. The
// rest are spares you asked for with N, and they retire when you close them.

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "terminus.js" as Terminus
import "tags.js" as Tags
import "collections.js" as Coll

Scope {
  id: mgr

  // Windows are CREATED, not modelled.
  //
  // The first version put an Instantiator over a JS array of ids and pushed a
  // new id onto it. Replacing the array makes the Instantiator rebuild every
  // delegate, not just add one — so the second press destroyed the window you
  // already had (recreating it hidden, which read as "it closed the first
  // one") and built the rest from scratch at the same time. Exactly the bug
  // reported.
  //
  // createObject touches nothing that already exists, which is the whole
  // requirement here. `wins` holds the live objects so a binding on it — the
  // ipc handler's `w` — re-evaluates when one arrives or leaves; a function
  // call in a binding would not have.
  property var wins: []
  property int nextId: 0

  // The yank buffer, held here rather than in a window, so the windows
  // acknowledge each other: copy in one, paste in another. It was per-window
  // before, which meant two terminus windows side by side could not hand a file
  // between them at all — the only route was a drag, and dragging out of a
  // quickshell surface does not currently work.
  property var clipboard: null

  // ── THE WINDOW IS NOT COMPILED AT STARTUP ─────────────────────────────
  // An inline `Component { TerminusWindow {} }` names the type at file
  // scope, and naming it is what makes the engine compile it during the
  // shell's own load. TerminusWindow.qml is 23,000 lines; measured, that
  // compile is 3.4s of a 4.7s cold start, and the bar does not reach the
  // screen until 4.2s. Everything you actually look at when you log in was
  // queued behind a file manager that is not on screen.
  //
  // MEASURED, because the obvious fix is not the fix. Handing
  // Qt.createComponent Component.Asynchronous during the shell's load
  // changes nothing at all — the engine waits for components created while
  // it is still loading, so the bar still arrived at 4.2s. It is the
  // DEFERRAL that does the work; asynchronous is what stops the deferred
  // compile from freezing the shell when it does run.
  //
  // With both: bar on screen at 1.1s, and the compile running off the GUI
  // thread afterwards without dropping a frame (measured on a 100ms
  // heartbeat: no gap over 250ms for the whole 3.4s).
  property var winComp: null
  property bool compiling: false

  // Requests that arrived before the type was ready. Never blocked: a
  // shell that freezes for three seconds because you pressed SUPER+E is
  // worse than one that takes a moment to show a window, and the window
  // appearing late looks like an application starting, which it is.
  property var pending: []

  readonly property bool compReady:
    mgr.winComp !== null && mgr.winComp.status === Component.Ready

  // Started off the critical path. The delay is not a guess at how long
  // startup takes — it is there because a component created during the
  // root document's load is waited for however it was asked for.
  Timer {
    id: compileSoon
    interval: 1200
    running: true
    repeat: false
    onTriggered: mgr.beginCompile()
  }

  function beginCompile() {
    if (mgr.compReady || mgr.compiling) return;
    mgr.compiling = true;
    mgr.winComp = Qt.createComponent("TerminusWindow.qml",
                                     Component.Asynchronous);
    if (mgr.winComp.status === Component.Loading)
      mgr.winComp.statusChanged.connect(mgr.compileSettled);
    else
      mgr.compileSettled();
  }

  function compileSettled() {
    if (!mgr.winComp || mgr.winComp.status === Component.Loading) return;
    mgr.compiling = false;
    if (mgr.winComp.status === Component.Error) {
      console.error("terminus: " + mgr.winComp.errorString());
      mgr.pending = [];
      return;
    }
    const q = mgr.pending;
    mgr.pending = [];
    for (let i = 0; i < q.length; ++i) mgr.fulfil(q[i]);

    // ── AND THE FIRST WINDOW, BUILT NOW AND HIDDEN ────────────────────
    // This used to be the opposite: nothing was built until something
    // asked, on the reasoning that instantiating the tree costs 750ms on
    // the GUI thread even incubated, and that a freeze five seconds after
    // login is worse than a slow login, because you are using the machine
    // by then.
    //
    // REVERSED DELIBERATELY. That reasoning trades a cost you notice
    // rarely for one you notice every single time you open the file
    // manager, and the file manager is opened far more often than the
    // machine is logged into. Until the 750ms itself comes down, it is
    // better spent while you are still looking at a desktop that has only
    // just appeared. A longer cold start beats a longer SUPER+E.
    //
    // HIDDEN, and that part is measured: an idle VISIBLE terminus window
    // costs the shell some 19 CPU points, and hiding it returns the shell
    // to its 3.67% baseline. A window standing by costs nothing until it
    // is on screen.
    //
    // The ipc `spawn` already reuses window 0 while it is hidden — see its
    // note — so this is the window SUPER+E gets, not one it leaves behind.
    if (mgr.wins.length === 0) mgr.makeFor("");
  }

  // The blocking path, kept for the ONE caller that cannot wait: the
  // portal hands back a window synchronously or the request fails, and a
  // failed picker is an application writing its file somewhere else.
  function ensureComp() {
    if (mgr.compReady) return mgr.winComp;
    mgr.winComp = Qt.createComponent("TerminusWindow.qml");
    mgr.compiling = false;
    if (mgr.winComp.status === Component.Error)
      console.error("terminus: " + mgr.winComp.errorString());
    return mgr.winComp;
  }

  // SHOWN FIRST, THEN THE DESTINATION, and the order is not cosmetic —
  // see the note on the ipc `open`. Being shown is what clears the
  // restored session, so a goTo that happens before it is undone by the
  // reset that follows: asking to open ~/Pictures landed on home.
  function fulfil(req) {
    const w = mgr.makeFor(req.path);
    if (!w) return;
    if (req.show) { w.shown = true; w.takeFocus(); }
  }

  // Asks for a window, now or as soon as there is one. Returns the window
  // when it could be made immediately, and null when the caller will have
  // to wait — which for every caller here means "say so and move on".
  function request(path, show) {
    if (mgr.compReady) {
      const req = { path: path || "", show: show === true };
      const before = mgr.wins.length;
      mgr.fulfil(req);
      return mgr.wins.length > before ? mgr.wins[mgr.wins.length - 1] : null;
    }
    mgr.pending.push({ path: path || "", show: show === true });
    mgr.beginCompile();
    return null;
  }

  // THE DESTINATION IS HANDED TO THE WINDOW, not applied to it afterwards.
  // A window restores its session ASYNCHRONOUSLY — it shells out to check
  // which stored directories still exist — so a goTo from out here worked
  // and was undone about a second later, which read as the request being
  // ignored. bootPath is what the window consults once its own restore has
  // settled; see takeBoot over there.
  function makeFor(path) {
    if (!mgr.compReady) return null;
    const w = mgr.winComp.createObject(mgr, {
      winId: mgr.nextId++, mgr: mgr, bootPath: path || ""
    });
    if (!w) return null;
    const next = mgr.wins.slice();
    next.push(w);
    mgr.wins = next;
    return w;
  }

  function make(path) { return mgr.makeFor(path); }

  // Window 0, or null. A FUNCTION and not a property on the handler: an
  // IpcHandler exposes its declared properties over ipc, and a var is a
  // QVariant, which cannot cross that boundary — declaring one there logged
  // "Type QVariant cannot be used across IPC" on every load.
  function win() { return mgr.wins.length > 0 ? mgr.wins[0] : null; }

  // ── A WINDOW TO ASK, WHICH IS NOT THE SAME AS ONE TO SHOW ─────────────
  // The tag index and the collections live on a window, and since nothing
  // is built at startup any more there may not be one — which quietly
  // broke `Terminus tag ~/notes.md work` from a script when the file
  // manager happened to be closed.
  //
  // So a query builds one if it has to, HIDDEN, and blocks to do it. This
  // is the one place blocking is right: the caller wants an answer on
  // standard output and there is nothing to show them in the meantime.
  // Nothing is shown, so nothing appears on screen for a script that only
  // wanted to read a tag.
  function dataWin() {
    const w = mgr.win();
    if (w) return w;
    const comp = mgr.ensureComp();
    if (!comp || comp.status !== Component.Ready) return null;
    return mgr.makeFor("");
  }

  function spawn(path) {
    return mgr.request(path && path !== "" ? path : Paths.home(), true);
  }

  function retire(id) {
    // the last window is kept: it is the one the keybind and the portal reach,
    // and a manager with nothing in it has nowhere to put the next request
    if (mgr.wins.length < 2) return;
    const keep = [];
    let doomed = null;
    for (const w of mgr.wins) {
      if (w && w.winId === id) doomed = w;
      else keep.push(w);
    }
    if (!doomed) return;
    mgr.wins = keep;
    doomed.destroy();
  }

  // ── the portal's own window ─────────────────────────────────────────────
  // A file dialog is not the same object as your file manager.
  //
  // The portal used to be handed window 0, and the cost of that was hidden in
  // plain sight: a "save as" from a browser navigated the terminus you were
  // browsing in, flipped it to columns view, and hid it once you answered. If
  // window 0 happened to be open already, `shown = true` changed nothing and
  // no dialog ever came forward.
  //
  // So a request gets a window of its own, made on demand and destroyed when
  // it answers. It is deliberately NOT in `wins`: `win()` must stay "window
  // 0", `windows()` lists what you opened, and retire()'s keep-the-last guard
  // must not count a dialog as your last file manager.
  property var pickerWin: null

  // WHERE YOU LAST SAVED SOMETHING, held HERE rather than on the dialog.
  //
  // The dialog is destroyed the moment it answers, and the preference write
  // behind it is debounced — so a value recorded on the window went to the
  // grave with it every single time, and the next save opened wherever the
  // asking program suggested all over again. The manager outlives every
  // picker, which is the whole reason it is the one holding this.
  property string lastSaveDir: ""

  // Recorded, and asked to be written down. Window 0 owns the preferences
  // file; a dialog has no business writing it and will not be alive to.
  function noteSaveDir(d) {
    if (!d || d === "") return;
    mgr.lastSaveDir = d;
    const w = mgr.win();
    if (w) w.persistPrefs();
  }

  function picker() {
    // A DEAD POINTER IS NOT A WINDOW. The dialog can go away by routes this
    // manager never hears about — the compositor closing it, a destroy that
    // raced a new request — and a destroyed QObject held in a `var` does not
    // become null, it simply throws the moment anything is read off it. So the
    // stale pointer was handed the next request, setting `portal` on it threw,
    // the portal was never answered and never will be, and no dialog could be
    // opened again for the life of the shell.
    //
    // Reading one property is the only way to ask "are you still there".
    if (mgr.pickerWin) {
      try {
        if (mgr.pickerWin.winId === -1) return mgr.pickerWin;
      } catch (e) {
        // fall through and build a fresh one
      }
      mgr.pickerWin = null;
    }
    // winId -1 so the window knows it is a dialog rather than a file manager
    const comp = mgr.ensureComp();
    if (!comp || comp.status !== Component.Ready) return null;
    mgr.pickerWin = comp.createObject(mgr, { winId: -1, mgr: mgr });
    return mgr.pickerWin;
  }

  function retirePicker() {
    const w = mgr.pickerWin;
    if (!w) return;
    mgr.pickerWin = null;
    w.shown = false;
    // Deferred: retirePicker is reached from inside the window's own
    // portalAnswer, and destroying an object while its method is still on the
    // stack is the one way to turn a working dialog into a crash.
    Qt.callLater(() => { if (w) w.destroy(); });
  }

  // The reply is written HERE, not in the window that was asked, because that
  // window is destroyed the moment it answers — a Process owned by it would be
  // torn down mid-write and the portal would sit forever waiting on a `.done`
  // marker that never arrived.
  //
  // Queued for the same reason zeus' mixer queues its pactl calls: the log
  // shows requests arriving a second apart, and a second answer must not
  // reset the command of a process still writing the first.
  property var replies: []

  Process {
    id: answerProc
    onExited: mgr.drainReplies()
  }

  // `create` is set for a SAVE, and it is not optional.
  //
  // termfilechooser STATS the path the wrapper hands back, and refuses it if
  // nothing is there:
  //
  //     [ERROR] filechooser: failed to stat '…/suggested.png':
  //             No such file or directory
  //
  // A save names a file that does not exist yet — that is what a save IS — so
  // every save request was answered with a path the portal then threw away,
  // and the application received response code 2: not "the user cancelled" but
  // "the dialog failed". Firefox answers that by downloading into its own
  // last-used folder on its own, which is where the half-written file that
  // started all of this was coming from.
  //
  // So the chosen path is brought into existence before it is handed over.
  // Nothing is created until you have said where — this runs on confirm, at
  // the path you picked, and it is the file the application is about to fill.
  function answerPortal(out, paths, create) {
    if (!out || out === "") return;
    const make = (create && paths.length > 0)
      ? "mkdir -p -- " + Strings.shellQuote(Terminus.dirname(paths[0]))
        + " 2>/dev/null; touch -- " + Strings.shellQuote(paths[0])
        + " 2>/dev/null; "
      : "";
    const body = paths.length === 0 ? ":"
      : make + "printf '%s\n' " + paths.map((p) => Strings.shellQuote(p)).join(" ")
        + " > " + Strings.shellQuote(out);
    // the marker last, and always: it is what the wrapper is waiting on
    mgr.replies.push(["sh", "-c",
      body + "; : > " + Strings.shellQuote(out + ".done")]);
    mgr.drainReplies();
  }

  function drainReplies() {
    if (mgr.replies.length === 0 || answerProc.running) return;
    answerProc.command = mgr.replies.shift();
    answerProc.running = true;
  }

  // One window from the start, hidden, so there is always something for the
  // keybind to reveal.
  // Guarded, because a reload does not always start from nothing: quickshell
  // reuses what it can, and this ran again on a manager that still held its
  // windows — leaving a second one hidden in `wins` that nothing could reach,
  // since spawn() only ever reuses window 0.
  // Nothing is built here any more — see the note on winComp. The compile
  // starts on the timer above, and the first window is built by whatever
  // first asks for one.

    IpcHandler {
        target: "Terminus"


      function toggle(): string {
        const w = mgr.win();
        // No window yet means the type is still compiling, or nothing has
        // asked for one. Either way "toggle" means "show me one".
        if (!w) return mgr.request("", true) ? "open" : "opening";
        w.shown = !w.shown;
        if (w.shown) { w.refresh(); w.takeFocus(); }
        return w.shown ? "open" : "closed";
      }

      function open(path: string): string {
        const w = mgr.win();
        if (!w)
          return mgr.request(path === "" ? Paths.home() : path, true)
            ? "open" : "opening";
        // SHOWN FIRST, THEN THE DESTINATION. Being shown is what clears the
        // session when "restore session" is off, and a clear that lands after
        // the navigation undoes it — `Terminus open ~/Documents` opened at
        // home. Asking for somewhere always beats the reset.
        w.shown = true;
        w.goTo(path === "" ? Paths.home() : path);
        w.takeFocus();
        return w.cwd;
      }

      // ── tags ──────────────────────────────────────────────────────
      // Scriptable for the same reason `open` is: a file manager that can
      // be driven from a shell is one that can be driven from anything.
      // `Terminus tag ~/notes.md work` from a script is the same gesture as
      // the sheet, and it is also how this was tested before it had a sheet.
      function tag(path: string, name: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        if (path === "" || name === "") return "usage: tag <path> <name>";
        w.toggleTagFor([path], name);
        return "ok";
      }

      function tags(path: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        if (path !== "") return w.tagsFor(path).join(",");
        // No path: every tag that is on something, with its count.
        const counts = Tags.tally(w.tagMarks);
        const out = [];
        for (const k in counts) out.push(k + " (" + counts[k] + ")");
        return out.sort().join("\n");
      }

      // Opens the tag picker over whatever is selected, which is the same
      // thing c t does from the keyboard.
      function tagsheet(): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        w.shown = true;
        w.openTagPicker();
        return "ok";
      }

      // Lists everything carrying a tag, the same page clicking it in the
      // sidebar opens. Escape in the window returns to where you were.
      function tagopen(name: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        if (name === "") return "usage: tagopen <name>";
        w.shown = true;
        w.openTag(name);
        return "ok";
      }

      // Lists the saved collections, or opens one by name.
      function collection(name: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        // allCollections, not collections: the built-in Recents is
        // synthesised rather than stored — see recentsCollection — so
        // the stored list does not contain it and `Terminus collection
        // Recents` quietly matched nothing.
        const all = w.allCollections;
        if (name === "") {
          const out = [];
          for (let i = 0; i < all.length; ++i)
            out.push(all[i].name + "  \u2014  " + Coll.describe(all[i]));
          return out.length > 0 ? out.join("\n") : "none saved";
        }
        for (let i = 0; i < all.length; ++i) {
          if (all[i].name.toLowerCase() === name.toLowerCase()) {
            w.shown = true;
            w.goToCollection(all[i].id);
            return "ok";
          }
        }
        return "no such collection";
      }

      // Opens the collection editor — blank, or on the named folder.
      function collectionedit(name: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        w.shown = true;
        if (name === "") { w.openCollectionEditor(-1); return "new"; }
        const all = w.collections;
        for (let i = 0; i < all.length; ++i)
          if (all[i].name.toLowerCase() === name.toLowerCase()) {
            w.openCollectionEditor(all[i].id);
            return "ok";
          }
        return "no such collection";
      }

      // Renames a tag everywhere it appears. Merges into an existing name.
      function tagrename(from: string, to: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        if (from === "" || to === "") return "usage: tagrename <from> <to>";
        w.renameTag(from, to);
        return "ok";
      }

      // Opens the properties card, optionally on its permissions page —
      // the same card alt+return opens.
      function properties(page: string): string {
        const w = mgr.win();
        if (!w) return "no window";
        w.shown = true;
        w.openProperties(page === "permissions" ? 1 : 0);
        return "ok";
      }

      // Rebuilds the cache from the disk. Takes a root so a test does not
      // have to sweep $HOME to check one directory.
      function tagscan(where: string): string {
        const w = mgr.dataWin();
        if (!w) return "no window";
        w.rebuildTagIndex(where === "" ? Paths.home() : where);
        return "scanning " + (where === "" ? Paths.home() : where);
      }

      function cwd(): string {
        const w = mgr.win();
        if (!w) return "no window"; return w.cwd; }

      // What SUPER+E does. Never hides: a keybind called "open the file
      // manager" that closes it half the time is a coin toss, which is what
      // `toggle` was once there could be more than one window.
      //
      // Window 0 is reused while it is hidden, so the first press does not
      // leave an unreachable hidden window behind a visible new one. After
      // that every press is a new window.
      function spawn(path: string): string {
        // the hidden first window is reused, so the opening press does not
        // leave an unreachable window behind a visible new one
        const first = mgr.wins.length > 0 ? mgr.wins[0] : null;
        if (first && !first.shown) {
          // ONLY when a path was asked for. Falling back to home here is what
          // quietly emptied the restored session: window 0 comes back from
          // disk holding the tabs of the last one, SUPER+E sends no path, and
          // a goTo(home) on the way in walked the tab that was showing to the
          // home directory — overwriting the cwd that had just been restored,
          // and saving it there 400ms later. Do it across a few tabs over a
          // few days and every one of them reads "~".
          //
          // A window that is merely hidden is still WHERE IT WAS. Showing it
          // again is not navigation, so it should not be a navigation; only
          // `open`, which is handed somewhere to go, is.
          // shown first for the reason `open` gives: the clean slate that a
          // disabled "restore session" performs happens on the way in, and a
          // destination asked for afterwards is the one that should stick.
          first.shown = true;
          if (path && path !== "") first.goTo(path);
          first.takeFocus();
          return "window " + first.winId;
        }
        const w = mgr.spawn(path);
        return w ? "window " + w.winId : "failed";
      }

      // Close one by id. `windows` is how you find the id.
      function close(id: int): string {
        mgr.retire(id);
        return mgr.wins.length + " window(s) left";
      }

      function windows(): string {
        // `wins` holds the window OBJECTS now, not ids — looking each one up
        // by treating it as an id printed the QML type name instead
        let s = mgr.wins.length + " window(s):";
        for (const x of mgr.wins) {
          if (!x) { s += " [gone]"; continue; }
          s += " [" + x.winId + (x.shown ? " shown " : " hidden ") + x.cwd + "]";
        }
        // The picker is not one of `wins`, but "is there a dialog up?" is
        // exactly the question this is here to answer.
        const p = mgr.pickerWin;
        if (p) s += " + picker[" + (p.shown ? "shown " : "hidden ") + p.cwd + "]";
        return s;
      }

      // What it currently is, for when something is not behaving and the
      // question is which half is wrong. Every other layer here carries one.
      function status(): string {
        // The picker when there is one, because that is the half that is
        // usually being asked about; window 0 otherwise.
        const w = mgr.pickerWin ? mgr.pickerWin : mgr.win();
        if (!w) return "no window";
        return "collOpen=" + w.collOpenId + " tagOpen=" + w.openTagName
          + " mode=" + w.searchMode
          + " visible=" + w.shown
          + " focus=" + w.hasFocus
          + " preview=" + w.previewKind
          + " dual=" + w.dual
          + " other=" + w.otherCwd + "@" + w.otherSel
          + " side=" + w.paneSide + " split=" + w.paneFrac.toFixed(3)
          + " views=" + JSON.stringify(w.paneViews)
          + " renaming=" + w.renaming
          + " marked=" + w.markedCount
          + " view=" + w.viewMode
          // STILL PICKING UNTIL THE ANSWER IS ON DISK.
          //
          // The wrapper polls this to decide whether its dialog is still up,
          // and treats picking=false without a .done marker as "closed without
          // answering" — it then DELETES the marker and hands the application
          // an empty file, which every application reads as cancel.
          //
          // portalAnswer clears `portal` and only then queues the write, so
          // there was a window of a frame or two where the dialog was gone and
          // the answer had not been written yet. A poll landing in it cancelled
          // a save that had actually been confirmed, and the asking program
          // fell back to the file it had already written in the folder it
          // suggested — which is how a save aimed at one directory ended up as
          // a half-written file in the last one.
          //
          // An answer in flight counts as still picking. It is the same
          // question the wrapper is really asking: is there an answer coming.
          + " picking=" + (w.picking || mgr.replies.length > 0
                           || answerProc.running)
          + " cwd=" + w.cwd
          + " rows=" + w.view.length
          + " sel=" + w.sel;
      }

      // Which layout, by name. `v` cycles them from the keyboard; this is the
      // same switch for anything that wants to open terminus already in the view
      // that suits what it is opening — a picture folder in grid, say.
      // The portal's request, handed over by the wrapper script. Everything is a
      // string because that is what ipc arguments are; "1"/"0" is the shape
      // xdg-desktop-portal-termfilechooser already uses for its own flags.
      function pick(multiple: string, directory: string, save: string,
                    path: string, out: string): string {
        // Everything that can throw happens BEFORE any window state is
        // assigned, and that ORDER is the bug this once had.
        //
        // `portal` was set first and Terminus.basename called second — and
        // terminus.js was not imported in this file, so every SAVE request threw
        // a ReferenceError right there. The window was left hidden with
        // picking=true, no dialog appeared, and the next SUPER+E hit spawn()'s
        // "reuse the hidden first window" path and revealed the stale picker
        // instead of a file manager. The portal log said it plainly: every
        // save=0 request answered "picking", every save=1 answered nothing.
        //
        // A save request arrives with a suggested FILE; the others arrive with
        // a directory to start in. Landing in the file's parent with its name
        // already in the field is what every other save dialog does.
        const saving = save === "1";
        let start = path;
        let suggested = "";
        if (saving && path !== "") {
          suggested = Terminus.basename(path);
          start = Terminus.dirname(path);
        }

        const w = mgr.picker();
        if (!w) return "no window";
        // WHERE YOU LAST SAVED beats where the program suggests — see
        // lastSaveDir in the window. The NAME still comes from the request:
        // the program knows what the file should be called, it just has no
        // idea where you keep things.
        if (saving && mgr.lastSaveDir !== "") start = mgr.lastSaveDir;
        w.portal = {
          multiple: multiple === "1",
          directory: directory === "1",
          save: saving,
          // The path the REQUEST named, kept whole. The dialog opens somewhere
          // else more often than not — see lastSaveDir below — but the file the
          // asking application has already written is at this path, and the
          // window needs it to know what not to list. See portalGhost there.
          suggested: saving ? path : "",
          out: out
        };
        w.goTo(start === "" ? Paths.home() : start);
        w.setSaveName(suggested);
        // The view this dialog was last left in, not a fixed one. Columns
        // is still the default — pickerView starts there — but a picker
        // that you switched to list stays a list next time. See
        // pickerView in the window; it is a slot of its own so a dialog
        // can remember without touching what the file manager remembers.
        w.setView(w.pickerView);
        // and one pane: a dialog picks a file, it does not move files about
        w.dual = false;
        w.shown = true;
        // Not takeFocus/focusSaveField: forcing focus on the frame `visible`
        // is set is dropped on the floor, because the surface is not mapped
        // yet. claimFocus keeps trying, and knows a save dialog wants the
        // name field rather than the listing.
        w.claimFocus();
        return "picking";
      }

      function view(mode: string): string {
        const w = mgr.win();
        if (!w) return "no window";
        w.setView(mode);
        return w.viewMode;
      }
    }
}
