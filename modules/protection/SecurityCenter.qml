pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Tabbed security center behind the bar shield: Protection, Firewall, HTTP
// Debugger and Startup Apps. Each tab is a self-contained component that fills
// the card body; this file owns the window chrome, the tab strip, and the
// shared open/close animation. Dismiss: click the scrim or press Escape.
Scope {
    id: root

    readonly property bool open: Security.panelOpen
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]

    readonly property var tabs: [
        {id: "protection", label: qsTr("Protection"), icon: "security", badge: Protection.pendingCount},
        {id: "firewall", label: qsTr("Firewall"), icon: "gpp_good", badge: Firewall.pendingCount},
        {id: "http", label: qsTr("HTTP"), icon: "travel_explore", badge: 0},
        {id: "startup", label: qsTr("Startup"), icon: "rocket_launch", badge: 0}
    ]

    // Startup is a pull model (no daemon push), so refresh it whenever the
    // panel opens or that tab is selected.
    function _maybeRefreshStartup(): void {
        if (root.open && Security.tab === "startup")
            Startup.refresh();
    }
    onOpenChanged: _maybeRefreshStartup()
    Connections {
        target: Security
        function onTabChanged(): void { root._maybeRefreshStartup(); }
    }

    StyledWindow {
        id: win

        screen: root.focusedScreen
        name: "security-center"
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
                onClicked: Security.panelOpen = false
            }
        }

        StyledRect {
            id: card

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness) * 2 + Tokens.padding.large * 3

            implicitWidth: 600
            implicitHeight: Math.min(760, win.height * 0.82)

            radius: Tokens.rounding.large
            color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.7)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

            // Clean fade: card and scrim fade together on the same effects
            // curve, with only a gentle scale — no vertical drop, so a big
            // centered panel doesn't read as "falling in".
            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.98
            focus: root.open

            Keys.onEscapePressed: Security.panelOpen = false

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on scale {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            StyledClippingRect {
                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                radius: card.radius - Tokens.padding.small
                color: Colours.palette.m3surfaceContainerLow

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Tab strip + close.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Tokens.padding.large
                        Layout.bottomMargin: Tokens.padding.small
                        spacing: Tokens.spacing.extraSmall

                        Repeater {
                            model: root.tabs

                            TabButton {
                                required property var modelData
                                label: modelData.label
                                icon: modelData.icon
                                badge: modelData.badge
                                active: Security.tab === modelData.id
                                onClicked: Security.tab = modelData.id
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        MaterialIcon {
                            id: closeBtn
                            Layout.alignment: Qt.AlignVCenter
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
                                onClicked: Security.panelOpen = false
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.padding.large
                        Layout.rightMargin: Tokens.padding.large
                        implicitHeight: 1
                        color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
                    }

                    // Active tab body.
                    Loader {
                        id: body
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: Tokens.padding.large

                        source: {
                            switch (Security.tab) {
                            case "firewall":
                                return "FirewallTab.qml";
                            case "http":
                                return "HttpTab.qml";
                            case "startup":
                                return "StartupTab.qml";
                            default:
                                return "ProtectionTab.qml";
                            }
                        }

                        opacity: root.open ? 1 : 0
                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }
                }
            }
        }
    }

    // One tab in the strip: icon + label, pill highlight when active, count
    // badge when its subsystem has something pending.
    component TabButton: StyledRect {
        id: tb

        required property string label
        required property string icon
        required property int badge
        required property bool active

        signal clicked

        implicitWidth: tbRow.implicitWidth + Tokens.padding.large * 2
        implicitHeight: tbRow.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.full
        color: active ? Colours.palette.m3secondaryContainer : "transparent"
        scale: tbLayer.pressed ? 0.96 : 1

        Behavior on color {
            CAnim {}
        }

        Behavior on scale {
            Anim {
                type: tbLayer.pressed ? Anim.FastSpatial : Anim.Emphasized
            }
        }

        StateLayer {
            id: tbLayer
            radius: Tokens.rounding.full
            color: tb.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
            onClicked: tb.clicked()
        }

        Row {
            id: tbRow
            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: tb.icon
                fill: tb.active ? 1 : 0
                color: tb.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small

                Behavior on fill {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: tb.label
                color: tb.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.small.weight(tb.active ? Font.Bold : Font.Medium).build()
            }

            StyledRect {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Math.max(badgeText.implicitWidth + Tokens.padding.small, badgeText.implicitHeight)
                implicitHeight: badgeText.implicitHeight
                radius: Tokens.rounding.full
                color: Colours.palette.m3error
                visible: tb.badge > 0

                StyledText {
                    id: badgeText
                    anchors.centerIn: parent
                    text: tb.badge
                    color: Colours.palette.m3onError
                    font: Tokens.font.body.builders.small.scale(0.7).weight(Font.Bold).build()
                }
            }
        }
    }
}
