// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TERMINUS' pure half — what a directory is, and the commands that change one.
// No QML in here; TerminusWindow draws it and runs these.

// ── reading a directory ───────────────────────────────────────────────────
// find, not ls. `ls -A1p` gives names and a trailing slash and nothing else,
// so a size or a date costs a stat per row; find hands over every field in one
// pass, and -printf says exactly which ones rather than leaving them to be
// picked out of a column layout meant for a human.
//
// The separators are \037 UNIT SEPARATOR between fields and \036 RECORD
// SEPARATOR between rows, not tab and newline. A filename may legally contain
// a newline — and a tab, and a quote — so the obvious choice silently splits
// one file into two rows and mis-sizes both. These two bytes are the ones
// ASCII set aside for this job and no tool puts them in a name.
//
//   %y  type as it sits on disk      — 'l' says this entry IS a symlink
//   %Y  type after following it      — 'd'/'f', or 'N' for a broken link
//   %m  permission bits, octal       — the executable bit, for the exec glyph
//   %s  size in bytes
//   %T@ mtime as a unix float
//   %f  the name alone, without the path
// Written as escapes, not as the literal bytes: they are invisible in an
// editor, they do not survive a copy through a terminal, and a reader has no
// way to tell a lone \037 from a stray space.
const FIELD = "\u001f";
const RECORD = "\u001e";
// One level down from RECORD, for a record that carries more than a name.
const UNIT = "\u001f";

// The one -printf format, shared by the listing and by the search results, so
// the two cannot drift into producing rows of different shapes. Kept as the
// bare format as well, for the caller that hands find its arguments directly
// rather than writing a shell line — see statArgv.
const PRINTF_FMT = "%y\\037%Y\\037%m\\037%s\\037%T@\\037%p\\036";
const PRINTF = " -printf '" + PRINTF_FMT + "' ";

// A TRAILING SLASH on the search path, and it is not cosmetic.
//
// `find some-symlink-to-a-directory -maxdepth 1` prints nothing and exits 0:
// find treats the link as the file it is and never looks inside. So entering
// a symlinked directory in terminus produced an empty listing with no error to
// say why. `find some-symlink/` follows it, and a trailing slash on a real
// directory changes nothing at all — the printed paths are identical either
// way, single-slashed.
//
// Not `find -L`: that would resolve every entry as well, so %y would report
// the TARGET's type for each row and terminus would lose the one thing that
// tells it a row is a link.
function listPath(dir) {
  const d = String(dir);
  return d === "" || d.charAt(d.length - 1) === "/" ? d : d + "/";
}

function listCommand(dir) {
  return "find " + Strings.shellQuote(listPath(dir)) + " -maxdepth 1 -mindepth 1"
    + PRINTF + "2>/dev/null";
}

// The same listing, capped. A preview pane is a glance into a directory, and
// a glance at /usr/lib does not need forty thousand rows parsed and turned
// into objects to show you the first thirty.
function peekCommand(dir) {
  return "find " + Strings.shellQuote(listPath(dir)) + " -maxdepth 1 -mindepth 1"
    + PRINTF + "2>/dev/null | head -c 200000";
}

function parseListing(text, dir) {
  const rows = [];
  for (const rec of String(text || "").split(RECORD)) {
    if (rec === "") continue;
    const f = rec.split(FIELD);
    if (f.length < 6) continue;
    // %p, not %f: the search results need the full path and one format has to
    // serve both. The name is the tail of it.
    const full = f[5];
    const name = basename(full);
    if (name === "" || name === "." || name === "..") continue;
    const mode = parseInt(f[2], 8) || 0;
    rows.push({
      name: name,
      path: full,
      isDir: f[1] === "d",
      isLink: f[0] === "l",
      broken: f[1] === "N",
      // any of the three x bits — a file you could run earns its own glyph
      isExec: (mode & 73) !== 0,
      // kept whole, not just the exec bit: the permissions editor needs
      // somewhere to start, and re-statting the file to find out what it
      // already is would be asking a question find has already answered
      mode: mode,
      isHidden: name.charAt(0) === ".",
      size: parseInt(f[3], 10) || 0,
      mtime: parseFloat(f[4]) || 0
    });
  }
  return rows;
}

// ── paths ─────────────────────────────────────────────────────────────────
function joinPath(dir, name) {
  return dir === "/" ? "/" + name : dir + "/" + name;
}

function dirname(p) {
  const s = String(p);
  if (s === "/") return "/";
  const cut = s.lastIndexOf("/");
  return cut <= 0 ? "/" : s.slice(0, cut);
}

// The name without its extension, for yazi's `c n`. A leading dot is part of
// the name, not an extension: ".bashrc" has no stem to strip.
function stem(name) {
  const n = String(name);
  const cut = n.lastIndexOf(".");
  return cut > 0 ? n.slice(0, cut) : n;
}

// Trailing slashes are stripped first. fd marks a directory by appending one,
// and the obvious basename of "…/terminus/" is the empty string — which the row
// builder then threw away, so a search never showed a single directory.
function basename(p) {
  const s = String(p).replace(/\/+$/, "");
  if (s === "") return "/";
  const cut = s.lastIndexOf("/");
  return cut >= 0 ? s.slice(cut + 1) : s;
}

// The path as a row of pieces, each carrying the path it leads to, so the
// crumb bar is a set of jump targets rather than a label. Built here because
// it is string work, and the window should only have to render it.
// A PATH UNDER HOME IS WRITTEN FROM HOME. Nobody thinks of their downloads as
// the third thing down the filesystem, and "/ home / buck" spent two of the
// bar's steps — a good quarter of it on a shallow path — restating something
// every step after it already implies. `~` is what they would have typed.
//
// Only when home is a REAL prefix and not merely a string one: /home/buckley
// begins with /home/buck and is not inside it, which is what the trailing
// slash in the test is for. The crumb still carries the full path, so clicking
// it goes home rather than to a directory called "~".
function crumbs(path, home) {
  const p = String(path);
  const h = String(home || "");
  const under = h !== "" && (p === h || p.indexOf(h + "/") === 0);
  const out = under ? [{ label: "~", path: h }]
                    : [{ label: "/", path: "/" }];
  let at = under ? h : "";
  for (const part of (under ? p.slice(h.length) : p).split("/")) {
    if (part === "") continue;
    at += "/" + part;
    out.push({ label: part, path: at });
  }
  return out;
}

// WHERE a result was found, said as briefly as it can be said.
//
// A result's own name is already in the NAME column, so the half worth a
// column of its own is the directory it came out of — and against a search
// started in ~/Projects, "spoot/src" says everything
// "/home/buck/Projects/spoot/src" does and fits. The search root itself is
// ".", the answer every tool gives; anything NOT under the root keeps its full
// path, because a relative name for it would be a lie.
function whereOf(path, base) {
  const dir = dirname(path);
  let b = String(base || "");
  if (b !== "/") b = b.replace(/\/+$/, "");
  if (b === "") return dir;
  if (dir === b) return ".";
  const pre = b === "/" ? "/" : b + "/";
  return dir.indexOf(pre) === 0 ? dir.slice(pre.length) : dir;
}

// ── shape of the list ─────────────────────────────────────────────────────
// Directories first, always, whatever the sort is. Not a preference: a size
// sort that interleaves folders among files makes the folders unfindable, and
// every file manager worth using has settled on the same rule.
// `dirsFirst` defaults to true when it is not passed, so every caller that
// has not been told about it keeps the order it always had.
// `tags` is the path-keyed map the window holds (root.tagMarks), passed in
// rather than read off the row. A row deliberately carries no tag field —
// see the note beside enrich about metadata costing 4000 computations before
// first paint — so the one place that needs it is handed it.
function sortEntries(rows, key, desc, dirsFirst, natural, tags) {
  const dir = desc ? -1 : 1;
  const n = rows.length;

  // DECORATE, SORT, UNDECORATE — and the reason is arithmetic.
  //
  // The comparator used to read its key off the row on every comparison: a
  // lower-cased name, and for `kind` a rank and an extension worked out from
  // the name each time. A sort asks n log n questions, so four thousand rows
  // meant something like fifty thousand extractions to carry four thousand
  // rows' worth of information. Pulling the keys out once first is a linear
  // pass and leaves the comparator doing nothing but comparing.
  //
  // `i` is carried so ties keep the order they arrived in — a stable sort, so
  // a directory cannot shuffle under the cursor between two identical sorts.
  const dec = new Array(n);
  const kind = key === "kind";
  // "usage" is the disk-usage view's order: what is BIG, regardless of what
  // it is. It reads `du` — the measured recursive size, which the caller
  // attaches — and falls back to the entry's own size for a file, which is
  // already the whole truth about a file.
  const usage = key === "usage";
  // ── ORDERING BY TAG ──────────────────────────────────────────────────
  // By the COLOUR WHEEL, not alphabetically. The seven presets are declared
  // red -> orange -> yellow -> green -> blue -> purple -> grey, which is an
  // order the eye already knows; sorted by name they would come out blue,
  // green, grey, orange, purple, red, yellow, which is an order nobody has
  // ever wanted. A tag of your own has no place on that wheel, so those go
  // after the seven, among themselves by name.
  //
  // A file carries its tags normalised — deduped and sorted — so names[0]
  // is a stable choice for "which tag is this filed under" when there are
  // several. Untagged sorts last in both directions: it is the absence of
  // an answer rather than a low one, and flipping the order should not
  // bury everything that HAS a tag under everything that does not.
  const byTag = key === "tag";
  const wheel = {};
  if (byTag) for (let w = 0; w < TAG_WHEEL.length; ++w) wheel[TAG_WHEEL[w]] = w;
  for (let i = 0; i < n; ++i) {
    const r = rows[i];
    const nm = displaySound_(r);
    dec[i] = {
      r: r,
      // Directories first — EXCEPT in the usage view, where that rule is the
      // one thing you do not want: a 4GB file below every empty folder
      // answers the opposite of the question being asked. And except when
      // you have said otherwise, in which case a folder sorts by its name
      // like everything else.
      d: (usage || dirsFirst === false) ? 0 : (r.isDir ? 0 : 1),
      nm: nm,
      num: usage ? (r.du !== undefined && r.du !== null ? r.du : r.size)
         : (key === "size" ? r.size : (key === "time" ? r.mtime : 0)),
      kr: kind ? kindRank(r.name) : 0,
      ex: kind ? extOf(nm) : "",
      // rank on the wheel, and the tag's own name to break ties among the
      // custom ones. 1e9 is "no tag at all", which is why it is not sorted
      // against `dir` below.
      tw: byTag ? tagRank_(tags, r.path, wheel) : 0,
      tn: byTag ? tagFirst_(tags, r.path) : "",
      i: i
    };
  }

  // ── NAMES WITH NUMBERS IN THEM ────────────────────────────────────────
  // A plain string compare reads "file10" as less than "file2", because it
  // compares the "1" against the "2" and stops. Every numbered set anybody
  // owns — screenshots, episodes, renders — therefore came out shuffled:
  //   file10.txt  file2.txt  IMG_10.jpg  IMG_9.jpg  track1  track20  track3
  //
  // localeCompare with numeric ordering reads the digits as a number, which
  // is what a person does:
  //   file2.txt  file10.txt  IMG_9.jpg  IMG_10.jpg  track1  track3  track20
  //
  // It is the slower of the two and that is why it is a switch rather than
  // the only way: the names are already lowercased and cached (see
  // displaySound_), so a plain compare is a pointer comparison most of the
  // time, and a directory of four thousand files is a lot of comparisons.
  const byName = natural
    ? (a, b) => a.nm.localeCompare(b.nm, undefined,
                                   { numeric: true, sensitivity: "base" })
    : (a, b) => a.nm < b.nm ? -1 : (a.nm > b.nm ? 1 : 0);
  let cmp;
  if (key === "size" || key === "time" || usage)
    cmp = (a, b) => (a.num - b.num) * dir || byName(a, b);
  else if (kind)
    // Broad type first, extension second, name third — so every .jpg lands
    // together inside the pictures rather than merely near them.
    cmp = (a, b) => (a.kr - b.kr) * dir
      || (a.ex < b.ex ? -1 : (a.ex > b.ex ? 1 : 0)) * dir
      || byName(a, b);
  else if (byTag)
    // The untagged block is held at the bottom whichever way the rest is
    // turned — see the note above. Everything else flips as usual.
    cmp = (a, b) => {
      const au = a.tw >= 1e9, bu = b.tw >= 1e9;
      if (au !== bu) return au ? 1 : -1;
      if (au) return byName(a, b);
      return (a.tw - b.tw) * dir
        || (a.tn < b.tn ? -1 : (a.tn > b.tn ? 1 : 0)) * dir
        || byName(a, b);
    };
  else
    cmp = (a, b) => byName(a, b) * dir;

  dec.sort((a, b) => (a.d - b.d) || cmp(a, b) || (a.i - b.i));

  const out = new Array(n);
  for (let i = 0; i < n; ++i) out[i] = dec[i].r;
  return out;
}

// The seven presets in the order tags.js declares them, which is a colour
// wheel. Written out rather than imported: terminus.js is loaded by things
// that have no reason to pull in the tag store, and this is seven strings.
var TAG_WHEEL = ["red", "orange", "yellow", "green", "blue", "purple", "grey"];

// Where a path's first tag sits on the wheel. 1e9 for untagged, and
// TAG_WHEEL.length for a tag of the user's own, which puts every custom tag
// in one block after the seven and lets the name sort them within it.
function tagRank_(tags, path, wheel) {
  const t = tags ? tags[path] : null;
  if (!t || t.length === 0) return 1e9;
  const w = wheel[t[0]];
  return w === undefined ? TAG_WHEEL.length : w;
}

function tagFirst_(tags, path) {
  const t = tags ? tags[path] : null;
  return (t && t.length > 0) ? t[0] : "";
}

// ── ARRANGING: THE HEADING A ROW SITS UNDER ─────────────────────────────
// Finder calls it "Arrange by" and treats it as a second axis beside the
// sort. It is not one: a heading is only meaningful when the rows beneath
// it are together, which is exactly what the sort already decides. Group by
// anything other than the sort key and you get the same heading over and
// over down the list.
//
// So there is no second key here. This answers "what does THIS sort call
// the band this row falls in", and the caller shows a heading wherever the
// answer changes. One toggle, and it cannot produce nonsense.
//
// Returns "" when the current sort has no useful bands — which is every
// sort over a listing of one thing.
function groupLabel(row, key, tags, now) {
  if (!row) return "";
  // A directory is its own band under every sort, because dirsFirst has
  // already put them all at the top and they would otherwise be filed
  // under whatever their name or date happens to say.
  if (row.isDir && key !== "tag") return "Folders";

  if (key === "kind") return KIND_LABEL[kindOf(row.name)] || "Other";

  if (key === "tag") {
    const t = tags ? tags[row.path] : null;
    return (t && t.length > 0) ? t[0] : "Untagged";
  }

  if (key === "size" || key === "usage") {
    const n = (key === "usage" && row.du !== undefined && row.du !== null)
      ? row.du : row.size;
    if (!(n > 0)) return "Empty";
    if (n < 102400) return "Under 100 KB";
    if (n < 1048576) return "Under 1 MB";
    if (n < 104857600) return "Under 100 MB";
    if (n < 1073741824) return "Under 1 GB";
    return "Over 1 GB";
  }

  if (key === "time") {
    // Against a `now` handed in rather than read here: every row in one
    // listing must be filed against the SAME moment, or a sweep that
    // straddles midnight puts two rows a second apart in different bands.
    const t = Number(row.mtime) || 0;
    if (t <= 0) return "Unknown";
    const d = new Date(t * 1000);
    const day = new Date(now * 1000);
    day.setHours(0, 0, 0, 0);
    const midnight = day.getTime() / 1000;
    if (t >= midnight) return "Today";
    if (t >= midnight - 86400) return "Yesterday";
    if (t >= midnight - 86400 * 7) return "Previous 7 days";
    if (t >= midnight - 86400 * 30) return "Previous 30 days";
    if (d.getFullYear() === new Date(now * 1000).getFullYear())
      return MONTHS[d.getMonth()];
    return String(d.getFullYear());
  }

  if (key === "name") {
    const c = String(displaySound_(row) || "").charAt(0).toUpperCase();
    if (c === "") return "\u2014";
    // Digits and punctuation share one band rather than getting twelve
    // headings of one row each.
    return (c >= "A" && c <= "Z") ? c : "#";
  }
  return "";
}

var MONTHS = ["January", "February", "March", "April", "May", "June", "July",
              "August", "September", "October", "November", "December"];

// kindOf's vocabulary, in the words a heading wants. Its own table because
// "image" is the right token for a lookup and the wrong word for a heading.
var KIND_LABEL = {
  image: "Images", video: "Videos", audio: "Audio",
  archive: "Archives", document: "Documents", text: "Text",
  file: "Files", other: "Other"
};

// The query half on its own, for filtering a list that is ALREADY sorted.
// Sorting is order and filtering is membership, and filtering never disturbs
// order — so the sort can happen once when the directory or the sort key
// changes, and a keystroke only has to filter. Doing both per keystroke meant
// re-sorting a few thousand rows to answer a question about a substring.
// How well a name answers a query, or -1 for not at all.
//
// Substring first, because that is what most typing is and it should win
// outright: "conf" means .config, not some scattering of c-o-n-f across a
// longer name. Only when nothing contains the query does it fall back to a
// SUBSEQUENCE — the letters in order but not adjacent — which is what makes
// "cfg" reach .config and "dwn" reach Downloads.
//
// The score orders the survivors rather than deciding them. Higher is better,
// and every rule below is about putting the name you meant at the top:
// matching at the start beats matching in the middle, matching at a word
// boundary beats matching mid-word, and adjacent letters beat scattered ones.
// Word boundary, by character code rather than by regex.
//
// This is asked once per candidate per keystroke and, in the subsequence
// branch, once per LETTER of the query per candidate — so a four-thousand-row
// directory ran tens of thousands of regex tests for every key pressed. The
// question is only "is the character before this one alphanumeric", which is
// four comparisons.
function wordStart_(hay, k) {
  if (k === 0) return true;
  const c = hay.charCodeAt(k - 1);
  return !((c >= 97 && c <= 122) || (c >= 48 && c <= 57));
}

