pragma ComponentBehavior: Bound

import "./kblayout"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.components

Item {
    id: root

    required property PopoutState popouts
    readonly property Popout currentPopout: content.children.find(c => c.shouldBeActive) ?? null
    readonly property Item current: currentPopout?.item ?? null

    implicitWidth: (currentPopout?.implicitWidth ?? 0) + Tokens.padding.extraLargeIncreased
    implicitHeight: (currentPopout?.implicitHeight ?? 0) + Tokens.padding.extraLargeIncreased

    Item {
        id: content

        anchors.fill: parent
        anchors.margins: Tokens.padding.large

        Popout {
            id: networkPopout

            name: "network"
            sourceComponent: Network {
                popouts: root.popouts
                view: "wireless"
            }
        }

        Popout {
            name: "ethernet"
            sourceComponent: Network {
                popouts: root.popouts
                view: "ethernet"
            }
        }

        Popout {
            id: passwordPopout

            name: "wirelesspassword"
            sourceComponent: WirelessPassword {
                id: passwordComponent

                popouts: root.popouts
                network: (networkPopout.item as Network)?.passwordNetwork ?? null
            }

            Connections {
                function onCurrentNameChanged() {
                    // Update network immediately when password popout becomes active
                    if (root.popouts.currentName === "wirelesspassword") {
                        // Set network immediately if available
                        if ((networkPopout.item as Network)?.passwordNetwork) {
                            if (passwordPopout.item) {
                                (passwordPopout.item as WirelessPassword).network = (networkPopout.item as Network).passwordNetwork;
                            }
                        }
                        // Also try after a short delay in case networkPopout.item wasn't ready
                        Qt.callLater(() => {
                            if (passwordPopout.item && (networkPopout.item as Network)?.passwordNetwork) {
                                (passwordPopout.item as WirelessPassword).network = (networkPopout.item as Network).passwordNetwork;
                            }
                        }, 100);
                    }
                }

                target: root.popouts
            }

            Connections {
                function onItemChanged() {
                    // When network popout loads, update password popout if it's active
                    if (root.popouts.currentName === "wirelesspassword" && passwordPopout.item) {
                        Qt.callLater(() => {
                            if ((networkPopout.item as Network)?.passwordNetwork) {
                                (passwordPopout.item as WirelessPassword).network = (networkPopout.item as Network).passwordNetwork;
                            }
                        });
                    }
                }

                target: networkPopout
            }
        }

        Popout {
            name: "bluetooth"
            sourceComponent: Bluetooth {
                popouts: root.popouts
            }
        }

        Popout {
            name: "battery"
            sourceComponent: Battery {}
        }

        Popout {
            name: "audio"
            sourceComponent: Audio {
                popouts: root.popouts
            }
        }

        Popout {
            name: "kblayout"
            sourceComponent: KbLayout {}
        }

        Popout {
            name: "lockstatus"
            sourceComponent: LockStatus {}
        }

        Repeater {
            model: ScriptModel {
                values: SystemTray.items.values.filter(i => !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))
            }

            Popout {
                id: trayMenu

                required property SystemTrayItem modelData
                required property int index

                name: `traymenu${index}`
                sourceComponent: trayMenuComp

                Connections {
                    function onHasCurrentChanged(): void {
                        if (root.popouts.hasCurrent && trayMenu.shouldBeActive) {
                            trayMenu.sourceComponent = null;
                            trayMenu.sourceComponent = trayMenuComp;
                        }
                    }

                    target: root.popouts
                }

                Component {
                    id: trayMenuComp

                    TrayMenu {
                        popouts: root.popouts
                        trayItem: trayMenu.modelData.menu // qmllint disable unresolved-type
                    }
                }
            }
        }
    }

    component Popout: Loader {
        id: popout

        required property string name
        readonly property bool shouldBeActive: root.popouts.currentName === name
        // Reveal only once the async load finished: starting the entrance
        // while the Loader instantiates blocks the GUI thread (~300ms for
        // Network) and the timeline-based animation skips its first frames,
        // which reads as extreme choppiness across the whole shell.
        readonly property bool revealed: shouldBeActive && status === Loader.Ready
        // Latched after first load so warm hovers reveal instantly instead
        // of paying an async reload pause on every open.
        property bool keepAlive: false

        anchors.centerIn: parent

        opacity: 0
        asynchronous: true
        active: shouldBeActive || keepAlive
        onStatusChanged: {
            if (status === Loader.Ready)
                keepAlive = true;
        }
        // Kept-alive popouts must not render (or animate) while hidden.
        visible: opacity > 0

        // Entrance choreography: descend from the bar while fading in
        transform: Translate {
            id: slide

            y: -popout.Tokens.padding.large
        }

        states: State {
            name: "active"
            when: popout.revealed

            PropertyChanges {
                popout.opacity: 1
                slide.y: 0
            }
        }

        transitions: [
            Transition {
                from: "active"
                to: ""

                ParallelAnimation {
                    Anim {
                        property: "opacity"
                        type: Anim.DefaultEffects
                    }
                    Anim {
                        property: "y"
                        type: Anim.Emphasized
                    }
                }
            },
            Transition {
                from: ""
                to: "active"

                ParallelAnimation {
                    Anim {
                        property: "opacity"
                        type: Anim.SlowEffects
                    }
                    Anim {
                        property: "y"
                        type: Anim.Emphasized
                    }
                }
            }
        ]
    }
}
