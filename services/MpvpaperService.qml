pragma Singleton

import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string statePath: `${Paths.state}/mpvpaper-wallpaper.txt`
    readonly property string debugPath: `${Paths.state}/mpvpaper-debug.log`
    property string currentPath: ""
    property string mpvOptions: "loop hwdec=auto-safe no-audio"
    property bool available: false
    property bool storageReady: false
    property bool mpvpaperChecked: false
    property bool running: false
    property string lastCommandKey: ""
    property var pendingCommand: []
    property var debugLines: []

    function normalizePath(path: var): string {
        if (!path)
            return "";
        if (typeof path !== "string")
            path = path.toString();
        const trimmed = path.trim();
        if (!trimmed)
            return "";
        if (trimmed.startsWith("file://")) {
            let stripped = trimmed.replace(/^file:\/*/, "/");
            try {
                stripped = decodeURIComponent(stripped);
            } catch (e) {
                // Keep raw path if decoding fails.
            }
            return stripped;
        }
        if (trimmed.startsWith("~"))
            return trimmed.replace(/^~(?=\/|$)/, Paths.home);
        if (trimmed.startsWith("/"))
            return trimmed;
        return Paths.absolutePath(trimmed);
    }

    function logDebug(message: string): void {
        const stamp = new Date().toISOString();
        debugLines.push(`${stamp} ${message}`);
        if (debugLines.length > 200)
            debugLines.shift();
        debugView.setText(debugLines.join("\n"));
    }

    function setWallpaper(path: var): void {
        const normalized = normalizePath(path);
        if (!normalized) {
            logDebug(`setWallpaper: skipped empty path (${path})`);
            return;
        }
        if (normalized === currentPath)
            return;

        currentPath = normalized;
        storage.setText(normalized);
        logDebug(`setWallpaper: ${normalized}`);
        scheduleRestart();
    }

    function scheduleRestart(): void {
        restartTimer.restart();
    }

    function stop(): void {
        if (!running)
            return;
        pendingCommand = [];
        killProc.running = true;
    }

    function resolveOutputs(): list<string> {
        const names = [];
        const monitors = Hypr?.monitors;
        const monitorCount = monitors?.length ?? 0;
        for (let i = 0; i < monitorCount; i++) {
            const monitor = monitors[i];
            const name = monitor?.name ?? "";
            if (name && !names.includes(name))
                names.push(name);
        }

        if (names.length > 0)
            return names;

        const screens = Quickshell.screens;
        const screenCount = screens?.length ?? 0;
        for (let i = 0; i < screenCount; i++) {
            const screen = screens[i];
            const name = screen?.name ?? "";
            if (name && !names.includes(name))
                names.push(name);
        }

        return names;
    }

    function restartNow(): void {
        if (!storageReady || !mpvpaperChecked)
            return;

        if (!available) {
            logDebug("restartNow: mpvpaper unavailable");
            stop();
            return;
        }

        if (!currentPath) {
            logDebug("restartNow: no currentPath");
            stop();
            return;
        }

        const outputs = resolveOutputs();
        if (outputs.length === 0) {
            console.warn("MpvpaperService: no outputs available");
            logDebug("restartNow: no outputs available");
            stop();
            return;
        }

        outputs.sort();
        const commandKey = `${outputs.join(",")}|${currentPath}`;
        if (commandKey === lastCommandKey && running)
            return;

        lastCommandKey = commandKey;
        pendingCommand = ["mpvpaper", "--auto-pause", "--layer", "background", "-p", "-o", mpvOptions];
        for (const output of outputs)
            pendingCommand.push(output, currentPath);

        logDebug(`restartNow: ${pendingCommand.join(" ")}`);
        killProc.running = true;
    }

    Timer {
        id: restartTimer

        interval: 150
        repeat: false
        onTriggered: root.restartNow()
    }

    Process {
        id: checkProc

        running: true
        command: ["sh", "-c", "command -v mpvpaper"]
        onExited: code => {
            root.mpvpaperChecked = true;
            root.available = code === 0;
            if (!root.available) {
                console.warn("MpvpaperService: mpvpaper not found in PATH");
                root.logDebug("mpvpaper not found in PATH");
            } else {
                root.logDebug("mpvpaper found");
            }
            root.scheduleRestart();
        }
    }

    Process {
        id: killProc

        command: ["pkill", "-x", "mpvpaper"]
        onExited: () => {
            if (root.pendingCommand.length === 0) {
                root.running = false;
                root.lastCommandKey = "";
                return;
            }

            Quickshell.execDetached(root.pendingCommand);
            root.pendingCommand = [];
            root.running = true;
            root.logDebug("mpvpaper launched");
        }
    }

    FileView {
        id: storage

        path: root.statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const normalized = root.normalizePath(text());
            root.currentPath = normalized;
            root.storageReady = true;
            root.logDebug(`storage loaded: ${normalized}`);
            root.scheduleRestart();
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                setText("");
            root.storageReady = true;
            root.logDebug("storage missing, initialized");
            root.scheduleRestart();
        }
    }

    FileView {
        id: debugView

        path: root.debugPath
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                setText("");
        }
    }

    Connections {
        target: Hypr

        function onMonitorsChanged(): void {
            root.scheduleRestart();
        }
    }

    onMpvOptionsChanged: scheduleRestart()
}
