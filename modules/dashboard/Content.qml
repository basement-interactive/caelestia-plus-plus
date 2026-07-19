pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.utils
import Quickshell.Io

Item {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker

    readonly property var dashboardTabs: {
        const allTabs = [
            {
                component: dashComponent,
                iconName: "dashboard",
                text: qsTr("Dashboard"),
                enabled: Config.dashboard.showDashboard
            },
            {
                component: mediaComponent,
                iconName: "queue_music",
                text: qsTr("Media"),
                enabled: Config.dashboard.showMedia
            },
            {
                component: performanceComponent,
                iconName: "speed",
                text: qsTr("Performance"),
                enabled: Config.dashboard.showPerformance
            },
            {
                component: weatherComponent,
                iconName: "cloud",
                text: qsTr("Weather"),
                enabled: Config.dashboard.showWeather
            }
        ];
        return allTabs.filter(tab => tab.enabled);
    }

    readonly property real nonAnimWidth: view.implicitWidth + viewWrapper.anchors.margins * 2
    readonly property real nonAnimHeight: tabs.implicitHeight + tabs.anchors.topMargin + view.implicitHeight + viewWrapper.anchors.margins * 2

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    Tabs {
        id: tabs

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: CUtils.clamp(anchors.margins - Config.border.thickness, 0, anchors.margins)
        anchors.margins: Tokens.padding.large

        nonAnimWidth: root.nonAnimWidth - anchors.margins * 2
        screenState: root.screenState
        tabs: root.dashboardTabs
    }

    ClippingRectangle {
        id: viewWrapper

        anchors.top: tabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large

        radius: Tokens.rounding.large
        color: "transparent"

        Flickable {
            id: view

            readonly property int currentIndex: root.screenState.dashboardTab
            readonly property Item currentItem: {
                repeater.count; // Trigger update on count change
                return repeater.itemAt(currentIndex);
            }

            anchors.fill: parent

            flickableDirection: Flickable.HorizontalFlick

            // Panel size follows the largest pane seen so far, not the
            // current tab — per-tab implicit sizes differ and letting them
            // through resized the whole panel on every tab switch
            implicitWidth: row.maxPaneWidth || (currentItem?.implicitWidth ?? 0)
            implicitHeight: row.maxPaneHeight || (currentItem?.implicitHeight ?? 0)

            contentX: currentItem?.x ?? 0
            contentWidth: row.implicitWidth
            contentHeight: row.implicitHeight

            onContentXChanged: {
                if (!moving || !currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 2)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 2)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
            }

            onDragEnded: {
                if (!currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 10)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 10)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
                else
                    contentX = Qt.binding(() => currentItem?.x ?? 0);
            }

            RowLayout {
                id: row

                // Largest pane ever seen; itemAt() isn't notifiable, so
                // the delegates push their size changes here instead.
                // Monotonic on purpose: off-screen panes unload and their
                // implicit size drops to 0 — recomputing a "current" max
                // shrank the panel on every tab switch and regrew it on
                // return. Once locked bigger, the panel never shrinks.
                //
                // The lock persists across shell restarts: without it every
                // session started at 0 and the first visit to a wider/taller
                // tab morphed the panel once per session. Stale after a
                // config/font change that shrinks panes — delete the state
                // file to re-measure.
                property real maxPaneWidth
                property real maxPaneHeight
                property bool seeded: false

                // Called before the first write can happen: the Repeater
                // populates during creation, so no object-lifecycle hook on
                // a sibling runs early enough — the first pane's write used
                // to clobber the persisted lock before an async load could
                // seed it. Blocking on the read here closes that race.
                function seed(): void {
                    if (seeded)
                        return;
                    seeded = true;
                    sizeStore.reload();
                    sizeStore.waitForJob();
                    let saved;
                    try {
                        saved = JSON.parse(sizeStore.text());
                    } catch (e) {
                        return;
                    }
                    maxPaneWidth = Math.max(maxPaneWidth, saved.paneWidth ?? 0);
                    maxPaneHeight = Math.max(maxPaneHeight, saved.paneHeight ?? 0);
                }

                function updateMaxPaneSize(): void {
                    seed();
                    let w = maxPaneWidth;
                    let h = maxPaneHeight;
                    for (let i = 0; i < repeater.count; i++) {
                        const pane = repeater.itemAt(i);
                        if (pane) {
                            w = Math.max(w, pane.implicitWidth);
                            h = Math.max(h, pane.implicitHeight);
                        }
                    }
                    if (w === maxPaneWidth && h === maxPaneHeight)
                        return;
                    maxPaneWidth = w;
                    maxPaneHeight = h;
                    sizeStore.setText(JSON.stringify({paneWidth: w, paneHeight: h}) + "\n");
                }

                FileView {
                    id: sizeStore

                    path: `${Paths.state}/dashboard-size.json`
                    printErrors: false
                }

                Repeater {
                    id: repeater

                    model: ScriptModel {
                        values: root.dashboardTabs
                    }

                    delegate: Loader {
                        id: paneLoader

                        required property int index
                        required property var modelData

                        Layout.alignment: Qt.AlignTop
                        // Uniform slots: every pane gets the full locked
                        // panel size — a smaller pane would otherwise show
                        // the next pane bleeding in at the right edge and
                        // leave a gap below itself
                        Layout.preferredWidth: row.maxPaneWidth || implicitWidth
                        Layout.preferredHeight: row.maxPaneHeight || implicitHeight

                        sourceComponent: modelData.component
                        onImplicitWidthChanged: row.updateMaxPaneSize()
                        onImplicitHeightChanged: row.updateMaxPaneSize()

                        Component.onCompleted: active = Qt.binding(() => {
                            if (index === view.currentIndex)
                                return true;
                            const vx = Math.floor(view.visibleArea.xPosition * view.contentWidth);
                            const vex = Math.floor(vx + view.visibleArea.widthRatio * view.contentWidth);
                            return (vx >= x && vx <= x + implicitWidth) || (vex >= x && vex <= x + implicitWidth);
                        })
                    }
                }
            }

            Component {
                id: dashComponent

                Dash {
                    screenState: root.screenState
                    facePicker: root.facePicker
                }
            }

            Component {
                id: mediaComponent

                Media {
                    screenState: root.screenState
                }
            }

            Component {
                id: performanceComponent

                Performance {}
            }

            Component {
                id: weatherComponent

                WeatherTab {}
            }

            Behavior on contentX {
                Anim {}
            }
        }
    }

    Behavior on implicitWidth {
        Anim {}
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
