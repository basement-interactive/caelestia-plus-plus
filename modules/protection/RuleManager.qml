pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

// Generic per-executable rule manager shared by the Firewall and Protection
// tabs: two collapsible sections (a positive verdict and a negative one), each
// row an app with a segmented two-way control and a delete button, plus a
// search box. The host binds the rule data and the verdict/delete callbacks;
// the two verdicts differ only in label/colour (allow/deny vs allow/block).
Item {
    id: root

    required property var rules            // [{exe, action, name, ...}]
    property bool animate: true            // staggered entrance when opening

    property string positiveAction: "allow"
    property string negativeAction: "deny"
    property string positiveLabel: qsTr("Allow")
    property string negativeLabel: qsTr("Deny")
    property string positiveTitle: qsTr("Approved")
    property string negativeTitle: qsTr("Denied")
    property string positiveIcon: "check_circle"
    property string negativeIcon: "block"
    property color positiveAccent: Colours.palette.m3primary
    property color negativeAccent: Colours.palette.m3error
    property color positiveOn: Colours.palette.m3onPrimary
    property color negativeOn: Colours.palette.m3onError
    property string emptyText: qsTr("No rules yet.")
    // Optional per-row secondary line; defaults to the exe path.
    property var detailFor: null

    signal setRule(string exe, string action, string name)
    signal delRule(string exe)

    readonly property string query: (search.text ?? "").trim().toLowerCase()
    readonly property var filtered: [...rules].filter(r => !query || (r.name ?? "").toLowerCase().includes(query) || (r.exe ?? "").toLowerCase().includes(query))
    readonly property var positives: filtered.filter(r => r.action === positiveAction).sort((a, b) => (a.name ?? a.exe).localeCompare(b.name ?? b.exe))
    readonly property var negatives: filtered.filter(r => r.action !== positiveAction).sort((a, b) => (a.name ?? a.exe).localeCompare(b.name ?? b.exe))

    property bool positiveOpen: true
    property bool negativeOpen: true

    implicitHeight: contentCol.implicitHeight

    Column {
        id: contentCol

        width: parent.width
        spacing: Tokens.spacing.small

        Item {
            width: parent.width
            visible: root.rules.length > 0
            implicitHeight: search.implicitHeight

            SearchBar {
                id: search
                anchors.left: parent.left
                anchors.right: parent.right
                placeholderText: qsTr("Search apps…")
            }
        }

        StyledText {
            visible: root.filtered.length === 0
            width: parent.width
            topPadding: Tokens.padding.large
            text: root.rules.length === 0 ? root.emptyText : qsTr("No apps match “%1”.").arg(root.query)
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        RuleSection {
            title: root.positiveTitle
            icon: root.positiveIcon
            accent: root.positiveAccent
            rules: root.positives
            expanded: root.positiveOpen || root.query.length > 0
            onToggled: root.positiveOpen = !root.positiveOpen
        }

        RuleSection {
            title: root.negativeTitle
            icon: root.negativeIcon
            accent: root.negativeAccent
            rules: root.negatives
            expanded: root.negativeOpen || root.query.length > 0
            entranceIndex: 1
            onToggled: root.negativeOpen = !root.negativeOpen
        }
    }

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
        width: contentCol.width
        spacing: Tokens.spacing.small

        opacity: root.animate ? 0 : 1
        Component.onCompleted: opacity = 1

        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation {
                    duration: 90 + section.entranceIndex * 50
                }
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Item {
            id: sectionHead

            width: parent.width
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
        readonly property bool positive: modelData.action === root.positiveAction
        readonly property string appName: modelData.name || (modelData.exe ?? "").split("/").pop()

        width: ListView.view.width
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
                    text: root.detailFor ? root.detailFor(row.modelData) : row.modelData.exe
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.mono.small
                    elide: Text.ElideMiddle
                }
            }

            StyledRect {
                id: seg
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: posSeg.implicitWidth + negSeg.implicitWidth
                implicitHeight: posSeg.implicitHeight
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerLowest

                Row {
                    SegButton {
                        id: posSeg
                        label: root.positiveLabel
                        active: row.positive
                        accent: root.positiveAccent
                        onColour: root.positiveOn
                        onClicked: root.setRule(row.modelData.exe, root.positiveAction, row.modelData.name)
                    }
                    SegButton {
                        id: negSeg
                        label: root.negativeLabel
                        active: !row.positive
                        accent: root.negativeAccent
                        onColour: root.negativeOn
                        onClicked: root.setRule(row.modelData.exe, root.negativeAction, row.modelData.name)
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
                    onClicked: root.delRule(row.modelData.exe)
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
