import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // This plasmoid only has a full representation.
    preferredRepresentation: fullRepresentation

    // Latest parsed ping values (ms); -1 means timeout/unavailable.
    property real currentPingCf: -1
    property real currentPingG: -1

    // Dynamic Y-scale target and eased display value for the chart.
    property real maxPing: 50
    property real displayMaxPing: 50

    // Smoothed values currently rendered in the chart/labels.
    property real displayCf: -1
    property real displayG: -1

    // Easing state for each provider.
    property real cfFrom: -1
    property real cfTo: -1
    property real cfStartTime: 0
    property real gFrom: -1
    property real gTo: -1
    property real gStartTime: 0

    readonly property real easeDuration: 800
    readonly property real windowSecs: 60

    readonly property color cfColor: Kirigami.Theme.positiveTextColor
    readonly property color gColor: Kirigami.Theme.negativeTextColor

    // Timeout flash overlay opacities.
    property real cfFlashOpacity: 0
    property real gFlashOpacity: 0

    // Smooth S-curve interpolation used for point transitions.
    function smoothstep(t) {
        if (t <= 0) {
            return 0
        }
        if (t >= 1) {
            return 1
        }
        return t * t * (3 - 2 * t)
    }

    // Parse-independent ping application path used by both providers.
    // `ping` is in ms; invalid/timeout values are normalized to -1.
    function applyPing(isCf, ping) {
        var value = (ping >= 0 && ping < 1000) ? ping : -1
        var now = Date.now()

        if (isCf) {
            if (value < 0) {
                currentPingCf = -1
                displayCf = -1
                cfFrom = -1
                cfTo = -1
                cfFlash.restart()
            } else {
                cfFrom = displayCf >= 0 ? displayCf : value
                cfTo = value
                cfStartTime = now
                currentPingCf = value
            }
        } else {
            if (value < 0) {
                currentPingG = -1
                displayG = -1
                gFrom = -1
                gTo = -1
                gFlash.restart()
            } else {
                gFrom = displayG >= 0 ? displayG : value
                gTo = value
                gStartTime = now
                currentPingG = value
            }
        }

        var m = 50
        if (currentPingCf > m) {
            m = currentPingCf
        }
        if (currentPingG > m) {
            m = currentPingG
        }
        maxPing = Math.max(50, Math.ceil(m / 25) * 25)
    }

    // Parse ping stdout and forward normalized value to state updater.
    function processPing(stdout, isCf) {
        var ping = -1
        var match = stdout.match(/time=([\d.]+)\s*ms/)
        if (match) {
            ping = parseFloat(match[1])
        }
        applyPing(isCf, ping)
    }

    // Subtle timeout indicator for each provider.
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

    // Plasma executable engine runs ping commands asynchronously.
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

    // Poll each host every 2s, staggered by 1s so only one command starts per second.
    Timer {
        id: pingCfTimer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: executable.connectSource("ping -c 1 -W 1 1.1.1.1")
    }

    Timer {
        id: pingGTimer
        interval: 2000
        running: false
        repeat: true
        triggeredOnStart: false
        onTriggered: executable.connectSource("ping -c 1 -W 1 8.8.8.8")
    }

    // Start second provider 1s later to keep steady alternation.
    Timer {
        id: startStagger
        interval: 1000
        running: true
        repeat: false
        onTriggered: pingGTimer.start()
    }

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

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Static grid lines are separate from the canvas to avoid redraw complexity.
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
                    // Cooperative avoids aggressively preempting the scene graph thread.
                    renderStrategy: Canvas.Cooperative

                    // One value per horizontal pixel; -1 marks gaps/timeouts.
                    property var cfLineBuf: []
                    property var gLineBuf: []
                    property int lineWidthPx: 0

                    // Fractional scroll accumulator for sub-pixel time progression.
                    property real scrollAcc: 0
                    property real lastTickTime: 0

                    function valueChanged(a, b, epsilon) {
                        if (a < 0 && b < 0) {
                            return false
                        }
                        return Math.abs(a - b) > epsilon
                    }

                    // Allocate fixed-size line buffers matching current drawable width.
                    function resetBuffers() {
                        var w = Math.max(0, Math.floor(width - 90))
                        lineWidthPx = w
                        cfLineBuf = new Array(w)
                        gLineBuf = new Array(w)
                        for (var i = 0; i < w; ++i) {
                            cfLineBuf[i] = -1
                            gLineBuf[i] = -1
                        }
                    }

                    // Scroll left by `count` pixels and append latest display sample values.
                    // Uses in-place shifting to avoid re-allocating arrays each tick.
                    function appendSamples(count) {
                        if (lineWidthPx <= 0 || count <= 0) {
                            return
                        }

                        if (count >= lineWidthPx) {
                            resetBuffers()
                            return
                        }

                        var kept = lineWidthPx - count
                        for (var i = 0; i < kept; ++i) {
                            cfLineBuf[i] = cfLineBuf[i + count]
                            gLineBuf[i] = gLineBuf[i + count]
                        }

                        var cfValue = (root.currentPingCf >= 0 && root.displayCf >= 0) ? root.displayCf : -1
                        var gValue = (root.currentPingG >= 0 && root.displayG >= 0) ? root.displayG : -1
                        for (var j = 0; j < count; ++j) {
                            cfLineBuf[kept + j] = cfValue
                            gLineBuf[kept + j] = gValue
                        }
                    }

                    onWidthChanged: resetBuffers()
                    Component.onCompleted: resetBuffers()

                    Timer {
                        id: chartUpdateTimer
                        interval: 100
                        repeat: true
                        running: chartCanvas.visible
                        onTriggered: {
                            var now = Date.now()
                            if (chartCanvas.lastTickTime === 0) {
                                chartCanvas.lastTickTime = now
                                chartCanvas.requestPaint()
                                return
                            }

                            var dt = (now - chartCanvas.lastTickTime) / 1000
                            chartCanvas.lastTickTime = now

                            var oldCf = root.displayCf
                            var oldG = root.displayG
                            var oldMax = root.displayMaxPing

                            // Keep line movement smooth between 2s ping updates.
                            if (root.currentPingCf >= 0 && root.cfStartTime > 0 && root.cfTo >= 0) {
                                var tCf = (now - root.cfStartTime) / root.easeDuration
                                root.displayCf = root.cfFrom + (root.cfTo - root.cfFrom) * root.smoothstep(tCf)
                            }
                            if (root.currentPingG >= 0 && root.gStartTime > 0 && root.gTo >= 0) {
                                var tG = (now - root.gStartTime) / root.easeDuration
                                root.displayG = root.gFrom + (root.gTo - root.gFrom) * root.smoothstep(tG)
                            }

                            // Y-axis adaptation is intentionally damped to prevent jitter.
                            root.displayMaxPing += (root.maxPing - root.displayMaxPing) * 0.15

                            var chartW = Math.max(0, Math.floor(chartCanvas.width - 90))
                            if (chartW !== chartCanvas.lineWidthPx) {
                                chartCanvas.resetBuffers()
                            }

                            var speed = chartW / root.windowSecs
                            chartCanvas.scrollAcc += speed * dt
                            var dx = Math.floor(chartCanvas.scrollAcc)
                            if (dx > 0) {
                                chartCanvas.scrollAcc -= dx
                                chartCanvas.appendSamples(dx)
                            }

                            // Repaint only when something visible changed.
                            if (dx > 0
                                    || chartCanvas.valueChanged(oldCf, root.displayCf, 0.02)
                                    || chartCanvas.valueChanged(oldG, root.displayG, 0.02)
                                    || chartCanvas.valueChanged(oldMax, root.displayMaxPing, 0.02)) {
                                chartCanvas.requestPaint()
                            }
                        }
                    }

                    Component.onDestruction: {
                        try { if (chartUpdateTimer) chartUpdateTimer.stop() } catch (e) {}
                    }

                    onPaint: {
                        var ctx = getContext("2d")
                        var w = width
                        var h = height
                        var padY = 12
                        var rightMargin = 90
                        var chartW = w - rightMargin
                        var chartH = h - padY * 2

                        ctx.clearRect(0, 0, w, h)

                        if (chartW <= 0 || chartH <= 0 || lineWidthPx <= 0) {
                            return
                        }

                        var maxVal = Math.max(1, root.displayMaxPing)

                        // Draw one polyline per provider, splitting at invalid gaps.
                        function drawBuf(buf, color) {
                            if (!buf || !buf.length) {
                                return
                            }
                            ctx.strokeStyle = color
                            ctx.lineWidth = 2
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"

                            var inPath = false
                            ctx.beginPath()
                            for (var x = 0; x < buf.length; ++x) {
                                var v = buf[x]
                                if (v === null || v === undefined || isNaN(v) || v < 0) {
                                    inPath = false
                                    continue
                                }
                                var y = padY + chartH - (Math.min(v, maxVal) / maxVal) * chartH
                                if (!inPath) {
                                    ctx.moveTo(x, y)
                                    inPath = true
                                } else {
                                    ctx.lineTo(x, y)
                                }
                            }
                            ctx.stroke()
                        }

                        drawBuf(cfLineBuf, root.cfColor)
                        drawBuf(gLineBuf, root.gColor)

                        var globalMax = -Infinity
                        var globalMin = Infinity
                        var maxIndex = -1
                        var minIndex = -1

                        // One pass across both buffers for global min/max markers.
                        function scanBuf(buf) {
                            for (var i = 0; i < buf.length; ++i) {
                                var v = buf[i]
                                if (v < 0 || isNaN(v)) {
                                    continue
                                }
                                if (v > globalMax) {
                                    globalMax = v
                                    maxIndex = i
                                }
                                if (v < globalMin) {
                                    globalMin = v
                                    minIndex = i
                                }
                            }
                        }

                        scanBuf(cfLineBuf)
                        scanBuf(gLineBuf)

                        var extremeColor = "#ffdd44"
                        var extremeFont = Kirigami.Theme.defaultFont.pixelSize * 1.2
                        var bgPad = 3

                        // Draw highlighted min/max point with a compact value bubble.
                        function drawExtremeLabel(dotX, dotY, val, offsetY) {
                            ctx.fillStyle = extremeColor
                            ctx.beginPath()
                            ctx.arc(dotX, dotY, 4, 0, 2 * Math.PI)
                            ctx.fill()

                            ctx.font = extremeFont + "px sans-serif"
                            ctx.textBaseline = "middle"
                            var y = Math.max(extremeFont / 2 + 2, Math.min(h - extremeFont / 2 - 2, dotY + offsetY))
                            var text = val.toFixed(1) + " ms"
                            var tw = ctx.measureText(text).width
                            var x = dotX + 8
                            if (x + tw + bgPad > chartW - 10) {
                                x = dotX - 8 - tw
                            }

                            ctx.fillStyle = Qt.rgba(0, 0, 0, 0.6)
                            ctx.fillRect(x - bgPad, y - extremeFont / 2 - bgPad, tw + bgPad * 2, extremeFont + bgPad * 2)
                            ctx.fillStyle = extremeColor
                            ctx.fillText(text, x, y)
                        }

                        if (maxIndex >= 0) {
                            var maxY = padY + chartH - (Math.min(globalMax, maxVal) / maxVal) * chartH
                            drawExtremeLabel(maxIndex, maxY, globalMax, -10)
                        }
                        if (minIndex >= 0 && globalMax - globalMin >= 1) {
                            var minY = padY + chartH - (Math.min(globalMin, maxVal) / maxVal) * chartH
                            drawExtremeLabel(minIndex, minY, globalMin, -10)
                        }

                        var cfY = (root.displayCf >= 0) ? padY + chartH - (Math.min(root.displayCf, maxVal) / maxVal) * chartH : -1
                        var gY = (root.displayG >= 0) ? padY + chartH - (Math.min(root.displayG, maxVal) / maxVal) * chartH : -1

                        var fontSize = Kirigami.Theme.defaultFont.pixelSize * 1.5
                        var minGap = fontSize + 4
                        var cfLabelY = cfY
                        var gLabelY = gY

                        // Keep live labels readable when values are close together.
                        if (cfY >= 0 && gY >= 0 && Math.abs(cfY - gY) < minGap) {
                            var mid = (cfY + gY) / 2
                            cfLabelY = mid - minGap / 2
                            gLabelY = mid + minGap / 2
                            if (cfLabelY < fontSize) {
                                cfLabelY = fontSize
                                gLabelY = cfLabelY + minGap
                            }
                            if (gLabelY > h - 2) {
                                gLabelY = h - 2
                                cfLabelY = gLabelY - minGap
                            }
                        }

                        ctx.save()
                        ctx.font = fontSize + "px sans-serif"
                        ctx.textBaseline = "middle"

                        if (cfY >= 0) {
                            ctx.fillStyle = "" + root.cfColor
                            ctx.beginPath()
                            ctx.arc(chartW, cfY, 5, 0, 2 * Math.PI)
                            ctx.fill()
                            ctx.fillText(root.displayCf.toFixed(1) + " ms", chartW + 10, cfLabelY)
                        }

                        if (gY >= 0) {
                            ctx.fillStyle = "" + root.gColor
                            ctx.beginPath()
                            ctx.arc(chartW, gY, 5, 0, 2 * Math.PI)
                            ctx.fill()
                            ctx.fillText(root.displayG.toFixed(1) + " ms", chartW + 10, gLabelY)
                        }

                        ctx.restore()
                    }
                }
            }
        }
    }

    Component.onDestruction: {
        // Explicit timer stops prevent work from continuing during teardown.
        try { if (pingCfTimer) pingCfTimer.stop() } catch (e) {}
        try { if (pingGTimer) pingGTimer.stop() } catch (e) {}
        try { if (startStagger) startStagger.stop() } catch (e) {}
    }
}
