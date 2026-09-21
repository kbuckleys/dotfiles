// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HOWLER's pure half — what a notification is worth keeping, and what has to
// be thrown away before it is written down. No QML in here; Howler.qml runs
// the server and the panels draw it.

// ── WHAT CANNOT SURVIVE A RESTART ─────────────────────────────────────────
// An image reference is only worth storing if it will still resolve in a
// session that has never met the process which sent it.
//
// A quickshell provider handle is the clearest case: `image://qsimage/13/1`
// is a token for ONE running instance, so the process that could answer it is
// the process that has just exited. It is the least durable thing a
// notification can carry, not an edge case.
//
// A path is volatile for a different reason and the same outcome: an app
// writes its icon to a temporary file, the file goes when the app does, and
// what is left in the history is a row with a dead reference — a failure that
// happens INVISIBLY and LATE, in a warning that names a number rather than
// the notification it came from.
//
// A bare themed name is neither. It is a lookup that works in any session,
// and it is what a cleaned row falls back to.
function localImage(src) {
  const s = String(src === undefined || src === null ? "" : src);
  if (s === "") return false;
  if (s.indexOf("image://") === 0) return true;   // any provider handle
  if (s.indexOf("file://") === 0) return true;    // a url to a path
  if (s.charAt(0) === "/") return true;           // a path
  return false;
}

// One row, cleaned. `image` is the only field inspected — `appIcon` is the
// application's own icon and is as stable as the application is, so a path
// there is left exactly as it came.
function keepable(row) {
  const out = {};
  for (const k in row) if (Object.prototype.hasOwnProperty.call(row, k))
    out[k] = row[k];
  if (localImage(out.image)) out.image = "";
  return out;
}

function serialize(rows) {
  const list = Array.isArray(rows) ? rows : [];
  const out = [];
  for (let i = 0; i < list.length; ++i) out.push(keepable(list[i]));
  return JSON.stringify(out);
}

// THE SAME RULE AGAIN ON THE WAY IN, and that is not belt and braces. A
// history written before the rule existed still holds the dead handle, and a
// fix that only ran on write would need the file deleted by hand to take
// effect.
//
// Anything that is not a list of rows is no history at all: empty text,
// nonsense, or a JSON value of the wrong shape all mean the same thing, and
// the panel that reads this should never have to tell them apart.
function parse(text) {
  let j = null;
  try { j = JSON.parse(String(text || "").trim() || "[]"); }
  catch (e) { return []; }
  if (!Array.isArray(j)) return [];
  const out = [];
  for (let i = 0; i < j.length; ++i)
    if (j[i] && typeof j[i] === "object") out.push(keepable(j[i]));
  return out;
}
