import qs.components
import qs.components.images
import qs.services
import qs.utils
import qs.config
import QtQuick

Item {
    id: root

    required property string video
    required property string preview
    property real tileWidth: 220
    property real tileHeight: 124

    readonly property string previewPath: MpvpaperService.normalizePath(preview)
    readonly property string videoPath: MpvpaperService.normalizePath(video)
    readonly property bool previewIsGif: previewPath.toLowerCase().endsWith(".gif")
    property bool previewFailed: false
    readonly property bool needsFallback: !previewPath || previewFailed || previewIsGif
    readonly property string fallbackPreview: needsFallback ? (videoPath ? WallpapersList.thumbnailFor(videoPath) : "") : ""
    readonly property string effectivePreview: needsFallback ? fallbackPreview : previewPath
    required property int index
    readonly property bool useStaticPreview: root.effectivePreview !== ""
    readonly property bool selected: videoPath !== "" && videoPath === MpvpaperService.currentPath

    function logState(reason: string): void {
        console.log(`Wallpapers: ${reason} idx=${index} video=${videoPath} preview=${previewPath} effective=${effectivePreview}`);
    }

    implicitWidth: tileWidth
    implicitHeight: tileHeight
    width: tileWidth
    height: tileHeight

    Component.onCompleted: {
        logState("init");
        if (index < 5)
            WallpapersList.appendDebug(`item ${index} preview=${previewPath} video=${videoPath} effective=${effectivePreview}`);
    }

    onVideoChanged: {
        if (!videoPath)
            console.warn(`Wallpapers: empty video idx=${index} raw=${video}`);
        if (index < 5)
            WallpapersList.appendDebug(`item ${index} video changed: ${videoPath}`);
    }

    onPreviewChanged: {
        previewFailed = false;
        if (!previewPath && videoPath)
            console.warn(`Wallpapers: empty preview idx=${index} video=${videoPath}`);
        if (index < 5)
            WallpapersList.appendDebug(`item ${index} preview changed: ${previewPath}`);
    }

    StyledClippingRect {
        id: tile

        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Colours.tPalette.m3surfaceContainer
        antialiasing: true
        layer.enabled: true
        layer.smooth: true

        CachingImage {
            id: staticPreview

            anchors.fill: parent
            path: root.needsFallback ? "" : root.previewPath
            visible: root.useStaticPreview
            cache: true
            smooth: true

            onStatusChanged: {
                if (root.index < 5)
                    WallpapersList.appendDebug(`item ${root.index} static status=${status}`);
                if (status === Image.Error) {
                    root.previewFailed = true;
                    console.warn(`Wallpapers: preview error idx=${root.index} path=${root.previewPath}`);
                }
            }
        }

        Image {
            id: staticFallback

            anchors.fill: parent
            source: root.useStaticPreview && staticPreview.status !== Image.Ready && root.effectivePreview
                ? root.effectivePreview
                : ""
            visible: opacity > 0
            asynchronous: true
            cache: true
            smooth: true
            fillMode: Image.PreserveAspectCrop

            opacity: source !== "" ? 1 : 0

            Behavior on opacity {
                Anim {}
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: root.effectivePreview === ""
            text: "wallpaper"
            color: Colours.tPalette.m3outline
            font.pointSize: Appearance.font.size.extraLarge * 2
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: tile.radius
        color: Colours.palette.m3onSurface
        preventStealing: true
        propagateComposedEvents: true
        acceptedButtons: Qt.LeftButton

        function onClicked(event): void {
            if (root.videoPath) {
                console.log(`Wallpapers: click idx=${root.index} path=${root.videoPath}`);
                MpvpaperService.logDebug(`click: ${root.videoPath}`);
                MpvpaperService.setWallpaper(root.videoPath);
            } else {
                console.warn(`Wallpapers: click ignored idx=${root.index} video=${root.video}`);
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: tile.radius + border.width
        border.width: root.selected ? 2 : 0
        border.color: Colours.palette.m3primary
        antialiasing: true
        smooth: true

        Behavior on border.width {
            Anim {}
        }
    }
}
