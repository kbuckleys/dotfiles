// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── tags ────────────────────────────────────────────────────────────────
// A file's tags live in an EXTENDED ATTRIBUTE on the file itself,
// `user.xdg.tags`, comma-separated. Not in a database keyed by path.
//
// The difference shows up the moment anything moves. A path is not an
// identity — rename a file in any other program and a path-keyed database is
// now describing a file that does not exist, silently, with no way to tell
// that entry from one whose file was deleted. An attribute travels with the
// inode: mv, rename-in-place, and rsync -X all carry it, because it is part
// of the file rather than a remark about it.
//
// `user.xdg.tags` specifically, rather than a name of our own: it is what
// the other Linux file managers that do tags already read and write, so a
// file tagged here is tagged for them too. This machine has none of them
// installed today, which is an argument for picking the shared name now
// while nothing has to be migrated, not an argument against it.
//
// THE COST OF NOT HAVING AN INDEX, measured rather than assumed: a recursive
// sweep of 432,933 files under $HOME takes 1.57s. That is fine once in the
// background and far too slow behind a sidebar click, which is why the
// caller keeps a JSON index and treats these commands as the truth it is
// derived from.
// No .pragma library, and that is deliberate: terminus.js does not have one
// either. A library-pragma file gets its OWN scope, isolated from the QML
// document that imported it — and `Strings` is a QML singleton, not a JS
// file, so inside a library it would simply be undefined. Sharing the
// document's scope is what puts shellQuote in reach.

// THE SEVEN, and the Zenon colour each one means. A tag may be any string
// at all; these are the names that come with a colour already, so "red"
// is red the first time it is typed and nothing has to be seeded into the
// state file for that to be true.
//
// Named for the COLOUR rather than mapped one-to-one onto Zenon's own
// names, because the two vocabularies disagree: Zenon's `yellow` is
// #fab387, which is orange, and the yellow a person means is `sand`.
var PRESETS = [
  { name: "red",    ink: "red" },
  { name: "orange", ink: "yellow" },
  { name: "yellow", ink: "sand" },
  { name: "green",  ink: "green" },
  { name: "blue",   ink: "blue" },
  { name: "purple", ink: "magenta" },
  { name: "grey",   ink: "muted" }
];

// The Zenon colour name for a tag, or "" if it is not one of the seven.
function presetInk(name) {
  for (var i = 0; i < PRESETS.length; ++i)
    if (PRESETS[i].name === name) return PRESETS[i].ink;
  return "";
}

var ATTR = "user.xdg.tags";

// As a collection has one, and for the same reasons — see DEFAULT_VIEW in
// collections.js. A tag page is its own place and does not borrow the
// arrangement of whatever directory you happened to be standing in.
var DEFAULT_VIEW = "list";

// ── reading ─────────────────────────────────────────────────────────────

// getfattr prints nothing at all for a file that has no such attribute, and
// exits nonzero when NONE of the files it was given has one. That is a
// perfectly good answer — no tags anywhere — so the exit code is swallowed
// and the empty output is what gets parsed.
//
// --absolute-names because getfattr strips the leading slash otherwise, and
// a path-keyed map with no leading slash matches nothing we look up.
//
// The whole tree in one pass, which is how the index is built. -h so a
// symlink is asked about ITSELF rather than about what it points at: tagging
// a link and tagging its target are two different acts, and following here
// would report the target's tags against the link's path.
function scanTagsCommand(root) {
  return "getfattr -Rh --absolute-names -n " + ATTR
    + " -- " + Strings.shellQuote(root) + " 2>/dev/null || true";
}

// getfattr's dump format is stanzas separated by blank lines:
//
//   # file: /home/buck/notes.md
//   user.xdg.tags="red,work"
//
// The value is C-quoted by getfattr — it escapes \ and " and emits \NNN
// OCTAL (not hex) for anything non-printing, which is why the unescape below
// is octal. Tag names are ordinary words in practice, but a tag typed with a
// quote in it should come back as the tag that was typed.
function parseTagDump(text) {
  var out = {};
  var lines = String(text || "").split("\n");
  var path = "";
  for (var i = 0; i < lines.length; ++i) {
    var line = lines[i];
    if (line.indexOf("# file: ") === 0) { path = line.slice(8); continue; }
    if (path === "" || line.indexOf(ATTR + "=") !== 0) continue;

    var raw = line.slice(ATTR.length + 1);
    // Quoted unless the value is empty, in which case getfattr prints the
    // bare name with nothing after the =.
    if (raw.length >= 2 && raw.charAt(0) === '"'
        && raw.charAt(raw.length - 1) === '"')
      raw = raw.slice(1, -1);

    var names = splitTags(unescapeAttr(raw));
    if (names.length > 0) out[path] = names;
    path = "";
  }
  return out;
}

