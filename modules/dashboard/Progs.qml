pragma ComponentBehavior: Bound

import "../launcher"
import "../launcher/services" as LauncherServices

import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
Item {
    id: root

    property PersistentProperties visibilities

    property int currentSection: 1
    property var allEntries: []
    property var pinnedEntries: []
    property var visibleAllEntries: []
    property var visiblePinnedEntries: []
    property bool tabActive: true
    property bool userSelectedSection: false
    readonly property bool searchVisible: searchField.text.length > 0
    readonly property var currentList: root.currentSection === 0 ? pinnedList : allList

    readonly property int pad: Appearance.padding.large

    PersistentProperties {
        id: pinnedState

        property var pinnedIds: []

        reloadableId: "dashboardPinned"
        onPinnedIdsChanged: root.updatePinnedEntries()
    }

    Timer {
        id: searchFocusRetry

        interval: 16
        repeat: true
        running: false
        property int remainingAttempts: 0

        function schedule(): void {
            remainingAttempts = 10;
            if (!running)
                start();
        }

        onTriggered: {
            if (!root.tabActive || !(root.visibilities?.dashboard ?? false) || !root.visible) {
                stop();
                remainingAttempts = 0;
                return;
            }

            searchField.forceActiveFocus();
            if (searchField.activeFocus) {
                stop();
                remainingAttempts = 0;
            } else if (--remainingAttempts <= 0) {
                stop();
            }
        }
    }


    function normalizeEntry(entry): var {
        if (entry && entry.entry)
            return entry.entry;
        return entry;
    }

    function isValidEntry(entry): bool {
        if (!entry || !entry.id || !entry.name)
            return false;

        var cmd = entry.command;
        if (cmd && cmd.length > 0)
            return true;

        var execString = entry.execString;
        if (execString && execString.length > 0)
            return true;

        return false;
    }

    function sanitizePinnedIds(ids): var {
        if (!ids || !(ids instanceof Array))
            return [];

        var out = [];
        for (var i = 0; i < ids.length; i++) {
            var entryId = ids[i];
            if (typeof entryId === "string" && entryId.length > 0)
                out.push(entryId);
        }
        return out;
    }

    function idsEqual(a, b): bool {
        if (a === b)
            return true;
        if (!a || !b || a.length !== b.length)
            return false;
        for (var i = 0; i < a.length; i++) {
            if (a[i] !== b[i])
                return false;
        }
        return true;
    }

    function updateAllEntries(): void {
        var entries = LauncherServices.Apps.search("") || [];
        var out = [];
        for (var i = 0; i < entries.length; i++) {
            var entry = normalizeEntry(entries[i]);
            if (isValidEntry(entry))
                out.push(entry);
        }
        root.allEntries = out;
        updatePinnedEntries();
    }

    function updatePinnedEntries(): void {
        var ids = sanitizePinnedIds(pinnedState.pinnedIds);
        if (!idsEqual(ids, pinnedState.pinnedIds)) {
            pinnedState.pinnedIds = ids;
            return;
        }

        var allEntries = root.allEntries || [];
        var byId = {};
        for (var i = 0; i < allEntries.length; i++) {
            var entry = normalizeEntry(allEntries[i]);
            if (entry && entry.id)
                byId[entry.id] = entry;
        }

        var pinned = [];
        for (var j = 0; j < ids.length; j++) {
            var entryId = ids[j];
            if (byId[entryId])
                pinned.push(byId[entryId]);
        }
        root.pinnedEntries = pinned;
        root.updateVisibleEntries();
        root.applyDefaultSection();
    }

    function togglePinned(entry): void {
        if (!entry || !entry.id)
            return;
        if (typeof entry.id !== "string" || entry.id.length === 0)
            return;

        var ids = pinnedState.pinnedIds;
        if (!ids || !(ids instanceof Array))
            ids = [];

        var idx = ids.indexOf(entry.id);
        if (idx === -1) {
            ids = ids.concat([entry.id]);
        } else {
            var next = ids.slice();
            next.splice(idx, 1);
            ids = next;
        }
        pinnedState.pinnedIds = ids;
        updatePinnedEntries();
    }

    function updateVisibleEntries(): void {
        var text = searchField.text || "";
        if (text.length === 0) {
            root.visibleAllEntries = root.allEntries;
            root.visiblePinnedEntries = root.pinnedEntries;
            return;
        }

        var results = LauncherServices.Apps.search(text) || [];
        var out = [];
        var ids = {};
        for (var i = 0; i < results.length; i++) {
            var entry = normalizeEntry(results[i]);
            if (!isValidEntry(entry))
                continue;
            out.push(entry);
            if (entry.id)
                ids[entry.id] = true;
        }
        root.visibleAllEntries = out;

        var pinned = root.pinnedEntries || [];
        var pinnedOut = [];
        for (var j = 0; j < pinned.length; j++) {
            var pinnedEntry = normalizeEntry(pinned[j]);
            if (pinnedEntry && pinnedEntry.id && ids[pinnedEntry.id])
                pinnedOut.push(pinnedEntry);
        }
        root.visiblePinnedEntries = pinnedOut;
    }

    function lockDashboard(): void {
        if (root.visibilities)
            root.visibilities.dashboardLock = true;
    }

    function markKeyboardNavigation(): void {
        var list = root.currentList;
        if (!list)
            return;
        if ("mouseSelectionEnabled" in list)
            list.mouseSelectionEnabled = false;
        if ("keyboardNavigationActive" in list)
            list.keyboardNavigationActive = true;
        if ("lastMousePos" in list)
            list.lastMousePos = Qt.point(-1, -1);
        if (list.currentIndex >= 0)
            list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }

    function applyDefaultSection(): void {
        if (!root.tabActive || root.userSelectedSection)
            return;
        root.currentSection = root.pinnedEntries.length > 0 ? 0 : 1;
    }

    function syncDashboardLock(): void {
        if (!root.visibilities)
            return;
        var shouldLock = root.visibilities.dashboard && root.tabActive;
        root.visibilities.dashboardLock = shouldLock;
        if (shouldLock) {
            searchField.forceActiveFocus();
            root.ensureSearchFocus();
        }
    }

    function handleSearchKey(event): void {
        if (!event || searchField.activeFocus)
            return;
        if (!event.text || event.text.length === 0)
            return;
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return;

        searchField.text = searchField.text + event.text;
        searchField.cursorPosition = searchField.text.length;
        searchField.forceActiveFocus();
        root.lockDashboard();
        event.accepted = true;
    }

    function insertSearchText(text): void {
        if (!text || text.length === 0)
            return;
        searchField.text = `${searchField.text}${text}`;
        searchField.cursorPosition = searchField.text.length;
        searchField.forceActiveFocus();
        root.lockDashboard();
    }

    function handleNavigationKey(event): bool {
        if (!event)
            return false;

        if (event.key === Qt.Key_Up) {
            root.currentList?.decrementCurrentIndex();
            root.lockDashboard();
            root.markKeyboardNavigation();
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_Down) {
            root.currentList?.incrementCurrentIndex();
            root.lockDashboard();
            root.markKeyboardNavigation();
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launchCurrent();
            root.lockDashboard();
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_Escape) {
            if (searchField.text.length > 0) {
                searchField.text = "";
                searchField.focus = false;
            } else if (root.visibilities) {
                root.visibilities.dashboard = false;
            }
            event.accepted = true;
            return true;
        }

        return false;
    }

    function currentEntry(): var {
        if (!root.currentList || root.currentList.currentIndex < 0)
            return null;
        return root.currentList.currentItem?.modelData ?? null;
    }

    function launchCurrent(): void {
        var entry = root.currentEntry();
        if (!entry)
            return;
        LauncherServices.Apps.launch(entry);
        if (root.visibilities)
            root.visibilities.dashboard = false;
    }

    focus: tabActive && (root.visibilities ? root.visibilities.dashboard : true)
    activeFocusOnTab: true

    onTabActiveChanged: {
        if (tabActive) {
            forceActiveFocus();
            root.ensureSearchFocus();
            root.userSelectedSection = false;
            root.applyDefaultSection();
        } else if (searchField.activeFocus) {
            searchField.focus = false;
        }
        root.syncDashboardLock();
    }

    Component.onCompleted: {
        if (tabActive)
            forceActiveFocus();
        root.syncDashboardLock();
        if (tabActive)
            root.ensureSearchFocus();
        updateAllEntries();
    }

    Keys.onPressed: function(event) {
        if (root.handleNavigationKey(event))
            return;
        root.handleSearchKey(event);
    }


    Connections {
        target: DesktopEntries.applications
        function onValuesChanged(): void {
            root.updateAllEntries();
        }
    }

    Connections {
        target: Config.launcher
        function onHiddenAppsChanged(): void {
            root.updateAllEntries();
        }
    }

    Connections {
        target: root.visibilities
        function onDashboardChanged(): void {
            if (root.visibilities.dashboard) {
                if (tabActive) {
                    root.forceActiveFocus();
                    root.ensureSearchFocus();
                }
            } else {
                searchField.text = "";
                searchField.focus = false;
            }
            root.syncDashboardLock();
        }
    }

    implicitWidth: 840
    implicitHeight: 420

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Appearance.spacing.large

        ColumnLayout {
            id: header

            Layout.fillWidth: true
            spacing: root.searchVisible ? Appearance.spacing.small : 0

            Behavior on spacing {
                Anim {
                    duration: Appearance.anim.durations.small
                    easing.bezierCurve: Appearance.anim.curves.standardDecel
                }
            }

            Item {
                id: searchArea

                Layout.fillWidth: true
                implicitHeight: root.searchVisible ? searchWrapper.implicitHeight : 0
                opacity: root.searchVisible ? 1 : 0
                clip: true
                visible: true

                Behavior on implicitHeight {
                    Anim {
                        duration: Appearance.anim.durations.small
                        easing.bezierCurve: Appearance.anim.curves.standardDecel
                    }
                }

                Behavior on opacity {
                    Anim {
                        duration: Appearance.anim.durations.small
                        easing.bezierCurve: Appearance.anim.curves.standardDecel
                    }
                }

                StyledRect {
                    id: searchWrapper

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top

                    color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
                    radius: Appearance.rounding.full

                    implicitHeight: Math.max(searchIcon.implicitHeight, searchField.implicitHeight, clearIcon.implicitHeight)

                    MaterialIcon {
                        id: searchIcon

                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Appearance.padding.large

                        text: "search"
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledTextField {
                        id: searchField

                        anchors.left: searchIcon.right
                        anchors.right: clearIcon.left
                        anchors.leftMargin: Appearance.spacing.small
                        anchors.rightMargin: Appearance.spacing.small

                        topPadding: Appearance.padding.larger
                        bottomPadding: Appearance.padding.larger

                        placeholderText: qsTr("Search apps")

                        onTextChanged: root.updateVisibleEntries()

                        Keys.onPressed: function(event) {
                            if (root.handleNavigationKey(event))
                                return;
                            event.accepted = false;
                        }
                    }

                    MaterialIcon {
                        id: clearIcon

                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: Appearance.padding.large

                        width: searchField.text ? implicitWidth : implicitWidth / 2
                        opacity: {
                            if (!searchField.text)
                                return 0;
                            if (clearMouse.pressed)
                                return 0.7;
                            if (clearMouse.containsMouse)
                                return 0.8;
                            return 1;
                        }

                        text: "close"
                        color: Colours.palette.m3onSurfaceVariant

                        MouseArea {
                            id: clearMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: searchField.text ? Qt.PointingHandCursor : undefined

                            onClicked: searchField.text = ""
                        }

                        Behavior on width {
                            Anim {
                                duration: Appearance.anim.durations.small
                            }
                        }

                        Behavior on opacity {
                            Anim {
                                duration: Appearance.anim.durations.small
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                SectionTab {
                    index: 0
                    text: qsTr("Pinned (%1)").arg(root.visiblePinnedEntries.length)
                }

                SectionTab {
                    index: 1
                    text: qsTr("All (%1)").arg(root.visibleAllEntries.length)
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }

        Item {
            id: listArea

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            AppList {
                id: pinnedList

                anchors.fill: parent
                clip: true

                readonly property bool active: root.currentSection === 0

                allowActions: false
                closeDrawer: "dashboard"
                overrideValues: root.visiblePinnedEntries
                visibilities: root.visibilities

                enabled: active
                interactive: active
                focus: false
                opacity: active ? 1 : 0
                scale: active ? 1 : 0.98
                visible: opacity > 0.01

                onAppRightClicked: root.togglePinned(entry)
                Keys.onPressed: function(event) {
                    if (root.handleNavigationKey(event))
                        return;
                    root.handleSearchKey(event);
                }

                Behavior on opacity {
                    Anim {
                        duration: Appearance.anim.durations.small
                        easing.bezierCurve: Appearance.anim.curves.standardDecel
                    }
                }

                Behavior on scale {
                    Anim {
                        duration: Appearance.anim.durations.small
                        easing.bezierCurve: Appearance.anim.curves.standardDecel
                    }
                }
            }

            AppList {
                id: allList

                anchors.fill: parent
                clip: true

                readonly property bool active: root.currentSection === 1

                allowActions: false
                closeDrawer: "dashboard"
                overrideValues: root.visibleAllEntries
                visibilities: root.visibilities

                enabled: active
                interactive: active
                focus: false
                opacity: active ? 1 : 0
                scale: active ? 1 : 0.98
                visible: opacity > 0.01

                onAppRightClicked: root.togglePinned(entry)
                Keys.onPressed: function(event) {
                    if (root.handleNavigationKey(event))
                        return;
                    root.handleSearchKey(event);
                }

                Behavior on opacity {
                    Anim {
                        duration: Appearance.anim.durations.small
                        easing.bezierCurve: Appearance.anim.curves.standardDecel
                    }
                }

                Behavior on scale {
                    Anim {
                        duration: Appearance.anim.durations.small
                        easing.bezierCurve: Appearance.anim.curves.standardDecel
                    }
                }
            }
        }
    }

    function ensureSearchFocus(): void {
        if (!root.tabActive)
            return;
        if (!(root.visibilities?.dashboard ?? false))
            return;
        searchFocusRetry.schedule();
    }

    component SectionTab: Item {
        id: tab

        required property int index
        required property string text
        readonly property bool current: root.currentSection === index

        implicitHeight: label.implicitHeight + Appearance.padding.small * 2
        implicitWidth: label.implicitWidth + Appearance.padding.large * 2

        StyledRect {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: Colours.palette.m3primary
            opacity: tab.current ? 0.14 : 0

            Behavior on opacity {
                Anim {}
            }
        }

        StyledRect {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
            opacity: mouse.pressed ? 0.12 : mouse.containsMouse ? 0.08 : 0

            Behavior on opacity {
                Anim {}
            }
        }

        StyledText {
            id: label

            anchors.centerIn: parent
            text: tab.text
            font.pointSize: Appearance.font.size.normal
            font.weight: tab.current ? 600 : 500
            color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            elide: Text.ElideRight
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                root.userSelectedSection = true;
                root.currentSection = tab.index;
            }
        }
    }

}
