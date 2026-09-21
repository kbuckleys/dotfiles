// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Tags live in an extended attribute on the file, not in a database — so
// every one of these functions either builds a command that writes to a real
// inode or parses what one wrote back. There is no undo for a setfattr.
//
// That is the argument for the suite: a quoting slip here does not raise an
// error, it runs. And the parsing half has to survive getfattr's own format,
// which C-quotes its values in OCTAL and prints nothing at all for a file
// with no attribute — two behaviours easy to write a parser against by
// assuming rather than by reading.

"use strict";

module.exports = {
  module: "terminus/tags.js",
  cases: (T, t) => {
    // ── the seven ─────────────────────────────────────────────────────────
    // Named for the COLOUR a person means, mapped onto Zenon's own names,
    // which disagree: Zenon's `yellow` is #fab387, which is orange.
    t.eq("there are seven presets", T.PRESETS.length, 7);
    t.eq("orange means Zenon's yellow", T.presetInk("orange"), "yellow");
    t.eq("yellow means Zenon's sand", T.presetInk("yellow"), "sand");
    t.eq("purple means Zenon's magenta", T.presetInk("purple"), "magenta");
    t.eq("a tag of one's own has no preset ink", T.presetInk("work"), "");
    t.eq("and nor does the empty string", T.presetInk(""), "");
    // presetInk returns the NAME of a colour, not a colour. Handing the
    // resolved value to a definition made every renamed preset come out cyan,
    // because tagInk looks the name up again on the way out.
    t.ok("a preset ink is a name, not a #hex",
      T.PRESETS.every((p) => p.ink.charAt(0) !== "#"));

    // ── names ─────────────────────────────────────────────────────────────
    t.eq("a comma separates tags", T.splitTags("red,work"), ["red", "work"]);
    t.eq("and the spaces around one are not part of the name",
      T.splitTags("red, work"), ["red", "work"]);
    t.eq("a stray comma makes no empty tag",
      T.splitTags("red,,work,"), ["red", "work"]);
    t.eq("nothing is no tags", T.splitTags(""), []);
    t.eq("and neither is undefined", T.splitTags(undefined), []);

    // normalise is what makes two files carrying the same set carry the same
    // STRING, which is what lets a plain comparison answer "are these alike".
    t.eq("normalise sorts", T.normalise(["work", "red"]), ["red", "work"]);
    t.eq("normalise dedupes", T.normalise(["red", "red"]), ["red"]);
    t.eq("normalise drops the empties", T.normalise(["red", "", "  "]),
      ["red"]);
    // A comma cannot survive inside a name: it is the separator, so a tag
    // holding one would read back as two.
    t.eq("a comma inside a name becomes a space",
      T.normalise(["a,b"]), ["a b"]);

    t.ok("hasTag finds one", T.hasTag(["red", "work"], "work"));
    t.ok("hasTag is exact", !T.hasTag(["redo"], "red"));
    t.ok("hasTag survives no list", !T.hasTag(undefined, "red"));

    // ── reading what getfattr wrote ───────────────────────────────────────
    const dump = [
      "# file: /home/buck/notes.md",
      'user.xdg.tags="red,work"',
      "",
      "# file: /home/buck/photo.png",
      'user.xdg.tags="green"',
      ""
    ].join("\n");
    t.eq("two stanzas, two files",
      Object.keys(T.parseTagDump(dump)).sort(),
      ["/home/buck/notes.md", "/home/buck/photo.png"]);
    t.eq("and the names come back split",
      T.parseTagDump(dump)["/home/buck/notes.md"], ["red", "work"]);

    // A file with the attribute PRESENT but empty is not a tagged file, and
    // must not enter the index — it would sit there forever as a path with
    // no tags.
    t.eq("an empty value is not an entry",
      T.parseTagDump("# file: /a\nuser.xdg.tags=\"\"\n"), {});
    t.eq("nothing at all parses to nothing", T.parseTagDump(""), {});
    t.eq("and so does undefined", T.parseTagDump(undefined), {});
    // Another attribute in the dump is not ours.
    t.eq("a different attribute is ignored",
      T.parseTagDump("# file: /a\nuser.other=\"red\"\n"), {});

    // getfattr C-quotes the value and writes \NNN in OCTAL, not hex. A parser
    // that assumed hex would turn \040 into an @ rather than a space.
    t.eq("an octal escape decodes", T.unescapeAttr("a\\040b"), "a b");
    t.eq("an escaped quote decodes", T.unescapeAttr('a\\"b'), 'a"b');
    t.eq("an escaped backslash decodes", T.unescapeAttr("a\\\\b"), "a\\b");
    t.eq("something that is not an escape is left alone",
      T.unescapeAttr("a\\zb"), "a\\zb");
    t.eq("a tag with a space survives the round trip",
      T.parseTagDump('# file: /a\nuser.xdg.tags="deep\\040work"\n')["/a"],
      ["deep work"]);

    // ── writing ───────────────────────────────────────────────────────────
    const w = T.writeTagsCommand("/home/buck/a b.txt", ["work", "red"]);
    t.ok("a path with a space is quoted", w.indexOf("'/home/buck/a b.txt'") >= 0);
    t.ok("the value is written sorted", w.indexOf("'red,work'") >= 0);
    t.ok("and it is setfattr -n", w.indexOf("setfattr -n user.xdg.tags") === 0);

    // An empty list REMOVES the attribute. Storing "" would leave a file that
    // reads as tagged to anything doing a presence check — including the -n
    // sweep the index is built from.
    t.ok("no tags means -x, not an empty value",
      T.writeTagsCommand("/a", []).indexOf("setfattr -x") === 0);
    t.ok("and -x swallows its own failure",
      T.writeTagsCommand("/a", []).indexOf("|| true") > 0);
    t.ok("an all-empty list is still -x",
      T.writeTagsCommand("/a", ["", "  "]).indexOf("setfattr -x") === 0);

    t.eq("nothing to write is a command that does nothing",
      T.writeManyCommand([]), "true");
    t.eq("and so is no list at all", T.writeManyCommand(null), "true");
    t.eq("two files are two lines",
      T.writeManyCommand([{ path: "/a", names: ["x"] },
                          { path: "/b", names: ["y"] }]).split("\n").length, 2);

    // ── toggling across a selection ───────────────────────────────────────
    // The case a checkbox cannot say: SOME of them have it. Flipping each
    // individually would leave the set exactly as mixed as it started and
    // look like nothing happened, so a mixed selection is brought into line.
    const idx = { "/a": ["red"], "/b": [] };
    const mixed = T.toggleAcross(idx, ["/a", "/b"], "red");
    t.ok("a mixed selection ADDS", mixed.added);
    t.eq("so both come out carrying it",
      mixed.pairs.map((p) => p.names), [["red"], ["red"]]);

    const all = T.toggleAcross({ "/a": ["red"], "/b": ["red"] },
                               ["/a", "/b"], "red");
    t.ok("only when every one has it does it come off", !all.added);
    t.eq("and then both come out without it",
      all.pairs.map((p) => p.names), [[], []]);

    t.eq("nothing selected is nothing to write",
      T.toggleAcross(idx, [], "red").pairs, []);
    // The OTHER tags on a file are not the toggle's business.
    t.eq("a file's other tags are kept",
      T.toggleAcross({ "/a": ["work", "red"] }, ["/a"], "red").pairs[0].names,
      ["work"]);

    // ── renaming ──────────────────────────────────────────────────────────
    const ix = { "/a": ["red", "work"], "/b": ["work"], "/c": ["blue"] };
    const moved = T.renamePairs(ix, "work", "job");
    t.eq("only the files carrying it are touched",
      moved.map((p) => p.path).sort(), ["/a", "/b"]);
    t.eq("and the new name arrives sorted in",
      moved.find((p) => p.path === "/a").names, ["job", "red"]);

    // MERGING IS THE USEFUL CASE as often as not — "recieve" onto "receive"
    // should end with one tag over the union, not a refusal.
    const merged = T.renamePairs({ "/a": ["a", "b"] }, "a", "b");
    t.eq("renaming onto an existing tag merges rather than duplicating",
      merged[0].names, ["b"]);

    t.eq("renaming to itself is not a change", T.renamePairs(ix, "work", "work"), []);
    t.eq("renaming from nothing is not a change", T.renamePairs(ix, "", "job"), []);
    t.eq("renaming to nothing is not a change", T.renamePairs(ix, "work", ""), []);
    t.eq("renaming to whitespace is not a change",
      T.renamePairs(ix, "work", "   "), []);
    t.eq("a tag nothing carries moves nothing",
      T.renamePairs(ix, "absent", "job"), []);

    // ── the index ─────────────────────────────────────────────────────────
    t.eq("tally counts what the disk says",
      T.tally(ix), { red: 1, work: 2, blue: 1 });
    t.eq("an empty index tallies to nothing", T.tally({}), {});
    t.eq("pathsWith answers sorted", T.pathsWith(ix, "work"), ["/a", "/b"]);
    t.eq("and answers nothing for a tag nothing carries",
      T.pathsWith(ix, "absent"), []);

    // ── the sweep ─────────────────────────────────────────────────────────
    const scan = T.scanTagsCommand("/home/buck/my files");
    t.ok("the root is quoted", scan.indexOf("'/home/buck/my files'") >= 0);
    // -h so a symlink is asked about ITSELF: tagging a link and tagging its
    // target are two different acts.
    t.ok("it does not follow symlinks", scan.indexOf("-Rh") >= 0);
    t.ok("--absolute-names, or the index keys lose their leading slash",
      scan.indexOf("--absolute-names") >= 0);
    // getfattr exits nonzero when NOTHING has the attribute, which is a
    // perfectly good answer and must not read as a failure.
    t.ok("and nothing tagged anywhere is not an error",
      scan.indexOf("|| true") > 0);

    // ── quoting, against the names a real disk holds ──────────────────────
    // Every one of these builds shell text that runs unsandboxed. A name is
    // whatever the filesystem allows, which is everything but / and NUL.
    const evil = "/tmp/we'll $(id) `id`; rm -rf x \"q\" *.txt";
    for (const [name, cmd] of [
      ["scanTagsCommand", T.scanTagsCommand(evil)],
      ["writeTagsCommand", T.writeTagsCommand(evil, ["a"])],
      ["writeTagsCommand -x", T.writeTagsCommand(evil, [])],
      ["writeManyCommand", T.writeManyCommand([{ path: evil, names: ["a"] }])]
    ]) {
      // Inside single quotes nothing expands, so the only way out is a quote
      // that is not doubled back — which is exactly what shellQuote prevents.
      const bare = cmd.replace(/'\\''/g, "").split("'");
      t.ok(name + " leaves no unquoted $( ` or ;",
        bare.filter((_, i) => i % 2 === 0)
            .every((s) => !/[$`;]/.test(s.replace(/\$xf|\$\{/g, ""))));
    }
    // A tag is user text too, and it goes in as a VALUE.
    t.ok("a tag holding a quote is quoted",
      T.writeTagsCommand("/a", ["it's"]).indexOf("'it'\\''s'") >= 0);
  }
};
