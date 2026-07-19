import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.services

LauncherItem {
    id: root

    readonly property string math: list.search.text.slice(`${GlobalConfig.launcher.actionPrefix}calc `.length)

    onMathChanged: {
        if (math.length > 0)
            Qalculator.evalAsync(math);
    }

    onTriggered: {
        Quickshell.execDetached(["wl-copy", Qalculator.rawResult]);
        list.screenState.launcher = false;
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        spacing: Tokens.spacing.medium

        Tile {
            icon: "function"

            // RowLayout ignores the anchored-to-parent sizing Tile defaults to
            anchors.verticalCenter: undefined
            implicitHeight: root.height - Tokens.padding.small * 2
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            id: result

            color: {
                if (text.includes("error: ") || text.includes("warning: "))
                    return Colours.palette.m3error;
                if (!root.math)
                    return Colours.palette.m3onSurfaceVariant;
                return Colours.palette.m3onSurface;
            }

            text: root.math.length > 0 ? (Qalculator.result || qsTr("Calculating...")) : qsTr("Type an expression to calculate")
            font: Tokens.font.body.medium
            elide: Text.ElideLeft

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }

        StyledRect {
            color: Colours.palette.m3tertiary
            radius: Tokens.rounding.large
            clip: true

            implicitWidth: (stateLayer.containsMouse ? label.implicitWidth + label.anchors.rightMargin : 0) + icon.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: Math.max(label.implicitHeight, icon.implicitHeight) + Tokens.padding.small

            Layout.alignment: Qt.AlignVCenter

            scale: stateLayer.pressed ? 0.97 : 1

            Behavior on scale {
                Anim {
                    type: stateLayer.pressed ? Anim.FastSpatial : Anim.Emphasized
                }
            }

            StateLayer {
                id: stateLayer

                onClicked: {
                    Quickshell.execDetached([...GlobalConfig.general.apps.terminal, "fish", "-C", `exec qalc -i '${root.math}'`]);
                    root.list.screenState.launcher = false;
                }

                color: Colours.palette.m3onTertiary
            }

            StyledText {
                id: label

                anchors.verticalCenter: parent.verticalCenter
                anchors.right: icon.left
                anchors.rightMargin: Tokens.spacing.small

                text: qsTr("Open in calculator")
                color: Colours.palette.m3onTertiary
                font: Tokens.font.label.medium

                opacity: stateLayer.containsMouse ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            MaterialIcon {
                id: icon

                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Tokens.padding.medium

                text: "open_in_new"
                color: Colours.palette.m3onTertiary
                fontStyle: Tokens.font.icon.large
            }

            Behavior on implicitWidth {
                Anim {
                    type: Anim.Emphasized
                }
            }
        }
    }
}
