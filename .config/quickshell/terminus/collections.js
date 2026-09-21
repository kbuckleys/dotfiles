// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── collections ─────────────────────────────────────────────────────────
// A saved QUESTION, not a saved answer. Opening one asks the disk again, so
// what it holds is whatever matches today — which is the whole difference
// between this and a bookmark, and the reason it cannot just be a list of
// paths written down somewhere.
//
// A collection is { id, name, ink, root, rules: [...] } and every rule is
// { kind, op, value }. They are ANDed: each one narrows what the last one
// found. Nobody has yet wanted "png OR jpg" badly enough to justify a
// grammar, and `-e png -e jpg` is one rule with two values when they do.
//
// ── WHAT RUNS, AND IN WHICH ORDER ──────────────────────────────────────
// Three stages, cheapest first, because the expensive one must never see a
// file the cheap ones could have ruled out:
//
//   1. fd    — name, kind, size and date, all of them flags it already has
//   2. rg    — content, over only what fd let through
//   3. tags  — an intersection with the index, in JS, no process at all
//
// Putting content last is not a detail. `rg` over a home directory is
// seconds of work; `rg` over the ninety files fd returned is instant, and
// the two produce the same answer.
//
// No .pragma library — see tags.js for why.

// ── what a rule can ask ─────────────────────────────────────────────────
// Kept here rather than in the QML so the editor's dropdowns and the
// compiler cannot drift apart: a kind the editor offers and the compiler
// has never heard of is a rule that silently matches everything.
// ── HOW A COLLECTION IS READ WHEN IT HAS NOT BEEN TOLD ──────────────────
// A collection is its own place, not a view of the one you came from, so
// it does not inherit the pane's arrangement — it starts with this and
// remembers whatever you change it to.
//
// `list` rather than `columns`: the rows come from all over the tree, so
// the parent column has nothing true to say about them, and rather than
// what the cursor is on you usually want to see WHERE each one is, which
// is a column the full-width list has room for.
var DEFAULT_VIEW = "list";

var KINDS = [
  { kind: "name",    label: "Name",     ops: ["contains", "is", "matches"] },
  { kind: "kind",    label: "Kind",     ops: ["is"] },
  // EXTENSION, SEPARATELY FROM KIND. "Kind is image" is ten extensions at
  // once, which is the right answer to "show me the pictures" and no answer
  // at all to "show me the PNGs" — and that second question is the commoner
  // one. Typed rather than picked, because the list of extensions a person
  // might want is the list of extensions that exist.
  { kind: "ext",     label: "Extension", ops: ["is"] },
  { kind: "tag",     label: "Tag",      ops: ["is", "is not"] },
  { kind: "size",    label: "Size",     ops: ["larger", "smaller"] },
  { kind: "date",    label: "Modified", ops: ["within", "before"] },
  { kind: "content", label: "Contains", ops: ["text", "matches"] }
];

