pragma ComponentBehavior: Bound

import "popouts" as BarPopouts
import "components"
import "components/workspaces"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

RowLayout {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    // Rounded pill ends need extra inset so end items clear the curvature
    readonly property int hPadding: Tokens.padding.large * 2

    function closeTray(): void {
        if (!Config.bar.tray.compact)
            return;

        for (let i = 0; i < repeater.count; i++) {
            const tray = (repeater.itemAt(i) as EntryWrapper).item as Tray;
            if (tray)
                tray.expanded = false;
        }
    }

    function checkPopout(x: real): void {
        popouts.lastCheckX = x;
        const ch = childAt(x, height / 2) as EntryWrapper;

        if (ch?.entryId !== "tray")
            closeTray();

        if (!ch) {
            popouts.hasCurrent = false;
            return;
        }

        const id = ch.entryId;
        const left = ch.x;

        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            const items = (ch.item as StatusIcons).items;
            const icon = items.childAt(mapToItem(items, x, 0).x, items.height / 2);
            if (icon) {
                popouts.currentName = icon.name;
                popouts.currentCenter = Qt.binding(() => icon.mapToItem(null, icon.implicitWidth / 2, 0).x);
                popouts.hasCurrent = true;
            } else {
                popouts.hasCurrent = false;
            }
        } else if (id === "tray" && Config.bar.popouts.tray) {
            const tray = ch.item as Tray;
            if (!Config.bar.tray.compact || (tray.expanded && !tray.expandIcon.contains(mapToItem(tray.expandIcon, x, tray.implicitHeight / 2)))) {
                const index = Math.floor(((x - left - tray.padding * 2 + tray.spacing) / tray.layout.implicitWidth) * tray.items.count);
                const trayItem = tray.items.itemAt(index);
                if (trayItem) {
                    popouts.currentName = `traymenu${index}`;
                    popouts.currentCenter = Qt.binding(() => trayItem.mapToItem(null, trayItem.implicitWidth / 2, 0).x);
                    popouts.hasCurrent = true;
                } else {
                    popouts.hasCurrent = false;
                }
            } else {
                popouts.hasCurrent = false;
                tray.expanded = true;
            }
        } else {
            // Entries without a popout of their own (firewall, features, …):
            // clear any popout left open from a neighbouring entry, so it
            // never overlaps their click menus.
            popouts.hasCurrent = false;
        }
    }

    function handleWheel(x: real, angleDelta: point): void {
        const ch = childAt(x, height / 2) as EntryWrapper;
        if (ch?.entryId === "workspaces" && Config.bar.scrollActions.workspaces) {
            // Workspace scroll
            const mon = (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor);
            const specialWs = mon?.lastIpcObject.specialWorkspace.name;
            if (specialWs?.length > 0)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${specialWs.slice(8)}")` : `togglespecialworkspace ${specialWs.slice(8)}`);
            else if (angleDelta.y < 0 || (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? mon.activeWorkspace?.id : Hypr.activeWsId) > 1)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "r${angleDelta.y > 0 ? "-" : "+"}1" })` : `workspace r${angleDelta.y > 0 ? "-" : "+"}1`);
        } else if (x < screen.width / 2 && Config.bar.scrollActions.volume) {
            // Volume scroll on left half
            if (angleDelta.y > 0)
                Audio.incrementVolume();
            else if (angleDelta.y < 0)
                Audio.decrementVolume();
        } else if (Config.bar.scrollActions.brightness) {
            // Brightness scroll on right half
            const monitor = Brightness.getMonitorForScreen(screen);
            if (angleDelta.y > 0)
                monitor.setBrightness(monitor.brightness + GlobalConfig.services.brightnessIncrement);
            else if (angleDelta.y < 0)
                monitor.setBrightness(monitor.brightness - GlobalConfig.services.brightnessIncrement);
        }
    }
    spacing: Tokens.spacing.medium

    Repeater {
        id: repeater

        model: ScriptModel {
            // Endcap style: the logo caps the pill, so any "logo" entry from
            // the user's config is dropped (stock configs ship one). Inline
            // style: keep the config's logo entry, or lead with one if absent.
            // The features wrench disappears when no feature applies (desktop).
            values: {
                const entries = root.Config.bar.entries.filter(e => (e.enabled ?? true)
                    && !(e.id === "features" && Features.features.length === 0)
                    && !(e.id === "activeWindow" && !ShellPrefs.barShowActiveWindow));
                if (ShellPrefs.barLogoEndcap || !ShellPrefs.barLogoShow)
                    return entries.filter(e => e.id !== "logo");
                return entries.some(e => e.id === "logo") ? entries : [{
                    id: "logo"
                }].concat(entries);
            }
        }

        DelegateChooser {
            role: "id"

            DelegateChoice {
                roleValue: "spacer"
                delegate: EntryWrapper {
                    Layout.fillWidth: true
                }
            }
            DelegateChoice {
                roleValue: "logo"
                delegate: EntryWrapper {
                    OsIcon {
                        objectName: "taskbarLogo"
                    }
                }
            }
            DelegateChoice {
                roleValue: "workspaces"
                delegate: EntryWrapper {
                    WorkspaceNumbers {
                        objectName: "taskbarWorkspaces"
                        screen: root.screen
                        fullscreen: root.fullscreen
                    }
                }
            }
            DelegateChoice {
                roleValue: "activeWindow"
                delegate: EntryWrapper {
                    ActiveWindow {
                        objectName: "taskbarActiveWindow"
                        bar: root
                        monitor: Brightness.getMonitorForScreen(root.screen)
                    }
                }
            }
            DelegateChoice {
                roleValue: "firewall"
                delegate: EntryWrapper {
                    FirewallButton {
                        objectName: "taskbarFirewall"
                    }
                }
            }
            DelegateChoice {
                roleValue: "features"
                delegate: EntryWrapper {
                    FeaturesButton {
                        objectName: "taskbarFeatures"
                    }
                }
            }
            DelegateChoice {
                roleValue: "tray"
                delegate: EntryWrapper {
                    Tray {
                        objectName: "taskbarTray"
                    }
                }
            }
            DelegateChoice {
                roleValue: "clock"
                delegate: EntryWrapper {
                    Clock {
                        objectName: "taskbarClock"
                        fullscreen: root.fullscreen
                    }
                }
            }
            DelegateChoice {
                roleValue: "statusIcons"
                delegate: EntryWrapper {
                    StatusIcons {
                        objectName: "taskbarStatusIcons"
                    }
                }
            }
            DelegateChoice {
                roleValue: "power"
                delegate: EntryWrapper {
                    Power {
                        objectName: "taskbarPowerButton"
                        screenState: root.screenState
                    }
                }
            }
        }
    }

    component EntryWrapper: Item {
        id: wrapper

        required property var modelData
        required property int index
        default property Item item
        readonly property string entryId: modelData.id

        // Wide clearance only makes sense trailing the endcap logo; with the
        // logo inline or hidden the row starts at the pill's rounded end and
        // gets the same tight padding as the right side
        Layout.leftMargin: index === 0 ? (ShellPrefs.barLogoEndcap && ShellPrefs.barLogoShow ? root.hPadding : Tokens.padding.large) : 0
        // Tighter than the endcap side: the row already ends at the pill
        // edge, and the full hPadding read as a hole before the rounded end
        Layout.rightMargin: index === repeater.count - 1 ? Tokens.padding.large : 0
        Layout.alignment: Qt.AlignVCenter

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        opacity: 0

        transform: Translate {
            id: slide

            y: -wrapper.Tokens.sizes.bar.innerWidth / 2
        }

        Component.onCompleted: entrance.restart()

        SequentialAnimation {
            id: entrance

            PauseAnimation {
                duration: wrapper.index * 50
            }
            ParallelAnimation {
                Anim {
                    target: wrapper
                    property: "opacity"
                    to: 1
                    type: Anim.DefaultEffects
                }
                Anim {
                    target: slide
                    property: "y"
                    to: 0
                    type: Anim.Emphasized
                }
            }
        }

        children: item
    }
}
