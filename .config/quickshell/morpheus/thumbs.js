// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE POOL OF THUMBNAILS, for everything in this shell that needs one.
//
// Terminus and Picasso both look at the same pictures — Picasso's whole directory
// of wallpapers is a directory Terminus browses — and both used to cache their own
// copy of every one of them, at two sizes, under two names, in two places. The
// same 8MB PNG was decoded and written twice and cleared once.
//
// The KEY IS COMPUTED IN SHELL AND NOWHERE ELSE, and that is the design.
//
// The obvious arrangement — each side works out the filename itself — needs one
// hash function written twice, once in JavaScript and once in something a shell
// can run, producing byte-identical output forever. Terminus had a FNV-style hash
// in JS that no awk can reproduce: `(h ^ c) * 16777619` passes 2^53 and doubles
// stop counting. So instead the generator REPORTS what it made — one
// `source<TAB>thumbnail` line per file — and the caller keeps the mapping. The
// formula then only has to agree with itself.
//
// Existing files are reported without being regenerated, so asking for a
// directory that is already cached costs one `stat` and one `md5sum` per file
// and no decoding at all.

// Under quickshell's own cache root rather than either component's, because it
// belongs to neither of them now.
function dir() {
  return Paths.cacheDir() + "/quickshell/thumbs";
}

// The size both sides settled on. 256 was Terminus' and looked soft in a zoomed
// grid; 480 was Picasso's and is generous for a 190px tile — but a thumbnail
// that is too big costs one decode and a thumbnail that is too small costs a
// fallback to an 8MB original, so the larger number is the cheaper mistake.
const SIZE = 480;

// ── JPEG, NOT PNG ────────────────────────────────────
// A thumbnail of a photograph is a photograph, and PNG is a terrible way
// to store one. Measured over 20 of the pool's own entries: PNG averaged
// 184KB and decoded in 0.114s; the same images as JPEG q85 averaged 27KB
// and decoded in 0.069s. Six times less to read, and a decode that is
// what a person sees as the grid filling in.
//
// The pool was 133MB of PNG. The same pool in JPEG is about 20MB.
//
// WHAT JPEG CANNOT DO IS ALPHA, and rather than flatten it onto a colour
// that would be wrong the moment the theme changed, a source that is not
// opaque is simply not cached — see generate. Those are icons and logos
// and cut-out screenshots: small files that Qt opens directly and quickly,
// which is exactly what a tile does when it has no thumbnail.

// A source that will never have a thumbnail, recorded so it is only ever
// asked about once. Not a path — every real answer is absolute — so the
// two can never be confused.
const NONE = "-";
function none() { return NONE; }
function isNone(v) { return String(v) === NONE; }
const EXT = "jpg";
const QUALITY = "85";

// ── AND ONE SIZE UP, FOR WHEN SOMEBODY IS LOOKING PROPERLY ──────────────
// The preview pane follows the cursor, so what it shows has to be cheap —
// 480 is that. Quick look is ASKED for, one file at a time, which is the
// moment a soft picture stops being acceptable.
//
// It is only ever wanted for a file Qt cannot open itself: an ordinary png
// is handed to Qt directly at whatever size the pane wants, and rendering a
// second copy of it here would be work for nothing.
const BIG = 1600;

// path | size | mtime, hashed. Size and mtime together are what makes replacing
// a picture with a different one of the same name a different cache entry —
// which is what lets both sides leave Qt's image cache on, since a changed file
// is never the same URL.
//
// mtime is the INTEGER second: `find -printf %T@` prints a fraction whose
// digits depend on the filesystem, and two callers that disagree about the tail
// of it disagree about every filename.
// path | size | mtime, hashed. Size and mtime together are what makes replacing
// a picture with a different one of the same name a different cache entry —
// which is what lets both sides leave Qt's image cache on, since a changed file
// is never the same URL.
//
// mtime is the INTEGER second: `find -printf %T@` prints a fraction whose
// digits depend on the filesystem, and two callers that disagree about the tail
// of it disagree about every filename.
//
// Written as one line per step with `;` rather than a here-document: the whole
// script is the single-quoted argument of `sh -c`, and a here-doc inside it is
// read by the OUTER shell, which ends the quoting where nobody meant it to.
function keyScript() {
  return 'sz=$(stat -c %s -- "$1" 2>/dev/null); '
    + 'mt=$(stat -c %Y -- "$1" 2>/dev/null); '
    + 'key=$(printf "%s|%s|%s" "$1" "$sz" "$mt" | md5sum | cut -d" " -f1); ';
}

