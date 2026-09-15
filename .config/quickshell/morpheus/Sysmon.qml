// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SYSMON — every system reading this shell takes, in one place.
//
// It used to be four copies of the same shape: each bar module ran its own
// Timer, its own Process and its own thirty-sample pushHistory. That was
// tolerable while the bar was the only reader. Zeus wants the same five
// readings as graphs, and a second set of pollers would have meant cpu.sh
// running twice a second for two views that then disagreed about what the last
// minute looked like.
//
// So the polling and the history live here, and the modules and zeus are both
// pure display. One reading, one history, and the bar's meter and zeus' graph
// can never tell you two different things.
//
// The inks live here too, for the same reason: a reading's colour IS part of
// the reading in this shell — red is cpu wherever you see it.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "helpers.js" as Helpers
import "../oracle"
import "."

Singleton {
  id: root

  // Two minutes at 1Hz by default. The bar's tooltip sparklines only ever drew
  // the last thirty, and still do — a Sparkline trims to its own maxPoints —
  // but zeus' graphs are four times as wide and want the room.
  //
  // Shortening it takes effect as the histories are next pushed to, not by
  // truncating what is already held: push() trims from the front each time, so
  // a graph walks down to its new length over the next few seconds rather than
  // losing its left half in one frame.
  readonly property int span: Oracle.sysmonSpan

  function push(list, v) {
    const h = list.slice();
    h.push(Math.max(0, Math.min(100, v)));
    while (h.length > root.span) h.shift();
    return h;
  }

  // ── cpu ───────────────────────────────────────────────────────────────
  readonly property color cpuInk: Zenon.red
  property int cpuUsage: 0
  property string cpuTip: ""
  property var cpuHistory: []
  // null until the machine has answered, so a pane can tell "not known" from
  // "zero" and print a dash instead of a wrong number
  property var cpuFreq: null      // MHz
  property var cpuTemp: null      // °C
  property var cpuLoad: null      // 1-minute load average

  // ── THE CPU, READ RATHER THAN SHELLED OUT FOR ─────────────────────────
  // cpu.sh ran once a second and forked about eight times doing it: bash,
  // two mktemps, two greps of /proc/stat either side of an internal
  // `sleep 0.3`, an awk over both, then — every single tick, for facts that
  // cannot change while the machine is on — a grep of /proc/cpuinfo, TWO
  // lscpus and an nproc.
  //
  // All of it is in files this process can open. /proc/stat gives the usage
  // and the per-core breakdown, /proc/loadavg the load and the process count,
  // /proc/cpuinfo the model and the core counts, and cpufreq the frequency.
  //
  // AND THE SAMPLING WINDOW IS THE TICK. The script slept 0.3s to have two
  // readings to subtract; this keeps the previous one, so the window is the
  // whole second between ticks — a longer baseline and a truer number, for
  // no sleep at all.
  //
  // The script is left in scripts/ untouched. Nothing calls it now.
  FileView { id: statFile; path: "/proc/stat"; blockLoading: true; printErrors: false }
  FileView { id: loadFile; path: "/proc/loadavg"; blockLoading: true; printErrors: false }
  FileView { id: cpuinfoFile; path: "/proc/cpuinfo"; blockLoading: true; printErrors: false }

  // The reading the last tick took, to subtract this one from.
  property var cpuPrev: null
  // Read once: a processor does not change model or core count mid-session.
  property string cpuName: ""
  property int cpuCores: 0
  property int cpuThreads: 0
  // Found once, because the hwmon index is fixed for the life of the boot.
  property string cpuTempPath: ""

  FileView {
    id: cpuTempFile
    path: root.cpuTempPath
    blockLoading: true
    printErrors: false
  }

  Process {
    id: cpuTempFind
    command: ["sh", "-c",
      "find /sys/devices/platform/coretemp.0/hwmon -name temp1_input 2>/dev/null | head -n1"]
    stdout: StdioCollector {
      id: cpuTempOut
      waitForEnd: true
      onStreamFinished: root.cpuTempPath = String(cpuTempOut.text).trim()
    }
  }

  // One FileView per thread, the same files cpu.sh averaged over.
  Instantiator {
    id: freqFiles
    model: root.cpuThreads
    delegate: FileView {
      required property int index
      path: "/sys/devices/system/cpu/cpu" + index + "/cpufreq/scaling_cur_freq"
      blockLoading: true
      printErrors: false
    }
  }

  function readCpuStatic() {
    cpuinfoFile.reload();
    const t = String(cpuinfoFile.text());
    const nm = t.match(/^model name\s*:\s*(.+)$/m);
    root.cpuName = nm ? nm[1].trim() : "";
    const th = t.match(/^processor\s*:/gm);
    root.cpuThreads = th ? th.length : 0;
    const co = t.match(/^cpu cores\s*:\s*(\d+)$/m);
    root.cpuCores = co ? parseInt(co[1], 10) : root.cpuThreads;
  }

  // The totals and the idle time of every line in /proc/stat that names a cpu.
  function cpuSample() {
    statFile.reload();
    const out = ({});
    const lines = String(statFile.text()).split("\n");
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(/^(cpu[0-9]*)\s+(.*)$/);
      if (!m) continue;
      const n = m[2].trim().split(/\s+/).map(Number);
      let tot = 0;
      for (let k = 0; k < n.length; k++) tot += n[k];
      // idle + iowait, the two columns cpu.sh counted as not-working
      out[m[1]] = { t: tot, i: (n[3] || 0) + (n[4] || 0) };
    }
    return out;
  }

  function cpuPct(now, prev, key) {
    if (!prev || !prev[key] || !now[key]) return 0;
    const dt = now[key].t - prev[key].t;
    const di = now[key].i - prev[key].i;
    return dt > 0 ? Math.round(100 * (dt - di) / dt) : 0;
  }

  function pollCpu() {
    const now = root.cpuSample();
    const prev = root.cpuPrev;
    root.cpuPrev = now;
    // The first tick has nothing to subtract from and is not a reading.
    if (!prev) return;

    const usage = root.cpuPct(now, prev, "cpu");

    let freq = null;
    let sum = 0;
    let seen = 0;
    for (let i = 0; i < freqFiles.count; i++) {
      const f = freqFiles.objectAt(i);
      if (!f) continue;
      f.reload();
      const v = parseInt(String(f.text()).trim(), 10);
      if (!isNaN(v)) { sum += v; seen++; }
    }
    if (seen > 0) freq = Math.round(sum / seen / 1000);

    let temp = null;
    if (root.cpuTempPath !== "") {
      cpuTempFile.reload();
      const v = parseInt(String(cpuTempFile.text()).trim(), 10);
      if (!isNaN(v)) temp = Math.round(v / 1000);
    }

    loadFile.reload();
    const la = String(loadFile.text()).trim().split(/\s+/);
    const load = la.length > 0 ? parseFloat(la[0]) : null;

    // ── THE TOOLTIP, SAID THE WAY THE SCRIPT SAID IT ────────────────────
    // Same lines, same order, same wording — this is the one part of the
    // change anybody can see, so it is the one part that must not differ.
    let tip = "CPU: " + root.cpuName
      + "\nCores: " + (root.cpuCores || "?") + " cores / "
      + (root.cpuThreads || "?") + " threads";
    if (freq !== null)
      tip += "\nFrequency: " + (freq / 1000).toFixed(2) + " GHz";
    if (temp !== null) tip += "\nTemperature: " + temp + "\u00b0C";
    if (la.length >= 3)
      tip += "\nLoad Average: " + la[0] + " " + la[1] + " " + la[2];
    if (la.length >= 4) tip += "\nRunning: " + la[3];
    tip += "\n\nUsage: " + usage + "%\n\nPer Core:";
    const keys = [];
    for (const k in now) if (k !== "cpu") keys.push(k);
    keys.sort((a, b) => parseInt(a.slice(3), 10) - parseInt(b.slice(3), 10));
    for (let i = 0; i < keys.length; i++)
      tip += "\n  " + keys[i].slice(3) + " " + root.cpuPct(now, prev, keys[i]) + "%";

    root.cpuUsage = usage;
    root.cpuTip = tip;
    root.cpuFreq = freq;
    root.cpuTemp = temp;
    root.cpuLoad = isNaN(load) ? null : load;
    root.cpuHistory = root.push(root.cpuHistory, usage);
  }

  // Stands in for the Process the tick used to start, so the tick below is
  // unchanged and does not have to know which pollers are processes.
  QtObject {
    id: cpuProc
    property bool running: false
    onRunningChanged: {
      if (!cpuProc.running) return;
      root.pollCpu();
      cpuProc.running = false;
    }
  }

  // ── gpu ───────────────────────────────────────────────────────────────
  readonly property color gpuInk: Zenon.pink
  // a fact about the machine, not about the text: the bar's module hides on it
  property bool gpuPresent: false
  property int gpuUsage: 0
  property int gpuTemp: 0
  property string gpuTip: ""
  property var gpuHistory: []

  Process {
    id: gpuProc
    command: [Helpers.script("gpu.sh")]
    stdout: SplitParser {
      onRead: (line) => {
        try {
          const o = JSON.parse(line);
          root.gpuPresent = o.present ?? false;
          root.gpuUsage = o.util ?? 0;
          root.gpuTemp = o.temp ?? 0;
          root.gpuTip = o.tooltip ?? "";
          root.gpuHistory = root.push(root.gpuHistory, o.util ?? 0);
        } catch (e) {}
      }
    }
  }

  // ── memory ────────────────────────────────────────────────────────────
  readonly property color memInk: Zenon.sand
  property real memTotal: 0        // KiB, as /proc/meminfo reports it
  property real memAvail: 0
  property real swapTotal: 0
  property real swapFree: 0
  property int memUsage: 0
  property string memTip: ""
  property var memHistory: []

  readonly property real memUsed: Helpers.giB(root.memTotal - root.memAvail)
  readonly property real swapUsed: Helpers.giB(root.swapTotal - root.swapFree)

  // ── READ, NOT SPAWNED ─────────────────────────────────────────────────
  // This was `cat /proc/meminfo` — a fork, an exec and a pipe, once a second,
  // for the whole life of the session, to read a file this process can open
  // itself. FileView reads /proc directly: measured, the same 1671 bytes and
  // fresh values on every reload.
  //
  // The parser is untouched. It wants lines and it still gets lines; only the
  // thing handing them over has changed.
  FileView {
    id: memFile
    path: "/proc/meminfo"
    blockLoading: true
    printErrors: false
  }

  // Kept so the tick below can go on saying `if (!running)` about all four
  // pollers without knowing which of them are processes any more.
  QtObject {
    id: memProc
    property bool running: false
    onRunningChanged: {
      if (!memProc.running) return;
      memFile.reload();
      const lines = String(memFile.text()).split("\n");
      for (let i = 0; i < lines.length; i++) root.parseMem(lines[i]);
      memProc.running = false;
    }
  }

  // /proc/meminfo arrives a line at a time and the four fields that matter are
  // in a fixed order, so SwapFree — the last of them — is where the reading is
  // complete enough to publish.
  function parseMem(line) {
    if (line.startsWith("MemTotal:")) root.memTotal = parseInt(line.split(/\s+/)[1], 10) || 0;
    else if (line.startsWith("MemAvailable:")) root.memAvail = parseInt(line.split(/\s+/)[1], 10) || 0;
    else if (line.startsWith("SwapTotal:")) root.swapTotal = parseInt(line.split(/\s+/)[1], 10) || 0;
    else if (line.startsWith("SwapFree:")) {
      root.swapFree = parseInt(line.split(/\s+/)[1], 10) || 0;
      root.memTip =
          "RAM Total: " + Helpers.format1f(Helpers.giB(root.memTotal)) + "GiB\n" +
          "RAM Used: " + Helpers.format1f(root.memUsed) + "GiB\n" +
          "RAM Available: " + Helpers.format1f(Helpers.giB(root.memAvail)) + "GiB\n\n" +
          "SWAP Total: " + Helpers.format1f(Helpers.giB(root.swapTotal)) + "GiB\n" +
          "SWAP Used: " + Helpers.format1f(root.swapUsed) + "GiB\n" +
          "SWAP Available: " + Helpers.format1f(Helpers.giB(root.swapFree)) + "GiB";
      const pct = root.memTotal > 0
        ? Math.round((root.memTotal - root.memAvail) / root.memTotal * 100) : 0;
      root.memUsage = pct;
      root.memHistory = root.push(root.memHistory, pct);
    }
  }

  // ── disk ──────────────────────────────────────────────────────────────
  // Two inks, like the network's, because it is the same kind of reading: two
  // directions through one pipe.
  readonly property color diskReadInk: Zenon.cyan
  readonly property color diskWriteInk: Zenon.green
  property real diskRead: 0        // bytes/sec
  property real diskWrite: 0
  property int diskUsedPct: 0
  property real diskTotal: 0       // bytes
  property real diskUsedBytes: 0
  property string diskTip: ""
  property var diskReadHistory: []
  property var diskWriteHistory: []

  readonly property string diskReadText: Helpers.powFormat(root.diskRead)
  readonly property string diskWriteText: Helpers.powFormat(root.diskWrite)

  // ── THE DISK, SPLIT BY HOW OFTEN IT CHANGES ───────────────────────────
  // disk.sh was the most expensive poller in the shell: 358ms of bash every
  // second — two walks of /sys/block either side of an internal `sleep 0.3`,
  // several awks, a df and a jq. It was alive for a third of every second.
  //
  // Throughput is read here, the same way the CPU is: the previous sample is
  // kept and the window is the tick, so there is no sleep and no process.
  //
  // CAPACITY IS A DIFFERENT QUESTION and gets a different rate. How full the
  // root filesystem is moves in minutes, not in tenths of a second, and there
  // is no /proc for it — statvfs is what df is for. So it keeps its process
  // and runs every thirty seconds instead of every one.
  property var diskDevs: []
  property var diskPrev: null

  Process {
    id: diskFind
    command: ["sh", "-c",
      "for d in /sys/block/*; do n=${d##*/}; case $n in loop*|zram*|ram*|dm-*|md*) continue;; esac; [ -r \"$d/stat\" ] && echo $n; done"]
    stdout: StdioCollector {
      id: diskFindOut
      waitForEnd: true
      onStreamFinished: {
        const out = [];
        const ls = String(diskFindOut.text).trim().split("\n");
        for (let i = 0; i < ls.length; i++)
          if (ls[i].trim() !== "") out.push(ls[i].trim());
        root.diskDevs = out;
      }
    }
  }

  Instantiator {
    id: diskFiles
    model: root.diskDevs
    delegate: FileView {
      required property var modelData
      path: "/sys/block/" + modelData + "/stat"
      blockLoading: true
      printErrors: false
    }
  }

  function pollDisk() {
    let r = 0;
    let w = 0;
    for (let i = 0; i < diskFiles.count; i++) {
      const f = diskFiles.objectAt(i);
      if (!f) continue;
      f.reload();
      const n = String(f.text()).trim().split(/\s+/);
      if (n.length < 8) continue;
      // field 3 is sectors read and field 7 sectors written, and a sector is
      // 512 bytes whatever the drive's own block size is — the kernel reports
      // these in 512-byte units by definition.
      r += parseInt(n[2], 10) || 0;
      w += parseInt(n[6], 10) || 0;
    }
    const now = Date.now();
    const prev = root.diskPrev;
    root.diskPrev = { r: r, w: w, time: now };
    if (!prev) return;
    const dt = (now - prev.time) / 1000;
    if (dt <= 0) return;
    root.diskRead = Math.max(0, (r - prev.r) * 512 / dt);
    root.diskWrite = Math.max(0, (w - prev.w) * 512 / dt);
    root.diskReadCeil = Math.max(root.diskRead, root.minDiskCeil,
      root.diskReadCeil * root.slowDecay);
    root.diskWriteCeil = Math.max(root.diskWrite, root.minDiskCeil,
      root.diskWriteCeil * root.slowDecay);
    root.diskReadHistory = root.push(root.diskReadHistory,
      root.logLevel(root.diskRead, root.diskReadCeil));
    root.diskWriteHistory = root.push(root.diskWriteHistory,
      root.logLevel(root.diskWrite, root.diskWriteCeil));
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!diskCapProc.running) diskCapProc.running = true
  }

  Process {
    id: diskCapProc
    command: ["df", "-P", "-B1", "/"]
    stdout: StdioCollector {
      id: diskCapOut
      waitForEnd: true
      onStreamFinished: {
        const ls = String(diskCapOut.text).trim().split("\n");
        if (ls.length < 2) return;
        const f = ls[1].trim().split(/\s+/);
        if (f.length < 5) return;
        const total = parseInt(f[1], 10) || 0;
        const used = parseInt(f[2], 10) || 0;
        const avail = parseInt(f[3], 10) || 0;
        const pct = parseInt(String(f[4]).replace("%", ""), 10) || 0;
        root.diskTotal = total;
        root.diskUsedBytes = used;
        root.diskUsedPct = pct;
        const gib = (b) => (b / 1073741824).toFixed(1);
        root.diskTip = "Disk: / \u2014 " + gib(used) + " GiB used of "
          + gib(total) + " GiB\nFree: " + gib(avail) + " GiB ("
          + pct + "% used)";
      }
    }
  }

  // Stands in for the Process the tick used to start.
  QtObject {
    id: diskProc
    property bool running: false
    onRunningChanged: {
      if (!diskProc.running) return;
      root.pollDisk();
      diskProc.running = false;
    }
  }


  readonly property real minDiskCeil: 32 * 1024 * 1024
  // per 1s sample — about a three minute half-life, same feel as the network's
  readonly property real slowDecay: 0.996
  property real diskReadCeil: root.minDiskCeil
  property real diskWriteCeil: root.minDiskCeil

  // ── network ───────────────────────────────────────────────────────────
  readonly property color netDownInk: Zenon.blue
  readonly property color netUpInk: Zenon.magenta

  property string netIface: ""
  property string netIp: ""
  property bool netConnected: false
  property real netDown: 0            // smoothed bytes/sec
  property real netUp: 0
  property string netDownText: "0.0B/s"
  property string netUpText: "0.0B/s"
  property var netDownHistory: []
  property var netUpHistory: []
  property var netSample: null

  // exponential smoothing: 4Hz sampling without twitchy segments
  function smoothed(oldV, newV) {
    if (oldV <= 0) return newV;
    return oldV * 0.6 + newV * 0.4;
  }

  // Log-scaled between a floor and a ceiling, rather than from zero.
  //
  // Dividing log10(1 + bytes) by log10(1 + max) puts idle traffic most of the
  // way up: 36 kB/s — a page loading in the background — measured 62/100, so
  // the top two notches were the only ones that ever moved and the meter looked
  // permanently near full without ever reaching it. Normalising the log over
  // floor..max instead spends the range where the traffic actually is.
  //
  // The ceiling is LEARNED, not guessed. Any fixed full-scale figure is a guess
  // about someone else's line: measured on this one the uplink peaks at
  // 0.74 MB/s, so even a 4MB/s ceiling put a saturated upload at five notches
  // and made the sixth unreachable by construction. Tracking the fastest rate
  // actually seen means "all six lit" reads as "as fast as this link goes" —
  // correct on a 6 Mbit uplink and on a gigabit one, with nothing to retune.
  //
  // The peak decays slowly, so one big transfer does not desensitise the meter
  // for the rest of the session; the floor stops an idle trickle from looking
  // like saturation just because nothing faster has happened yet.
  readonly property real barFloor: 1024
  readonly property real minDownCeil: 2 * 1024 * 1024
  readonly property real minUpCeil: 512 * 1024
  // per 250ms sample — a half-life of about three minutes
  readonly property real peakDecay: 0.999
  property real downCeil: root.minDownCeil
  property real upCeil: root.minUpCeil

  function logLevel(bytes, ceil) {
    if (bytes <= root.barFloor) return 0;
    const frac = Math.log10(bytes / root.barFloor)
      / Math.log10(ceil / root.barFloor);
    return Math.max(0, Math.min(1, frac)) * 100;
  }

  readonly property real netDownLevel:
    root.netConnected ? root.logLevel(root.netDown, root.downCeil) : 0
  readonly property real netUpLevel:
    root.netConnected ? root.logLevel(root.netUp, root.upCeil) : 0

  onNetIfaceChanged: {
    root.netSample = null;
    root.netDownText = "0.0B/s";
    root.netUpText = "0.0B/s";
    root.netDown = 0;
    root.netUp = 0;
  }

  Process {
    id: netInfoProc
    command: ["sh", Helpers.script("netinfo.sh")]
    stdout: SplitParser {
      onRead: (line) => {
        const parts = line.split("|");
        if (parts.length === 3) {
          root.netIface = parts[0];
          root.netIp = parts[1];
          root.netConnected = parts[0] !== "" && parts[2].trim() === "1";
        }
      }
    }
  }

  // ── FOUR TIMES A SECOND, WITHOUT A PROCESS ────────────────────────────
  // This was a shell held open for the life of the session running
  // `cat /proc/net/dev; sleep 0.25` forever — a fork and an exec every 250ms,
  // eight processes a second, to read a 450-byte file. The comment above it
  // argued that a loop was cheaper than spawning a shell per sample, which
  // was true and beside the point: nothing has to be spawned at all.
  //
  // The sample rate and the parser are unchanged.
  FileView {
    id: netDevFile
    path: "/proc/net/dev"
    blockLoading: true
    printErrors: false
  }

  Timer {
    interval: 250
    repeat: true
    running: true
    onTriggered: {
      netDevFile.reload();
      root.netDevLines = String(netDevFile.text()).split("\n");
      root.finalizeNetSample();
    }
  }

  property var netDevLines: []

  function finalizeNetSample() {
    let rx = 0;
    let tx = 0;
    for (const l of root.netDevLines) {
      const idx = l.indexOf(":");
      if (idx <= 0) continue;
      const name = l.slice(0, idx).trim();
      if (name === "lo") continue;
      if (root.netIface !== "" && name !== root.netIface) continue;
      const nums = l.slice(idx + 1).trim().split(/\s+/).map(Number);
      if (nums.length >= 16) {
        rx += nums[0];
        tx += nums[8];
      }
    }
    root.netDevLines = [];
    const now = Date.now();
    if (root.netSample) {
      const elapsed = (now - root.netSample.time) / 1000;
      if (elapsed > 0) {
        const down = Math.max(0, (rx - root.netSample.rx) / elapsed);
        const up = Math.max(0, (tx - root.netSample.tx) / elapsed);
        root.netDown = root.smoothed(root.netDown, down);
        root.netUp = root.smoothed(root.netUp, up);
        // the high-water mark each meter is scaled against
        root.downCeil = Math.max(root.netDown, root.minDownCeil,
          root.downCeil * root.peakDecay);
        root.upCeil = Math.max(root.netUp, root.minUpCeil,
          root.upCeil * root.peakDecay);
        root.netDownText = Helpers.powFormat(root.netDown);
        root.netUpText = Helpers.powFormat(root.netUp);
        root.netDownHistory = root.push(root.netDownHistory, root.netDownLevel);
        root.netUpHistory = root.push(root.netUpHistory, root.netUpLevel);
      }
    }
    root.netSample = { rx: rx, tx: tx, time: now };
  }

  // ── the tick ──────────────────────────────────────────────────────────
  // One timer for the four one-shot pollers rather than four of them on their
  // own phase. `if (!running)` on each: a poller that is somehow taking longer
  // than a second must not be asked again on top of itself.
  Timer {
    interval: Oracle.sysmonInterval
    repeat: true
    running: true
    onTriggered: {
      if (!cpuProc.running) cpuProc.running = true;
      if (!memProc.running) memProc.running = true;
      if (!diskProc.running) diskProc.running = true;
    }
  }

  // ON ITS OWN CLOCK. The other three read files; this one spawns a process
  // that talks to the driver, and it is the only poller left that does.
  Timer {
    interval: Oracle.sysmonGpuInterval
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!gpuProc.running) gpuProc.running = true
  }

  // the interface and address change far more rarely than the throughput does
  Timer {
    interval: Oracle.sysmonNetInterval
    repeat: true
    running: true
    onTriggered: {
      if (!netInfoProc.running) netInfoProc.running = true;
    }
  }

  Component.onCompleted: {
    root.readCpuStatic();
    cpuTempFind.running = true;
    diskFind.running = true;
    cpuProc.running = true;
    gpuProc.running = true;
    memProc.running = true;
    diskProc.running = true;
    netInfoProc.running = true;
  }
}
