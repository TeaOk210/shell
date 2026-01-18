import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    implicitWidth: 640
    implicitHeight: 420

    readonly property int entriesCount: WallpapersList.count
    readonly property real tileSpacing: Appearance.spacing.normal

    Component.onCompleted: {
        const issues = WallpapersList.validate();
        if (issues.length > 0)
            console.warn(`WallpapersList: ${issues.join("; ")}`);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.large

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Wallpapers")
            font.pointSize: Appearance.font.size.large
            font.weight: 600
            color: Colours.palette.m3onSurface
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: grid

                anchors.fill: parent
                clip: true
                model: WallpapersList.model
                cellWidth: tileWidth + root.tileSpacing
                cellHeight: tileHeight + root.tileSpacing
                visible: root.entriesCount > 0

                readonly property int columnsCount: 3
                readonly property real tileWidth: {
                    const available = width > 0 ? width : root.implicitWidth;
                    const totalSpacing = root.tileSpacing * columnsCount;
                    const computed = Math.floor((available - totalSpacing) / columnsCount);
                    return computed > 0 ? computed : 200;
                }
                readonly property real tileHeight: Math.round(tileWidth / 16 * 9)

                delegate: Item {
                    id: entryWrapper

                    required property int index
                    required property string video
                    required property string preview

                    width: grid.cellWidth
                    height: grid.cellHeight

                    WallpaperItem {
                        x: root.tileSpacing / 2
                        y: root.tileSpacing / 2
                        tileWidth: grid.tileWidth
                        tileHeight: grid.tileHeight
                        index: entryWrapper.index
                        video: entryWrapper.video
                        preview: entryWrapper.preview || ""
                    }
                }

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: grid
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.entriesCount === 0
                text: qsTr("No wallpapers found in Videos or Steam workshop")
                font.pointSize: Appearance.font.size.normal
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Appearance.padding.small
                visible: !MpvpaperService.available
                text: qsTr("mpvpaper not found in PATH")
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3error
            }
        }
    }
}
