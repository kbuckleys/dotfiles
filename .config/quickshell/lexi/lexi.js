// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

function dictHistoryPath() {
  return Paths.cacheDir() + "/dict-history";
}

function transHistoryPath() {
  return Paths.cacheDir() + "/translate-history";
}

function usagePath() {
  return Paths.cacheDir() + "/translate-usage";
}

const UA = "qs-lexicon/1.0 (https://github.com/kbuckleys/)";
const TRANSLATE_ENDPOINT = "https://translate.googleapis.com/translate_a/single";
const WIKT_API = "https://en.wiktionary.org/w/api.php";
const WIKT_AUDIO_BASE = "https://commons.wikimedia.org/wiki/Special:FilePath/";

// Icons (JetBrainsMono Nerd Font). JS "\uXXXX" is strictly four hex digits,
// so astral-plane codepoints are written as explicit surrogate pairs:
//   U+F405 → \uF405 · U+F040 → \uF040 · U+F07C5 → \uDB81\uDFC5
//   U+F05CA → \uDB81\uDDCA · U+F02DA → \uDB80\uDEDA
const ICON_HEAD = "\uF405";
const ICON_AUDIO = "\uDB81\uDFC5";
const ICON_CORRECTED = "\uF040";
const ICON_TRANSLATE = "\uDB81\uDDCA";
const ICON_STAR = "\uDB80\uDEDA";

// History caps
const DICT_HISTORY_MAX = 100;
const TRANS_HISTORY_MAX = 20;

// TTS: Google rejects a single request over ~200 chars; split on sentence
// boundaries where possible and pack into chunks of at most this size.
const TTS_CHUNK_MAX = 190;
const TTS_REQUEST_GAP = 0.25;

// Target languages: native name + Google code. Source is auto-detected
// unless the input carries an explicit "<code>: " prefix.
const LANGS = [
  ["ar", "العربية"], ["bg", "Български"], ["bn", "বাংলা"], ["ca", "Català"],
  ["cs", "Čeština"], ["da", "Dansk"], ["de", "Deutsch"], ["el", "Ελληνικά"],
  ["en", "English"], ["es", "Español"], ["et", "Eesti"], ["fa", "فارسی"],
  ["fi", "Suomi"], ["fil", "Filipino"], ["fr", "Français"], ["gu", "ગુજરાતી"],
  ["he", "עברית"], ["hi", "हिन्दी"], ["hr", "Hrvatski"], ["hu", "Magyar"],
  ["id", "Indonesia"], ["it", "Italiano"], ["ja", "日本語"], ["kn", "ಕನ್ನಡ"],
  ["ko", "한국어"], ["lt", "Lietuvių"], ["lv", "Latviešu"], ["ml", "മലയാളം"],
  ["mr", "मराठी"], ["ms", "Bahasa Melayu"], ["nl", "Nederlands"], ["no", "Norsk"],
  ["pl", "Polski"], ["pt", "Português"], ["pt-BR", "Português (Brasil)"],
  ["ro", "Română"], ["ru", "Русский"], ["sk", "Slovenčina"], ["sl", "Slovenščina"],
  ["sr", "Српски"], ["sv", "Svenska"], ["sw", "Kiswahili"], ["ta", "தமிழ்"],
  ["te", "తెలుగు"], ["th", "ไทย"], ["tr", "Türkçe"], ["uk", "Українська"],
  ["ur", "اردو"], ["vi", "Tiếng Việt"], ["zh-CN", "简体中文"], ["zh-TW", "繁體中文"],
];

// A Wiktionary heading is the language's name IN ENGLISH, and LANGS holds
// native names because that is what a person picking one wants to read.
// So the two live side by side: Español to choose, Spanish to find.
const EN_NAMES = {
  ar: "Arabic", bg: "Bulgarian", bn: "Bengali", ca: "Catalan",
  cs: "Czech", da: "Danish", de: "German", el: "Greek",
  en: "English", es: "Spanish", et: "Estonian", fa: "Persian",
  fi: "Finnish", fil: "Tagalog", fr: "French", gu: "Gujarati",
  he: "Hebrew", hi: "Hindi", hr: "Serbo-Croatian", hu: "Hungarian",
  id: "Indonesian", it: "Italian", ja: "Japanese", kn: "Kannada",
  ko: "Korean", lt: "Lithuanian", lv: "Latvian", ml: "Malayalam",
  mr: "Marathi", ms: "Malay", nl: "Dutch", no: "Norwegian",
  pl: "Polish", pt: "Portuguese", "pt-BR": "Portuguese",
  ro: "Romanian", ru: "Russian", sk: "Slovak", sl: "Slovene",
  sr: "Serbo-Croatian", sv: "Swedish", sw: "Swahili", ta: "Tamil",
  te: "Telugu", th: "Thai", tr: "Turkish", uk: "Ukrainian",
  ur: "Urdu", vi: "Vietnamese", "zh-CN": "Chinese", "zh-TW": "Chinese",
};

function enName(code) { return EN_NAMES[code] || "English"; }

// The other way round, for reading a heading off a page and turning it
// into something the picker and the cache can key on.
function codeForEnName(name) {
  const want = String(name || "").trim().toLowerCase();
  for (const code in EN_NAMES)
    if (EN_NAMES[code].toLowerCase() === want) return code;
  return null;
}

// Only the ones Wiktionary has a heading for can be READ, which is not
// the same set as the ones Google will translate into.
function dictLangRows(usage) {
  const rows = [];
  for (const r of rankedLangs(usage))
    if (EN_NAMES[r.code]) rows.push(r);
  return rows;
}

