pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../controlcenter/network"

Item {
    id: root

    required property var wrapper
    property bool alignRight: false

    implicitWidth: layout.implicitWidth + Appearance.padding.normal * 2
    implicitHeight: layout.implicitHeight + Appearance.padding.normal * 2

    function streamLabel(node: PwNode): string {
        const props = node?.properties ?? {};
        return props["application.name"]
            || props["application.id"]
            || props["application.process.binary"]
            || props["media.name"]
            || node?.description
            || node?.nickname
            || node?.name
            || qsTr("Unknown App");
    }

    function normalizeKey(value: var): string {
        if (value === null || value === undefined)
            return "";
        return value.toString().trim().toLowerCase();
    }

    function streamGroupInfo(node: PwNode): var {
        const props = node?.properties ?? {};
        const pid = Number(props["application.process.id"] ?? props["pipewire.access.pid"] ?? 0);
        const appId = props["application.id"] ?? "";
        const appName = props["application.name"] ?? "";
        const binary = props["application.process.binary"] ?? "";
        const mediaName = props["media.name"] ?? "";
        const nodeName = props["node.name"] ?? node?.name ?? "";
        const label = appName
            || appId
            || binary
            || mediaName
            || node?.description
            || node?.nickname
            || nodeName
            || qsTr("Unknown App");

        let key = "";
        if (Number.isFinite(pid) && pid > 0)
            key = `pid:${pid}`;
        else if (appId)
            key = `app:${normalizeKey(appId)}`;
        else if (appName)
            key = `name:${normalizeKey(appName)}`;
        else if (binary)
            key = `bin:${normalizeKey(binary)}`;
        else if (mediaName)
            key = `media:${normalizeKey(mediaName)}`;
        else
            key = `node:${normalizeKey(nodeName || label)}`;

        return {
            key: key,
            label: label
        };
    }

    function entryHasAudio(entry: var): bool {
        return (entry?.streams?.length ?? 0) > 0;
    }

    function entryVolume(entry: var): real {
        const streams = entry?.streams ?? [];
        if (streams.length === 0)
            return 0;
        let total = 0;
        for (const stream of streams)
            total += stream.audio?.volume ?? 0;
        return total / streams.length;
    }

    function setEntryVolume(entry: var, newVolume: real): void {
        const streams = entry?.streams ?? [];
        for (const stream of streams)
            Audio.setNodeVolume(stream, newVolume);
    }

    function adjustEntryVolume(entry: var, amount: real): void {
        const streams = entry?.streams ?? [];
        for (const stream of streams)
            Audio.adjustNodeVolume(stream, amount);
    }

    readonly property var appEntries: {
        const entries = [];
        const streams = Audio.streams ?? [];
        const entriesByKey = new Map();

        for (const stream of streams) {
            const info = streamGroupInfo(stream);
            const key = info.key || `stream:${stream?.id ?? entries.length}`;
            let entry = entriesByKey.get(key);
            if (!entry) {
                entry = {
                    id: key,
                    name: info.label || streamLabel(stream),
                    streams: []
                };
                entriesByKey.set(key, entry);
                entries.push(entry);
            }
            entry.streams.push(stream);
        }

        return entries;
    }

    readonly property var activeEntries: appEntries.filter(entry => root.entryHasAudio(entry))

    ButtonGroup {
        id: sinks
    }

    ButtonGroup {
        id: sources
    }

    ColumnLayout {
        id: layout

        anchors.left: root.alignRight ? undefined : parent.left
        anchors.right: root.alignRight ? parent.right : undefined
        anchors.verticalCenter: parent.verticalCenter
        spacing: Appearance.spacing.normal

        StyledText {
            text: qsTr("Output device")
            font.weight: 500
        }

        Repeater {
            model: Audio.sinks

            StyledRadioButton {
                id: control

                required property PwNode modelData

                ButtonGroup.group: sinks
                checked: Audio.sink?.id === modelData.id
                onClicked: Audio.setAudioSink(modelData)
                text: modelData.description
            }
        }

        StyledText {
            Layout.topMargin: Appearance.spacing.smaller
            text: qsTr("Input device")
            font.weight: 500
        }

        Repeater {
            model: Audio.sources

            StyledRadioButton {
                required property PwNode modelData

                ButtonGroup.group: sources
                checked: Audio.source?.id === modelData.id
                onClicked: Audio.setAudioSource(modelData)
                text: modelData.description
            }
        }

        StyledText {
            Layout.topMargin: Appearance.spacing.smaller
            Layout.bottomMargin: -Appearance.spacing.small / 2
            text: qsTr("Volume (%1)").arg(Audio.muted ? qsTr("Muted") : `${Math.round(Audio.volume * 100)}%`)
            font.weight: 500
        }

        CustomMouseArea {
            Layout.fillWidth: true
            implicitHeight: Appearance.padding.normal * 3

            onWheel: event => {
                if (event.angleDelta.y > 0)
                    Audio.incrementVolume();
                else if (event.angleDelta.y < 0)
                    Audio.decrementVolume();
            }

            StyledSlider {
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: parent.implicitHeight

                value: Audio.volume
                onMoved: Audio.setVolume(value)

                Behavior on value {
                    Anim {}
                }
            }
        }

        StyledText {
            Layout.topMargin: Appearance.spacing.smaller
            text: qsTr("Applications")
            font.weight: 500
            visible: root.activeEntries.length > 0
        }

        Repeater {
            model: root.activeEntries

            ColumnLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: Appearance.spacing.small / 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: modelData.name
                    }

                    StyledText {
                        text: root.entryHasAudio(modelData)
                            ? `${Math.round(root.entryVolume(modelData) * 100)}%`
                            : qsTr("No audio")
                        color: root.entryHasAudio(modelData)
                            ? Colours.palette.m3onSurfaceVariant
                            : Colours.palette.m3outline
                    }
                }

                CustomMouseArea {
                    Layout.fillWidth: true
                    implicitHeight: Appearance.padding.normal * 2.5

                    onWheel: event => {
                        if (!root.entryHasAudio(modelData))
                            return;
                        if (event.angleDelta.y > 0)
                            root.adjustEntryVolume(modelData, Config.services.audioIncrement);
                        else if (event.angleDelta.y < 0)
                            root.adjustEntryVolume(modelData, -Config.services.audioIncrement);
                    }

                    StyledSlider {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        implicitHeight: parent.implicitHeight

                        value: root.entryVolume(modelData)
                        enabled: root.entryHasAudio(modelData)
                        opacity: enabled ? 1 : 0.45
                        onMoved: root.setEntryVolume(modelData, value)

                        Behavior on value {
                            Anim {}
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.topMargin: Appearance.spacing.smaller
            text: qsTr("No active applications")
            color: Colours.palette.m3onSurfaceVariant
            visible: root.activeEntries.length === 0
        }

        IconTextButton {
            Layout.fillWidth: true
            Layout.topMargin: Appearance.spacing.normal
            inactiveColour: Colours.palette.m3primaryContainer
            inactiveOnColour: Colours.palette.m3onPrimaryContainer
            verticalPadding: Appearance.padding.small
            text: qsTr("Open settings")
            icon: "settings"

            onClicked: root.wrapper.detach("audio")
        }
    }
}
