// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A collection compiles a few dropdowns into an fd invocation, sometimes an
// rg after it, and a filter in memory after that. Everything here is the
// compiler, and a compiler is the thing worth testing: its output is a shell
// command nobody reads before it runs, and a rule that quietly matches
// EVERYTHING looks, on screen, exactly like a rule that works.
//
// The `-t f` default is the reason this file exists. Recents is a date rule
// over home with no kind rule, so the "files by default" line excluded every
// directory from it — and the only symptom was folders missing from a list
// that never claimed to have them.

"use strict";

module.exports = {
  module: "terminus/collections.js",
  cases: (T, t) => {
    const HOME = "/home/buck";
    const fd = (rules, folder, home) =>
      T.fdCommand(Object.assign({ root: "/r" }, folder || {}), rules,
                  home === undefined ? HOME : home);

    // ── the vocabulary the editor and the compiler share ──────────────────
    // Kept in one list precisely so they cannot drift: a kind the editor
    // offers and the compiler has never heard of matches everything.
    t.ok("every KIND offers at least one operator",
      T.KINDS.every((k) => k.ops.length > 0));
    t.ok("every FILE_KIND says how fd should ask",
      T.FILE_KINDS.every((k) => !!k.flag || (k.ext && k.ext.length > 0)));
    t.eq("a folder is -t d", T.kindSpec("folder").flag, "-t d");
    t.eq("a file is -t f", T.kindSpec("file").flag, "-t f");
    t.eq("a kind nobody offers is not a kind", T.kindSpec("sandwich"), null);
    t.eq("and it has no operators either", T.opsFor("sandwich"), []);
    t.eq("a new rule takes its kind's first operator",
      T.newRule("name").op, T.opsFor("name")[0]);
    t.eq("a blank collection starts with one name rule",
      T.blank(7).rules.map((r) => r.kind), ["name"]);
    t.eq("and carries the id it was given", T.blank(7).id, 7);

    // ── size, as fd spells it ─────────────────────────────────────────────
    t.eq("a unit is kept", T.sizeArg("10m"), "10m");
    t.eq("case and spaces do not matter", T.sizeArg(" 10 M "), "10m");
    // A bare number means bytes, which is what a person typing 1000 means.
    t.eq("a bare number is bytes", T.sizeArg("1000"), "1000b");
    // fd takes no fractions, so they are resolved rather than refused for a
    // reason nobody typing "1.5m" would guess.
    t.eq("a fraction becomes whole bytes", T.sizeArg("1.5m"), "1572864b");
    t.eq("a fractional gig too", T.sizeArg("0.5g"), "536870912b");
    t.eq("nonsense asks for nothing", T.sizeArg("big"), "");
    t.eq("and so does nothing", T.sizeArg(""), "");
    t.eq("and so does undefined", T.sizeArg(undefined), "");

    // ── dates ─────────────────────────────────────────────────────────────
    t.eq("a bare number means days", T.dateArg("7"), "7d");
    t.eq("a duration is passed through", T.dateArg("2w"), "2w");
    t.eq("with its spaces closed up", T.dateArg("3 months"), "3months");
    t.eq("an absolute date is taken as it is", T.dateArg("2026-01-02"),
      "2026-01-02");
    t.eq("a half-written date asks for nothing", T.dateArg("2026-1-2"), "");
    t.eq("and nonsense asks for nothing", T.dateArg("soon"), "");

    // ── ~ ─────────────────────────────────────────────────────────────────
    // The shell expands it before a program sees it; fd gets an argv, so an
    // unexpanded tilde matches a directory called "~" that does not exist.
    t.eq("a bare tilde is home", T.expandHome("~", HOME), HOME);
    t.eq("and so is the start of a path", T.expandHome("~/Pictures", HOME),
      HOME + "/Pictures");
    t.eq("a tilde in the middle is part of the name",
      T.expandHome("/a/~/b", HOME), "/a/~/b");
    t.eq("a user tilde is not ours to expand", T.expandHome("~bob/x", HOME),
      "~bob/x");
    t.eq("an absolute path is left alone", T.expandHome("/etc", HOME), "/etc");
    t.eq("and with no home there is nothing to expand",
      T.expandHome("~/x", ""), "~/x");

    // ── the fd invocation ─────────────────────────────────────────────────
    const nameRule = [{ kind: "name", op: "contains", value: "notes" }];

    t.ok("hidden files are searched", fd(nameRule).indexOf("--hidden") >= 0);
    t.ok("and ignore files are not obeyed",
      fd(nameRule).indexOf("--no-ignore") >= 0);
    t.ok("results are NUL separated", fd(nameRule).indexOf("--print0") >= 0);
    t.ok("the root is quoted and last",
      fd(nameRule).indexOf("-- '/r'") > 0);

    // FILES BY DEFAULT: without it a name rule also matches the DIRECTORIES
    // holding the files, and a collection of "invoices" lists the invoices
    // folder beside the invoices.
    t.ok("a name rule alone looks for files", fd(nameRule).indexOf("-t f") >= 0);
    // ...and `anyKind` is how Recents opts out. That default is about NAME
    // rules; a date over home has none, and a folder worked in this morning
    // is as good an answer as a file saved in it.
    t.ok("anyKind opts out of that",
      fd([{ kind: "date", op: "within", value: "7d" }],
         { anyKind: true }).indexOf("-t f") < 0);
    t.ok("but a kind rule settles it either way",
      fd([{ kind: "kind", op: "is", value: "folder" }]).indexOf("-t f") < 0);
    t.ok("and an extension rule counts as one",
      fd([{ kind: "ext", op: "is", value: "png" }]).indexOf("-t f") < 0);

    // ── name operators ────────────────────────────────────────────────────
    t.ok("`is` is anchored, so notes is not notes-old",
      fd([{ kind: "name", op: "is", value: "notes" }])
        .indexOf("'^notes$'") >= 0);
    t.ok("`contains` is not anchored",
      fd(nameRule).indexOf("'notes'") >= 0);
    // A literal must not be read as a pattern: a file called "a.b" is not
    // "a" followed by any character.
    t.ok("a literal dot is escaped",
      fd([{ kind: "name", op: "contains", value: "a.b" }])
        .indexOf("'a\\.b'") >= 0);
    t.ok("`matches` is handed over unescaped",
      fd([{ kind: "name", op: "matches", value: "^a.b$" }])
        .indexOf("'^a.b$'") >= 0);
    // fd reads a missing pattern as the PATH, so "everything" is an explicit
    // dot rather than an omission.
    t.ok("no name rule still passes a pattern",
      fd([{ kind: "kind", op: "is", value: "folder" }]).indexOf("'.'") >= 0);

    // ── extensions ────────────────────────────────────────────────────────
    const exts = fd([{ kind: "ext", op: "is", value: "png, jpg" }]);
    t.ok("a comma separates extensions", exts.indexOf("-e 'png'") >= 0);
    t.ok("and the spaces around one are not part of it",
      exts.indexOf("-e 'jpg'") >= 0);
    t.ok("a leading dot is not part of it either",
      fd([{ kind: "ext", op: "is", value: ".png" }]).indexOf("-e 'png'") >= 0);
    t.ok("nor is a leading star",
      fd([{ kind: "ext", op: "is", value: "*.png" }]).indexOf("-e 'png'") >= 0);
    t.ok("an empty item in the list adds nothing",
      fd([{ kind: "ext", op: "is", value: "png,,," }])
        .split("-e ").length === 2);

    // ── size and date become flags ────────────────────────────────────────
    t.ok("larger is +", fd([{ kind: "size", op: "larger", value: "10m" }])
      .indexOf("--size +10m") >= 0);
    t.ok("smaller is -", fd([{ kind: "size", op: "smaller", value: "10m" }])
      .indexOf("--size -10m") >= 0);
    t.ok("a size fd cannot read adds no flag",
      fd([{ kind: "size", op: "larger", value: "huge" }])
        .indexOf("--size") < 0);
    t.ok("within is --changed-within",
      fd([{ kind: "date", op: "within", value: "7d" }])
        .indexOf("--changed-within '7d'") >= 0);
    t.ok("before is --changed-before",
      fd([{ kind: "date", op: "before", value: "7d" }])
        .indexOf("--changed-before '7d'") >= 0);

    // ── the noise list ────────────────────────────────────────────────────
    // Only for a folder that asks. A collection someone wrote is a question
    // they meant, and dropping half the disk out from under it would make
    // its answers wrong in a way nothing on screen could explain.
    t.ok("an ordinary collection excludes nothing",
      fd(nameRule).indexOf("--exclude") < 0);
    const tidy = fd(nameRule, { tidy: true });
    t.ok("a tidy one excludes the application state",
      tidy.indexOf("--exclude '.cache'") >= 0);
    t.eq("all of it", tidy.split("--exclude ").length - 1, T.NOISE.length);
    t.ok("and the paths with a slash in them are quoted whole",
      tidy.indexOf("--exclude '.local/share'") >= 0);

    // ── stage two ─────────────────────────────────────────────────────────
    const content = [{ kind: "content", op: "text", value: "hello" }];
    t.eq("a content rule is found", T.contentRule(content).value, "hello");
    t.eq("an empty one is not a rule",
      T.contentRule([{ kind: "content", op: "text", value: "  " }]), null);
    t.eq("and neither is no rule at all", T.contentRule([]), null);

    const rg = T.rgStage(content[0]);
    t.ok("text is a fixed string, not a pattern",
      rg.indexOf("--fixed-strings") >= 0);
    t.ok("matches is not", T.rgStage({ op: "matches", value: "a.b" })
      .indexOf("--fixed-strings") < 0);
    t.ok("it reports names, not lines",
      rg.indexOf("--files-with-matches") >= 0);
    // -r, or an empty candidate list makes rg read stdin and hang forever —
    // which is exactly what "nothing matched stage one" would mean.
    t.ok("an empty candidate list runs nothing", rg.indexOf("xargs -0 -r") === 0);
    t.ok("and the pattern is quoted",
      T.rgStage({ op: "text", value: "it's $HOME" })
        .indexOf("'it'\\''s $HOME'") >= 0);

    // ── the whole pipeline ────────────────────────────────────────────────
    // "" when nothing can be asked yet. The caller shows nothing rather than
    // listing the entire disk, which is what an unconstrained fd does.
    t.eq("a collection with no rules asks nothing",
      T.command({ root: "/r", rules: [] }, HOME), "");
    t.eq("and nor does one whose only rule is empty",
      T.command({ root: "/r", rules: [{ kind: "name", op: "is", value: " " }] },
        HOME), "");
    // A tag rule counts as usable with no value, because the tag half is
    // answered from the index rather than by fd.
    t.ok("a tag rule alone is still a question",
      T.command({ root: "/r", rules: [{ kind: "tag", op: "is", value: "" }] },
        HOME) !== "");

    const full = T.command({ root: "~/w", rules: nameRule.concat(content) },
                           HOME);
    t.ok("fd comes first", full.indexOf("fd ") === 0);
    t.ok("rg comes after it", full.indexOf("| xargs -0 -r rg") > 0);
    t.ok("the root's tilde is expanded", full.indexOf("'/home/buck/w'") > 0);
    // A page you look at, not forty thousand rows.
    t.ok("and the whole thing is capped",
      full.indexOf("head -z -n 2000") > 0);
    t.ok("with no content rule there is no rg",
      T.command({ root: "/r", rules: nameRule }, HOME).indexOf("rg") < 0);

    // ── the tag half ──────────────────────────────────────────────────────
    t.ok("a folder asking only about tags needs no process",
      T.tagsOnly({ rules: [{ kind: "tag", op: "is", value: "red" }] }));
    t.ok("one asking anything else does",
      !T.tagsOnly({ rules: [{ kind: "tag", op: "is", value: "red" },
                            { kind: "name", op: "is", value: "a" }] }));
    // An empty rule of another kind is not something to run fd for.
    t.ok("an empty rule of another kind does not count",
      T.tagsOnly({ rules: [{ kind: "tag", op: "is", value: "red" },
                           { kind: "name", op: "is", value: "" }] }));
    t.ok("and a folder with no rules asks nothing of anything",
      !T.tagsOnly({ rules: [] }));

    const index = { "/a": ["red"], "/b": ["red", "work"], "/c": ["work"] };
    t.eq("`is` keeps the ones carrying it",
      T.applyTags({ rules: [{ kind: "tag", op: "is", value: "red" }] },
        ["/a", "/b", "/c"], index), ["/a", "/b"]);
    t.eq("`is not` drops them",
      T.applyTags({ rules: [{ kind: "tag", op: "is not", value: "red" }] },
        ["/a", "/b", "/c"], index), ["/c"]);
    t.eq("two tag rules are both applied",
      T.applyTags({ rules: [{ kind: "tag", op: "is", value: "red" },
                            { kind: "tag", op: "is", value: "work" }] },
        ["/a", "/b", "/c"], index), ["/b"]);
    t.eq("an empty tag rule filters nothing",
      T.applyTags({ rules: [{ kind: "tag", op: "is", value: "" }] },
        ["/a", "/c"], index), ["/a", "/c"]);
    t.eq("a path the index has never seen carries no tags",
      T.applyTags({ rules: [{ kind: "tag", op: "is", value: "red" }] },
        ["/unknown"], index), []);
    t.eq("every path the index knows",
      T.allTagged(index).sort(), ["/a", "/b", "/c"]);
    t.eq("and nothing tagged is nothing", T.allTagged({}), []);

    // ── the sentence ──────────────────────────────────────────────────────
    t.eq("a name rule reads as one",
      T.describe({ rules: nameRule }), "name contains notes");
    t.eq("rules are joined",
      T.describe({ rules: [{ kind: "kind", op: "is", value: "image" },
                           { kind: "size", op: "larger", value: "1m" }] }),
      "image · larger than 1m");
    t.eq("a tag wears a hash",
      T.describe({ rules: [{ kind: "tag", op: "is", value: "red" }] }), "#red");
    t.eq("and a negated one says so",
      T.describe({ rules: [{ kind: "tag", op: "is not", value: "red" }] }),
      "not #red");
    t.eq("extensions read with their dots",
      T.describe({ rules: [{ kind: "ext", op: "is", value: "png, jpg" }] }),
      ".png / .jpg");
    t.eq("an empty rule says nothing",
      T.describe({ rules: [{ kind: "name", op: "is", value: "" }] }), "");
    t.eq("and a folder with no rules says nothing", T.describe({}), "");

    // ── quoting, against the values a person can type ─────────────────────
    // Every one of these ends up in shell text. A name rule is free text and
    // a root is a path, so both are hostile input by default.
    const evil = "we'll $(id) `id`; rm -rf x";
    for (const [label, cmd] of [
      ["a name rule", fd([{ kind: "name", op: "contains", value: evil }])],
      ["a root", fd(nameRule, { root: evil })],
      ["an extension", fd([{ kind: "ext", op: "is", value: evil }])],
      ["a content rule", T.rgStage({ op: "text", value: evil })]
    ]) {
      // Inside single quotes nothing expands; the only way out is a quote
      // that has not been doubled back, which shellQuote prevents.
      const outside = cmd.replace(/'\\''/g, "").split("'")
        .filter((_, i) => i % 2 === 0).join("");
      t.ok(label + " cannot break out of its quotes",
        !/[$`;]/.test(outside));
    }
  }
};