const SOURCE_NAMES = {};
for (const l of LANGS) SOURCE_NAMES[l[0]] = l[1];
SOURCE_NAMES["iw"] = "עברית";
SOURCE_NAMES["jw"] = "Jawa";

function sourceName(code) {
  return (code && SOURCE_NAMES[code]) || (code ? String(code).toUpperCase() : "");
}

const KNOWN_CODES = {};
for (const c of [
  "af","sq","am","ar","hy","az","eu","be","bn","bs","bg","ca","ceb","zh-CN",
  "zh-TW","co","hr","cs","da","nl","en","eo","et","fi","fr","fy","gl","ka","de",
  "el","gu","ht","ha","haw","he","hi","hmn","hu","is","ig","id","ga","it","ja",
  "jv","kn","kk","km","ko","ku","ky","lo","la","lv","lt","lb","mk","mg","ms",
  "ml","mt","mi","mr","mn","my","ne","no","ny","or","ps","fa","pl","pt","pa",
  "ro","ru","sm","gd","sr","st","sn","sd","si","sk","sl","so","es","su","sw",
  "sv","tg","ta","te","th","tr","tk","uk","ur","ug","uz","vi","cy","xh","yi",
  "yo","zu","iw","jw",
]) KNOWN_CODES[c] = true;

// Truncate by Unicode code point so surrogate pairs are never split.
function truncate(text, max) {
  const chars = Array.from(String(text));
  if (chars.length <= max) return String(text);
  return chars.slice(0, max).join("") + "…";
}

function hasContent(s) {
  return /\S/.test(s);
}

// Parse the "<code>: text" source-language prefix, mirroring translate.lua:
// only a recognised code counts, so "no: way" isn't read as Norwegian.
function splitSourcePrefix(raw) {
  const m = String(raw).match(/^(\S+)\s*:\s*(\S.*)$/);
  if (m && KNOWN_CODES[m[1]] && hasContent(m[2])) {
    return { text: m[2], source: m[1] };
  }
  return { text: String(raw), source: null };
}

// Build a Google Translate request. POST body so long inputs aren't
// constrained by URL length limits, mirroring translate.lua.
function translateRequest(text, tl, sl) {
  const src = sl && KNOWN_CODES[sl] ? sl : "auto";
  return {
    url: TRANSLATE_ENDPOINT,
    body: "client=gtx&sl=" + encodeURIComponent(src) +
      "&tl=" + encodeURIComponent(tl) +
      "&dt=t&dt=rm&q=" + encodeURIComponent(text),
  };
}

// Response shape: [[["trans","src echo",null,null,"roman"],...], null, "src"]
function parseTranslateResponse(body) {
  let data;
  try { data = JSON.parse(body); } catch (e) { return null; }
  if (!data || !Array.isArray(data) || !Array.isArray(data[0])) return null;

  const parts = [];
  let roman = null;
  // translate.lua read seg[3] in 1-indexed Lua — JS index 2 here. Some
  // response variants carry it at JS index 3 instead.
  for (const seg of data[0]) {
    if (!Array.isArray(seg)) continue;
    if (typeof seg[0] === "string" && seg[0] !== "") parts.push(seg[0]);
    if (roman === null) {
      if (typeof seg[2] === "string" && seg[2] !== "") roman = seg[2];
      else if (typeof seg[3] === "string" && seg[3] !== "") roman = seg[3];
    }
  }
  if (parts.length === 0) return null;
  return {
    translation: parts.join(""),
    roman: roman,
    source: typeof data[2] === "string" ? data[2] : null,
  };
}

// Split text into sentence-aligned chunks Google's TTS will accept
// (port of split_tts from translate.lua).
function ttsChunks(text) {
  const chunks = [];
  const sentences = [];
  for (const seg of String(text).split(/(?<=[.!?\n。．！？])/)) {
    const piece = seg.replace(/^\s+/, "");
    if (hasContent(piece)) sentences.push(piece);
  }

  let cur = "";
  const flush = () => {
    if (hasContent(cur)) chunks.push(cur);
    cur = "";
  };

  for (const s of sentences) {
    const chars = Array.from(s);
    if (cur !== "" && Array.from(cur).length + chars.length > TTS_CHUNK_MAX) flush();
    if (chars.length <= TTS_CHUNK_MAX) {
      cur += s;
    } else {
      let rest = s;
      while (Array.from(rest).length > TTS_CHUNK_MAX) {
        chunks.push(Array.from(rest).slice(0, TTS_CHUNK_MAX).join(""));
        rest = Array.from(rest).slice(TTS_CHUNK_MAX).join("");
      }
      cur = rest;
    }
  }
  flush();
  return chunks;
}

// One-shot shell script: fetch every TTS chunk sequentially (Google rate
// limit), concatenate into a valid MP3 stream, wait until non-empty, play,
// clean up. Fully detached — quickshell never waits on it.
function ttsScript(prefix, text, code, playerCmd) {
  const chunks = ttsChunks(text);
  if (chunks.length === 0) return null;
  const n = chunks.length;
  const path = "/tmp/" + prefix + ".mp3";

  const cmds = [];
  const pieces = [];
  for (let i = 0; i < n; ++i) {
    const url = "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob" +
      "&tl=" + encodeURIComponent(code) +
      "&total=" + n + "&idx=" + i +
      "&textlen=" + chunks[i].length +
      "&q=" + encodeURIComponent(chunks[i]);
    const piece = path + "." + i;
    cmds.push("curl -sL --max-time 12 -A " + Strings.shellQuote(UA) + " " +
      Strings.shellQuote(url) + " -o " + Strings.shellQuote(piece));
    pieces.push(Strings.shellQuote(piece));
  }

  return "{ " + cmds.join(" && sleep " + TTS_REQUEST_GAP + " && ") + "; } && " +
    "cat " + pieces.join(" ") + " > " + Strings.shellQuote(path) + " && " +
    "rm -f " + pieces.join(" ") + " && " +
    "for i in $(seq 1 40); do [ -s " + Strings.shellQuote(path) + " ] && break; sleep 0.1; done && " +
    playerCmd + " " + Strings.shellQuote(path) + " >/dev/null 2>&1";
}