// The Kind row's own vocabulary. `fd` says folder/file with -t and
// extensions with -e, so one list covers both by saying which it is.
var FILE_KINDS = [
  { name: "folder",   flag: "-t d" },
  { name: "file",     flag: "-t f" },
  { name: "image",    ext: ["png", "jpg", "jpeg", "gif", "webp", "avif", "bmp", "svg", "tif", "tiff"] },
  { name: "video",    ext: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv"] },
  { name: "audio",    ext: ["mp3", "flac", "wav", "ogg", "opus", "m4a", "aac"] },
  { name: "document", ext: ["pdf", "epub", "djvu", "doc", "docx", "odt", "rtf"] },
  { name: "archive",  ext: ["zip", "tar", "gz", "xz", "zst", "bz2", "7z", "rar"] },
  { name: "code",     ext: ["js", "ts", "qml", "py", "rs", "go", "c", "h", "cpp", "sh", "lua", "json", "toml", "yaml", "yml"] }
];

function kindSpec(name) {
  for (var i = 0; i < FILE_KINDS.length; ++i)
    if (FILE_KINDS[i].name === name) return FILE_KINDS[i];
  return null;
}

function opsFor(kind) {
  for (var i = 0; i < KINDS.length; ++i)
    if (KINDS[i].kind === kind) return KINDS[i].ops;
  return [];
}

function newRule(kind) {
  var ops = opsFor(kind);
  return { kind: kind, op: ops.length > 0 ? ops[0] : "", value: "" };
}

function blank(id) {
  return {
    id: id,
    name: "",
    ink: "cyan",
    root: "",
    rules: [newRule("name")]
  };
}

// ── size and date, as fd spells them ────────────────────────────────────

// "10m", "2g", "500k" — and a bare number means bytes, which is what a
// person typing "1000" into a size box means. fd wants a unit either way.
function sizeArg(value) {
  var v = String(value || "").trim().toLowerCase().replace(/\s+/g, "");
  if (v === "") return "";
  var m = v.match(/^(\d+(?:\.\d+)?)\s*([kmgt]?)(i?b?)$/);
  if (!m) return "";
  var n = m[1];
  // fd takes no fractions, so 1.5m becomes 1536k rather than being refused
  // for a reason nobody typing it would guess.
  var unit = m[2] || "b";
  if (n.indexOf(".") >= 0) {
    var step = { b: 1, k: 1024, m: 1024 * 1024, g: 1024 * 1024 * 1024,
                 t: 1024 * 1024 * 1024 * 1024 };
    var bytes = Math.round(parseFloat(n) * (step[unit] || 1));
    return String(bytes) + "b";
  }
  return n + unit;
}

// "7d", "2w", "3 months" — fd understands a duration string directly, so
// this only has to refuse what it would choke on.
function dateArg(value) {
  var v = String(value || "").trim();
  if (v === "") return "";
  if (/^\d+$/.test(v)) return v + "d";          // a bare number means days
  if (/^[0-9]+\s*(s|min|h|d|w|m|y|[a-z]+)$/i.test(v)) return v.replace(/\s+/g, "");
  // An absolute date, which fd also takes
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
  return "";
}

// ── stage one: fd ───────────────────────────────────────────────────────

// ~ IS WHAT PEOPLE TYPE. The shell expands it before a program ever sees
// it, so a path handed straight to fd in an argv — which is where this one
// goes, correctly quoted — arrives as a literal tilde and matches a
// directory called "~" that does not exist. Expanded here rather than when
// the collection is saved, so the stored rule keeps the "~" the person
// wrote: it is shorter to read and it still means home on another machine.
function expandHome(path, home) {
  var p = String(path || "");
  if (!home) return p;
  if (p === "~") return home;
  if (p.indexOf("~/") === 0) return home + p.slice(1);
  return p;
}

// ── WHAT A "RECENT FILES" SWEEP MUST NOT COUNT ──────────────────────────
// Measured on this machine over a 7-day window: 5,748 of 5,824 hits were
// nvim's undo history under .local/share, and over a 1-day window 886 of
// 988 were Discord and Firefox rewriting their profiles. None of that is a
// file anybody has "worked on recently", and at 2,000 results the cap threw
// away the ones that were.
//
// Excluding hidden files wholesale is the obvious alternative and is wrong
// here: this machine's actual work lives in ~/.config/quickshell, which is
// under a dot-directory. So the rule is not "hidden" but "application
// state" — caches, package and build trees, browser and chat profiles, and
// the share/state directories apps scribble in.
//
// With this list the same 7-day window returns 75 files, all of them real.
var NOISE = [
  ".cache", ".local/state", ".local/share", ".claude",
  ".git", "node_modules", "__pycache__", ".venv",
  ".npm", ".cargo", ".rustup", ".gradle", ".m2", ".java", ".dotnet",
  ".mozilla", ".thunderbird", ".config/mozilla",
  ".config/discord", ".config/Code", ".config/chromium",
  ".config/BraveSoftware",
  ".steam", ".var", ".nv", ".pki", ".gnupg", ".zcompdump"
];

function fdCommand(folder, rules, home) {
  var args = ["fd", "--hidden", "--no-ignore", "--color=never", "--print0"];
  // Only for a folder that asks for it — see NOISE. A collection you wrote
  // yourself is a question you meant, and quietly dropping half the disk
  // out from under it would make its answers wrong in a way nothing on
  // screen could explain.
  if (folder && folder.tidy)
    for (var q = 0; q < NOISE.length; ++q)
      args.push("--exclude " + Strings.shellQuote(NOISE[q]));
  var pattern = "";
  var patternIsRegex = false;
  var sawKind = false;

  for (var i = 0; i < rules.length; ++i) {
    var r = rules[i];
    var v = String(r.value || "").trim();
    if (v === "" && r.kind !== "kind") continue;

    if (r.kind === "name") {
      if (r.op === "matches") { pattern = v; patternIsRegex = true; }
      else if (r.op === "is") {
        // Anchored, so "notes" is notes and not notes-old.
        pattern = "^" + escapeRe(v) + "$";
        patternIsRegex = true;
      } else {
        pattern = escapeRe(v);
        patternIsRegex = true;
      }
    } else if (r.kind === "ext") {
      // Comma-separated, so "png,jpg" is one rule. fd ORs its -e flags,
      // which is what a list of extensions means.
      var exts = v.split(",");
      for (var x = 0; x < exts.length; ++x) {
        var ex = exts[x].trim().replace(/^[.*]+/, "");
        if (ex !== "") { args.push("-e " + Strings.shellQuote(ex)); sawKind = true; }
      }
    } else if (r.kind === "kind") {
      var spec = kindSpec(v);
      if (!spec) continue;
      sawKind = true;
      if (spec.flag) args.push(spec.flag);
      else for (var e = 0; e < spec.ext.length; ++e)
        args.push("-e " + spec.ext[e]);
    } else if (r.kind === "size") {
      var s = sizeArg(v);
      if (s !== "") args.push("--size " + (r.op === "smaller" ? "-" : "+") + s);
    } else if (r.kind === "date") {
      var d = dateArg(v);
      if (d !== "")
        args.push((r.op === "before" ? "--changed-before " : "--changed-within ")
                  + Strings.shellQuote(d));
    }
  }

  // Files by default. Without this a name rule matches the DIRECTORIES that
  // contain the files too, and a collection of "invoices" lists the
  // invoices folder alongside the invoices.
  //
  // `anyKind` opts out, and Recents is why. That default is about NAME
  // rules; Recents has none — it is a date over home — so it was excluding
  // folders for a reason that did not apply to it, and a folder worked in
  // this morning is as good an answer to "where did I put that" as a file
  // saved in it. Set on the record rather than inferred from "has no name
  // rule", because a collection someone wrote deliberately should not
  // change what it matches when they delete a rule from it.
  if (!sawKind && !(folder && folder.anyKind)) args.push("-t f");

  // fd wants the pattern before the path, and an empty pattern means
  // everything — which is spelt with an explicit "." rather than by leaving
  // it out, because leaving it out makes fd read the path as the pattern.
  args.push(patternIsRegex && pattern !== ""
    ? Strings.shellQuote(pattern) : Strings.shellQuote("."));
  args.push("--");
  args.push(Strings.shellQuote(expandHome(folder.root || ".", home)));
  return args.join(" ");
}

function escapeRe(s) {
  return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// ── stage two: rg, over what fd found ───────────────────────────────────

function contentRule(rules) {
  for (var i = 0; i < rules.length; ++i) {
    var r = rules[i];
    if (r.kind === "content" && String(r.value || "").trim() !== "") return r;
  }
  return null;
}

// xargs -0 rather than a shell loop: one rg over the whole candidate list
// is one process, and a loop would be one per file. -r so an empty list
// runs nothing at all instead of rg reading standard input and hanging
// forever, which is exactly what "no candidates" would otherwise mean.
function rgStage(rule) {
  var pat = String(rule.value || "");
  var flags = "--files-with-matches --null --color=never";
  if (rule.op !== "matches") flags += " --fixed-strings";
  flags += " --smart-case";
  return "xargs -0 -r rg " + flags + " -- " + Strings.shellQuote(pat);
}

// ── the whole pipeline ──────────────────────────────────────────────────

// Returns "" when the folder cannot ask anything yet — no rules, or only
// empty ones. The caller shows nothing rather than listing the entire disk,
// which is what an unconstrained fd would do.
function command(folder, home) {
  var rules = (folder && folder.rules) ? folder.rules : [];
  var usable = 0;
  for (var i = 0; i < rules.length; ++i) {
    if (rules[i].kind === "tag") { usable++; continue; }
    if (String(rules[i].value || "").trim() !== "") usable++;
  }
  if (usable === 0) return "";

  var cmd = fdCommand(folder, rules, home);
  var content = contentRule(rules);
  if (content) cmd += " | " + rgStage(content);
  // A cap, because a collection is a page you look at and 40,000 rows is
  // not one. The same 2000 the grep search settles for.
  cmd += " | head -z -n 2000";
  return cmd;
}

// Whether anything here needs a process at all. A folder whose only rules
// are tags is answered entirely from the index.
function tagsOnly(folder) {
  var rules = (folder && folder.rules) ? folder.rules : [];
  if (rules.length === 0) return false;
  for (var i = 0; i < rules.length; ++i) {
    if (rules[i].kind !== "tag") {
      if (String(rules[i].value || "").trim() !== "") return false;
    }
  }
  return true;
}

// ── stage three: the tag rules, in memory ───────────────────────────────

// Applied to whatever the pipeline returned — or, when the folder asks
// about nothing else, to every path the index knows.
function applyTags(folder, paths, index) {
  var rules = (folder && folder.rules) ? folder.rules : [];
  var out = paths;
  for (var i = 0; i < rules.length; ++i) {
    var r = rules[i];
    if (r.kind !== "tag") continue;
    var want = String(r.value || "").trim();
    if (want === "") continue;
    var negate = r.op === "is not";
    out = out.filter(function (p) {
      var names = index[p] || [];
      var has = names.indexOf(want) >= 0;
      return negate ? !has : has;
    });
  }
  return out;
}

// Every path the index knows, for the tags-only case.
function allTagged(index) {
  var out = [];
  for (var p in index) out.push(p);
  return out;
}

// ── describing one, in a sentence ───────────────────────────────────────
// The sidebar has a name and the editor has the rules; this is for the
// places in between — the status line when one opens, and the row in the
// manager under its name.
function describe(folder) {
  var rules = (folder && folder.rules) ? folder.rules : [];
  var bits = [];
  for (var i = 0; i < rules.length; ++i) {
    var r = rules[i];
    var v = String(r.value || "").trim();
    if (v === "") continue;
    if (r.kind === "name") bits.push("name " + r.op + " " + v);
    else if (r.kind === "kind") bits.push(v);
    else if (r.kind === "ext")
      bits.push(v.split(",").map(function (e) {
        return "." + e.trim().replace(/^[.*]+/, "");
      }).join(" / "));
    else if (r.kind === "tag") bits.push((r.op === "is not" ? "not " : "") + "#" + v);
    else if (r.kind === "size") bits.push(r.op + " than " + v);
    else if (r.kind === "date") bits.push("modified " + r.op + " " + v);
    else if (r.kind === "content") bits.push("containing " + v);
  }
  return bits.join(" · ");
}
