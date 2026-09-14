// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

// The name a wallpaper goes by in the picker: the file's own, without the
// directory or the extension.
function label(path) {
  const base = String(path || "").split("/").pop();
  const dot = base.lastIndexOf(".");
  return dot > 0 ? base.slice(0, dot) : base;
}

// The path with the wallpaper root stripped off, e.g. "ether/pack_21/eveWS".
// This is what the filter matches: the scan is recursive, and typing a
// folder's name is the only way to narrow to one pack without a tree view.
function rel(path, dir) {
  const p = String(path || "");
  const d = String(dir || "");
  return (d !== "" && p.indexOf(d + "/") === 0) ? p.slice(d.length + 1) : p;
}

// A row is { path, thumb, mtime, size }: the wallpaper, the cached thumbnail
// the picker actually draws (thumb is "" when one could not be generated),
// and the two facts the ordering needs.
function filter(files, query, dir) {
  const q = String(query || "").trim().toLowerCase();
  if (q === "") return files;
  return files.filter((f) => rel(f.path, dir).toLowerCase().indexOf(q) >= 0);
}

// scan() emits "<path>\t<thumb>\t<mtime>\t<size>" per line; a line with the
// wrong field count is a filename with a tab in it, and is dropped rather
// than half-parsed into a row that would sort somewhere absurd.
function parseRows(text) {
  const out = [];
  for (const line of String(text || "").split("\n")) {
    if (line.trim() === "") continue;
    const parts = line.split("\t");
    if (parts.length !== 4) continue;
    out.push({
      path: parts[0],
      thumb: parts[1],
      mtime: parseFloat(parts[2]) || 0,
      size: parseInt(parts[3], 10) || 0
    });
  }
  return out;
}

// Ordering. Sorts a COPY: the caller's array is the scan's own result and is
// shared with everything else reading it.
function sortRows(files, mode, dir) {
  const out = (files || []).slice();
  if (mode === "name")
    out.sort((a, b) => rel(a.path, dir).localeCompare(rel(b.path, dir)));
  else if (mode === "size")
    out.sort((a, b) => b.size - a.size);
  else
    // "recent" — newest first, which is the default
    out.sort((a, b) => b.mtime - a.mtime);
  return out;
}

function serialize(map) {
  return JSON.stringify(map);
}

function parse(text) {
  try {
    const v = JSON.parse(text || "{}");
    return (v && typeof v === "object" && !Array.isArray(v)) ? v : {};
  } catch (e) {
    return {};
  }
}

// ── the whole of picasso's state ──────────────────────────────────────────
// Two maps now, both keyed by monitor name: which image is on it, and how
// that image is fitted to it. Fit used to be one global setting, which is
// wrong the moment two monitors are different shapes — the exact case picasso
// already handled for the image itself.
//
// THE OLD FILE IS A BARE MAP of monitor to path, with no wrapper at all. It
// has to keep loading, and a version marker is the only honest way to tell
// the two apart: a monitor cannot be called "v", but it could in principle be
// called "assignment", and a format that guesses from a key name is a format
// that corrupts somebody's config the day they buy that monitor.
function serializeState(assignment, fits) {
  return JSON.stringify({ v: 2, assignment: assignment || {}, fits: fits || {} });
}

function parseState(text) {
  const j = parse(text);
  if (j.v === 2) {
    return {
      assignment: (j.assignment && typeof j.assignment === "object"
                   && !Array.isArray(j.assignment)) ? j.assignment : {},
      fits: (j.fits && typeof j.fits === "object"
             && !Array.isArray(j.fits)) ? j.fits : {}
    };
  }
  // version 1: the object IS the assignment, and nothing had a fit of its own
  return { assignment: j, fits: {} };
}