function fuzzyScore(hay, q) {
  if (q === "") return 0;
  const at = hay.indexOf(q);
  if (at >= 0) {
    // 1000 keeps every substring hit above every subsequence one
    let sc = 1000 - at;
    if (at === 0) sc += 200;
    else if (wordStart_(hay, at)) sc += 100;
    return sc - hay.length * 0.01;
  }

  let sc = 0, from = 0, last = -2, runs = 0;
  for (let i = 0; i < q.length; ++i) {
    const k = hay.indexOf(q.charAt(i), from);
    if (k < 0) return -1;
    // adjacent to the previous letter: the run is what makes a scattered
    // match feel deliberate rather than accidental
    if (k === last + 1) { runs++; sc += 8 + runs; }
    else { runs = 0; sc += 2; }
    if (k === 0) sc += 12;
    else if (wordStart_(hay, k)) sc += 6;
    last = k;
    from = k + 1;
  }
  return sc - hay.length * 0.02;
}

// Filtered and RANKED. The old version filtered on a substring and left the
// order alone; a fuzzy match without ranking puts the accidental hits among
// the intended ones, which is worse than not matching them at all.
//
// The sort is stable in effect because the score carries a length penalty and
// ties fall back to the name, so a directory does not shuffle under the cursor
// between two identical filters.
function filterQuery(rows, query) {
  const q = String(query || "").toLowerCase();
  if (q === "") return rows;
  const scored = [];
  for (let i = 0; i < rows.length; ++i) {
    const sc = fuzzyScore(displaySound_(rows[i]), q);
    if (sc >= 0) scored.push({ row: rows[i], sc: sc, i: i });
  }
  scored.sort((a, b) => (b.sc - a.sc) || (a.i - b.i));
  const out = [];
  for (let i = 0; i < scored.length; ++i) out.push(scored[i].row);
  return out;
}

// The lower-cased haystack for a row, cached ON THE ROW the first time it is
// asked for.
//
// Every sort compares names case-insensitively and every filter matches
// against them, so a four-thousand-row directory was calling toLowerCase about
// fifty thousand times per sort and again on every letter typed. Lazily rather
// than at parse: a directory that is listed and never sorted or filtered — the
// second pane's, most of the time — pays nothing.
function displaySound_(r) {
  if (r.hay === undefined) r.hay = String(r.name).toLowerCase();
  return r.hay;
}

// `hidePath` drops exactly one entry by its full path. It exists for the save
// dialog: see portalGhost in TerminusWindow — the application asking for the
// dialog has usually already written the file it is about to ask you where to
// put, so the thing you are naming is sitting in the listing behind the name
// field, looking like something that was already there.
function filterEntries(rows, query, showHidden, hidePath) {
  const q = String(query || "").toLowerCase();
  const hide = String(hidePath || "");
  // The common call is (rows, "", true) — every listing, both panes, on every
  // sort change. Handing back the same array rather than a copy of it is the
  // difference between allocating four thousand-element arrays for nothing and
  // not.
  if (q === "" && showHidden && hide === "") return rows;
  return rows.filter((r) => {
    if (hide !== "" && r.path === hide) return false;
    if (!showHidden && r.isHidden) return false;
    return q === "" || displaySound_(r).indexOf(q) >= 0;
  });
}

// ── what a PDF is, beside the page it renders ───────────────────────────
// pdfinfo prints "Key: value" lines; only a handful are worth a row. Title
// and author are the document's own idea of itself and are often absent or
// wrong, so they come first only when they are there at all.
function pdfInfoCommand(path) {
  return "pdfinfo -- " + Strings.shellQuote(path) + " 2>/dev/null";
}

function parsePdfInfo(text) {
  const out = {};
  const lines = String(text || "").split("\n");
  if (lines.length === 0) return null;
  for (const line of lines) {
    const c = line.indexOf(":");
    if (c < 0) continue;
    out[line.slice(0, c).trim().toLowerCase()] = line.slice(c + 1).trim();
  }
  if (out["pages"] === undefined && out["page size"] === undefined) return null;
  // "612 x 792 pts (letter)" — the name in the brackets is the useful half,
  // and the numbers are points, which nobody thinks in.
  let size = out["page size"] || "";
  const named = size.match(/\(([^)]+)\)/);
  if (named) size = named[1];
  return {
    pages: out["pages"] || "",
    pageSize: size,
    version: out["pdf version"] || "",
    title: out["title"] || "",
    author: out["author"] || "",
    // "no", or "yes (print:yes …)" — only the first word matters here
    encrypted: (out["encrypted"] || "").indexOf("yes") === 0 ? "yes" : ""
  };
}

// Milliseconds as a clock, for the one place that counts in them. Hours only
// when there are any — "0:03:07" for a three-minute track is a film's format
// worn by something that is not one.
function formatClock(ms) {
  const t = Math.max(0, Math.floor(Number(ms) / 1000));
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const sec = t % 60;
  const pad = (n) => (n < 10 ? "0" + n : String(n));
  return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec);
}

// ── how it reads ──────────────────────────────────────────────────────────
// Binary units, because that is what the filesystem allocates in and what
// every other tool on this machine reports.
function formatSize(n) {
  const v = Number(n) || 0;
  if (v >= 1073741824) return (v / 1073741824).toFixed(1) + " GiB";
  if (v >= 1048576) return (v / 1048576).toFixed(1) + " MiB";
  if (v >= 1024) return (v / 1024).toFixed(1) + " KiB";
  return v + " B";
}

// A date you can act on: how long ago while that is still the useful answer,
// and the actual day once "31d ago" has stopped being one.
function formatTime(epoch) {
  const t = Number(epoch) || 0;
  if (t <= 0) return "";
  const age = Date.now() / 1000 - t;
  if (age < 60) return "just now";
  if (age < 3600) return Math.floor(age / 60) + "m ago";
  if (age < 86400) return Math.floor(age / 3600) + "h ago";
  if (age < 2592000) return Math.floor(age / 86400) + "d ago";
  const d = new Date(t * 1000);
  const pad = (n) => String(n).padStart(2, "0");
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
}

// What the selection adds up to, for the status strip. Directories are left
// out of the total rather than counted at their entry size, which is the size
// of the directory RECORD — 4096 bytes for a folder holding a gigabyte — and
// would make the number a lie.
function selectionSize(rows) {
  let n = 0;
  for (const r of rows) if (!r.isDir) n += r.size;
  return n;
}

// ── colour, as yazi decides it ────────────────────────────────────────────
// Straight off the [filetype] rules in the ZENON flavor, in the order they are
// listed there, because yazi takes the FIRST rule that matches:
//
//   image/*                       #b6e0a4   Zenon.green
//   {audio,video}/*               #e0d8a4   Zenon.sand
//   archives                      #fab387   Zenon.yellow
//   application/{pdf,doc,rtf}     #9bbfbf   Zenon.cyan
//   inode/empty                   #a0a09b   grey
//   orphan                        #e78284   Zenon.red
//   link                          #c8a4e0   Zenon.magenta
//   exec                          #fab387   Zenon.yellow
//   directory fallback            #9bbfbf   Zenon.cyan
//   file fallback                 #dfdfdd   Zenon.white
//
// Yazi asks a mime database; this asks the extension. That is a real
// difference and it is the honest one to make here — a mime lookup is a
// process per row, and the answer only ever changes the colour of a name.
const CAT_EXTS = {
  media: {
    mp3:1, flac:1, wav:1, ogg:1, oga:1, opus:1, m4a:1, aac:1, wma:1, mid:1,
    mp4:1, mkv:1, webm:1, avi:1, mov:1, wmv:1, flv:1, m4v:1, mpg:1, mpeg:1,
    "3gp":1, ts:1
  },
  archive: {
    zip:1, rar:1, "7z":1, tar:1, gz:1, tgz:1, bz2:1, xz:1, zst:1, lzma:1,
    lz4:1, cpio:1, arj:1, xar:1, cab:1, iso:1, deb:1, rpm:1, pkg:1, jar:1
  },
  document: {
    pdf:1, doc:1, docx:1, rtf:1, odt:1, epub:1, djvu:1, ps:1
  }
};

function categoryOf(name) {
  if (isImage(name)) return "image";
  const n = String(name);
  const cut = n.lastIndexOf(".");
  if (cut <= 0) return "";
  const e = n.slice(cut + 1).toLowerCase();
  if (CAT_EXTS.media[e]) return "media";
  if (CAT_EXTS.archive[e]) return "archive";
  if (CAT_EXTS.document[e]) return "document";
  return "";
}

// ── what KIND of thing a name is ──────────────────────────────────────────
// Broader than categoryOf, which lumps audio and video together as "media"
// because that is all the colouring rules need. Sorting wants them apart: a
// folder of downloads is far more useful with the music in one run and the
// films in another.
//
// The order IS the sort order. Pictures first because a folder of them is the
// commonest reason to reach for this, and the two nameless groups last —
// "other" is a file with an extension nothing here recognises and "file" one
// with no extension at all, which is usually a script or a README.
const KIND_ORDER = ["image", "video", "audio", "document", "text", "archive",
                    "other", "file"];

// Text and code, which is most of what is in most directories and was landing
// in "other" — a column that calls a .md file "other" is a column nobody
// reads. Not a preview question: isText is about what the row SAYS it is, and
// bat decides what can actually be shown.
const TEXT_EXTS = {
  txt: 1, md: 1, markdown: 1, rst: 1, log: 1, csv: 1, tsv: 1,
  json: 1, yaml: 1, yml: 1, toml: 1, ini: 1, conf: 1, cfg: 1, env: 1,
  xml: 1, html: 1, htm: 1, css: 1, scss: 1, svg: 0,
  sh: 1, bash: 1, zsh: 1, fish: 1, ps1: 1,
  c: 1, h: 1, cc: 1, cpp: 1, hpp: 1, rs: 1, go: 1, py: 1, rb: 1, pl: 1,
  lua: 1, js: 1, mjs: 1, ts: 1, tsx: 1, jsx: 1, java: 1, kt: 1, cs: 1,
  qml: 1, vim: 1, el: 1, sql: 1, diff: 1, patch: 1, desktop: 1, service: 1
};

function isText(name) {
  return TEXT_EXTS[extOf(name)] === 1;
}

function extOf(name) {
  const n = String(name);
  const cut = n.lastIndexOf(".");
  // a leading dot is a hidden file, not an extension: ".bashrc" has none
  return cut > 0 ? n.slice(cut + 1).toLowerCase() : "";
}

function kindOf(name) {
  if (isImage(name)) return "image";
  if (isVideo(name)) return "video";
  if (isAudio(name)) return "audio";
  if (isArchive(name)) return "archive";
  const e = extOf(name);
  if (e === "") return "file";
  if (CAT_EXTS.document[e] || isFont(name)) return "document";
  if (isText(name)) return "text";
  return "other";
}

// ONE LOOKUP PER EXTENSION, EVER — not a walk through five tables per row.
//
// kindOf asks isImage, then isVideo, then isAudio, then isArchive, each of
// which splits the name again, and the kind sort asks it once per row. On a
// four-thousand-row directory that was the whole cost of the sort.
//
// The answer for a given extension is a constant, so it is worked out once and
// remembered. Asked of kindOf itself rather than by reading the tables
// directly: the tables are declared further down this file, so naming them
// here is a forward reference Qt warns about — and, worse, it would be a
// second copy of kindOf's order of questions, free to drift from the first.
// A directory holds a handful of distinct extensions, so this fills up almost
// immediately and then costs one property read.
var KIND_BY_EXT_ = ({});

function kindRank(name) {
  const e = extOf(name);
  if (e === "") return KIND_ORDER.indexOf("file");
  let r = KIND_BY_EXT_[e];
  if (r === undefined) {
    r = KIND_ORDER.indexOf(kindOf("x." + e));
    if (r < 0) r = KIND_ORDER.length;
    KIND_BY_EXT_[e] = r;
  }
  return r;
}

// ── previews ──────────────────────────────────────────────────────────────
// What Qt's own image loader will open. Checked by extension rather than by
// asking `file`, because a preview that costs a process per keypress is a
// preview you feel — and being wrong here shows a glyph instead of a picture,
// which is the cheapest possible way to be wrong.
// EVERYTHING THE INSTALLED DECODERS CAN READ, which is a great deal more than
// the dozen this used to list. Taken from the plugins actually present in
// /usr/lib/qt6/plugins/imageformats rather than from memory: Qt's own, plus
// qt6-imageformats (icns, jp2, mng, tga, tiff, wbmp, webp) and kimageformats
// (the kimg_* set — avif, dds, exr, heif, jxl, psd, qoi, raw, xcf and the rest).
//
// A name here only means "ask Qt to decode it". If a plugin is missing the
// Image simply fails and the row falls back to its glyph, which is what
// happened to every webp in the library while the decoder was absent — so the
// cost of listing one too many is nothing, and the cost of listing one too few
// is a file that silently never shows itself.
const IMAGE_EXTS = {
  // Qt's own
  png: 1, jpg: 1, jpeg: 1, jpe: 1, gif: 1, bmp: 1, svg: 1, svgz: 1,
  ico: 1, cur: 1, pbm: 1, pgm: 1, ppm: 1, pnm: 1, xbm: 1, xpm: 1,
  // qt6-imageformats
  webp: 1, tif: 1, tiff: 1, tga: 1, targa: 1, icns: 1, wbmp: 1,
  jp2: 1, j2k: 1, jpf: 1, jpx: 1, jpm: 1, mng: 1,
  // kimageformats
  avif: 1, avifs: 1, heif: 1, heic: 1, hif: 1, avci: 1, hej2: 1,
  jxl: 1, jxr: 1, hdp: 1, wdp: 1, dds: 1, exr: 1, hdr: 1, pic: 1,
  ff: 1, qoi: 1, pcx: 1, pfm: 1, phm: 1, psd: 1, psb: 1, pxr: 1,
  ras: 1, sun: 1, sct: 1, tim: 1, xcf: 1, kra: 1, krz: 1, ora: 1,
  iff: 1, ilbm: 1, lbm: 1, rgb: 1, rgba: 1, bw: 1, sgi: 1,
  ani: 1, eps: 1, epsf: 1, epsi: 1,
  // camera raw, via kimg_raw
  arw: 1, cr2: 1, cr3: 1, crw: 1, dcr: 1, dng: 1, erf: 1, kdc: 1,
  mef: 1, mos: 1, mrw: 1, nef: 1, nrw: 1, orf: 1, pef: 1, raf: 1,
  raw: 1, rw2: 1, sr2: 1, srf: 1, srw: 1, x3f: 1
};

// Video, for the thumbnails and the preview pane. Separate from isImage
// because the two are made differently — Qt decodes a picture itself, and a
// video has to have a frame pulled out of it first.
const VIDEO_EXTS = {
  mp4: 1, mkv: 1, webm: 1, avi: 1, mov: 1, wmv: 1, flv: 1, m4v: 1,
  mpg: 1, mpeg: 1, "3gp": 1, ts: 1, ogv: 1, m2ts: 1, mts: 1, vob: 1
};

function isVideo(name) {
  const n = String(name);
  const cut = n.lastIndexOf(".");
  if (cut <= 0) return false;
  return VIDEO_EXTS[n.slice(cut + 1).toLowerCase()] === 1;
}

// ── WHAT QT CANNOT OPEN, WHATEVER IT IS CALLED ──────────────────────────
// isImage answers "is this a picture", which is the right question for the
// glyph, the colour, the sort and the kind column. It is the wrong question
// for "can I point an Image at it": this Qt has decoders for about a quarter
// of the formats in IMAGE_EXTS, and the rest — every camera raw, the whole
// HEIF family, jxl, psd, xcf — fail on decode. A folder of phone photos
// previewed as nothing at all and wrote two warnings per file doing it.
//
// The answer is a thumbnail rendered by ImageMagick, which reads 51 of the
// 68 Qt cannot. This is the list that says which files to send that way
// rather than handing them to Qt first.
//
// DELIBERATELY NOT AUTHORITATIVE. Qt also sniffs content, so an extension
// list can only ever approximate it, and the plugins present differ per
// machine. Being wrong here costs nothing in either direction: a format
// wrongly listed gets a thumbnail it did not need, and one wrongly missing
// is caught when the Image fails and the caller remembers the extension —
// see root.blindExt. It is an optimisation with a safety net under it, not
// a source of truth, which is why it may be edited freely.
var QT_BLIND_EXTS = {
  // camera raw, every one of them
  arw: 1, cr2: 1, cr3: 1, crw: 1, dcr: 1, dng: 1, erf: 1, kdc: 1, mef: 1,
  mos: 1, mrw: 1, nef: 1, nrw: 1, orf: 1, pef: 1, raf: 1, raw: 1, rw2: 1,
  sr2: 1, srf: 1, srw: 1, x3f: 1,
  // the HEIF family and its neighbours
  avif: 1, avifs: 1, heif: 1, heic: 1, hif: 1, avci: 1, hej2: 1, jxl: 1,
  jxr: 1, hdp: 1, wdp: 1,
  // editor and exchange formats
  psd: 1, psb: 1, xcf: 1, kra: 1, krz: 1, ora: 1, exr: 1, hdr: 1, dds: 1,
  // the old raster zoo
  pcx: 1, ras: 1, sun: 1, sct: 1, tim: 1, pic: 1, pxr: 1, ff: 1, qoi: 1,
  pfm: 1, phm: 1, iff: 1, ilbm: 1, lbm: 1, rgb: 1, rgba: 1, bw: 1, sgi: 1,
  ani: 1, eps: 1, epsf: 1, epsi: 1
};

function qtBlind(name) {
  var n = String(name);
  var cut = n.lastIndexOf(".");
  if (cut <= 0) return false;
  return QT_BLIND_EXTS[n.slice(cut + 1).toLowerCase()] === 1;
}

function isImage(name) {
  const n = String(name);
  const cut = n.lastIndexOf(".");
  if (cut <= 0) return false;
  return IMAGE_EXTS[n.slice(cut + 1).toLowerCase()] === 1;
}

// ── previewing something that is not a picture ────────────────────────────
// bat, not head, when bat is there: it syntax-highlights, it knows markdown,
// and it stops at a line range so a huge file costs the same as a small one.
// --color=always because it is not writing to a terminal and would otherwise
// helpfully turn colour off.
function batCommand(path) {
  // --theme=ansi is the whole trick for keeping this in Zenon. It makes bat
  // emit ONLY the sixteen base ANSI colours instead of a theme's own hexes,
  // and the sixteen are ours to define — see xterm256 below. The alternative
  // was writing a Zenon .tmTheme for bat, which is a second copy of the
  // palette living outside Zenon.qml.
  // 90 lines, not 300. The pane shows forty at most, and every line past
  // that is paid for three times: bat highlights it, ansiToRich turns it into
  // markup, and Qt lays that markup out as rich text. That last one is the
  // expensive part and it is proportional to what it is given.
  return "exec bat --color=always --theme=ansi --style=plain --paging=never"
    + " --line-range=1:90 -- "
    + Strings.shellQuote(path) + " 2>/dev/null";
}

