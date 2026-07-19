pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property ScreenState screenState
    required property var panels
    required property real maxHeight
    property real openProgress: 1

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: Tokens.rounding.extraLarge
    readonly property int inset: Tokens.padding.small

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight: search.height + listWrapper.height + padding + search.anchors.bottomMargin

    Item {
        id: listWrapper

        implicitWidth: list.implicitWidth + root.inset * 2
        implicitHeight: header.anchors.topMargin + header.implicitHeight + Tokens.padding.small + list.height + root.inset

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: search.top
        anchors.bottomMargin: root.padding

        transform: Translate {
            y: (1 - root.openProgress) * root.Tokens.padding.large
        }

        StyledRect {
            anchors.fill: parent

            radius: root.rounding
            color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.7)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

            StyledRect {
                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall

                radius: parent.radius - anchors.margins
                color: Colours.tPalette.m3surfaceContainerLow
            }
        }

        Header {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: root.inset + Tokens.padding.small
            anchors.leftMargin: root.inset + Tokens.padding.medium
            anchors.rightMargin: root.inset + Tokens.padding.medium

            mode: list.mode
            count: list.resultCount
        }

        ContentList {
            id: list

            anchors.leftMargin: root.inset
            anchors.rightMargin: root.inset
            anchors.bottomMargin: root.inset

            content: root
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight - search.implicitHeight - root.padding * 3 - header.implicitHeight - Tokens.padding.small * 2
            search: search
            padding: root.padding
            rounding: root.rounding
        }
    }

    SearchBar {
        id: search

        objectName: "launcherSearch"

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
        anchors.bottomMargin: CUtils.clamp(root.padding - Config.border.thickness, 0, root.padding)

        topPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)
        bottomPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)

        bg.border.width: 1
        bg.border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)

        placeholderText: qsTr("Type \"%1\" for commands").arg(GlobalConfig.launcher.actionPrefix)

        onAccepted: {
            const currentItem = list.currentList?.currentItem;
            if (currentItem) {
                if (list.showWallpapers) {
                    if (Colours.scheme === "dynamic" && currentItem.modelData.path !== Wallpapers.actualCurrent)
                        Wallpapers.previewColourLock = true;
                    Wallpapers.setWallpaper(currentItem.modelData.path);
                    root.screenState.launcher = false;
                } else if (text.startsWith(GlobalConfig.launcher.actionPrefix)) {
                    if (text.startsWith(`${GlobalConfig.launcher.actionPrefix}calc `))
                        currentItem.onClicked();
                    else
                        currentItem.modelData.onClicked(list.currentList);
                } else {
                    Apps.launch(currentItem.modelData);
                    root.screenState.launcher = false;
                }
            }
        }

        Keys.onUpPressed: list.currentList?.decrementCurrentIndex()
        Keys.onDownPressed: list.currentList?.incrementCurrentIndex()

        Keys.onEscapePressed: root.screenState.launcher = false

        Keys.onPressed: event => {
            if (!GlobalConfig.launcher.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                    list.currentList?.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                    list.currentList?.decrementCurrentIndex();
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab) {
                list.currentList?.incrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                list.currentList?.decrementCurrentIndex();
                event.accepted = true;
            }
        }

        // Content is preloaded and kept resident (see Wrapper), so the
        // search field must retake focus on every open, not just on creation
        Component.onCompleted: {
            if (root.screenState.launcher)
                forceActiveFocus();
        }

        Connections {
            function onLauncherChanged(): void {
                if (root.screenState.launcher)
                    search.forceActiveFocus();
                else
                    search.text = "";
            }

            function onSessionChanged(): void {
                if (!root.screenState.session && root.screenState.launcher)
                    search.forceActiveFocus();
            }

            target: root.screenState
        }
    }

    // Search icon follows the active mode: mode glyph in primary while a
    // command prefix is active, plain search otherwise.
    Binding {
        target: search.searchIcon
        property: "animate"
        value: true
    }

    Binding {
        target: search.searchIcon
        property: "text"
        value: list.mode === "apps" ? "search" : header.info.icon
    }

    Binding {
        target: search.searchIcon
        property: "color"
        value: list.mode === "apps" ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
    }
}
