pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// HTTP Debugger: a mitmproxy-backed flow inspector. Capture, inspect, resend,
// and — with intercept on — hold requests to modify or block before they go
// out. HTTPS needs the CA trusted (one pkexec step). Three states: not
// installed, stopped, running (flow list ⇄ per-flow detail).
Item {
    id: root

    property string selectedId: ""
    readonly property var selectedFlow: Http.flows.find(f => f.id === root.selectedId) ?? null

    readonly property color good: "#4bd97b"
    readonly property color warn: "#ffc233"
    readonly property color bad: "#ff5c5c"

    function methodColour(m) {
        switch (m) {
        case "GET":
            return good;
        case "POST":
        case "PUT":
        case "PATCH":
            return warn;
        case "DELETE":
            return bad;
        default:
            return Colours.palette.m3primary;
        }
    }
    function statusColour(s) {
        if (s >= 500)
            return bad;
        if (s >= 400)
            return warn;
        if (s >= 300)
            return Colours.palette.m3primary;
        if (s >= 200)
            return good;
        return Colours.palette.m3outline;
    }

    onSelectedIdChanged: if (selectedId) Http.requestDetail(selectedId)

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.medium

        TabHeader {
            Layout.fillWidth: true
            icon: "travel_explore"
            title: qsTr("HTTP Debugger")
            accent: Http.running ? Colours.palette.m3primary : Colours.palette.m3outline
            subtitle: !Http.installed ? qsTr("mitmproxy not installed") : Http.running ? qsTr("Proxy on 127.0.0.1:%1 · %2 flows").arg(Http.port).arg(Http.flows.length) : qsTr("Stopped")
            showSwitch: Http.installed
            switchOn: Http.running
            onToggled: Http.toggle()
        }

        // -- Not installed --------------------------------------------------- #
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.padding.large
            visible: !Http.installed
            spacing: Tokens.spacing.medium

            StyledText {
                Layout.fillWidth: true
                text: qsTr("The HTTP debugger routes traffic through a local mitmproxy so you can inspect, resend, intercept, modify and block HTTP/HTTPS requests. It's an explicit localhost proxy, so it coexists with your VPN.")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
                wrapMode: Text.WordWrap
            }

            TextButton {
                text: qsTr("Install mitmproxy")
                onClicked: Http.install()
            }
        }

        // -- Stopped --------------------------------------------------------- #
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.padding.large
            visible: Http.installed && !Http.running
            text: qsTr("Turn on the proxy to start capturing. Point an app at 127.0.0.1:%1, or use “Route system apps” below once it's running. HTTPS needs the CA trusted (offered on first run).").arg(Http.port)
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
            wrapMode: Text.WordWrap
        }

        // -- Running: controls ---------------------------------------------- #
        RowLayout {
            Layout.fillWidth: true
            visible: Http.running && root.selectedId === ""
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "pan_tool"
                text: qsTr("Intercept")
                inactiveColour: Http.intercept ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh
                inactiveOnColour: Http.intercept ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                onClicked: Http.setIntercept(!Http.intercept)
            }

            IconTextButton {
                icon: "lan"
                text: qsTr("Route system apps")
                inactiveColour: Http.systemProxy ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh
                inactiveOnColour: Http.systemProxy ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                onClicked: Http.setSystemProxy(!Http.systemProxy)
            }

            Item {
                Layout.fillWidth: true
            }

            IconButton {
                icon: "delete_sweep"
                type: IconButton.Tonal
                onClicked: Http.clear()
            }
        }

        // CA-trust nudge while running undecrypted.
        StyledRect {
            Layout.fillWidth: true
            visible: Http.running && !Http.caTrusted && root.selectedId === ""
            implicitHeight: caRow.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.small
            color: Qt.alpha(root.warn, 0.12)

            RowLayout {
                id: caRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "lock_open"
                    color: root.warn
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("HTTPS flows stay encrypted until mitmproxy's CA is trusted.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }

                TextButton {
                    text: qsTr("Trust CA")
                    type: TextButton.Tonal
                    onClicked: Http.trustCa()
                }
            }
        }

        // -- Running: flow list --------------------------------------------- #
        StyledClippingRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Http.running && root.selectedId === ""
            radius: Tokens.rounding.small
            color: Colours.palette.m3surface

            StyledListView {
                id: flowList

                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                clip: true
                spacing: Tokens.spacing.extraSmall / 2

                model: ScriptModel {
                    values: Http.flows
                }

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: flowList
                }

                delegate: StyledRect {
                    id: flowRow

                    required property var modelData

                    width: ListView.view.width
                    implicitHeight: flowLine.implicitHeight + Tokens.padding.medium * 2
                    radius: Tokens.rounding.small
                    color: flowRow.modelData.held ? Qt.alpha(root.warn, 0.15) : rowLayer.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent"

                    StateLayer {
                        id: rowLayer
                        radius: parent.radius
                        onClicked: root.selectedId = flowRow.modelData.id
                    }

                    RowLayout {
                        id: flowLine
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        StyledText {
                            Layout.preferredWidth: 52
                            text: flowRow.modelData.method
                            color: root.methodColour(flowRow.modelData.method)
                            font: Tokens.font.mono.builders.small.weight(Font.Bold).build()
                        }

                        StyledText {
                            Layout.preferredWidth: 34
                            text: flowRow.modelData.held ? "•••" : (flowRow.modelData.status || "")
                            color: flowRow.modelData.held ? root.warn : root.statusColour(flowRow.modelData.status)
                            font: Tokens.font.mono.builders.small.weight(Font.Bold).build()
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: flowRow.modelData.url
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.mono.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: flowRow.modelData.ms > 0
                            text: qsTr("%1ms").arg(flowRow.modelData.ms)
                            color: Colours.palette.m3outline
                            font: Tokens.font.body.small
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: flowList.count === 0
                    width: parent.width - Tokens.padding.large * 2
                    horizontalAlignment: Text.AlignHCenter
                    text: Http.intercept ? qsTr("Intercepting — waiting for a request…") : qsTr("Waiting for traffic. Point an app at the proxy.")
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.medium
                    wrapMode: Text.WordWrap
                }
            }
        }

        // -- Detail / editor ------------------------------------------------- #
        FlowDetail {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.selectedId !== ""
            flow: root.selectedFlow
            onBack: root.selectedId = ""
        }
    }

    // Per-flow detail. For a held request it's an editor (method/url/headers/
    // body) with Resume/Block; otherwise a read-only request+response view with
    // Resend.
    component FlowDetail: ColumnLayout {
        id: fd

        required property var flow
        signal back

        readonly property bool held: fd.flow?.held ?? false
        readonly property var detail: Http.detail && Http.detail.id === fd.flow?.id ? Http.detail : null

        spacing: Tokens.spacing.medium

        // Prefill editor fields when a held flow's detail arrives.
        onDetailChanged: {
            if (fd.held && fd.detail) {
                methodField.text = fd.flow.method;
                urlField.text = fd.flow.url;
                headerEdit.text = fd.detail.reqHeaders.map(h => `${h[0]}: ${h[1]}`).join("\n");
                bodyEdit.text = fd.detail.reqBody.binary ? "" : fd.detail.reqBody.text;
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconButton {
                icon: "arrow_back"
                type: IconButton.Text
                onClicked: fd.back()
            }

            StyledText {
                Layout.fillWidth: true
                text: fd.flow ? `${fd.flow.method} ${fd.flow.url}` : ""
                color: Colours.palette.m3onSurface
                font: Tokens.font.mono.builders.small.weight(Font.Medium).build()
                elide: Text.ElideMiddle
            }

            StyledRect {
                visible: fd.held
                implicitWidth: heldLabel.implicitWidth + Tokens.padding.medium
                implicitHeight: heldLabel.implicitHeight + Tokens.padding.small
                radius: Tokens.rounding.full
                color: Qt.alpha(root.warn, 0.18)
                StyledText {
                    id: heldLabel
                    anchors.centerIn: parent
                    text: qsTr("HELD")
                    color: root.warn
                    font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                }
            }
        }

        // Scroll region: editor (held) or read-only view.
        StyledClippingRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.rounding.small
            color: Colours.palette.m3surface

            StyledFlickable {
                id: detailScroll
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                clip: true
                contentHeight: detailCol.implicitHeight
                flickableDirection: Flickable.VerticalFlick

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: detailScroll
                }

                ColumnLayout {
                    id: detailCol
                    width: detailScroll.width
                    spacing: Tokens.spacing.small

                    // Editor for held requests.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: fd.held
                        spacing: Tokens.spacing.small

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small
                            StyledTextField {
                                id: methodField
                                Layout.preferredWidth: 90
                                placeholderText: qsTr("Method")
                            }
                            StyledTextField {
                                id: urlField
                                Layout.fillWidth: true
                                placeholderText: qsTr("URL")
                            }
                        }

                        SectionLabel {
                            text: qsTr("Request headers (one per line)")
                        }
                        EditArea {
                            id: headerEdit
                            Layout.fillWidth: true
                            Layout.preferredHeight: 120
                        }

                        SectionLabel {
                            text: qsTr("Request body")
                        }
                        EditArea {
                            id: bodyEdit
                            Layout.fillWidth: true
                            Layout.preferredHeight: 140
                        }
                    }

                    // Read-only view for completed flows.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !fd.held
                        spacing: Tokens.spacing.small

                        SectionLabel {
                            text: qsTr("Request headers")
                        }
                        HeaderView {
                            Layout.fillWidth: true
                            headers: fd.detail?.reqHeaders ?? []
                        }
                        BodyView {
                            Layout.fillWidth: true
                            body: fd.detail?.reqBody ?? null
                            label: qsTr("Request body")
                        }

                        SectionLabel {
                            text: qsTr("Response · %1").arg(fd.flow?.status || "…")
                        }
                        HeaderView {
                            Layout.fillWidth: true
                            headers: fd.detail?.respHeaders ?? []
                        }
                        BodyView {
                            Layout.fillWidth: true
                            body: fd.detail?.respBody ?? null
                            label: qsTr("Response body")
                        }
                    }
                }
            }
        }

        // Actions.
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            TextButton {
                visible: !fd.held
                text: qsTr("Resend")
                type: TextButton.Tonal
                onClicked: if (fd.flow) Http.replay(fd.flow.id)
            }

            Item {
                Layout.fillWidth: true
            }

            TextButton {
                visible: fd.held
                text: qsTr("Block")
                type: TextButton.Tonal
                inactiveColour: Qt.alpha(root.bad, 0.15)
                inactiveOnColour: root.bad
                onClicked: {
                    if (fd.flow)
                        Http.block(fd.flow.id);
                    fd.back();
                }
            }

            TextButton {
                visible: fd.held
                text: qsTr("Resume")
                onClicked: {
                    if (fd.flow) {
                        const headers = headerEdit.text.split("\n").map(l => {
                            const i = l.indexOf(":");
                            return i > 0 ? [l.slice(0, i).trim(), l.slice(i + 1).trim()] : null;
                        }).filter(Boolean);
                        Http.resume(fd.flow.id, {
                            method: methodField.text.trim(),
                            url: urlField.text.trim(),
                            headers: headers,
                            body: bodyEdit.text
                        });
                    }
                    fd.back();
                }
            }
        }
    }

    component SectionLabel: StyledText {
        color: Colours.palette.m3primary
        font: Tokens.font.body.builders.small.weight(Font.Bold).build()
    }

    component HeaderView: Column {
        property var headers: []
        spacing: 0

        Repeater {
            model: parent.headers
            RowLayout {
                required property var modelData
                width: parent.width
                spacing: Tokens.spacing.small
                StyledText {
                    Layout.alignment: Qt.AlignTop
                    Layout.maximumWidth: 180
                    text: modelData[0]
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.mono.small
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: modelData[1]
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.mono.small
                    wrapMode: Text.WrapAnywhere
                }
            }
        }

        StyledText {
            visible: parent.headers.length === 0
            text: qsTr("(none)")
            color: Colours.palette.m3outline
            font: Tokens.font.mono.small
        }
    }

    component BodyView: Column {
        property var body: null
        property string label
        width: parent.width
        spacing: Tokens.spacing.extraSmall / 2
        visible: body && (body.text.length > 0 || body.binary)

        StyledText {
            text: parent.label + (parent.body?.truncated ? qsTr(" (truncated)") : "")
            color: Colours.palette.m3primary
            font: Tokens.font.body.builders.small.weight(Font.Bold).build()
            topPadding: Tokens.padding.small
        }

        TextEdit {
            width: parent.width
            text: parent.body?.text ?? ""
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            color: Colours.palette.m3onSurface
            selectionColor: Colours.palette.m3primary
            selectedTextColor: Colours.palette.m3onPrimary
            font: Tokens.font.mono.small
        }
    }

    // Editable multiline field with a bordered surface.
    component EditArea: StyledRect {
        property alias text: edit.text
        radius: Tokens.rounding.small
        color: Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.3)

        StyledFlickable {
            anchors.fill: parent
            anchors.margins: Tokens.padding.small
            clip: true
            contentHeight: edit.implicitHeight
            flickableDirection: Flickable.VerticalFlick

            TextEdit {
                id: edit
                width: parent.width
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: Colours.palette.m3onSurface
                selectionColor: Colours.palette.m3primary
                selectedTextColor: Colours.palette.m3onPrimary
                font: Tokens.font.mono.small
            }
        }
    }
}