// A PDF is a picture of a page. pdftoppm renders the first one at a modest
// dpi into the cache directory; -singlefile keeps the name predictable so the
// pane can point at it without parsing pdftoppm's output.
function pdfCommand(path, outStem) {
  // mkdir first: the rendered page lives with the thumbnails now rather than
  // loose in the cache root, and on a fresh machine that directory does not
  // exist until the first thumbnail batch has made it.
  return "mkdir -p " + Strings.shellQuote(dirname(outStem)) + "; "
    + "pdftoppm -png -f 1 -l 1 -r 72 -singlefile -- "
    + Strings.shellQuote(path) + " " + Strings.shellQuote(outStem) + " 2>/dev/null";
}

// Everything terminus caches on disk lives under one directory, so clearing it is
// one rm and nothing is left behind in the cache root.
function terminusCacheDir() {
  return Paths.cacheDir() + "/terminus";
}

// Audio, which until now was only ever half of "media". It earns its own
// list because it previews differently from everything else: there is nothing
// to look at unless the file happens to carry cover art, and the interesting
// part is what the tags say.
const AUDIO_EXTS = {
  mp3: 1, flac: 1, wav: 1, ogg: 1, oga: 1, opus: 1, m4a: 1, aac: 1, wma: 1,
  aiff: 1, aif: 1, ape: 1, wv: 1, mka: 1, mid: 1, midi: 1
};

function isAudio(name) {
  return !!AUDIO_EXTS[extOf(name)];
}

// A font is previewed by BEING the preview: Qt can load the file and draw with
// it, which says more in one line of specimen than any list of facts about it.
// Only the formats Qt's FontLoader actually opens are listed — woff and woff2
// are web wrappers it does not read, and offering a preview that silently
// falls back to the default font would be worse than showing none.
const FONT_EXTS = { ttf: 1, otf: 1, ttc: 1, pfb: 1 };

function isFont(name) {
  return !!FONT_EXTS[extOf(name)];
}

function isPdf(name) {
  return /\.pdf$/i.test(String(name));
}

// ── disks ─────────────────────────────────────────────────────────────────
// lsblk in JSON, so there is nothing to parse by hand and nothing to break
// when a label contains a space. Only the leaves are of interest: a whole
// disk is not something you mount, its partitions are.
// FSAVAIL and FSSIZE come from lsblk itself, so knowing how full a disk is
// costs nothing extra — no df, no second process. They are only populated for
// a MOUNTED filesystem, which is exactly when the number is worth showing.
function disksCommand() {
  return "lsblk -J -o NAME,PATH,LABEL,SIZE,MOUNTPOINT,RM,TYPE,FSTYPE,FSAVAIL,FSSIZE"
    + " 2>/dev/null";
}

function parseDisks(text) {
  let tree;
  try { tree = JSON.parse(String(text || "{}")); } catch (e) { return []; }
  const out = [];

  const walk = (node) => {
    const kids = node.children || [];
    for (const k of kids) walk(k);
    // a node with children is a container, not a thing to mount
    if (kids.length > 0) return;
    if (node.type !== "part" && node.type !== "disk" && node.type !== "rom") return;
    // no filesystem means nothing to mount; swap and the boot partitions are
    // not places you browse
    const fs = String(node.fstype || "");
    if (fs === "" || fs === "swap") return;
    const mp = node.mountpoint;
    if (mp === "[SWAP]") return;
    out.push({
      name: String(node.label || node.name || ""),
      path: String(node.path || ""),
      size: String(node.size || ""),
      mount: mp ? String(mp) : "",
      removable: !!node.rm,
      fstype: fs,
      // strings as lsblk formats them ("412.3G"), or "" when not mounted
      avail: String(node.fsavail || ""),
      fsSize: String(node.fssize || "")
    });
  };

  for (const d of (tree.blockdevices || [])) walk(d);
  return out;
}

// Mounts the system is standing on. Offering to eject one is offering to take
// the floor out from under everything — udisks would refuse a busy /, but /home
// or a data partition might well unmount and take your session's files with it,
// and the honest answer is not to put the button there at all.
//
// Matched on the mountpoint rather than on `rm`, because removable says how the
// hardware is attached and this is a question about what the mount is FOR: an
// external disk holding /home is exactly as unejectable as an internal one.
const SYSTEM_MOUNTS = {
  "/": 1, "/home": 1, "/boot": 1, "/boot/efi": 1, "/efi": 1,
  "/usr": 1, "/var": 1, "/etc": 1, "/nix": 1, "/opt": 1, "/srv": 1
};

function isSystemMount(mp) {
  const m = String(mp || "");
  if (m === "") return false;                    // not mounted: safe to mount
  if (SYSTEM_MOUNTS[m]) return true;
  // anything nested under the boot partitions counts too
  return m.indexOf("/boot/") === 0 || m.indexOf("/efi/") === 0;
}

// udisksctl, not `mount`: it works without root for a user-session device,
// which is the entire reason a removable disk can be mounted from a file
// manager at all.
function mountCommand(path) {
  return "udisksctl mount -b " + Strings.shellQuote(path) + " 2>&1";
}

function unmountCommand(path) {
  return "udisksctl unmount -b " + Strings.shellQuote(path) + " 2>&1";
}

// What identifies a disk for "has the set changed" — the paths, in order, so
// plugging something in is a different string and a remount is not.
function diskKey(disks) {
  return disks.map((d) => d.path + ":" + d.mount).join("|");
}

// ── thumbnails ────────────────────────────────────────────────────────────
// They live in morpheus/thumbs.js now, shared with Picasso: the same pictures
// were being cached twice, at two sizes, under two names, in two directories.
// Nothing about them is terminus-specific, so nothing about them is here.

// ── ANSI to rich text ─────────────────────────────────────────────────────
// bat speaks SGR escapes and Qt's Text does not, so the colours have to be
// translated rather than stripped. Only the codes bat actually emits are
// handled — 24-bit and 256-colour foregrounds, bold, and the resets — and
// anything else is dropped, which loses a colour and never breaks the markup.
//
// The 256-colour cube is computed rather than tabled: 16-231 is a 6x6x6 cube
// and 232-255 is a grey ramp, both of which are formulas.
function xterm256(n) {
  // The sixteen, as Zenon defines them — including its own names for the
  // bright three it actually differentiates: bright black is `muted`, bright
  // red is `pink`, bright yellow is `sand`. The rest of the brights are the
  // base colour, because Zenon does not have a second one for them.
  const Z = Strings.zenonHex();
  const basic = [Z.black, Z.red, Z.green, Z.yellow, Z.blue, Z.magenta,
                 Z.cyan, Z.white, Z.muted, Z.pink, Z.green, Z.sand,
                 Z.blue, Z.magenta, Z.cyan, Z.white];
  if (n < 16) return basic[n];
  if (n < 232) {
    const c = n - 16;
    const lv = [0, 95, 135, 175, 215, 255];
    const hex = (v) => ("0" + v.toString(16)).slice(-2);
    return "#" + hex(lv[Math.floor(c / 36) % 6])
               + hex(lv[Math.floor(c / 6) % 6]) + hex(lv[c % 6]);
  }
  const g = 8 + (n - 232) * 10;
  const hx = ("0" + g.toString(16)).slice(-2);
  return "#" + hx + hx + hx;
}

function ansiToRich(text) {
  const src = String(text || "");
  let out = "";
  let open = 0;
  let i = 0;
  while (i < src.length) {
    const esc = src.indexOf("\u001b[", i);
    if (esc < 0) { out += Strings.escapeHtml(src.slice(i)); break; }
    out += Strings.escapeHtml(src.slice(i, esc));
    const end = src.indexOf("m", esc);
    if (end < 0) { i = src.length; break; }
    const codes = src.slice(esc + 2, end).split(";").map((n) => parseInt(n, 10) || 0);
    let k = 0;
    while (k < codes.length) {
      const c = codes[k];
      if (c === 0) {
        while (open > 0) { out += "</span>"; open--; }
        k++;
      } else if (c === 1) {
        out += "<span style=\"font-weight:700;\">"; open++; k++;
      } else if (c === 38 && codes[k+1] === 2) {
        out += "<span style=\"color:rgb(" + (codes[k+2]|0) + ","
          + (codes[k+3]|0) + "," + (codes[k+4]|0) + ");\">";
        open++; k += 5;
      } else if (c === 38 && codes[k+1] === 5) {
        out += "<span style=\"color:" + xterm256(codes[k+2]|0) + ";\">";
        open++; k += 3;
      } else if (c >= 30 && c <= 37) {
        out += "<span style=\"color:" + xterm256(c - 30) + ";\">"; open++; k++;
      } else if (c >= 90 && c <= 97) {
        out += "<span style=\"color:" + xterm256(c - 90 + 8) + ";\">"; open++; k++;
      } else k++;
    }
    i = end + 1;
  }
  while (open > 0) { out += "</span>"; open--; }
  // <pre>, because Qt's rich text collapses newlines and runs of spaces like
  // any other HTML — without it the whole file rendered as a single line.
  // pre-wrap, not plain pre. <pre> keeps the newlines and the runs of spaces,
  // which is the whole reason it is here — but it also refuses to break a long
  // line, and Text.wrapMode cannot overrule a tag. So a source file ran off
  // the right edge of the preview pane with no way to read the rest of it.
  // pre-wrap keeps everything pre keeps and wraps what overflows.
  return "<pre style=\"white-space: pre-wrap;\">" + out + "</pre>";
}


// A file is "text" if the first block holds no NUL. That is the same test
// every other tool uses, it needs nothing installed, and it costs a scan of
// what has already been read.
function looksBinary(text) {
  return String(text || "").indexOf("\u0000") >= 0;
}

// ── searching ─────────────────────────────────────────────────────────────
// Two searches, because yazi has two and they answer different questions:
// `s` is "where is the file called…", `S` is "which files contain…".
//
// Both print NUL-separated paths so a filename with a newline in it survives,
// and both are capped: a search that returns forty thousand rows has not
// answered anything, and building that list costs more than running it.
// Recursive, and FUZZY — artemis' two-step, in one pipe.
//
// fd on its own matches its argument as a regex against the filename, so
// "jnwn" finds nothing and "Terminus Window" finds nothing either. Artemis solved
// that by listing everything with fd and then ranking with `fzf --filter`,
// which is what makes typing four letters of a path work. Same here, minus
// artemis' index file: artemis re-searches one fixed root often enough to cache
// it, and terminus searches whatever directory you happen to be in.
//
// Directories first, exactly as artemis orders them, so they win ties. fd marks
// them with a trailing slash, which parseListing now strips.
// MATCHED AGAINST THE NAME, not against the whole path.
//
// fzf was handed complete paths, so the letters you typed could be satisfied
// by directory names three levels up — `spt` matched
// `/home/buck/Projects/spoot/src/main.rs` through the middle of "Projects" and
// scored it above a file actually called `spt`. That is what made the results
// read as random: every one of them was a genuine fuzzy hit, on a string you
// were not searching.
//
// `-d / --nth -1` restricts both the match and the score to the last path
// segment, which is the thing being named. The whole line is still printed.
function findCommand(dir, query) {
  const d = Strings.shellQuote(dir);
  const q = Strings.shellQuote(String(query).trim());
  // DIRECTORIES FIRST, each group ranked on its own. Both were fed through one
  // fzf before, which scored them together and interleaved them — a folder
  // called exactly what you typed could sit below eight files that merely
  // contain the letters. A place you can go is a different kind of answer from
  // a file you can open, and it is nearly always the one being looked for.
  //
  // `--nth -2` for the directories and `-1` for the files, because fd ends a
  // directory with a slash — so its last field is the empty string, and every
  // directory scored zero and vanished from the results entirely. The caller
  // strips the trailing slash again when it parses.
  const rank = (nth) => " | fzf --filter " + q + " -d / --nth " + nth
    + " 2>/dev/null";
  return "{ fd -t d -H --no-ignore --color=never . " + d + " 2>/dev/null"
    + rank(-2)
    + " ; fd -t f -H --no-ignore --color=never . " + d + " 2>/dev/null"
    + rank(-1)
    + " ; } | head -n 500 | tr '\\n' '\\0'";
}

// Sorted, because rg's is a PARALLEL walk and the order it finishes in is not
// an order at all — the same query twice ran the same files past you in two
// different arrangements. There is no relevance to preserve here the way there
// is for a name search: every one of these files contains what you asked for,
// so the useful order is the one you can predict.
// TWO THINGS MADE THIS TAKE A MINUTE AND A HALF, and they compounded.
//
// `--no-ignore` AND `--hidden` together switch off every filter ripgrep has:
// no .gitignore, no .ignore, no skipping of dot-directories. Pointed at a home
// directory that is what it says — walk .cache, .cargo/registry, the Steam
// library, all of it. Measured searching $HOME for "function": either flag on
// its own finishes in under a tenth of a second, and the two together took
// 79.2 seconds. Yazi passes neither; `rg --color=never --files-with-matches
// --smart-case` is its whole content search, which is why it answers instantly
// on the same tree.
//
// And `sort` sat between rg and the cap. `head -c` closes the pipe when it has
// enough, which is what lets rg stop early — but sort cannot emit its first
// byte until its input has ENDED, so the cap could never reach rg and the walk
// always ran to completion. The bound has to come before the sort to be a
// bound at all.
//
// HIDDEN FILES YES, .local NO — and that pairing is the whole answer.
//
// Plain --hidden costs 79 seconds searching $HOME, and the cap does not save
// you: a common word fills 2000 matches early and head closes the pipe, so rg
// dies young, but a RARE one — a name, which is what you search for most —
// never fills it, and rg walks every byte before it can say it found four
// things. "function" answered instantly and "kbuck" took 72 seconds from the
// same command on the same tree, which is what made this so hard to see.
//
// But the cost is not spread across the hidden directories. It is ONE of them.
// Measured for "kbuck" from ~:
//
//   no --hidden                  0.0s      24 hits
//   --hidden                    79.4s     846 hits
//   --hidden, minus .local       0.7s     840 hits
//
// .local is 819GB of Steam library on this machine and contributed SIX of the
// 846. Everything people actually grep for in a hidden directory — .config,
// .cache, dotfiles at the top of home — is in the other 840, and it arrives in
// under a second. So the exclusion is one entry rather than a policy.
//
// It is also scoped rather than absolute: the glob is relative to the search
// ROOT, so standing in ~/.local and searching still searches it. It only means
// "do not descend into .local on your way somewhere else".
//
// The rest: ripgrep's own ignore rules are respected, and the result count is
// capped where the cap can still be felt upstream. --smart-case is yazi's too
// — a lower-case query matches either case, one with a capital means it.
//
// Sorted AFTER that, because rg's is a parallel walk and the order it finishes
// in is not an order — the same query twice ran the same files past you in two
// different arrangements. Every one of these files contains what you asked
// for, so the useful order is the one you can predict. Past the cap it is the
// first 2000 rg found rather than the first 2000 alphabetically; that is the
// price of being able to stop it, and a search that broad is being narrowed
// again anyway.
// DIRECTORIES ONLY, for the send-to sheet's filter, and the WHOLE MACHINE.
// A file is never an answer to "where should this go", so unlike findCommand
// there is no second pass and nothing to interleave — which also halves the
// walk and is most of what pays for the scope.
//
// MEASURED BEFORE IT WAS WIDENED, warm cache, this machine:
//
//   ~ depth 8                9,989 dirs    ~30ms      (what this used to be)
//   / depth 8  no excludes  35,602 dirs   ~100ms
//   / depth 8  excludes     15,049 dirs    ~55ms
//   / depth 10 excludes     20,883 dirs    ~85ms      (this)
//   / unlimited excludes    66,455 dirs   ~215ms
//
// DEPTH 10, NOT 8, AND THAT IS NOT A ROUND-UP. Depth is counted from the
// search root, so `/` at 8 reaches only six levels into a home directory —
// LESS of the place you actually send things than the old home-only scope
// covered. Ten from / is eight from ~, which is where it started.
//
// NOT UNLIMITED: three times the time for, on the query this was measured
// with, exactly the same hits. Everything past ten levels was deeper noise.
//
// THE PSEUDO-FILESYSTEMS ARE CUT OUT or the rest does not matter: /proc,
// /sys, /dev and /run more than DOUBLE the walk and cannot contain a
// destination. fd's --one-file-system cannot do this job here, because /home
// is its own partition and would go with them.
//
// The cap cannot save any of this, and it is worth knowing why: `fzf
// --filter` reads all of stdin before it emits a line, so `head` never closes
// the pipe early. Cost scales with how many directories exist, not with how
// many match.
//
// `--nth -2` for the reason findCommand gives: fd ends a directory with a
// slash, so its last field is empty and every entry would score zero. The
// caller strips that slash back off.
// MATCHED AGAINST THE WHOLE PATH, not against the folder's own name. It used
// to pass `-d / --nth -2`, which pins fzf to the second-to-last slash-delimited
// field — the basename, since fd ends a directory with a slash. That made the
// obvious narrowing impossible: "config buck" could never find ~/.config,
// because "buck" is in the path and never in the name. Off the leash, fzf's
// space-separated terms AND together across the entire path, which is what
// everyone already means by typing a second word.
function dirFindCommand(query) {
  const q = Strings.shellQuote(String(query).trim());
  return "fd -t d -H --no-ignore --color=never --max-depth 10"
    + " -E /proc -E /sys -E /dev -E /run . / 2>/dev/null"
    + " | fzf --filter " + q + " 2>/dev/null"
    + " | head -n 120 | tr '\\n' '\\0'";
}

function grepCommand(dir, query) {
  return "rg --files-with-matches --smart-case --null --color=never --hidden"
    + " -g " + Strings.shellQuote("!.local")
    + " -- " + Strings.shellQuote(query) + " " + Strings.shellQuote(dir)
    + " 2>/dev/null | head -z -n 2000 | sort -z | head -c 400000";
}

