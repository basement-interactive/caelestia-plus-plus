import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Strip above the results list: animated mode chip on the left, live result
// count on the right.
Item {
    id: root

    required property string mode
    required property int count

    readonly property var info: {
        const modes = {
            apps: { icon: "apps", label: qsTr("Apps") },
            actions: { icon: "bolt", label: qsTr("Actions") },
            calc: { icon: "function", label: qsTr("Calculator") },
            scheme: { icon: "palette", label: qsTr("Schemes") },
            variant: { icon: "format_paint", label: qsTr("Variants") },
            wallpapers: { icon: "wallpaper", label: qsTr("Wallpapers") }
        };
        return modes[mode] ?? modes.apps;
    }

    implicitHeight: chip.implicitHeight

    StyledRect {
        id: chip

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: chipRow.implicitHeight + Tokens.padding.small * 2

        radius: Tokens.rounding.full
        color: Qt.alpha(Colours.palette.m3primary, 0.12)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3primary, 0.25)

        Behavior on implicitWidth {
            Anim {
                type: Anim.Emphasized
            }
        }

        Row {
            id: chipRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                animate: true
                text: root.info.icon
                color: Colours.palette.m3primary
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                animate: true
                text: root.info.label
                color: Colours.palette.m3primary
                font: Tokens.font.label.large
            }
        }
    }

    StyledText {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        visible: root.mode !== "calc"
        text: root.count === 1 ? qsTr("1 result") : qsTr("%1 results").arg(root.count)
        color: Colours.palette.m3outline
        font: Tokens.font.label.medium
    }
}
