pragma ComponentBehavior: Bound

import "items"
import "services"
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import QtQuick

StyledListView {
    id: root

    property StyledTextField search
    required property PersistentProperties visibilities
    property bool allowActions: true
    property var overrideValues: null
    property string closeDrawer: "launcher"
    signal appRightClicked(var entry)
    property bool mouseSelectionEnabled: true
    property bool keyboardNavigationActive: false
    property point lastMousePos: Qt.point(-1, -1)
    property real mouseMoveThreshold: 2

    model: ScriptModel {
        id: model

        onValuesChanged: root.currentIndex = 0
    }

    spacing: Appearance.spacing.small
    orientation: Qt.Vertical
    implicitHeight: (Config.launcher.sizes.itemHeight + spacing) * Math.min(Config.launcher.maxShown, count) - spacing

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: ListView.NoHighlightRange

    highlightFollowsCurrentItem: false
    highlight: StyledRect {
        radius: Appearance.rounding.normal
        color: Colours.palette.m3onSurface
        opacity: 0.08

        y: root.currentItem?.y ?? 0
        implicitWidth: root.width
        implicitHeight: root.currentItem?.implicitHeight ?? 0

        Behavior on y {
            Anim {
                duration: Appearance.anim.durations.expressiveDefaultSpatial
                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
            }
        }
    }

    HoverHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        onPointChanged: {
            if (!root.interactive)
                return;
            const pos = point.position;
            if (root.moving || root.flicking) {
                root.lastMousePos = Qt.point(pos.x, pos.y);
                return;
            }
            if (root.keyboardNavigationActive) {
                if (root.lastMousePos.x < 0 && root.lastMousePos.y < 0) {
                    root.lastMousePos = Qt.point(pos.x, pos.y);
                    return;
                }
                const moved = Math.abs(pos.x - root.lastMousePos.x) + Math.abs(pos.y - root.lastMousePos.y) > root.mouseMoveThreshold;
                if (!moved)
                    return;
                root.keyboardNavigationActive = false;
                root.mouseSelectionEnabled = true;
                root.lastMousePos = Qt.point(pos.x, pos.y);
            } else {
                root.lastMousePos = Qt.point(pos.x, pos.y);
            }

            if (!root.mouseSelectionEnabled)
                return;

            const idx = root.indexAt(pos.x, pos.y);
            if (idx >= 0 && idx !== root.currentIndex)
                root.currentIndex = idx;
        }
    }

    state: {
        if (!root.allowActions)
            return "apps";

        const text = root.search ? root.search.text : "";
        const prefix = Config.launcher.actionPrefix;
        if (text.startsWith(prefix)) {
            for (const action of ["calc", "scheme", "variant"])
                if (text.startsWith(`${prefix}${action} `))
                    return action;

            return "actions";
        }

        return "apps";
    }

    onStateChanged: {
        if (state === "scheme" || state === "variant")
            Schemes.reload();
    }

    states: [
        State {
            name: "apps"

            PropertyChanges {
                model.values: root.overrideValues != null ? root.overrideValues : Apps.search(root.search ? root.search.text : "")
                root.delegate: appItem
            }
        },
        State {
            name: "actions"

            PropertyChanges {
                model.values: Actions.query(root.search ? root.search.text : "")
                root.delegate: actionItem
            }
        },
        State {
            name: "calc"

            PropertyChanges {
                model.values: [0]
                root.delegate: calcItem
            }
        },
        State {
            name: "scheme"

            PropertyChanges {
                model.values: Schemes.query(root.search ? root.search.text : "")
                root.delegate: schemeItem
            }
        },
        State {
            name: "variant"

            PropertyChanges {
                model.values: M3Variants.query(root.search ? root.search.text : "")
                root.delegate: variantItem
            }
        }
    ]

    transitions: Transition {
        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: Appearance.anim.durations.small
                    easing.bezierCurve: Appearance.anim.curves.standardAccel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 1
                    to: 0.9
                    duration: Appearance.anim.durations.small
                    easing.bezierCurve: Appearance.anim.curves.standardAccel
                }
            }
            PropertyAction {
                targets: [model, root]
                properties: "values,delegate"
            }
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Appearance.anim.durations.small
                    easing.bezierCurve: Appearance.anim.curves.standardDecel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 0.9
                    to: 1
                    duration: Appearance.anim.durations.small
                    easing.bezierCurve: Appearance.anim.curves.standardDecel
                }
            }
            PropertyAction {
                targets: [root.add, root.remove]
                property: "enabled"
                value: true
            }
        }
    }

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    add: Transition {
        enabled: !root.state

        Anim {
            properties: "opacity,scale"
            from: 0
            to: 1
        }
    }

    remove: Transition {
        enabled: !root.state

        Anim {
            properties: "opacity,scale"
            from: 1
            to: 0
        }
    }

    move: Transition {
        Anim {
            property: "y"
        }
        Anim {
            properties: "opacity,scale"
            to: 1
        }
    }

    addDisplaced: Transition {
        Anim {
            property: "y"
            duration: Appearance.anim.durations.small
        }
        Anim {
            properties: "opacity,scale"
            to: 1
        }
    }

    displaced: Transition {
        Anim {
            property: "y"
        }
        Anim {
            properties: "opacity,scale"
            to: 1
        }
    }

    Component {
        id: appItem

        AppItem {
            visibilities: root.visibilities
            closeDrawer: root.closeDrawer
            list: root
            index: index
            onRightClicked: root.appRightClicked(modelData)
        }
    }

    Component {
        id: actionItem

        ActionItem {
            list: root
            index: index
        }
    }

    Component {
        id: calcItem

        CalcItem {
            list: root
            index: index
        }
    }

    Component {
        id: schemeItem

        SchemeItem {
            list: root
            index: index
        }
    }

    Component {
        id: variantItem

        VariantItem {
            list: root
            index: index
        }
    }
}