// A found path becomes the same row shape the listing produces, so one
// delegate draws both. stat is asked once for the whole set rather than once
// per path — the difference on a two thousand row result is seconds.
// AS ARGV, NOT AS A SHELL LINE, and the difference is the whole point.
//
// Linux caps a SINGLE argument at MAX_ARG_STRLEN — 32 pages, 128KB — while the
// whole list may run to ARG_MAX, 2MB. Joining thousands of result paths into
// one `sh -c "find … "` string puts the entire search inside one argument, and
// a content search across a large tree goes past 128KB easily: 2722 matches
// measured 291KB here, and execve refused it with E2BIG.
//
// The failure was invisible from the outside. The search itself succeeded, the
// stat that turns its paths into rows never started, and the results came back
// empty — so a search that matched too much looked exactly like a search that
// matched nothing.
//
// Handed to find as separate arguments each path is its own short argument, so
// only the 2MB total applies, and grepCommand's own 400KB output cap keeps the
// whole list an order of magnitude below it.
//
// No `2>/dev/null` any more, because there is no shell to redirect with. That
// is acceptable here: every path came out of a search that had just listed it,
// so a path find cannot stat is a file that vanished in between — rare, and
// worth a line in the log rather than silence.
function statArgv(paths) {
  return ["find"].concat(paths).concat(["-maxdepth", "0", "-printf", PRINTF_FMT]);
}

// Results come back through the same parser the listing uses, because they are
// the same rows — that is the whole point of sharing one -printf format.
function parseStat(text) {
  return parseListing(text, "");
}

// What a directory actually holds. `du -sb` walks it, which is the only way
// to know — a directory's own size field is the size of the RECORD, 4096 bytes
// for a folder containing a gigabyte. It is asked for on demand, never while
// drawing a list: walking every row of /home would take longer than the panel.
// WHAT IS IN A DIRECTORY, as two numbers on two lines: files then directories.
//
// Recursive, deliberately, because the row sits directly under the total size
// and that size is the whole tree. Counting only the top level there would put
// two numbers side by side that are answers to different questions — "4 items,
// 30 GiB" reads as though four things weighed thirty gigabytes.
//
// Symlinks count as files rather than being followed: a link is a thing in the
// directory, and following it would count another directory's contents into
// this one's total and could walk in a circle doing it.
function countCommand(paths) {
  const q = paths.map((p) => Strings.shellQuote(p)).join(" ");
  return "find " + q + " -mindepth 1 \\( -type f -o -type l \\) 2>/dev/null | wc -l; "
    + "find " + q + " -mindepth 1 -type d 2>/dev/null | wc -l";
}

function sizeCommand(paths) {
  return "du -sbc -- " + paths.map((p) => Strings.shellQuote(p)).join(" ")
    + " 2>/dev/null | tail -1 | cut -f1";
}

// ── the verbs ─────────────────────────────────────────────────────────────
// ── how big a folder really is ────────────────────────────────────────────
// A directory's `size` is the size of its RECORD — 4096 bytes for a folder
// holding a gigabyte — so the listing shows a dash rather than a number that
// is never the one anybody means. The real answer costs a walk of the whole
// tree, which is why it is asked for rather than offered.
//
// -sb, not -sbc: one line per path and no total, because several folders can
// be measured at once and each needs its own answer. The output is
// "bytes<TAB>path", and paths can contain anything except a tab or a newline,
// so the first tab is the only split that is safe.
function dirSizeCommand(paths) {
  return "du -sb -- " + paths.map((p) => Strings.shellQuote(p)).join(" ")
    + " 2>/dev/null";
}

function parseDirSizes(text) {
  const out = {};
  for (const line of String(text || "").split("\n")) {
    const cut = line.indexOf("\t");
    if (cut <= 0) continue;
    const n = parseInt(line.slice(0, cut), 10);
    const p = line.slice(cut + 1);
    if (p !== "" && n >= 0) out[p] = n;
  }
  return out;
}

// A shell where you are standing. The same xdg-terminal-exec shape the bar's
// own click actions use.
// ── OPENING A SHELL WHERE YOU ARE STANDING ───────────────────────────────
// `xdg-terminal-exec` is the freedesktop way to ask "whatever terminal this
// user prefers": it reads ~/.config/xdg-terminals.list and falls back to
// guessing. It is the right default and it is not always right — not
// installed, or a stale list, and "open shell here" fails SILENTLY, with
// nothing the window can say about it.
//
// So `term` overrides it, and takes two shapes on purpose:
//
//   ""            the default above, untouched
//   "kitty"       a terminal to run, given `-e sh -c ...` — which kitty,
//                 foot, alacritty, wezterm and xterm all accept
//   "... %d ..."  a whole command line, with %d standing for the directory,
//                 already quoted
//
// The second covers everyone who just wants a different terminal; the third
// is there because terminals disagree about every flag except -e, and a
// setting that only took a binary would be a setting that broke on the first
// one that wanted its title spelled differently.
function shellCommand(dir, term) {
  const t = String(term || "").trim();
  const quoted = Strings.shellQuote(dir);
  const inner = Strings.shellQuote("cd " + quoted + " && exec $SHELL");

  if (t === "") {
    return "xdg-terminal-exec --title=terminus-shell -e sh -c "
      + inner + " >/dev/null 2>&1 &";
  }
  if (t.indexOf("%d") >= 0) {
    return t.split("%d").join(quoted) + " >/dev/null 2>&1 &";
  }
  return t + " -e sh -c " + inner + " >/dev/null 2>&1 &";
}

// yazi's `a`: a trailing slash means a directory, anything else a file.
// A NAME NOTHING IN THIS DIRECTORY IS USING.
//
// Creating something now makes it first and asks what to call it second, so it
// has to arrive with a name — "new file", or "new file 2" if that is taken.
// Worked out from the listing already in hand rather than by asking the disk:
// the listing is what the row will appear in, and a name free in it is free.
function freeName(rows, base) {
  const taken = {};
  for (let i = 0; i < rows.length; ++i) taken[rows[i].name] = true;
  if (!taken[base]) return base;
  for (let i = 2; i < 1000; ++i) {
    const n = base + " " + i;
    if (!taken[n]) return n;
  }
  return base + " " + Date.now();
}

// Like freeName, but it keeps the extension where a reader expects it:
// "report.pdf" becomes "report (1).pdf" rather than "report.pdf 2". The
// bracketed form is the one Keep both already writes on a paste, so a name
// made here and a name made there are the same shape.
//
// Last dot, which is the ordinary rule and the one the rename field itself
// works by. An archive's ".tar.zst" is the known exception — see
// archiveTargetCommand, which is handed its extension for exactly that
// reason — and is not what this is for.
function freeNameKeeping(rows, name) {
  const taken = {};
  for (let i = 0; i < rows.length; ++i) taken[rows[i].name] = true;
  if (!taken[name]) return name;
  const dot = name.lastIndexOf(".");
  // A LEADING dot is the whole name of a hidden file, not an extension:
  // ".zshrc" must not become " (1).zshrc".
  const cut = dot > 0 ? dot : name.length;
  const stem = name.slice(0, cut);
  const ext = name.slice(cut);
  for (let i = 1; i < 1000; ++i) {
    const n = stem + " (" + i + ")" + ext;
    if (!taken[n]) return n;
  }
  return stem + " " + Date.now() + ext;
}

function createCommand(dir, name) {
  const target = joinPath(dir, name.replace(/\/+$/, ""));
  if (/\/$/.test(name)) return "mkdir -p -- " + Strings.shellQuote(target);
  return "mkdir -p -- " + Strings.shellQuote(dirname(target))
    + " && touch -- " + Strings.shellQuote(target);
}

// yazi's `D`, which is not the trash. Kept separate from trashCommand on
// purpose: one of these is recoverable and the other is not, and they should
// not be reachable by the same key or built by the same function.
function deleteCommand(paths) {
  return "rm -rf -- " + paths.map((p) => Strings.shellQuote(p)).join(" ");
}

// gio open, NOT xdg-open, and the difference is TERMINAL APPLICATIONS.
//
// xdg-open on this system falls through to its generic branch, which runs the
// handler's Exec line as a plain child. For a desktop entry carrying
// `Terminal=true` — nvim's, and every other TUI's — that means nvim is started
// with no terminal attached at all: no window appears, nothing is drawn, and
// the process sits there forever. `ps` after a few attempts showed a pile of
// headless `nvim <file>` children of xdg-open and not one surface on screen.
//
// GLib honours Terminal=true and spawns the entry through xdg-terminal-exec,
// which lands in foot. Verified both ways on the same text file: xdg-open gave
// an orphan nvim, gio open gave `foot -e nvim <file>` and a window.
function openCommand(path) {
  return "gio open " + Strings.shellQuote(path) + " >/dev/null 2>&1 &";
}

// Something created a moment ago as an empty file, asked to be a directory
// instead — which is what the trailing slash at the end of `a` means. Becoming
// a directory is unmaking the file and making the other thing; there is no
// operation that converts one into the other.
//
// Only ever run against a path this window made seconds ago and nothing has
// had the chance to write to, which is why an unguarded rm is honest here.
function recreateAsDir(fresh, target) {
  return "rm -f -- " + Strings.shellQuote(fresh)
    + " && mkdir -p -- " + Strings.shellQuote(target);
}

function mkdirCommand(dir, name) {
  return "mkdir -p -- " + Strings.shellQuote(joinPath(dir, name));
}

// Make the folder and move the selection into it, in that order and in one
// shell — see gatherIntoFolder for why it cannot be two commands. `&&` so
// nothing is moved if the directory could not be made, and -- before the
// paths because a file called -r is still a file.
function gatherCommand(dir, name, paths) {
  const dest = Strings.shellQuote(joinPath(dir, name));
  return "mkdir -p -- " + dest + " && mv -- "
    + paths.map(function (p) { return Strings.shellQuote(p); }).join(" ")
    + " " + dest + "/";
}

// -T so a rename onto an existing DIRECTORY fails loudly instead of quietly
// moving the source inside it, which is mv's default and is never what a
// rename meant.
//
// AND A GUARD IN FRONT OF IT, because -T does not help with a FILE: mv
// replaces one without a word, and a rename is not a request to destroy
// anything. The caller asks first from the listing it already has — see
// commitRename — and this is what catches the gap between that listing and
// the disk. renameOverCommand is the answer to the question, and the only
// way to get the overwrite.
function renameCommand(path, newName) {
  const dst = Strings.shellQuote(joinPath(dirname(path), newName));
  return "[ -e " + dst + " ] && { echo 'already exists' >&2; exit 1; }; "
    + renameOverCommand(path, newName);
}

function renameOverCommand(path, newName) {
  return "mv -T -- " + Strings.shellQuote(path) + " "
    + Strings.shellQuote(joinPath(dirname(path), newName));
}

// ── how far along a copy is ───────────────────────────────────────────────
// rsync REPORTS it, which is better than measuring it. --info=progress2 gives
// a running percentage for the whole transfer rather than per file, and
// --remove-source-files turns the same command into a move.
//
// This replaced a du-based estimate — total the sources, poll the destination,
// divide — which worked but was approximate at every edge (sparse files, hard
// links, a destination that already held some of the names) and cost a process
// every 400ms to maintain.
//
// -a keeps permissions, times and links. --no-inc-recursive makes rsync scan
// everything up front, which is what lets the percentage mean anything from
// the start instead of climbing towards a total it is still discovering.
// What to do about a name the destination already has. Three answers, and
// which one you get is CHOSEN rather than assumed, because exactly one of them
// destroys something: overwrite is the only outcome a paste cannot be undone
// from, so it does not get to be the default that happens while you are not
// looking.
//
//   overwrite  rsync as it always was: the incoming copy wins
//   skip       --ignore-existing: keep what is there, take the rest
//   keep       both, the new one renamed "name (1).ext"
const CLASH = { overwrite: "overwrite", skip: "skip", keep: "keep" };

// Finding the free name is done in the SHELL, at the moment of writing, not
// here from the listing we happen to be holding. Two reasons: the listing can
// be seconds stale, and a transfer of several items creates names as it goes —
// "report (1).pdf" has to be taken into account by the time the second report
// arrives, and only the filesystem knows that.
//
// A dotfile has no extension to preserve: ${n%.*} on ".bashrc" leaves an empty
// stem and an extension of ".bashrc", which would produce " (1).bashrc". A
// directory has no extension either, whatever a dot in its name suggests.
// TAGS HAVE TO SURVIVE A COPY, and -a does not carry them: it is
// -rlptgoD, and extended attributes are -X, which is not in that list. A
// file copied with rsync as it stood arrived untagged.
//
// PROBED, NOT ASSUMED. Handed -X, rsync fails per file on a destination
// that cannot hold an attribute and exits 23 — so a perfectly good copy to
// an exFAT stick would have reported itself as a failed transfer, and
// terminus mounts those sticks itself, so that is the ordinary case and not
// an exotic one. One temp file in the destination answers the question
// before rsync is asked it; an unquoted $xf expands to nothing at all when
// the answer is no.
const XATTR_PROBE =
  "xf=\n" +
  "xprobe=$(mktemp \"$XDEST/.terminus-xattr.XXXXXX\" 2>/dev/null) && {\n" +
  "  setfattr -n user.xdg.tags -v probe -- \"$xprobe\" 2>/dev/null && xf=-X\n" +
  "  rm -f -- \"$xprobe\"\n" +
  "}\n";

const FREE_NAME =
  "terminus_free() {\n" +
  "  d=$1; n=$2; s=$3\n" +
  "  [ -e \"$d/$n\" ] || { printf '%s' \"$n\"; return; }\n" +
  "  if [ -d \"$s\" ]; then stem=$n; ext=\n" +
  "  else\n" +
  "    case $n in *.*) stem=${n%.*}; ext=.${n##*.} ;; *) stem=$n; ext= ;; esac\n" +
  "  fi\n" +
  "  [ -n \"$stem\" ] || { stem=$n; ext=; }\n" +
  "  i=1\n" +
  "  while [ -e \"$d/$stem ($i)$ext\" ]; do i=$((i+1)); done\n" +
  "  printf '%s' \"$stem ($i)$ext\"\n" +
  "}\n";

// Printed before each item in the modes that copy one at a time, so the panel
// can say "3 of 7" instead of watching the percentage drop back to zero six
// times with no explanation. Carried on \r, the same separator rsync's own
// progress uses, so one parser reads both kinds of line.
const ITEM_MARK = "@@TERMINUS-ITEM@@";

function transferCommand(paths, destDir, move, clash) {
  const mode = clash || CLASH.overwrite;
  const quoted = paths.map((p) => Strings.shellQuote(p));
  const dest = Strings.shellQuote(destDir);
  // $xf is set by XATTR_PROBE below, and is either -X or empty.
  const flags = "-a $xf --info=progress2 --no-inc-recursive"
    + (move ? " --remove-source-files" : "");

  const prologue = "XDEST=" + dest + "\n" + XATTR_PROBE;

  let cmd;
  if (mode === CLASH.keep) {
    // One rsync per item, because rsync renames only when it is given a single
    // source and a full target path — there is no per-file rename for a batch.
    cmd = prologue + FREE_NAME
      + "i=0\n"
      + "for p in " + quoted.join(" ") + "; do\n"
      + "  i=$((i+1))\n"
      + "  printf '" + ITEM_MARK + "%s\\r' \"$i\"\n"
      + "  t=$(terminus_free " + dest + " \"$(basename -- \"$p\")\" \"$p\")\n"
      + "  rsync " + flags + " -- \"$p\" " + dest + "/\"$t\" || exit 1\n"
      + "done\n";
  } else {
    // --ignore-times on overwrite, and it is not optional.
    //
    // rsync's quick check calls a file unchanged when its size and mtime
    // match, which is right for a sync and wrong for this: paste NEW over an
    // OLD of the same length and rsync transfers nothing, so the one answer
    // that promised "the incoming copy wins" silently did nothing at all.
    // Verified — two 4-byte files with equal mtimes, and the destination kept
    // its own contents. An explicit overwrite has to actually write.
    cmd = prologue + "rsync " + flags
      + (mode === CLASH.skip ? " --ignore-existing" : " --ignore-times")
      + " -- " + quoted.join(" ") + " " + Strings.shellQuote(destDir + "/")
      // EXIT ON FAILURE, so the sweep below cannot answer for it. Without
      // this, a transfer that failed and a sweep that succeeded added up to a
      // job that reported success — the keep-both branch has always had its
      // own `|| exit 1` and this branch simply never got one.
      + " || exit 1\n";
  }

  // --remove-source-files empties the source directories but leaves the
  // directories themselves, so a move has to sweep them afterwards.
  //
  // AND THE SWEEP MUST NOT DECIDE THE JOB'S FATE. `find` is handed the same
  // paths rsync was, and rsync has just deleted them — so for a move of plain
  // files every one of those paths is gone by the time find is asked about it,
  // and find exits non-zero for having been asked. Being the last command in
  // the script, its status became the script's: a move of files reported
  // itself as FAILED every single time, having done exactly what was asked.
  //
  // There is no meaningful failure here in any case. Nothing was promised
  // about directories that turn out not to be empty, and everything that can
  // genuinely fail has already exited above.
  if (move) {
    cmd += "find " + quoted.join(" ")
      + " -depth -type d -empty -delete 2>/dev/null\n"
      + "exit 0\n";
  }
  return cmd;
}

// rsync rewrites its progress line with a carriage return, so the stream is
// one long line with \r in it rather than many lines. The last percentage in
// whatever has arrived is the current one.
function parseProgress(text) {
  const m = String(text || "").match(/(\d+)%/g);
  if (!m || m.length === 0) return -1;
  return parseInt(m[m.length - 1], 10);
}

// Which item a "keep both" transfer has reached, or -1 for any other line.
function parseItem(line) {
  const t = String(line || "");
  const at = t.indexOf(ITEM_MARK);
  if (at < 0) return -1;
  const n = parseInt(t.slice(at + ITEM_MARK.length), 10);
  return isNaN(n) ? -1 : n;
}


// gio, not `rm`, and not a hand-rolled move into ~/.local/share/Trash.
//
// The XDG trash spec wants a .trashinfo file beside every trashed item holding
// its original path and the deletion time, and it wants name collisions
// resolved so two files called notes.txt from different directories both
// survive. gio does all of that, and refuses on filesystems where a trash
// cannot legally live — /tmp says "Trashing on system internal mounts is not
// supported" rather than pretending. A hand-rolled version gets the happy path
// right and loses the file on every other one.
function trashCommand(paths) {
  return "gio trash -- " + paths.map((p) => Strings.shellQuote(p)).join(" ");
}