// Dictionary pronunciation: download to <path> then play, tolerating a slow
// start (the prefetch may still be running when the key lands).
function audioPlayScript(path, playerCmd) {
  return "for i in $(seq 1 30); do [ -s " + Strings.shellQuote(path) + " ] && break; sleep 0.1; done && " +
    "[ -s " + Strings.shellQuote(path) + " ] && " +
    playerCmd + " " + Strings.shellQuote(path) + " >/dev/null 2>&1";
}

// Player preference, best first — same ladder as the Lua scripts.
const PLAYERS = [
  ["mpv", "mpv --no-video --really-quiet"],
  ["mpg123", "mpg123 -q"],
  ["ffplay", "ffplay -nodisp -autoexit -loglevel quiet"],
  ["paplay", "paplay"],
];

function playerProbeCommand() {
  let out = "if command -v " + PLAYERS[0][0] + " >/dev/null 2>&1; then echo " +
    Strings.shellQuote(PLAYERS[0][1]) + ";";
  for (let i = 1; i < PLAYERS.length; ++i) {
    out += " elif command -v " + PLAYERS[i][0] + " >/dev/null 2>&1; then echo " +
      Strings.shellQuote(PLAYERS[i][1]) + ";";
  }
  return out + " else :; fi";
}

const CLIPBOARDS = [["wl-copy", "wl-copy"], ["xclip", "xclip -selection clipboard"],
  ["xsel", "xsel --clipboard --input"], ["pbcopy", "pbcopy"]];

function clipboardProbeCommand() {
  let out = "if command -v " + CLIPBOARDS[0][0] + " >/dev/null 2>&1; then echo " +
    Strings.shellQuote(CLIPBOARDS[0][1]) + ";";
  for (let i = 1; i < CLIPBOARDS.length; ++i) {
    out += " elif command -v " + CLIPBOARDS[i][0] + " >/dev/null 2>&1; then echo " +
      Strings.shellQuote(CLIPBOARDS[i][1]) + ";";
  }
  return out + " else :; fi";
}

// ---------------------------------------------------------------- history --

// Plain lines, most recent first
function parseDictHistory(text) {
  const list = [];
  if (!text) return list;
  for (const line of String(text).split("\n")) {
    if (line.trim() !== "") list.push(line);
  }
  return list;
}

function serializeDictHistory(list) {
  return list.slice(0, DICT_HISTORY_MAX).join("\n") + "\n";
}

function addDictHistory(list, word) {
  const lower = word.toLowerCase();
  const filtered = list.filter((w) => w.toLowerCase() !== lower);
  filtered.unshift(word);
  return filtered.slice(0, DICT_HISTORY_MAX);
}

function removeDictHistory(list, word) {
  const lower = word.toLowerCase();
  return list.filter((w) => w.toLowerCase() !== lower);
}

// JSON lines: { code, source?, text, translation }
function parseTransHistory(text) {
  const entries = [];
  if (!text) return entries;
  for (const line of String(text).split("\n")) {
    if (line.trim() === "") continue;
    try {
      const e = JSON.parse(line);
      if (e && typeof e.code === "string" && typeof e.text === "string") {
        entries.push({ code: e.code, source: e.source || null,
          text: e.text, translation: e.translation || "" });
      }
    } catch (err) {}
  }
  return entries;
}

function serializeTransHistory(entries) {
  if (entries.length === 0) return "";
  return entries.slice(0, TRANS_HISTORY_MAX)
    .map((e) => JSON.stringify(e)).join("\n") + "\n";
}

function addTransHistory(entries, code, source, text, translation) {
  const out = [{ code: code, source: source, text: text, translation: translation }];
  let n = 1;
  for (const e of entries) {
    if (n >= TRANS_HISTORY_MAX) break;
    if (e.code === code && e.text === text) continue;
    out.push(e);
    n++;
  }
  return out;
}

function removeTransHistory(entries, code, text) {
  return entries.filter((e) => !(e.code === code && e.text === text));
}

// One-line picker row for a saved translation
function transHistoryRow(e) {
  const t = truncate((e.text || "").replace(/\n/g, " "), 45);
  const tr = truncate((e.translation || "").replace(/\n/g, " "), 45);
  return t + "  →  " + tr + "  (" + sourceName(e.code) + ")";
}

// ------------------------------------------------------- language ranking --

function parseUsage(text) {
  const usage = {};
  if (!text) return usage;
  for (const line of String(text).split("\n")) {
    const m = line.match(/^(\S+)\s+(\d+)$/);
    if (m) usage[m[1]] = parseInt(m[2], 10);
  }
  return usage;
}

function serializeUsage(usage) {
  const lines = [];
  for (const c in usage) {
    if (usage[c] > 0) lines.push(c + " " + usage[c]);
  }
  return lines.length > 0 ? lines.join("\n") + "\n" : "";
}

// Language-picker filter. Matches the native name or the code, so both
// "deutsch" and "de" land on German. Same case-insensitive substring rule
// every other layer's list uses.
function filterLangs(rows, query) {
  const q = String(query || "").trim().toLowerCase();
  if (!q) return rows;
  return rows.filter((r) =>
    r.name.toLowerCase().indexOf(q) >= 0 ||
    r.code.toLowerCase().indexOf(q) >= 0);
}

