// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PICASSO — the wallpaper store. Quickshell is the daemon itself here: there
// is no swww or hyprpaper to talk to, the background is just another layer
// surface this shell owns. This singleton holds what is chosen and where the
// choices live; PicassoDaemon paints them and PicassoPopup picks them.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../morpheus/thumbs.js" as Thumbs
import "../oracle"
import "picasso.js" as Art

Singleton {
  id: root

  // ── where the backgrounds are ────────────────────────────────────────
  // WHAT XDG SAYS, not a path written down here. "Pictures" is the
  // specification's own default and xdg-user-dirs is free to have moved it —
  // to Bilder, to Images, onto another disk — and a shell that assumed the
  // English name would find nothing on such a machine and report an empty
  // folder as though the folder were empty.
  //
  // The one piece that is genuinely this shell's own convention is the
  // "Wallpapers" leaf, and it is only a DEFAULT: oracle stores nothing until
  // somebody types a path, and anything typed there wins outright.
  //
  // Trailing slashes are cut because every path built from this joins with one
  // of its own, and "~/Walls//a.png" is a different string from
  // "~/Walls/a.png" — which matters, because that string is the key the
  // per-monitor assignment is stored under.
  readonly property string defaultDir: root.picturesDir + "/Wallpapers"

  readonly property string dir: {
    const d = String(Oracle.backgroundDir || "").replace(/\/+$/, "");
    return d === "" ? root.defaultDir : d;
  }

  // XDG_PICTURES_DIR, from the file xdg-user-dirs actually writes it to. The
  // environment variable is checked first by Paths.pictures(), for the
  // sessions that do export it, and the spec's default is the floor under
  // both.
  property string picturesDir: Paths.pictures()

  FileView {
    id: userDirs
    path: Paths.userDirsFile()
    blockLoading: true
    printErrors: false
    onLoaded: root.readUserDirs()
  }

  // The file is shell syntax — `XDG_PICTURES_DIR="$HOME/Pictures"` — so $HOME
  // is expanded by hand rather than by starting a shell to read four lines.
  function readUserDirs() {
    const m = String(userDirs.text() || "")
      .match(/^\s*XDG_PICTURES_DIR\s*=\s*"([^"]*)"/m);
    if (!m) return;
    const v = m[1].replace(/\$HOME/g, Paths.home()).replace(/\/+$/, "");
    if (v !== "") root.picturesDir = v;
  }

  // Where the thumbnails live and how big they are is morpheus/thumbs.js'
  // business, not picasso's — see scan(), which builds both from Thumbs so a
  // wallpaper terminus has already thumbnailed is found here under the same
  // name. Picasso carried its own cacheDir and thumbSize until that move and
  // then kept them, unread, describing a size and a directory neither of which
  // was in use any more.

  // How an image that is not the monitor's shape gets fitted. Cover by
  // default: this setup pairs a 2560x1440 with a rotated 1080x1920, and
  // anything else letterboxes one of them badly.
  //
  // Named rather than numbered — "crop" is a thing a person can choose,
  // Image.PreserveAspectCrop is a number that happens to be 2 — so the
  // translation happens here, where Image is already in scope, and the name is
  // what travels through oracle and through the picker.
  //
  // The ORDER is the ring alt+f walks, and it is not alphabetical: it runs
  // from the one that always fills the screen to the ones that increasingly
  // do not, so stepping through it is stepping along a single axis rather
  // than shuffling a bag of words.
  readonly property var fitModes: ["crop", "fit", "stretch", "pad", "tile"]
  readonly property var fitLabels: ({
    crop: "cropped", fit: "fitted", stretch: "stretched",
    pad: "centred", tile: "tiled"
  })

  // ── PER MONITOR, like the image itself ───────────────────────────────
  // One global fit is wrong the moment two monitors are different shapes,
  // which is the exact case picasso already handled for the image: this setup
  // pairs a 2560x1440 with a rotated 1080x1920, and an image that wants
  // cropping on one wants centring on the other.
  //
  // Two layers, and only two. `fits` holds the monitors that have been given
  // an answer of their own; everything else takes oracle's, which is the
  // DEFAULT rather than a fourth place to look. A monitor that has never been
  // touched therefore follows the setting, and one that has been set stays
  // set — including across replugging, because the key is the name.
  property var fits: ({})

  readonly property string defaultFit: {
    const m = Oracle.backgroundFit;
    return root.fitModes.indexOf(m) >= 0 ? m : "crop";
  }

  function fitFor(screenName) {
    const f = root.fits[screenName];
    return root.fitModes.indexOf(f) >= 0 ? f : root.defaultFit;
  }

  function fitLabelFor(screenName) {
    return root.fitLabels[root.fitFor(screenName)];
  }

  // Named rather than numbered on the way in, and numbered on the way out —
  // Image.PreserveAspectCrop is a number that happens to be 2, and nothing
  // outside this function should have to know that.
  function fillModeFor(screenName) {
    const m = root.fitFor(screenName);
    if (m === "fit") return Image.PreserveAspectFit;
    if (m === "stretch") return Image.Stretch;
    if (m === "pad") return Image.Pad;
    if (m === "tile") return Image.Tile;
    return Image.PreserveAspectCrop;
  }

  // One monitor's answer.
  function setFitFor(screenName, fit) {
    if (root.fitModes.indexOf(fit) < 0) return;
    const next = Object.assign({}, root.fits);
    next[screenName] = fit;
    root.fits = next;
    saveTimer.restart();
  }

  // Every monitor's answer: the default moves AND the overrides are cleared,
  // for the same reason setAll clears the per-monitor images. "All monitors"
  // that quietly left an old override in place would be a lie.
  function setFitAll(fit) {
    if (root.fitModes.indexOf(fit) < 0) return;
    root.fits = ({});
    Oracle.set("backgroundFit", fit);
    saveTimer.restart();
  }

  // The ring the picker's status line walks, the way cycleSort is the ring
  // alt+s walks. It steps the DEFAULT — a ring that stepped one monitor would
  // have to say which, and the status line is about the list, not a monitor.
  function cycleFit() {
    const i = root.fitModes.indexOf(root.defaultFit);
    root.setFitAll(root.fitModes[(i + 1) % root.fitModes.length]);
  }

  // What the status line shows: the default, plus a note when the monitors
  // do not agree — otherwise one word would be claiming to describe a screen
  // it has nothing to do with.
  readonly property bool fitsDiffer: Object.keys(root.fits).length > 0
  readonly property string fitLabel:
    root.fitLabels[root.defaultFit] + (root.fitsDiffer ? "*" : "")

  readonly property var extensions: ["jpg", "jpeg", "png", "webp", "bmp", "gif", "jxl", "avif"]

  // every wallpaper found, sorted, newest scan wins
  property var files: []
  property bool scanning: false
  property string scanError: ""

  // ── what is on screen ────────────────────────────────────────────────
  // monitor name -> path, plus "*" for the one every other monitor uses.
  // Keyed by name rather than index because a monitor's index changes when
  // you unplug the other one, and the wallpaper should not follow it.
  property var assignment: ({})

  readonly property string fallbackKey: "*"

  // Trigger for replaying the wallpaper zoom on unlock — bumped by shell
  // when Cerberus releases the session, watched by PicassoDaemon per-screen.
  property int introTick: 0
  property int holdTick: 0
  function replayIntro() { root.introTick++ }
  function holdIntro() { root.holdTick++ }

  // ── ordering ─────────────────────────────────────────────────────────
  // Newest first by default: a wallpaper you just dropped in is the one you
  // are most likely opening the picker to find. Held here rather than in the
  // popup so the choice survives closing and reopening it.
  readonly property var sortModes: ["recent", "name", "size"]
  property int sortIndex: 0
  readonly property string sortMode: root.sortModes[root.sortIndex]

  function cycleSort() {
    root.sortIndex = (root.sortIndex + 1) % root.sortModes.length;
  }

  function wallpaperFor(screenName) {
    const a = root.assignment;
    if (a[screenName]) return a[screenName];
    if (a[root.fallbackKey]) return a[root.fallbackKey];
    return "";
  }

  // one wallpaper everywhere: clears the per-monitor overrides too, otherwise
  // "set everywhere" would quietly leave an old override in place
  function setAll(path) {
    root.assignment = { [root.fallbackKey]: path };
    saveTimer.restart();
  }

  function setFor(screenName, path) {
    const next = Object.assign({}, root.assignment);
    next[screenName] = path;
    root.assignment = next;
    saveTimer.restart();
  }

  function clearAll() {
    root.assignment = ({});
    saveTimer.restart();
  }

  // ── scanning ─────────────────────────────────────────────────────────

  // Scan and thumbnail in one pass. It generates only what is missing, so the
  // cost is paid once per new wallpaper and never again — the picker used to
  // re-decode every full-size original on every filter keystroke.
  //
  // The cache key is path+mtime+size, which means replacing a wallpaper with a
  // different image of the same name produces a NEW cache filename. That is
  // what lets the picker turn Qt's image cache back on: a changed file is
  // never the same URL, so a decode failure can never be cached against it.
  function scan() {
    root.scanning = true;
    root.scanError = "";
    const exts = root.extensions.join("\\|");
    const dirQ = Strings.shellQuote(root.dir);
    // The KEY AND THE SIZE ARE NOT PICASSO'S ANY MORE. Both come from
    // morpheus/thumbs.js, so a wallpaper terminus has already thumbnailed is
    // found here under the name terminus' generator gave it, and vice versa.
    // find only has to produce the path now: the shared expression stats the
    // file itself, which is also what guarantees both sides hash exactly the
    // same bytes rather than two spellings of the same mtime.
    scanProc.command = ["sh", "-c",
      'mkdir -p ' + Strings.shellQuote(Thumbs.dir()) + '; ' +
      // Recursive: wallpapers arrive in per-pack subdirectories, and a
      // depth limit silently hid most of them. Dot-directories are pruned so
      // a stray .thumbnails or version-control dir is not treated as art.
      'find ' + dirQ + " -type f -not -path '*/.*' -iregex '.*\\.\\(" + exts + "\\)$' " +
      "-print 2>/dev/null | sort | " +
      'while IFS= read -r p; do ' +
      '  set -- "$p"; ' +
      Thumbs.keyExpr() +
      '  [ -s "$out" ] || magick "$1"[0] -auto-orient -thumbnail '
        + Thumbs.size() + 'x' + Thumbs.size() + ' -strip "$out" 2>/dev/null; ' +
      // path, thumb, mtime, size — the last two so the picker can order by
      // them without going back to the disk on every sort change
      '  if [ -s "$out" ]; then printf \'%s\\t%s\\t%s\\t%s\\n\' "$1" "$out" "$mt" "$sz"; ' +
      '  else printf \'%s\\t\\t%s\\t%s\\n\' "$1" "$mt" "$sz"; fi; ' +
      'done; ' +
      // The pool is shared, so "delete anything no wallpaper claims" would
      // delete every thumbnail terminus made. Age is the only question either
      // side can answer about the other's entries.
      Thumbs.sweep(30)];
    scanProc.running = true;
  }

  Process {
    id: scanProc
    stdout: StdioCollector {
      waitForEnd: true
      // `text` is StdioCollector's own property, not a signal parameter.
      // Declaring it as one shadowed the property with undefined, and the
      // scan quietly returned nothing at all.
      onStreamFinished: {
        root.files = Art.parseRows(text);
        root.scanning = false;
      }
    }
  }

  // The top of the tree is watched, so dropping a new image or a new pack in
  // pre-generates its thumbnail before the picker is ever opened. Only the top:
  // a watch per subdirectory would be a lot of machinery for a head start, and
  // the picker rescans on open regardless, so nothing is ever missed — a file
  // added deep in the tree just pays its 0.2s thumbnail on first open.
  FileView {
    id: dirWatch
    path: root.dir
    watchChanges: true
    printErrors: false
    onFileChanged: rescanDebounce.restart()
  }

  Timer {
    id: rescanDebounce
    // copying a batch of files in fires this repeatedly; scan once at the end
    interval: 500
    onTriggered: root.scan()
  }

  // ── persistence ──────────────────────────────────────────────────────

  FileView {
    id: stateFile
    path: Quickshell.statePath("picasso.json")
    blockLoading: true
    printErrors: false
  }

  Timer {
    id: saveTimer
    interval: 250
    onTriggered: stateFile.setText(
      Art.serializeState(root.assignment, root.fits))
  }

  // Pointed somewhere else, the list on screen is about a directory that is no
  // longer the one in use. dirWatch follows the new path on its own — it is
  // bound to this — but a watch only reports CHANGES to a directory, and
  // arriving at one is not a change to it, so the first scan has to be asked
  // for. Through the same debounce a file drop uses, so a path that lands in
  // two writes is still one scan.
  onDirChanged: rescanDebounce.restart()

  Component.onCompleted: {
    // before the scan, because it decides which directory is scanned
    root.readUserDirs();
    // parseState reads the old bare-map file as well as the current one, so
    // an install that predates per-monitor fit loads with its wallpapers
    // intact and no fits set — which is exactly what it had.
    const st = Art.parseState(stateFile.text());
    root.assignment = st.assignment;
    root.fits = st.fits;
    root.scan();
  }
}
