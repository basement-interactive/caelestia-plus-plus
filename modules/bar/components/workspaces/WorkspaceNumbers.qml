pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

// Minimal workspace indicator: bare numbers on the bar (no background pill,
// no window icons) with a primary squircle that slides to the active one.
Item {
    id: root

    required property ShellScreen screen
    required property bool fullscreen

    readonly property int shown: Math.max(1, Config.bar.workspaces.shown)
    readonly property int activeWs: GlobalConfig.bar.workspaces.perMonitorWorkspaces ? (Hypr.monitorFor(screen)?.activeWorkspace?.id ?? 1) : Hypr.activeWsId
    // Workspaces come in pages of `shown`: 1-5, 6-10, ...
    readonly property int groupStart: Math.floor((activeWs - 1) / shown) * shown + 1
    readonly property int cellWidth: 26
    readonly property int hPadding: 10
    readonly property var occupied: {
        const occ = {};
        for (const ws of Hypr.workspaces.values)
            occ[ws.id] = ws.lastIpcObject.windows > 0;
        return occ;
    }

    implicitWidth: shown * cellWidth + hPadding * 2
    implicitHeight: Tokens.sizes.bar.innerWidth

    // subtle capsule frame, same recipe as the tray/status pills
    StyledRect {
        anchors.fill: parent
        radius: height / 2
        color: Qt.alpha(Colours.tPalette.m3surfaceContainer, Colours.tPalette.m3surfaceContainer.a * 0.7)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
    }

    StyledRect {
        id: highlight

        visible: Config.bar.workspaces.activeIndicator
        x: root.hPadding + (root.activeWs - root.groupStart) * root.cellWidth + (root.cellWidth - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 24
        implicitHeight: 24
        radius: 8
        color: Colours.palette.m3primary

        Behavior on x {
            Anim {
                type: Anim.Emphasized
            }
        }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: root.hPadding
        anchors.rightMargin: root.hPadding

        Repeater {
            model: root.shown

            Item {
                id: cell

                required property int index
                readonly property int ws: root.groupStart + index
                readonly property bool isActive: root.activeWs === ws

                width: root.cellWidth
                height: root.height

                StyledText {
                    anchors.centerIn: parent
                    text: cell.ws
                    // Without the sliding squircle, the active number carries
                    // the accent itself instead of sitting on it
                    color: cell.isActive ? (Config.bar.workspaces.activeIndicator ? Colours.palette.m3onPrimary : Colours.palette.m3primary) : root.occupied[cell.ws] ? Colours.palette.m3primary : Colours.palette.m3outline
                    font.weight: cell.isActive ? 700 : 500

                    Behavior on color {
                        CAnim {}
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!cell.isActive)
                            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "${cell.ws}" })` : `workspace ${cell.ws}`);
                    }
                }
            }
        }
    }
}
