import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

// Cava visualizer — runs cava directly with a generated per-side config.
// Bypasses the socket manager for reliability.
// Non-collapse: uses a hidden sizer Text so width is always reserved.
// Auto-hides when no mpris player is detected (unless manual override is set).
Item {
    id: root
    property string side: "left"   // "left" or "right"

    Layout.alignment: Qt.AlignVCenter

    // ── Auto-hide logic ─────────────────────────────────────────────────────
    //  When Config.cavaAutoHide is true (default) AND no mpris player is
    //  detected, the cava module hides itself.  The manual showCava toggle
    //  in the Visibility sub-tab overrides this: when showCava is false,
    //  the module is always hidden; when showCava is true AND cavaAutoHide
    //  is false, the module is always shown regardless of mpris status.
    property bool _mprisActive: false

    // Poll mpris status periodically (lightweight — just checks for any player)
    Process {
        id: mprisCheckProc
        command: ["bash", "-c", "playerctl status 2>/dev/null || echo NoPlayer"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                root._mprisActive = (t === "Playing" || t === "Paused")
            }
        }
        onExited: mprisCheckTimer.restart()
    }
    Timer {
        id: mprisCheckTimer; interval: 3000; repeat: false
        onTriggered: if (!mprisCheckProc.running) mprisCheckProc.running = true
    }

    // Effective visibility: auto-hide when no mpris detected (unless override)
    readonly property bool _autoVisible: Config.cavaAutoHide ? root._mprisActive : true
    visible: _autoVisible
    Behavior on visible { NumberAnimation { duration: 0 } }

    //  Non-collapse: always reserve full width when transparent-when-inactive.
    //  _sizer uses a placeholder string of cavaWidth first-bar chars so the
    //  island pre-allocates the correct width before cava outputs anything.
    implicitWidth:  visible
                        ? (Config.cavaTransparentWhenInactive
                            ? (_sizer.implicitWidth + Config.modPadH * 2)
                            : (_active ? (cavaLabel.implicitWidth + Config.modPadH * 2) : 0))
                        : 0
    implicitHeight: Config.moduleHeight

    property string _text:   ""
    property bool   _active: false

    // ── Direct cava invocation ────────────────────────────────────────────────
    //  Writes a temp config file then runs cava with ascii output.
    //  Each output line: semicolon-separated integers 0..N-1 where N = len(bars).
    //  The ascii_del flag inserts spacing between bars when cavaAsciiSpacing > 0.
    Process {
        id: cavaProc
        // Build command at binding time so it reacts to Config changes on restart.
        command: {
            const bars    = Config.cavaEffectiveBars
            const maxR    = Math.max(0, bars.length - 1)
            const rev     = root.side === "right" ? 1 : 0
            const cfgPath = "/tmp/qs-cava-" + root.side + ".ini"
            const lines = [
                "[general]",
                "bars = "             + Config.cavaWidth,
                "framerate = 60",
                "",
                "[output]",
                "method = raw",
                "raw_target = /dev/stdout",
                "data_format = ascii",
                "ascii_max_range = "  + maxR,
                "bar_delimiter = 59",
                "channels = mono",
                "reverse = "          + rev
            ]
            const quoted   = lines.map(l => JSON.stringify(l)).join(" ")
            const writeCmd = "printf '%s\\n' " + quoted + " > " + cfgPath
            return ["bash", "-c", writeCmd + " && cava -p " + cfgPath]
        }
        Component.onCompleted: running = true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                if (!t || t.startsWith("[")) return   // skip cava header lines
                const vals    = t.split(";")
                const barsStr = Config.cavaEffectiveBars
                let   result  = ""
                let   allZero = true
                const spacer  = Config.cavaAsciiSpacing > 0
                    ? " ".repeat(Config.cavaAsciiSpacing) : ""
                for (let i = 0; i < vals.length; i++) {
                    const v = parseInt(vals[i])
                    if (!isNaN(v)) {
                        if (v > 0) allZero = false
                        if (i > 0 && spacer) result += spacer
                        result += barsStr[Math.min(v, barsStr.length - 1)]
                    }
                }
                root._text   = result
                root._active = !allZero
            }
        }
        onExited: restartTimer.restart()
    }
    Timer { id: restartTimer; interval: 2000; repeat: false
        onTriggered: if (!cavaProc.running) cavaProc.running = true }

    // ── Hidden sizer: reserves correct width before first output ─────────────
    Text {
        id: _sizer
        visible: false
        text: {
            const b = Config.cavaEffectiveBars
            const ch = b.length > 0 ? b[0] : " "
            const sp = Config.cavaAsciiSpacing > 0
                ? " ".repeat(Config.cavaAsciiSpacing) : ""
            let s = ""
            for (let i = 0; i < Config.cavaWidth; i++) {
                if (i > 0 && sp) s += sp
                s += ch
            }
            return s
        }
        font.family:    Config.fontFamily
        font.pixelSize: Config.glyphSize
    }

    // ── Visible label ─────────────────────────────────────────────────────────
    Text {
        id: cavaLabel
        anchors.centerIn: parent
        text: root._text

        readonly property color _activeColor: Config.cavaGradientEnabled
            ? Config.cavaGradientStartColor
            : Qt.rgba(Config.cavaGlyphColor.r, Config.cavaGlyphColor.g,
                      Config.cavaGlyphColor.b, Config.cavaActiveOpacity)

        readonly property color _inactiveColor: Config.cavaGradientEnabled
            ? Qt.rgba(Config.cavaGradientEndColor.r, Config.cavaGradientEndColor.g,
                      Config.cavaGradientEndColor.b, Config.cavaInactiveOpacity)
            : Qt.rgba(Config.cavaGlyphColor.r, Config.cavaGlyphColor.g,
                      Config.cavaGlyphColor.b, Config.cavaInactiveOpacity)

        color: root._active ? _activeColor : _inactiveColor
        font.family:    Config.fontFamily
        font.pixelSize: Config.glyphSize
        Behavior on color { ColorAnimation { duration: 300 } }
    }
}
