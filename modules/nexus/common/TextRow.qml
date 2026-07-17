import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

ConnectedRect {
    id: root

    property alias label: label.text
    property string subtext
    property string value
    property alias placeholder: field.placeholderText
    // Live field content — `value` only feeds the field, edits don't write back
    readonly property alias fieldText: field.text

    signal committed(value: string)

    // User edits break the field.text binding; push later value changes manually
    onValueChanged: field.text = value

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + Tokens.padding.medium * 2

    RowLayout {
        id: row

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
                id: label

                anchors.left: parent.left
                anchors.right: parent.right
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                anchors.left: parent.left
                anchors.right: parent.right
                visible: root.subtext
                text: root.subtext
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        StyledTextField {
            id: field

            Layout.preferredWidth: 240
            text: root.value
            font: Tokens.font.body.small

            onEditingFinished: {
                if (text !== root.value)
                    root.committed(text);
            }
        }
    }
}
