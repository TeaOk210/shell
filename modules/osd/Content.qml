pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import qs.utils
import qs.modules.bar.popouts as BarPopouts
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property Brightness.Monitor monitor
    required property var visibilities

    required property real volume
    required property bool muted
    required property real sourceVolume
    required property bool sourceMuted
    required property real brightness
    required property Item popouts

    property bool volumeHovered: false
    property bool mixerHovered: false
    property bool mixerVisible: false
    property bool mixerOpensLeft: true
    property real mixerGap: -Math.round(Config.osd.sizes.sliderWidth / 2)

    implicitWidth: layout.implicitWidth + Appearance.padding.large * 2
    implicitHeight: layout.implicitHeight + Appearance.padding.large * 2

    function updateMixerVisibility(): void {
        if (!root.visibilities.osd) {
            mixerHideDelay.stop();
            mixerVisible = false;
            return;
        }
        if (volumeHovered || mixerHovered) {
            mixerHideDelay.stop();
            mixerVisible = true;
            return;
        }
        mixerHideDelay.restart();
    }

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Appearance.spacing.normal
        z: 1

        // Speaker volume
        CustomMouseArea {
            id: outputVolumeArea

            implicitWidth: Config.osd.sizes.sliderWidth
            implicitHeight: Config.osd.sizes.sliderHeight
            hoverEnabled: true

            function onWheel(event: WheelEvent) {
                if (event.angleDelta.y > 0)
                    Audio.incrementVolume();
                else if (event.angleDelta.y < 0)
                    Audio.decrementVolume();
            }

            onEntered: {
                root.volumeHovered = true;
                root.updateMixerVisibility();
            }

            onExited: {
                root.volumeHovered = false;
                root.updateMixerVisibility();
            }

            FilledSlider {
                anchors.fill: parent

                icon: Icons.getVolumeIcon(value, root.muted)
                value: root.volume
                to: Config.services.maxVolume
                onMoved: Audio.setVolume(value)
            }
        }

        // Microphone volume
        WrappedLoader {
            shouldBeActive: Config.osd.enableMicrophone && (!Config.osd.enableBrightness || !root.visibilities.session)

            sourceComponent: CustomMouseArea {
                implicitWidth: Config.osd.sizes.sliderWidth
                implicitHeight: Config.osd.sizes.sliderHeight

                function onWheel(event: WheelEvent) {
                    if (event.angleDelta.y > 0)
                        Audio.incrementSourceVolume();
                    else if (event.angleDelta.y < 0)
                        Audio.decrementSourceVolume();
                }

                FilledSlider {
                    anchors.fill: parent

                    icon: Icons.getMicVolumeIcon(value, root.sourceMuted)
                    value: root.sourceVolume
                    to: Config.services.maxVolume
                    onMoved: Audio.setSourceVolume(value)
                }
            }
        }

        // Brightness
        WrappedLoader {
            shouldBeActive: Config.osd.enableBrightness

            sourceComponent: CustomMouseArea {
                implicitWidth: Config.osd.sizes.sliderWidth
                implicitHeight: Config.osd.sizes.sliderHeight

                function onWheel(event: WheelEvent) {
                    const monitor = root.monitor;
                    if (!monitor)
                        return;
                    if (event.angleDelta.y > 0)
                        monitor.setBrightness(monitor.brightness + Config.services.brightnessIncrement);
                    else if (event.angleDelta.y < 0)
                        monitor.setBrightness(monitor.brightness - Config.services.brightnessIncrement);
                }

                FilledSlider {
                    anchors.fill: parent

                    icon: `brightness_${(Math.round(value * 6) + 1)}`
                    value: root.brightness
                    onMoved: root.monitor?.setBrightness(value)
                }
            }
        }
    }

    Item {
        id: mixerPopup

        readonly property real anchorX: root.mixerOpensLeft
            ? outputVolumeArea.x - root.mixerGap
            : outputVolumeArea.x + outputVolumeArea.width + root.mixerGap
        readonly property real targetY: outputVolumeArea.y + (outputVolumeArea.height - height) / 2
        property real targetWidth: 0

        width: 0
        height: mixerContent.implicitHeight
        clip: true
        visible: opacity > 0
        opacity: 0
        scale: 0.92
        z: 0
        transformOrigin: root.mixerOpensLeft ? Item.TopRight : Item.TopLeft

        x: root.mixerOpensLeft ? anchorX - width : anchorX
        y: targetY

        function animateTo(visible: bool): void {
            targetWidth = mixerContent.implicitWidth;
            widthAnim.from = width;
            opacityAnim.from = opacity;
            scaleAnim.from = scale;
            if (visible) {
                mixerPopup.visible = true;
                widthAnim.to = targetWidth;
                opacityAnim.to = 1;
                scaleAnim.to = 1;
            } else {
                widthAnim.to = 0;
                opacityAnim.to = 0;
                scaleAnim.to = 0.92;
            }
            widthAnim.restart();
            opacityAnim.restart();
            scaleAnim.restart();
        }

        HoverHandler {
            id: mixerHover

            onHoveredChanged: {
                root.mixerHovered = hovered;
                root.updateMixerVisibility();
            }
        }

        StyledRect {
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: Colours.palette.m3surface
        }

        BarPopouts.Audio {
            id: mixerContent

            width: implicitWidth
            height: implicitHeight
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: root.mixerOpensLeft ? parent.right : undefined
            anchors.left: root.mixerOpensLeft ? undefined : parent.left
            wrapper: root.popouts
            alignRight: root.mixerOpensLeft
        }

        Anim {
            id: widthAnim

            target: mixerPopup
            property: "width"
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial

            onStopped: {
                if (!root.mixerVisible && mixerPopup.width <= 0.5)
                    mixerPopup.visible = false;
            }
        }

        Anim {
            id: opacityAnim

            target: mixerPopup
            property: "opacity"
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
        }

        Anim {
            id: scaleAnim

            target: mixerPopup
            property: "scale"
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
        }

        Connections {
            target: root

            function onMixerVisibleChanged(): void {
                mixerPopup.animateTo(root.mixerVisible);
            }
        }

    }

    Timer {
        id: mixerHideDelay

        interval: 200
        onTriggered: root.mixerVisible = false
    }

    Connections {
        target: root.visibilities

        function onOsdChanged(): void {
            if (root.visibilities.osd)
                return;
            root.volumeHovered = false;
            root.mixerHovered = false;
            mixerHideDelay.stop();
            root.mixerVisible = false;
        }
    }

    component WrappedLoader: Loader {
        required property bool shouldBeActive

        Layout.preferredHeight: shouldBeActive ? Config.osd.sizes.sliderHeight : 0
        opacity: shouldBeActive ? 1 : 0
        active: opacity > 0
        visible: active

        Behavior on Layout.preferredHeight {
            Anim {
                easing.bezierCurve: Appearance.anim.curves.emphasized
            }
        }

        Behavior on opacity {
            Anim {}
        }
    }
}
