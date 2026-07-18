pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

// Startup Apps tab: XDG autostart entries and enabled systemd --user services,
// each with an on/off switch and a remove action, plus an add-new row.
ColumnLayout {
    id: root

    property bool adding: false

    spacing: Tokens.spacing.medium

    TabHeader {
        Layout.fillWidth: true
        icon: "rocket_launch"
        title: qsTr("Startup Apps")
        subtitle: Startup.scanning ? qsTr("Scanning…") : qsTr("%1 launch at login").arg(Startup.entries.filter(e => e.enabled).length)
    }

    StyledText {
        Layout.fillWidth: true
        text: qsTr("Autostart entries and systemd user services that run when you log in. Hyprland exec-once lines live in your Lua config and aren't shown here.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        TextButton {
            text: root.adding ? qsTr("Cancel") : qsTr("Add app")
            type: TextButton.Tonal
            onClicked: root.adding = !root.adding
        }

        Item {
            Layout.fillWidth: true
        }

        TextButton {
            text: qsTr("Rescan")
            type: TextButton.Tonal
            disabled: Startup.scanning
            onClicked: Startup.refresh()
        }
    }

    // Add-new inline form.
    StyledRect {
        Layout.fillWidth: true
        visible: root.adding
        implicitHeight: addCol.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHigh

        ColumnLayout {
            id: addCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            StyledTextField {
                id: addName
                Layout.fillWidth: true
                placeholderText: qsTr("Name (e.g. Nextcloud)")
            }

            StyledTextField {
                id: addExec
                Layout.fillWidth: true
                placeholderText: qsTr("Command (e.g. nextcloud --background)")
            }

            TextButton {
                Layout.alignment: Qt.AlignRight
                text: qsTr("Create")
                disabled: addName.text.trim() === "" || addExec.text.trim() === ""
                onClicked: {
                    Startup.add(addName.text.trim(), addExec.text.trim());
                    addName.text = "";
                    addExec.text = "";
                    root.adding = false;
                }
            }
        }
    }

    StyledFlickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentHeight: listCol.implicitHeight
        flickableDirection: Flickable.VerticalFlick

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: parent
        }

        Column {
            id: listCol
            width: parent.width
            spacing: Tokens.spacing.small

            Repeater {
                model: ScriptModel {
                    values: Startup.entries
                }

                StyledRect {
                    id: entryRow

                    required property var modelData

                    width: listCol.width
                    implicitHeight: entryLayout.implicitHeight + Tokens.padding.medium * 2
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3surfaceContainerHigh
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.25)
                    opacity: entryRow.modelData.enabled ? 1 : 0.55

                    Row {
                        id: entryLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.large
                        anchors.rightMargin: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        IconImage {
                            id: entryIcon
                            anchors.verticalCenter: parent.verticalCenter
                            asynchronous: true
                            source: Icons.getAppIcon(entryRow.modelData.icon || entryRow.modelData.name, entryRow.modelData.source === "systemd" ? "application-x-executable" : "application-x-executable")
                            implicitSize: 32
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - parent.spacing * 3 - entryIcon.width - sw.width - rm.width

                            StyledText {
                                width: parent.width
                                text: entryRow.modelData.name
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                text: (entryRow.modelData.source === "systemd" ? "⚙ " : "") + entryRow.modelData.exec
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.mono.small
                                elide: Text.ElideMiddle
                            }
                        }

                        StyledSwitch {
                            id: sw
                            anchors.verticalCenter: parent.verticalCenter
                            checked: entryRow.modelData.enabled
                            onToggled: Startup.toggle(entryRow.modelData)
                        }

                        MaterialIcon {
                            id: rm
                            anchors.verticalCenter: parent.verticalCenter
                            text: "delete"
                            color: rmLayer.containsMouse ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                            scale: rmLayer.pressed ? 0.9 : 1

                            Behavior on scale {
                                Anim {
                                    type: rmLayer.pressed ? Anim.FastSpatial : Anim.Emphasized
                                }
                            }

                            StateLayer {
                                id: rmLayer
                                anchors.centerIn: parent
                                implicitWidth: parent.implicitHeight + Tokens.padding.small
                                implicitHeight: implicitWidth
                                radius: Tokens.rounding.full
                                onClicked: Startup.remove(entryRow.modelData)
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: Startup.entries.length === 0 && !Startup.scanning
                width: parent.width
                topPadding: Tokens.padding.large
                text: qsTr("Nothing runs at startup yet.")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }
    }
}
