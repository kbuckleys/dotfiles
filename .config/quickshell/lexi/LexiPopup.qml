// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "lexi.js" as Lexicon
import "../morpheus"

PanelWindow {
  id: popup

  WlrLayershell.layer: WlrLayer.Overlay

  property bool shown: false
  property bool morphMode: false
  // 0..1, driven by shell.qml, which owns the crossfade schedule: 0 until the
  // pill's own row has finished clearing, then rising to 1 as the pill
  // finishes taking this layer's shape
  property real morphFade: 1
  property real showFactor: 0
  property bool collapsing: false
  // ── NO SCALE WHEN MORPHED, AND THAT IS THE POINT ────────────────────
  // This briefly followed contentFade so the panel would grow as it faded,
  // the way a detached one does. It looked wrong, and the capture showed
  // why: detached, the panel is arriving out of nothing and 0.94 -> 1.0
  // reads as arrival. Morphed, the container is ALREADY THERE — it is the
  // pill — so the same scale is not an entrance, it is the text being
  // stretched horizontally in place. Measured across the morph: the
  // content spread outward over seven frames.
  //
  // So a morph is a straight crossfade inside a shape that is already
  // right, and the scale belongs to the case that has something to scale
  // from.
  readonly property real growth: popup.showFactor
  readonly property real panelX: (popup.collapsing ? 0.985 + 0.015 * popup.growth
                        : 0.94 + 0.06 * popup.growth)
  readonly property real panelY: (popup.collapsing ? 0.82 + 0.18 * popup.growth
                        : 0.90 + 0.10 * popup.growth)
  // Morphed, the handover is timed off the PILL's progress, not this popup's
  // own showFactor: showFactor is OutCubic and front-loaded, so it crossed the
  // threshold ~25ms in and this layer's content faded up on top of a morpheus
  // row that was still 80% opaque.
  // Math.min, not morphFade alone. Handing the pill straight to another
  // layer leaves morphFade pinned at 1 — the pill never un-morphs, so there
  // is nothing to ease it down — and this layer stayed fully opaque until its
  // window simply blinked out. Its own closeAnim is already easing
  // showFactor to 0, so taking the lower of the two fades it out on the way
  // between layers while leaving the normal open schedule untouched.
  readonly property real contentFade: popup.morphMode
    ? Math.min(popup.morphFade, popup.showFactor) : popup.showFactor

  property var statusbar: null

  readonly property color bgColor: Zenon.layerBg
  readonly property color borderColor: Zenon.surfaceBorder
  readonly property color msgColor: Zenon.headBg
  readonly property color msgBorder: Zenon.msgBorder
  readonly property color fgColor: Zenon.white
  readonly property color headColor: Zenon.cyan
  readonly property color keyColor: Zenon.keyInk
  readonly property color dimColor: Zenon.muted
  readonly property color exColor: Zenon.pink
  readonly property color errColor: Zenon.red
  readonly property color selColor: Zenon.selBg

  // appMode: which tool is active · view: screen within the tool
  property string appMode: "dict"
  property string view: "input"

  // dictionary state
  property string dictQuery: ""
  property string query: ""
  property bool dictLoading: false
  property int lookupSeq: 0
  property var dictResult: null
  property string dictError: ""
  property var dictRows: []
  property var dictHist: []

  // translate state
  property bool swapping: false
  property string transText: ""
  property var live: null            // { translation, roman, source } | { error }
  property int liveSeq: 0
  property var targetLang: ({ code: "en", name: "English" })

  // ── WHICH LANGUAGE THE DICTIONARY IS READING ──────────────────────────
  // Wiktionary is fifty dictionaries on one page and this read the English
  // section of it and nothing else, so "faire" and "Haus" and "καλός" were
  // all "check spelling". The picker that chooses a translation target
  // chooses this too — it is the same list, filtered to the languages
  // Wiktionary actually has headings for.
  // `en` is the Wiktionary section name, which is what the parse is keyed
  // by and the only part that is always present: a section can be readable
  // without being a translation target, so Occitan and Old French have a
  // name and no code. `code` is for the cache and the picker.
  property var dictLang: ({ code: "en", name: "English", en: "English" })
  readonly property string dictLangEn:
    popup.dictLang.en || Lexicon.enName(popup.dictLang.code)
  // what keys a cache line: the code where there is one, the name where
  // there is not
  readonly property string dictLangKey:
    popup.dictLang.code || popup.dictLangEn

  // WHAT THE HEADER IS CARRYING BESIDES THE WORD. Named here because the
  // spacers between them have to ask: a Row skips a child that is not
  // visible, spacing and all, but a spacer Item is visible by definition,
  // so the gaps kept standing where the things they separate were not.
  // The row is centred, so every unused gap pushed the word left of centre
  // — most visible on an entry with no pronunciation at all.
  // A MESSAGE RATHER THAN A RESULT. The header stands down for this the
  // same way it does while the look-up is out: a titled strip over one red
  // line is a frame around a sentence that is already whole.
  // THE THING THAT FAILED, kept apart from the sentence about it so it can
  // be drawn as a chip. Quotation marks around a word are a typographic
  // apology for not being able to show where it starts and ends; a chip
  // shows it, and this shell already says "this is one object, quoted from
  // somewhere else" that way everywhere else.
  property string dictErrorWord: ""

  readonly property bool dictMessage:
    popup.dictError !== "" && !popup.dictLoading

  readonly property bool showIpa:
    !popup.dictLoading && !!popup.dictResult && !!popup.dictResult.ipa
  readonly property bool showAudio:
    !popup.dictLoading && !!popup.dictResult && !!popup.dictResult.audio
    && popup.playerCmd !== ""
  readonly property bool showCorrected:
    !popup.dictLoading && !!popup.dictResult && !!popup.dictResult.corrected
  readonly property bool dictIsEnglish: popup.dictLang.code === "en"
  property var transHist: []
  property var usageMap: ({})

  // shared list state
  property var langRows: []
  // what the picker actually shows. `query` is the same free-typing buffer
  // the history view filters with — the picker is another focus-less list,
  // so it gets the same treatment rather than a second input field.
  readonly property var langFiltered: Lexicon.filterLangs(
    popup.pickerFor === "dict" ? popup.dictLangRows : popup.langRows, popup.query)
  // Wiktionary has a heading for most of the translate targets, but not
  // all of them, and a language it cannot read is not worth offering.
  readonly property var dictLangRows: Lexicon.dictLangRows(popup.usageMap)
  property int sel: 0

  // environment probes
  property string playerCmd: ""
  property string clipCmd: ""

  readonly property bool wide: popup.view === "results"

  // ── AS WIDE AS THE LIST IN IT ─────────────────────────────────────────
  // Two of these five views are lists of short strings — the language picker
  // and the history — and both stood in a panel sized for a paragraph. A
  // hundred language names in eight hundred pixels is a column of text down
  // the middle of an empty box.
  //
  // The other three are PROSE, and prose is not fitted this way: wrapped
  // text fills whatever measure it is given, so there is no longest line to
  // shrink to and a comfortable measure is the whole point. They keep their
  // literals.
  //
  // Longest by characters, then MEASURED EXACTLY. The face here is
  // proportional, so counting characters against one advance — which is what
  // folio and artemis do, matching the truncation they already had — would
  // only ever be an estimate. Picking the candidate by length and then
  // asking for that one string's real width costs a single measurement and
  // is not an estimate at all.
  readonly property string pickerLongest: {
    let best = "", n = -1;
    const rows = popup.langFiltered;
    for (let i = 0; i < rows.length; ++i) {
      const t = (rows[i].used ? Lexicon.ICON_STAR + " " : "")
        + rows[i].name + " (" + rows[i].code + ")";
      if (t.length > n) { n = t.length; best = t; }
    }
    return best;
  }
  readonly property string histLongest: {
    let best = "", n = -1;
    const rows = popup.historyModel();
    for (let i = 0; i < rows.length; ++i) {
      const t = String(rows[i]);
      if (t.length > n) { n = t.length; best = t; }
    }
    return best;
  }

  // One instance, switched by view: only one of the two lists is on screen.
  TextMetrics {
    id: rowMetrics
    font.family: Zenon.face
    font.weight: 500
    font.pixelSize: 17
    text: popup.view === "picker" ? popup.pickerLongest : popup.histLongest
  }
  // The line above the body: the picker has no input field, so its title
  // doubles as one and grows with whatever is typed into it, and the
  // dictionary's results are headed by the word they are about. 80 covers
  // the glyph and the spacers that sit either side of both.
  TextMetrics {
    id: titleMetrics
    font.family: Zenon.face
    font.weight: 600
    font.pixelSize: 18
    text: {
      if (popup.view === "picker")
        return popup.query === "" ? "Translate to" : popup.query;
      if (popup.view === "results" && popup.appMode === "dict")
        return popup.dictQuery;
      return "";
    }
  }

  // ── AND THE THREE VIEWS THAT ARE PROSE ────────────────────────────────
  // Wrapped text fills whatever measure it is given, so there is no longest
  // line to shrink to while a paragraph is long — measured unwrapped it runs
  // past the ceiling and the ceiling is what it gets, which is the width
  // these views always had. What it buys is the SHORT case: one word typed
  // into the dictionary, a two-line definition, a phrase being translated.
  // Those used to sit in eight hundred pixels of panel regardless.
  //
  // Same two-step as the lists — longest by characters, then measured — for
  // the same reason: this face is proportional.
  readonly property string proseLongest: {
    if (popup.view === "results" &&
        (popup.dictError !== "" || popup.dictSuggest.length > 0)) {
      // the message, and the widest thing offered under it
      // the sentence, the chip and the air around it — the chip is 16 of
      // padding and the row 8 of spacing, which is about three characters
      const line = popup.dictErrorWord === "" ? popup.dictError
        : popup.dictError + "   " + popup.dictErrorWord;
      let best = line.length > popup.offerLabel.length
        ? line : popup.offerLabel;
      for (const c of popup.dictSuggest)
        if (String(c.text).length > best.length) best = String(c.text);
      return best;
    }
    if (popup.view === "results" && popup.appMode === "dict") {
      let best = "", n = -1;
      const rows = popup.dictRows;
      for (let i = 0; i < rows.length; ++i) {
        const t = String(rows[i].text || "");
        if (t.length > n) { n = t.length; best = t; }
      }
      return best;
    }
    if (popup.view === "input" && popup.appMode === "dict")
      return wordInput.text === "" ? popup.recents.join(" · ") : "";
    if (popup.appMode === "trans") {
      // what is being typed, and what came back for it
      const a = String(tArea.text || "");
      const b = popup.live ? String(popup.live.translation || "") : "";
      return a.length >= b.length ? a : b;
    }
    return "";
  }
  TextMetrics {
    id: proseMetrics
    font.family: Zenon.face
    font.weight: 500
    // THE SIZE IT IS ACTUALLY DRAWN AT. The message state sets its own
    // line two points larger, and a width measured at the body's size
    // would have come out a tenth short — which wraps a sentence that was
    // meant to be one line.
    font.pixelSize: popup.dictMessage ? 19 : 17
    text: popup.proseLongest
  }

  // 60 is what the history delegate already holds back from its own elide,
  // and it leaves the picker's centred rows the same room either side. 84 is
  // the inset the definitions column already keeps, which is wider on
  // purpose — prose read too close to the edge to be a body of text.
  readonly property int hintPad: 24
  // The bar OVERLAYS the right edge of the list rather than sitting beside
  // it, so it is not part of a row's width — it is a strip the panel has to
  // carry in addition, or the end of the longest row is read through it. No
  // circle: whether a list scrolls is decided by how many rows it has.
  readonly property int listBarW: {
    const bar = popup.view === "picker" ? pickBar : histBar;
    return bar.visible ? bar.width : 0;
  }
  readonly property int listWant: Math.ceil(rowMetrics.advanceWidth) + 60
    + popup.listBarW + popup.hintPad * 2
  readonly property int proseWant: {
    // The dictionary's field is a single-line TextInput, so it can be asked
    // what it is actually drawing rather than measured off to one side.
    if (popup.view === "input" && popup.appMode === "dict") {
      // the field, or the line of recents under it, whichever is wider —
      // proseLongest hands the metric whichever of the two is on show
      return Math.max(Math.ceil(wordInput.contentWidth) + 120,
                      Math.ceil(proseMetrics.advanceWidth) + 84);
    }
    return Math.ceil(proseMetrics.advanceWidth) + 84;
  }

  // NO NARROWER THAN ITS OWN FURNITURE: the hint strip along the bottom, and
  // the title above the body where there is one. Any one of the five strips
  // answers for all of them — they all bind popup.hints(), which is already
  // the current view's.
  readonly property int minW:
    Math.ceil(Math.max(hintsProbe.needW, titleMetrics.advanceWidth + 80))
      + popup.hintPad * 2

  readonly property int panelWidth: {
    if (popup.view === "picker" || popup.view === "history")
      return Math.max(popup.minW, Math.min(800, popup.listWant));
    return Math.max(popup.minW,
      Math.min(popup.wide ? 1000 : 800, popup.proseWant));
  }
  readonly property int panelTarget: Zenon.layerWidth(popup.panelWidth)

  // WHAT IS ON SCREEN, which is not the target while the pill is moving.
  // This used to be a plain Behavior on the panel's width, which is a second
  // easing chasing the pill's own — measured as the panel lagging the shape
  // it is painted on. Morphed, the pill's animated width IS the value and
  // the two are locked frame-for-frame; standalone there is no pill to
  // follow, so the ease stays here. Cynosure, folio, artemis and ideo all
  // say this now.
  property real liveWidth: (popup.morphMode && popup.statusbar
      && popup.statusbar.pillWidth > 0)
    ? popup.statusbar.pillWidth : popup.panelTarget
  Behavior on liveWidth {
    enabled: !popup.morphMode
    NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease }
  }
  readonly property int maxBodyH: 520

  // ── THE KEYS, DRAWN AS KEYS ──────────────────────────────────────────
  // They were a run of rich text with the key set in bold and the word after
  // it in grey — which asks the reader to work out where one hint ends and
  // the next begins from weight alone. A chip says "this is a key you press"
  // the way the rest of this desktop says it, and a chip with its word beside
  // it is one object rather than two runs that happen to be adjacent.
  //
  // The recipe is terminus' KeyChip, which is an inline component of that
  // file and so cannot be imported. Two definitions of one small shape, and
  // the alternative was a shared component that nine other popups would then
  // be half-using.
  component KeyCap: Rectangle {
    id: cap
    property string label: ""
    implicitWidth: capText.implicitWidth + 13
    implicitHeight: 19
    radius: 5
    color: Qt.rgba(Zenon.keyInk.r, Zenon.keyInk.g, Zenon.keyInk.b, 0.10)
    border.width: 1
    border.color: Qt.rgba(Zenon.keyInk.r, Zenon.keyInk.g, Zenon.keyInk.b, 0.30)
    visible: cap.label !== ""

    Text {
      id: capText
      anchors.centerIn: parent
      text: cap.label
      color: Zenon.keyInk
      font.family: Zenon.face
      font.pixelSize: 11
    }
  }

  component HintBar: Item {
    id: hintBarRoot
    height: 30
    property var rows: popup.hints()
    // What the strip would LIKE to be, for whoever is sizing the panel it
    // sits in. The chips decide it and not one of them looks at the panel,
    // so reading it back to set that width closes no circle.
    readonly property real needW: hintRowInner.implicitWidth

    // The same strip ideo, zeus and folio stand theirs on. These used to sit
    // inside a header that had its own ground; anchored to the bottom they
    // had none, and a row of keys floating on the panel reads as content.
    Rectangle {
      anchors.fill: parent
      color: Zenon.hintBg

      // And the hairline along its top edge, which is what the other three
      // already draw — the strip is translucent, so without a line the body
      // above it simply gets darker rather than ending.
      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Zenon.msgBorder
      }
    }

    // WHAT JUST HAPPENED, over the top of what you could do next. A copy
    // is silent and instant, which between them mean there is no way to
    // tell it from a chord that did nothing at all — so the strip stops
    // advertising for a moment and reports instead.
    Text {
      anchors.centerIn: parent
      visible: popup.copied
      text: "copied"
      color: popup.headColor
      font.family: Zenon.face
      font.weight: 600
      font.pixelSize: 13
    }

    Row {
      id: hintRowInner
      opacity: popup.copied ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
      anchors.centerIn: parent
      // Tighter between the pairs than the old 22, because a chip already
      // draws its own boundary — the space was doing that job before.
      spacing: 14
      Repeater {
        model: hintBarRoot.rows

        delegate: Row {
          id: hintPair
          required property var modelData
          spacing: 5

          KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            label: hintPair.modelData[0]
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hintPair.modelData[1]
            color: popup.dimColor
            font.family: Zenon.face
            font.pixelSize: 13
          }
        }
      }
    }
  }

  visible: popup.showFactor > 0.01
  color: "transparent"

  anchors { left: true; right: true; top: true; bottom: true }
  focusable: true
  exclusionMode: ExclusionMode.Ignore

  NumberAnimation {
    id: openAnim
    target: popup; property: "showFactor"
    to: 1; duration: Zenon.slow; easing.type: Zenon.ease
  }

  NumberAnimation {
    id: closeAnim
    target: popup; property: "showFactor"
    to: 0; duration: Zenon.slow; easing.type: Zenon.ease
    onFinished: popup.shown = false
  }

  HyprlandFocusGrab {
    id: grab
    windows: [ popup ]
    active: popup.shown
    onCleared: popup.closePopup()
  }

  IpcHandler {
    target: "Lexi"
    function toggle() { popup.toggle(); }

    function translate() { popup.openPopup("trans"); }

    // Open onto a word without typing it — for a script, a menu entry, or
    // anything else that already knows what it wants defined.
    function define(word: string): string {
      const w = String(word || "").trim();
      if (w === "") return "empty";
      popup.openPopup("dict");
      popup.seedLookup(w);
      return "defining " + w;
    }
  }

  // Set once the cache file has been read, which on a cold open is a
  // process away. Until then a look-up would go to the network for a
  // definition already sitting on disk — the one case where waiting is
  // faster than not.
  property bool cachesRead: false
  property string pendingLookup: ""

  // A look-up that arrived before the file did — see seedLookup.
  function cacheReadDone() {
    popup.cachesRead = true;
    if (popup.pendingLookup === "") return;
    const w = popup.pendingLookup;
    popup.pendingLookup = "";
    popup.startLookup(w);
  }

  function seedLookup(word) {
    if (popup.appMode === "trans") {
      tArea.text = word;
      popup.transText = word;
      popup.scheduleLive();
      return;
    }
    wordInput.text = word;
    if (popup.cachesRead) popup.startLookup(word);
    else popup.pendingLookup = word;
  }

  // ------------------------------------------------------------- procs --

  Process {
    id: rDictHist
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.onRead("dicthist", text)
    }
  }

  Process {
    id: rTransHist
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.onRead("transhist", text)
    }
  }

  Process {
    id: rUsage
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.onRead("usage", text)
    }
  }

  Process {
    id: rDictCache
    // The stream is what carries the content; the exit is what guarantees
    // an answer. Both release the pending look-up, whichever arrives.
    onExited: popup.cacheReadDone()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.onRead("dictcache", text)
    }
  }

  Process {
    id: rTransCache
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.onRead("transcache", text)
    }
  }

  Process {
    id: writeProc
    onExited: popup.drainWrite()
  }
  property var writeQueue: []

  Process {
    id: probeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const parts = text.trim().split("\n---\n");
        if (parts.length === 2) {
          popup.playerCmd = parts[0].trim();
          popup.clipCmd = parts[1].trim();
        }
      }
    }
  }

  function readCaches() {
    // THROUGH A SHELL, and swallowing the error. A missing file makes cat
    // exit non-zero, and a look-up seeded from IPC waits on this read
    // before it will go to the network — so a cache that has never been
    // written must still ANSWER, with nothing, rather than not answer.
    rDictCache.command = ["sh", "-c",
      "cat " + Strings.shellQuote(Lexicon.dictCachePath()) + " 2>/dev/null"];
    rDictCache.running = true;
    rTransCache.command = ["sh", "-c",
      "cat " + Strings.shellQuote(Lexicon.transCachePath()) + " 2>/dev/null"];
    rTransCache.running = true;
    rDictHist.command = ["cat", Lexicon.dictHistoryPath()];
    rDictHist.running = true;
    rTransHist.command = ["cat", Lexicon.transHistoryPath()];
    rTransHist.running = true;
    rUsage.command = ["cat", Lexicon.usagePath()];
    rUsage.running = true;
  }

  function onRead(purpose, text) {
    if (purpose === "dicthist") {
      popup.dictHist = Lexicon.parseDictHistory(text);
    } else if (purpose === "transhist") {
      popup.transHist = Lexicon.parseTransHistory(text);
    } else if (purpose === "usage") {
      popup.usageMap = Lexicon.parseUsage(text);
      popup.langRows = Lexicon.rankedLangs(popup.usageMap);
    } else if (purpose === "dictcache") {
      popup.dictCache = Lexicon.parseCache(text);
      popup.cacheReadDone();
    } else if (purpose === "transcache") {
      popup.transCache = Lexicon.parseCache(text);
    }
  }

  // The head of the look-up history, for the line under the empty field.
  // Four: enough to be a reminder, few enough to stay one line on a panel
  // that is now only as wide as what is in it.
  readonly property var recents: popup.dictHist.slice(0, 4)

  // Answers already in hand. See the note in lexi.js — these are read at
  // open like the histories are, so a look-up never waits on a file.
  property var dictCache: Lexicon.emptyCache()
  property var transCache: Lexicon.emptyCache()

  function saveDictCache() {
    popup.writeFile(Lexicon.dictCachePath(),
      Lexicon.serializeCache(popup.dictCache));
  }
  function saveTransCache() {
    popup.writeFile(Lexicon.transCachePath(),
      Lexicon.serializeCache(popup.transCache));
  }

  function writeFile(path, content) {
    popup.writeQueue.push({ path: path, content: content });
    popup.drainWrite();
  }

  function drainWrite() {
    if (popup.writeQueue.length === 0 || writeProc.running) return;
    const job = popup.writeQueue.shift();
    writeProc.command = ["sh", "-c",
      "printf '%s' " + Strings.shellQuote(job.content) + " > " + Strings.shellQuote(job.path)];
    writeProc.running = true;
  }

  function detach(script) {
    if (script) Quickshell.execDetached(["bash", "-c", script]);
  }

  // ── TAKING THE ANSWER WITH YOU ────────────────────────────────────────
  // A tool that fetches something and cannot hand it over is a tool you
  // read out loud to yourself and retype. The clipboard command has been
  // probed at startup since this was written; nothing had ever read it.
  //
  // What copies depends on what is on screen, and it is always the thing
  // you came for: the definition, the translation, the row under the
  // caret. Never the query — you already have that, you typed it.
  property bool copied: false
  Timer { id: copiedFlash; interval: 900; onTriggered: popup.copied = false }

  function copyText(text) {
    if (popup.clipCmd === "" || !Lexicon.hasContent(text)) return false;
    popup.detach(Lexicon.clipboardScript(popup.clipCmd, text));
    popup.copied = true;
    copiedFlash.restart();
    return true;
  }

  function copyPayload() {
    if (popup.view === "results" && popup.appMode === "dict")
      return Lexicon.dictPlain(popup.dictQuery, popup.dictRows);
    if (popup.view === "history") {
      const rows = popup.historyModel();
      return popup.sel >= 0 && popup.sel < rows.length ? String(rows[popup.sel]) : "";
    }
    if (popup.appMode === "trans" && popup.live && !popup.live.error)
      return String(popup.live.translation || "");
    return "";
  }

  function copyCurrent() { return popup.copyText(popup.copyPayload()); }

  function takeOffer(offer) {
    if (!offer) return;
    if (offer.kind === "lang") {
      popup.dictLang = {
        code: offer.code,
        name: offer.code ? Lexicon.sourceName(offer.code) : offer.en,
        en: offer.en,
      };
      popup.startLookup(popup.dictQuery);
      return;
    }
    popup.startLookup(String(offer.text));
  }

  // Whether there is anything to take, which is what decides if the hint
  // is offered at all — a chord advertised over nothing is a lie.
  readonly property bool canCopy:
    popup.clipCmd !== "" && Lexicon.hasContent(popup.copyPayload())

  // ------------------------------------------------------------ open --

  function openPopup(mode) {
    popup.appMode = mode || "dict";
    popup.shown = true;
    popup.collapsing = false;
    popup.view = "input";
    popup.sel = 0;
    popup.stopAudio();

    // fresh session: nothing carried over from the previous run
    popup.dictQuery = "";
    wordInput.text = "";
    popup.dictResult = null;
    popup.dictRows = [];
    popup.dictError = "";
    popup.dictLoading = false;
    popup.lookupSeq++;          // invalidate any in-flight look-up
    popup.cachesRead = false;
    popup.pendingLookup = "";
    liveTimer.stop();
    tArea.text = "";
    popup.transText = "";
    popup.live = null;
    popup.liveSeq++;

    readCaches();

    focusRetry.counter = 0;
    focusRetry.restart();
    closeAnim.stop();
    popup.showFactor = 0;
    openAnim.restart();
    popup.syncFocus();
  }

  function closePopup() {
    popup.stopAudio();
    popup.collapsing = true;
    openAnim.stop();
    closeAnim.restart();
  }

  function toggle() {
    if (popup.shown) popup.closePopup();
    else popup.openPopup();
  }

  function toggleMode() {
    popup.stopAudio();
    popup.appMode = popup.appMode === "dict" ? "trans" : "dict";
    popup.view = "input";
    popup.syncFocus();
  }

  function syncFocus() {
    Qt.callLater(() => {
      if (!popup.shown) return;
      if (popup.view === "input" && popup.appMode === "dict") wordInput.forceActiveFocus();
      else if (popup.view === "input") tArea.forceActiveFocus();
      else bgRoot.forceActiveFocus();
    });
  }

  // --------------------------------------------------------- hints --

  function hints() {
    if (popup.view === "picker")
      return [["type", "filter"], ["return", "pick"],
              ["backspace", "back"], ["esc", "close"]];
    if (popup.view === "history") {
      const h = [
        ["return", popup.appMode === "dict" ? "re-look up" : "re-translate"],
        ["delete", "remove"],
      ];
      if (popup.canCopy) h.push(["alt c", "copy"]);
      h.push(["tab", popup.appMode === "dict" ? "translate" : "dictionary"],
             ["esc", "back"]);
      return h;
    }
    if (popup.view === "results") {
      const h = [];
      if (popup.dictSuggest.length > 0)
        return [["↑ ↓", "choose"], ["return", "look up"],
                ["backspace", "back"], ["esc", "close"]];
      if (!popup.dictIsEnglish) h.push(["shift return", "language"]);
      if (popup.dictResult && popup.dictResult.audio && popup.playerCmd !== "")
        h.push(["space", "play"]);
      if (popup.hasMore) h.push(["alt e", "more"]);
      else if (popup.expanded) h.push(["alt e", "less"]);
      if (popup.canCopy) h.push(["alt c", "copy"]);
      h.push(["tab", "translate"], ["backspace", "back"], ["esc", "close"]);
      return h;
    }
    if (popup.appMode === "dict")
      return [["return", "define / history"], ["shift return", "language"],
              ["esc", "clear · close"], ["tab", "translate"]];
    const h = [["return", "play"], ["shift return", "language"]];
    if (popup.canCopy) h.push(["alt c", "copy"]);
    h.push(["esc", "clear · close"], ["alt s", "swap"], ["tab", "dictionary"]);
    return h;
  }

  // ---------------------------------------------------- dictionary --

  function startLookup(word) {
    popup.dictQuery = word;
    popup.dictError = "";
    popup.dictErrorWord = "";
    popup.dictResult = null;
    popup.dictSuggest = [];
    popup.dictAlso = [];
    popup.expanded = false;
    popup.view = "results";
    popup.syncFocus();

    // A word already read comes back in this frame: no request, and no
    // loading state either, because there is nothing to wait for and a
    // spinner that never spins is a flicker.
    const key = Lexicon.dictCacheKey(word, popup.dictLangKey);
    const hit = Lexicon.cacheGet(popup.dictCache, key);
    if (hit) {
      popup.lookupSeq++;   // anything still in flight is answering an old question
      popup.dictLoading = false;
      popup.showDictResult(hit);
      return;
    }

    popup.dictLoading = true;
    const seq = ++popup.lookupSeq;
    Lexicon.resolveWord(word, popup.dictLangEn).then(
      (res) => popup.onDictResolved(seq, res),
      (err) => popup.onDictFailed(seq, err)
    );
  }

  // Everything that happens once a result exists, however it was come by.
  function showDictResult(result) {
    popup.dictResult = result;
    popup.dictRows = popup.buildDictRows(result);
    if (result.corrected) popup.dictQuery = result.title;

    popup.dictHist = Lexicon.addDictHistory(popup.dictHist, result.title);
    popup.writeFile(Lexicon.dictHistoryPath(),
      Lexicon.serializeDictHistory(popup.dictHist));

    if (result.audio && popup.playerCmd !== "")
      popup.prefetchDictAudio(result.audio.file);
  }

  function onDictResolved(seq, res) {
    if (seq !== popup.lookupSeq || !popup.shown) return;
    popup.dictLoading = false;

    const result = Lexicon.entryToResult(res);

    // Under BOTH names. A typo that Wiktionary's own search rescued —
    // "helo" to "hello" — is the look-up most worth not repeating, and it
    // is the one a title-only key would miss every time.
    const lc = popup.dictLangKey;
    popup.dictCache = Lexicon.cachePut(popup.dictCache,
      Lexicon.dictCacheKey(result.title, lc), result);
    const asked = Lexicon.dictCacheKey(popup.dictQuery, lc);
    if (asked !== "" && asked !== Lexicon.dictCacheKey(result.title, lc))
      popup.dictCache = Lexicon.cachePut(popup.dictCache, asked, result);
    popup.saveDictCache();

    popup.showDictResult(result);

    // Only when it corrected: an exact hit has no runners-up worth the
    // request, and this is one more round trip on a path that just made
    // a guess on your behalf.
    if (result.corrected) {
      const asked = popup.dictQuery;
      const got = String(result.title).toLowerCase();
      Lexicon.suggest(asked, 6).then((list) => {
        if (seq !== popup.lookupSeq || !popup.shown) return;
        const out = [];
        for (const c of list)
          if (String(c).toLowerCase() !== got && out.length < 3) out.push(String(c));
        popup.dictAlso = out;
      });
    }
  }

  // ── WHAT IT NEARLY FOUND ──────────────────────────────────────────────
  // resolveWord already asks Wiktionary's own search when the word as
  // typed is not a page, and tries the top three — so a typo usually
  // rescues itself. When none of the three has an English section you got
  // "Check spelling?" and nothing else, while the search had a list of
  // near misses sitting right there.
  //
  // Eight now rather than three, because the three it already tried are
  // the ones that failed: the useful ones are the five underneath them.
  property var dictSuggest: []

  // THE RUNNERS-UP, when the word you typed was not the word you got.
  // "kick the buckit" resolves to "kick the bucket" and says CORRECTED,
  // which is the right answer nine times in ten — and in the tenth there
  // was no way to see what else the search had offered, or to take it.
  // Not a list with a caret in it: the definition on screen is still the
  // answer, and this is a footnote to it.
  property var dictAlso: []

  // What the offers under an error ARE. Two kinds, one caret: a near-miss
  // word to look up instead, or a language the page does have a section
  // for — because when "faire" misses while reading English, the fix is
  // not a different spelling, it is a different language, and the answer
  // was on the page all along.
  property string offerLabel: "did you mean"

  function onDictFailed(seq, err) {
    if (seq !== popup.lookupSeq || !popup.shown) return;
    popup.dictLoading = false;

    // the page exists, just not in this language
    if (err && typeof err === "object" && err.kind === "lang") {
      // EVERY SECTION THE PAGE CAN BE READ IN, code or no code. Filtering
      // these by codeForEnName is what made the list wrong: it kept only
      // the languages that are translation targets, which on "faire" meant
      // keeping the two that parse to nothing and dropping the eight that
      // work.
      const offers = [];
      for (const name of err.has)
        offers.push({ kind: "lang", code: Lexicon.codeForEnName(name) || "",
                      en: name, text: name });
      popup.offerLabel = "\"" + popup.dictQuery + "\" is not "
        + popup.dictLangEn + ". This page has";
      // EMPTY, not a space. It was a space so the error branch of the
      // height would fire; that branch now measures the column like every
      // other, and the space was rendering as a blank line of 17px text
      // with its padding — forty pixels of nothing above the sentence.
      popup.dictError = offers.length > 0 ? ""
        : "no " + popup.dictLangEn + " entry for";
      popup.dictErrorWord = offers.length > 0 ? "" : popup.dictQuery;
      popup.dictSuggest = offers;
      popup.sel = 0;
      return;
    }

    // A MONTH-OLD DEFINITION BEATS AN ERROR. The cache is only read fresh
    // on the way in, which is right — but once the network has actually
    // failed, an entry too old to trust is still the answer to the
    // question, and the alternative on offer is nothing at all.
    if (err === "network") {
      const stale = Lexicon.cacheGetStale(popup.dictCache,
        Lexicon.dictCacheKey(popup.dictQuery, popup.dictLangKey));
      if (stale) { popup.showDictResult(stale); return; }
    }

    // THE WORD IS THE SUBJECT, and the header that used to carry it is
    // hidden in this state — so the message names it, and is the only
    // thing on the panel. Lower case and no full stop: the same voice the
    // rest of the shell answers in — "no match", "no backgrounds in …".
    popup.dictError = err === "network"
      ? "no answer from Wiktionary — check the connection"
      : "no entry for";
    popup.dictErrorWord = err === "network" ? "" : popup.dictQuery;

    if (err !== "network") {
      popup.offerLabel = "did you mean";
      const asked = popup.dictQuery;
      Lexicon.suggest(asked, 8).then((list) => {
        if (seq !== popup.lookupSeq || !popup.shown) return;
        const out = [];
        for (const c of list)
          if (String(c).toLowerCase() !== String(asked).toLowerCase())
            out.push({ kind: "word", text: String(c) });
        popup.dictSuggest = out;
        popup.sel = 0;
      });
    }
  }

  // Whether the whole entry is on show. Resets with every look-up: it is
  // a thing you ask of one word, not a setting.
  property bool expanded: false
  readonly property bool hasMore:
    !popup.expanded && Lexicon.hasMoreThanShown(popup.dictResult)

  function buildDictRows(res) {
    const rows = [];
    const maxDefs = popup.expanded ? 99 : Lexicon.showDefs();
    const maxSyn = popup.expanded ? 99 : Lexicon.showSynonyms();
    for (const group of res.pos) {
      rows.push({ kind: "pos", text: Strings.escapeHtml(group.name) });
      for (const d of group.defs.slice(0, maxDefs)) {
        const label = d.label ? "(" + d.label + ") " : "";
        const lab = label
          ? "<span style=\"color:" + popup.dimColor + ";font-style:italic;\">" +
            Strings.escapeHtml(label) + "</span>"
          : "";
        rows.push({ kind: "def", text: lab + Strings.escapeHtml(d.def) });
        if (d.example)
          rows.push({ kind: "ex", text: Strings.escapeHtml(d.example) });
      }
    }
    if (res.synonyms && res.synonyms.length > 0) {
      rows.push({ kind: "syn", text: "<b>Synonyms:</b> " +
        Strings.escapeHtml(res.synonyms.slice(0, maxSyn).join(", ")) });
    }
    return rows;
  }

  property string dictAudioPath: "/tmp/qslexicon-dict.audio"

  function prefetchDictAudio(file) {
    const url = Lexicon.WIKT_AUDIO_BASE + encodeURIComponent(file);
    popup.detach("rm -f " + Strings.shellQuote(popup.dictAudioPath) +
      " " + Strings.shellQuote(popup.dictAudioPath + ".part") + " && " +
      "curl -sL --max-time 10 -A " + Strings.shellQuote(Lexicon.UA) + " " +
      Strings.shellQuote(url) + " -o " +
      Strings.shellQuote(popup.dictAudioPath + ".part") + " && mv -f " +
      Strings.shellQuote(popup.dictAudioPath + ".part") + " " +
      Strings.shellQuote(popup.dictAudioPath));
  }

  function playDictAudio() {
    if (popup.playerCmd === "" || !popup.dictResult || !popup.dictResult.audio) return;
    popup.detach(Lexicon.audioPlayScript(popup.dictAudioPath, popup.playerCmd));
  }

  // ------------------------------------------------------ translate --

  Timer {
    id: liveTimer
    interval: 350
    onTriggered: popup.doLive()
  }

  function scheduleLive() {
    if (!popup.shown || popup.appMode !== "trans" || popup.view !== "input") return;
    liveTimer.restart();
  }

  function doLive() {
    const raw = popup.transText.trim();
    if (!Lexicon.hasContent(raw)) {
      popup.live = null;
      return;
    }
    const split = Lexicon.splitSourcePrefix(raw);
    const code = popup.targetLangCode();

    // Typing back over something you just typed — a corrected word, an
    // undo, the same phrase in the other direction after a swap — asks
    // the same question again. It is answered from here.
    const key = Lexicon.transCacheKey(code, split.source, split.text);
    const hit = Lexicon.cacheGet(popup.transCache, key);
    if (hit) { popup.liveSeq++; popup.live = hit; return; }

    const seq = ++popup.liveSeq;
    const rq = Lexicon.translateRequest(split.text, code, split.source);

    let req = new XMLHttpRequest();
    req.open("POST", rq.url);
    req.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    req.onreadystatechange = () => {
      if (req.readyState !== XMLHttpRequest.DONE) return;
      if (seq !== popup.liveSeq) return;
      if (req.status !== 200) {
        popup.live = { error: true };
        return;
      }
      const parsed = Lexicon.parseTranslateResponse(req.responseText);
      if (parsed) {
        popup.transCache = Lexicon.cachePut(popup.transCache, key, parsed);
        popup.saveTransCache();
      }
      popup.live = parsed || { error: true };
    };
    req.send(rq.body);
  }

  function targetLangCode() {
    return popup.targetLang ? popup.targetLang.code : "en";
  }

  // Which tool is waiting on the answer. Empty means the translator, which
  // is the only thing that ever asked before this.
  property string pickerFor: ""

  function openDictPicker() {
    popup.pickerFor = "dict";
    popup.openPicker();
  }

  function openPicker() {
    popup.view = "picker";
    popup.query = "";
    popup.sel = 0;
    popup.followSelection();
    popup.syncFocus();
  }

  // Leaving the picker without picking. Deliberately not goBack(): that
  // clears the input you came from, and the picker is a detour off the
  // translate screen rather than an output screen you are finished with.
  function closePicker() {
    popup.pickerFor = "";
    popup.query = "";
    popup.view = "input";
    popup.sel = 0;
    popup.syncFocus();
  }

  // Return with input: pick a language, then refresh the live output half
  // in that language. No separate results screen — auto-translate is always
  // visible under the input.
  function confirmLanguage() {
    if (popup.langFiltered.length === 0) return;
    const lang = popup.langFiltered[Math.min(popup.sel, popup.langFiltered.length - 1)];
    popup.usageMap[lang.code] = (popup.usageMap[lang.code] || 0) + 1;
    popup.writeFile(Lexicon.usagePath(), Lexicon.serializeUsage(popup.usageMap));
    popup.query = "";

    // The dictionary asked, so the dictionary is what changes: back to the
    // word that was on screen, read in the language just chosen.
    if (popup.pickerFor === "dict") {
      popup.pickerFor = "";
      popup.dictLang = { code: lang.code, name: lang.name,
                         en: Lexicon.enName(lang.code) };
      const word = popup.dictQuery;
      if (Lexicon.hasContent(word)) { popup.startLookup(word); return; }
      popup.view = "input";
      popup.syncFocus();
      return;
    }

    popup.targetLang = { code: lang.code, name: lang.name };
    popup.view = "input";
    popup.syncFocus();

    const raw = popup.transText.trim();
    if (!Lexicon.hasContent(raw)) {
      doLive();
      return;
    }
    const split = Lexicon.splitSourcePrefix(raw);
    doTranslate(split.text, lang.code, split.source);
  }

  function doTranslate(text, code, source) {
    const key = Lexicon.transCacheKey(code, source, text);
    const hit = Lexicon.cacheGet(popup.transCache, key);
    if (hit) {
      popup.liveSeq++;
      popup.live = hit;
      popup.transHist = Lexicon.addTransHistory(
        popup.transHist, code, source, text, hit.translation);
      popup.writeFile(Lexicon.transHistoryPath(),
        Lexicon.serializeTransHistory(popup.transHist));
      return;
    }

    const seq = ++popup.liveSeq;
    const rq = Lexicon.translateRequest(text, code, source);

    let req = new XMLHttpRequest();
    req.open("POST", rq.url);
    req.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    req.onreadystatechange = () => {
      if (req.readyState !== XMLHttpRequest.DONE) return;
      if (seq !== popup.liveSeq) return;
      const parsed = req.status === 200
        ? Lexicon.parseTranslateResponse(req.responseText) : null;
      if (!parsed) {
        // the stale rule again: a translation you have seen before is a
        // better answer to "no connection" than the words "no connection"
        const stale = Lexicon.cacheGetStale(popup.transCache, key);
        popup.live = stale || { error: true };
        return;
      }
      popup.transCache = Lexicon.cachePut(popup.transCache, key, parsed);
      popup.saveTransCache();
      popup.live = parsed;

      popup.transHist = Lexicon.addTransHistory(
        popup.transHist, code, source, text, parsed.translation);
      popup.writeFile(Lexicon.transHistoryPath(),
        Lexicon.serializeTransHistory(popup.transHist));
    };
    req.send(rq.body);
  }

  function retranslateHistory(entry) {
    popup.targetLang = { code: entry.code, name: Lexicon.sourceName(entry.code) };
    popup.transText = entry.text;
    tArea.text = entry.text;
    popup.view = "input";
    popup.syncFocus();
    doTranslate(entry.text, entry.code, entry.source);
  }

  property string activePrefix: ""

  function stopAudio() {
    // Kill only the running playback's own prefix; a broad "qslexicon-"
    // pattern races against freshly spawned scripts and kills them instead.
    if (popup.activePrefix !== "") {
      popup.detach("pkill -f " + Strings.shellQuote(popup.activePrefix) +
        " >/dev/null 2>&1");
    }
    popup.activePrefix = "";
  }

  // Return in translate: speak the live translation; press again to stop.

  // Reverse the language pair, like Google Translate's swap button:
  // english → arabic becomes arabic → english. The textarea takes the
  // translation, the detected source becomes the new target language, and
  // the old input becomes the new live output. Return then speaks whichever
  // side is the current output.
  function toggleSwap() {
    if (!popup.live || popup.live.error ||
        !Lexicon.hasContent(popup.live.translation) || !popup.live.source) {
      return;
    }

    popup.stopAudio();
    popup.swapping = true;

    const newInput = popup.live.translation;
    const newTarget = {
      code: popup.live.source,
      name: Lexicon.sourceName(popup.live.source),
    };
    const newLive = {
      translation: Lexicon.splitSourcePrefix(popup.transText.trim()).text,
      roman: null,
      source: popup.targetLang.code,
    };

    tArea.text = newInput;
    popup.transText = newInput;
    popup.targetLang = newTarget;
    popup.liveSeq++;
    popup.live = newLive;

    popup.usageMap[newTarget.code] = (popup.usageMap[newTarget.code] || 0) + 1;
    popup.writeFile(Lexicon.usagePath(), Lexicon.serializeUsage(popup.usageMap));
    popup.transHist = Lexicon.addTransHistory(
      popup.transHist, newTarget.code, null, newInput, newLive.translation);
    popup.writeFile(Lexicon.transHistoryPath(),
      Lexicon.serializeTransHistory(popup.transHist));

    popup.swapping = false;
  }

  function clearTranslate() {
    popup.stopAudio();
    tArea.text = "";
    popup.transText = "";
    popup.live = null;
  }

  function speakLive() {
    // One press always (re)starts: any playing pipeline is killed first.
    popup.stopAudio();
    const text = popup.live ? popup.live.translation : "";
    const code = popup.targetLang.code;
    if (!Lexicon.hasContent(text) || !code) return;
    if (popup.playerCmd === "") return;
    const prefix = "qslexicon-" + Date.now();
    popup.activePrefix = prefix;
    popup.detach(Lexicon.ttsScript(prefix, text, code, popup.playerCmd));
  }

  // -------------------------------------------------------- history --

  function historyModel() {
    if (popup.view !== "history") {
      // outside history return display strings so histList delegate (text: modelData)
      // never receives a QVariantMap -> QML warnings. Length still reflects
      // underlying history size.
      if (popup.appMode === "dict") return popup.dictHist.slice();
      return popup.transHist.map((e) => Lexicon.transHistoryRow(e));
    }
    const q = (popup.query || "").toLowerCase();
    if (popup.appMode === "dict") {
      if (!q) return popup.dictHist.filter((w) => typeof w === "string");
      return popup.dictHist.filter((w) =>
        typeof w === "string" && w.toLowerCase().indexOf(q) >= 0);
    }
    const rows = popup.transHist.map((e) => Lexicon.transHistoryRow(e));
    if (!q) return rows;
    return rows.filter((s) => s.toLowerCase().indexOf(q) >= 0);
  }

  function deleteSelected() {
    if (popup.view !== "history") return;
    if (popup.appMode === "dict") {
      const filtered = popup.historyModel();
      if (popup.sel >= filtered.length) return;
      const word = filtered[popup.sel];
      popup.dictHist = Lexicon.removeDictHistory(popup.dictHist, word);
      popup.writeFile(Lexicon.dictHistoryPath(),
        Lexicon.serializeDictHistory(popup.dictHist));
    } else {
      const q = (popup.query || "").toLowerCase();
      const filtered = q === ""
        ? popup.transHist.slice()
        : popup.transHist.filter((e) => Lexicon.transHistoryRow(e).toLowerCase().indexOf(q) >= 0);
      if (popup.sel >= filtered.length) return;
      const e = filtered[popup.sel];
      popup.transHist = Lexicon.removeTransHistory(popup.transHist, e.code, e.text);
      popup.writeFile(Lexicon.transHistoryPath(),
        Lexicon.serializeTransHistory(popup.transHist));
    }
    popup.clampSel();
  }

  function activateHistory() {
    if (popup.appMode === "dict") {
      const filtered = popup.historyModel();
      if (popup.sel >= filtered.length) return;
      popup.startLookup(filtered[popup.sel]);
    } else {
      const q = (popup.query || "").toLowerCase();
      const filtered = q === ""
        ? popup.transHist.slice()
        : popup.transHist.filter((e) => Lexicon.transHistoryRow(e).toLowerCase().indexOf(q) >= 0);
      if (popup.sel >= filtered.length) return;
      popup.retranslateHistory(filtered[popup.sel]);
    }
  }

  // How many rows the view on screen is showing. moveSel and clampSel both
  // need it, and they disagreed the moment the picker got a filter of its
  // own: clamping against the history model left the selection past the end
  // of a narrowed language list.
  // Three of the views are a list of rows with a caret in them, and the
  // fourth becomes one when a look-up misses and the near misses come back.
  readonly property bool hasList: popup.view === "picker" ||
    popup.view === "history" ||
    (popup.view === "results" && popup.dictSuggest.length > 0)

  function selLength() {
    if (popup.view === "picker") return popup.langFiltered.length;
    if (popup.view === "results") return popup.dictSuggest.length;
    return popup.historyModel().length;
  }

  function clampSel() {
    const len = popup.selLength();
    if (len === 0) popup.sel = 0;
    else popup.sel = Math.max(0, Math.min(popup.sel, len - 1));
    popup.followSelection();
  }

  function followSelection() {
    Qt.callLater(() => {
      pickerList.positionViewAtIndex(popup.sel, ListView.Contain);
      histList.positionViewAtIndex(popup.sel, ListView.Contain);
    });
  }

  // ----------------------------------------------------------- keys --

  function translateReturnKey(shift) {
    if (shift) popup.openPicker();
    else popup.handleReturn();
  }

  function handleReturn() {
    if (popup.view === "input") {
      if (popup.appMode === "dict") {
        const q = wordInput.text.trim();
        if (q === "") {
          popup.query = "";
          popup.view = "history";
          popup.sel = 0;
          popup.clampSel();
          popup.syncFocus();
        } else {
          popup.startLookup(q);
        }
      } else {
        const t = popup.transText.trim();
        if (!Lexicon.hasContent(t)) {
          popup.query = "";
          popup.view = "history";
          popup.sel = 0;
          popup.clampSel();
          popup.syncFocus();
        } else {
          popup.speakLive();
        }
      }
    } else if (popup.view === "picker") {
      popup.confirmLanguage();
    } else if (popup.view === "history") {
      popup.activateHistory();
    } else if (popup.view === "results" && popup.dictSuggest.length > 0) {
      // a miss turned the results into a list of offers; Return takes the
      // one under the caret rather than leaving for the history
      popup.takeOffer(popup.dictSuggest[popup.sel]);
    } else {
      // dict results: Return opens the look-up history
      popup.stopAudio();
      popup.query = "";
      popup.view = "history";
      popup.sel = 0;
      popup.clampSel();
      popup.syncFocus();
    }
  }

  function goBack() {
    popup.stopAudio();
    // leaving an output screen starts a fresh query
    popup.query = "";
    popup.dictQuery = "";
    wordInput.text = "";
    popup.dictResult = null;
    popup.dictRows = [];
    popup.dictError = "";
    popup.dictLoading = false;
    liveTimer.stop();
    tArea.text = "";
    popup.transText = "";
    popup.live = null;
    popup.view = "input";
    popup.syncFocus();
  }

  function moveSel(delta) {
    const len = popup.selLength();
    if (len === 0) return;
    popup.sel = ((popup.sel + delta) % len + len) % len;
    popup.followSelection();
  }

  // ---------------------------------------------------------- panel --

  MouseArea {
    anchors.fill: parent
    z: 0
    onClicked: popup.closePopup()
  }

  Item {
    id: panel
    width: Math.round(popup.liveWidth)
    height: popup.calcHeight()
    // Zenon.slow is the pill's own height easing in shell.qml. Width eases
    // in liveWidth instead, which knows whether the pill is driving it.
    Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
    // Either edge. A layer opens out of the pill, so it has to be on the
    // same one — anchored to whichever it is and given the same lift, with
    // the unused anchor left undefined so the two can never both apply.
    anchors {
      horizontalCenter: parent.horizontalCenter
      top: Zenon.barTop ? parent.top : undefined
      bottom: Zenon.barTop ? undefined : parent.bottom
      topMargin: Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
      bottomMargin: Zenon.edgeLift(popup.morphMode, popup.screen, popup.statusbar)
    }
    z: 1
    opacity: popup.contentFade
    transform: Scale {
      origin.x: panel.width / 2
      // grows out of the edge the bar is on, which is the edge it came from
      origin.y: Zenon.barTop ? 0 : panel.height
      xScale: popup.panelX
      yScale: popup.panelY
    }

    MouseArea { anchors.fill: parent }

    LayerShadow {
      panel: bgRoot
      cornerRadius: Zenon.pillRadius
      morphed: popup.morphMode
    }

    // ClippingRectangle, not Rectangle + clip: true. Qt's own clip is
    // RECTANGULAR — it clips to the bounding box and knows nothing about the
    // radius — so every square child painted to the panel's edge (the bottom
    // strip most visibly) filled in the rounded corners behind it. This one
    // clips to the rounded shape itself.
    ClippingRectangle {
      id: bgRoot
      anchors.fill: parent
      // Grown by its own border: a ClippingRectangle insets its children by
      // border.width on every side, so the content box came out 2px smaller
      // than the panel and any layout measured against the panel's size fell
      // one row or one column short. This hands the content its full box back.
      anchors.margins: -bgRoot.border.width
      color: popup.bgColor
      radius: Zenon.pillRadius
      topLeftRadius: Zenon.pillRadius
      topRightRadius: Zenon.pillRadius
      bottomLeftRadius: Zenon.pillRadius
      bottomRightRadius: Zenon.pillRadius
      border.color: popup.borderColor
      border.width: 1
      focus: true

      // -------------------------------------------------- dict input --

      Item {
        id: dictInputView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.view === "input" && popup.appMode === "dict" ? 1 : 0
        x: popup.view === "input" && popup.appMode === "dict" ? 0 : -24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        Column {
          anchors.fill: parent

          Item {
            width: parent.width
            height: 38
            Text {
              anchors.top: parent.top
              anchors.topMargin: 14
              anchors.horizontalCenter: parent.horizontalCenter
              text: Lexicon.ICON_HEAD
              color: popup.headColor
              font.family: Zenon.face
              font.pixelSize: 18
            }
          }


          Item {
            width: parent.width
            height: 54

            TextInput {
              id: wordInput
              anchors.fill: parent
              horizontalAlignment: TextInput.AlignHCenter
              onTextChanged: popup.query = text
              verticalAlignment: TextInput.AlignVCenter
              color: popup.headColor
              selectionColor: popup.headColor
              selectedTextColor: "#000000"
              font.family: Zenon.face
              font.weight: 600
              font.pixelSize: 18
              cursorVisible: activeFocus
              cursorDelegate: Item {}
              clip: true
              Keys.forwardTo: bgRoot

              Rectangle {
                id: dictPulse
                anchors.left: parent.left
                anchors.leftMargin: Math.min((parent.width + parent.contentWidth) / 2 + 2,
                                             parent.width - 5)
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 20
                radius: 1
                color: popup.headColor
                opacity: 0.25
                visible: wordInput.activeFocus
                SequentialAnimation on opacity {
                  running: wordInput.activeFocus
                  loops: Animation.Infinite
                  NumberAnimation { to: 1; duration: 550; easing.type: Easing.InOutSine }
                  NumberAnimation { to: 0.25; duration: 550; easing.type: Easing.InOutSine }
                }
              }
            }
          }

          // ── THE LAST FEW, WHERE YOU CAN SEE THEM ──────────────────────
          // The history is one keypress away and has been from the start,
          // and a panel that opens onto a glyph and a caret gives you no
          // reason to believe there is anything behind it. Four words is
          // not the history — it is the evidence that there is one.
          //
          // Only while the field is empty: the moment you type, what you
          // are typing is the subject and these are last week's business.
          Row {
            id: recentRow
            visible: wordInput.text === "" && popup.recents.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Repeater {
              model: popup.recents

              delegate: Row {
                id: recentPair
                required property var modelData
                required property int index
                spacing: 10

                Text {
                  visible: recentPair.index > 0
                  anchors.verticalCenter: parent.verticalCenter
                  text: "·"
                  color: popup.dimColor
                  opacity: 0.5
                  font.family: Zenon.face
                  font.pixelSize: 14
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: recentPair.modelData
                  color: recentMa.containsMouse ? popup.headColor : popup.dimColor
                  font.family: Zenon.face
                  font.weight: 500
                  font.pixelSize: 14
                  Behavior on color {
                    ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                  }

                  MouseArea {
                    id: recentMa
                    anchors.fill: parent
                    anchors.margins: -5
                    hoverEnabled: true
                    onClicked: {
                      wordInput.text = String(recentPair.modelData);
                      popup.startLookup(String(recentPair.modelData));
                    }
                  }
                }
              }
            }
          }
        }

        // ── THE HINTS, ALONG THE BOTTOM ──────────────────────────────
        // They sat directly under the title, between you and the thing you
        // opened this for. A hint is what you read when you do not know what
        // to do next, which is not the first thing on the panel — so it goes
        // where a footer goes, and the body starts at the top where it
        // belongs. Anchored rather than laid out: what is above it is already
        // sized so this 30 is exactly what is left over.
        HintBar {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
        }
      }

      // ------------------------------------------------- trans input --

      Item {
        id: transInputView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.view === "input" && popup.appMode === "trans" ? 1 : 0
        x: popup.view === "input" && popup.appMode === "trans" ? 0 : 24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        Column {
          anchors.fill: parent

          Item {
            width: parent.width
            height: 38
            Text {
              anchors.top: parent.top
              anchors.topMargin: 14
              anchors.horizontalCenter: parent.horizontalCenter
              text: Lexicon.ICON_TRANSLATE
              color: popup.headColor
              font.family: Zenon.face
              font.pixelSize: 18
            }
          }


          Item {
            width: parent.width
            height: popup.tAreaH()

            TextArea {
              id: tArea
              anchors.fill: parent
              anchors.leftMargin: 30
              anchors.rightMargin: 30
              wrapMode: TextArea.Wrap
              color: popup.headColor
              selectionColor: popup.headColor
              selectedTextColor: "#000000"
              placeholderText: "text to translate…"
              placeholderTextColor: popup.dimColor
              font.family: Zenon.face
              font.weight: 600
              font.pixelSize: 18
              background: null
              cursorVisible: activeFocus
              cursorDelegate: Item {}
              clip: true
              Keys.forwardTo: bgRoot

              Rectangle {
                id: transPulse
                x: parent.cursorRectangle.x
                y: parent.cursorRectangle.y
                width: 3
                height: parent.cursorRectangle.height > 0 ? parent.cursorRectangle.height : 18
                radius: 1
                color: popup.headColor
                opacity: 0.25
                visible: tArea.activeFocus
                SequentialAnimation on opacity {
                  running: tArea.activeFocus
                  loops: Animation.Infinite
                  NumberAnimation { to: 1; duration: 550; easing.type: Easing.InOutSine }
                  NumberAnimation { to: 0.25; duration: 550; easing.type: Easing.InOutSine }
                }
              }
              Keys.priority: Keys.BeforeItem
              Keys.onPressed: (event) => {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                  event.accepted = true;
                  popup.translateReturnKey(event.modifiers & Qt.ShiftModifier);
                  return;
                }
                if (event.key === Qt.Key_Backspace &&
                    popup.view === "history" && !tArea.text) {
                  event.accepted = true;
                  popup.goBack();
                }
              }
              Keys.onTabPressed: (event) => {
                event.accepted = true;
                popup.toggleMode();
              }
              onTextChanged: {
                popup.transText = tArea.text;
                if (!popup.swapping) popup.scheduleLive();
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: popup.msgBorder
            visible: liveBlock.visible
          }

          Item {
            id: liveBlock
            width: parent.width
            height: visible ? liveCol.height : 0
            visible: popup.view === "input" && popup.live !== null && popup.appMode === "trans"

            Column {
              id: liveCol
              width: parent.width
              topPadding: 10
              bottomPadding: 20
              spacing: 4

              Text {
                width: parent.width
                visible: popup.live !== null && !popup.live.error
                horizontalAlignment: Text.AlignHCenter
                text: {
                  const det = popup.live && popup.live.source
                    ? Lexicon.sourceName(popup.live.source) : "auto";
                  return det + "  →  " + popup.targetLang.name;
                }
                color: popup.dimColor
                font.family: Zenon.face
                font.weight: 500
                font.pixelSize: 16

                MouseArea {
                  anchors.fill: parent
                  onClicked: popup.toggleSwap()
                }
              }

              Text {
                width: parent.width
                visible: popup.live !== null && popup.live.error === true
                horizontalAlignment: Text.AlignHCenter
                text: popup.live && popup.live.error
                  ? "no translation — check connection" : ""
                color: popup.errColor
                font.family: Zenon.face
                font.weight: 500
                font.pixelSize: 16
              }

              Text {
                width: parent.width
                leftPadding: 30
                rightPadding: 30
                visible: popup.live !== null && !popup.live.error
                text: popup.live && !popup.live.error
                  ? "<b>" + Strings.escapeHtml(popup.live.translation) + "</b>" : ""
                color: popup.fgColor
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.RichText
                font.family: Zenon.face
                font.weight: 500
                font.pixelSize: 17
              }

              Text {
                width: parent.width
                leftPadding: 30
                rightPadding: 30
                visible: popup.live !== null && !popup.live.error &&
                         popup.live.roman
                text: popup.live && popup.live.roman
                  ? "<i>" + Strings.escapeHtml(popup.live.roman) + "</i>" : ""
                color: popup.exColor
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.RichText
                font.family: Zenon.face
                font.weight: 500
                font.pixelSize: 17
              }
            }
          }
        }

        // ── THE HINTS, ALONG THE BOTTOM ──────────────────────────────
        // They sat directly under the title, between you and the thing you
        // opened this for. A hint is what you read when you do not know what
        // to do next, which is not the first thing on the panel — so it goes
        // where a footer goes, and the body starts at the top where it
        // belongs. Anchored rather than laid out: what is above it is already
        // sized so this 30 is exactly what is left over.
        HintBar {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
        }
      }

      // -------------------------------------------------- dict results --

      Item {
        id: dictResView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.view === "results" && popup.appMode === "dict" ? 1 : 0
        x: popup.view === "results" && popup.appMode === "dict" ? 0 : -24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        Column {
          anchors.fill: parent

          Rectangle {
            width: parent.width
            // The hint bar used to stand in here under the title; it is
            // anchored to the bottom of the view now, so the header gives
            // back the 30 it was holding for it and the panel's own height
            // is unchanged.
            //
            // AND IT STANDS DOWN WHILE THE LOOK-UP IS OUT. A titled strip
            // over an empty body is a panel claiming to be a result that
            // has not arrived — the word moves down into the body instead
            // and waits there with the dots, in one container, so what is
            // on screen is one thing happening rather than a finished
            // frame around a hole.
            visible: !popup.dictLoading && !popup.dictMessage
            height: popup.dictLoading || popup.dictMessage ? 0 : 44
            color: popup.msgColor

            Rectangle {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              height: 1
              color: popup.msgBorder
            }

            Column {
              anchors.fill: parent
              topPadding: 8

              Item {
                width: parent.width
                height: 32

                Row {
                  anchors.centerIn: parent
                  spacing: 10

                  Text {
                    text: Lexicon.ICON_HEAD
                    color: popup.headColor
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Zenon.face
                    font.pixelSize: 19
                  }

                  Text {
                    // No trailing "…" while it is out: the dots in the body
                    // below say it, and two things saying it at once made
                    // the word itself twitch as the ellipsis came and went.
                    text: Strings.escapeHtml(popup.dictQuery)
                    color: popup.headColor
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Zenon.face
                    font.weight: 600
                    font.pixelSize: 18
                  }

                  // WHICH DICTIONARY THIS IS, when it is not the one you
                  // would assume. Silent for English, because a label
                  // that is always there stops being read.
                  Text {
                    visible: !popup.dictIsEnglish
                    anchors.verticalCenter: parent.verticalCenter
                    text: popup.dictLangEn
                    color: popup.dimColor
                    font.family: Zenon.face
                    font.weight: 500
                    font.pixelSize: 14
                  }

                  Item {
                    width: 14; height: 1
                    visible: popup.showIpa || popup.showAudio
                  }

                  Text {
                    visible: popup.showIpa
                    text: popup.dictResult ? popup.dictResult.ipa || "" : ""
                    color: popup.headColor
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Zenon.face
                    font.weight: 600
                    font.pixelSize: 18
                  }

                  Text {
                    visible: popup.showAudio
                    text: Lexicon.ICON_AUDIO + " " +
                          (popup.dictResult && popup.dictResult.audio
                            ? popup.dictResult.audio.code || "" : "")
                    color: popup.headColor
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Zenon.face
                    font.weight: 600
                    font.pixelSize: 18

                    MouseArea {
                      anchors.fill: parent
                      onClicked: popup.playDictAudio()
                    }
                  }

                  Item {
                    width: 16; height: 1
                    visible: popup.showCorrected
                  }

                  Text {
                    visible: popup.showCorrected
                    text: Lexicon.ICON_CORRECTED + " CORRECTED"
                    color: popup.dimColor
                    font.italic: true
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Zenon.face
                    font.pixelSize: 15
                  }
                }
              }

            }
          }

          // THE BAR IS A SIBLING OF THE VIEW, never a child of it — inside, it
          // becomes part of the scrolling content: it travels with the rows and
          // its anchors resolve against the content item, which is as tall as
          // the whole list. So the view gets a box of its own to sit in, and
          // the bar sits in it beside it. It hides itself when everything fits.
          Item {
            width: parent.width
            height: popup.dictBodyH()

            Flickable {
              id: dictScroll
              anchors.fill: parent
              // Finder's rubber band and the smooth wheel notch, one rule for
              // the whole shell — see morpheus/Elastic.qml. Inside the view
              // rather than over it: it pins itself to the viewport.
              ElasticScroll { view: dictScroll }
              clip: true
              contentWidth: width
              contentHeight: dictCol.height + 12

              // ── OUT, AND NOT BACK YET ─────────────────────────────
              // The word you asked for, and under it the three dots picasso
              // waits with — see morpheus/Working.qml. The header above is
              // hidden while this shows, so these two ARE the panel: what
              // was asked, and that it has not been answered.
              Column {
                id: waitCol
                visible: popup.dictLoading
                anchors.horizontalCenter: parent.horizontalCenter
                y: 16
                spacing: 12

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: popup.dictQuery
                  color: popup.headColor
                  font.family: Zenon.face
                  font.weight: 600
                  font.pixelSize: 18
                }

                Working {
                  anchors.horizontalCenter: parent.horizontalCenter
                  running: popup.dictLoading
                  ink: popup.headColor
                  dot: 5
                  gap: 7
                }
              }

              Column {
                id: dictCol
                // wider side inset than the translate panes: definitions wrap to
                // several lines, and at 30 the text ran too close to the edge to
                // read as a body of prose
                x: 42
                y: 10
                width: parent.width - 84
                spacing: 3

                Row {
                  visible: popup.dictError !== ""
                  anchors.horizontalCenter: parent.horizontalCenter
                  // Room either side, because with the header gone this is
                  // the panel rather than a line inside one.
                  topPadding: 14
                  bottomPadding: 14
                  spacing: 8

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: popup.dictError
                    color: popup.errColor
                    font.family: Zenon.face
                    font.pixelSize: 19
                  }

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: popup.dictErrorWord !== ""
                    width: badWord.implicitWidth + 16
                    height: badWord.implicitHeight + 6
                    radius: 5
                    color: Qt.rgba(popup.errColor.r, popup.errColor.g,
                                   popup.errColor.b, 0.10)
                    border.width: 1
                    border.color: Qt.rgba(popup.errColor.r, popup.errColor.g,
                                          popup.errColor.b, 0.32)

                    Text {
                      id: badWord
                      anchors.centerIn: parent
                      text: popup.dictErrorWord
                      color: popup.errColor
                      font.family: Zenon.face
                      font.weight: 600
                      font.pixelSize: 19
                    }
                  }
                }

                Text {
                  visible: popup.dictSuggest.length > 0
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  topPadding: 12
                  bottomPadding: 2
                  text: popup.offerLabel
                  color: popup.dimColor
                  font.family: Zenon.face
                  font.weight: 500
                  font.pixelSize: 14
                }

                Repeater {
                  model: popup.dictSuggest

                  delegate: Item {
                    required property var modelData
                    required property int index
                    width: dictCol.width
                    height: popup.dictSuggest.length > 0 ? 30 : 0

                    Rectangle {
                      anchors.fill: parent
                      anchors.leftMargin: -12
                      anchors.rightMargin: -12
                      radius: 5
                      color: index === popup.sel ? popup.selColor : "transparent"
                    }

                    Text {
                      anchors.centerIn: parent
                      text: modelData.text
                      color: popup.fgColor
                      opacity: index === popup.sel ? 1 : 0.85
                      font.family: Zenon.face
                      font.weight: 500
                      font.pixelSize: 17
                    }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: popup.takeOffer(modelData)
                    }
                  }
                }


                Repeater {
                  model: popup.dictRows

                  delegate: Text {
                    required property var modelData
                    required property int index
                    width: dictCol.width
                    topPadding: {
                      if (modelData.kind === "pos") return index === 0 ? 2 : 12;
                      if (modelData.kind === "syn") return 10;
                      return 0;
                    }
                    text: {
                      if (modelData.kind === "pos" || modelData.kind === "ex")
                        return "<i>" + modelData.text + "</i>";
                      return modelData.text;
                    }
                    color: modelData.kind === "pos" ? popup.dimColor :
                           modelData.kind === "ex" ? popup.exColor :
                           modelData.kind === "syn" ? popup.headColor :
                           popup.fgColor
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    textFormat: Text.RichText
                    font.family: Zenon.face
                    font.weight: 500
                    font.pixelSize: 17
                  }
                }

                // THE FOOTNOTE. Last in the column, under the definition,
                // because it is only worth reading once the answer on
                // offer has turned out to be the wrong one.
                Row {
                  id: alsoRow
                  visible: popup.dictAlso.length > 0 && popup.dictError === ""
                  anchors.horizontalCenter: parent.horizontalCenter
                  topPadding: 12
                  bottomPadding: 4
                  spacing: 8

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "or"
                    color: popup.dimColor
                    font.family: Zenon.face
                    font.pixelSize: 14
                  }

                  Repeater {
                    model: popup.dictAlso

                    // A MIDDOT BETWEEN THEM, because the candidates are
                    // idioms as often as words — "kicked the bucket kicks
                    // the bucket" is two of them and reads as one.
                    delegate: Row {
                      id: alsoPair
                      required property var modelData
                      required property int index
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 8

                      Text {
                        visible: alsoPair.index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: "·"
                        color: popup.dimColor
                        opacity: 0.6
                        font.family: Zenon.face
                        font.pixelSize: 14
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: alsoPair.modelData
                        color: alsoMa.containsMouse ? popup.headColor : popup.dimColor
                        font.family: Zenon.face
                        font.weight: 500
                        font.pixelSize: 14
                        Behavior on color {
                          ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
                        }

                        MouseArea {
                          id: alsoMa
                          anchors.fill: parent
                          anchors.margins: -4
                          hoverEnabled: true
                          onClicked: popup.startLookup(String(alsoPair.modelData))
                        }
                      }
                    }
                  }
                }
              }
            }

            Scrollbar {
              id: dictBar
              flick: dictScroll
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
            }
          }
        }

        // ── THE HINTS, ALONG THE BOTTOM ──────────────────────────────
        // They sat directly under the title, between you and the thing you
        // opened this for. A hint is what you read when you do not know what
        // to do next, which is not the first thing on the panel — so it goes
        // where a footer goes, and the body starts at the top where it
        // belongs. Anchored rather than laid out: what is above it is already
        // sized so this 30 is exactly what is left over.
        HintBar {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
        }
      }

      // ------------------------------------------------------- picker --

      Item {
        id: pickerView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.view === "picker" ? 1 : 0
        x: popup.view === "picker" ? 0 : -24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        Column {
          anchors.fill: parent

          Rectangle {
            width: parent.width
            // The hint bar used to stand in here under the title; it is
            // anchored to the bottom of the view now, so the header gives
            // back the 30 it was holding for it and the panel's own height
            // is unchanged.
            height: 42
            color: popup.msgColor

            Rectangle {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              height: 1
              color: popup.msgBorder
            }

            Column {
              anchors.fill: parent
              topPadding: 6

              Item {
                width: parent.width
                height: 32
                Text {
                  anchors.centerIn: parent
                  // the picker has no input field, so the title doubles as
                  // one — without it, typing filters an apparently static list
                  text: popup.query === "" ? "Translate to" : popup.query
                  color: popup.headColor
                  font.family: Zenon.face
                  font.weight: 600
                  font.pixelSize: 18
                }
              }

            }
          }

          // THE BAR IS A SIBLING OF THE VIEW, never a child of it — inside, it
          // becomes part of the scrolling content: it travels with the rows and
          // its anchors resolve against the content item, which is as tall as
          // the whole list. So the view gets a box of its own to sit in, and
          // the bar sits in it beside it. It hides itself when everything fits.
          Item {
            width: parent.width
            height: popup.listBodyH(popup.langFiltered.length)

            ListView {
              id: pickerList
              anchors.fill: parent
              // Finder's rubber band and the smooth wheel notch, one rule for
              // the whole shell — see morpheus/Elastic.qml. Inside the view
              // rather than over it: it pins itself to the viewport.
              ElasticScroll { view: pickerList }
              clip: true
              model: popup.langFiltered
              highlightMoveDuration: 120

              delegate: Item {
                required property var modelData
                required property int index
                width: pickerList.width
                height: 32

                Rectangle {
                  anchors.fill: parent
                  color: index === popup.sel ? popup.selColor : "transparent"
                }

                Text {
                  anchors.centerIn: parent
                  text: (modelData.used ? Lexicon.ICON_STAR + " " : "") +
                        modelData.name + " (" + modelData.code + ")"
                  color: popup.fgColor
                  opacity: index === popup.sel ? 1 : 0.85
                  font.family: Zenon.face
                  font.weight: 500
                  font.pixelSize: 17
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    popup.sel = index;
                    popup.confirmLanguage();
                  }
                }
              }
            }

            Scrollbar {
              id: pickBar
              flick: pickerList
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
            }
          }
        }

        // ── THE HINTS, ALONG THE BOTTOM ──────────────────────────────
        // They sat directly under the title, between you and the thing you
        // opened this for. A hint is what you read when you do not know what
        // to do next, which is not the first thing on the panel — so it goes
        // where a footer goes, and the body starts at the top where it
        // belongs. Anchored rather than laid out: what is above it is already
        // sized so this 30 is exactly what is left over.
        HintBar {
          id: hintsProbe
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
        }
      }

      // ------------------------------------------------------- history --

      Item {
        id: histView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.view === "history" ? 1 : 0
        x: popup.view === "history" ? 0 : 24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        Column {
          anchors.fill: parent

          Rectangle {
            width: parent.width
            // The hint bar used to stand in here under the title; it is
            // anchored to the bottom of the view now, so the header gives
            // back the 30 it was holding for it and the panel's own height
            // is unchanged.
            height: 42
            color: popup.msgColor

            Rectangle {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              height: 1
              color: popup.msgBorder
            }

            Column {
              anchors.fill: parent
              topPadding: 6

              Item {
                width: parent.width
                height: 26
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 4
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: popup.appMode === "dict" ? "Look-up history" : "Translation history"
                  color: popup.headColor
                  font.family: Zenon.face
                  font.weight: 600
                  font.pixelSize: 18
                }
              }

            }
          }

          // THE BAR IS A SIBLING OF THE VIEW, never a child of it — inside, it
          // becomes part of the scrolling content: it travels with the rows and
          // its anchors resolve against the content item, which is as tall as
          // the whole list. So the view gets a box of its own to sit in, and
          // the bar sits in it beside it. It hides itself when everything fits.
          Item {
            width: parent.width
            height: popup.listBodyH(popup.historyModel().length)

            ListView {
              id: histList
              anchors.fill: parent
              // Finder's rubber band and the smooth wheel notch, one rule for
              // the whole shell — see morpheus/Elastic.qml. Inside the view
              // rather than over it: it pins itself to the viewport.
              ElasticScroll { view: histList }
              clip: true
              model: popup.historyModel()
              highlightMoveDuration: 120

              delegate: Item {
                required property var modelData
                required property int index
                width: histList.width
                height: 32

                Rectangle {
                  anchors.fill: parent
                  color: index === popup.sel ? popup.selColor : "transparent"
                }

                Text {
                  anchors.centerIn: parent
                  text: modelData
                  color: popup.fgColor
                  opacity: index === popup.sel ? 1 : 0.85
                  elide: Text.ElideMiddle
                  width: Math.min(implicitWidth + 8, histList.width - 60)
                  font.family: Zenon.face
                  font.weight: 500
                  font.pixelSize: 17
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    popup.sel = index;
                    popup.activateHistory();
                  }
                }
              }
            }

            Scrollbar {
              id: histBar
              flick: histList
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
            }
          }
        }

        // ── THE HINTS, ALONG THE BOTTOM ──────────────────────────────
        // They sat directly under the title, between you and the thing you
        // opened this for. A hint is what you read when you do not know what
        // to do next, which is not the first thing on the panel — so it goes
        // where a footer goes, and the body starts at the top where it
        // belongs. Anchored rather than laid out: what is above it is already
        // sized so this 30 is exactly what is left over.
        HintBar {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
        }
      }



      // ------------------------------------------------------ keys --

    Keys.onEscapePressed: (event) => {
      event.accepted = true;
      if (popup.view === "picker") {
        // backspace is what steps back out of the picker; esc clears the
        // filter and then closes, the same cascade as every other layer
        if (popup.query !== "") popup.query = "";
        else popup.closePopup();
      } else if (popup.view === "history" || popup.view === "results") {
        popup.goBack();
      } else if (popup.view === "input" && popup.appMode === "dict" && wordInput.text !== "") {
        wordInput.text = "";
      } else if (popup.view === "input" && popup.appMode === "trans" && tArea.text !== "") {
        popup.clearTranslate();
      } else {
        popup.closePopup();
      }
    }


    Keys.onPressed: (event) => {
      if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) &&
          !((event.modifiers & Qt.ShiftModifier) &&
            popup.view === "results" && popup.appMode === "trans")) {
        event.accepted = true;
        if (popup.view === "input" && popup.appMode === "dict" &&
            (event.modifiers & Qt.ShiftModifier)) {
          popup.openDictPicker();
        } else if (popup.view === "input" && popup.appMode === "trans") {
          // shift picks the output language, plain speaks it
          if (!Lexicon.hasContent(popup.transText)) {
            popup.query = "";
            popup.view = "history";
            popup.sel = 0;
            popup.clampSel();
            popup.syncFocus();
          } else if (event.modifiers & Qt.ShiftModifier) {
            popup.openPicker();
          } else {
            popup.speakLive();
          }
        } else if (event.modifiers & Qt.ShiftModifier) {
          // shift+return: the language menu, for whichever tool is asking
          if (popup.appMode === "trans") popup.openPicker();
          else popup.openDictPicker();
        } else {
          popup.handleReturn();
        }
      } else if (event.key === Qt.Key_E && (event.modifiers & Qt.AltModifier) &&
                 popup.view === "results" && popup.dictResult) {
        event.accepted = true;
        popup.expanded = !popup.expanded;
        popup.dictRows = popup.buildDictRows(popup.dictResult);
      } else if (event.key === Qt.Key_C && (event.modifiers & Qt.AltModifier)) {
        // alt c, the same chord artemis copies a path with
        event.accepted = true;
        popup.copyCurrent();
      } else if (event.key === Qt.Key_S && (event.modifiers & Qt.AltModifier) &&
          popup.view === "input" && popup.appMode === "trans") {
        event.accepted = true;
        popup.toggleSwap();
      } else if (event.key === Qt.Key_Tab) {
        event.accepted = true;
        popup.toggleMode();
      } else if (event.key === Qt.Key_Space && popup.view === "results" && popup.appMode === "dict") {
        event.accepted = true;
        popup.playDictAudio();
      } else if (event.key === Qt.Key_Backspace &&
                 (popup.view === "results" || popup.view === "history" ||
                  popup.view === "picker")) {
        event.accepted = true;
        if (popup.view !== "results" && popup.query.length > 0) {
          const chars = Array.from(popup.query);
          chars.pop();
          popup.query = chars.join("");
          popup.clampSel();
        } else if (popup.view === "picker") {
          popup.closePicker();
        } else {
          popup.goBack();
        }
      } else if (event.key === Qt.Key_Delete && popup.view === "history") {
        event.accepted = true;
        popup.deleteSelected();
      } else if (event.key === Qt.Key_Up && popup.hasList) {
        event.accepted = true;
        popup.moveSel(-1);
      } else if (event.key === Qt.Key_Down && popup.hasList) {
        event.accepted = true;
        popup.moveSel(1);
      } else if (event.key === Qt.Key_PageUp && popup.hasList) {
        event.accepted = true;
        popup.moveSel(-8);
      } else if (event.key === Qt.Key_PageDown && popup.hasList) {
        event.accepted = true;
        popup.moveSel(8);
      } else if ((popup.view === "history" || popup.view === "picker") &&
                 event.text && event.text.length > 0 &&
                 !(event.modifiers & Qt.ControlModifier) &&
                 !(event.modifiers & Qt.AltModifier) &&
                 !(event.modifiers & Qt.MetaModifier) &&
                 event.key !== Qt.Key_Escape && event.key !== Qt.Key_Return &&
                 event.key !== Qt.Key_Enter && event.key !== Qt.Key_Tab &&
                 event.key !== Qt.Key_Backspace && event.key !== Qt.Key_Delete) {
        event.accepted = true;
        popup.query += event.text;
        popup.clampSel();
      }
    }
  }
  }

  // -------------------------------------------------------- helpers --

  function calcHeight() {
    if (popup.view === "input") {
      if (popup.appMode === "dict")
        return 134 + (wordInput.text === "" && popup.recents.length > 0 ? 26 : 0);
      let h = 36 + 30 + popup.tAreaH();
      if (popup.live !== null) h += liveCol.height + 9;
      return Math.min(h + 30, 500);
    }
    // 74 is the 44 of the header plus the 30 of the hint strip; while the
    // look-up is out the header is not there to pay for.
    if (popup.view === "results")
      return (popup.dictLoading || popup.dictMessage ? 30 : 74)
        + popup.dictBodyH();
    if (popup.view === "picker")
      return 72 + popup.listBodyH(popup.langFiltered.length);
    return 72 + popup.listBodyH(popup.historyModel().length);
  }

  function tAreaH() {
    const lines = Math.max(1, Math.min(tArea.lineCount, 8));
    return lines * 26 + 22;
  }

  function dictBodyH() {
    // The word, the gap and the dots, with the same 16 above and below —
    // this body is the whole panel while the header is down.
    if (popup.dictLoading) return 16 + waitCol.height + 16;
    // THE COLUMN'S OWN HEIGHT, whatever is in it — a definition, an error,
    // a list of offers. The error case used to be 70 plus 34 plus a row
    // height per offer, which counted the message's own padding twice and
    // left a band of empty panel above the line it was reserving for.
    return Math.min(dictCol.height + 22, popup.maxBodyH);
  }

  function listBodyH(count) {
    return count === 0 ? 44 : Math.min(count * 32, 480);
  }

  Timer {
    id: focusRetry
    interval: 60
    repeat: true
    onTriggered: {
      if (!popup.shown) {
        stop();
        return;
      }
      popup.syncFocus();
      if (wordInput.activeFocus || tArea.activeFocus ||
          (popup.view !== "input" && bgRoot.activeFocus)) stop();
      if (focusRetry.counter++ > 12) stop();
    }
    property int counter: 0
  }

  Component.onCompleted: {
    probeProc.command = ["sh", "-c",
      Lexicon.playerProbeCommand() + "; echo ---; " + Lexicon.clipboardProbeCommand()];
    probeProc.running = true;
  }
}
