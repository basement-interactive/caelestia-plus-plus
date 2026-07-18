pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Shared header for each security-center tab: leading icon, title, a status
// subtitle, and an optional master on/off switch on the right.
Item {
    id: root

    property string icon: "shield"
    property string title
    property string subtitle
    property bool subtitleError: false
    property color accent: Colours.palette.m3primary
    property bool showSwitch: false
    property bool switchOn: false

    signal toggled

    implicitHeight: Math.max(row.implicitHeight, sw.implicitHeight)

    Row {
        id: row
        anchors.left: parent.left
        anchors.right: sw.visible ? sw.left : parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Tokens.spacing.medium
        spacing: Tokens.spacing.medium

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            fill: 1
            color: root.accent
            fontStyle: Tokens.font.icon.large
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: row.width - row.spacing - 32

            StyledText {
                text: root.title
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.builders.large.weight(Font.Bold).build()
            }

            StyledText {
                width: parent.width
                text: root.subtitle
                color: root.subtitleError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }
        }
    }

    StyledSwitch {
        id: sw
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showSwitch
        checked: root.switchOn
        onToggled: root.toggled()
    }
}