// What is already there, asked BEFORE anything is written. cp and mv overwrite
// without a word, so the answer to this is the whole difference between a
// paste and a silent loss.
// ── THE SYSTEM CLIPBOARD ──────────────────────────────────────────────────
//
// Terminus kept its own private clipboard: `y` recorded a list of paths in a
// property and `p` rsynced them. That is fast and exact and it is not a
// clipboard — copy a file here and nothing else on the machine knew; copy an
// image out of a browser and there was nothing here to paste. A file manager
// that cannot exchange with the rest of the desktop is a file manager for one
// application.
//
// The internal list is KEPT, because it carries the copy/move distinction and
// the exact paths, and because rsync with progress is better than anything a
// clipboard can express. The system clipboard is written alongside it and read
// when the internal one is empty, so the two never disagree about an operation
// terminus itself started.
//
// text/uri-list, because it is the one type nearly everything understands for
// "here are some files". wl-copy offers a single type per invocation, so this
// is a choice: GTK file managers also speak x-special/gnome-copied-files,
// which carries copy-versus-cut, and picking it would trade every other
// application for that one distinction.
function clipboardCopyCommand(paths) {
  const uris = paths.map((p) => "file://" + encodeURI(p)).join("\r\n");
  return "printf '%s' " + Strings.shellQuote(uris)
    + " | wl-copy -t text/uri-list >/dev/null 2>&1";
}

// What the clipboard is holding, decided IN ONE ROUND TRIP.
//
// Asking for the type list and then asking again for the payload is two
// processes with a gap between them, and the clipboard can change in that gap
// — the second answer would be about something the first never saw. The shell
// decides and returns the answer already labelled.
//
// Three things can come back: a list of files, an image that exists only on
// the clipboard, or nothing worth having.
function clipboardPasteCommand(destDir) {
  const d = Strings.shellQuote(destDir);
  return FREE_NAME
    + 't=$(wl-paste --list-types 2>/dev/null)\n'
    // GNOME's own file-clipboard format leads with the operation — "copy" or
    // "cut" — and every GTK file manager writes it. Preferred when present
    // because it is the only one that says which of the two it was.
    + 'if printf \'%s\\n\' "$t" | grep -qx "x-special/gnome-copied-files"; then\n'
    + '  printf \'gnome\\036\'\n'
    + '  wl-paste -t x-special/gnome-copied-files 2>/dev/null\n'
    + '  exit 0\n'
    + 'fi\n'
    + 'if printf \'%s\\n\' "$t" | grep -qx "text/uri-list"; then\n'
    + '  printf \'uris\\036\'\n'
    + '  wl-paste -t text/uri-list 2>/dev/null\n'
    + '  exit 0\n'
    + 'fi\n'
    // An image with no file behind it: a screenshot, or something copied out
    // of a browser. There is nothing to copy FROM, so there is a file to write.
    + 'm=$(printf \'%s\\n\' "$t" | grep -m1 "^image/")\n'
    + '[ -n "$m" ] || { printf \'none\\036\'; exit 0; }\n'
    + 'ext=${m#image/}\n'
    + 'case $ext in jpeg) ext=jpg ;; svg+xml) ext=svg ;; x-*) ext=${ext#x-} ;; esac\n'
    + 'f=$(terminus_free ' + d + ' "Pasted image.$ext" "")\n'
    + 'wl-paste -t "$m" > ' + d + '/"$f" 2>/dev/null'
    + ' || { printf \'fail\\036\'; exit 0; }\n'
    // An empty file is a failed paste wearing a name; say so rather than
    // leaving a 0-byte thing in the directory.
    + '[ -s ' + d + '/"$f" ] || { rm -f -- ' + d + '/"$f"; printf \'fail\\036\'; exit 0; }\n'
    + 'printf \'wrote\\036%s\\036\' "$f"\n';
}

// A URL dropped in from outside — an image dragged off a web page, which
// arrives as an http address and not as a file. Fetched into the directory it
// was dropped on, under the name the server calls it.
//
// --remote-name-all would use the URL's last segment blindly, which is how you
// end up with a file called "800px-Foo.jpg?v=3". -J prefers the name the
// server states and -O falls back to the URL's own, and the whole thing lands
// in a free name rather than over anything already there.
// A PAGE IS NOT A PICTURE, and a 200 does not mean you got the file.
//
// This is why an image dragged out of a browser could land "corrupted": a lot
// of sites refuse hotlinked images not with an error but with an HTML page —
// a login wall, a "hotlinking not allowed" notice, an interstitial — served
// as 200 OK. curl -f only rejects HTTP failure codes, so the body was written
// out under the picture's own name and something.jpg on disk was markup. The
// file was never damaged in transit; it was never the picture.
//
// Three things, in order:
//   a Referer and a browser User-Agent, because that is the difference
//     between being served the image and being served the notice;
//   the type CHECKED after the fact, because no header can be trusted to
//     have told the truth;
//   and the extension CORRECTED from what actually arrived, so a picture
//     saved from a URL with no extension is not left unopenable.
function fetchUrlCommand(url, destDir, fallback) {
  const d = Strings.shellQuote(destDir);
  const u = Strings.shellQuote(url);
  // scheme://host/ — enough of a Referer to satisfy a same-origin check
  const origin = String(url).replace(/^([a-z]+:\/\/[^\/]+).*$/i, '$1') + '/';
  return FREE_NAME
    + 'f=$(terminus_free ' + d + ' ' + Strings.shellQuote(fallback) + ' "")\n'
    + 'curl -fsSL --max-time 120 '
    + '-A ' + Strings.shellQuote(
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        + '(KHTML, like Gecko) Chrome/124.0 Safari/537.36') + ' '
    + '-e ' + Strings.shellQuote(origin) + ' '
    + '-o ' + d + '/"$f" -- ' + u
    + ' || { rm -f -- ' + d + '/"$f"; exit 1; }\n'
    + '[ -s ' + d + '/"$f" ] || { rm -f -- ' + d + '/"$f"; exit 1; }\n'
    // What came back, according to the bytes rather than to the server.
    + 'm=$(file -b --mime-type -- ' + d + '/"$f" 2>/dev/null)\n'
    + 'case "$m" in\n'
    + '  text/html|text/xml|application/xhtml*)\n'
    // Kept out of the directory rather than left looking like a broken
    // picture: the drop failed, and a file that cannot be opened is a worse
    // answer than no file.
    + '    rm -f -- ' + d + '/"$f"; exit 1 ;;\n'
    + 'esac\n'
    // The name is a guess off the end of a URL; the type is not a guess. If
    // they disagree, and the URL gave nothing usable, take the real one.
    + 'case "$f" in\n'
    + '  *.*) ;;\n'
    + '  *)\n'
    + '    ext=""\n'
    + '    case "$m" in\n'
    + '      image/jpeg) ext=.jpg ;;\n'
    + '      image/png) ext=.png ;;\n'
    + '      image/gif) ext=.gif ;;\n'
    + '      image/webp) ext=.webp ;;\n'
    + '      image/avif) ext=.avif ;;\n'
    + '      image/svg+xml) ext=.svg ;;\n'
    + '      video/mp4) ext=.mp4 ;;\n'
    + '      video/webm) ext=.webm ;;\n'
    + '      application/pdf) ext=.pdf ;;\n'
    + '    esac\n'
    + '    [ -n "$ext" ] && mv -n -- ' + d + '/"$f" ' + d + '/"$f$ext"\n'
    + '  ;;\n'
    + 'esac\n';
}

// What to call a thing fetched from a URL when nothing better is known.
function urlFallbackName(url) {
  let u = String(url).split("#")[0].split("?")[0];
  const cut = u.lastIndexOf("/");
  let n = cut < 0 ? u : u.slice(cut + 1);
  try { n = decodeURIComponent(n); } catch (e) { /* leave it as it came */ }
  n = n.replace(/[\/\0]/g, "");
  return n === "" ? "download" : n;
}

// ── THE OPEN BRANCHES THAT ARE STILL THERE ──────────────────────────────
// openDirs is deliberately never pruned — walking out of a folder and back
// in should find it as you left it — and that is right for a session. It is
// wrong for a list restored from DISK, where every entry is a guess about a
// directory that may have been deleted months ago. Measured on this machine
// before it was: 59 of 70 remembered branches pointed at nothing.
//
// Two costs, and the second is the sharp one. The list is capped, so ghosts
// occupy slots and evict branches that do exist, and the feature quietly
// stops working. And openBranches hands every branch UNDER the current
// directory to inotifywait, filtered by prefix rather than by existence —
// inotifywait exits at once on a path that is not there, taking the watch on
// the directory down with it and leaving a listing that silently stops
// refreshing. In a session forgetVanished clears those out; a restored list
// has never been through it.
//
// find with -maxdepth 0, which is the one-shot way to ask "which of these
// exist" — the missing ones go to stderr and the survivors come back in one
// pass, NUL separated because a path may hold anything but NUL.
function livingDirsCommand(lists) {
  const parts = [];
  for (var i = 0; i < lists.length; ++i) {
    var l = lists[i] || [];
    // find with no paths is an error, not an empty answer.
    if (l.length > 0)
      parts.push("find "
        + l.map(function (p) { return Strings.shellQuote(p); }).join(" ")
        // `|| true`, because find exits nonzero for having been ASKED about a
        // path that is gone — which is the ordinary case here and not a
        // failure. The survivors are already on stdout by then.
        + " -maxdepth 0 -type d -print0 2>/dev/null || true");
    else parts.push("true");
  }
  return parts.join("; printf '\\036'; ");
}

function parseLivingDirs(text, n) {
  var out = [];
  var chunks = String(text || "").split(RECORD);
  for (var i = 0; i < n; ++i) {
    var c = chunks[i] === undefined ? "" : chunks[i];
    out.push(c.split("\u0000").filter(function (p) { return p !== ""; }));
  }
  return out;
}

function conflictCommand(names, destDir) {
  const d = Strings.shellQuote(destDir);
  // ── AND WHETHER IT IS A DIRECTORY ───────────────────────────────────
  // Because the answer to a clash is not the same word for both. rsync
  // -a MERGES a directory into one of the same name — the destination's
  // other contents are left exactly where they were, verified with two
  // trees and a file only the destination had — so "Overwrite" is what
  // happens to a file and never what happens to a folder. The scan says
  // which it is, and the card can then use the word that is true.
  const tests = names.map((n) => {
    const q = Strings.shellQuote(n);
    return "[ -e " + d + "/" + q + " ] && printf '%s\\037%s\\036' " + q
      + " \"$([ -d " + d + "/" + q + " ] && echo d || echo f)\"";
  });
  return tests.join("; ") + "; true";
}

// Whether the archive about to be written is already there, and what it would
// be called if the one that is there is kept. Both answers in one scan, for
// the reason conflictCommand exists: the archivers overwrite without a word.
//
// The extension is passed in rather than worked out, because an archive's is
// not the part after the last dot — trimming ".tar.zst" by that rule gives
// "name.tar (1).zst", which names the copy after a file type it is not.
function archiveTargetCommand(destDir, name, ext) {
  const d = Strings.shellQuote(destDir);
  const n = Strings.shellQuote(name);
  const e = Strings.shellQuote(ext);
  // Silent when the name is free, so an ordinary archive costs one stat and
  // asks nothing.
  return "[ -e " + d + "/" + n + " ] || exit 0\n"
    + "n=" + n + "; e=" + e + "; stem=${n%\"$e\"}\n"
    + "[ -n \"$stem\" ] || stem=$n\n"
    + "i=1\n"
    + "while [ -e " + d + "/\"$stem ($i)$e\" ]; do i=$((i+1)); done\n"
    + "printf '%s\\036%s\\036' \"$n\" \"$stem ($i)$e\"\n";
}

function parseConflicts(text) {
  return String(text || "").split(RECORD).filter((s) => s !== "");
}

// conflictCommand's own reader: [{ name, isDir }]. Separate from
// parseConflicts, which reads archiveTargetCommand's two bare fields and
// must go on seeing plain strings.
function parseClashes(text) {
  return String(text || "").split(RECORD)
    .filter(function (s) { return s !== ""; })
    .map(function (s) {
      const bits = s.split(UNIT);
      return { name: bits[0], isDir: bits[1] === "d" };
    });
}

// chmod, from nine booleans. Octal because that is what chmod takes and what
// every other tool reports, and because the symbolic form cannot express "set
// exactly this" without a mask.
function chmodCommand(paths, mode) {
  const oct = ("000" + (mode & 511).toString(8)).slice(-3);
  return "chmod " + oct + " -- "
    + paths.map((p) => Strings.shellQuote(p)).join(" ");
}

// The mode as the rwxrwxrwx string every listing shows, so the editor can be
// checked against `ls -l` without translating in your head.
function modeString(mode) {
  const bit = (i, ch) => ((mode >> i) & 1) ? ch : "-";
  return bit(8, "r") + bit(7, "w") + bit(6, "x")
       + bit(5, "r") + bit(4, "w") + bit(3, "x")
       + bit(2, "r") + bit(1, "w") + bit(0, "x");
}

// A name the filesystem will actually accept. A slash cannot appear in one at
// all, and the two dot names already belong to the directory itself.
function nameError(name) {
  const n = String(name || "");
  if (n === "") return "a name is required";
  if (n.indexOf("/") >= 0) return "a name cannot contain /";
  if (n === "." || n === "..") return "that name belongs to the filesystem";
  return "";
}

// ── the trash, and the way back out of it ───────────────────────────────
// gio puts a file IN the trash; getting it back out is our own job, because
// `gio trash --list` and `--restore` both need the gvfs trash backend, which
// is not installed here — asked, and it answers "Operation not supported".
//
// No real loss: the freedesktop spec is simple, and every trashed file has a
// .trashinfo beside it holding the path it came from. Reading that directly is
// more robust than depending on a daemon, and it is the same file every other
// trash implementation on the system writes.
function trashRoot() { return Paths.home() + "/.local/share/Trash"; }
function trashFilesDir() { return trashRoot() + "/files"; }
function isTrashDir(dir) { return String(dir) === trashFilesDir(); }

// Python, not shell, and for one specific reason: Path= is PERCENT-ENCODED
// per the spec. Decoding that in POSIX sh means sedding %XX into \xXX and
// feeding it through printf %b, which mangles any path containing a
// backslash — and a restore that picks the wrong destination puts a file
// somewhere you will never think to look for it.
const RESTORE_PY = [
  "import os, shutil, sys",
  "from urllib.parse import unquote",
  "root = sys.argv[1]",
  "mode = sys.argv[2]",
  "",
  "def original(info):",
  "    with open(info, 'r', errors='replace') as fh:",
  "        for line in fh:",
  "            if line.startswith('Path='):",
  "                return unquote(line[5:].strip())",
  "    return ''",
  "",
  "# 'path' mode is what undo uses: it knows where the file CAME FROM, not what",
  "# the trash decided to call it — gio appends a suffix when the name is taken,",
  "# so the two are not always the same string.",
  "names = []",
  "if mode == 'path':",
  "    want = set(sys.argv[3:])",
  "    infodir = os.path.join(root, 'info')",
  "    for entry in sorted(os.listdir(infodir)) if os.path.isdir(infodir) else []:",
  "        if not entry.endswith('.trashinfo'):",
  "            continue",
  "        if original(os.path.join(infodir, entry)) in want:",
  "            names.append(entry[:-len('.trashinfo')])",
  "else:",
  "    names = sys.argv[3:]",
  "",
  "for name in names:",
  "    info = os.path.join(root, 'info', name + '.trashinfo')",
  "    src = os.path.join(root, 'files', name)",
  "    if not os.path.isfile(info) or not os.path.exists(src):",
  "        sys.stderr.write('no trash record for ' + name + chr(10)); continue",
  "    dest = original(info)",
  "    if not dest:",
  "        sys.stderr.write('no original path for ' + name + chr(10)); continue",
  "    if not os.path.isabs(dest):",
  "        dest = os.path.join(os.path.expanduser('~'), dest)",
  "    if os.path.exists(dest):",
  "        sys.stderr.write('already exists: ' + dest + chr(10)); continue",
  "    parent = os.path.dirname(dest)",
  "    if parent:",
  "        os.makedirs(parent, exist_ok=True)",
  "    shutil.move(src, dest)",
  "    os.remove(info)",
  ""
].join("\n");

// `mode` is "name" when you are standing in the trash looking at the files, and
// "path" when undo is putting back something it watched you delete.
function restoreCommand(keys, mode) {
  return "python3 - " + Strings.shellQuote(trashRoot()) + " "
    + Strings.shellQuote(mode || "name") + " "
    + keys.map((n) => Strings.shellQuote(n)).join(" ")
    + " <<'TERMINUS_PY'\n" + RESTORE_PY + "TERMINUS_PY\n";
}

// ── archives ────────────────────────────────────────────────────────────
// bsdtar reads all of these and writes most of them, which is why it is the
// one tool here rather than a switch over tar/unzip/7z. 7z is the exception:
// libarchive will not create one, so that format keeps its own writer.
const ARCHIVE_EXTS = {
  zip: 1, tar: 1, gz: 1, tgz: 1, bz2: 1, tbz: 1, tbz2: 1, xz: 1, txz: 1,
  zst: 1, tzst: 1, "7z": 1, rar: 1, iso: 1, jar: 1, cab: 1, lz4: 1, lzma: 1
};

function isArchive(name) {
  const ext = String(name).split(".").pop().toLowerCase();
  return ARCHIVE_EXTS[ext] === 1;
}

// "archive.tar.gz" -> "archive", not "archive.tar"
function stripArchiveExt(name) {
  let n = String(name).replace(/\.(gz|bz2|xz|zst|lz4|lzma)$/i, "");
  return n.replace(/\.(tar|zip|7z|rar|iso|jar|cab|tgz|tbz2?|txz|tzst)$/i, "");
}

// A free DIRECTORY name, the same idea as terminus_free and for the same reason:
// extracting the same archive twice should give you two directories, not a
// merge of the two into one.
const FREE_DIR =
  "terminus_free_dir() {\n" +
  "  d=$1; n=$2\n" +
  "  [ -e \"$d/$n\" ] || { printf '%s' \"$n\"; return; }\n" +
  "  i=1\n" +
  "  while [ -e \"$d/$n ($i)\" ]; do i=$((i+1)); done\n" +
  "  printf '%s' \"$n ($i)\"\n" +
  "}\n";

