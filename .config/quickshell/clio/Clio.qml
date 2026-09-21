// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┘┴└─┘
// https://github.com/kbuckleys/
//
// CLIO — notes left on the desktop.
//
// THE STATE, not the drawing. One list of notes, persisted, plus the verbs
// that change it. The board reads this and draws; anything else that wants to
// make a note — icarus' menu, a keybind, `qs ipc` — calls a function here and
// never touches a window.
//
// WHY A SINGLETON AND NOT A PROPERTY ON THE BOARD: the board is a Variants
// over screens, so there is one of it per monitor. The notes are not per
// monitor — they are one wall that every screen shows its own part of — and
// hanging them off the board would have made a second copy appear the moment
// a second display did.

pragma Singleton

import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import "../morpheus"
import "clio.js" as Scribe

Singleton {
  id: root

  // Every note, in the order they were made. The board's Repeater is driven
  // by this, so replacing the list wholesale is what makes a note appear or
  // go — and why every mutation below builds a new array rather than editing
  // one in place, which QML would not notice.
  property var notes: []

  // Hidden without being forgotten. A wall of notes is useful until you want
  // to see the desktop under it, and deleting them is not the answer to that.
  property bool shown: true

  readonly property int count: root.notes.length

  // ── WHAT THE VIEWS ARE DRIVEN BY ───────────────────────────────────────
  // `notes` is the truth — it is what is reasoned about and what is written
  // to disk — but it is a JS array, and every change replaces it wholesale.
  // Handed to a Repeater that is death: measured, a Repeater given a plain
  // count destroys and rebuilds EVERY delegate when the number changes, so
  // making one note replayed the arrival of all of them and threw away the
  // caret, the selection and the focus of any note being typed into.
  //
  // This is the same list said in a way QML can change a piece of: one row
  // appended when a note is made, one removed when it goes, and every other
  // delegate left exactly as it was. It holds only the KEY — a delegate
  // looks the note up — so editing one never touches the model at all.
  ListModel { id: keyModel }
  readonly property alias rows: keyModel

  function resync() {
    keyModel.clear();
    for (let i = 0; i < root.notes.length; i++)
      keyModel.append({ key: root.notes[i].id });
  }

  // ── THE IDS, AS A LIST OF THEIR OWN ────────────────────────────────────
  // The board runs one window per note, and Variants keys its instances on
  // the model's VALUES. Handed the notes themselves it would rebuild every
  // window on every keystroke — a new array of new objects each time. Handed
  // the ids, it rebuilds one when a note is made or removed and never
  // otherwise, because a string that has not changed is the same string.
  readonly property var ids: {
    const out = [];
    for (let i = 0; i < root.notes.length; i++) out.push(root.notes[i].id);
    return out;
  }

  // ── ONE SURFACE PER NOTE PER SCREEN ────────────────────────────────────
  // A layer surface belongs to an output — the protocol sets it at creation
  // and has no request to change it — so a note cannot be carried across a
  // seam the way a window is. Moving one meant destroying its surface and
  // building another, which is the redraw.
  //
  // So nothing moves. Every screen holds a surface for every note, each
  // drawing the note at its own origin and showing it only where it actually
  // falls. A note crossing a seam is already drawn on the far side before it
  // gets there; the two surfaces simply show more and less of it.
  //
  // KEYED BY NAME AND ID, both strings — Variants rebuilds an instance when
  // its model VALUE changes, and a pair of strings that have not changed is
  // the same value. Built from objects it would rebuild every window on
  // every keystroke.
  readonly property var slots: {
    const out = [];
    const scr = Quickshell.screens;
    for (let s = 0; s < scr.length; s++)
      for (let i = 0; i < root.notes.length; i++)
        out.push(scr[s].name + "\u001f" + root.notes[i].id);
    return out;
  }

  function noteFor(id) {
    const i = root.indexOf(id);
    return i < 0 ? null : root.notes[i];
  }

  // ── THE PALETTE, BY NAME ───────────────────────────────────────────────
  // clio.js knows which names exist; zenon knows what they look like. This is
  // the join, and it is the only place in clio that a colour is a colour.
  function ink(hue) {
    switch (String(hue)) {
      case "sand":    return Zenon.sand;
      case "yellow":  return Zenon.yellow;
      case "green":   return Zenon.green;
      case "cyan":    return Zenon.cyan;
      case "blue":    return Zenon.blue;
      case "magenta": return Zenon.magenta;
      case "pink":    return Zenon.pink;
    }
    return Zenon.sand;
  }

  // The note's own ground: its hue laid over black, faint enough that white
  // text reads on it. A sticky note is identified by its colour from across
  // the room, not read through it.
  function wash(hue) {
    const c = root.ink(hue);
    return Qt.rgba(c.r * 0.35, c.g * 0.35, c.b * 0.35, 0.90);
  }

  function indexOf(id) {
    for (let i = 0; i < root.notes.length; i++)
      if (root.notes[i].id === id) return i;
    return -1;
  }

  // ── MAKING ONE ─────────────────────────────────────────────────────────
  // Placed where it was asked for, and cascaded when it was not: a stack of
  // notes all at the same coordinate is one note as far as anyone can tell.
  function add(x, y) {
    const n = root.notes.length;
    const cascade = (n % 8) * 26;
    const note = Scribe.blank(Scribe.newId(),
      x !== undefined ? x : 120 + cascade,
      y !== undefined ? y : 120 + cascade,
      Scribe.nextHue(root.notes));
    root.notes = root.notes.concat([note]);
    keyModel.append({ key: note.id });
    root.shown = true;
    root.save();
    return note.id;
  }

  // ── WHERE YOU ARE LOOKING ──────────────────────────────────────────────
  // A note made from the menu appeared at 120,120 of the layout, which is the
  // top-left of the leftmost monitor — so asking for one on the right-hand
  // screen put it on the other one. The pointer is where you are, and it is
  // the only thing that knows.
  //
  // Asked of hyprland rather than of Qt, and in its GLOBAL logical space,
  // which is the same space a note's position is in. Icarus reads it exactly
  // this way to open its menu at the cursor.
  //
  // Offset so the note lands UNDER the pointer rather than hanging off it:
  // the head is what you reach for, so the pointer starts on the head.
  function addHere() {
    cursorProc.running = false;
    cursorProc.running = true;
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      id: cursorOut
      waitForEnd: true
      onStreamFinished: {
        // "2186, 774"
        const m = String(cursorOut.text).trim().match(/(-?\d+)\s*,\s*(-?\d+)/);
        // No answer is not a reason to lose the note — it simply lands where
        // it used to.
        if (!m) { root.add(); return; }
        root.add(parseInt(m[1], 10) - 40, parseInt(m[2], 10) - 13);
      }
    }
  }

  function remove(id) {
    const out = [];
    for (let i = 0; i < root.notes.length; i++)
      if (root.notes[i].id !== id) out.push(root.notes[i]);
    root.notes = out;
    // The one row, not the whole list: every other note keeps its delegate
    // and everything that delegate was holding.
    for (let i = 0; i < keyModel.count; i++) {
      if (keyModel.get(i).key === id) { keyModel.remove(i); break; }
    }
    root.save();
  }

  // ── CHANGING ONE ───────────────────────────────────────────────────────
  // Field by field through one door, so every change is saved the same way
  // and none of them can forget to be.
  function set(id, field, value) {
    const i = root.indexOf(id);
    if (i < 0) return;
    const out = root.notes.slice();
    const copy = ({});
    for (const k in out[i]) copy[k] = out[i][k];
    copy[field] = value;
    out[i] = copy;
    root.notes = out;
    root.save();
  }

  // Moved and resized together, because a drag changes both and two calls
  // would be two list rebuilds and two saves per frame.
  function place(id, x, y, w, h) {
    const i = root.indexOf(id);
    if (i < 0) return;
    // COPIED FIELD BY FIELD FROM WHAT IS THERE, never written out as a
    // literal. Spelling the note out here listed the fields it had the day
    // this was written — so `size` and `z`, added later, were silently
    // dropped every time a note was dragged or resized. A note that forgets
    // how big its text is whenever you move it is not a note you can use.
    const out = root.notes.slice();
    const copy = ({});
    for (const k in out[i]) copy[k] = out[i][k];
    copy.x = Math.round(x);
    copy.y = Math.round(y);
    copy.w = Math.round(w);
    copy.h = Math.round(h);
    out[i] = copy;
    root.notes = out;
    root.save();
  }

  // ── COMING TO THE FRONT ────────────────────────────────────────────────
  // By NUMBER, not by position. This used to move the note to the end of the
  // list, which is how a Repeater draws one last — and it cannot work here,
  // because the board addresses a note by its INDEX. Reordering renumbered
  // every note, so the one you clicked handed its position and size to
  // whichever note slid into its place.
  //
  // A counter that only goes up. There is no need to renumber the others:
  // nothing cares what the numbers are, only which is biggest.
  property int topZ: 1

  function raise(id) {
    const i = root.indexOf(id);
    if (i < 0) return;
    if (root.notes[i].z === root.topZ) return;
    root.topZ += 1;
    root.set(id, "z", root.topZ);
  }

  function clear() {
    root.notes = [];
    keyModel.clear();
    root.save();
  }

  function toggle() { root.shown = !root.shown; }

  // ── KEPT ON DISK ───────────────────────────────────────────────────────
  // Debounced: dragging a note writes its position on every frame, and a file
  // rewritten sixty times a second to record one gesture is sixty writes for
  // one fact.
  function save() { saveTimer.restart(); }

  FileView {
    id: stateFile
    path: Quickshell.statePath("clio-notes.json")
    blockLoading: true
    printErrors: false
    // NO onLoaded — the shape howler and chronos both use. FileView re-reads
    // after a write, and that reload can land with a snapshot older than what
    // is in memory, which clobbers the list it was supposed to be persisting.
    // Read once below; memory is the truth from then on.
  }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: stateFile.setText(Scribe.serialize(root.notes))
  }

  IpcHandler {
    target: "Clio"

    function add(): string {
      root.addHere();
      return "note added at the pointer";
    }

    function toggle(): string {
      root.toggle();
      return root.shown ? "shown" : "hidden";
    }

    function clear(): string {
      const n = root.count;
      root.clear();
      return n + " removed";
    }

    function status(): string {
      return root.count + " notes, " + (root.shown ? "shown" : "hidden");
    }
  }

  Component.onCompleted: {
    root.notes = Scribe.parse(stateFile.text());
    root.resync();
    // Carry on above whatever was saved, so a note raised today still lands
    // in front of one raised last week.
    let top = 1;
    for (let i = 0; i < root.notes.length; i++)
      if (root.notes[i].z > top) top = root.notes[i].z;
    root.topZ = top;
  }
}