function unescapeAttr(s) {
  var out = "";
  for (var i = 0; i < s.length; ++i) {
    if (s.charAt(i) !== "\\") { out += s.charAt(i); continue; }
    var next = s.charAt(i + 1);
    if (next === "\\" || next === '"') { out += next; i += 1; continue; }
    // \NNN, octal, exactly three digits as getfattr writes them
    var oct = s.substr(i + 1, 3);
    if (/^[0-7]{3}$/.test(oct)) {
      out += String.fromCharCode(parseInt(oct, 8));
      i += 3;
      continue;
    }
    out += "\\";
  }
  return out;
}

// ── writing ─────────────────────────────────────────────────────────────

// An empty list REMOVES the attribute rather than storing "". A file with
// `user.xdg.tags=""` is a file that reads as tagged to anything doing a
// presence check, including the -n sweep above, and it would sit in the
// index forever as a path with no tags.
//
// -x exits nonzero when the attribute was not there to begin with, which is
// the ordinary case for "untag something that has one tag left", so that one
// is swallowed too.
function writeTagsCommand(path, names) {
  var p = Strings.shellQuote(path);
  var clean = normalise(names);
  if (clean.length === 0)
    return "setfattr -x " + ATTR + " -- " + p + " 2>/dev/null || true";
  return "setfattr -n " + ATTR
    + " -v " + Strings.shellQuote(clean.join(",")) + " -- " + p;
}

// Several files in one shell, because tagging is nearly always done to a
// selection. One setfattr per file — there is no batch form — but one
// process rather than one per file.
function writeManyCommand(pairs) {
  if (!pairs || pairs.length === 0) return "true";
  return pairs.map(function (e) {
    return writeTagsCommand(e.path, e.names);
  }).join("\n");
}

// ── names ───────────────────────────────────────────────────────────────

// A comma separates tags, so a tag cannot contain one. Whitespace is trimmed
// because "red, work" is what a person types, and the empties that a stray
// comma leaves are dropped rather than becoming a tag with no name.
function splitTags(s) {
  return String(s || "").split(",")
    .map(function (t) { return t.trim(); })
    .filter(function (t) { return t !== ""; });
}

// Deduplicated and sorted, so two files carrying the same set carry the same
// STRING — which is what lets a plain comparison answer "are these tagged
// alike" and keeps the attribute from churning when nothing really changed.
function normalise(names) {
  var seen = {};
  var out = [];
  var list = names || [];
  for (var i = 0; i < list.length; ++i) {
    var t = String(list[i]).replace(/,/g, " ").trim();
    if (t === "" || seen[t]) continue;
    seen[t] = true;
    out.push(t);
  }
  return out.sort();
}

function hasTag(names, tag) {
  return !!names && names.indexOf(tag) >= 0;
}

// Toggling across a SELECTION, not a file. With a mixed selection — some
// tagged, some not — the useful answer is to bring the odd ones into line
// rather than to flip each individually, which would leave the set exactly
// as mixed as it started and look like nothing happened. So: add to all
// unless every one of them already has it, and only then remove.
function toggleAcross(current, paths, tag) {
  var all = paths.length > 0;
  for (var i = 0; i < paths.length; ++i) {
    if (!hasTag(current[paths[i]], tag)) { all = false; break; }
  }
  var pairs = [];
  for (var j = 0; j < paths.length; ++j) {
    var p = paths[j];
    var names = (current[p] || []).slice();
    if (all) names = names.filter(function (t) { return t !== tag; });
    else if (names.indexOf(tag) < 0) names.push(tag);
    pairs.push({ path: p, names: normalise(names) });
  }
  return { pairs: pairs, added: !all };
}

// ── renaming ────────────────────────────────────────────────────────────
// A tag lives on every file that carries it, so renaming one is a write to
// each of them — there is no central record to edit. Returns the pairs to
// write; the caller applies them the same way a toggle is applied.
//
// MERGING IS ALLOWED, and is the useful case as often as not: renaming
// "recieve" to "receive" when "receive" already exists should end with one
// tag on the union of both sets, not with a refusal. normalise dedupes, so
// a file carrying both ends up carrying it once.
function renamePairs(index, from, to) {
  var want = normalise([to])[0] || "";
  if (from === "" || want === "" || from === want) return [];
  var pairs = [];
  for (var path in index) {
    var names = index[path] || [];
    if (names.indexOf(from) < 0) continue;
    var next = names.filter(function (t) { return t !== from; });
    next.push(want);
    pairs.push({ path: path, names: normalise(next) });
  }
  return pairs;
}

// ── the index ───────────────────────────────────────────────────────────

// Every tag that is actually on something, with how many things, so the
// sidebar can list tags without walking the map per row. Tags that exist
// only as a definition — made, never used — are the caller's business; this
// counts what the disk says.
function tally(index) {
  var counts = {};
  for (var path in index) {
    var names = index[path] || [];
    for (var i = 0; i < names.length; ++i)
      counts[names[i]] = (counts[names[i]] || 0) + 1;
  }
  return counts;
}

function pathsWith(index, tag) {
  var out = [];
  for (var path in index)
    if (hasTag(index[path], tag)) out.push(path);
  return out.sort();
}
