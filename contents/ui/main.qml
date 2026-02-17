import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
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
    property real maxPing: 100
    property real displayMaxPing: 100

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

    readonly property real windowSecs: 30
    readonly property int gridIntervals: 2
    readonly property int gridLineCount: gridIntervals + 1

    readonly property color cfColor: Kirigami.Theme.positiveTextColor
    readonly property color gColor: Kirigami.Theme.negativeTextColor

    property bool shuttingDown: false

    // One persistent ping process per host, writing to per-widget temp logs.
    readonly property string sessionToken: "" + Math.floor(Math.random() * 1000000000) + "-" + Date.now()
    readonly property string cfLogPath: "/tmp/plasma-pingmonitor-cf-" + sessionToken + ".log"
    readonly property string gLogPath: "/tmp/plasma-pingmonitor-g-" + sessionToken + ".log"
    readonly property string startCfCmd: "sh -c 'ping -n -O -i 2 -W 1 1.1.1.1 > " + cfLogPath + " 2>&1 & echo $!'"
    readonly property string startGCmd: "sh -c 'ping -n -O -i 2 -W 1 8.8.8.8 > " + gLogPath + " 2>&1 & echo $!'"
    readonly property string pollCfCmd: "tail -n 4 " + cfLogPath
    readonly property string pollGCmd: "tail -n 4 " + gLogPath
    property int cfPid: -1
    property int gPid: -1
    property string checkCfCmd: ""
    property string checkGCmd: ""
    property string lastPingReceivedText: "--:--:--"

    function processCheckCmd(pid) {
        return "sh -c 'kill -0 " + pid + " 2>/dev/null && echo up || echo down'"
    }

    function requestStartCf() {
        if (!shuttingDown) {
            executable.connectSource(startCfCmd)
        }
    }

    function requestStartG() {
        if (!shuttingDown) {
            executable.connectSource(startGCmd)
        }
    }

    function formatHms(ms) {
        if (ms <= 0) {
            return "--:--:--"
        }
        var d = new Date(ms)
        function two(n) { return (n < 10 ? "0" : "") + n }
        return two(d.getHours()) + ":" + two(d.getMinutes()) + ":" + two(d.getSeconds())
    }

    // Axis scale: 2 chunks (3 lines), at least 25ms per chunk (minimum range 0..100ms).
    function axisStepMs() {
        var base = Math.max(100, displayMaxPing)
        var step = Math.ceil((base / gridIntervals) / 25) * 25
        return Math.max(50, step)
    }

    function axisTopMs() {
        return axisStepMs() * gridIntervals
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
            } else {
                cfFrom = value
                cfTo = value
                cfStartTime = now
                currentPingCf = value
                displayCf = value
                lastPingReceivedText = formatHms(now)
            }
        } else {
            if (value < 0) {
                currentPingG = -1
                displayG = -1
                gFrom = -1
                gTo = -1
            } else {
                gFrom = value
                gTo = value
                gStartTime = now
                currentPingG = value
                displayG = value
                lastPingReceivedText = formatHms(now)
            }
        }

    }

    function processPingLine(line, isCf) {
        if (!line || line.length === 0) {
            return false
        }

        var match = line.match(/time[=<]([\d.]+)\s*ms/)
        if (match) {
            applyPing(isCf, parseFloat(match[1]))
            return true
        }

        var lower = line.toLowerCase()
        if (lower.indexOf("no answer yet") !== -1
                || lower.indexOf("timeout") !== -1
                || lower.indexOf("unreachable") !== -1
                || lower.indexOf("100% packet loss") !== -1) {
            applyPing(isCf, -1)
            return true
        }
        return false
    }

    function processPingSnapshot(stdout, isCf) {
        var lines = stdout.split(/\r?\n/)
        for (var i = lines.length - 1; i >= 0; --i) {
            if (processPingLine(lines[i], isCf)) {
                return
            }
        }
    }

    function parsePid(stdout) {
        var m = stdout.match(/(\d+)\s*$/)
        if (!m) {
            return -1
        }
        return parseInt(m[1])
    }

    // Plasma executable engine runs ping commands asynchronously.
    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            var stdout = data["stdout"] || ""
            if (source === root.startCfCmd) {
                root.cfPid = root.parsePid(stdout)
                root.checkCfCmd = (root.cfPid > 0) ? root.processCheckCmd(root.cfPid) : ""
            } else if (source === root.startGCmd) {
                root.gPid = root.parsePid(stdout)
                root.checkGCmd = (root.gPid > 0) ? root.processCheckCmd(root.gPid) : ""
            } else if (source === root.pollCfCmd) {
                root.processPingSnapshot(stdout, true)
            } else if (source === root.pollGCmd) {
                root.processPingSnapshot(stdout, false)
            } else if (source === root.checkCfCmd) {
                if (stdout.indexOf("up") === -1) {
                    root.cfPid = -1
                    root.checkCfCmd = ""
                    root.requestStartCf()
                }
            } else if (source === root.checkGCmd) {
                if (stdout.indexOf("up") === -1) {
                    root.gPid = -1
                    root.checkGCmd = ""
                    root.requestStartG()
                }
            }
            executable.disconnectSource(source)
        }
    }

    // Start both persistent ping streams once (second source slightly staggered).
    Timer {
        id: startCfProcess
        interval: 1
        running: true
        repeat: false
        triggeredOnStart: true
        onTriggered: root.requestStartCf()
    }

    Timer {
        id: startGProcess
        interval: 1000
        running: true
        repeat: false
        triggeredOnStart: false
        onTriggered: root.requestStartG()
    }

    // Poll latest output from each long-running ping process.
    Timer {
        id: pollCfTimer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (root.cfPid > 0) executable.connectSource(root.pollCfCmd)
    }

    Timer {
        id: pollGTimer
        interval: 2000
        running: false
        repeat: true
        triggeredOnStart: false
        onTriggered: if (root.gPid > 0) executable.connectSource(root.pollGCmd)
    }

    Timer {
        id: startPollG
        interval: 1000
        running: true
        repeat: false
        onTriggered: pollGTimer.start()
    }

    // Recover from failed starts or dead ping processes (e.g., applet starts offline).
    Timer {
        id: processWatchdog
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.shuttingDown) {
                return
            }
            if (root.cfPid <= 0) {
                root.requestStartCf()
            } else if (root.checkCfCmd.length > 0) {
                executable.connectSource(root.checkCfCmd)
            }
            if (root.gPid <= 0) {
                root.requestStartG()
            } else if (root.checkGCmd.length > 0) {
                executable.connectSource(root.checkGCmd)
            }
        }
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

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.smallSpacing * 2
            anchors.rightMargin: Kirigami.Units.smallSpacing * 2
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.gridUnit

                RowLayout {
                    spacing: 4
                    Rectangle { width: 12; height: 12; radius: 6; color: root.cfColor }
                    Text {
                        text: "1.1.1.1"
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 0.75
                        opacity: 0.8
                    }
                }

                RowLayout {
                    spacing: 4
                    Rectangle { width: 12; height: 12; radius: 6; color: root.gColor }
                    Text {
                        text: "8.8.8.8"
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 0.75
                        opacity: 0.8
                    }
                }

                Item { Layout.fillWidth: true }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Static grid lines remain independent from the dynamic chart layer.
                Repeater {
                    model: root.gridLineCount
                    Item {
                        required property int index
                        x: 0
                        y: 12 + (parent.height - 24) * index / root.gridIntervals
                        width: parent.width
                        height: 1

                        Rectangle {
                            width: parent.width - 90
                            height: 1
                            color: Kirigami.Theme.textColor
                            opacity: 0.1
                        }

                        Text {
                            x: (parent.width - 90) - width - 4
                            y: -height
                            text: ((root.gridIntervals - index) * root.axisStepMs()) + " ms"
                            color: Qt.rgba(1, 1, 1, 0.45)
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 0.85
                            opacity: 1
                        }
                    }
                }

                Item {
                    id: chartView
                    anchors.fill: parent

                    readonly property real padY: 12
                    readonly property real rightMargin: 90
                    readonly property real chartW: Math.max(0, width - rightMargin)
                    readonly property real chartH: Math.max(0, height - padY * 2)
                    // 2px sampling halves geometry work while remaining visually smooth.
                    readonly property real sampleStepPx: 2

                    property var cfSamples: []
                    property var gSamples: []
                    property int pointCount: 0
                    property int cfValidPoints: 0
                    property int gValidPoints: 0
                    property real scrollAccPoints: 0
                    property real lastTickTime: 0
                    property real lastPathScale: -1

                    property string cfPath: ""
                    property string gPath: ""

                    property real cachedMax: -1
                    property real cachedMin: -1
                    property int cachedMaxIndex: -1
                    property int cachedMinIndex: -1
                    property real cachedCfY: -1
                    property real cachedGY: -1
                    property real cachedCfLabelY: -1
                    property real cachedGLabelY: -1
                    property real cachedMaxY: -1
                    property real cachedMinY: -1
                    readonly property bool idleMode: (cfValidPoints === 0
                            && gValidPoints === 0
                            && root.currentPingCf < 0
                            && root.currentPingG < 0
                            && root.displayCf < 0
                            && root.displayG < 0)

                    function valueChanged(a, b, epsilon) {
                        if (a < 0 && b < 0) {
                            return false
                        }
                        return Math.abs(a - b) > epsilon
                    }

                    function computeY(v, maxVal) {
                        if (v < 0 || chartH <= 0) {
                            return -1
                        }
                        return padY + chartH - (Math.min(v, maxVal) / maxVal) * chartH
                    }

                    function ensureBuffers() {
                        var needed = Math.max(8, Math.floor(chartW / sampleStepPx))
                        if (needed === pointCount && cfSamples.length === needed && gSamples.length === needed) {
                            return false
                        }
                        pointCount = needed
                        cfSamples = new Array(needed)
                        gSamples = new Array(needed)
                        for (var i = 0; i < needed; ++i) {
                            cfSamples[i] = -1
                            gSamples[i] = -1
                        }
                        cfValidPoints = 0
                        gValidPoints = 0
                        scrollAccPoints = 0
                        return true
                    }

                    function appendSamples(count) {
                        if (pointCount <= 0 || count <= 0) {
                            return false
                        }
                        if (count >= pointCount) {
                            ensureBuffers()
                            return true
                        }

                        var kept = pointCount - count
                        var removedCf = 0
                        var removedG = 0
                        for (var r = 0; r < count; ++r) {
                            if (cfSamples[r] >= 0 && !isNaN(cfSamples[r])) {
                                removedCf += 1
                            }
                            if (gSamples[r] >= 0 && !isNaN(gSamples[r])) {
                                removedG += 1
                            }
                        }
                        for (var i = 0; i < kept; ++i) {
                            cfSamples[i] = cfSamples[i + count]
                            gSamples[i] = gSamples[i + count]
                        }

                        var cfValue = (root.currentPingCf >= 0 && root.displayCf >= 0) ? root.displayCf : -1
                        var gValue = (root.currentPingG >= 0 && root.displayG >= 0) ? root.displayG : -1
                        for (var j = 0; j < count; ++j) {
                            cfSamples[kept + j] = cfValue
                            gSamples[kept + j] = gValue
                        }
                        var addedCf = (cfValue >= 0) ? count : 0
                        var addedG = (gValue >= 0) ? count : 0
                        cfValidPoints = Math.max(0, cfValidPoints - removedCf + addedCf)
                        gValidPoints = Math.max(0, gValidPoints - removedG + addedG)
                        return true
                    }

                    function rebuildPathsAndExtrema() {
                        var maxVal = Math.max(1, root.axisTopMs())
                        var cfOut = ""
                        var gOut = ""
                        var cfStarted = false
                        var gStarted = false
                        var localMax = -Infinity
                        var localMin = Infinity
                        var localMaxIndex = -1
                        var localMinIndex = -1

                        for (var i = 0; i < pointCount; ++i) {
                            var x = i * sampleStepPx
                            var cfv = cfSamples[i]
                            var gv = gSamples[i]

                            if (cfv >= 0 && !isNaN(cfv)) {
                                var cfy = computeY(cfv, maxVal)
                                if (cfStarted) {
                                    cfOut += " L " + x + " " + cfy
                                } else {
                                    cfOut += "M " + x + " " + cfy
                                    cfStarted = true
                                }
                                if (cfv > localMax) {
                                    localMax = cfv
                                    localMaxIndex = i
                                }
                                if (cfv < localMin) {
                                    localMin = cfv
                                    localMinIndex = i
                                }
                            } else {
                                cfStarted = false
                            }

                            if (gv >= 0 && !isNaN(gv)) {
                                var gy = computeY(gv, maxVal)
                                if (gStarted) {
                                    gOut += " L " + x + " " + gy
                                } else {
                                    gOut += "M " + x + " " + gy
                                    gStarted = true
                                }
                                if (gv > localMax) {
                                    localMax = gv
                                    localMaxIndex = i
                                }
                                if (gv < localMin) {
                                    localMin = gv
                                    localMinIndex = i
                                }
                            } else {
                                gStarted = false
                            }
                        }

                        cfPath = cfOut
                        gPath = gOut
                        cachedMaxIndex = localMaxIndex
                        cachedMinIndex = localMinIndex
                        cachedMax = (localMaxIndex >= 0) ? localMax : -1
                        cachedMin = (localMinIndex >= 0) ? localMin : -1
                        cachedMaxY = (cachedMaxIndex >= 0) ? computeY(cachedMax, maxVal) : -1
                        cachedMinY = (cachedMinIndex >= 0) ? computeY(cachedMin, maxVal) : -1
                        lastPathScale = maxVal
                    }

                    function updateLiveLabels() {
                        var maxVal = Math.max(1, root.axisTopMs())
                        var cfY = computeY(root.displayCf, maxVal)
                        var gY = computeY(root.displayG, maxVal)
                        var fontSize = Kirigami.Theme.defaultFont.pixelSize * 1.5
                        var minGap = fontSize + 4
                        var cfLabelY = cfY
                        var gLabelY = gY

                        if (cfY >= 0 && gY >= 0 && Math.abs(cfY - gY) < minGap) {
                            var mid = (cfY + gY) / 2
                            cfLabelY = mid - minGap / 2
                            gLabelY = mid + minGap / 2
                            if (cfLabelY < fontSize) {
                                cfLabelY = fontSize
                                gLabelY = cfLabelY + minGap
                            }
                            if (gLabelY > height - 2) {
                                gLabelY = height - 2
                                cfLabelY = gLabelY - minGap
                            }
                        }

                        cachedCfY = cfY
                        cachedGY = gY
                        cachedCfLabelY = cfLabelY
                        cachedGLabelY = gLabelY
                    }

                    onWidthChanged: {
                        if (ensureBuffers()) {
                            rebuildPathsAndExtrema()
                        }
                    }

                    onHeightChanged: {
                        ensureBuffers()
                        rebuildPathsAndExtrema()
                        updateLiveLabels()
                    }

                    Component.onCompleted: {
                        ensureBuffers()
                        rebuildPathsAndExtrema()
                        updateLiveLabels()
                    }

                    Timer {
                        id: chartUpdateTimer
                        interval: chartView.idleMode ? 500 : 50
                        repeat: true
                        running: chartView.visible
                        onTriggered: {
                            var now = Date.now()
                            if (chartView.lastTickTime === 0) {
                                chartView.lastTickTime = now
                                return
                            }

                            var dt = (now - chartView.lastTickTime) / 1000
                            chartView.lastTickTime = now
                            if (chartView.idleMode) {
                                return
                            }
                            var oldCf = root.displayCf
                            var oldG = root.displayG
                            var oldAxisTop = root.axisTopMs()

                            var maxDelta = root.maxPing - root.displayMaxPing
                            if (Math.abs(maxDelta) > 0.25) {
                                root.displayMaxPing += maxDelta * 0.2
                            } else {
                                root.displayMaxPing = root.maxPing
                            }

                            var rebuilt = false
                            if (chartView.ensureBuffers()) {
                                rebuilt = true
                            }

                            var pointsPerSec = (chartView.pointCount > 0) ? (chartView.pointCount / root.windowSecs) : 0
                            chartView.scrollAccPoints += pointsPerSec * dt
                            var ds = Math.floor(chartView.scrollAccPoints)
                            if (ds > 0) {
                                chartView.scrollAccPoints -= ds
                                rebuilt = chartView.appendSamples(ds) || rebuilt
                            }

                            var newAxisTop = root.axisTopMs()
                            var axisChanged = chartView.valueChanged(oldAxisTop, newAxisTop, 0.1)

                            if (rebuilt || axisChanged) {
                                chartView.rebuildPathsAndExtrema()
                            }

                            var visibleMax = chartView.cachedMax
                            if (root.displayCf > visibleMax) {
                                visibleMax = root.displayCf
                            }
                            if (root.displayG > visibleMax) {
                                visibleMax = root.displayG
                            }
                            if (visibleMax < 0) {
                                visibleMax = 100
                            }
                            root.maxPing = Math.max(100, Math.ceil(visibleMax / 25) * 25)

                            if (rebuilt
                                    || axisChanged
                                    || chartView.valueChanged(oldCf, root.displayCf, 0.2)
                                    || chartView.valueChanged(oldG, root.displayG, 0.2)) {
                                chartView.updateLiveLabels()
                            }
                        }
                    }

                    Component.onDestruction: {
                        try { if (chartUpdateTimer) chartUpdateTimer.stop() } catch (e) {}
                    }

                    Item {
                        id: blurScene
                        anchors.fill: parent
                        visible: !chartView.idleMode
                    }

                    Shape {
                        id: chartShape
                        parent: blurScene
                        anchors.fill: parent
                        antialiasing: true
                        preferredRendererType: Shape.CurveRenderer
                        layer.enabled: true
                        layer.smooth: true
                        layer.samples: 4

                        ShapePath {
                            strokeColor: root.cfColor
                            strokeWidth: 2
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathSvg { path: chartView.cfPath }
                        }

                        ShapePath {
                            strokeColor: root.gColor
                            strokeWidth: 2
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathSvg { path: chartView.gPath }
                        }
                    }

                    Rectangle {
                        parent: blurScene
                        visible: chartView.cachedMaxIndex >= 0 && chartView.cachedMaxY >= 0
                        width: 8
                        height: 8
                        radius: 4
                        color: "#ffdd44"
                        x: chartView.cachedMaxIndex * chartView.sampleStepPx - width / 2
                        y: chartView.cachedMaxY - height / 2
                    }

                    Rectangle {
                        id: maxBubble
                        visible: !chartView.idleMode && chartView.cachedMaxIndex >= 0 && chartView.cachedMaxY >= 0
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.08)
                        width: maxText.implicitWidth + 6
                        height: maxText.implicitHeight + 4
                        property real dotX: chartView.cachedMaxIndex * chartView.sampleStepPx
                        x: (dotX + 8 + width > chartView.chartW - 10) ? Math.max(0, dotX - 8 - width) : dotX + 8
                        y: Math.max(2, Math.min(chartView.height - height - 2, chartView.cachedMaxY - 10 - height / 2))
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.2)

                        Text {
                            id: maxText
                            anchors.centerIn: parent
                            color: "#ffdd44"
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.2
                            font.bold: true
                            text: chartView.cachedMax >= 0 ? chartView.cachedMax.toFixed(1) + " ms" : ""
                        }
                    }

                    Rectangle {
                        parent: blurScene
                        visible: chartView.cachedMinIndex >= 0 && chartView.cachedMinY >= 0 && chartView.cachedMax - chartView.cachedMin >= 1
                        width: 8
                        height: 8
                        radius: 4
                        color: "#ffdd44"
                        x: chartView.cachedMinIndex * chartView.sampleStepPx - width / 2
                        y: chartView.cachedMinY - height / 2
                    }

                    Rectangle {
                        id: minBubble
                        visible: !chartView.idleMode && chartView.cachedMinIndex >= 0 && chartView.cachedMinY >= 0 && chartView.cachedMax - chartView.cachedMin >= 1
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.08)
                        width: minText.implicitWidth + 6
                        height: minText.implicitHeight + 4
                        property real dotX: chartView.cachedMinIndex * chartView.sampleStepPx
                        x: (dotX + 8 + width > chartView.chartW - 10) ? Math.max(0, dotX - 8 - width) : dotX + 8
                        y: Math.max(2, Math.min(chartView.height - height - 2, chartView.cachedMinY - 10 - height / 2))
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.2)

                        Text {
                            id: minText
                            anchors.centerIn: parent
                            color: "#ffdd44"
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.2
                            font.bold: true
                            text: chartView.cachedMin >= 0 ? chartView.cachedMin.toFixed(1) + " ms" : ""
                        }
                    }

                    Rectangle {
                        parent: blurScene
                        visible: chartView.cachedCfY >= 0
                        width: 10
                        height: 10
                        radius: 5
                        color: root.cfColor
                        x: chartView.chartW - width / 2
                        y: chartView.cachedCfY - height / 2
                    }

                    Text {
                        parent: blurScene
                        visible: chartView.cachedCfY >= 0
                        text: root.displayCf.toFixed(1) + " ms"
                        color: root.cfColor
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.5
                        x: chartView.chartW + 10
                        y: chartView.cachedCfLabelY - height / 2
                    }

                    Rectangle {
                        parent: blurScene
                        visible: chartView.cachedGY >= 0
                        width: 10
                        height: 10
                        radius: 5
                        color: root.gColor
                        x: chartView.chartW - width / 2
                        y: chartView.cachedGY - height / 2
                    }

                    Text {
                        parent: blurScene
                        visible: chartView.cachedGY >= 0
                        text: root.displayG.toFixed(1) + " ms"
                        color: root.gColor
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.5
                        x: chartView.chartW + 10
                        y: chartView.cachedGLabelY - height / 2
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.ceil(font.pixelSize * 1.05)
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
                text: "last ping received: " + root.lastPingReceivedText
                color: Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 0.75
                opacity: 1
            }
        }
    }

    Component.onDestruction: {
        // Explicitly stop/teardown long-lived ping sources and timers.
        shuttingDown = true
        try { if (startCfProcess) startCfProcess.stop() } catch (e) {}
        try { if (startGProcess) startGProcess.stop() } catch (e) {}
        try { if (pollCfTimer) pollCfTimer.stop() } catch (e) {}
        try { if (pollGTimer) pollGTimer.stop() } catch (e) {}
        try { if (startPollG) startPollG.stop() } catch (e) {}
        try { if (processWatchdog) processWatchdog.stop() } catch (e) {}
        try { executable.disconnectSource(startCfCmd) } catch (e) {}
        try { executable.disconnectSource(startGCmd) } catch (e) {}
        try { executable.disconnectSource(pollCfCmd) } catch (e) {}
        try { executable.disconnectSource(pollGCmd) } catch (e) {}
        if (cfPid > 0) {
            try { executable.connectSource("sh -c 'kill " + cfPid + " 2>/dev/null || true'") } catch (e) {}
        }
        if (gPid > 0) {
            try { executable.connectSource("sh -c 'kill " + gPid + " 2>/dev/null || true'") } catch (e) {}
        }
        try { executable.connectSource("sh -c 'rm -f " + cfLogPath + " " + gLogPath + " 2>/dev/null || true'") } catch (e) {}
    }
}
