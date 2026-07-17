pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property int maxResults: 40
    property string query

    readonly property var filtered: {
        const q = query.toLowerCase();
        return HyprMod.schema.filter(o => !q || o.name.toLowerCase().includes(q) || (o.description ?? "").toLowerCase().includes(q));
    }

    title: qsTr("All options")
    isSubPage: true

    Component.onCompleted: HyprMod.refreshSchema()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledTextField {
            id: searchField

            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.medium
            leadingIcon: "search"
            placeholderText: qsTr("Search %1 compositor options…").arg(HyprMod.schema.length)
            onTextChanged: queryDebounce.restart()

            // Filtering rebuilds up to 40 delegate rows — batch keystrokes
            Timer {
                id: queryDebounce

                interval: 150
                onTriggered: root.query = searchField.text
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Tokens.spacing.small
            visible: root.filtered.length > root.maxResults
            text: qsTr("Showing %1 of %2 matches — keep typing to narrow down").arg(root.maxResults).arg(root.filtered.length)
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
        }

        Repeater {
            model: root.filtered.slice(0, root.maxResults)

            ConnectedRect {
                id: optionRow

                required property var modelData
                required property int index

                readonly property bool isBool: typeof modelData.default === "boolean"
                readonly property bool overridden: HyprMod.overrides[modelData.name] !== undefined
                readonly property var shownValue: HyprMod.optionValue(modelData)

                Layout.fillWidth: true
                first: index === 0
                last: index === Math.min(root.filtered.length, root.maxResults) - 1
                implicitHeight: rowLayout.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: rowLayout

                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    Column {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: optionRow.modelData.name + (optionRow.overridden ? " •" : "")
                            color: optionRow.overridden ? Colours.palette.m3primary : Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            visible: text.length > 0
                            text: {
                                let extra = optionRow.modelData.description ?? "";
                                if (optionRow.modelData.min !== null && optionRow.modelData.max !== null)
                                    extra += qsTr(" (%1–%2)").arg(optionRow.modelData.min).arg(optionRow.modelData.max);
                                return extra;
                            }
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        visible: optionRow.overridden
                        icon: "history"
                        onClicked: HyprMod.unsetOption(optionRow.modelData.name)
                    }

                    StyledSwitch {
                        visible: optionRow.isBool
                        checked: optionRow.shownValue === true || optionRow.shownValue === "true"
                        onToggled: HyprMod.setOption(optionRow.modelData.name, checked)
                    }

                    StyledTextField {
                        visible: !optionRow.isBool
                        Layout.preferredWidth: 140
                        text: String(optionRow.shownValue ?? "")
                        font: Tokens.font.body.small

                        onEditingFinished: {
                            if (text !== String(optionRow.shownValue ?? ""))
                                HyprMod.setOption(optionRow.modelData.name, text);
                        }
                    }
                }
            }
        }
    }
}
