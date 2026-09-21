// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ORACLE's arithmetic. Every one of these is a rule the settings panel relies
// on being true and cannot check for itself: a slider that quietly stored
// 0.30000000000000004, a file that came back with a string where an int
// belongs, an enum that walked off the end of its own list. None of those
// would throw — they would just make a setting wrong, on disk, permanently.

"use strict";

// the specs these cases work against, shaped exactly like Oracle.specs entries
const INT = { key: "notifMaxVisible", section: "notify", label: "Toasts on screen",
              help: "how many stack above the pill", type: "int",
              min: 1, max: 10, step: 1, fallback: 5 };
const MS = { key: "notifTimeout", section: "notify", label: "Timeout", type: "int",
             min: 0, max: 30000, step: 500, unit: "ms", fallback: 4000 };
const SECS = { key: "idleLockSecs", section: "idle", label: "Lock after", type: "int",
               min: 0, max: 3600, step: 30, unit: "s", fallback: 300 };
const REAL = { key: "motionScale", section: "motion", label: "Animation speed",
               type: "real", min: 0, max: 2.5, step: 0.05, unit: "x", fallback: 1.0 };
const BOOL = { key: "showCpu", section: "bar", label: "CPU meter", type: "bool",
               fallback: true };
const ENUM = { key: "backgroundFit", section: "paper", label: "Fit", type: "enum",
               fallback: "crop",
               options: [ { value: "crop", label: "Crop" },
                          { value: "fit", label: "Fit" },
                          { value: "stretch", label: "Stretch" } ] };
// An OPEN enum: the options are the monitors that happen to be plugged in,
// so a value outside them is a fact about the hardware rather than an error.
const OPEN = { key: "barMonitor", section: "bar", label: "Monitor", type: "enum",
               open: true, optionsFrom: "screens", fallback: "",
               options: [ { value: "", label: "Automatic" },
                          { value: "DP-1", label: "DP-1" },
                          { value: "HDMI-A-1", label: "HDMI-A-1" } ] };

const TEXT = { key: "backgroundDir", section: "paper", label: "Folder", type: "text",
               fallback: "" };
const ACT = { key: "actionResetAll", section: "about", label: "Reset everything",
              type: "action", verb: "Reset all" };
// A READOUT. Holds nothing, is never written, never counts as changed —
// exactly like an action, which is what Ora.stored exists to say once.
const NFO = { key: "infoStatePath", section: "about", label: "Kept in",
              type: "info" };

const SCHEMA = [INT, MS, SECS, REAL, BOOL, ENUM, OPEN, TEXT, ACT, NFO];
const DEFAULTS = {
  notifMaxVisible: 5, notifTimeout: 4000, idleLockSecs: 300,
  motionScale: 1.0, showCpu: true, backgroundFit: "crop",
  backgroundDir: "", barMonitor: ""
};