// Usage-ranked index list into LANGS: used languages first (stable within
// rank), then the curated order.
function rankedLangs(usage) {
  const order = [];
  for (let i = 0; i < LANGS.length; ++i) order.push(i);
  order.sort((a, b) => {
    const ua = usage[LANGS[a][0]] || 0;
    const ub = usage[LANGS[b][0]] || 0;
    if (ua !== ub) return ub - ua;
    return a - b;
  });
  return order.map((i) => ({
    code: LANGS[i][0], name: LANGS[i][1],
    used: (usage[LANGS[i][0]] || 0) > 0,
  }));
}

// ===========================================================================
// Wiktionary engine
// ===========================================================================

// Accents we prefer to hear, best first
const ACCENT_PREFERENCE = ["US", "UK", "AU"];

// WHAT IS SHOWN, and what is KEPT, are two different numbers.
//
// These used to be one: the parser stopped after two definitions per part
// of speech and six synonyms, so the rest of the entry was never built and
// "show me more" would have meant fetching and parsing the page again.
// Two is still the right thing to READ — a dictionary panel that opens
// onto twenty senses of "set" is a wall — but the other ten now exist, in
// the result and in the cache with it, and the panel simply declines to
// draw them until asked.
//
// Twelve rather than everything: the cache is rewritten through the shell
// on every look-up, so an entry's size is an argv, and the eighteenth
// sense of a verb is not what anyone opened this for.
const MAX_DEFS_PER_POS = 2;
const MAX_SYNONYMS = 6;
const KEEP_DEFS_PER_POS = 12;
const KEEP_SYNONYMS = 14;

const POS_HEADINGS = {};
for (const h of [
  "noun", "proper noun", "verb", "adjective", "adverb", "preposition",
  "conjunction", "interjection", "pronoun", "determiner", "numeral", "number",
  "article", "particle", "phrase", "proverb", "prepositional phrase",
  "verb phrase", "adjective phrase", "adverbial phrase", "contraction",
  "idiom", "abbreviation", "acronym", "initialism", "prefix", "suffix",
]) POS_HEADINGS[h] = true;

const AUDIO_EXT = { ogg: true, oga: true, mp3: true, wav: true, flac: true };

function trim(s) {
  return String(s).replace(/^\s+/, "").replace(/\s+$/, "");
}

// Dictionary lookups are considered contentful only on ASCII alphanumerics,
// ASCII alphanumerics only
function hasAlpha(s) {
  return /[\w]/.test(s);
}

function decodeHtml(s) {
  s = s.replace(/&nbsp;/g, " ");
  s = s.replace(/&amp;/g, "&");
  s = s.replace(/&lt;/g, "<");
  s = s.replace(/&gt;/g, ">");
  s = s.replace(/&quot;/g, '"');
  s = s.replace(/&#39;/g, "'");
  s = s.replace(/&apos;/g, "'");
  return s;
}

// ------------------------------------------------------------------ HTTP --

function httpGet(url) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let req = new XMLHttpRequest();
    req.open("GET", url);
    try { req.setRequestHeader("User-Agent", UA); } catch (e) {}
    req.onreadystatechange = () => {
      if (req.readyState !== XMLHttpRequest.DONE || settled) return;
      settled = true;
      if (req.status >= 200 && req.status < 300) resolve(req.responseText);
      else reject(req.status === 0 ? "network" : "http");
    };
    try {
      req.send();
    } catch (e) {
      if (!settled) { settled = true; reject("network"); }
    }
  });
}

function httpGetJson(url) {
  return httpGet(url).then((body) => {
    try { return JSON.parse(body); } catch (e) { throw "network"; }
  });
}

// ------------------------------------------------------- wikitext parsing --

// Inner text of the template starting at position 0 of s, or null.
// Brace-aware so nested templates don't truncate the match.
function templateInner(s) {
  if (!s.startsWith("{{")) return null;
  let depth = 0, i = 0;
  while (i < s.length) {
    const two = s.substr(i, 2);
    if (two === "{{") { depth++; i += 2; }
    else if (two === "}}") {
      depth--; i += 2;
      if (depth === 0) return s.slice(2, i - 2);
    } else i++;
  }
  return null;
}

// Split template arguments on "|", ignoring pipes nested in {{ }} or [[ ]]
function splitArgs(inner) {
  const parts = [];
  let cur = "", depth = 0;
  for (let i = 0; i < inner.length;) {
    const two = inner.substr(i, 2);
    const c = inner[i];
    if (two === "{{" || two === "[[") { depth++; cur += two; i += 2; }
    else if (two === "}}" || two === "]]") { depth--; cur += two; i += 2; }
    else if (c === "|" && depth <= 0) { parts.push(cur); cur = ""; i++; }
    else { cur += c; i++; }
  }
  parts.push(cur);
  return parts;
}

function isNamedArg(p) {
  return /^\s*[\w\-\s]+=/.test(p);
}

// Positional (unnamed) arguments of a template, lang code dropped
// EVERY TEMPLATE ON A WIKTIONARY PAGE LEADS WITH ITS LANGUAGE CODE —
// {{lb|en|transitive}}, {{ux|fr|Je fais}}, {{syn|de|machen}} — and it is
// never part of what the template says. This dropped a leading "en" and
// nothing else, which was invisible for as long as English was the only
// section ever read: the moment it was not, "fr" turned up as a label, as
// an example sentence, and in the synonym list.
//
// Matched by SHAPE rather than against a list, because Wiktionary's codes
// are its own — sh for Serbo-Croatian, tl for Tagalog, grc for Ancient
// Greek — and the shape is unmistakable: two or three lowercase letters,
// optionally a dash and a variant. The guard is that something must be
// left afterwards, so a template whose only argument looks like a code
// keeps it rather than coming out empty.
const LANG_ARG = /^[a-z]{2,3}(-[a-z0-9]{2,4})?$/;

