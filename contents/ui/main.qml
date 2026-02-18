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
    property real currentCloudflarePing: -1
    property real currentGooglePing: -1
    property real currentGatewayPing: -1

    // Dynamic Y-scale target and eased display value for the chart.
    property real maxPing: 100
    property real displayMaxPing: 100

    // Smoothed values currently rendered in the chart/labels.
    property real displayCloudflarePing: -1
    property real displayGooglePing: -1
    property real displayGatewayPing: -1

    // Easing state for each provider.
    property real cloudflareFrom: -1
    property real cloudflareTo: -1
    property real cloudflareStartTime: 0
    property real googleFrom: -1
    property real googleTo: -1
    property real googleStartTime: 0
    property real gatewayFrom: -1
    property real gatewayTo: -1
    property real gatewayStartTime: 0

    readonly property real windowSecs: 30
    readonly property int gridIntervals: 2
    readonly property int gridLineCount: gridIntervals + 1

    readonly property color cloudflareColor: Kirigami.Theme.positiveTextColor
    readonly property color googleColor: Kirigami.Theme.negativeTextColor
    readonly property color gatewayColor: "#4aa3ff"

    property bool shuttingDown: false

    // One-shot ping commands, launched by timers.
    readonly property string gatewayQueryCmd: "sh -c 'ip route show default 2>/dev/null | awk '\\''/default/ {print $3; exit}'\\'''"
    property string gatewayIp: ""
    property bool gatewayOnline: false
    readonly property string cloudflarePingCmd: "ping -n -c 1 -W 1 1.1.1.1"
    readonly property string googlePingCmd: "ping -n -c 1 -W 1 8.8.8.8"
    property string gatewayPingCmd: gatewayIp.length > 0 ? "ping -n -c 1 -W 1 " + gatewayIp : ""
    property bool cloudflarePingInFlight: false
    property bool googlePingInFlight: false
    property bool gatewayPingInFlight: false
    property string gatewayPingCmdInFlight: ""
    property int pingCycleIndex: 0
    property string lastPingReceivedText: "--:--:--"

    function requestCloudflarePing() {
        if (cloudflarePingInFlight) {
            return
        }
        if (!shuttingDown) {
            cloudflarePingInFlight = true
            executable.connectSource(cloudflarePingCmd)
        }
    }

    function requestGooglePing() {
        if (googlePingInFlight) {
            return
        }
        if (!shuttingDown) {
            googlePingInFlight = true
            executable.connectSource(googlePingCmd)
        }
    }

    function requestGatewayPing() {
        if (gatewayPingInFlight) {
            return
        }
        if (!shuttingDown && gatewayIp.length > 0 && gatewayPingCmd.length > 0) {
            gatewayPingInFlight = true
            gatewayPingCmdInFlight = gatewayPingCmd
            executable.connectSource(gatewayPingCmdInFlight)
        }
    }

    function requestNextPing() {
        var target = pingCycleIndex
        pingCycleIndex = (pingCycleIndex + 1) % 3

        if (target === 0) {
            requestCloudflarePing()
        } else if (target === 1) {
            requestGooglePing()
        } else {
            if (gatewayIp.length > 0) {
                requestGatewayPing()
            } else {
                applyPing("gateway", -1)
            }
        }
    }

    function updateGatewayIp(newIp) {
        var ip = (newIp || "").trim()
        if (ip === gatewayIp) {
            return
        }
        gatewayIp = ip
        if (gatewayIp.length === 0) {
            applyPing("gateway", -1)
        } else if (gatewayIp.length > 0) {
            gatewayOnline = false
            currentGatewayPing = -1
            displayGatewayPing = -1
            gatewayFrom = -1
            gatewayTo = -1
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
    function applyPing(target, ping) {
        var value = (ping >= 0 && ping < 1000) ? ping : -1
        var now = Date.now()

        if (target === "cloudflare") {
            if (value < 0) {
                currentCloudflarePing = -1
                displayCloudflarePing = -1
                cloudflareFrom = -1
                cloudflareTo = -1
            } else {
                cloudflareFrom = value
                cloudflareTo = value
                cloudflareStartTime = now
                currentCloudflarePing = value
                displayCloudflarePing = value
                lastPingReceivedText = formatHms(now)
            }
        } else if (target === "google") {
            if (value < 0) {
                currentGooglePing = -1
                displayGooglePing = -1
                googleFrom = -1
                googleTo = -1
            } else {
                googleFrom = value
                googleTo = value
                googleStartTime = now
                currentGooglePing = value
                displayGooglePing = value
                lastPingReceivedText = formatHms(now)
            }
        } else if (target === "gateway") {
            if (value < 0) {
                currentGatewayPing = -1
                displayGatewayPing = -1
                gatewayFrom = -1
                gatewayTo = -1
                gatewayOnline = false
            } else {
                gatewayFrom = value
                gatewayTo = value
                gatewayStartTime = now
                currentGatewayPing = value
                displayGatewayPing = value
                gatewayOnline = true
            }
        }

    }

    function processPingLine(line, target) {
        if (!line || line.length === 0) {
            return false
        }

        var match = line.match(/time[=<]([\d.]+)\s*ms/)
        if (match) {
            applyPing(target, parseFloat(match[1]))
            return true
        }

        var lower = line.toLowerCase()
        if (lower.indexOf("no answer yet") !== -1
                || lower.indexOf("timeout") !== -1
                || lower.indexOf("unreachable") !== -1
                || lower.indexOf("100% packet loss") !== -1) {
            applyPing(target, -1)
            return true
        }
        return false
    }

    function processPingSnapshot(stdout, target) {
        var lines = stdout.split(/\r?\n/)
        for (var i = lines.length - 1; i >= 0; --i) {
            var line = lines[i]
            if (!line || line.length === 0) {
                continue
            }
            var m = line.match(/time[=<]([\d.]+)\s*ms/)
            var l = line.toLowerCase()
            var timeoutish = (l.indexOf("no answer yet") !== -1
                    || l.indexOf("timeout") !== -1
                    || l.indexOf("unreachable") !== -1
                    || l.indexOf("100% packet loss") !== -1)
            if (!m && !timeoutish) {
                continue
            }

            if (processPingLine(line, target)) {
                return true
            }
        }
        return false
    }

    // Plasma executable engine runs ping commands asynchronously.
    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            var stdout = data["stdout"] || ""
            if (source === root.gatewayQueryCmd) {
                root.updateGatewayIp(stdout)
            } else if (source === root.cloudflarePingCmd) {
                root.cloudflarePingInFlight = false
                if (!root.processPingSnapshot(stdout, "cloudflare")) {
                    root.applyPing("cloudflare", -1)
                }
            } else if (source === root.googlePingCmd) {
                root.googlePingInFlight = false
                if (!root.processPingSnapshot(stdout, "google")) {
                    root.applyPing("google", -1)
                }
            } else if (source === root.gatewayPingCmdInFlight) {
                root.gatewayPingInFlight = false
                var requestedSource = root.gatewayPingCmdInFlight
                root.gatewayPingCmdInFlight = ""
                if (requestedSource === root.gatewayPingCmd) {
                    if (!root.processPingSnapshot(stdout, "gateway")) {
                        root.applyPing("gateway", -1)
                    }
                }
            }
            executable.disconnectSource(source)
        }
    }

    // Refresh gateway IP periodically to keep route changes in sync.
    Timer {
        id: gatewayRefreshTimer
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: executable.connectSource(root.gatewayQueryCmd)
    }

    // One-shot ping loop: one provider ping per second (3-second full cycle).
    Timer {
        id: pingCycleTimer
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.requestNextPing()
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
                    Rectangle { width: 12; height: 12; radius: 6; color: root.cloudflareColor }
                    Text {
                        text: "1.1.1.1"
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 0.75
                        opacity: 0.8
                    }
                }

                RowLayout {
                    spacing: 4
                    Rectangle { width: 12; height: 12; radius: 6; color: root.googleColor }
                    Text {
                        text: "8.8.8.8"
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 0.75
                        opacity: 0.8
                    }
                }

                RowLayout {
                    visible: root.gatewayIp.length > 0
                    spacing: 4
                    Rectangle {
                        width: 12
                        height: 12
                        radius: 6
                        color: root.gatewayColor
                        visible: root.gatewayOnline
                    }
                    Text {
                        text: root.gatewayIp
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
                    readonly property real rightMargin: 58
                    readonly property real chartW: Math.max(0, width - rightMargin)
                    readonly property real chartH: Math.max(0, height - padY * 2)
                    readonly property real publicRealtimeLabelFontSize: Kirigami.Theme.defaultFont.pixelSize * 1.3
                    // Gateway has one extra character (e.g. "1.1ms"), so scale down to match public-label width.
                    readonly property real gatewayRealtimeLabelFontSize: publicRealtimeLabelFontSize * 0.8
                    // 2px sampling halves geometry work while remaining visually smooth.
                    readonly property real sampleStepPx: 2

                    property var cloudflareSamples: []
                    property var googleSamples: []
                    property var gatewaySamples: []
                    property int pointCount: 0
                    property int cloudflareValidPoints: 0
                    property int googleValidPoints: 0
                    property int gatewayValidPoints: 0
                    property real scrollAccPoints: 0
                    property real lastTickTime: 0
                    property real lastPathScale: -1

                    property string cloudflarePath: ""
                    property string googlePath: ""
                    property string gatewayPath: ""

                    property real cachedMax: -1
                    property real cachedMin: -1
                    property int cachedMaxIndex: -1
                    property int cachedMinIndex: -1
                    property real cachedCloudflareY: -1
                    property real cachedGoogleY: -1
                    property real cachedGatewayY: -1
                    property real cachedCloudflareLabelY: -1
                    property real cachedGoogleLabelY: -1
                    property real cachedGatewayLabelY: -1
                    property real cachedCloudflareLabelValue: -1
                    property real cachedGoogleLabelValue: -1
                    property real cachedGatewayLabelValue: -1
                    property real cachedMaxY: -1
                    property real cachedMinY: -1
                    readonly property bool idleMode: (cloudflareValidPoints === 0
                            && googleValidPoints === 0
                            && gatewayValidPoints === 0
                            && root.currentCloudflarePing < 0
                            && root.currentGooglePing < 0
                            && root.currentGatewayPing < 0
                            && root.displayCloudflarePing < 0
                            && root.displayGooglePing < 0
                            && root.displayGatewayPing < 0)

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
                        if (needed === pointCount && cloudflareSamples.length === needed
                                && googleSamples.length === needed && gatewaySamples.length === needed) {
                            return false
                        }
                        pointCount = needed
                        cloudflareSamples = new Array(needed)
                        googleSamples = new Array(needed)
                        gatewaySamples = new Array(needed)
                        for (var i = 0; i < needed; ++i) {
                            cloudflareSamples[i] = -1
                            googleSamples[i] = -1
                            gatewaySamples[i] = -1
                        }
                        cloudflareValidPoints = 0
                        googleValidPoints = 0
                        gatewayValidPoints = 0
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
                        var removedCloudflare = 0
                        var removedGoogle = 0
                        var removedGateway = 0
                        for (var r = 0; r < count; ++r) {
                            if (cloudflareSamples[r] >= 0 && !isNaN(cloudflareSamples[r])) {
                                removedCloudflare += 1
                            }
                            if (googleSamples[r] >= 0 && !isNaN(googleSamples[r])) {
                                removedGoogle += 1
                            }
                            if (gatewaySamples[r] >= 0 && !isNaN(gatewaySamples[r])) {
                                removedGateway += 1
                            }
                        }
                        for (var i = 0; i < kept; ++i) {
                            cloudflareSamples[i] = cloudflareSamples[i + count]
                            googleSamples[i] = googleSamples[i + count]
                            gatewaySamples[i] = gatewaySamples[i + count]
                        }

                        var cloudflareValue = (root.currentCloudflarePing >= 0 && root.displayCloudflarePing >= 0) ? root.displayCloudflarePing : -1
                        var googleValue = (root.currentGooglePing >= 0 && root.displayGooglePing >= 0) ? root.displayGooglePing : -1
                        var gatewayValue = (root.currentGatewayPing >= 0 && root.displayGatewayPing >= 0) ? root.displayGatewayPing : -1
                        for (var j = 0; j < count; ++j) {
                            cloudflareSamples[kept + j] = cloudflareValue
                            googleSamples[kept + j] = googleValue
                            gatewaySamples[kept + j] = gatewayValue
                        }
                        var addedCloudflare = (cloudflareValue >= 0) ? count : 0
                        var addedGoogle = (googleValue >= 0) ? count : 0
                        var addedGateway = (gatewayValue >= 0) ? count : 0
                        cloudflareValidPoints = Math.max(0, cloudflareValidPoints - removedCloudflare + addedCloudflare)
                        googleValidPoints = Math.max(0, googleValidPoints - removedGoogle + addedGoogle)
                        gatewayValidPoints = Math.max(0, gatewayValidPoints - removedGateway + addedGateway)
                        return true
                    }

                    function rebuildPathsAndExtrema() {
                        var maxVal = Math.max(1, root.axisTopMs())
                        var cloudflarePathOutput = ""
                        var googlePathOutput = ""
                        var gatewayPathOutput = ""
                        var cloudflareStarted = false
                        var googleStarted = false
                        var gatewayStarted = false
                        var localMax = -Infinity
                        var localMin = Infinity
                        var localMaxIndex = -1
                        var localMinIndex = -1

                        for (var i = 0; i < pointCount; ++i) {
                            var x = i * sampleStepPx
                            var cloudflareSample = cloudflareSamples[i]
                            var googleSample = googleSamples[i]
                            var gatewaySample = gatewaySamples[i]

                            if (cloudflareSample >= 0 && !isNaN(cloudflareSample)) {
                                var cloudflareY = computeY(cloudflareSample, maxVal)
                                if (cloudflareStarted) {
                                    cloudflarePathOutput += " L " + x + " " + cloudflareY
                                } else {
                                    cloudflarePathOutput += "M " + x + " " + cloudflareY
                                    cloudflareStarted = true
                                }
                                if (cloudflareSample > localMax) {
                                    localMax = cloudflareSample
                                    localMaxIndex = i
                                }
                                if (cloudflareSample < localMin) {
                                    localMin = cloudflareSample
                                    localMinIndex = i
                                }
                            } else {
                                cloudflareStarted = false
                            }

                            if (googleSample >= 0 && !isNaN(googleSample)) {
                                var googleY = computeY(googleSample, maxVal)
                                if (googleStarted) {
                                    googlePathOutput += " L " + x + " " + googleY
                                } else {
                                    googlePathOutput += "M " + x + " " + googleY
                                    googleStarted = true
                                }
                                if (googleSample > localMax) {
                                    localMax = googleSample
                                    localMaxIndex = i
                                }
                                if (googleSample < localMin) {
                                    localMin = googleSample
                                    localMinIndex = i
                                }
                            } else {
                                googleStarted = false
                            }

                            if (gatewaySample >= 0 && !isNaN(gatewaySample)) {
                                var gatewayY = computeY(gatewaySample, maxVal)
                                if (gatewayStarted) {
                                    gatewayPathOutput += " L " + x + " " + gatewayY
                                } else {
                                    gatewayPathOutput += "M " + x + " " + gatewayY
                                    gatewayStarted = true
                                }
                            } else {
                                gatewayStarted = false
                            }
                        }

                        cloudflarePath = cloudflarePathOutput
                        googlePath = googlePathOutput
                        gatewayPath = gatewayPathOutput
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
                        var cloudflareY = computeY(root.displayCloudflarePing, maxVal)
                        var googleY = computeY(root.displayGooglePing, maxVal)
                        var gatewayY = computeY(root.displayGatewayPing, maxVal)
                        var fontSize = publicRealtimeLabelFontSize
                        var minGap = fontSize + 4
                        var topBound = fontSize
                        var bottomBound = height - 2
                        if (bottomBound < topBound) {
                            bottomBound = topBound
                        }

                        var labels = []
                        if (cloudflareY >= 0) {
                            labels.push({ target: "cloudflare", desiredY: cloudflareY, adjustedY: cloudflareY })
                        }
                        if (googleY >= 0) {
                            labels.push({ target: "google", desiredY: googleY, adjustedY: googleY })
                        }
                        if (gatewayY >= 0) {
                            labels.push({ target: "gateway", desiredY: gatewayY, adjustedY: gatewayY })
                        }
                        labels.sort(function(a, b) { return a.desiredY - b.desiredY })

                        for (var i = 0; i < labels.length; ++i) {
                            var y = labels[i].desiredY
                            if (i > 0 && y < labels[i - 1].adjustedY + minGap) {
                                y = labels[i - 1].adjustedY + minGap
                            }
                            labels[i].adjustedY = y
                        }

                        if (labels.length > 0 && labels[labels.length - 1].adjustedY > bottomBound) {
                            labels[labels.length - 1].adjustedY = bottomBound
                            for (var j = labels.length - 2; j >= 0; --j) {
                                var maxAllowed = labels[j + 1].adjustedY - minGap
                                if (labels[j].adjustedY > maxAllowed) {
                                    labels[j].adjustedY = maxAllowed
                                }
                            }
                            if (labels[0].adjustedY < topBound) {
                                labels[0].adjustedY = topBound
                                for (var k = 1; k < labels.length; ++k) {
                                    var minAllowed = labels[k - 1].adjustedY + minGap
                                    if (labels[k].adjustedY < minAllowed) {
                                        labels[k].adjustedY = minAllowed
                                    }
                                }
                            }
                        }

                        var cloudflareLabelY = -1
                        var googleLabelY = -1
                        var gatewayLabelY = -1
                        for (var m = 0; m < labels.length; ++m) {
                            var entry = labels[m]
                            if (entry.target === "cloudflare") {
                                cloudflareLabelY = entry.adjustedY
                            } else if (entry.target === "google") {
                                googleLabelY = entry.adjustedY
                            } else if (entry.target === "gateway") {
                                gatewayLabelY = entry.adjustedY
                            }
                        }

                        cachedCloudflareY = cloudflareY
                        cachedGoogleY = googleY
                        cachedGatewayY = gatewayY
                        cachedCloudflareLabelY = cloudflareLabelY
                        cachedGoogleLabelY = googleLabelY
                        cachedGatewayLabelY = gatewayLabelY
                        cachedCloudflareLabelValue = (cloudflareY >= 0) ? root.displayCloudflarePing : -1
                        cachedGoogleLabelValue = (googleY >= 0) ? root.displayGooglePing : -1
                        cachedGatewayLabelValue = (gatewayY >= 0) ? root.displayGatewayPing : -1
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
        interval: 1000
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
                            var oldCloudflarePing = root.displayCloudflarePing
                            var oldGooglePing = root.displayGooglePing
                            var oldGatewayPing = root.displayGatewayPing
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
                            if (root.displayCloudflarePing > visibleMax) {
                                visibleMax = root.displayCloudflarePing
                            }
                            if (root.displayGooglePing > visibleMax) {
                                visibleMax = root.displayGooglePing
                            }
                            if (root.displayGatewayPing > visibleMax) {
                                visibleMax = root.displayGatewayPing
                            }
                            if (visibleMax < 0) {
                                visibleMax = 100
                            }
                            root.maxPing = Math.max(100, Math.ceil(visibleMax / 25) * 25)

                            if (rebuilt
                                    || axisChanged
                                    || chartView.valueChanged(oldCloudflarePing, root.displayCloudflarePing, 0.2)
                                    || chartView.valueChanged(oldGooglePing, root.displayGooglePing, 0.2)
                                    || chartView.valueChanged(oldGatewayPing, root.displayGatewayPing, 0.2)) {
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
                            strokeColor: root.cloudflareColor
                            strokeWidth: 2
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathSvg { path: chartView.cloudflarePath }
                        }

                        ShapePath {
                            strokeColor: root.googleColor
                            strokeWidth: 2
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathSvg { path: chartView.googlePath }
                        }

                        ShapePath {
                            strokeColor: root.gatewayColor
                            strokeWidth: 2
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathSvg { path: chartView.gatewayPath }
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
                        visible: chartView.cachedCloudflareY >= 0
                        width: 10
                        height: 10
                        radius: 5
                        color: root.cloudflareColor
                        x: chartView.chartW - width / 2
                        y: chartView.cachedCloudflareY - height / 2
                    }

                    Text {
                        parent: blurScene
                        visible: chartView.cachedCloudflareY >= 0
                        text: Math.round(chartView.cachedCloudflareLabelValue) + "ms"
                        color: root.cloudflareColor
                        font.pixelSize: chartView.publicRealtimeLabelFontSize
                        x: chartView.chartW + 6
                        y: chartView.cachedCloudflareLabelY - height / 2
                    }

                    Rectangle {
                        parent: blurScene
                        visible: chartView.cachedGoogleY >= 0
                        width: 10
                        height: 10
                        radius: 5
                        color: root.googleColor
                        x: chartView.chartW - width / 2
                        y: chartView.cachedGoogleY - height / 2
                    }

                    Text {
                        parent: blurScene
                        visible: chartView.cachedGoogleY >= 0
                        text: Math.round(chartView.cachedGoogleLabelValue) + "ms"
                        color: root.googleColor
                        font.pixelSize: chartView.publicRealtimeLabelFontSize
                        x: chartView.chartW + 6
                        y: chartView.cachedGoogleLabelY - height / 2
                    }

                    Rectangle {
                        parent: blurScene
                        visible: chartView.cachedGatewayY >= 0
                        width: 10
                        height: 10
                        radius: 5
                        color: root.gatewayColor
                        x: chartView.chartW - width / 2
                        y: chartView.cachedGatewayY - height / 2
                    }

                    Text {
                        parent: blurScene
                        visible: chartView.cachedGatewayY >= 0
                        text: chartView.cachedGatewayLabelValue.toFixed(1) + "ms"
                        color: root.gatewayColor
                        font.pixelSize: chartView.gatewayRealtimeLabelFontSize
                        x: chartView.chartW + 6
                        y: chartView.cachedGatewayLabelY - height / 2
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.ceil(font.pixelSize * 1.05)
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
                text: "Last Internet Ping Received: " + root.lastPingReceivedText
                color: Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 0.75
                opacity: 1
            }
        }
    }

    Component.onDestruction: {
        // Explicitly stop timers and disconnect any in-flight one-shot commands.
        shuttingDown = true
        try { if (gatewayRefreshTimer) gatewayRefreshTimer.stop() } catch (e) {}
        try { if (pingCycleTimer) pingCycleTimer.stop() } catch (e) {}
        try { executable.disconnectSource(gatewayQueryCmd) } catch (e) {}
        try { executable.disconnectSource(cloudflarePingCmd) } catch (e) {}
        try { executable.disconnectSource(googlePingCmd) } catch (e) {}
        try { if (gatewayPingCmdInFlight.length > 0) executable.disconnectSource(gatewayPingCmdInFlight) } catch (e) {}
        cloudflarePingInFlight = false
        googlePingInFlight = false
        gatewayPingInFlight = false
        gatewayPingCmdInFlight = ""
    }
}
