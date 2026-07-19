pragma ComponentBehavior: Bound

import QtQuick
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
//
// The whole thing is ONE virtualized ListView (it scrolls itself — hosts must
// give it a height, not wrap it in a Flickable). Section headers are sentinel
// entries in the model and rows are keyed by exe path, so delegates survive
// daemon rule pushes and search keystrokes instead of being rebuilt.
Item {
    id: root

    required property var rules            // [{exe, action, name, ...}]
    property bool animate: true            // fade-in when opening

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

    property bool positiveOpen: true
    property bool negativeOpen: true

    property string searchText: ""
    readonly property string query: searchText.trim().toLowerCase()

    // Model entries are exe strings (stable identity) so ScriptModel keeps
    // delegates alive across rule pushes; row details come from this map.
    readonly property var ruleByExe: {
        const map = {};
        for (const r of rules)
            map[r.exe] = r;
        return map;
    }

    readonly property var positives: sortedExes(r => r.action === positiveAction)
    readonly property var negatives: sortedExes(r => r.action !== positiveAction)

    // Section headers as sentinels inline in the one list model; exe paths
    // are absolute so a leading NUL can't collide.
    readonly property string hdrPositive: "\u0000+"
    readonly property string hdrNegative: "\u0000-"

    readonly property var listModel: {
        const out = [];
        if (positives.length > 0) {
            out.push(hdrPositive);
            if (positiveOpen || query)
                out.push(...positives);
        }
        if (negatives.length > 0) {
            out.push(hdrNegative);
            if (negativeOpen || query)
                out.push(...negatives);
        }
        return out;
    }

    // Built once instead of per row — the builder chain allocates.
    readonly property var rowTitleFont: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    readonly property var segFont: Tokens.font.body.builders.small.weight(Font.Medium).build()

    function sortedExes(pred: var): var {
        return rules.filter(r => pred(r) && (!query || (r.name ?? "").toLowerCase().includes(query) || (r.exe ?? "").toLowerCase().includes(query))).sort((a, b) => (a.name ?? a.exe).localeCompare(b.name ?? b.exe)).map(r => r.exe);
    }

    StyledListView {
        id: list

        anchors.fill: parent
        clip: true
        spacing: Tokens.spacing.small
        flickableDirection: Flickable.VerticalFlick

        model: ScriptModel {
            values: root.listModel
        }

        opacity: root.animate ? 0 : 1
        Component.onCompleted: opacity = 1

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: list
        }

        header: Column {
            width: list.width
            spacing: Tokens.spacing.small
            bottomPadding: Tokens.spacing.small

            SearchBar {
                width: parent.width
                visible: root.rules.length > 0
                placeholderText: qsTr("Search apps…")
                onTextChanged: root.searchText = text
            }

            StyledText {
                visible: root.positives.length === 0 && root.negatives.length === 0
                width: parent.width
                topPadding: Tokens.padding.large
                text: root.rules.length === 0 ? root.emptyText : qsTr("No apps match “%1”.").arg(root.query)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }
        }

        add: Transition {
            Anim {
                properties: "opacity"
                from: 0
                to: 1
            }
        }

        displaced: Transition {
            Anim {
                properties: "x,y"
            }
        }

        delegate: Item {
            id: entry

            required property string modelData
            readonly property bool isHeader: modelData.charCodeAt(0) === 0

            width: ListView.view.width
            implicitHeight: (headLoader.item ?? rowLoader.item)?.implicitHeight ?? 0

            Loader {
                id: headLoader
                width: parent.width
                active: entry.isHeader
                sourceComponent: SectionHead {
                    positive: entry.modelData === root.hdrPositive
                }
            }

            Loader {
                id: rowLoader
                width: parent.width
                active: !entry.isHeader
                sourceComponent: RuleRow {
                    rule: root.ruleByExe[entry.modelData] ?? null
                }
            }
        }
    }

    component SectionHead: Item {
        id: section

        required property bool positive
        readonly property bool expanded: (positive ? root.positiveOpen : root.negativeOpen) || root.query.length > 0
        readonly property int count: positive ? root.positives.length : root.negatives.length

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
            onClicked: {
                if (section.positive)
                    root.positiveOpen = !root.positiveOpen;
                else
                    root.negativeOpen = !root.negativeOpen;
            }
        }

        Row {
            id: headRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: section.positive ? root.positiveIcon : root.negativeIcon
                fill: 1
                color: section.positive ? root.positiveAccent : root.negativeAccent
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("%1 (%2)").arg(section.positive ? root.positiveTitle : root.negativeTitle).arg(section.count)
                color: Colours.palette.m3onSurface
                font: root.rowTitleFont
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

    component RuleRow: StyledRect {
        id: row

        required property var rule
        readonly property bool positive: rule?.action === root.positiveAction
        readonly property string appName: rule?.name || (rule?.exe ?? "").split("/").pop()

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
                    text: row.rule?.name ?? ""
                    color: Colours.palette.m3onSurface
                    font: root.rowTitleFont
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: root.detailFor ? root.detailFor(row.rule) : (row.rule?.exe ?? "")
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
                        onClicked: root.setRule(row.rule.exe, root.positiveAction, row.rule.name)
                    }
                    SegButton {
                        id: negSeg
                        label: root.negativeLabel
                        active: !row.positive
                        accent: root.negativeAccent
                        onColour: root.negativeOn
                        onClicked: root.setRule(row.rule.exe, root.negativeAction, row.rule.name)
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
                    onClicked: root.delRule(row.rule.exe)
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
            font: root.segFont

            Behavior on color {
                CAnim {}
            }
        }
    }
}