// `i` a picture, `v` a frame out of a video, `a` a track's cover art. xargs
// hands the first token to the script as $0 and the second as $1, which is the
// same shape terminus' own batch used.
//
// A file that yields nothing — a track with no artwork, a video ffmpeg cannot
// seek — writes nothing and is not reported, which is how the caller knows to
// keep showing its glyph rather than pointing an Image at a path that was never
// written.
// `big` asks for the BIG size under a name of its own, so the two live in
// the cache side by side: the pane keeps showing its cheap copy while quick
// look renders the better one, and neither invalidates the other.
function generate(jobs, big) {
  if (!jobs || jobs.length === 0) return "";
  const d = Strings.shellQuote(dir());
  const px = big ? BIG : SIZE;
  const tail = big ? "@big" : "";
  const args = jobs.map((j) => j.kind + " " + Strings.shellQuote(j.src)).join("\n");
  return "mkdir -p " + d + "; printf '%s\n' " + Strings.shellQuote(args)
    + " | xargs -P 4 -L 1 sh -c '"
    + keyScript()
    + 'out=' + d + '/$key' + tail + '.' + EXT + '; '
    + 'if [ ! -s "$out" ]; then '
    + 'if [ "$0" = v ]; then '
    + 'ffmpeg -nostdin -loglevel quiet -ss 1 -i "$1" -frames:v 1 '
    + '-vf scale=' + px + ':-1 -y "$out"; '
    + 'elif [ "$0" = a ]; then '
    + 'ffmpeg -nostdin -loglevel quiet -i "$1" -an -frames:v 1 '
    + '-vf scale=' + px + ':-1 -y "$out"; '
    + 'else '
    // ── A SOURCE WITH TRANSPARENCY IS NOT CACHED ──────────────
    // JPEG has no alpha, so it is asked first and skipped rather than
    // silently flattened onto black. The answer is `-`, which the
    // caller records — that is what keeps this from being paid again:
    // deciding costs a full decode (0.19s on a 12MB PNG, the same as
    // making the thumbnail would), so it must happen once per version
    // of a file and never again.
    //
    // `%[opaque]` and not `%[channels]`: the question is whether the
    // picture actually USES transparency, not whether the format left
    // room for it. An opaque screenshot saved with an alpha channel is
    // perfectly good JPEG material and there are a lot of those.
    //
    // JPEG sources are exempt because the format cannot carry alpha,
    // and they are the common case — no decode is spent proving it.
    + (big ? '' :
        'case "$1" in *.jpg|*.JPG|*.jpeg|*.JPEG|*.jpe|*.JPE) ;; '
        + '*) if [ "$(magick identify -format "%[opaque]" "$1" '
        + '2>/dev/null)" = False ]; then '
        + 'printf "%s\t' + NONE + '\n" "$1"; exit 0; fi ;; esac; ')
    + 'magick "$1"[0] -auto-orient -thumbnail ' + px + 'x' + px
    + ' -strip -quality ' + QUALITY + ' "$out"; '
    + 'fi; fi; '
    + 'test -s "$out" && printf "%s\t%s\n" "$1" "$out"'
    + "' 2>/dev/null";
}

// The same key, for a caller that already has its own `find` running and wants
// the thumbnail named inside it — Picasso scans and thumbnails in one pass.
// `$1` must be the path when this is spliced in.
function keyExpr() {
  return keyScript() + 'out=' + Strings.shellQuote(dir())
    + '/$key.' + EXT + '; ';
}

// ── AND WHAT IT REPORTED, REMEMBERED ───────────────────────
// Naming a thumbnail costs a `stat` and an `md5sum` PER FILE even when
// every one of them is already on disk — measured at 0.49s for a folder of
// 481, four cores busy, before a single cached picture can be shown. The
// key is computed in shell and nowhere else, and that stays true; what was
// missing is that nobody wrote down the answer.
//
// So the answer is kept: source -> "size|mtime|key". The key still comes
// from the shell, but only once per version of a file. Size and mtime are
// stored beside it because they are two thirds of what the key is MADE of,
// and a caller that already stat'ed the file — which any file manager
// listing a directory has — can check them itself and skip the process
// entirely.
//
// It lives inside the thumbnail directory on purpose: an index of a cache
// belongs to the cache, and deleting the pool takes its index with it
// rather than leaving one that promises files nobody has.
function indexPath() { return dir() + "/index.json"; }

// The hash out of a path generate() reported, and the path back out of a
// hash. Only the normal size is indexed — `@big` is rendered on demand for
// one file at a time and has nothing to save.
function keyOf(thumb) {
  const t = String(thumb || "");
  const cut = t.lastIndexOf("/");
  const base = cut >= 0 ? t.slice(cut + 1) : t;
  const dot = "." + EXT;
  if (base.slice(-dot.length) !== dot) return "";
  const k = base.slice(0, -dot.length);
  return /^[0-9a-f]{32}$/.test(k) ? k : "";
}

function fileFor(key) { return dir() + "/" + key + "." + EXT; }

// source -> thumbnail, from what generate() reported.
function size() { return SIZE; }

function parseMade(text) {
  const out = {};
  for (const line of String(text || "").split("\n")) {
    const cut = line.indexOf("\t");
    if (cut > 0) out[line.slice(0, cut)] = line.slice(cut + 1);
  }
  return out;
}

// The pool is SHARED, so nothing may prune it by asking "does any wallpaper
// claim this file" — the answer is no for every thumbnail Terminus made, and
// Picasso's old sweep would have deleted the lot on its next scan. Age is the
// only question either side can answer about the other's entries: a thumbnail
// nothing has regenerated in a month is one whose source is gone or changed.
function sweep(days) {
  const d = Math.max(1, Math.floor(Number(days) || 30));
  // BOTH extensions. The pool was PNG until the format changed, and
  // those files are now unreachable — nothing will ever regenerate one,
  // so without this they would sit there being 133MB forever.
  return "find " + Strings.shellQuote(dir())
    + " -maxdepth 1 -type f \\( -name '*." + EXT + "' -o -name '*.png' \\)"
    + " -mtime +" + d + " -delete 2>/dev/null";
}