module.exports = {
  module: "oracle/oracle.js",
  cases: (T, t) => {
    // ── coerce: what a value must BE before it is stored ────────────────
    // The file is hand-editable, so every one of these is a real thing that
    // can arrive at this function.
    t.eq("an int past its maximum lands ON the maximum",
      T.coerce(INT, 99), 10);
    t.eq("and past its minimum, on the minimum", T.coerce(INT, -4), 1);
    t.eq("a float in an int slot is rounded", T.coerce(INT, 3.7), 4);
    t.eq("a numeric string is a number", T.coerce(INT, "7"), 7);
    t.eq("something that is not a number at all falls back",
      T.coerce(INT, "banana"), 5);
    t.eq("and so does nothing", T.coerce(INT, undefined), 5);

    t.eq("a bool is true only for the things that mean true",
      T.coerce(BOOL, "true"), true);
    t.eq("'false' is not true", T.coerce(BOOL, "false"), false);
    t.eq("nor is 0", T.coerce(BOOL, 0), false);
    t.eq("1 is", T.coerce(BOOL, 1), true);

    t.eq("an enum keeps a value that is in its list",
      T.coerce(ENUM, "stretch"), "stretch");
    t.eq("and refuses one that is not", T.coerce(ENUM, "wobble"), "crop");

    // An OPEN enum keeps anything. Its list is the monitors currently
    // plugged in, so a name that is not among them is an unplugged monitor —
    // and erasing the setting on undock, then putting the bar somewhere else
    // on redock, is the bug this flag exists to prevent.
    t.eq("an open enum keeps a value from its list",
      T.coerce(OPEN, "DP-1"), "DP-1");
    t.eq("and keeps one that is NOT in its list",
      T.coerce(OPEN, "DP-9"), "DP-9");
    t.eq("empty stays empty, which is its automatic",
      T.coerce(OPEN, ""), "");
    // It still walks its own list, starting from the beginning when the
    // current value is not in it.
    t.eq("nudging an open enum walks the options",
      T.nudge(OPEN, "", 1), "DP-1");
    t.eq("and from an unplugged name it starts at the first",
      T.nudge(OPEN, "DP-9", 1), "");
    // Display falls back to the raw value, so an unplugged monitor still
    // says which one it is rather than showing the first option's label.
    t.eq("an unknown value displays as itself",
      T.display(OPEN, "DP-9"), "DP-9");
    t.eq("a known one displays its label",
      T.display(OPEN, ""), "Automatic");

    t.eq("text is text", T.coerce(TEXT, "/srv/walls"), "/srv/walls");
    t.eq("and null is the empty string, not the word null",
      T.coerce(TEXT, null), "");

    // ── quantize: the reason a slider does not store 0.30000000000000004 ──
    t.eq("a real lands on its own step",
      T.coerce(REAL, 0.333), 0.35);
    t.eq("and carries no more decimals than the step has",
      String(T.coerce(REAL, 1.0 + 0.05 * 3)), "1.15");
    t.eq("a step of 500 snaps a timeout to it", T.coerce(MS, 4321), 4500);
    t.eq("a step of 30 snaps seconds to it", T.coerce(SECS, 301), 300);
    // The step is measured FROM the minimum, not from zero. A spec whose min
    // is not a multiple of its step would otherwise be unable to reach its own
    // minimum, which is the one value a slider must always be able to hit.
    t.eq("the minimum is always reachable", T.coerce(SECS, 0), 0);
    t.eq("and so is the maximum", T.coerce(SECS, 3600), 3600);

    // ── nudge: one press of left or right ───────────────────────────────
    t.eq("right steps up", T.nudge(INT, 5, 1), 6);
    t.eq("left steps down", T.nudge(INT, 5, -1), 4);
    t.eq("a number CLAMPS at its end, it does not wrap",
      T.nudge(INT, 10, 1), 10);
    t.eq("at the other end too", T.nudge(INT, 1, -1), 1);
    t.eq("a bool inverts whichever way you press",
      T.nudge(BOOL, true, 1), false);
    t.eq("and the other way", T.nudge(BOOL, true, -1), false);
    // An enum WRAPS where a number clamps: a ring of three has no far end
    // worth being stuck against.
    t.eq("an enum wraps forwards", T.nudge(ENUM, "stretch", 1), "crop");
    t.eq("and backwards", T.nudge(ENUM, "crop", -1), "stretch");
    t.eq("a value not in the ring steps to its start, not past it",
      T.nudge(ENUM, "wobble", 1), "crop");
    t.eq("whichever way it is pressed",
      T.nudge(ENUM, "wobble", -1), "crop");
    t.eq("text is not nudgeable", T.nudge(TEXT, "/a", 1), "/a");

    // ── the slider's geometry ───────────────────────────────────────────
    t.eq("a value at the minimum is at the left end",
      T.fraction(INT, 1), 0);
    t.eq("and at the maximum, the right", T.fraction(INT, 10), 1);
    t.eq("the middle is the middle", T.fraction(MS, 15000), 0.5);
    t.eq("dragging to the far left gives the minimum",
      T.fromFraction(INT, 0), 1);
    t.eq("dragging past it still gives the minimum",
      T.fromFraction(INT, -3), 1);
    t.eq("and past the right end, the maximum",
      T.fromFraction(INT, 4), 10);
    // fromFraction goes through coerce, so a drag can only ever land on a
    // storable value — this is what stops a drag writing 7.4 toasts.
    t.eq("a drag lands on a step", T.fromFraction(MS, 0.1234), 3500);

    // ── display: what is printed beside the slider ──────────────────────
    // A duration is the one thing nobody reads in milliseconds.
    t.eq("milliseconds read as seconds", T.display(MS, 4000), "4s");
    t.eq("a timeout of zero is 'never', not '0s'", T.display(MS, 0), "never");
    t.eq("seconds under a minute stay seconds", T.display(SECS, 45), "45s");
    t.eq("and over one become minutes", T.display(SECS, 300), "5m");
    t.eq("and over an hour, hours", T.display(SECS, 3600), "1h");
    t.eq("a half hour is not rounded away",
      T.display({ type: "int", unit: "s" }, 5400), "1.5h");
    t.eq("a multiplier says so", T.display(REAL, 1.25), "1.25×");
    t.eq("a bool reads as on or off", T.display(BOOL, false), "off");
    t.eq("an enum shows its LABEL, not its value",
      T.display(ENUM, "crop"), "Crop");
    t.eq("empty text is an em-dash rather than nothing at all",
      T.display(TEXT, ""), "—");
    t.eq("a plain count has no unit", T.display(INT, 5), "5");

    // ── the filter ──────────────────────────────────────────────────────
    t.ok("an empty query matches everything", T.matches(INT, ""));
    t.ok("a label word matches", T.matches(INT, "toasts"));
    t.ok("case does not matter", T.matches(INT, "TOASTS"));
    t.ok("a word from the help text matches", T.matches(INT, "pill"));
    // The key is searchable because the key is what appears in the JSON file,
    // so it is what someone who has been editing that file will type.
    t.ok("so does the key", T.matches(INT, "notifmaxvisible"));
    t.ok("every word has to land somewhere",
      T.matches(INT, "toasts screen"));
    t.ok("in any order", T.matches(INT, "screen toasts"));
    t.ok("but all of them have to",
      !T.matches(INT, "toasts wallpaper"));

    // `alias` carries the words someone types that the prose has no reason to
    // contain. "Bar opacity" IS the pill's transparency control, and a
    // substring filter will not get there from "transparent" in the help —
    // "transparency" is the longer word, so it is not a substring of it.
    const ALIASED = { key: "barOpacity", section: "look", type: "real",
      alias: "transparency see-through morpheus",
      label: "Bar opacity", help: "Alpha over black." };
    t.ok("an alias word finds a setting the prose never names",
      T.matches(ALIASED, "transparency"));
    t.ok("and so does another one", T.matches(ALIASED, "morpheus"));
    t.ok("aliases mix with real words",
      T.matches(ALIASED, "morpheus opacity"));
    t.ok("a setting without aliases is unaffected",
      T.matches(INT, "toasts") && !T.matches(INT, "transparency"));

    // A query searches the WHOLE panel: not knowing which section a setting
    // is filed under is exactly why you are typing.
    t.eq("standing in a section shows only that section",
      T.filterSchema(SCHEMA, "notify", "").length, 2);
    t.eq("and the bar section has its two",
      T.filterSchema(SCHEMA, "bar", "").length, 2);
    t.eq("a query reaches past it",
      T.filterSchema(SCHEMA, "notify", "background").length, 2);
    t.eq("and finds nothing when there is nothing",
      T.filterSchema(SCHEMA, "notify", "zzqq").length, 0);

    // ── the file ────────────────────────────────────────────────────────
    // Only what has been CHANGED is written. A file holding every default
    // would pin an install to the day it was first opened and never see a
    // default improved afterwards.
    const stock = Object.assign({}, DEFAULTS);
    t.eq("an untouched shell writes an empty object",
      T.serialize(SCHEMA, stock, DEFAULTS).trim(), "{}");

    const moved = Object.assign({}, DEFAULTS, { notifMaxVisible: 3, showCpu: false });
    const written = JSON.parse(T.serialize(SCHEMA, moved, DEFAULTS));
    t.eq("only the changed keys are written",
      Object.keys(written).sort().join(","), "notifMaxVisible,showCpu");
    t.eq("with their values", written.notifMaxVisible, 3);
    t.ok("and actions are never written", !("actionResetAll" in written));
    t.ok("nor are readouts", !("infoStatePath" in written));

    // ── parse ───────────────────────────────────────────────────────────
    t.eq("a value comes back", T.parse(SCHEMA, '{"notifMaxVisible":3}').notifMaxVisible, 3);
    t.eq("out of range, it comes back clamped",
      T.parse(SCHEMA, '{"notifMaxVisible":9000}').notifMaxVisible, 10);
    t.eq("a key nothing knows about is dropped",
      Object.keys(T.parse(SCHEMA, '{"whoIsThis":1}')).length, 0);
    // Bad settings are worth less than a working shell. This is the same rule
    // terminus applies to its own view preferences.
    t.eq("a half-written file is not an exception, it is an empty answer",
      Object.keys(T.parse(SCHEMA, '{"notifMaxVisible":')).length, 0);
    t.eq("and so is a file holding something that is not an object",
      Object.keys(T.parse(SCHEMA, '[1,2,3]')).length, 0);
    t.eq("an empty file is simply no settings",
      Object.keys(T.parse(SCHEMA, "")).length, 0);

    // A round trip has to be exact, or a setting would drift a step every
    // time the shell restarted.
    const trip = T.parse(SCHEMA, T.serialize(SCHEMA, moved, DEFAULTS));
    t.eq("what was written is what comes back", trip.notifMaxVisible, 3);
    t.eq("including the falses", trip.showCpu, false);

    // ── the sidebar's counts ────────────────────────────────────────────
    t.eq("nothing changed is nothing to say",
      T.changedIn(SCHEMA, stock, DEFAULTS, ""), 0);
    t.eq("two changed, across two sections",
      T.changedIn(SCHEMA, moved, DEFAULTS, ""), 2);
    t.eq("one of them in notify",
      T.changedIn(SCHEMA, moved, DEFAULTS, "notify"), 1);
    t.eq("one in bar", T.changedIn(SCHEMA, moved, DEFAULTS, "bar"), 1);
    t.eq("and none in paper", T.changedIn(SCHEMA, moved, DEFAULTS, "paper"), 0);

    // ── stored() ────────────────────────────────────────────────────────
    // The one predicate every pass over the schema asks. Getting it wrong in
    // either direction is silent: a setting that stops being saved, or a
    // button that gets written to the file as though it held something.
    t.ok("a number holds a value", T.stored(INT));
    t.ok("so does text", T.stored(TEXT));
    t.ok("so does a bool", T.stored(BOOL));
    t.ok("an action does not", !T.stored(ACT));
    t.ok("and neither does a readout", !T.stored(NFO));

    // A readout must not be parsed back in either, however it got into the
    // file — a hand-edited file can name anything.
    t.eq("a readout in the file is ignored",
      Object.keys(T.parse(SCHEMA, '{"infoStatePath":"/tmp/x"}')).length, 0);
    t.eq("and never counts as changed",
      T.changedIn(SCHEMA, Object.assign({}, DEFAULTS,
        { infoStatePath: "/tmp/x" }), DEFAULTS, "about"), 0);

    // `same` compares reals with a tolerance, which is the whole reason a
    // quantized 1.15 does not read as "changed" against a default of 1.15.
    t.ok("two reals that are equal are the same",
      T.same(0.1 + 0.2, 0.3));
    t.ok("and two that are not, are not", !T.same(0.3, 0.35));
    t.ok("a string is compared as a string", T.same("crop", "crop"));
    t.ok("and false is not zero", !T.same(false, 0));
  }
};
