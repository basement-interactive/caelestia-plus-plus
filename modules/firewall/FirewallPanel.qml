pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

// Rules manager, toggled by the bar shield. Remembered apps are grouped into
// collapsible Approved / Denied sections, each row with a segmented
// Allow/Deny control and a remove button. Dismiss: click the scrim or press
// Escape.
Scope {
    id: root

    readonly property bool open: Firewall.panelOpen
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]

    readonly property string query: (search.text ?? "").trim().toLowerCase()
    readonly property var filteredRules: [...Firewall.rules].filter(r => !root.query || (r.name ?? "").toLowerCase().includes(root.query) || (r.exe ?? "").toLowerCase().includes(root.query))
    readonly property var allowRules: root.filteredRules.filter(r => r.action === "allow").sort((a, b) => (a.name ?? a.exe).localeCompare(b.name ?? b.exe))
    readonly property var denyRules: root.filteredRules.filter(r => r.action !== "allow").sort((a, b) => (a.name ?? a.exe).localeCompare(b.name ?? b.exe))
    readonly property int allowCount: Firewall.rules.filter(r => r.action === "allow").length
    readonly property int denyCount: Firewall.rules.length - allowCount

    // Collapse state. Searching temporarily expands both sections so matches
    // are never hidden behind a collapsed header.
    property bool allowOpen: true
    property bool denyOpen: true

    StyledWindow {
        id: win

        screen: root.focusedScreen
        name: "firewall-panel"
        visible: root.open || closeTimer.running

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        Timer {
            id: closeTimer
            interval: Tokens.anim.durations.large
        }

        Connections {
            target: root
            function onOpenChanged(): void {
                if (!root.open)
                    closeTimer.restart();
            }
        }

        StyledRect {
            anchors.fill: parent
            color: Colours.palette.m3scrim
            opacity: root.open ? 0.4 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: Firewall.panelOpen = false
            }
        }

        // Outer bezel: translucent tinted shell with a hairline; the solid
        // core sits inset for concentric corners.
        StyledRect {
            id: card

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            // Below the floating bar pill: pill height + its float margins + gap
            anchors.topMargin: Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness) * 2 + Tokens.padding.large * 3

            implicitWidth: 540
            implicitHeight: Math.min(inner.implicitHeight, win.height * 0.7) + Tokens.padding.small * 2

            radius: Tokens.rounding.large
            color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.7)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.94
            focus: root.open

            Keys.onEscapePressed: Firewall.panelOpen = false

            transform: Translate {
                y: root.open ? 0 : -30

                Behavior on y {
                    Anim {
                        type: Anim.Emphasized
                    }
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on scale {
                Anim {
                    type: Anim.Emphasized
                }
            }

            StyledClippingRect {
                id: core

                anchors.fill: parent
                anchors.margins: Tokens.padding.small

                radius: card.radius - Tokens.padding.small
                color: Colours.palette.m3surfaceContainerLow

                Column {
                    id: inner

                    width: parent.width
                    spacing: 0

                    // Header.
                    Item {
                        width: parent.width
                        implicitHeight: header.implicitHeight + Tokens.padding.large * 2

                        Row {
                            id: header

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Tokens.padding.extraLargeIncreased
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Firewall.connected ? "gpp_good" : "gpp_bad"
                                fill: 1
                                color: Firewall.connected ? Colours.palette.m3primary : Colours.palette.m3outline
                                fontStyle: Tokens.font.icon.large

                                // Idle accent: slow breath while the panel is
                                // open and the firewall is actively filtering.
                                SequentialAnimation on opacity {
                                    running: root.open && win.visible && Firewall.connected && Firewall.enabled
                                    loops: Animation.Infinite
                                    alwaysRunToEnd: true

                                    Anim {
                                        to: 0.8
                                        duration: 3000
                                        type: Anim.Standard
                                    }
                                    Anim {
                                        to: 1
                                        duration: 3000
                                        type: Anim.Standard
                                    }
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter

                                StyledText {
                                    text: qsTr("Firewall")
                                    color: Colours.palette.m3onSurface
                                    font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                                }

                                StyledText {
                                    text: !Firewall.connected ? qsTr("Daemon not running") : !Firewall.enabled ? qsTr("Disabled — all traffic allowed") : qsTr("%1 allowed · %2 denied").arg(root.allowCount).arg(root.denyCount)
                                    color: !Firewall.connected || !Firewall.enabled ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.body.small
                                }
                            }
                        }

                        StyledSwitch {
                            anchors.right: closeBtn.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: Tokens.spacing.large
                            checked: Firewall.enabled
                            enabled: Firewall.connected
                            onToggled: Firewall.setEnabled(checked)
                        }

                        MaterialIcon {
                            id: closeBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: Tokens.padding.extraLargeIncreased

                            text: "close"
                            color: closeLayer.containsMouse ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            scale: closeLayer.pressed ? 0.9 : 1

                            Behavior on scale {
                                Anim {
                                    type: closeLayer.pressed ? Anim.FastSpatial : Anim.Emphasized
                                }
                            }

                            StateLayer {
                                id: closeLayer
                                anchors.centerIn: parent
                                implicitWidth: parent.implicitHeight + Tokens.padding.medium
                                implicitHeight: implicitWidth
                                radius: Tokens.rounding.full
                                onClicked: Firewall.panelOpen = false
                            }
                        }
                    }

                    // Search.
                    Item {
                        id: searchBox

                        visible: Firewall.rules.length > 0
                        width: parent.width
                        implicitHeight: search.implicitHeight + Tokens.padding.large

                        opacity: root.open ? 1 : 0

                        Behavior on opacity {
                            SequentialAnimation {
                                PauseAnimation {
                                    duration: root.open ? 50 : 0
                                }
                                Anim {
                                    type: Anim.DefaultEffects
                                }
                            }
                        }

                        SearchBar {
                            id: search

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: Tokens.padding.large
                            anchors.rightMargin: Tokens.padding.large

                            placeholderText: qsTr("Search apps…")
                        }
                    }

                    // Empty state.
                    StyledText {
                        visible: root.filteredRules.length === 0
                        width: parent.width - Tokens.padding.extraLargeIncreased * 2
                        x: Tokens.padding.extraLargeIncreased
                        bottomPadding: Tokens.padding.large * 2
                        text: !Firewall.connected ? qsTr("Start the firewall daemon (system/redwall/install.sh) to begin filtering.") : Firewall.rules.length === 0 ? qsTr("No rules yet. Apps you allow or deny will show up here.") : qsTr("No apps match “%1”.").arg(root.query)
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        wrapMode: Text.WordWrap
                    }

                    // Rules list: collapsible Approved / Denied sections sharing
                    // one scroll region.
                    StyledFlickable {
                        id: list

                        width: parent.width
                        implicitHeight: Math.min(contentHeight, win.height * 0.7 - header.implicitHeight - Tokens.padding.large * 3 - Tokens.padding.small * 2 - (searchBox.visible ? searchBox.implicitHeight : 0))
                        visible: root.filteredRules.length > 0
                        clip: true
                        contentHeight: sections.implicitHeight
                        flickableDirection: Flickable.VerticalFlick

                        StyledScrollBar.vertical: StyledScrollBar {
                            flickable: list
                            policy: ScrollBar.AlwaysOn
                        }

                        Column {
                            id: sections

                            width: list.width
                            spacing: Tokens.spacing.small
                            bottomPadding: Tokens.padding.large

                            RuleSection {
                                title: qsTr("Approved")
                                icon: "check_circle"
                                accent: Colours.palette.m3primary
                                rules: root.allowRules
                                expanded: root.allowOpen || root.query.length > 0
                                onToggled: root.allowOpen = !root.allowOpen
                            }

                            RuleSection {
                                title: qsTr("Denied")
                                icon: "block"
                                accent: Colours.palette.m3error
                                rules: root.denyRules
                                expanded: root.denyOpen || root.query.length > 0
                                entranceIndex: 1
                                onToggled: root.denyOpen = !root.denyOpen
                            }
                        }
                    }
                }
            }
        }
    }

    // One collapsible category: clickable header (icon, title, count,
    // chevron) over an inline rules list. Collapse clips the list away with
    // an animated reveal; the section hides entirely when the current search
    // leaves it empty.
    component RuleSection: Column {
        id: section

        required property string title
        required property string icon
        required property color accent
        required property var rules
        required property bool expanded
        property int entranceIndex: 0

        signal toggled

        visible: rules.length > 0
        width: parent.width
        spacing: Tokens.spacing.small

        // Staggered entrance when the panel opens.
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation {
                    duration: root.open ? 90 + section.entranceIndex * 50 : 0
                }
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        transform: Translate {
            y: root.open ? 0 : -12

            Behavior on y {
                SequentialAnimation {
                    PauseAnimation {
                        duration: root.open ? 90 + section.entranceIndex * 50 : 0
                    }
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
            }
        }

        Item {
            id: sectionHead

            x: Tokens.padding.large
            width: parent.width - Tokens.padding.large * 2
            implicitHeight: headRow.implicitHeight + Tokens.padding.medium * 2

            scale: headLayer.pressed ? 0.98 : 1

            Behavior on scale {
                Anim {
                    type: headLayer.pressed ? Anim.FastSpatial : Anim.Emphasized
                }
            }

            StateLayer {
                id: headLayer
                radius: Tokens.rounding.medium
                onClicked: section.toggled()
            }

            Row {
                id: headRow

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: section.icon
                    fill: 1
                    color: section.accent
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("%1 (%2)").arg(section.title).arg(section.rules.length)
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                }
            }

            MaterialIcon {
                anchors.right: parent.right
                anchors.rightMargin: Tokens.padding.medium
                anchors.verticalCenter: parent.verticalCenter
                text: "expand_more"
                color: Colours.palette.m3onSurfaceVariant
                rotation: section.expanded ? 0 : -90

                Behavior on rotation {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }

        StyledClippingRect {
            width: parent.width
            implicitHeight: section.expanded ? rulesList.contentHeight : 0
            color: "transparent"

            Behavior on implicitHeight {
                Anim {
                    type: Anim.Emphasized
                }
            }

            StyledListView {
                id: rulesList

                anchors.top: parent.top
                width: parent.width
                height: contentHeight
                interactive: false
                spacing: Tokens.spacing.small
                leftMargin: Tokens.padding.large
                rightMargin: Tokens.padding.large

                model: ScriptModel {
                    values: section.rules
                }

                add: Transition {
                    Anim {
                        properties: "opacity"
                        from: 0
                        to: 1
                    }
                    Anim {
                        properties: "scale"
                        from: 0.85
                        to: 1
                        easing: Tokens.anim.standardDecel
                    }
                }

                remove: Transition {
                    Anim {
                        properties: "opacity"
                        to: 0
                    }
                    Anim {
                        properties: "scale"
                        to: 0.85
                    }
                }

                displaced: Transition {
                    Anim {
                        properties: "x,y"
                    }
                }

                delegate: RuleRow {}
            }
        }
    }

    component RuleRow: StyledRect {
        id: row

        required property var modelData
        readonly property bool allowed: modelData.action === "allow"
        readonly property string appName: modelData.name || (modelData.exe ?? "").split("/").pop()

        width: ListView.view.width - Tokens.padding.large * 2
        implicitHeight: rowLayout.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.25)

        Row {
            id: rowLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            IconImage {
                id: appIcon

                anchors.verticalCenter: parent.verticalCenter
                asynchronous: true
                source: Icons.getAppIcon(row.appName, "application-x-executable")
                implicitSize: 32
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - parent.spacing * 3 - appIcon.width - seg.width - del.width

                StyledText {
                    width: parent.width
                    text: row.modelData.name ?? ""
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: row.modelData.exe
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.mono.small
                    elide: Text.ElideMiddle
                }
            }

            // Segmented Allow/Deny.
            StyledRect {
                id: seg

                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: allowSeg.implicitWidth + denySeg.implicitWidth
                implicitHeight: allowSeg.implicitHeight
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerLowest

                Row {
                    SegButton {
                        id: allowSeg
                        label: qsTr("Allow")
                        active: row.allowed
                        accent: Colours.palette.m3primary
                        onColour: Colours.palette.m3onPrimary
                        onClicked: Firewall.setRule(row.modelData.exe, "allow", row.modelData.name)
                    }
                    SegButton {
                        id: denySeg
                        label: qsTr("Deny")
                        active: !row.allowed
                        accent: Colours.palette.m3error
                        onColour: Colours.palette.m3onError
                        onClicked: Firewall.setRule(row.modelData.exe, "deny", row.modelData.name)
                    }
                }
            }

            MaterialIcon {
                id: del

                anchors.verticalCenter: parent.verticalCenter
                text: "delete"
                color: delLayer.containsMouse ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
                scale: delLayer.pressed ? 0.9 : 1

                Behavior on scale {
                    Anim {
                        type: delLayer.pressed ? Anim.FastSpatial : Anim.Emphasized
                    }
                }

                StateLayer {
                    id: delLayer
                    anchors.centerIn: parent
                    implicitWidth: parent.implicitHeight + Tokens.padding.small
                    implicitHeight: implicitWidth
                    radius: Tokens.rounding.full
                    onClicked: Firewall.delRule(row.modelData.exe)
                }
            }
        }
    }

    component SegButton: StyledRect {
        id: sb

        required property string label
        required property bool active
        required property color accent
        required property color onColour

        signal clicked

        implicitWidth: segText.implicitWidth + Tokens.padding.large * 2
        implicitHeight: segText.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: active ? accent : "transparent"
        scale: segLayer.pressed ? 0.95 : 1

        Behavior on color {
            CAnim {}
        }

        Behavior on scale {
            Anim {
                type: segLayer.pressed ? Anim.FastSpatial : Anim.Emphasized
            }
        }

        StateLayer {
            id: segLayer
            color: sb.active ? sb.onColour : sb.accent
            onClicked: sb.clicked()
        }

        StyledText {
            id: segText
            anchors.centerIn: parent
            text: sb.label
            color: sb.active ? sb.onColour : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.builders.small.weight(Font.Medium).build()

            Behavior on color {
                CAnim {}
            }
        }
    }
}