// ── links ───────────────────────────────────────────────────────────────
// Both kinds, because they answer different questions: a symlink points at a
// path and breaks if it moves, a hard link is the same file under a second
// name and survives anything but deleting them all. -n so linking to an
// existing symlinked directory replaces the link rather than landing inside
// whatever it points at.
function linkCommand(paths, destDir, symbolic) {
  return "ln " + (symbolic ? "-sn" : "-n") + " -t "
    + Strings.shellQuote(destDir) + " -- "
    + paths.map((p) => Strings.shellQuote(p)).join(" ");
}

// ── A LINK BESIDE THE THING IT POINTS AT ────────────────────────────────
// The above needs somewhere ELSE to put the link, which is right when you
// have carried a yank to another directory and wrong when you just want an
// alias here. `ln -t .` cannot do it: the link would want the name the file
// already has, and ln refuses.
//
// So the name is derived instead — "notes.md" becomes "notes link.md",
// keeping the extension where a suffix on the end would hide it from
// everything that reads one. Through terminus_free, so making two aliases
// of the same file gives you two rather than an error.
//
// Symbolic only. A hard link beside the original is a second name for one
// inode in one directory, which is a thing almost nobody means and a good
// way to be surprised later by an edit that changed "both" files.
function linkHereCommand(paths) {
  let out = FREE_NAME;
  for (const p of paths) {
    const q = Strings.shellQuote(p);
    const base = basename(p);
    const dot = base.lastIndexOf(".");
    // A dotfile's leading dot is not an extension: ".zshrc" must not become
    // " link.zshrc".
    const stem = dot > 0 ? base.slice(0, dot) : base;
    const ext = dot > 0 ? base.slice(dot) : "";
    out += "d=$(dirname -- " + q + ")\n"
      + "n=$(terminus_free \"$d\" " + Strings.shellQuote(stem + " link" + ext)
      + " " + q + ")\n"
      + "ln -sn -- " + q + " \"$d/$n\"\n";
  }
  return out;
}

// ── WHICH DIRECTORIES HAVE ANYTHING IN THEM ─────────────────────────────
// A disclosure chevron promises there is something through it, and until
// this the list had no way to know: every directory got one, and half of
// them opened onto nothing.
//
// One shell for the whole listing, and one find per directory that STOPS
// AT THE FIRST ENTRY — `-quit` after a single `-printf .`. So the cost is
// one readdir apiece rather than a walk, whatever is inside.
//
// Prints the non-empty ones. The caller starts from the list it asked
// about, so silence about a directory is the answer "empty" rather than
// the absence of one.
function nonEmptyCommand(dirs) {
  if (!dirs || dirs.length === 0) return "true";
  const lines = dirs.map(function (d) {
    const q = Strings.shellQuote(d);
    return "[ -n \"$(find " + q + " -mindepth 1 -maxdepth 1 -printf . -quit"
      + " 2>/dev/null)\" ] && printf '%s\\0' " + q;
  });
  // A trailing `true` so a run where every directory is empty — every line
  // exiting nonzero — is still a success rather than a failed command.
  return lines.join("\n") + "\ntrue\n";
}

// ── quick actions ───────────────────────────────────────────────────────
// The two or three things you want to do to a file at the exact moment you
// are looking at it, done from the viewer rather than by finding the file
// again in another program. Finder calls them Quick Actions and puts them
// under the preview; the same idea, and the same short list.
//
// magick and ffmpeg are already required for the thumbnails, so none of
// this adds a dependency.

// ROTATION IS IN PLACE, which is the one destructive thing here and is
// deliberate: rotating a photo is correcting it, and a correction that
// leaves the wrong version behind under a similar name has not corrected
// anything. It is also the behaviour every other viewer has.
//
// -auto-orient FIRST, so a JPEG carrying an EXIF orientation is baked
// upright before the turn is applied — otherwise the tag and the pixels
// disagree afterwards and the picture appears to rotate by the wrong
// amount in whichever programs honour it.
function rotateCommand(path, degrees) {
  return "magick mogrify -auto-orient -rotate "
    + Strings.shellQuote(String(degrees)) + " -- " + Strings.shellQuote(path);
}

// CONVERSION WRITES A NEW FILE, because unlike a rotation it throws
// something away — a PNG turned into a JPEG cannot be turned back. Through
// terminus_free, so converting twice gives you two files rather than
// silently overwriting the first.
function convertCommand(path, ext) {
  const q = Strings.shellQuote(path);
  const base = basename(path);
  const dot = base.lastIndexOf(".");
  const stem = dot > 0 ? base.slice(0, dot) : base;
  return FREE_NAME
    + "d=$(dirname -- " + q + ")\n"
    + "n=$(terminus_free \"$d\" " + Strings.shellQuote(stem + "." + ext)
    + " " + q + ")\n"
    + "magick -- " + q + " \"$d/$n\"\n";
}

// The soundtrack, without re-encoding it: -vn drops the video and -c copy
// takes the audio stream across exactly as it was stored. Instant whatever
// the file's length, and bit-identical, which a re-encode would not be.
// The container follows the codec — .m4a holds the aac that nearly every
// mp4 carries — so this asks ffprobe rather than guessing.
function extractAudioCommand(path) {
  const q = Strings.shellQuote(path);
  const base = basename(path);
  const dot = base.lastIndexOf(".");
  const stem = dot > 0 ? base.slice(0, dot) : base;
  return FREE_NAME
    + "d=$(dirname -- " + q + ")\n"
    + "c=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name"
    + " -of default=nw=1:nk=1 -- " + q + " 2>/dev/null)\n"
    + "case $c in mp3) e=mp3 ;; opus) e=opus ;; vorbis) e=ogg ;;"
    + " flac) e=flac ;; *) e=m4a ;; esac\n"
    + "n=$(terminus_free \"$d\" " + Strings.shellQuote(stem) + "\".$e\" " + q + ")\n"
    + "ffmpeg -nostdin -v error -y -i " + q + " -vn -c copy -- \"$d/$n\"\n";
}

// ── bulk rename ─────────────────────────────────────────────────────────
// Renaming forty files is a text-editing problem, and for a long time the
// answer here was to hand the forty names to $EDITOR in a terminal and read
// the file back. It worked, and it meant the feature only existed if you had
// an editor configured, opened a window you then had to find, and could not
// tell you a name was illegal until after you had closed it.
//
// So the editing happens in terminus now — see the bulk card in
// TerminusWindow.qml — and what is left here is the part that was always the
// interesting half: deciding whether a proposed set of names is one we can act
// on, and turning it into moves that cannot destroy anything.

// What is wrong with each proposed name, by index: "" when the name is fine,
// otherwise the reason, short enough to sit on the row.
//
// ONE list of rules. The card marks a row and the gate refuses the batch, and
// they read the same function so they cannot disagree about what a legal name
// is.
//
// The seen-map has a NULL PROTOTYPE. A plain object inherits "toString",
// "constructor" and a dozen more, so a file actually called toString made the
// old duplicate check fire against a name nothing had used.
// ── the batch rename's toolkit ────────────────────────────────────────────
//
// Every one of these takes the list and returns a new list. None of them reads
// or writes anything else, which is what lets the card treat them as buttons:
// press, see the result in the rows, press another, and undo by pressing the
// one that got you here again. They are also, for the same reason, the only
// part of batch renaming that can be checked without a window.
//
// STEM ONLY is the option every one of them carries, because it is the thing
// people actually mean nine times in ten. "Lowercase these" means the name,
// not the .JPG that the camera wrote and that the next program will look for.
function splitExt(name) {
  const n = String(name);
  // A leading dot is the whole name of a dotfile, not an empty stem with an
  // extension — ".bashrc" has no extension to preserve.
  const at = n.lastIndexOf(".");
  if (at <= 0) return [n, ""];
  return [n.slice(0, at), n.slice(at)];
}

function mapPart(names, stemOnly, fn) {
  return names.map((name) => {
    if (!stemOnly) return fn(String(name));
    const parts = splitExt(name);
    return fn(parts[0]) + parts[1];
  });
}

// Literal by default and a REGEX when asked. An invalid pattern returns the
// names untouched rather than throwing: the field is being typed into, so it
// is invalid most of the time it is read.
function bulkReplaceIn(names, find, repl, useRegex, stemOnly) {
  const f = String(find === undefined ? "" : find);
  if (f === "") return names.slice();
  const r = String(repl === undefined ? "" : repl);
  if (!useRegex) return mapPart(names, stemOnly, (s) => s.split(f).join(r));
  let re;
  try { re = new RegExp(f, "g"); } catch (e) { return names.slice(); }
  return mapPart(names, stemOnly, (s) => s.replace(re, r));
}

function titleCase(s) {
  return s.replace(/([^\s\-_.]+)/g, (w) =>
    w.charAt(0).toUpperCase() + w.slice(1).toLowerCase());
}

function bulkCase(names, mode, stemOnly) {
  if (mode === "lower") return mapPart(names, stemOnly, (s) => s.toLowerCase());
  if (mode === "upper") return mapPart(names, stemOnly, (s) => s.toUpperCase());
  if (mode === "title") return mapPart(names, stemOnly, titleCase);
  return names.slice();
}

// Runs of whitespace and underscores collapsed to one space, and the ends
// trimmed. The commonest tidy-up there is, and the one hardest to do by hand
// across forty rows.
function bulkTidy(names, stemOnly) {
  return mapPart(names, stemOnly, (s) =>
    s.replace(/[\s_]+/g, " ").replace(/\s*-\s*/g, " - ").trim());
}

// Numbered in the order they are listed, which is the order they are shown —
// so sorting the listing before opening the card is how you choose the order.
// Padded to the width of the LAST number, so 1..10 is 01..10 and never 1..10
// mixed, unless a wider pad is asked for.
function bulkNumber(names, start, pad, where, sep, stemOnly) {
  const from = parseInt(start, 10);
  const base = isNaN(from) ? 1 : from;
  const last = base + names.length - 1;
  const width = Math.max(parseInt(pad, 10) || 0, String(last).length);
  const s = sep === undefined ? " " : String(sep);
  return names.map((name, i) => {
    let num = String(base + i);
    while (num.length < width) num = "0" + num;
    const apply = (str) => where === "prefix" ? num + s + str : str + s + num;
    if (!stemOnly) return apply(String(name));
    const parts = splitExt(name);
    return apply(parts[0]) + parts[1];
  });
}

// ── add text ────────────────────────────────────────────────────────────
// The second of Finder's three modes, and the one find/replace cannot do at
// all: there is no pattern to FIND when what you want is the same word in
// front of every name. Literal always — a prefix is not an expression, and
// honouring the regex switch here would only mean "\d" silently going in as
// two characters some of the time.
function bulkAddText(names, text, where, stemOnly) {
  const t = String(text === undefined ? "" : text);
  if (t === "") return names.slice();
  return mapPart(names, stemOnly, (s) => where === "before" ? t + s : s + t);
}

// Today, as the name a file sorts by. ISO order rather than anything local:
// a dated batch is nearly always one you are about to sort by name, and only
// this order makes those two the same thing.
function formatStamp() {
  const d = new Date();
  const p = (n) => (n < 10 ? "0" : "") + n;
  return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
}

// ── format ──────────────────────────────────────────────────────────────
// A name built from scratch rather than edited: every row becomes the same
// custom text plus whatever tells them apart. The old name is DISCARDED,
// which is the whole difference between this and the other two modes and the
// reason it is worth its own mode rather than another verb.
//
// Index and counter differ only in padding, and they are still kept apart —
// for the same reason Finder keeps them apart. "1, 2, 3" and "00001, 00002"
// are two different intentions and picking between them by typing a pad
// width is a worse question than picking between two words.
function bulkFormat(names, fmt, kind, where, start, sep, stemOnly) {
  const base = String(fmt === undefined ? "" : fmt);
  // A date needs no custom text to be a complete name; an index alone would
  // rename every file to a bare number, which is a thing you do by accident
  // and not on purpose.
  if (base === "" && kind !== "date") return names.slice();
  const from = parseInt(start, 10);
  const first = isNaN(from) ? 1 : from;
  const stamp = formatStamp();
  const s = sep === undefined ? " " : String(sep);
  // Padded to the width of the LAST index, so 1..10 is 01..10 throughout
  // rather than 1..9 then 10 — the same rule bulkNumber follows.
  const width = String(first + names.length - 1).length;
  return names.map((name, i) => {
    let tail;
    // DATE, AND THEN AN INDEX IF IT HAS TO. Every file in one batch gets the
    // same date, so a date alone renames forty files to one name — which
    // bulkIssues correctly refuses, leaving a mode that can never apply. The
    // index is what makes the date a name rather than a collision, and it is
    // left off entirely when there is only one file to rename.
    if (kind === "date") {
      tail = names.length > 1 ? stamp + s + String(first + i) : stamp;
    }
    else if (kind === "counter") {
      let n = String(first + i);
      while (n.length < 5) n = "0" + n;
      tail = n;
    } else {
      let n = String(first + i);
      while (n.length < width) n = "0" + n;
      tail = n;
    }
    const built = base === "" ? tail
      : (where === "before" ? tail + s + base : base + s + tail);
    return stemOnly ? built + splitExt(name)[1] : built;
  });
}

function bulkIssues(oldNames, newNames) {
  const out = [];
  const seen = Object.create(null);
  for (let i = 0; i < newNames.length; ++i) {
    const to = String(newNames[i] === undefined ? "" : newNames[i]).trim();
    if (to === "") { out.push("empty"); continue; }
    if (to.indexOf("/") >= 0) { out.push("has a /"); continue; }
    if (to === "." || to === "..") { out.push("reserved"); continue; }
    if (seen[to] !== undefined) {
      out.push("same as row " + (seen[to] + 1));
      continue;
    }
    seen[to] = i;
    out.push("");
  }
  return out;
}

// The renames a proposed set amounts to, or null if the set is not one we can
// act on. A name that did not change is not a rename. Anything illegal refuses
// the WHOLE batch, because a bulk rename that half-applies is worse than one
// that does not run.
function bulkPairs(oldNames, newNames) {
  if (!newNames || newNames.length !== oldNames.length) return null;
  const bad = bulkIssues(oldNames, newNames);
  for (let i = 0; i < bad.length; ++i) if (bad[i] !== "") return null;
  const pairs = [];
  for (let i = 0; i < newNames.length; ++i) {
    const to = String(newNames[i]).trim();
    if (to !== oldNames[i]) pairs.push([oldNames[i], to]);
  }
  return pairs;
}

// Find-and-replace across the whole set at once, which is the thing the editor
// was really being borrowed for.
//
// PLAIN TEXT, not a regular expression. These strings are filenames, and
// filenames are full of dots and brackets and parentheses — quietly treating
// "(1)" as a capture group would make the tool a trap. An empty needle changes
// nothing rather than inserting between every character.
function bulkReplace(names, find, repl) {
  const f = String(find === undefined ? "" : find);
  if (f === "") return names.slice();
  const r = String(repl === undefined ? "" : repl);
  return names.map((n) => String(n).split(f).join(r));
}

// Renamed through a temporary name when the new name is one that another file
// in the same batch still has. Swapping two names is the obvious case, and
// doing it directly would destroy one of them.
function bulkRenameApply(dir, pairs) {
  const d = Strings.shellQuote(dir);
  let cmd = "cd " + d + " || exit 1\n";
  const stamp = "terminus.tmp." + Date.now() + ".";
  for (let i = 0; i < pairs.length; ++i) {
    cmd += "mv -n -- " + Strings.shellQuote(pairs[i][0]) + " "
      + Strings.shellQuote(stamp + i) + " || exit 1\n";
  }
  for (let i = 0; i < pairs.length; ++i) {
    cmd += "mv -n -- " + Strings.shellQuote(stamp + i) + " "
      + Strings.shellQuote(pairs[i][1]) + " || exit 1\n";
  }
  return cmd;
}

// ── open with ───────────────────────────────────────────────────────────
// The applications that claim this file's type, with the names they call
// themselves. One process rather than one per candidate: gio names the desktop
// files, and the Name= is pulled straight out of them.
function appsCommand(path) {
  return "m=$(xdg-mime query filetype " + Strings.shellQuote(path) + " 2>/dev/null); "
    + "[ -n \"$m\" ] || exit 0; "
    // THE TYPE ITSELF, first, as a record of its own.
    //
    // It is needed twice — once to find what already handles this file, and
    // again to REGISTER something when nothing does — and asking xdg-mime a
    // second time is a second process to answer a question already answered.
    // One field where every other record has three, which is exactly how
    // parseApps tells it apart from an application.
    + "printf '%s\\036' \"$m\"; "
    // AND THE DEFAULT, as a second one-field record. The registered list below
    // is every application that claims the type; which of them actually opens
    // it on a double click is a different question, and gio prints that answer
    // on a line the `^\t` filter deliberately drops.
    + "printf '%s\\036' \"$(xdg-mime query default \"$m\" 2>/dev/null)\"; "
    + "gio mime \"$m\" 2>/dev/null | sed -n 's/^\\t//p' | awk '!seen[$0]++' | "
    + "while read -r id; do "
    // the shared XDG search path — see morpheus/Desktop.qml. This used to be
    // two hardcoded directories, which could not see an entry installed
    // anywhere else.
    + "for dir in " + Desktop.dirsExpr() + "; do "
    + "if [ -f \"$dir/$id\" ]; then "
    + "nm=$(sed -n 's/^Name=//p' \"$dir/$id\" | head -1); "
    // the FULL PATH as well as the id: gio launch takes a file rather than an
    // id, and this loop is already standing in the directory that holds it
    + "printf '%s\\037%s\\037%s\\036' \"$id\" \"${nm:-$id}\" \"$dir/$id\"; "
    + "break; fi; done; done";
}

// The type appsCommand led with, or "" if it printed none — which is what a
// file xdg-mime could not identify looks like, and is not an error: it means
// there is nothing to register a handler against.
function parseAppsMime(text) {
  const recs = String(text || "").split(RECORD);
  if (recs.length === 0) return "";
  const f = recs[0].split(FIELD);
  // one field is the type; three is an application, from output written before
  // the type was led with
  return f.length === 1 ? f[0].trim() : "";
}