function positionalArgs(parts) {
  const pos = [];
  for (let i = 1; i < parts.length; ++i) {
    if (!isNamedArg(parts[i])) pos.push(trim(parts[i]));
  }
  if (pos.length > 1 && LANG_ARG.test(pos[0])) pos.shift();
  return pos;
}

function namedArg(parts, key) {
  for (let i = 1; i < parts.length; ++i) {
    const m = parts[i].match(/^\s*([\w-]+)\s*=(.*)$/);
    if (m && m[1].toLowerCase() === key) return trim(m[2]);
  }
  return null;
}

function templateName(parts) {
  return trim(parts[0] || "").toLowerCase();
}

// Replace a single template with the text it should contribute
function renderTemplate(inner) {
  const parts = splitArgs(inner);
  const name = templateName(parts);
  const pos = positionalArgs(parts);

  // Templates that stand in for a word: show the target, not a trailing gloss
  if (name === "w" || name === "l" || name === "m" || name === "ll"
      || name === "link" || name === "mention" || name === "glossary")
    return pos[0] || "";
  // Non-gloss definitions and glosses: keep the prose
  if (name === "n-g" || name === "ngd" || name === "non-gloss"
      || name === "non-gloss definition" || name === "gloss" || name === "gl")
    return pos[pos.length - 1] || "";
  // Inline qualifiers render parenthesised, as they do on the site
  if (name === "q" || name === "qualifier" || name === "qual" || name === "i")
    return pos.length > 0 ? "(" + pos.join(", ") + ")" : "";
  // Everything else (quotes, references, categories) contributes nothing
  return "";
}

// Reduce wikitext markup to plain prose
function stripWikitext(s) {
  if (!s) return "";

  s = String(s);
  s = s.replace(/<ref[^>]*\/>/g, "");
  s = s.replace(/<ref[^>]*>[\s\S]*?<\/ref>/g, "");

  // Innermost-first so nested templates resolve correctly
  for (let i = 0; i < 8; ++i) {
    const next = s.replace(/\{\{([^{}]*)\}\}/g, (m, inner) => renderTemplate(inner));
    if (next === s) break;
    s = next;
  }
  s = s.replace(/\{\{/g, "").replace(/\}\}/g, "");

  s = s.replace(/\[\[[^\[\]|]*\|([^\[\]|]*)\]\]/g, "$1");
  s = s.replace(/\[\[([^\[\]]*)\]\]/g, "$1");
  s = s.replace(/\[https?:\/\/\S+\s+([^\]]*)\]/g, "$1");
  s = s.replace(/\[https?:\/\/\S+\]/g, "");

  s = s.replace(/'''''/g, "").replace(/'''/g, "").replace(/''/g, "");
  s = s.replace(/<[^>]*>/g, "");

  s = decodeHtml(s);
  s = s.replace(/\s+/g, " ");
  // Tidy space left behind by dropped templates
  s = s.replace(/\s+([,;.!?])/g, "$1");
  s = s.replace(/^[\s,;:]+/, "");
  return trim(s);
}

// Slice out the ==English== section; Wiktionary pages hold many languages
// ── THE SECTION FOR ONE LANGUAGE ──────────────────────────────────────
// A Wiktionary page is every language that spells a word that way, each
// under a level-two heading with its name in ENGLISH — "Spanish", never
// "Español". This read only the English one, which made a dictionary of
// fifty languages into a dictionary of one: look "faire" up and there is
// no English section, so there was no entry, so you got "check spelling".
function languageSection(wikitext, name) {
  const want = trim(String(name || "English")).toLowerCase();
  const out = [];
  let inSection = false;
  for (const line of String(wikitext).split("\n")) {
    const heading = line.match(/^==\s*([^=]+)\s*==\s*$/);
    if (heading) {
      inSection = trim(heading[1]).toLowerCase() === want;
    } else if (inSection) {
      out.push(line);
    }
  }
  return out.join("\n");
}

// Which languages a page actually carries, in the order they appear.
function sectionNames(wikitext) {
  const out = [];
  for (const line of String(wikitext).split("\n")) {
    const heading = line.match(/^==\s*([^=]+)\s*==\s*$/);
    if (heading) {
      const n = trim(heading[1]);
      if (n !== "" && out.indexOf(n) < 0) out.push(n);
    }
  }
  return out;
}

