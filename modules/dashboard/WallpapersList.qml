pragma Singleton

import qs.utils
import Caelestia.Models
import Quickshell.Io
import QtQuick

Item {
    id: root

    visible: false

    readonly property string videoRoot: Paths.videos
    readonly property string videoAltRoot: `${Paths.home}/video`
    readonly property string steamRoot: `${Paths.home}/.steam/steam/steamapps/workshop/content/431960`
    readonly property string steamAltRoot: `${Paths.home}/.local/share/Steam/steamapps/workshop/content/431960`
    readonly property string thumbsDir: `${Paths.cache}/wallpaper-thumbs`
    readonly property string debugPath: `${Paths.state}/wallpapers-list-debug.txt`
    property alias model: entriesModel
    readonly property int count: entriesModel.count
    property var entries: []
    property var debugLines: []
    property var thumbQueue: []
    property var thumbQueued: new Set()
    property var thumbDone: new Set()
    property int thumbVersion: 0
    property bool thumbRunning: false
    property bool ffmpegChecked: false
    property bool ffmpegAvailable: false
    property var currentThumb: ({})

    function validate(): list<string> {
        const issues = [];
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            if (!entry || typeof entry !== "object") {
                issues.push(`entry ${i + 1}: not an object`);
                continue;
            }
            if (!entry.video || typeof entry.video !== "string")
                issues.push(`entry ${i + 1}: missing video`);
            if (entry.preview && typeof entry.preview !== "string")
                issues.push(`entry ${i + 1}: preview is not a string`);
        }
        return issues;
    }

    function normalizeRoot(path: string): string {
        return (path || "").replace(/\/+$/, "");
    }

    function dirFromPath(path: string): string {
        const idx = path.lastIndexOf("/");
        if (idx === -1)
            return "";
        return path.slice(0, idx);
    }

    function previewScore(path: string): int {
        const lower = path.toLowerCase();
        if (lower.endsWith(".png"))
            return 5;
        if (lower.endsWith(".jpg") || lower.endsWith(".jpeg"))
            return 4;
        if (lower.endsWith(".webp"))
            return 3;
        if (lower.endsWith(".gif"))
            return 0;
        return 1;
    }

    function scheduleRebuild(): void {
        rebuildTimer.restart();
    }

    function hashString(str: string): string {
        let h1 = 0xdeadbeef, h2 = 0x41c6ce57, ch;
        for (let i = 0; i < str.length; i++) {
            ch = str.charCodeAt(i);
            h1 = Math.imul(h1 ^ ch, 2654435761);
            h2 = Math.imul(h2 ^ ch, 1597334677);
        }
        h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507);
        h1 ^= Math.imul(h2 ^ (h2 >>> 13), 3266489909);
        h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507);
        h2 ^= Math.imul(h1 ^ (h1 >>> 13), 3266489909);
        return (h2 >>> 0).toString(16).padStart(8, "0") + (h1 >>> 0).toString(16).padStart(8, "0");
    }

    function thumbnailPath(videoPath: string): string {
        const hash = hashString(videoPath);
        return `${thumbsDir}/${hash}.jpg`;
    }

    function shellQuote(value: string): string {
        return "'" + value.replace(/'/g, "'\"'\"'") + "'";
    }

    function refreshThumbIndex(): void {
        const list = thumbsModel.entries;
        const next = new Set(thumbDone);
        for (let i = 0; i < list.length; i++) {
            const entry = list[i];
            if (entry?.path)
                next.add(entry.path);
        }
        thumbDone = next;
        for (const dest of thumbQueued) {
            if (thumbDone.has(dest))
                thumbQueued.delete(dest);
        }
        thumbVersion += 1;
    }

    function startThumbWorker(): void {
        if (thumbRunning || thumbQueue.length === 0 || !ffmpegAvailable)
            return;
        currentThumb = thumbQueue.shift();
        thumbRunning = true;
        const dest = currentThumb.dest;
        appendDebug(`thumb start: ${currentThumb.video}`);
        const cmd = [
            "mkdir -p", shellQuote(thumbsDir), "&&",
            "ffmpeg -y -hide_banner -loglevel error -ss 1 -i",
            shellQuote(currentThumb.video),
            "-frames:v 1 -vf scale=512:-1",
            shellQuote(dest)
        ].join(" ");
        thumbProc.command = ["sh", "-c", cmd];
        thumbProc.running = true;
    }

    function queueThumbnail(videoPath: string): void {
        if (ffmpegChecked && !ffmpegAvailable)
            return;
        const dest = thumbnailPath(videoPath);
        if (thumbDone.has(dest) || thumbQueued.has(dest))
            return;
        thumbQueued.add(dest);
        thumbQueue.push({
            video: videoPath,
            dest
        });
        appendDebug(`thumb queued: ${videoPath}`);
        startThumbWorker();
    }

    function thumbnailFor(videoPath: string): string {
        if (!videoPath)
            return "";
        const _ = thumbVersion;
        const dest = thumbnailPath(videoPath);
        if (!thumbDone.has(dest))
            queueThumbnail(videoPath);
        return thumbDone.has(dest) ? dest : "";
    }

    function rebuild(): void {
        const previewMap = {};
        const out = [];
        const seen = new Set();
        const useVideoAlt = videoMp4.entries.length === 0;
        const useSteamAlt = steamMp4.entries.length === 0;

        const addPreviews = model => {
            const list = model.entries;
            for (let i = 0; i < list.length; i++) {
                const entry = list[i];
                const dir = dirFromPath(entry.path);
                if (!dir)
                    continue;
                const score = previewScore(entry.path);
                if (score <= 0)
                    continue;
                if (!previewMap[dir] || score > previewMap[dir].score)
                    previewMap[dir] = { path: entry.path, score };
            }
        };

        function findPreview(path, rootBase) {
            let dir = dirFromPath(path);
            const root = normalizeRoot(rootBase);
            while (dir) {
                const hit = previewMap[dir];
                if (hit)
                    return hit.path;
                if (root && dir === root)
                    break;
                dir = dirFromPath(dir);
            }
            return "";
        }

        const addVideos = (model, rootBase, requirePreview) => {
            const list = model.entries;
            for (let i = 0; i < list.length; i++) {
                const entry = list[i];
                const preview = findPreview(entry.path, rootBase);
                if (requirePreview && !preview)
                    continue;
                if (seen.has(entry.path))
                    continue;
                seen.add(entry.path);
                out.push({
                    preview,
                    video: entry.path
                });
            }
        };

        addPreviews(videoPreviews);
        if (useVideoAlt)
            addPreviews(videoAltPreviews);
        addPreviews(steamPreviews);
        if (useSteamAlt)
            addPreviews(steamAltPreviews);
        addVideos(videoMp4, root.videoRoot, false);
        if (useVideoAlt)
            addVideos(videoAltMp4, root.videoAltRoot, false);
        addVideos(steamMp4, root.steamRoot, false);
        if (useSteamAlt)
            addVideos(steamAltMp4, root.steamAltRoot, false);

        out.sort((a, b) => a.video.localeCompare(b.video));
        updateModel(out);
    }

    function updateModel(out: list<var>): void {
        entries = out;
        entriesModel.clear();
        for (let i = 0; i < out.length; i++)
            entriesModel.append(out[i]);
        writeDebug();
    }

    function writeDebug(): void {
        const lines = [];
        lines.push(`videoRoot=${videoRoot}`);
        lines.push(`videoAltRoot=${videoAltRoot}`);
        lines.push(`steamRoot=${steamRoot}`);
        lines.push(`steamAltRoot=${steamAltRoot}`);
        lines.push(`videoMp4=${videoMp4.entries.length}`);
        lines.push(`videoAltMp4=${videoAltMp4.entries.length}`);
        lines.push(`steamMp4=${steamMp4.entries.length}`);
        lines.push(`steamAltMp4=${steamAltMp4.entries.length}`);
        lines.push(`videoPreviews=${videoPreviews.entries.length}`);
        lines.push(`videoAltPreviews=${videoAltPreviews.entries.length}`);
        lines.push(`steamPreviews=${steamPreviews.entries.length}`);
        lines.push(`steamAltPreviews=${steamAltPreviews.entries.length}`);
        lines.push(`useVideoAlt=${videoMp4.entries.length === 0}`);
        lines.push(`useSteamAlt=${steamMp4.entries.length === 0}`);
        lines.push(`ffmpegAvailable=${ffmpegAvailable}`);
        lines.push(`thumbs=${thumbDone.size ?? 0}`);
        lines.push(`entries=${entries.length}`);
        lines.push("samples:");
        for (let i = 0; i < Math.min(5, entries.length); i++) {
            const entry = entries[i];
            lines.push(`${i + 1}. video=${entry.video} preview=${entry.preview || "-"}`);
        }
        debugLines = lines;
        debugView.setText(lines.join("\n"));
    }

    function appendDebug(line: string): void {
        debugLines.push(line);
        if (debugLines.length > 200)
            debugLines.shift();
        debugView.setText(debugLines.join("\n"));
    }

    Timer {
        id: rebuildTimer

        interval: 200
        repeat: false
        onTriggered: root.rebuild()
    }

    ListModel {
        id: entriesModel
    }

    Process {
        id: thumbDirProc

        running: true
        command: ["mkdir", "-p", root.thumbsDir]
        onExited: {
            thumbsModel.path = root.thumbsDir;
            root.refreshThumbIndex();
        }
    }

    FileSystemModel {
        id: thumbsModel

        path: ""
        recursive: false
        watchChanges: true
        filter: FileSystemModel.Files
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        onEntriesChanged: root.refreshThumbIndex()
    }

    Process {
        id: ffmpegCheckProc

        running: true
        command: ["sh", "-c", "command -v ffmpeg"]
        onExited: code => {
            root.ffmpegChecked = true;
            root.ffmpegAvailable = code === 0;
            root.appendDebug(`ffmpegAvailable=${root.ffmpegAvailable}`);
            root.startThumbWorker();
        }
    }

    Process {
        id: thumbProc

        stdout: StdioCollector {
            onStreamFinished: text => {
                const trimmed = (text || "").trim();
                if (trimmed.length > 0)
                    root.appendDebug(`ffmpeg: ${trimmed}`);
            }
        }
        stderr: StdioCollector {
            onStreamFinished: text => {
                const trimmed = (text || "").trim();
                if (trimmed.length > 0)
                    root.appendDebug(`ffmpeg err: ${trimmed}`);
            }
        }
        onExited: code => {
            const dest = root.currentThumb.dest;
            if (dest)
                root.thumbQueued.delete(dest);
            if (dest) {
                if (code === 0) {
                    root.thumbDone.add(dest);
                    root.thumbVersion += 1;
                    root.appendDebug(`thumb done: ${dest}`);
                } else {
                    root.appendDebug(`thumb failed (${code}): ${root.currentThumb.video}`);
                }
            }
            root.thumbRunning = false;
            root.startThumbWorker();
        }
    }

    FileSystemModel {
        id: videoMp4

        path: root.videoRoot
        recursive: true
        showHidden: true
        watchChanges: true
        filter: FileSystemModel.Files
        nameFilters: ["*.mp4"]
        onEntriesChanged: root.scheduleRebuild()
    }

    FileSystemModel {
        id: steamMp4

        path: root.steamRoot
        recursive: true
        showHidden: true
        watchChanges: true
        filter: FileSystemModel.Files
        nameFilters: ["*.mp4"]
        onEntriesChanged: root.scheduleRebuild()
    }

    FileSystemModel {
        id: videoAltMp4

        path: root.videoAltRoot
        recursive: true
        showHidden: true
        watchChanges: true
        filter: FileSystemModel.Files
        nameFilters: ["*.mp4"]
        onEntriesChanged: root.scheduleRebuild()
    }

    FileSystemModel {
        id: steamAltMp4

        path: root.steamAltRoot
        recursive: true
        showHidden: true
        watchChanges: true
        filter: FileSystemModel.Files
        nameFilters: ["*.mp4"]
        onEntriesChanged: root.scheduleRebuild()
    }

    FileSystemModel {
        id: videoPreviews

        path: root.videoRoot
        recursive: true
        showHidden: true
        watchChanges: true
        filter: FileSystemModel.Files
        nameFilters: ["preview.*"]
        onEntriesChanged: root.scheduleRebuild()
    }

    FileSystemModel {
        id: videoAltPreviews

        path: root.videoAltRoot
        recursive: true
        showHidden: true
        watchChanges: true
        filter: FileSystemModel.Files
        nameFilters: ["preview.*"]
        onEntriesChanged: root.scheduleRebuild()
    }

    FileSystemModel {
        id: steamPreviews

        path: root.steamRoot
        recursive: true
        showHidden: true
        watchChanges: true
        filter: FileSystemModel.Files
        nameFilters: ["preview.*"]
        onEntriesChanged: root.scheduleRebuild()
    }

    FileSystemModel {
        id: steamAltPreviews

        path: root.steamAltRoot
        recursive: true
        showHidden: true
        watchChanges: true
        filter: FileSystemModel.Files
        nameFilters: ["preview.*"]
        onEntriesChanged: root.scheduleRebuild()
    }

    FileView {
        id: debugView

        path: root.debugPath
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                setText("");
        }
    }

    Component.onCompleted: scheduleRebuild()
}
