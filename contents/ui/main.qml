import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation

    property real currentPingCf: -1
    property real currentPingG: -1
    property real maxPing: 50
    property real displayMaxPing: 50
    property real displayCf: -1
    property real displayG: -1

    // Easing state: start value, start time for each series
    property real cfFrom: 0
    property real cfTo: 0
    property real cfStartTime: 0
    property real gFrom: 0
    property real gTo: 0
    property real gStartTime: 0
    // Duration of each transition (must be < 1s so it finishes before the other series starts)
    readonly property real easeDuration: 800 // ms
    property var cfHistory: []
    property var gHistory: []
    // Pending ping responses stored with their request timestamp (ms)
    property var _pendingCf: []
    property var _pendingG: []

    // Sampling/tuning: how often to sample the smoothed display values (ms)
    // Reduced to 40ms for smoother lines (tradeoff: slightly higher CPU).
    readonly property int sampleIntervalMs: 40
    // Cap history to this many samples (will be computed from sampleIntervalMs and windowSecs)
    readonly property int historyCap: Math.ceil((1000 / sampleIntervalMs) * windowSecs) + 4

    readonly property color cfColor: Kirigami.Theme.positiveTextColor
    readonly property color gColor: Kirigami.Theme.negativeTextColor

    // Show 1-minute history on the x-axis
    readonly property real windowSecs: 60

    // Timeout flash
    property real cfFlashOpacity: 0
    property real gFlashOpacity: 0

    SequentialAnimation {
        id: cfFlash
        NumberAnimation { target: root; property: "cfFlashOpacity"; to: 0.15; duration: 100 }
        NumberAnimation { target: root; property: "cfFlashOpacity"; to: 0; duration: 400 }
    }
    SequentialAnimation {
        id: gFlash
        NumberAnimation { target: root; property: "gFlashOpacity"; to: 0.15; duration: 100 }
        NumberAnimation { target: root; property: "gFlashOpacity"; to: 0; duration: 400 }
    }

    function processPing(stdout, isCf) {
        var ping = -1
        var match = stdout.match(/time=([\d.]+)\s*ms/)
        if (match) ping = parseFloat(match[1])
        // Try to parse the echoed request timestamp (we append it to the ping command)
        var reqTs = Date.now()
        var tmatch = stdout.match(/(\d{10,})\s*$/)
        if (tmatch) reqTs = parseInt(tmatch[1])

        // Do NOT immediately update `currentPing*` here; store into the
        // pending buffers and let the sampling/merge step apply the value
        // at the scheduled request timestamp so both series remain synced.
        if (isCf) {
            try { root._pendingCf = (root._pendingCf || []).concat([{ t: reqTs, v: ping }]) } catch(e) {}
        } else {
            try { root._pendingG = (root._pendingG || []).concat([{ t: reqTs, v: ping }]) } catch(e) {}
        }

        // Auto-scale (track recent max via lerp target)
        var m = 50
        if (root.currentPingCf > m) m = root.currentPingCf
        if (root.currentPingG > m) m = root.currentPingG
        root.maxPing = Math.max(root.maxPing, Math.ceil(m / 25) * 25)
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            var stdout = data["stdout"] || ""
            var isCf = source.indexOf("1.1.1.1") !== -1
            processPing(stdout, isCf)
            executable.disconnectSource(source)
        }
    }

    // Use two dedicated 1s timers staggered by 500ms so each host is pinged
    // on a regular 1s cadence. This avoids racey alternation and keeps
    // scheduling explicit.
    Timer {
        id: pingCfTimer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            executable.connectSource("ping -c 1 -W 1 1.1.1.1; echo " + Date.now())
        }
    }

    Timer {
        id: pingGTimer
        interval: 2000
        running: false
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            executable.connectSource("ping -c 1 -W 1 8.8.8.8; echo " + Date.now())
        }
    }

    // Start the second timer staggered by 1000ms after creation so each host
    // is pinged every 2s but staggered by 1s (only one host updates per second)
    Timer { id: startStagger; interval: 1000; running: true; repeat: false; onTriggered: pingGTimer.start() }

    fullRepresentation: Item {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: Kirigami.Units.gridUnit * 10
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 6

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.3)
            radius: 4
        }

        Rectangle {
            anchors.fill: parent
            color: root.cfColor
            opacity: root.cfFlashOpacity
            radius: 4
        }
        Rectangle {
            anchors.fill: parent
            color: root.gColor
            opacity: root.gFlashOpacity
            radius: 4
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing * 2
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.gridUnit

                RowLayout {
                    spacing: 4
                    Rectangle { width: 12; height: 12; radius: 6; color: root.cfColor }
                    Text {
                        text: "1.1.1.1"
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.5
                        opacity: 0.8
                    }
                }

                RowLayout {
                    spacing: 4
                    Rectangle { width: 12; height: 12; radius: 6; color: root.gColor }
                    Text {
                        text: "8.8.8.8"
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.5
                        opacity: 0.8
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Chart area with static grid lines behind canvas
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Static grid lines (not part of canvas, won't shift)
                Repeater {
                    model: 5
                    Rectangle {
                        required property int index
                        x: 0
                        y: 12 + (parent.height - 24) * index / 4
                        width: parent.width - 90
                        height: 1
                        color: Kirigami.Theme.textColor
                        opacity: 0.1
                    }
                }

                Canvas {
                    id: chartCanvas
                    anchors.fill: parent

                    property real lastCfY: -1
                    property real lastGY: -1
                    property real lastSampleTime: 0
                    property real scrollAcc: 0
                    property real lastTime: 0
                    // Per-pixel line buffers (values in ms or -1 for gap)
                    property var cfLineBuf: []
                    property var gLineBuf: []
                    property int _lineW: 0

                    property real lastCfSample: 0
                    property real lastGSample: 0

                    Timer {
                        id: chartUpdateTimer
                        interval: 16
                        running: true
                        repeat: true
                        onTriggered: {
                            // Smoothstep easing: symmetric ease-in + ease-out
                            // t goes 0→1 over easeDuration, smoothstep gives S-curve
                            var now = Date.now()

                            function smoothstep(t) {
                                if (t <= 0) return 0
                                if (t >= 1) return 1
                                return t * t * (3 - 2 * t)
                            }

                            if (root.currentPingCf >= 0 && root.cfStartTime > 0) {
                                var tCf = (now - root.cfStartTime) / root.easeDuration
                                root.displayCf = root.cfFrom + (root.cfTo - root.cfFrom) * smoothstep(tCf)
                            }
                            if (root.currentPingG >= 0 && root.gStartTime > 0) {
                                var tG = (now - root.gStartTime) / root.easeDuration
                                root.displayG = root.gFrom + (root.gTo - root.gFrom) * smoothstep(tG)
                            }
                            // Max scale uses simple lerp (doesn't need to be as precise)
                            root.displayMaxPing += (root.maxPing - root.displayMaxPing) * 0.05

                            // Sample the smoothed display values at a modest rate
                            // (avoid pushing on every frame). Use ~100ms sampling.
                            try {
                                var nowS = Date.now()
                                if (!chartCanvas.lastCfSample) chartCanvas.lastCfSample = 0
                                if (!chartCanvas.lastGSample) chartCanvas.lastGSample = 0
                                if (nowS - Math.min(chartCanvas.lastCfSample, chartCanvas.lastGSample) > root.sampleIntervalMs) {
                                    chartCanvas.lastCfSample = chartCanvas.lastCfSample || 0
                                    chartCanvas.lastGSample = chartCanvas.lastGSample || 0
                                    try {
                                        // Merge any pending ping responses first (they carry their request timestamps)
                                        var nc = (root.cfHistory || []).slice()
                                        var ng = (root.gHistory || []).slice()
                                        if (root._pendingCf && root._pendingCf.length) {
                                            for (var pi = 0; pi < root._pendingCf.length; ++pi) {
                                                var p = root._pendingCf[pi]
                                                if (p && typeof p.v !== 'undefined') {
                                                    var val = (p.v >= 1000 || p.v < 0) ? null : p.v
                                                    nc.push({ t: p.t, v: val })
                                                    if (val === null) {
                                                        root.currentPingCf = -1
                                                        root.displayCf = -1
                                                        cfFlash.restart()
                                                    } else {
                                                        root.cfFrom = root.displayCf > 0 ? root.displayCf : val
                                                        root.cfTo = val
                                                        root.cfStartTime = Date.now()
                                                        root.currentPingCf = val
                                                    }
                                                }
                                            }
                                            root._pendingCf = []
                                        }
                                        if (root._pendingG && root._pendingG.length) {
                                            for (var pj = 0; pj < root._pendingG.length; ++pj) {
                                                var q = root._pendingG[pj]
                                                if (q && typeof q.v !== 'undefined') {
                                                    var qv = (q.v >= 1000 || q.v < 0) ? null : q.v
                                                    ng.push({ t: q.t, v: qv })
                                                    if (qv === null) {
                                                        root.currentPingG = -1
                                                        root.displayG = -1
                                                        gFlash.restart()
                                                    } else {
                                                        root.gFrom = root.displayG > 0 ? root.displayG : qv
                                                        root.gTo = qv
                                                        root.gStartTime = Date.now()
                                                        root.currentPingG = qv
                                                    }
                                                }
                                            }
                                            root._pendingG = []
                                        }

                                        // Sample the moving display values into history while the
                                        // point is present. This makes the line follow the dot.
                                        if (nowS - chartCanvas.lastCfSample > root.sampleIntervalMs) {
                                            chartCanvas.lastCfSample = nowS
                                            if (root.displayCf >= 0) nc.push({ t: nowS, v: root.displayCf })
                                            else nc.push({ t: nowS, v: null })
                                        }
                                        if (nowS - chartCanvas.lastGSample > root.sampleIntervalMs) {
                                            chartCanvas.lastGSample = nowS
                                            if (root.displayG >= 0) ng.push({ t: nowS, v: root.displayG })
                                            else ng.push({ t: nowS, v: null })
                                        }

                                        // Sort histories chronologically and cap size
                                        try { nc.sort(function(a,b){return a.t - b.t}) } catch(e) {}
                                        try { ng.sort(function(a,b){return a.t - b.t}) } catch(e) {}
                                        var cap = root.historyCap
                                        root.cfHistory = dedupeAndCap(nc)
                                        root.gHistory = dedupeAndCap(ng)
                                    } catch(e) {}
                                }
                            } catch(e) {}

                            chartCanvas.requestPaint()
                        }
                    }

                    onPaint: {
                        var ctx = getContext("2d")
                        var w = width
                        var h = height
                        var now = Date.now()

                        var padY = 12
                        var rightMargin = 90
                        var chartW = w - rightMargin
                        var chartH = h - padY * 2
                        var maxVal = Math.max(1, root.displayMaxPing)

                        // Helper: dedupe entries with nearly-equal timestamps and cap length
                        function dedupeAndCap(arr) {
                            if (!arr) return []
                            try { arr.sort(function(a,b){return a.t - b.t}) } catch(e) {}
                            var out = []
                            var cap = root.historyCap
                            for (var ii=0; ii < arr.length; ++ii) {
                                var e = arr[ii]
                                if (!e || typeof e.v === 'undefined') continue
                                if (out.length && Math.abs(e.t - out[out.length-1].t) < 20) {
                                    // merge into last (use latest value)
                                    out[out.length-1].v = e.v
                                    out[out.length-1].t = e.t
                                } else {
                                    out.push({ t: e.t, v: e.v })
                                }
                            }
                            if (out.length > cap) out = out.slice(out.length - cap)
                            return out
                        }

                        // Flush any pending ping responses into history here as a
                        // safety net (ensures we render points even if the
                        // chartUpdateTimer sampling path didn't run).
                        try {
                            if (root._pendingCf && root._pendingCf.length) {
                                var nc = (root.cfHistory || []).slice()
                                for (var pi = 0; pi < root._pendingCf.length; ++pi) {
                                    var p = root._pendingCf[pi]
                                    if (!p || typeof p.v === 'undefined') continue
                                        var val = (p.v >= 1000 || p.v < 0) ? null : p.v
                                        nc.push({ t: p.t, v: val })
                                        if (val === null) { root.currentPingCf = -1; root.displayCf = -1; cfFlash.restart() }
                                        else {
                                            root.cfFrom = root.displayCf > 0 ? root.displayCf : val
                                            root.cfTo = val; root.cfStartTime = Date.now()
                                            root.currentPingCf = val
                                        }
                                }
                                root._pendingCf = []
                                root.cfHistory = dedupeAndCap(nc)
                                chartCanvas.lastCfSample = Date.now()
                            }
                            if (root._pendingG && root._pendingG.length) {
                                var ng = (root.gHistory || []).slice()
                                for (var pj = 0; pj < root._pendingG.length; ++pj) {
                                    var q = root._pendingG[pj]
                                    if (!q || typeof q.v === 'undefined') continue
                                    var qv = (q.v >= 1000 || q.v < 0) ? null : q.v
                                    ng.push({ t: q.t, v: qv })
                                    if (qv === null) { root.currentPingG = -1; root.displayG = -1; gFlash.restart() }
                                    else {
                                        root.gFrom = root.displayG > 0 ? root.displayG : qv
                                        root.gTo = qv; root.gStartTime = Date.now()
                                        root.currentPingG = qv
                                    }
                                }
                                root._pendingG = []
                                root.gHistory = dedupeAndCap(ng)
                                chartCanvas.lastGSample = Date.now()
                            }
                        } catch(e) {}

                        // Fallback sampler: if the chartUpdateTimer didn't add
                        // regular display samples, add them here at a reduced
                        // frequency so the line follows the moving dot.
                        try {
                            if (!chartCanvas.lastSampleTime) chartCanvas.lastSampleTime = 0
                            var nowSamp = now
                            if (nowSamp - chartCanvas.lastSampleTime > root.sampleIntervalMs) {
                                chartCanvas.lastSampleTime = nowSamp
                                var ncf = (root.cfHistory || []).slice()
                                var ngg = (root.gHistory || []).slice()
                                if (root.displayCf >= 0) ncf.push({ t: nowSamp, v: root.displayCf })
                                else ncf.push({ t: nowSamp, v: null })
                                if (root.displayG >= 0) ngg.push({ t: nowSamp, v: root.displayG })
                                else ngg.push({ t: nowSamp, v: null })
                                root.cfHistory = dedupeAndCap(ncf)
                                root.gHistory = dedupeAndCap(ngg)
                            }
                        } catch(e) {}

                        if (chartW <= 0 || chartH <= 0) {
                            ctx.clearRect(0, 0, w, h)
                            return
                        }

                        // First frame init
                        if (chartCanvas.lastTime === 0) {
                            chartCanvas.lastTime = now
                            ctx.clearRect(0, 0, w, h)
                            chartCanvas.lastCfY = -1
                            chartCanvas.lastGY = -1
                            return
                        }

                        var dt = (now - chartCanvas.lastTime) / 1000
                        chartCanvas.lastTime = now

                        // Scroll speed: chartW px over windowSecs seconds
                        var speed = chartW / root.windowSecs
                        chartCanvas.scrollAcc += speed * dt
                        var dx = Math.floor(chartCanvas.scrollAcc)
                        chartCanvas.scrollAcc -= dx

                        // Prune old history samples (keep at most `windowSecs` seconds)
                        try {
                            var cutoff = now - root.windowSecs * 1000
                            while (root.cfHistory.length && now - root.cfHistory[0].t > root.windowSecs * 1000) root.cfHistory.shift()
                            while (root.gHistory.length && now - root.gHistory[0].t > root.windowSecs * 1000) root.gHistory.shift()
                        } catch(e) {}

                        // Ensure line buffers match chart width
                        var bufW = Math.max(0, Math.floor(chartW))
                        if (chartCanvas._lineW !== bufW) {
                            chartCanvas._lineW = bufW
                            chartCanvas.cfLineBuf = []
                            chartCanvas.gLineBuf = []
                            for (var bi = 0; bi < bufW; ++bi) { chartCanvas.cfLineBuf.push(-1); chartCanvas.gLineBuf.push(-1) }
                        }

                        // Advance buffers by dx pixels (scroll left) and append current display values
                        if (dx > 0 && chartCanvas._lineW > 0) {
                            // shift left by dx
                            if (dx >= chartCanvas._lineW) {
                                chartCanvas.cfLineBuf = new Array(chartCanvas._lineW).fill(-1)
                                chartCanvas.gLineBuf = new Array(chartCanvas._lineW).fill(-1)
                            } else {
                                chartCanvas.cfLineBuf = chartCanvas.cfLineBuf.slice(dx)
                                chartCanvas.gLineBuf = chartCanvas.gLineBuf.slice(dx)
                                // append dx new samples (use latest display values)
                                for (var si = 0; si < dx; ++si) {
                                    // Only push real values after we've received at least one ping
                                    // (currentPing starts at -1, display starts at 0 and lerps from there)
                                    chartCanvas.cfLineBuf.push(root.currentPingCf > 0 && root.displayCf > 0 ? root.displayCf : -1)
                                    chartCanvas.gLineBuf.push(root.currentPingG > 0 && root.displayG > 0 ? root.displayG : -1)
                                }
                            }
                        }

                        // Clear entire canvas each frame (chart + label area)
                        ctx.clearRect(0, 0, w, h)

                        ctx.lineWidth = 2
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"

                        // Draw lines from per-pixel buffers
                        function drawBuf(buf, color) {
                            if (!buf || !buf.length) return
                            ctx.strokeStyle = color
                            ctx.lineWidth = 2
                            var inPath = false
                            ctx.beginPath()
                            for (var xi = 0; xi < buf.length; ++xi) {
                                var v = buf[xi]
                                if (v === null || v === undefined || isNaN(v) || v < 0) { inPath = false; continue }
                                var y = padY + chartH - (Math.min(v, maxVal) / maxVal) * chartH
                                if (!inPath) {
                                    ctx.moveTo(xi, y)
                                    inPath = true
                                } else {
                                    ctx.lineTo(xi, y)
                                }
                            }
                            ctx.stroke()
                        }

                        drawBuf(chartCanvas.cfLineBuf, root.cfColor)
                        drawBuf(chartCanvas.gLineBuf, root.gColor)

                        // Find single global min and max across both buffers
                        var extremeColor = "#ffdd44"
                        var lblSize = Kirigami.Theme.defaultFont.pixelSize * 1.2
                        var bgPad = 3
                        var globalMax = -Infinity, globalMin = Infinity
                        var globalMaxIdx = -1, globalMinIdx = -1
                        var globalMaxBuf = null, globalMinBuf = null

                        function scanBuf(buf) {
                            if (!buf || !buf.length) return
                            for (var ii = 0; ii < buf.length; ++ii) {
                                var vv = buf[ii]
                                if (vv === null || vv === undefined || isNaN(vv) || vv < 0) continue
                                if (vv > globalMax) { globalMax = vv; globalMaxIdx = ii; globalMaxBuf = buf }
                                if (vv < globalMin) { globalMin = vv; globalMinIdx = ii; globalMinBuf = buf }
                            }
                        }
                        scanBuf(chartCanvas.cfLineBuf)
                        scanBuf(chartCanvas.gLineBuf)

                        function drawExtremeLabel(dotX, dotY, val, offsetY) {
                            ctx.fillStyle = extremeColor
                            ctx.beginPath(); ctx.arc(dotX, dotY, 4, 0, 2 * Math.PI); ctx.fill()
                            ctx.font = lblSize + "px sans-serif"
                            ctx.textBaseline = "middle"
                            var ly = Math.max(lblSize / 2 + 2, Math.min(h - lblSize / 2 - 2, dotY + offsetY))
                            var txt = val.toFixed(1) + " ms"
                            var tw = ctx.measureText(txt).width
                            // Place label on left side if too close to right edge (real-time labels)
                            var labelX = dotX + 8
                            if (dotX + 8 + tw + bgPad > chartW - 10) {
                                labelX = dotX - 8 - tw
                            }
                            ctx.fillStyle = Qt.rgba(0, 0, 0, 0.6)
                            ctx.fillRect(labelX - bgPad, ly - lblSize / 2 - bgPad, tw + bgPad * 2, lblSize + bgPad * 2)
                            ctx.fillStyle = extremeColor
                            ctx.fillText(txt, labelX, ly)
                        }

                        if (globalMaxIdx >= 0) {
                            var maxY = padY + chartH - (Math.min(globalMax, maxVal) / maxVal) * chartH
                            drawExtremeLabel(globalMaxIdx, maxY, globalMax, -10)
                        }
                        if (globalMinIdx >= 0 && globalMax - globalMin >= 1) {
                            var minY = padY + chartH - (Math.min(globalMin, maxVal) / maxVal) * chartH
                            drawExtremeLabel(globalMinIdx, minY, globalMin, -10)
                        }

                        // Compute Y positions for the smoothed display values (for dots/labels)
                        var cfY = (root.displayCf > 0)
                            ? padY + chartH - (root.displayCf / maxVal) * chartH
                            : -1
                        var gY = (root.displayG > 0)
                            ? padY + chartH - (root.displayG / maxVal) * chartH
                            : -1

                        // Update last Y (used for small transitional logic)
                        chartCanvas.lastCfY = (cfY >= 0) ? cfY : -1
                        chartCanvas.lastGY  = (gY  >= 0) ? gY  : -1

                        // Dots + labels
                        var fontSize = Kirigami.Theme.defaultFont.pixelSize * 1.5
                        var minGap = fontSize + 4

                        var cfShow = cfY >= 0
                        var gShow = gY >= 0

                        var cfLabelY = cfY
                        var gLabelY = gY

                        // Nudge labels apart if overlapping
                        if (cfShow && gShow && Math.abs(cfLabelY - gLabelY) < minGap) {
                            var mid = (cfLabelY + gLabelY) / 2
                            cfLabelY = mid - minGap / 2
                            gLabelY = mid + minGap / 2
                            if (cfLabelY < fontSize) { cfLabelY = fontSize; gLabelY = cfLabelY + minGap }
                            if (gLabelY > h - 2) { gLabelY = h - 2; cfLabelY = gLabelY - minGap }
                        }

                        ctx.save()
                        ctx.font = fontSize + "px sans-serif"
                        ctx.textBaseline = "middle"

                        if (cfShow) {
                            // Dot
                            ctx.fillStyle = "" + root.cfColor
                            ctx.beginPath()
                            ctx.arc(chartW, cfY, 5, 0, 2 * Math.PI)
                            ctx.fill()
                            // Label
                            ctx.font = fontSize + "px sans-serif"
                            ctx.fillText(root.displayCf.toFixed(1) + " ms", chartW + 10, cfLabelY)
                        }

                        if (gShow) {
                            ctx.fillStyle = "" + root.gColor
                            ctx.beginPath()
                            ctx.arc(chartW, gY, 5, 0, 2 * Math.PI)
                            ctx.fill()
                            ctx.font = fontSize + "px sans-serif"
                            ctx.fillText(root.displayG.toFixed(1) + " ms", chartW + 10, gLabelY)
                        }
                        ctx.restore()
                    }
                }
            }
        }
    }

    Component.onDestruction: {
        // Stop timers to avoid spawning new worker processes while the
        // plasmoid is tearing down. Let in-flight DataSource responses
        // complete — `onNewData` will disconnect each source when done.
        try { if (pingCfTimer) pingCfTimer.stop() } catch(e) {}
        try { if (pingGTimer) pingGTimer.stop() } catch(e) {}
        try { if (startStagger) startStagger.stop() } catch(e) {}
        try { if (chartUpdateTimer) chartUpdateTimer.stop() } catch(e) {}
    }
}
