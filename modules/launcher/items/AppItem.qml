import "../services"
import qs.components
import qs.services
import qs.config
import qs.utils
import Quickshell
import Quickshell.Widgets
import QtQuick

Item {
    id: root

    required property DesktopEntry modelData
    required property PersistentProperties visibilities
    required property int index
    property string closeDrawer: "launcher"
    property var list
    signal rightClicked(var entry)
    property bool hoverGuardActive: false

    implicitHeight: Config.launcher.sizes.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Appearance.rounding.normal
        showHoverBackground: ListView.isCurrentItem
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        function onClicked(event): void {
            if (event.button === Qt.RightButton) {
                root.rightClicked(root.modelData);
                return;
            }
            if (root.visibilities && root.closeDrawer) {
                if (typeof root.visibilities[root.closeDrawer] !== "undefined")
                    root.visibilities[root.closeDrawer] = false;
                else if (root.visibilities.setProperty)
                    root.visibilities.setProperty(root.closeDrawer, false);
                if (root.closeDrawer === "dashboard" && Config.dashboard.showOnHover)
                    Qt.callLater(() => root.startHoverGuard());
            }
            Apps.launch(root.modelData);
        }
    }

    Timer {
        id: hoverGuardTimer

        interval: 250
        repeat: false
        onTriggered: root.stopHoverGuard()
    }

    function startHoverGuard(): void {
        if (!root.visibilities || typeof root.visibilities.dashboardLock === "undefined")
            return;
        root.hoverGuardActive = true;
        root.visibilities.dashboardLock = true;
        hoverGuardTimer.restart();
    }

    function stopHoverGuard(): void {
        if (!root.hoverGuardActive)
            return;
        root.hoverGuardActive = false;
        hoverGuardTimer.stop();
        if (root.visibilities && typeof root.visibilities.dashboardLock !== "undefined")
            root.visibilities.dashboardLock = false;
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Appearance.padding.larger
        anchors.rightMargin: Appearance.padding.larger
        anchors.margins: Appearance.padding.smaller

        IconImage {
            id: icon

            source: Quickshell.iconPath(root.modelData?.icon, "image-missing")
            implicitSize: parent.height * 0.8

            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Appearance.spacing.normal
            anchors.verticalCenter: icon.verticalCenter

            implicitWidth: parent.width - icon.width - favouriteIcon.width
            implicitHeight: name.implicitHeight + comment.implicitHeight

            StyledText {
                id: name

                text: root.modelData?.name ?? ""
                font.pointSize: Appearance.font.size.normal
            }

            StyledText {
                id: comment

                text: (root.modelData?.comment || root.modelData?.genericName || root.modelData?.name) ?? ""
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3outline

                elide: Text.ElideRight
                width: root.width - icon.width - favouriteIcon.width - Appearance.rounding.normal * 2

                anchors.top: name.bottom
            }
        }

        Loader {
            id: favouriteIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            active: modelData && Strings.testRegexList(Config.launcher.favouriteApps, modelData.id)

            sourceComponent: MaterialIcon {
                text: "favorite"
                fill: 1
                color: Colours.palette.m3primary
            }
        }
    }
}
