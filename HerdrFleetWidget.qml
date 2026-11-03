import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
import "." as Local

PluginComponent {
    id: root
    property var popoutService: null

    readonly property bool includeRemoteMachines: pluginData.includeRemoteMachines ?? true
    readonly property bool includeHerdrCore: pluginData.includeHerdrCore ?? true
    readonly property bool includeEmptySpaces: pluginData.includeEmptySpaces ?? false
    readonly property string pillDisplayMode: pluginData.pillDisplayMode || "breakdown"
    readonly property int baseIntervalMs: Math.max(3, (pluginData.refreshInterval || 8)) * 1000
    readonly property int maxIntervalMs: 60000
    readonly property int maxBackoffSteps: 3

    readonly property string pluginDir: PluginService.pluginDirectory + "/duxHerdrFleet"
    readonly property string collectorScript: pluginDir + "/collect-fleet"
    readonly property string focusScript: pluginDir + "/focus-target"

    PluginGlobalVar {
        id: sharedFleet
        varName: "fleetData"
        defaultValue: ({
            ok: false,
            totals: { machines_total: 0, machines_reachable: 0, workspaces: 0, agents: 0, blocked: 0, working: 0, idle: 0, done: 0 },
            machines: [],
            agents: []
        })
    }
    PluginGlobalVar {
        id: sharedFailures
        varName: "consecutiveFailures"
        defaultValue: 0
    }
    PluginGlobalVar {
        id: sharedLastPoll
        varName: "lastPollMs"
        defaultValue: 0
    }
    PluginGlobalVar {
        id: sharedSelectedMachine
        varName: "selectedMachine"
        defaultValue: "all"
    }
    PluginGlobalVar {
        id: sharedRefreshing
        varName: "isRefreshing"
        defaultValue: false
    }

    readonly property var fleet: sharedFleet.value || ({ totals: {}, machines: [], agents: [] })
    readonly property var totals: fleet.totals || ({ machines_total: 0, machines_reachable: 0, workspaces: 0, agents: 0, blocked: 0, working: 0, idle: 0, done: 0 })
    readonly property var machines: fleet.machines || []
    readonly property var agents: fleet.agents || []
    readonly property string selectedMachine: sharedSelectedMachine.value || "all"
    readonly property int currentIntervalMs: Math.min(baseIntervalMs * Math.pow(2, sharedFailures.value), maxIntervalMs)

    property var fleetPopout: null
    property bool fleetOpenRequested: false
    property real fleetOpenRequestedAt: 0

    Component.onCompleted: Local.HerdrFleetController.registerRoot(root)
    Component.onDestruction: Local.HerdrFleetController.unregisterRoot(root)

    pillRightClickAction: () => root.refreshNow()

    onIncludeRemoteMachinesChanged: root.refreshNow()
    onIncludeHerdrCoreChanged: root.refreshNow()
    onIncludeEmptySpacesChanged: root.refreshNow()

    function toggleHcQuick() {
        var nextVal = !root.includeHerdrCore;
        if (typeof PluginService !== "undefined" && PluginService.savePluginData) {
            PluginService.savePluginData("duxHerdrFleet", "includeHerdrCore", nextVal);
        }
        Qt.callLater(root.refreshNow);
    }

    function statusColor(st) {
        switch (st) {
        case "blocked": return Theme.error;
        case "working": return Theme.primary;
        case "idle": return Theme.warning;
        case "done": return Theme.success;
        default: return Theme.surfaceText;
        }
    }

    function statusIcon(st) {
        switch (st) {
        case "blocked": return "warning";
        case "working": return "bolt";
        case "idle": return "pause_circle";
        case "done": return "check_circle";
        default: return "help";
        }
    }

    function machineIcon(m) {
        if (!m) return "dns";
        if (m.backend === "hc") return "desktop_windows";
        if (m.isLocal) return "computer";
        return "dns";
    }

    readonly property color barIconColor: {
        if ((totals.agents || 0) === 0)
            return Theme.widgetIconColor;
        if ((totals.blocked || 0) > 0)
            return Theme.error;
        if ((totals.working || 0) > 0)
            return Theme.primary;
        return Theme.primary;
    }

    readonly property string pillLabelText: {
        var total = totals.agents || 0;
        var blocked = totals.blocked || 0;
        var working = totals.working || 0;
        if (pillDisplayMode === "iconOnly" || total === 0)
            return "";
        if (pillDisplayMode === "activeOnly") {
            var active = blocked + working;
            return active > 0 ? active.toString() : "";
        }
        if (pillDisplayMode === "breakdown") {
            var parts = [];
            if (blocked > 0) parts.push(blocked + "!");
            if (working > 0) parts.push(working + "⚡");
            parts.push(total.toString());
            return parts.join("·");
        }
        return total.toString();
    }

    readonly property var visibleMachines: {
        var list = root.machines || [];
        if (root.selectedMachine === "all")
            return list;
        var filtered = [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === root.selectedMachine)
                filtered.push(list[i]);
        }
        return filtered.length > 0 ? filtered : list;
    }

    Process {
        id: collectorProc
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                sharedRefreshing.set(false);
                var raw = (text || "").trim();
                if (!raw) {
                    sharedFailures.set(Math.min(sharedFailures.value + 1, root.maxBackoffSteps));
                    return;
                }
                try {
                    var parsed = JSON.parse(raw);
                    sharedFleet.set(parsed);
                    sharedFailures.set(0);
                } catch (e) {
                    sharedFailures.set(Math.min(sharedFailures.value + 1, root.maxBackoffSteps));
                }
            }
        }

        onExited: code => {
            sharedRefreshing.set(false);
            if (code !== 0) {
                sharedFailures.set(Math.min(sharedFailures.value + 1, root.maxBackoffSteps));
            }
        }
    }

    function runCollector() {
        if (collectorProc.running)
            return;
        sharedRefreshing.set(true);
        collectorProc.command = [
            "python3",
            root.collectorScript,
            "--include-hc", root.includeHerdrCore ? "1" : "0",
            "--include-remote", root.includeRemoteMachines ? "1" : "0",
            "--include-empty-spaces", root.includeEmptySpaces ? "1" : "0"
        ];
        collectorProc.running = true;
    }

    function maybeRefresh() {
        var now = Date.now();
        if (now - sharedLastPoll.value < root.currentIntervalMs - 500)
            return;
        sharedLastPoll.set(now);
        root.runCollector();
    }

    function refreshNow() {
        sharedLastPoll.set(Date.now());
        root.runCollector();
    }

    function focusAgent(agent) {
        if (!agent)
            return;
        Quickshell.execDetached([
            "bash",
            root.focusScript,
            "agent",
            agent.backend || "herdr",
            agent.machine_id || "local",
            agent.pane_id || ""
        ]);
    }

    function focusWorkspace(machine, ws) {
        if (!machine || !ws)
            return;
        Quickshell.execDetached([
            "bash",
            root.focusScript,
            "workspace",
            machine.backend || "herdr",
            machine.id || "local",
            ws.workspace_id || ""
        ]);
    }

    function focusHerdrWindow() {
        Quickshell.execDetached(["bash", root.focusScript, "window"]);
    }

    // IPC handlers
    function isPopoutOpen() {
        if (fleetOpenRequested && Date.now() - fleetOpenRequestedAt >= 1500)
            fleetOpenRequested = false;
        return fleetOpenRequested || !!fleetPopout?.shouldBeVisible;
    }

    function openFromIpc() {
        if (isPopoutOpen())
            return "HERDR_ALREADY_OPEN";
        fleetOpenRequested = true;
        fleetOpenRequestedAt = Date.now();
        triggerPopout();
        return "HERDR_OPENING";
    }

    function closeFromIpc() {
        if (!isPopoutOpen())
            return "HERDR_ALREADY_CLOSED";
        fleetOpenRequested = false;
        closePopout();
        return "HERDR_CLOSED";
    }

    function toggleFromIpc() {
        return isPopoutOpen() ? closeFromIpc() : openFromIpc();
    }

    function refreshFromIpc() {
        refreshNow();
        return "HERDR_REFRESH_QUEUED";
    }

    function statusFromIpc() {
        return JSON.stringify(root.totals);
    }

    Timer {
        interval: root.currentIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.maybeRefresh()
    }

    popoutWidth: 440
    popoutHeight: 540

    horizontalBarPill: Component {
        Item {
            implicitWidth: hRow.implicitWidth
            implicitHeight: hRow.implicitHeight

            Row {
                id: hRow
                spacing: Theme.spacingS

                DankIcon {
                    name: "smart_toy"
                    color: root.barIconColor
                    size: Theme.barIconSize(root.barThickness, -4)
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.pillLabelText
                    color: (root.totals.blocked || 0) > 0 ? Theme.error : Theme.surfaceText
                    font.pixelSize: Theme.barTextSize(root.barThickness)
                    font.weight: (root.totals.blocked || 0) > 0 ? Font.Bold : Font.Normal
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.pillLabelText.length > 0
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                acceptedButtons: Qt.MiddleButton
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton)
                        root.focusHerdrWindow();
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: vCol.implicitWidth
            implicitHeight: vCol.implicitHeight

            Column {
                id: vCol
                spacing: Theme.spacingXS

                DankIcon {
                    name: "smart_toy"
                    color: root.barIconColor
                    size: Theme.barIconSize(root.barThickness, -4)
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: (root.totals.agents || 0).toString()
                    color: (root.totals.blocked || 0) > 0 ? Theme.error : Theme.surfaceText
                    font.pixelSize: Theme.barTextSize(root.barThickness)
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.pillDisplayMode !== "iconOnly" && (root.totals.agents || 0) > 0
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                acceptedButtons: Qt.MiddleButton
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton)
                        root.focusHerdrWindow();
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Dux Herdr Fleet"
            detailsText: (root.totals.agents || 0) + " " + I18n.trFor("duxHerdrFleet", "agents") + " · " + (root.totals.workspaces || 0) + " spaces · " + (root.totals.machines_reachable || 0) + "/" + (root.totals.machines_total || 0) + " hosts"
            showCloseButton: true

            onParentPopoutChanged: {
                if (parentPopout)
                    root.fleetPopout = parentPopout;
            }
            Component.onCompleted: {
                if (parentPopout)
                    root.fleetPopout = parentPopout;
                root.refreshNow();
            }
            Connections {
                target: popout.parentPopout
                function onOpened() {
                    root.fleetOpenRequested = false;
                    root.refreshNow();
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingS

                // ── Top status bar + quick actions (hc toggle & refresh) ──
                Row {
                    width: parent.width
                    spacing: Theme.spacingXS

                    // Summary status badges
                    StyledRect {
                        height: 26
                        width: summaryRow.implicitWidth + Theme.spacingM * 2
                        radius: 13
                        color: Theme.surfaceContainer

                        Row {
                            id: summaryRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            Row {
                                spacing: 3
                                visible: (root.totals.blocked || 0) > 0
                                DankIcon {
                                    name: "warning"
                                    color: Theme.error
                                    size: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: (root.totals.blocked || 0) + " blocked"
                                    color: Theme.error
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Row {
                                spacing: 3
                                DankIcon {
                                    name: "bolt"
                                    color: Theme.primary
                                    size: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: (root.totals.working || 0) + " working"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Row {
                                spacing: 3
                                DankIcon {
                                    name: "pause_circle"
                                    color: Theme.warning
                                    size: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: (root.totals.idle || 0) + " idle"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Row {
                                spacing: 3
                                visible: (root.totals.done || 0) > 0
                                DankIcon {
                                    name: "check_circle"
                                    color: Theme.success
                                    size: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: (root.totals.done || 0) + " done"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    Item {
                        width: Math.max(4, parent.width - summaryRow.parent.width - hcChip.width - refreshBtn.width - Theme.spacingXS * 3)
                        height: 1
                    }

                    // Quick toggle for Herdr Desktop App (hc)
                    StyledRect {
                        id: hcChip
                        height: 26
                        width: hcRow.implicitWidth + Theme.spacingS * 2
                        radius: 13
                        color: root.includeHerdrCore ? Theme.withAlpha(Theme.primary, 0.22) : Theme.surfaceContainer
                        border.width: 1
                        border.color: root.includeHerdrCore ? Theme.withAlpha(Theme.primary, 0.55) : "transparent"

                        Row {
                            id: hcRow
                            anchors.centerIn: parent
                            spacing: 4

                            DankIcon {
                                name: "desktop_windows"
                                size: 13
                                color: root.includeHerdrCore ? Theme.primary : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: "hc"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: root.includeHerdrCore ? Font.Medium : Font.Normal
                                color: root.includeHerdrCore ? Theme.primary : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleHcQuick()
                        }
                    }

                    // Refresh button
                    StyledRect {
                        id: refreshBtn
                        width: 26
                        height: 26
                        radius: 13
                        color: refreshMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer

                        DankIcon {
                            anchors.centerIn: parent
                            name: sharedRefreshing.value ? "sync" : "refresh"
                            size: 15
                            color: sharedRefreshing.value ? Theme.primary : Theme.surfaceText
                        }

                        MouseArea {
                            id: refreshMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refreshNow()
                        }
                    }
                }

                // ── Machine Filter Chips ──
                Flickable {
                    width: parent.width
                    height: 30
                    contentWidth: chipsRow.implicitWidth
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: chipsRow
                        spacing: Theme.spacingXS
                        height: parent.height

                        // "All" chip
                        StyledRect {
                            height: 26
                            width: allChipText.implicitWidth + Theme.spacingM * 2
                            radius: 13
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.selectedMachine === "all" ? Theme.primary : Theme.surfaceContainer

                            StyledText {
                                id: allChipText
                                anchors.centerIn: parent
                                text: I18n.trFor("duxHerdrFleet", "All") + " (" + (root.totals.agents || 0) + ")"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: root.selectedMachine === "all" ? Font.Medium : Font.Normal
                                color: root.selectedMachine === "all" ? Theme.onPrimary : Theme.surfaceText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sharedSelectedMachine.set("all")
                            }
                        }

                        Repeater {
                            model: root.machines

                            delegate: StyledRect {
                                readonly property bool isSelected: root.selectedMachine === modelData.id
                                readonly property int mBlocked: (modelData.counts && modelData.counts.blocked) || 0
                                readonly property int mWorking: (modelData.counts && modelData.counts.working) || 0
                                readonly property int mTotal: (modelData.counts && modelData.counts.total) || 0

                                height: 26
                                width: mChipRow.implicitWidth + Theme.spacingM * 2
                                radius: 13
                                anchors.verticalCenter: parent.verticalCenter
                                color: isSelected ? Theme.primary : Theme.surfaceContainer
                                opacity: modelData.reachable ? 1.0 : 0.55

                                Row {
                                    id: mChipRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Rectangle {
                                        width: 7
                                        height: 7
                                        radius: 3.5
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !modelData.reachable || mBlocked > 0 || mWorking > 0
                                        color: !modelData.reachable ? Theme.outline : (mBlocked > 0 ? Theme.error : Theme.primary)
                                    }

                                    StyledText {
                                        text: (modelData.short_label || modelData.id) + " (" + mTotal + ")"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: isSelected ? Font.Medium : Font.Normal
                                        color: isSelected ? Theme.onPrimary : Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sharedSelectedMachine.set(isSelected ? "all" : modelData.id)
                                }
                            }
                        }
                    }
                }

                // ── Main Scrollable Tree: Machine -> Space -> Agents ──
                Flickable {
                    id: fleetFlick
                    width: parent.width
                    height: Math.min(400, Math.max(180, treeColumn.implicitHeight))
                    contentWidth: width
                    contentHeight: treeColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: treeColumn
                        width: parent.width
                        spacing: Theme.spacingM

                        StyledText {
                            visible: (root.totals.agents || 0) === 0 && !sharedRefreshing.value
                            text: I18n.trFor("duxHerdrFleet", "No active agents across monitored machines")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                        }

                        Repeater {
                            model: root.visibleMachines

                            delegate: Column {
                                id: machineBlock
                                required property var modelData
                                width: treeColumn.width
                                spacing: Theme.spacingXS
                                visible: (modelData.workspaces && modelData.workspaces.length > 0) || !modelData.reachable

                                // Machine Header
                                StyledRect {
                                    width: parent.width
                                    height: 28
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(Theme.primary, 0.10)

                                    Row {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: Theme.spacingS
                                        spacing: Theme.spacingXS

                                        DankIcon {
                                            name: root.machineIcon(machineBlock.modelData)
                                            size: 15
                                            color: machineBlock.modelData.reachable ? Theme.primary : Theme.error
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: machineBlock.modelData.label || machineBlock.modelData.id
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: Theme.surfaceText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: machineBlock.modelData.reachable
                                                ? "· " + ((machineBlock.modelData.workspaces || []).length) + " spaces · " + ((machineBlock.modelData.counts && machineBlock.modelData.counts.total) || 0) + " " + I18n.trFor("duxHerdrFleet", "agents")
                                                : "· " + I18n.trFor("duxHerdrFleet", "offline")
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: machineBlock.modelData.reachable ? Theme.surfaceVariantText : Theme.error
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                // Workspaces inside this Machine
                                Repeater {
                                    model: machineBlock.modelData.workspaces || []

                                    delegate: Column {
                                        id: wsBlock
                                        required property var modelData
                                        width: machineBlock.width
                                        spacing: 4

                                        // Space (Workspace) Subheader (clickable to focus space)
                                        StyledRect {
                                            width: parent.width
                                            height: 24
                                            radius: 6
                                            color: wsMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                                            Row {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: Theme.spacingS
                                                anchors.rightMargin: Theme.spacingS
                                                spacing: 6

                                                DankIcon {
                                                    name: wsBlock.modelData.focused ? "folder_open" : "folder"
                                                    size: 14
                                                    color: wsBlock.modelData.focused ? Theme.primary : Theme.surfaceVariantText
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                StyledText {
                                                    width: parent.width - 90
                                                    elide: Text.ElideRight
                                                    text: "[" + (wsBlock.modelData.number || "?") + "] " + (wsBlock.modelData.label || wsBlock.modelData.workspace_id)
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.weight: Font.Medium
                                                    color: wsBlock.modelData.focused ? Theme.primary : Theme.surfaceVariantText
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                StyledText {
                                                    text: (wsBlock.modelData.pane_count || 0) === 1 ? I18n.trFor("duxHerdrFleet", "1 pane") : I18n.trFor("duxHerdrFleet", "%1 panes").arg(wsBlock.modelData.pane_count || 0)
                                                    font.pixelSize: 11
                                                    color: Theme.surfaceVariantText
                                                    opacity: 0.75
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            MouseArea {
                                                id: wsMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.focusWorkspace(machineBlock.modelData, wsBlock.modelData);
                                                    popout.closePopout();
                                                }
                                            }
                                        }

                                        // Agents inside this Space
                                        Repeater {
                                            model: wsBlock.modelData.agents || []

                                            delegate: StyledRect {
                                                id: agentCard
                                                required property var modelData
                                                width: wsBlock.width
                                                height: agentCol.implicitHeight + Theme.spacingS * 2
                                                radius: Theme.cornerRadius
                                                color: agentMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                                                border.width: modelData.agent_status === "blocked" ? 1 : 0
                                                border.color: modelData.agent_status === "blocked" ? Theme.error : "transparent"

                                                Row {
                                                    id: agentRow
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.margins: Theme.spacingS
                                                    spacing: Theme.spacingS

                                                    DankIcon {
                                                        id: statusIconItem
                                                        name: root.statusIcon(agentCard.modelData.agent_status)
                                                        color: root.statusColor(agentCard.modelData.agent_status)
                                                        size: Theme.iconSizeSmall
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }

                                                    Column {
                                                        id: agentCol
                                                        width: agentRow.width - statusIconItem.width - agentRow.spacing
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: 2

                                                        Row {
                                                            width: parent.width
                                                            spacing: 6

                                                            StyledRect {
                                                                id: agentBadge
                                                                height: 16
                                                                width: badgeText.implicitWidth + 10
                                                                radius: 4
                                                                color: Theme.withAlpha(root.statusColor(agentCard.modelData.agent_status), 0.18)
                                                                anchors.verticalCenter: parent.verticalCenter

                                                                StyledText {
                                                                    id: badgeText
                                                                    anchors.centerIn: parent
                                                                    text: (agentCard.modelData.agent || "agent") + " · " + (agentCard.modelData.pane_id || "")
                                                                    font.pixelSize: 10
                                                                    font.weight: Font.Medium
                                                                    color: root.statusColor(agentCard.modelData.agent_status)
                                                                }
                                                            }

                                                            StyledText {
                                                                width: parent.width - agentBadge.width - 8
                                                                elide: Text.ElideRight
                                                                text: agentCard.modelData.title || agentCard.modelData.agent
                                                                color: Theme.surfaceText
                                                                font.pixelSize: Theme.fontSizeSmall
                                                                font.weight: Font.Medium
                                                                anchors.verticalCenter: parent.verticalCenter
                                                            }
                                                        }

                                                        StyledText {
                                                            width: parent.width
                                                            elide: Text.ElideMiddle
                                                            text: {
                                                                var parts = [];
                                                                if (agentCard.modelData.subtitle)
                                                                    parts.push(agentCard.modelData.subtitle);
                                                                if (agentCard.modelData.cwd)
                                                                    parts.push(agentCard.modelData.cwd);
                                                                if (agentCard.modelData.context)
                                                                    parts.push(agentCard.modelData.context);
                                                                if (agentCard.modelData.limit)
                                                                    parts.push(agentCard.modelData.limit);
                                                                parts.push(agentCard.modelData.agent_status);
                                                                return parts.join("  ·  ");
                                                            }
                                                            color: Theme.surfaceVariantText
                                                            font.pixelSize: 11
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    id: agentMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.focusAgent(agentCard.modelData);
                                                        popout.closePopout();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