// Pull a leading {{lb|en|...}} off a definition line.
// Returns { label: string|null, rest: string }
function extractLabel(line) {
  const m = line.match(/^\s*(\{\{.*)$/);
  if (!m) return { label: null, rest: line };
  const lead = m[1];
  const inner = templateInner(lead);
  if (!inner) return { label: null, rest: line };

  const parts = splitArgs(inner);
  const name = templateName(parts);
  if (name !== "lb" && name !== "label" && name !== "lbl" && name !== "tlb")
    return { label: null, rest: line };

  const labels = [];
  for (const p of positionalArgs(parts)) {
    // "_", "and", "or" are Wiktionary's label connectors, not labels
    if (p !== "" && p !== "_" && p !== "and" && p !== "or") labels.push(p);
  }

  const rest = lead.slice(inner.length + 4);
  if (labels.length === 0) return { label: null, rest };
  return { label: labels.join(", "), rest };
}

// Classify a recording by filename prefix (En-us-…), falling back to |a=
function audioAccent(file, annotation) {
  const prefix = file ? file.toLowerCase().match(/^en-([a-z]+)-/) : null;
  if (prefix) return prefix[1].toUpperCase();
  if (annotation && annotation !== "") {
    const a = annotation.toLowerCase().replace(/[^a-z]/g, "");
    if (a === "us" || a === "ga" || a === "genam" || a === "america"
        || a === "american" || a === "generalamerican") return "US";
    if (a === "uk" || a === "rp" || a === "british" || a === "britain"
        || a === "england" || a === "receivedpronunciation") return "UK";
    if (a === "au" || a === "aus" || a === "australia"
        || a === "australian") return "AU";
  }
  return null;
}

function accentRank(code) {
  const idx = ACCENT_PREFERENCE.indexOf(code);
  if (idx >= 0) return idx;
  return code ? ACCENT_PREFERENCE.length : ACCENT_PREFERENCE.length + 1;
}

// Parse the English section into a structured entry
// ── WHICH OF THEM ARE WORTH OFFERING ──────────────────────────────────
// A HEADING IS NOT AN ENTRY. Wiktionary gives a level-two section to every
// language that spells the word that way, and plenty of those sections
// hold nothing this parser can render — an inflected form that is one
// {{inflection of}} template, a stub with no definition line at all.
//
// Offering them by heading alone made the list actively wrong. On "faire":
// ten sections, of which English and German parse to nothing and eight
// others parse fine — and the offer list showed exactly English and
// German, because those two were the only ones with a code in EN_NAMES.
// Picking either did nothing and offered the other, forever.
//
// So the test is the parse itself, and a code is not required: what a
// section needs to be read is its NAME, which is what the page is keyed by.
// Irish, Occitan, Old French and Middle English are all readable and none
// of them are translation targets.
function usableSections(wikitext, exclude) {
  const skip = String(exclude || "").toLowerCase();
  const out = [];
  for (const name of sectionNames(wikitext)) {
    if (name.toLowerCase() === skip) continue;
    if (parseEntry(wikitext, name)) out.push(name);
  }
  return out;
}

function parseEntry(wikitext, langName) {
  const section = languageSection(wikitext, langName);
  if (section === "") return null;

  const entry = {
    posOrder: [],
    grouped: {},
    ipa: null,
    audio: null,
    synonyms: [],
  };

  const seenSyn = {};

  function addSynonyms(list) {
    for (const raw of list) {
      // A "Synonyms" bullet holds several {{l|en|…}} in one line, so the
      // stripped result is comma-joined; split it back into terms.
      const stripped = stripWikitext(raw) + ",";
      for (const term of stripped.split(/[,;]/)) {
        const clean = trim(term);
        // Thesaurus cross-links aren't usable synonyms, and "see also …"
        // survives template stripping, so match anywhere in the string
        if (clean !== "" && !clean.includes("Thesaurus:")
            && !seenSyn[clean.toLowerCase()]) {
          seenSyn[clean.toLowerCase()] = true;
          entry.synonyms.push(clean);
        }
      }
    }
  }

  let currentPos = null, defCount = 0, inSynonyms = false, lastDef = null;
  const ipaCandidates = [], audioCandidates = [];

  const lines = section.split("\n");
  for (const line of lines) {
    const heading = line.match(/^(=+)\s*(.*?)\s*=+\s*$/);
    if (heading) {
      const h = heading[2].toLowerCase().replace(/\s*\d+\s*$/, "");
      inSynonyms = h === "synonyms";
      if (POS_HEADINGS[h]) {
        currentPos = h;
        defCount = 0;
        if (!entry.grouped[h]) {
          entry.grouped[h] = [];
          entry.posOrder.push(h);
        }
      } else {
        currentPos = null;
      }
      lastDef = null;
      continue;
    }

    // Pronunciation data can appear anywhere in the section
    const ipaAt = line.search(/\{\{\s*IPA\s*\|/);
    if (ipaAt >= 0) {
      const inner = templateInner(line.slice(ipaAt));
      if (inner) {
        const parts = splitArgs(inner);
        for (const v of positionalArgs(parts)) {
          if (/^[\/\[]/.test(v)) {
            ipaCandidates.push({ text: v, accent: namedArg(parts, "a") });
          }
        }
      }
    }

    const audioAt = line.search(/\{\{\s*[Aa]udio\s*\|/);
    if (audioAt >= 0) {
      const inner = templateInner(line.slice(audioAt));
      if (inner) {
        const parts = splitArgs(inner);
        for (const v of positionalArgs(parts)) {
          const extM = v.match(/\.(\w+)$/);
          if (extM && AUDIO_EXT[extM[1].toLowerCase()]) {
            audioCandidates.push({ file: v, code: audioAccent(v, namedArg(parts, "a")) });
          }
        }
      }
    }

    if (inSynonyms) {
      const bullet = line.match(/^\*+(.*)$/);
      if (bullet && trim(bullet[1]) !== "") addSynonyms(splitArgs(bullet[1]));
    }

    const body = line.match(/^#([^#:*].*)$/);
    if (body && currentPos && defCount < KEEP_DEFS_PER_POS) {
      const { label, rest } = extractLabel(body[1]);
      const text = stripWikitext(rest);
      if (hasAlpha(text)) {
        defCount++;
        lastDef = { def: text, label: label, example: "" };
        entry.grouped[currentPos].push(lastDef);
      }
    } else if (/^#:/.test(line)) {
      const sub = trim((line.match(/^#:\s*(.*)$/) || ["", ""])[1]);
      const inner = templateInner(sub);
      const tname = inner ? templateName(splitArgs(inner)) : null;
      if (tname === "syn" || tname === "synonyms") {
        addSynonyms(positionalArgs(splitArgs(inner)));
      } else if (lastDef && lastDef.example === "") {
        // {{ux|en|…}} and friends, or a bare inline example
        let text = null;
        if (tname === "ux" || tname === "usex" || tname === "uxi" || tname === "ux+") {
          text = stripWikitext(positionalArgs(splitArgs(inner))[0] || "");
        } else if (tname !== "ant" && tname !== "antonyms") {
          text = stripWikitext(sub);
        }
        if (text && hasAlpha(text)) lastDef.example = text;
      }
    }
  }

  // Prefer an IPA matching our top accent, else the first listed
  ipaCandidates.sort((a, b) =>
    accentRank(audioAccent("", a.accent)) - accentRank(audioAccent("", b.accent)));
  if (ipaCandidates[0]) entry.ipa = ipaCandidates[0].text;

  audioCandidates.sort((a, b) => accentRank(a.code) - accentRank(b.code));
  if (audioCandidates[0]) entry.audio = audioCandidates[0];

  while (entry.synonyms.length > KEEP_SYNONYMS) entry.synonyms.pop();

  // An entry with headings but no definitions is not a usable result
  for (const pos of entry.posOrder) {
    if (entry.grouped[pos].length > 0) return entry;
  }
  return null;
}

// ---------------------------------------------------------------- network --

// redirects=1 matters: many idioms are redirects, e.g.
// "cost an arm and a leg" -> "an arm and a leg"
function fetchWikitext(title) {
  const url = WIKT_API + "?action=parse&page=" + encodeURIComponent(title) +
    "&prop=wikitext&format=json&formatversion=2&redirects=1";
  return httpGetJson(url).then(
    (data) => {
      if (!data || data.error || !data.parse || !data.parse.wikitext)
        return { err: "missing" };
      return { wikitext: data.parse.wikitext, title: data.parse.title };
    },
    () => ({ err: "network" })
  );
}

// Wiktionary's own search. Fuzzy enough to absorb real typos:
// "run off the mill" -> "run-of-the-mill", "kick the buckit" -> "kick the bucket".
function suggest(term, limit) {
  limit = limit || 3;
  const url = WIKT_API + "?action=opensearch&search=" +
    encodeURIComponent(term) + "&limit=" + limit + "&format=json";
  return httpGetJson(url).then(
    (data) => {
      // translate.lua read data[2] in 1-indexed Lua — the title array at
      // JS index 1
      const list = Array.isArray(data) && Array.isArray(data[1]) ? data[1] : [];
      return list.slice(0, limit);
    },
    () => []
  );
}

// Resolve a query to an entry. Tries the word as typed, then lowercased
// (page titles are case-sensitive), then Wiktionary's search for typos.
// Resolves to { entry, title, corrected } or rejects with an error kind:
// "network" | "missing".
function resolveWord(word, langName) {
  const tried = new Set();
  // The first page we actually got back, kept for the miss path: which
  // languages it can be read in is only worth working out once the read
  // in the language asked for has failed.
  let firstText = null;

  // Keyed on the exact string: page titles are case-sensitive, so the
  // lowercased retry is a genuinely different fetch, not a duplicate
  function attempt(candidate) {
    if (tried.has(candidate)) return Promise.resolve(null);
    tried.add(candidate);

    return fetchWikitext(candidate).then((res) => {
      if (res.wikitext) {
        if (firstText === null) firstText = res.wikitext;
        const entry = parseEntry(res.wikitext, langName);
        if (entry) {
          const resolved = res.title || candidate;
          return {
            entry: entry,
            title: resolved,
            corrected: resolved.toLowerCase() !== word.toLowerCase(),
          };
        }
      } else if (res.err === "network") {
        throw "network";
      }
      return null;
    });
  }

  const candidates = [word];
  if (word.toLowerCase() !== word) candidates.push(word.toLowerCase());

  let chain = Promise.resolve(null);
  for (const c of candidates) {
    chain = chain.then((found) => found || attempt(c));
  }
  return chain
    .then((found) => {
      if (found) return found;
      return suggest(word, 3).then((suggestions) => {
        let sChain = Promise.resolve(null);
        for (const s of suggestions) {
          sChain = sChain.then((f) => f || attempt(s));
        }
        return sChain;
      });
    })
    .then((found) => {
      if (found) return found;
      // The page exists and simply cannot be read in this language: worth
      // saying, because the fix is to change the language rather than the
      // spelling, and the answer is on the page already.
      if (firstText) {
        const has = usableSections(firstText, langName);
        if (has.length > 0) throw { kind: "lang", has: has };
      }
      throw "missing";
    });
}

// Structured view shaped for the results renderer.
function entryToResult(res) {
  const pos = [];
  for (const name of res.entry.posOrder) {
    const defs = [];
    for (const d of res.entry.grouped[name]) {
      defs.push({
        def: d.def,
        label: d.label || null,
        example: d.example !== "" ? d.example : null,
      });
    }
    if (defs.length > 0) pos.push({ name: name, defs: defs });
  }
  return {
    title: res.title,
    corrected: res.corrected === true,
    ipa: res.entry.ipa || null,
    audio: res.entry.audio
      ? { file: res.entry.audio.file, code: res.entry.audio.code || null }
      : null,
    pos: pos,
    synonyms: res.entry.synonyms.slice(),
  };
}

// ── TAKING SOMETHING OUT OF HERE ──────────────────────────────────────
// The clipboard tool was probed at startup from the day this was written
// and then never used: you could look a word up or translate a paragraph
// and there was no way to carry the answer anywhere. printf '%s', not
// echo, because echo interprets backslashes in some shells and a
// definition is full of them once the wikitext has been through here.
function clipboardScript(cmd, text) {
  if (!cmd || !hasContent(text)) return "";
  return "printf '%s' " + Strings.shellQuote(text) + " | " + cmd;
}

// What a dictionary entry reads as in plain text — the word, then the
// rows as they are on screen, minus the markup that made them italic.
// Blank line between parts of speech, because that is where the eye rests.
function dictPlain(word, rows) {
  const out = [String(word || "")];
  for (const r of rows || []) {
    if (!r || !hasContent(r.text)) continue;
    if (r.kind === "pos") out.push("");
    out.push(stripTags(String(r.text)));
  }
  return out.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

function stripTags(s) {
  return decodeHtml(String(s).replace(/<[^>]*>/g, ""));
}

// ── WHAT IT ALREADY KNOWS ─────────────────────────────────────────────
// Every look-up was a network round trip, including the ones you had
// already done: the history kept the WORD and threw the answer away, so
// "re-look up" from the history view went back to Wiktionary for a
// definition that had not changed since breakfast. With the answer kept,
// a word you have read before comes back in the same frame you ask for
// it, and the history works with the network down.
//
// One JSON object per line, newest first — the same shape the two
// history files already use, so nothing new has to be taught to read it.
// The whole file is rewritten on every write (printf '%s' through the
// shell, like everything else here), which is why the cap is a count
// rather than "everything, forever": 150 entries is a few hundred
// kilobytes of argv at the very worst.
function dictCachePath() { return Paths.cacheDir() + "/dict-cache"; }
function transCachePath() { return Paths.cacheDir() + "/translate-cache"; }

const CACHE_MAX = 120;
// Wiktionary is edited, so an entry is not kept forever — but a month is
// far longer than the span over which you look the same word up twice,
// which is the case this exists for.
const CACHE_TTL = 30 * 24 * 3600;

function nowSec() { return Math.floor(Date.now() / 1000); }

// ── WHICH PARSER WROTE IT ─────────────────────────────────────────────
// A cache entry is not the page, it is what THIS FILE made of the page —
// so a change in here makes every entry written before it wrong, and they
// do not look wrong, they look like the change failing to work. That cost
// an hour once: the language argument was leaking into labels, the fix
// was right, and the panel kept showing "(fr, transitive)" out of the
// cache while the parser it was blaming had already stopped producing it.
//
// Bump this with any change to what parseEntry or entryToResult build.
// Entries stamped with anything else are simply not there.
function parserVersion() { return 2; }

function emptyCache() { return { order: [], map: {} }; }

// The translation cache goes through the same functions; its entries
// carry the stamp too and simply never disagree with it, because nothing
// in here shapes a translation beyond reading it out of the response.
function parseCache(text) {
  const out = emptyCache();
  for (const line of String(text || "").split("\n")) {
    const s = line.trim();
    if (s === "") continue;
    let e;
    try { e = JSON.parse(s); } catch (x) { continue; }
    if (!e || typeof e.k !== "string" || !("v" in e)) continue;
    if (out.map[e.k]) continue;   // the file is newest-first, so first wins
    out.map[e.k] = e;
    out.order.push(e.k);
  }
  return out;
}

function serializeCache(cache) {
  if (!cache || !cache.order) return "";
  const lines = [];
  for (const k of cache.order.slice(0, CACHE_MAX)) {
    const e = cache.map[k];
    if (e) lines.push(JSON.stringify(e));
  }
  return lines.length ? lines.join("\n") + "\n" : "";
}

// Fresh only. The stale case is deliberately a separate question: it is
// worth answering when the network has just failed and worth ignoring
// when it has not.
function cacheGet(cache, key) {
  const e = cache && cache.map ? cache.map[key] : null;
  if (!e || e.p !== parserVersion()) return null;
  if (nowSec() - (e.t || 0) > CACHE_TTL) return null;
  return e.v;
}

function cacheGetStale(cache, key) {
  const e = cache && cache.map ? cache.map[key] : null;
  return e && e.p === parserVersion() ? e.v : null;
}

function cachePut(cache, key, value) {
  const c = cache && cache.map ? cache : emptyCache();
  const at = c.order.indexOf(key);
  if (at >= 0) c.order.splice(at, 1);
  c.order.unshift(key);
  c.map[key] = { k: key, t: nowSec(), p: parserVersion(), v: value };
  if (c.order.length > CACHE_MAX)
    for (const k of c.order.splice(CACHE_MAX)) delete c.map[k];
  return c;
}

// Whether there is anything behind the fold, which is what decides
// if the chord is offered at all.
// Read through a function rather than reaching for the const: a QML
// document can call into this file, and what it can see of the bare
// declarations is not something to bet a layout on.
function showDefs() { return MAX_DEFS_PER_POS; }
function showSynonyms() { return MAX_SYNONYMS; }

function hasMoreThanShown(result) {
  if (!result) return false;
  for (const g of result.pos || [])
    if (g.defs.length > MAX_DEFS_PER_POS) return true;
  return (result.synonyms || []).length > MAX_SYNONYMS;
}

// The language is part of the question: "set" in English and "set" in
// Dutch are two entries on one page, and one cache line cannot be both.
function dictCacheKey(word, lang) {
  // `lang` is a code where there is one and a section name where there is
  // not — Occitan has no entry in EN_NAMES and still needs its own line.
  return String(lang || "en") + "\u001f" + String(word || "").trim().toLowerCase();
}

// The source matters: the same sentence from auto-detect and from an
// explicit "de: " prefix are two different questions.
function transCacheKey(code, source, text) {
  return String(code || "") + "\u001f" + String(source || "auto")
    + "\u001f" + String(text || "");
}
