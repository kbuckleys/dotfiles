// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CLIO'S PURE HALF — everything about a note that is not a rectangle on a
// screen. Kept here so the shape of a note, the reading of a saved file and
// the writing of one can be reasoned about without a compositor.

.pragma library

// The palette a note can wear, by NAME. The names are zenon's, resolved to
// colours by the board — the same split oracle and howler use, and for the
// same reason: a file full of hex is a palette said twice.
var HUES = ["sand", "yellow", "green", "cyan", "blue", "magenta", "pink"];

// The sizes a note's text can be, smallest first. A stepper rather than a
// number: there is no note that wants 15px in particular.
var SIZES = [12, 14, 17, 21];

var MIN_W = 180;
var MIN_H = 140;
var MAX_W = 900;
var MAX_H = 900;

function clamp(v, lo, hi) {
  v = Number(v);
  if (isNaN(v)) return lo;
  return v < lo ? lo : (v > hi ? hi : v);
}

// A note, with every field present and in range. Made here rather than at the
// call site so a note read off disk and a note made by hand cannot differ in
// which keys they have — the board reads these fields unguarded.
function blank(id, x, y, hue) {
  return {
    id: String(id),
    text: "",
    hue: HUES.indexOf(hue) >= 0 ? hue : HUES[0],
    x: Math.round(Number(x) || 0),
    y: Math.round(Number(y) || 0),
    w: 260,
    h: 220,
    size: 14,
    // WHICH ONE IS IN FRONT, as a number rather than as a position in the
    // list. Raising by reordering would renumber every note's index, and the
    // board addresses a note BY index — so the one you clicked would hand its
    // geometry to whichever note took its place.
    z: 0
  };
}

function sane(n, id) {
  if (!n || typeof n !== "object") return null;
  return {
    id: String(n.id || id),
    text: String(n.text || ""),
    hue: HUES.indexOf(n.hue) >= 0 ? n.hue : HUES[0],
    x: Math.round(clamp(n.x, -MAX_W, 100000)),
    y: Math.round(clamp(n.y, -MAX_H, 100000)),
    w: Math.round(clamp(n.w, MIN_W, MAX_W)),
    h: Math.round(clamp(n.h, MIN_H, MAX_H)),
    size: SIZES.indexOf(Number(n.size)) >= 0 ? Number(n.size) : 14,
    z: Math.round(Number(n.z) || 0)
  };
}

function parse(text) {
  var out = [];
  try {
    var raw = JSON.parse(String(text || "").trim() || "[]");
    if (!Array.isArray(raw)) return out;
    for (var i = 0; i < raw.length; i++) {
      var n = sane(raw[i], "n" + i);
      if (n !== null) out.push(n);
    }
  } catch (e) {
    // A state file that cannot be read is a state file that is not there.
    // Throwing here would take the whole shell's startup with it.
  }
  return out;
}

function serialize(notes) {
  return JSON.stringify(notes || [], null, 1);
}

// The next hue in the ring, so notes made one after another are not all the
// same colour — the point of a wall of stickies is telling them apart.
function nextHue(notes) {
  if (!notes || notes.length === 0) return HUES[0];
  var last = notes[notes.length - 1].hue;
  var i = HUES.indexOf(last);
  return HUES[(i < 0 ? 0 : i + 1) % HUES.length];
}

// ── AND TRIMMED FURTHER, TO SOMETHING THAT CAN SIT IN A LINE ─────────────
// getFormattedText hands back a whole document too, and Qt wraps whatever it
// returns in a paragraph on top of that. A paragraph is a BLOCK: inserting
// one back into the middle of a sentence to make three words bold would break
// the line in half. This is the run of inline markup inside it, which is the
// only part that can be wrapped in <b> and put back where it came from.
function inline(html) {
  var s = fragment(html);
  // Qt brackets a copied range with these. They are comments, so they do no
  // harm where they land — but they are not part of the note either.
  s = s.replace(/<!--\/?(?:Start|End)Fragment-->/g, "");
  // ONLY WHEN THE RUN IS ONE PARAGRAPH is it safe to unwrap. Stripping the
  // first <p> and the last </p> off a two-paragraph run leaves the inner
  // tags unbalanced — which is how "test</p>" came out of a note with two
  // lines in it — and joins two lines into one besides.
  var m = s.match(/^\s*<p\b[^>]*>([\s\S]*)<\/p>\s*$/i);
  if (m && m[1].search(/<p\b/i) < 0) return m[1].trim();
  return s.trim();
}

// ── WHAT A TAG LOOKS LIKE ONCE QT HAS BEEN THROUGH IT ────────────────────
// Nothing inserted as <b> stays <b>: Qt normalises the document into inline
// styles the moment it reparses it. So asking "is this already bold" cannot
// look for the tag that was inserted — it has to look for what the tag became.
var MARKS = {
  b: { probe: /font-weight:\s*[5-9]\d\d/i, strip: /font-weight:\s*\d+\s*;?/gi },
  i: { probe: /font-style:\s*italic/i,      strip: /font-style:\s*italic\s*;?/gi },
  u: { probe: /text-decoration:[^;"]*underline/i,
       strip: /text-decoration:[^;"]*underline[^;"]*;?/gi }
};

function marked(run, tag) {
  var m = MARKS[tag];
  return m ? m.probe.test(String(run || "")) : false;
}

// TAKING IT OFF, which is not the same as not putting it on. The declaration
// is removed from whatever style attribute carries it, and a span left with
// nothing to say is unwrapped — otherwise every toggle would leave a layer of
// empty markup behind and the note would grow forever.
function unmark(run, tag) {
  var m = MARKS[tag];
  if (!m) return run;
  var s = String(run || "").replace(m.strip, "");
  s = s.replace(/<span style="\s*">([\s\S]*?)<\/span>/gi, "$1");
  s = s.replace(/<span style="">([\s\S]*?)<\/span>/gi, "$1");
  return s;
}

// STEPPED, NOT CYCLED, and it stops at the ends. A minus and a plus say which
// way they go; a stepper that wrapped from largest back to smallest would be
// a plus that sometimes shrinks the note's text.
function stepSize(size, by) {
  var i = SIZES.indexOf(Number(size));
  if (i < 0) i = 1;
  return SIZES[clamp(i + by, 0, SIZES.length - 1)];
}

// ── WHAT QT HANDS BACK, TRIMMED TO WHAT IS WORTH KEEPING ─────────────────
// A rich-text TextEdit's `text` is a whole HTML DOCUMENT — doctype, meta,
// a stylesheet, the lot — so an EMPTY note was six hundred bytes of Qt
// boilerplate in the state file. Only the body's contents are the note; Qt
// parses a fragment back just as happily as it parses its own document.
function fragment(html) {
  var s = String(html || "");
  var i = s.indexOf("<body");
  if (i < 0) return s;
  var open = s.indexOf(">", i);
  var close = s.lastIndexOf("</body>");
  if (open < 0 || close < 0 || close < open) return s;
  return s.slice(open + 1, close).trim();
}

// A fresh id. Time plus a counter: two notes made in the same millisecond
// would otherwise share one, and the id is how a note is found to be removed.
var _seq = 0;
function newId() {
  _seq = (_seq + 1) % 100000;
  return "n" + Date.now().toString(36) + "-" + _seq.toString(36);
}