// The desktop id that currently opens this type, or "" if nothing does. The
// second record, for the same reason the type is the first: asking a second
// process for something a running one already knows is a process wasted.
function parseAppsDefault(text) {
  const recs = String(text || "").split(RECORD);
  if (recs.length < 2) return "";
  const f = recs[1].split(FIELD);
  return f.length === 1 ? f[0].trim() : "";
}

// Making one of them THE one, without launching it — the half of
// adoptAppCommand that is about the type rather than about this file. Same
// `gio mime` for the same reason: it writes [Added Associations] as well as
// the default, and the scan can only see what is registered.
function setDefaultAppCommand(desktopId, mime) {
  const id = Desktop.fileName(desktopId);
  if (String(mime || "") === "" || String(id || "") === "") return "true";
  return "gio mime " + Strings.shellQuote(mime) + " " + Strings.shellQuote(id);
}

function parseApps(text) {
  const out = [];
  const recs = String(text || "").split(RECORD);
  for (let i = 0; i < recs.length; ++i) {
    if (recs[i] === "") continue;
    const f = recs[i].split(FIELD);
    // the path is the third field. An entry parsed from older output has only
    // the first two, and a row with no file simply cannot be launched — which
    // the caller checks, rather than building a menu entry that does nothing.
    if (f.length >= 2)
      out.push({ id: f[0], name: f[1], file: f.length >= 3 ? f[2] : "" });
  }
  return out;
}

// Launching by ID rather than by the file the scan found.
//
// The scan reports the FIRST file with that id, which is a user entry in
// ~/.local/share/applications whenever one exists. That entry can be stale —
// buck's nvim.desktop pointed at kitty long after kitty was uninstalled — and
// gio refuses to load an entry whose Exec binary is missing. Handing gio that
// one file meant "Open with -> Neovim" did nothing, which is precisely the
// complaint this was supposed to fix.
//
// Desktop.launchCommand walks the whole search path and stops at the first
// entry that actually launches, so a stale override falls through to the
// system's copy. The scanned path is still what names the row in the menu;
// it is just not what the launch is pinned to.
function openWithCommand(desktopId, path) {
  return Desktop.launchCommand(desktopId, path);
}

// ── picking a handler for a type that has none ──────────────────────────
//
// Choosing an application for a file nothing opens is TWO statements, and only
// one of them is about this file: open it with that, and from now on that is
// what this kind of file opens with. Doing only the first means the same walk
// through the same list of four hundred applications the very next time, which
// is the complaint rather than the fix.
//
// `gio mime <type> <id>` RATHER THAN `xdg-mime default`, and the difference is
// the whole point of doing this at all.
//
// xdg-mime writes only [Default Applications]. glib does not read that section
// when it is asked what is REGISTERED for a type, so after an xdg-mime the
// scan above — which is `gio mime <type>` — still answers "No registered
// applications" and the menu still has nothing to put in a submenu. Measured,
// not assumed: the association went in, and the very next right-click offered
// the same empty list.
//
// gio writes [Added Associations] as well as the default, which is the half
// the scan can see. The loop closes: what you choose here is what the menu
// offers next time.
//
// The registration is allowed to FAIL WITHOUT TAKING THE LAUNCH WITH IT: an
// immutable mimeapps.list is somebody's deliberate configuration, and the
// worst it should cost is having to choose again.
function adoptAppCommand(desktopId, mime, path) {
  const reg = String(mime || "") === "" ? ""
    : "gio mime " + Strings.shellQuote(mime) + " "
      + Strings.shellQuote(Desktop.fileName(desktopId)) + " >/dev/null 2>&1\n";
  return reg + Desktop.launchCommand(desktopId, path);
}

// ── and UNCHOOSING one ──────────────────────────────────────────────────
//
// There is no `gio mime` for this. gio can set a default and it can add an
// association, but it has no verb for "this application should stop claiming
// this type" — so the association file is edited directly, which is what the
// rest of the desktop does here.
//
// Three edits, per the freedesktop spec, and the third is the one that makes
// it stick: dropping the id from [Added Associations] and [Default
// Applications] only undoes what was added HERE, and the system-wide entry
// underneath would put the application straight back in the list. Naming it
// under [Removed Associations] is how a user says no to something they never
// added in the first place.
//
// Written through a temp file and moved into place, so an interrupted write
// cannot leave half a mimeapps.list behind — this is the file every
// application on the desktop consults to find out what opens what, and a
// truncated one breaks all of them rather than just this window.
function removeAppCommand(desktopId, mime) {
  const id = Desktop.fileName(desktopId);
  if (String(mime || "") === "" || String(id || "") === "") return "true";
  return "f=\"${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list\"; "
    + "mkdir -p \"$(dirname \"$f\")\" || exit 1; "
    + "[ -e \"$f\" ] || : > \"$f\"; "
    // An immutable or read-only mimeapps.list is somebody else's deliberate
    // configuration — the same judgement adoptAppCommand makes about it.
    + "[ -w \"$f\" ] || exit 1; "
    + "t=$(mktemp \"$f.XXXXXX\") || exit 1; "
    + "awk -v MIME=" + Strings.shellQuote(mime) + " -v ID=" + Strings.shellQuote(id) + " '"
    + "# Remove one desktop id as a handler for one mime type, per the freedesktop\n"
    + "# mimeapps.list spec: drop it from [Added Associations] and [Default\n"
    + "# Applications], and record it under [Removed Associations] so that a system\n"
    + "# default does not simply come back.\n"
    + "function strip(list,   n, i, p, out) {\n"
    + "  n = split(list, p, \";\"); out = \"\";\n"
    + "  for (i = 1; i <= n; i++)\n"
    + "    if (p[i] != \"\" && p[i] != ID) out = out p[i] \";\";\n"
    + "  return out;\n"
    + "}\n"
    + "/^[ \\t]*\\[/ {\n"
    + "  sec = $0; gsub(/^[ \\t]+|[ \\t]+$/, \"\", sec);\n"
    + "  if (!(sec in seen)) { seen[sec] = 1; order[++nsec] = sec }\n"
    + "  cur = sec; next;\n"
    + "}\n"
    + "{\n"
    + "  key = $0; sub(/=.*/, \"\", key); gsub(/^[ \\t]+|[ \\t]+$/, \"\", key);\n"
    + "  if (cur == \"\" ) { pre[++npre] = $0; next }\n"
    + "  if (key == MIME) {\n"
    + "    val = $0; sub(/^[^=]*=/, \"\", val);\n"
    + "    if (cur == \"[Added Associations]\" || cur == \"[Default Applications]\") {\n"
    + "      val = strip(val);\n"
    + "      if (val == \"\") next;                       # key is now empty: drop it\n"
    + "      body[cur] = body[cur] MIME \"=\" val \"\\n\"; next;\n"
    + "    }\n"
    + "    if (cur == \"[Removed Associations]\") {\n"
    + "      val = strip(val) ID \";\";                   # no duplicate, then append\n"
    + "      body[cur] = body[cur] MIME \"=\" val \"\\n\"; done = 1; next;\n"
    + "    }\n"
    + "  }\n"
    + "  body[cur] = body[cur] $0 \"\\n\";\n"
    + "}\n"
    + "END {\n"
    + "  if (!done) {\n"
    + "    if (!(\"[Removed Associations]\" in seen)) order[++nsec] = \"[Removed Associations]\";\n"
    + "    body[\"[Removed Associations]\"] = body[\"[Removed Associations]\"] MIME \"=\" ID \";\\n\";\n"
    + "  }\n"
    + "  for (i = 1; i <= npre; i++) print pre[i];\n"
    + "  for (i = 1; i <= nsec; i++) {\n"
    + "    b = body[order[i]];\n"
    + "    sub(/\\n+$/, \"\", b);                         # no run of blank lines where a section ends\n"
    + "    if (i > 1 || npre > 0) print \"\";\n"
    + "    print order[i];\n"
    + "    if (b != \"\") print b;\n"
    + "  }\n"
    + "}\n"
    + "' \"$f\" > \"$t\" && mv \"$t\" \"$f\" || { rm -f \"$t\"; exit 1; }";
}

// ── the list you choose from ────────────────────────────────────────────
//
// Everything installed is several hundred entries, which is a list you filter
// rather than one you read. Ranked rather than merely filtered: a name that
// STARTS with what was typed is what "gi" means when both GIMP and Digikam
// match, and an alphabetical list would bury it.
//
// Matched against the id as well as the name, because an entry calling itself
// "Document Viewer" is one most people would look for by typing "evince".
function filterApps(apps, query) {
  const list = apps || [];
  const q = String(query || "").trim().toLowerCase();
  if (q === "") return list.slice();
  const out = [];
  for (let i = 0; i < list.length; ++i) {
    const a = list[i];
    const name = String(a.name || "").toLowerCase();
    const id = String(a.id || "").toLowerCase();
    // 0 best: the name starts with it, then a word inside the name does, then
    // anywhere in the name, then the id alone
    let rank = -1;
    if (name.indexOf(q) === 0) rank = 0;
    else if ((" " + name).indexOf(" " + q) >= 0) rank = 1;
    else if (name.indexOf(q) > 0) rank = 2;
    else if (id.indexOf(q) >= 0) rank = 3;
    if (rank < 0) continue;
    out.push({ rank: rank, at: i, app: a });
  }
  // `at` breaks every tie, so the incoming order — which the caller has
  // already sorted by name — is what decides between two equal matches, and
  // the list does not reshuffle itself as you type a letter that changes
  // nothing.
  out.sort(function (x, y) {
    return x.rank !== y.rank ? x.rank - y.rank : x.at - y.at;
  });
  return out.map(function (e) { return e.app; });
}

// ── what a video IS ───────────────────────────────────────────────────────
// ffprobe, which ffmpeg already brings — the same package that pulls the
// thumbnail frame out of the file, so this adds no dependency either.
//
// `default=noprint_wrappers=1` prints one `key=value` line per field and the
// parse reads them BY NAME. `-of csv` was the shorter spelling and the wrong
// one: it prints bare values, and a file that reports no bit_rate shifts every
// column after it by one without saying so.
function videoInfoCommand(path) {
  return "ffprobe -v error -select_streams v:0 -show_entries "
    + "stream=width,height,codec_name,r_frame_rate:"
    + "format=duration,bit_rate,format_name"
    + " -of default=noprint_wrappers=1 -- " + Strings.shellQuote(path)
    + " 2>/dev/null";
}

function parseVideoInfo(text) {
  const kv = {};
  for (const line of String(text || "").split("\n")) {
    const cut = line.indexOf("=");
    if (cut > 0) kv[line.slice(0, cut)] = line.slice(cut + 1);
  }
  const w = parseInt(kv.width, 10);
  const h = parseInt(kv.height, 10);
  // no video stream is not an error worth a message, it is a file with nothing
  // to say about itself — the panel simply leaves those rows out
  if (!(w > 0) || !(h > 0)) return null;
  return {
    dims: w + " \u00d7 " + h,
    codec: kv.codec_name || "",
    fps: frameRate(kv.r_frame_rate),
    duration: formatDuration(kv.duration),
    bitrate: formatRate(kv.bit_rate),
    // "mov,mp4,m4a,3gp,3g2,mj2" is one container answering to six names, and
    // the first is the one anybody means by it
    container: String(kv.format_name || "").split(",")[0]
  };
}

// ffprobe reports a rate as an exact fraction — 24000/1001 — because 23.976 is
// not one. The fraction is the honest answer and the useless one.
function frameRate(text) {
  const parts = String(text || "").split("/");
  const n = Number(parts[0]);
  const d = parts.length > 1 ? Number(parts[1]) : 1;
  if (!(n > 0) || !(d > 0)) return "";
  const v = n / d;
  return (Math.abs(v - Math.round(v)) < 0.01
    ? String(Math.round(v)) : v.toFixed(3)) + " fps";
}

function formatDuration(secs) {
  const t = Math.round(Number(secs) || 0);
  if (t <= 0) return "";
  const pad = (n) => String(n).padStart(2, "0");
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  return (h > 0 ? h + ":" + pad(m) : String(m)) + ":" + pad(t % 60);
}

// Decimal units, and deliberately not formatSize's binary ones: a bitrate has
// always been quoted in millions of bits per second, never in mebibits, and
// making this one consistent with the file sizes would make it wrong.
function formatRate(bps) {
  const v = Number(bps) || 0;
  if (v <= 0) return "";
  if (v >= 1000000) return (v / 1000000).toFixed(1) + " Mb/s";
  if (v >= 1000) return Math.round(v / 1000) + " kb/s";
  return v + " b/s";
}

// The same probe as a video's, asking the audio stream instead — plus the
// TAGS, which are the whole point: a file called "01.mp3" has a title, an
// artist and an album inside it and the listing can only show the number.
function audioInfoCommand(path) {
  return "ffprobe -v error -select_streams a:0 -show_entries "
    + "stream=codec_name,sample_rate,channels,bit_rate:"
    + "format=duration,bit_rate,format_name:"
    + "format_tags=title,artist,album,date,track"
    + " -of default=noprint_wrappers=1 -- " + Strings.shellQuote(path)
    + " 2>/dev/null";
}

function parseAudioInfo(text) {
  const kv = {};
  for (const line of String(text || "").split("\n")) {
    const cut = line.indexOf("=");
    if (cut > 0) {
      const k = line.slice(0, cut);
      // Stream and format BOTH answer bit_rate, and ffprobe prints the stream
      // first. The stream's is the honest one for the audio; the container's
      // includes everything else in the file. First wins.
      if (kv[k] === undefined) kv[k] = line.slice(cut + 1);
    }
  }
  if (!kv.codec_name && !kv.duration) return null;
  const rate = Number(kv.sample_rate) || 0;
  const ch = Number(kv.channels) || 0;
  return {
    title: kv["TAG:title"] || kv.title || "",
    artist: kv["TAG:artist"] || kv.artist || "",
    album: kv["TAG:album"] || kv.album || "",
    date: kv["TAG:date"] || kv.date || "",
    track: kv["TAG:track"] || kv.track || "",
    duration: formatDuration(kv.duration),
    codec: kv.codec_name || "",
    container: String(kv.format_name || "").split(",")[0],
    bitrate: formatRate(kv.bit_rate),
    // kHz, because 44100 is a number everybody reads as 44.1
    rate: rate > 0 ? (rate / 1000).toFixed(1).replace(/\.0$/, "") + " kHz" : "",
    channels: ch === 1 ? "mono" : (ch === 2 ? "stereo" : (ch > 0 ? ch + " ch" : ""))
  };
}

// ── looking inside an archive ───────────────────────────────────────────
// A .zip or .tar.zst previewed as "binary", which is true and useless: the one
// thing worth knowing about an archive before you extract it is what is in it.
// bsdtar reads every format terminus can extract, so the preview and the extract
// agree by construction.
//
// Capped, because a package archive can hold tens of thousands of paths and
// the preview pane shows perhaps forty. The cap is a number the TREE also has
// to know — a listing cut off at the limit is a partial tree and has to say so
// rather than simply ending — so it is named once here rather than written
// into the command and guessed at afterwards.
const ARCHIVE_LINES = 400;

function archiveListCommand(path) {
  return "bsdtar -tf " + Strings.shellQuote(path) + " 2>/dev/null | head -n "
    + ARCHIVE_LINES;
}

// ── the listing, folded back into a tree ────────────────────────────────
//
// `bsdtar -tf` prints one full path per line, and a column of forty lines that
// all begin with the same three directories tells you nothing about the SHAPE
// of the archive — which is the question you open one to ask. Yazi draws a
// directory as a tree; an archive is a directory that happens to be in a file,
// so this draws it the same way, with the guides `tree` uses.
//
// Directories are INFERRED from the paths rather than trusted from the
// listing. `zip -D` writes no directory entries at all, 7z's are ordered
// however it pleases, and a path with anything after it is a directory whether
// or not the archive bothered to say so.
//
// Keys carry a "k:" prefix so that an archive holding a file called
// "constructor" or "__proto__" is a file called "constructor" and not a lookup
// that comes back with something off Object's prototype.
function archiveTree(text) {
  const lines = String(text || "").split("\n").filter((l) => l !== "");
  if (lines.length === 0) return [];

  const top = { name: "", isDir: true, kids: {}, order: [] };
  for (let i = 0; i < lines.length; ++i) {
    const line = lines[i];
    // "a/b/" is a directory entry: the trailing slash leaves an empty
    // component, which is not a name. "./a" is the same path as "a".
    const parts = line.split("/").filter((c) => c !== "" && c !== ".");
    let node = top;
    for (let j = 0; j < parts.length; ++j) {
      const nm = parts[j];
      const dir = j < parts.length - 1 || line.charAt(line.length - 1) === "/";
      const key = "k:" + nm;
      let kid = node.kids[key];
      if (kid === undefined) {
        kid = { name: nm, isDir: dir, kids: {}, order: [] };
        node.kids[key] = kid;
        node.order.push(key);
      } else if (dir) {
        // seen as a leaf first, and now known to have something under it
        kid.isDir = true;
      }
      node = kid;
    }
  }

  // Directories first and then by name, which is what the listing behind the
  // preview does — an archive drawn in whatever order it was written in reads
  // as a different kind of thing from the folder beside it.
  function ordered(node) {
    const kids = [];
    for (let i = 0; i < node.order.length; ++i) kids.push(node.kids[node.order[i]]);
    kids.sort(function (a, b) {
      if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
      const x = a.name.toLowerCase(), y = b.name.toLowerCase();
      return x < y ? -1 : (x > y ? 1 : 0);
    });
    return kids;
  }

  const out = [];
  function walk(node, prefix) {
    const kids = ordered(node);
    for (let i = 0; i < kids.length; ++i) {
      const last = i === kids.length - 1;
      out.push({ name: kids[i].name, isDir: kids[i].isDir,
                 prefix: prefix + (last ? "\u2514\u2500\u2500 "
                                        : "\u251c\u2500\u2500 ") });
      // the guide continues past a child that has siblings below it and stops
      // at one that does not, which is the whole of what the vertical bars say
      walk(kids[i], prefix + (last ? "    " : "\u2502   "));
    }
  }
  walk(top, "");

  // Cut short rather than finished: without this the tree simply ends, and a
  // truncated listing that looks complete is worse than no listing.
  if (lines.length >= ARCHIVE_LINES)
    out.push({ name: "\u2026 and more", isDir: false, prefix: "", more: true });
  return out;
}

