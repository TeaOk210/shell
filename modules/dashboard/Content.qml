pragma ComponentBehavior: Bound

import qs.components
import qs.components.filedialog
import qs.config
import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

FocusScope {
    id: root

    required property PersistentProperties visibilities
    required property PersistentProperties state
    required property FileDialog facePicker
    property string pendingSearchText: ""
    readonly property real nonAnimWidth: view.implicitWidth + viewWrapper.anchors.margins * 2
    readonly property real nonAnimHeight: tabs.implicitHeight + tabs.anchors.topMargin + view.implicitHeight + viewWrapper.anchors.margins * 2

    focus: root.visibilities.dashboard
    activeFocusOnTab: true

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
        if (!root.visibilities.dashboard)
            return;
        if (root.handleTabArrowNavigation(event))
            return;
        const searchField = progsPane.item?.searchField;
        if (searchField && searchField.activeFocus)
            return;
        if (!event.text || event.text.length === 0)
            return;
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return;

        root.triggerProgsSearch(event.text);
        event.accepted = true;
    }

    Tabs {
        id: tabs

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Appearance.padding.normal
        anchors.margins: Appearance.padding.large

        nonAnimWidth: root.nonAnimWidth - anchors.margins * 2
        state: root.state
    }

    ClippingRectangle {
        id: viewWrapper

        anchors.top: tabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Appearance.padding.large

        radius: Appearance.rounding.normal
        color: "transparent"

        Flickable {
            id: view

            readonly property int currentIndex: root.state.currentTab
            readonly property Item currentItem: row.children[currentIndex]

            anchors.fill: parent

            flickableDirection: Flickable.HorizontalFlick
            focus: root.visibilities.dashboard && root.state.currentTab !== progsPane.index
            activeFocusOnTab: true

            implicitWidth: currentItem.implicitWidth
            implicitHeight: currentItem.implicitHeight

            contentX: currentItem.x
            contentWidth: row.implicitWidth
            contentHeight: row.implicitHeight

            onContentXChanged: {
                if (!moving)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 2)
                    root.state.currentTab = Math.min(root.state.currentTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 2)
                    root.state.currentTab = Math.max(root.state.currentTab - 1, 0);
            }

            onDragEnded: {
                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 10)
                    root.state.currentTab = Math.min(root.state.currentTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 10)
                    root.state.currentTab = Math.max(root.state.currentTab - 1, 0);
                else
                    contentX = Qt.binding(() => currentItem.x);
            }

            RowLayout {
                id: row

                Component.onCompleted: {
                    if (root.state.currentTab > tabs.count - 1)
                        root.state.currentTab = tabs.count - 1;
                    if (root.state.currentTab < 0)
                        root.state.currentTab = 0;
                    }


                Pane {
                    index: 0
                    sourceComponent: Dash {
                        visibilities: root.visibilities
                        state: root.state
                        facePicker: root.facePicker
                    }
                }

                Pane {
                    index: 1
                    sourceComponent: Media {
                        visibilities: root.visibilities
                    }
                }

                Pane {
                    id: progsPane

                    index: 2
                    onLoaded: root.flushPendingSearch()
                    sourceComponent: Progs {
                        visibilities: root.visibilities
                        tabActive: progsPane.index === view.currentIndex
                    }
                }

                Pane {
                    index: 3
                    sourceComponent: Wallpapers {}
                }

                Pane {
                    index: 4
                    sourceComponent: Performance {}
                }
            }

            Behavior on contentX {
                Anim {}
            }
        }
    }

    function triggerProgsSearch(text): void {
        if (!text || text.length === 0)
            return;
        root.forceActiveFocus();
        root.pendingSearchText = `${root.pendingSearchText}${text}`;
        if (root.state.currentTab !== progsPane.index)
            root.state.currentTab = progsPane.index;
        Qt.callLater(() => root.flushPendingSearch());
    }

    function flushPendingSearch(): void {
        if (!root.pendingSearchText || root.pendingSearchText.length === 0)
            return;
        const progs = progsPane.item;
        if (!progs || !("insertSearchText" in progs))
            return;
        progs.insertSearchText(root.pendingSearchText);
        root.pendingSearchText = "";
    }

    function ensureTypingFocus(): void {
        if (!root.visibilities.dashboard)
            return;
        root.forceActiveFocus();
        if (root.state.currentTab === progsPane.index)
            return;
        view.forceActiveFocus();
    }

    function handleTabArrowNavigation(event): bool {
        if (!event)
            return false;
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        const searchField = progsPane.item?.searchField;
        if (searchField && searchField.activeFocus)
            return false;

        if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            root.shiftTab(1);
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            root.shiftTab(-1);
            event.accepted = true;
            return true;
        }
        return false;
    }

    function shiftTab(delta): void {
        if (!delta)
            return;
        const next = Math.max(0, Math.min(tabs.count - 1, root.state.currentTab + delta));
        if (next === root.state.currentTab)
            return;
        root.state.currentTab = next;
    }

    Connections {
        target: root.visibilities

        function onDashboardChanged(): void {
            if (root.visibilities.dashboard) {
                root.forceActiveFocus();
                Qt.callLater(() => root.forceActiveFocus());
                root.ensureTypingFocus();
            }
        }
    }

    Connections {
        target: root.state

        function onCurrentTabChanged(): void {
            root.ensureTypingFocus();
        }
    }

    Behavior on implicitWidth {
        Anim {
            duration: Appearance.anim.durations.large
            easing.bezierCurve: Appearance.anim.curves.emphasized
        }
    }

    Behavior on implicitHeight {
        Anim {
            duration: Appearance.anim.durations.large
            easing.bezierCurve: Appearance.anim.curves.emphasized
        }
    }

    component Pane: Loader {
        id: pane

        required property int index

        Layout.alignment: Qt.AlignTop

        Component.onCompleted: active = Qt.binding(() => {
            // Always keep current tab loaded
            if (pane.index === view.currentIndex)
                return true;
            const vx = Math.floor(view.visibleArea.xPosition * view.contentWidth);
            const vex = Math.floor(vx + view.visibleArea.widthRatio * view.contentWidth);
            return (vx >= x && vx <= x + implicitWidth) || (vex >= x && vex <= x + implicitWidth);
        })
    }
}