// ── emptying the trash ──────────────────────────────────────────────────
// Both halves, together. `files` holds what was deleted and `info` the records
// saying where each came from; removing one without the other leaves a trash
// that every other implementation then reports inconsistently.
function emptyTrashCommand() {
  const r = Strings.shellQuote(trashRoot());
  return "rm -rf -- " + r + "/files/* " + r + "/files/.[!.]* "
    + r + "/info/* " + r + "/info/.[!.]* 2>/dev/null; true";
}

// How much the trash is holding — the files, not the records, which are a few
// bytes each and are not what the question is about.
function trashSizeCommand() {
  return "du -sh " + Strings.shellQuote(trashFilesDir()) + " 2>/dev/null | cut -f1";
}

// ── what a file actually is ─────────────────────────────────────────────
// Computed ON REQUEST, never as part of opening the properties dialog: sha256
// over a few gigabytes takes real time, and a dialog that stalls every time you
// open it on a video is worse than not having the field at all.
function checksumCommand(path) {
  return "sha256sum -- " + Strings.shellQuote(path) + " 2>/dev/null | cut -d' ' -f1";
}

// Dimensions and the few image facts worth a glance. magick already makes the
// thumbnails, so this adds no dependency. [0] is the first frame — asking a
// multi-page PDF or an animation about its size otherwise prints one line per
// page.
function imageInfoCommand(path) {
  // Width and height come across as SEPARATE fields and are joined here, so
  // the one place that decides how a size reads is this file rather than a
  // format string — the video panel next to it spells it the same way.
  const fmt = "%w" + FIELD + "%h" + FIELD + "%m" + FIELD
    + "%[bit-depth]-bit" + FIELD + "%[colorspace]";
  return "magick identify -format " + Strings.shellQuote(fmt) + " "
    + Strings.shellQuote(path + "[0]") + " 2>/dev/null";
}

function parseImageInfo(text) {
  const f = String(text || "").trim().split(FIELD);
  if (f.length < 5 || f[0] === "") return null;
  return {
    dims: f[0] + " \u00d7 " + f[1],
    format: f[2],
    depth: f[3],
    colorspace: f[4]
  };
}

// ── what a text file IS, as opposed to what it says ─────────────────────
//
// Every other kind in the preview pane carries a line of facts above the
// thing itself — a picture its dimensions, a film its codec — and text alone
// showed the document and nothing about it. These are the questions worth
// asking of one: how long is it, how wide does it run, and what encoding is
// it in, which is the one that matters when it renders as mojibake.
//
// wc and file, both cheap, in one process. `wc -L` is the longest line, which
// is what says whether a file will wrap in a narrow pane.
function textInfoCommand(path) {
  const q = Strings.shellQuote(path);
  return "wc -l -w -c -L < " + q + " 2>/dev/null | tr -s ' ' '\\037'; "
    + "printf '\\036'; "
    + "file -b --mime-encoding -- " + q + " 2>/dev/null";
}

function parseTextInfo(text) {
  const parts = String(text || "").split(RECORD);
  const nums = String(parts[0] || "").trim().split(FIELD)
    .map((x) => x.trim()).filter((x) => x !== "");
  if (nums.length < 4) return null;
  const n = (x) => Number(x) || 0;
  return {
    lines: n(nums[0]).toLocaleString(),
    words: n(nums[1]).toLocaleString(),
    chars: n(nums[2]).toLocaleString(),
    longest: n(nums[3]).toLocaleString(),
    encoding: String(parts[1] || "").trim()
  };
}

// ── typing a path ───────────────────────────────────────────────────────
// What `g` then space opens: somewhere to type a destination rather than
// clicking down to it. Everything here is about turning half-typed text into
// something the rest of terminus can navigate to.

// `~` and `~/...` mean home, and nothing else does — `~foo` is another user's
// home on some systems and terminus has no business guessing at that. A relative
// path is taken against the directory you are standing in, which is what a
// shell would do and therefore what the fingers expect.
function expandPath(text, home, cwd) {
  let t = String(text || "").trim();
  if (t === "") return "";
  if (t === "~") return home;
  if (t.indexOf("~/") === 0) t = home + t.slice(1);
  if (t.charAt(0) !== "/") t = joinPath(cwd, t);
  // collapse any // and trailing / so two spellings of one path compare equal
  t = t.replace(/\/+/g, "/");
  if (t.length > 1) t = t.replace(/\/+$/, "");
  return t;
}

// How far the candidates agree, IN THE FILESYSTEM'S OWN CASE.
//
// Matching ignores case, so completing has to hand back the real spelling
// rather than the one you typed: type "doc" at a directory holding Documents
// and appending the tail would leave "documents", which is not a path. The
// caller replaces the whole fragment with this instead of appending to it.
//
// Empty when the best candidate does not start with what you typed — a fuzzy
// hit like "dwn" for Downloads has no prefix to agree on, and spelling one out
// would suggest something that does not exist. Tab takes the whole candidate
// in that case; see the path bar.
// How far every candidate agrees, so Tab can fill in the part that is not yet
// a choice — the shell behaviour: two directories sharing six letters means
// Tab types those six and stops rather than picking one for you.
function commonPrefix(names) {
  if (!names || names.length === 0) return "";
  if (names.length === 1) return names[0];
  let pre = names[0];
  for (let i = 1; i < names.length; ++i) {
    const n = names[i];
    let k = 0;
    while (k < pre.length && k < n.length
           && pre.charAt(k).toLowerCase() === n.charAt(k).toLowerCase()) k++;
    pre = pre.slice(0, k);
    if (pre === "") break;
  }
  return pre;
}

// ── how full a disk is ──────────────────────────────────────────────────
// lsblk prints sizes as it likes to read them — "907.1M", "32.3G", "1.8T" —
// so turning two of those back into a fraction means parsing them. Binary
// units, because that is what lsblk means by them and what the filesystem
// allocates in.
const SIZE_UNITS = {
  B: 1, K: 1024, M: 1048576, G: 1073741824,
  T: 1099511627776, P: 1125899906842624
};

function parseSizeStr(text) {
  const m = String(text || "").trim().match(/^([0-9]*\.?[0-9]+)\s*([BKMGTP])?/i);
  if (!m) return -1;
  const n = parseFloat(m[1]);
  if (isNaN(n)) return -1;
  const u = (m[2] || "B").toUpperCase();
  return n * (SIZE_UNITS[u] || 1);
}

// The proportion of a disk that is in use, or -1 when it cannot be known —
// an unmounted partition reports neither figure, and a bar drawn from a guess
// would be worse than no bar.
function usedFraction(avail, total) {
  const a = parseSizeStr(avail), t = parseSizeStr(total);
  if (a < 0 || t <= 0) return -1;
  const used = 1 - (a / t);
  return Math.max(0, Math.min(1, used));
}

// ── what git thinks of this directory ───────────────────────────────────
//
// One command answers both questions a file manager has: WHERE the repository
// is, and what is dirty inside it. They arrive in one process rather than two
// because the second is worthless without the first — porcelain paths are
// relative to the repository root, always, no matter which subdirectory git
// was invoked from, so the root is what turns them back into real paths.
//
// The two halves are separated by a NUL. That is not decoration: with -z the
// records themselves are NUL-terminated because a filename may legally contain
// a NEWLINE, and git stops quoting them under -z. So newline cannot separate
// anything here, and NUL can — the header is two lines of git's own output,
// which cannot contain one.
//
// --no-optional-locks matters more than it looks. Plain `git status` writes
// the index back when it refreshes stat information, so a file manager polling
// it would take the index lock every few seconds and lose races with whatever
// the user is running in a terminal. This flag makes it read-only.
//
// The pathspec is `.`, so only the subtree being looked at is scanned. Walking
// a whole kernel-sized repository to draw thirty rows is the difference
// between a listing that appears and one that arrives.
function gitCommand(dir) {
  const d = Strings.shellQuote(dir);
  return "git -C " + d + " --no-optional-locks rev-parse"
    + " --show-toplevel --abbrev-ref HEAD 2>/dev/null; printf '\\0'; "
    // --ignored, and it is cheaper than it sounds. gitState already reads "!!"
    // and GIT_MARK already has a dot for it; without the flag git never emits
    // one, so that branch and that mark were unreachable — the code was
    // written for a question nobody was asking.
    //
    // The default mode COLLAPSES an ignored directory to a single "dir/"
    // record instead of listing what is under it: measured, a node_modules of
    // 201 files came back as one line. So a repository with a large build tree
    // costs one record, not a walk of it, and gitRollup already lands "dir/"
    // on the right row because untracked directories arrive the same way.
    //
    // Worth having in a FILE MANAGER specifically: "git ignores this" is a
    // fact about a file you can see in the listing, and GIT_RANK puts ignored
    // below everything, so the dot never masks a state that matters.
    + "git -C " + d + " --no-optional-locks status --porcelain=v1 -z"
    + " --no-renames --ignored -- . 2>/dev/null";
}

// The porcelain's two columns are the index and the working tree, in that
// order, and between them they say everything. Read worst-first: a conflict is
// not also "modified", it is a conflict.
function gitState(code) {
  const x = code.charAt(0), y = code.charAt(1);
  if (code === "??") return "untracked";
  if (code === "!!") return "ignored";
  // Both sides touched the same path. git spells this six ways and they all
  // mean the same thing to someone looking at a list of files.
  if (x === "U" || y === "U" || code === "AA" || code === "DD") return "conflict";
  if (y === "D" || x === "D") return "deleted";
  // The working tree column first: an edit you have not staged is the one
  // thing you could still lose.
  if (y !== " " && y !== "") return "modified";
  if (x !== " " && x !== "") return "staged";
  return "";
}

// Worst-first, and the order is the point: a directory shows one mark for
// everything underneath it, so the mark has to be the one that matters most.
const GIT_RANK = { conflict: 5, deleted: 4, modified: 3, staged: 2, untracked: 1, ignored: 0 };

function gitWorse(a, b) {
  if (!a) return b || "";
  if (!b) return a;
  return (GIT_RANK[a] || 0) >= (GIT_RANK[b] || 0) ? a : b;
}

function parseGit(text) {
  const s = String(text || "");
  const cut = s.indexOf("\0");
  // No NUL at all means the command did not run — not a repository, or no git.
  if (cut === -1) return { root: "", branch: "", entries: [] };

  const head = s.slice(0, cut).split("\n");
  const root = (head[0] || "").trim();
  // In a repository with no commits yet, rev-parse can answer the first
  // question and fail the second. A root with no branch is still a repository.
  let branch = (head[1] || "").trim();
  if (branch === "HEAD") branch = "detached";
  if (root === "") return { root: "", branch: "", entries: [] };

  const entries = [];
  for (const recRaw of s.slice(cut + 1).split("\0")) {
    // "XY path": two status columns, one space, then the path — which may
    // itself begin with a space, so slice at a fixed offset rather than split.
    if (recRaw.length < 4) continue;
    const state = gitState(recRaw.slice(0, 2));
    if (state === "") continue;
    const rel = recRaw.slice(3);
    if (rel === "") continue;
    entries.push({ path: joinPath(root, rel), state: state });
  }
  return { root: root, branch: branch, entries: entries };
}

// Folds the repository's whole answer down to the rows actually on screen.
//
// Every reported path is either one of this directory's entries or something
// beneath one of them, so taking the first path segment below `cwd` names the
// row it belongs to either way — and a directory ends up holding the worst
// state of everything it contains without anyone walking a tree to work it
// out. An untracked directory arrives from git already collapsed to "dir/",
// which lands on the same row by the same rule.
function gitRollup(entries, cwd) {
  const out = {};
  const base = cwd === "/" ? "/" : String(cwd) + "/";
  for (const e of entries) {
    if (e.path.indexOf(base) !== 0) continue;
    const rest = e.path.slice(base.length);
    if (rest === "") continue;
    const cut = rest.indexOf("/");
    const name = cut === -1 ? rest : rest.slice(0, cut);
    if (name === "") continue;
    const key = base + name;
    out[key] = gitWorse(out[key], e.state);
  }
  return out;
}

// One character, because it sits in a gutter beside the name and anything
// wider would be a column. They are git's own letters where git has one, which
// makes them free to learn for anyone who has read a `git status`.
//
// Ignored has no letter of its own — "!!" is a pair, and "!" reads as an alarm,
// which is the opposite of what being ignored means. A HOLLOW CIRCLE instead:
// it stands at the same height as the letters beside it, so it is actually
// legible in a 13px gutter, but being an outline it stays the lightest thing
// in the column, which is what the mark is for. It was a middle dot, which is
// a mid-height mark a couple of pixels across and could not be seen at all.
const GIT_MARK = {
  conflict: "U", deleted: "D", modified: "M",
  staged: "+", untracked: "?", ignored: "○"
};

// Reached through a function rather than as Terminus.GIT_MARK, for the reason
// the paste-conflict modes are: a QML .js import does not reliably expose a
// top-level const on its namespace, and a table that reads as empty from the
// window is a gutter that silently draws nothing.
function gitMark(state) {
  return GIT_MARK[String(state || "")] || "";
}

// ── archiving and extracting, with something to watch ──────────────────
//
// Neither tool reports a percentage, so the percentage is COUNTED: how many
// entries have gone by against how many there are. That total is known before
// the work starts — `find` for an archive, the archive's own table of contents
// for an extract — so the bar is honest from the first entry rather than
// guessing from bytes, which compression makes a lie anyway.
//
// The entry lines arrive in different places depending on the tool: bsdtar
// writes its -v listing to STDERR for both -c and -x, 7z writes "+ path" to
// stdout under -bb1. Either way they are filtered out of the stream and turned
// into one progress record each, and a line that is NOT an entry is a real
// error, forwarded to stderr where the job's collector already reads it.
//
// The tool's exit status has to survive a pipeline, so it is parked in a file
// and re-raised at the end. Without that the status seen is the counting
// loop's, which succeeds cheerfully even when the archive failed to write.
const JOB_TOTAL = "T";
const JOB_AT = "P";

function archiveScript(prefix, countCmd, tool, entryPat, fromStdout) {
  // For bsdtar the pipe carries STDERR, so a line that is not an entry is a
  // real error and is forwarded on. For 7z the pipe carries STDOUT, where the
  // only other traffic is a copyright banner — its real errors go to stderr,
  // which is left alone to reach the job's collector untouched. Forwarding
  // there too would have reported "7-Zip 26.02 Copyright (c) Igor Pavlov" as
  // the reason your archive failed.
  const plumb = fromStdout ? "" : "2>&1 >/dev/null ";
  const other = fromStdout
    ? "*) ;;"
    : "*) [ -n \"$l\" ] && printf '%s\\n' \"$l\" >&2 ;;";
  return prefix
    + "rc=$(mktemp) || exit 1\n"
    + "total=$(" + countCmd + ")\n"
    + "[ -n \"$total\" ] || total=0\n"
    + "printf '" + JOB_TOTAL + "%s\\r' \"$total\"\n"
    + "{ " + tool + "; echo $? > \"$rc\"; } " + plumb + "| {\n"
    + "  i=0\n"
    + "  while IFS= read -r l; do\n"
    + "    case \"$l\" in\n"
    + "      " + entryPat + ") i=$((i+1)); printf '" + JOB_AT + "%s\\r' \"$i\" ;;\n"
    + "      " + other + "\n"
    + "    esac\n"
    + "  done\n"
    + "}\n"
    + "s=$(cat \"$rc\" 2>/dev/null); rm -f \"$rc\"\n"
    + "exit \"${s:-1}\"\n";
}

function archiveJobCommand(paths, archivePath) {
  const names = paths.map((p) => Strings.shellQuote(basename(p))).join(" ");
  const ar = Strings.shellQuote(archivePath);
  const sevenZ = /\.7z$/i.test(archivePath);
  const prefix = "cd " + Strings.shellQuote(dirname(paths[0])) + " || exit 1\n";
  if (sevenZ) {
    // 7z counts files only: it has no entry of its own for a directory
    return archiveScript(prefix, "find " + names + " -type f 2>/dev/null | wc -l",
      "7z a -bb1 -bd -- " + ar + " " + names, "'+ '*", true);
  }
  return archiveScript(prefix, "find " + names + " 2>/dev/null | wc -l",
    "bsdtar -a -cvf " + ar + " -- " + names, "'a '*", false);
}

// One archive at a time, so the count means something, and into a directory of
// its own ALWAYS: an archive holding twenty loose files at its top level would
// otherwise spray them across the folder you were standing in, and picking
// those back out by hand is a worse problem than extracting was meant to solve.
function extractJobCommand(path, destDir) {
  const p = Strings.shellQuote(path);
  const stem = stripArchiveExt(basename(path));
  const prefix = FREE_DIR
    + "d=" + Strings.shellQuote(destDir) + "\n"
    + "t=$(terminus_free_dir \"$d\" " + Strings.shellQuote(stem) + ")\n"
    + "mkdir -p \"$d/$t\" || exit 1\n";
  return archiveScript(prefix, "bsdtar -tf " + p + " 2>/dev/null | wc -l",
    "bsdtar -xvf " + p + " -C \"$d/$t\"", "'x '*", false);
}

// ── what a finished job is called ───────────────────────────────────────
//
// The one line a notification gets. Past tense, because by the time this is
// read the thing has already happened, and the SUBJECT is the file when there
// is one file and a count when there are several — "Copied notes.txt" tells
// you which, "Copied 40 items" tells you how many, and neither is improved by
// being told both.
//
// Here rather than in the window for the usual reason: it is a decision about
// wording with no pixels in it, so it can be checked.
function jobSummary(op, names) {
  const verb = op === "copy" ? "Copied"
             : op === "move" ? "Moved"
             : op === "archive" ? "Archived"
             : op === "extract" ? "Extracted"
             : "Finished";
  const list = names || [];
  if (list.length === 0) return verb;
  if (list.length === 1) return verb + " " + list[0];
  return verb + " " + list.length + " items";
}

// A progress record, or null for a line that is not one. The counting loop
// emits nothing else on stdout, so anything unrecognised is simply ignored.
function parseArchiveProgress(line) {
  const s = String(line || "");
  if (s.indexOf(JOB_TOTAL) === 0) {
    const n = parseInt(s.slice(JOB_TOTAL.length), 10);
    return isNaN(n) ? null : { total: Math.max(0, n) };
  }
  if (s.indexOf(JOB_AT) === 0) {
    const n = parseInt(s.slice(JOB_AT.length), 10);
    return isNaN(n) ? null : { at: Math.max(0, n) };
  }
  return null;
}
