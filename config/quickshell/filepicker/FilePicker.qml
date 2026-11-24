pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../bar/components"
import "../services"
import "../theme"

// Generic file/folder picker used by the XDG Desktop Portal FileChooser
// backend.  It deliberately mirrors the wallpaper picker's interaction model:
// a full-screen Overlay surface, a cached directory listing, keyboard and
// mouse navigation, an inline path field with directory completion, an inline
// new-folder row (header button or Ctrl+Shift+N), a recursive name search over
// the current folder, and Escape/outside-click cancellation.  Image and video
// tiles get a lazy 16:9 poster from file-thumbnail.sh: only delegates that the
// grid actually instantiates ask for one, and folders keep their glyph.
//
// The new-folder row sits between the filters and the save-name bar.  It
// validates the name locally, runs `mkdir` in argv form and then re-reads the
// folder, entering the created directory in the directory and save modes.
// Modes:
//   openFile      choose one file, or several when `multiple` is true
//   openDirectory choose the current folder
//   saveFile      choose a folder and a file name
//   saveFiles     choose a folder for a list of names supplied by the portal
//
// The portal backend passes a request JSON string over IPC and waits for the
// result file this component writes:
//   {"uris": ["/abs/path", ...], "writable": true}
//   {"cancelled": true}
Scope {
    id: root

    // ── Panel geometry ───────────────────────────────────────────────────
    readonly property int panelWidth: 1120
    readonly property int panelHeight: 760
    readonly property int screenMargin: 48
    readonly property int headerHeight: 56
    readonly property int searchHeight: 44
    readonly property int filterHeight: 40
    readonly property int folderRowHeight: 44
    readonly property int nameHeight: 44
    readonly property int footerHeight: 52
    readonly property int contentPadding: 16
    readonly property int tileSpacing: 12
    readonly property int gridColumns: 5
    readonly property int focusDelay: 20
    readonly property int completionDelay: 140
    readonly property int completionRowHeight: 28
    readonly property int searchDelay: 220
    readonly property int searchFlushDelay: 180
    // Must match the cap in search-files.sh; the worker reports truncation
    // with a `limit<TAB><cap>` record when the tree holds more matches.
    readonly property int searchLimit: 400

    readonly property real cellWidth: Math.floor(
        (panel.width - root.contentPadding * 2) / root.gridColumns)
    readonly property real tileWidth: root.cellWidth - root.tileSpacing
    readonly property int tileHeight: 156

    // ── Request state ────────────────────────────────────────────────────
    property bool active: false
    property real reveal: 0
    property string requestId: ""
    property string mode: "openFile"
    property string dialogTitle: "Open"
    property string acceptLabel: "Open"
    property bool multiple: false
    property var filters: []
    property int filterIndex: 0
    property string currentDir: ShellPaths.home
    property string currentName: ""
    property string currentFile: ""
    property var filesToSave: []
    property string resultPath: ""

    readonly property bool saveMode: root.mode === "saveFile" || root.mode === "saveFiles"
    readonly property bool saveNameMode: root.mode === "saveFile"
    readonly property bool directoryMode: root.mode === "openDirectory"
    readonly property bool hasFilters: root.filters.length > 0
    readonly property var filterModel: {
        const items = [{ name: "All files" }];
        for (let i = 0; i < root.filters.length; i++)
            items.push({ name: root.filters[i].name || "Filter " + (i + 1) });
        return items;
    }

    // ── Listing state ────────────────────────────────────────────────────
    property bool scanning: false
    property string scanError: ""
    property var allEntries: []
    property int fileCount: 0
    property int firstFileIndex: -1
    property int hoveredIndex: -1

    // ── Thumbnail previews ───────────────────────────────────────────────
    // Only a delegate that the grid actually instantiates asks for a preview,
    // so opening a huge photo folder generates nothing until a tile appears.
    // The map is replaced on every arrival: mutating a plain JS object in place
    // would not invalidate the tile bindings.  A failed path stays in
    // previewFailed so it is never retried, and the queue is capped: when a
    // fast scroll outruns ffmpeg the oldest pending request is dropped, since
    // those tiles have already left the viewport while the newest visible ones
    // are still waiting.
    property var previewMap: ({})
    property var previewQueue: []
    property var previewFailed: ({})
    property int previewGeneration: 0
    property int previewsLoaded: 0
    readonly property int previewQueueLimit: 64

    // Recursive search.  The typed text is debounced into search-files.sh and
    // the results replace the folder listing while a query is present; an
    // empty query shows the listing again.  Results stream in, so the model
    // is rebuilt on a short timer instead of once per recorded line.
    property bool searching: false
    property string searchText: ""
    property string searchError: ""
    property var searchResults: []
    property bool searchBusy: false
    property bool searchTruncated: false
    property bool discardingSearch: false
    property bool searchRestartPending: false

    readonly property string searchQuery: root.searchText.trim()
    readonly property bool searchActive: root.searching && root.searchQuery !== ""

    // Multi-select.  The object is replaced on every change so delegate
    // bindings invalidate; mutation in place would not notify QML.
    property var checkedPaths: ({})
    property int checkedCount: 0

    // Manual path entry, same contract as the wallpaper picker.
    property bool editingPath: false
    property bool pathBusy: false
    property string pathError: ""
    property var completions: []
    property int completionIndex: -1

    // Set while a running folder scan is stopped for a new directory.
    property bool restartPending: false
    property bool discardingEntries: false
    property string nameError: ""

    // Inline "New folder" row, opened from the header button or
    // Ctrl+Shift+N.  folderError is shared by the row and the footer hint.
    property bool creatingFolder: false
    property string folderError: ""

    readonly property var activeFilter: root.filterIndex > 0
        && root.filterIndex <= root.filters.length
        ? root.filters[root.filterIndex - 1] : null

    function currentEntry() {
        if (grid.currentIndex < 0 || grid.currentIndex >= entryModel.count)
            return null;
        return entryModel.get(grid.currentIndex);
    }

    readonly property bool canAccept: {
        if (root.mode === "openDirectory" || root.mode === "saveFiles")
            return true;
        if (root.mode === "saveFile")
            return nameInput.text.trim() !== ""
                && !nameInput.text.includes("/");
        if (root.multiple)
            return root.checkedCount > 0;
        const entry = root.currentEntry();
        return !!entry && entry.kind === "file";
    }

    // ── Request handling ─────────────────────────────────────────────────
    function openRequest(payload) {
        let spec;
        try {
            spec = JSON.parse(payload);
        } catch (error) {
            console.warn("FilePicker: invalid request:", error);
            return;
        }
        if (!spec || !spec.resultPath) {
            console.warn("FilePicker: request without resultPath");
            return;
        }

        // A second request while one is open replaces it; the first backend
        // must not hang waiting for a result that will never come.
        if (root.active && root.resultPath !== "" && root.resultPath !== spec.resultPath)
            root.writeResult({ cancelled: true });

        root.requestId = String(spec.id || "");
        root.mode = String(spec.mode || "openFile");
        root.dialogTitle = String(spec.title || "Open");
        root.acceptLabel = String(spec.acceptLabel
            || (root.mode === "openDirectory" ? "Select"
                : root.mode === "saveFile" || root.mode === "saveFiles" ? "Save" : "Open"));
        root.multiple = spec.multiple === true;
        root.filters = Array.isArray(spec.filters) ? spec.filters : [];
        root.filterIndex = 0;
        root.currentName = String(spec.currentName || "");
        nameInput.text = root.currentName;
        root.currentFile = String(spec.currentFile || "");
        root.filesToSave = Array.isArray(spec.files) ? spec.files.map(String) : [];
        root.resultPath = String(spec.resultPath);
        root.checkedPaths = ({});
        root.checkedCount = 0;
        root.nameError = "";
        root.pathError = "";
        root.editingPath = false;
        root.clearCompletions();
        root.resetSearch();
        root.resetNewFolder();

        let dir = String(spec.currentFolder || "");
        if (dir === "" && root.currentFile !== "")
            dir = root.currentFile.substring(0, root.currentFile.lastIndexOf("/"));
        if (dir !== "")
            root.currentDir = dir;

        root.active = true;
        root.resetEntries();
        root.resetPreviewQueue();
        root.beginScan();

        if (!win.visible) {
            root.reveal = 0;
            win.visible = true;
        }
        revealOut.stop();
        revealIn.restart();
        if (root.saveNameMode)
            nameFocusTimer.restart();
        else
            focusTimer.restart();
    }

    function cancelRequest(id) {
        if (root.active && root.requestId === String(id))
            root.cancel();
    }

    function writeResult(value) {
        if (root.resultPath === "")
            return;
        resultProc.command = [
            "sh", "-c", 'printf "%s" "$1" > "$2"',
            "kolir-file-picker",
            JSON.stringify(value),
            root.resultPath,
        ];
        resultProc.running = true;
    }

    function cancel() {
        root.writeResult({ cancelled: true });
        root.closePanel();
    }

    function finish(paths) {
        root.writeResult({ uris: paths, writable: true });
        root.closePanel();
    }

    function closePanel() {
        if (scanProc.running)
            scanProc.running = false;
        root.restartPending = false;
        root.discardingEntries = false;
        completionTimer.stop();
        root.clearCompletions();
        root.editingPath = false;
        root.pathError = "";
        root.resetSearch();
        if (pathCheckProc.running) {
            root.pathBusy = false;
            pathCheckProc.running = false;
        }
        root.active = false;
        root.checkedPaths = ({});
        root.checkedCount = 0;
        root.resetPreviewQueue();
        root.resetNewFolder();
        revealIn.stop();
        revealOut.restart();
        // The result process already captured resultPath in its command; drop
        // the stale request so a late backend cancel cannot target it.
        root.requestId = "";
        root.resultPath = "";
    }

    function accept() {
        if (!root.canAccept)
            return;

        if (root.mode === "openDirectory") {
            root.finish([root.currentDir]);
            return;
        }

        if (root.mode === "saveFiles") {
            const dir = root.currentDir.replace(/\/+$/, "");
            const paths = root.filesToSave.map(name => dir + "/" + name);
            root.finish(paths.length > 0 ? paths : [dir]);
            return;
        }

        if (root.mode === "saveFile") {
            const name = nameInput.text.trim();
            if (name === "" || name.includes("/")) {
                root.nameError = "Enter a file name";
                nameInput.forceActiveFocus();
                return;
            }
            const dir = root.currentDir.replace(/\/+$/, "");
            root.finish([dir + "/" + name]);
            return;
        }

        if (root.multiple) {
            const paths = Object.keys(root.checkedPaths);
            if (paths.length > 0)
                root.finish(paths);
            return;
        }

        const entry = root.currentEntry();
        if (entry && entry.kind === "file")
            root.finish([entry.path]);
    }

    function setFilter(index) {
        if (index === root.filterIndex)
            return;
        root.filterIndex = index;
        root.rebuildModel();
        focusTimer.restart();
    }

    // ── Listing ──────────────────────────────────────────────────────────
    function displayName(path) {
        const name = path.substring(path.lastIndexOf("/") + 1);
        return name === "" ? path : name;
    }

    // The extension lists are shared with file-thumbnail.sh: the helper
    // generates posters for exactly these two sets and rejects everything else,
    // so the grid never starts an ffmpeg run for an audio track or an archive.
    // `name` may be a path; only the last dot matters.
    function previewKindFor(name) {
        const dot = name.lastIndexOf(".");
        const ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : "";
        if (["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif", "heic", "tiff"].includes(ext))
            return "image";
        if (["mp4", "mkv", "mov", "avi", "webm", "flv", "m4v"].includes(ext))
            return "video";
        return "";
    }

    function previewKindForPath(path) {
        return root.previewKindFor(root.displayName(path));
    }

    function fileIconFor(name, folder) {
        if (folder)
            return Icons.folder;
        const preview = root.previewKindFor(name);
        if (preview === "image")
            return Icons.image;
        if (preview === "video")
            return Icons.movie;
        const dot = name.lastIndexOf(".");
        const ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : "";
        if (["mp3", "flac", "ogg", "wav", "m4a", "opus", "aac"].includes(ext))
            return Icons.audioFile;
        if (["zip", "tar", "gz", "xz", "zst", "7z", "rar", "bz2"].includes(ext))
            return Icons.archive;
        if (ext === "pdf")
            return Icons.pdf;
        if (["js", "ts", "qml", "py", "rs", "go", "c", "h", "cpp", "hpp", "lua",
             "sh", "zsh", "json", "toml", "yaml", "yml", "xml", "css", "html"].includes(ext))
            return Icons.code;
        if (["txt", "md", "rst", "conf", "ini", "log"].includes(ext))
            return Icons.file;
        return Icons.file;
    }

    // ── Preview request queue ────────────────────────────────────────────
    // FileTile emits previewRequested once, when the grid instantiates it.
    // Only previewable images and videos enter the queue, and a path is queued
    // at most once: loaded, failed, in-flight and queued paths are all skipped.
    // Requests beyond previewQueueLimit drop the oldest pending entry, not the
    // newest one, so the tiles at the current scroll position still win.
    function requestPreview(path) {
        if (!root.active || path === "")
            return;
        if (root.previewMap[path] || root.previewFailed[path])
            return;
        if (previewProc.running && previewProc.target === path)
            return;
        if (root.previewKindForPath(path) === "")
            return;
        if (root.previewQueue.indexOf(path) >= 0)
            return;
        const queue = root.previewQueue.slice();
        queue.push(path);
        while (queue.length > root.previewQueueLimit)
            queue.shift();
        root.previewQueue = queue;
        root.startNextPreview();
    }

    // Called on a new request, a panel close and every listing change.  The
    // generation is bumped before the worker is stopped, so a late exit or
    // output from the previous folder can never be mapped into the new one.
    function resetPreviewQueue() {
        root.previewGeneration += 1;
        root.previewQueue = [];
        root.previewMap = ({});
        root.previewFailed = ({});
        root.previewsLoaded = 0;
        if (previewProc.running)
            previewProc.running = false;
    }

    // A stopped worker keeps Quickshell's `running` true until its process
    // actually exits, so this never starts a second one over a draining child;
    // onExited calls back here for the next path.
    function startNextPreview() {
        if (!root.active || previewProc.running)
            return;
        while (root.previewQueue.length > 0) {
            const path = root.previewQueue[0];
            root.previewQueue = root.previewQueue.slice(1);
            if (root.previewMap[path] || root.previewFailed[path])
                continue;
            previewProc.target = path;
            previewProc.generation = root.previewGeneration;
            previewProc.output = "";
            previewProc.command = [
                "sh", ShellPaths.fileThumbnail, ShellPaths.filePreviewDir, path,
            ];
            previewProc.running = true;
            return;
        }
    }

    function finishPreview(generation, path, exitCode, output) {
        if (generation === root.previewGeneration && root.active) {
            const parts = output.trim().split("\t");
            if (exitCode === 0 && parts.length >= 2 && parts[0] !== ""
                && (parts[1] === "image" || parts[1] === "video")) {
                const map = Object.assign({}, root.previewMap);
                map[path] = { source: parts[0], kind: parts[1] };
                root.previewMap = map;
                root.previewsLoaded += 1;
            } else {
                const failed = Object.assign({}, root.previewFailed);
                failed[path] = true;
                root.previewFailed = failed;
            }
        }
        // Always advance: a stale worker that exited while the new folder was
        // already queued must not block the fresh queue behind it.
        root.startNextPreview();
    }

    function mimeForName(name) {
        const dot = name.lastIndexOf(".");
        const ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : "";
        const map = {
            png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg",
            gif: "image/gif", webp: "image/webp", svg: "image/svg+xml",
            avif: "image/avif", bmp: "image/bmp", tiff: "image/tiff",
            mp4: "video/mp4", mkv: "video/x-matroska", webm: "video/webm",
            mov: "video/quicktime", avi: "video/x-msvideo",
            mp3: "audio/mpeg", flac: "audio/flac", ogg: "audio/ogg",
            wav: "audio/wav", m4a: "audio/mp4", opus: "audio/ogg",
            pdf: "application/pdf", zip: "application/zip",
            tar: "application/x-tar", gz: "application/gzip",
            txt: "text/plain", md: "text/markdown", csv: "text/csv",
            html: "text/html", css: "text/css",
            js: "text/javascript", json: "application/json",
            xml: "application/xml", sh: "application/x-shellscript",
        };
        return map[ext] || "application/octet-stream";
    }

    function globMatch(pattern, name) {
        let expression = "^";
        for (let i = 0; i < pattern.length; i++) {
            const char = pattern[i];
            if (char === "*")
                expression += ".*";
            else if (char === "?")
                expression += ".";
            else
                expression += char.replace(/[.+^${}()|[\]\\]/g, "\\$&");
        }
        expression += "$";
        try {
            return new RegExp(expression).test(name);
        } catch (error) {
            return false;
        }
    }

    function matchesFilter(entry) {
        const filter = root.activeFilter;
        if (!filter)
            return true;
        for (let i = 0; i < (filter.patterns || []).length; i++)
            if (root.globMatch(filter.patterns[i], entry.name))
                return true;
        if ((filter.mimes || []).length > 0) {
            const mime = root.mimeForName(entry.name);
            for (let i = 0; i < filter.mimes.length; i++) {
                const wanted = filter.mimes[i];
                if (wanted === mime)
                    return true;
                if (wanted.endsWith("/*") && mime.startsWith(wanted.slice(0, -1)))
                    return true;
            }
        }
        return false;
    }

    function consumeLine(line) {
        if (root.discardingEntries)
            return;
        const parts = line.split("\t");
        if (parts.length < 2)
            return;
        const kind = parts[0];
        if (kind !== "dir" && kind !== "file")
            return;
        const path = parts[1];
        if (!path)
            return;
        const name = root.displayName(path);
        root.allEntries.push({
            kind: kind,
            path: path,
            name: name,
            icon: root.fileIconFor(name, kind === "dir"),
        });
    }

    // Search results show the path below the searched folder, so two files with
    // the same name stay distinguishable.  The icon and the save-file name keep
    // using the basename.
    function relativeLabel(path) {
        const dir = root.currentDir.replace(/\/+$/, "");
        const prefix = dir + "/";
        if (path.startsWith(prefix) && path.length > prefix.length)
            return path.substring(prefix.length);
        return root.displayName(path);
    }

    function consumeSearchLine(line) {
        if (root.discardingSearch)
            return;
        const parts = line.split("\t");
        if (parts.length < 2)
            return;
        if (parts[0] === "limit") {
            root.searchTruncated = true;
            return;
        }
        if (root.searchResults.length >= root.searchLimit)
            return;
        const kind = parts[0];
        if (kind !== "dir" && kind !== "file")
            return;
        const path = parts[1];
        if (!path)
            return;
        const base = root.displayName(path);
        root.searchResults.push({
            kind: kind,
            path: path,
            name: root.relativeLabel(path),
            icon: root.fileIconFor(base, kind === "dir"),
        });
    }

    function resetEntries() {
        root.allEntries = [];
        entryModel.clear();
        grid.currentIndex = -1;
        root.fileCount = 0;
        root.firstFileIndex = -1;
        root.hoveredIndex = -1;
        root.scanError = "";
    }

    function beginScan() {
        root.scanning = true;
        root.scanError = "";
        scanProc.running = true;
    }

    // Directories first, then files, both alphabetically.  The search worker
    // streams its matches in find order, so this runs again on every flush.
    function compareEntries(a, b) {
        if (a.kind !== b.kind)
            return a.kind === "dir" ? -1 : 1;
        const left = a.name.toLowerCase();
        const right = b.name.toLowerCase();
        if (left < right)
            return -1;
        return left > right ? 1 : 0;
    }

    function rebuildModel() {
        const current = root.currentEntry();
        const previous = current ? current.path : "";
        entryModel.clear();
        const source = root.searchActive ? root.searchResults : root.allEntries;
        const entries = [];
        for (let i = 0; i < source.length; i++) {
            const entry = source[i];
            if (entry.kind === "dir" || root.matchesFilter(entry))
                entries.push(entry);
        }
        entries.sort(root.compareEntries);
        for (let i = 0; i < entries.length; i++)
            entryModel.append(entries[i]);

        root.fileCount = 0;
        root.firstFileIndex = -1;
        for (let i = 0; i < entries.length; i++) {
            if (entries[i].kind !== "file")
                continue;
            root.fileCount += 1;
            if (root.firstFileIndex < 0)
                root.firstFileIndex = i;
        }

        let index = entries.length > 0
            ? (root.firstFileIndex >= 0 ? root.firstFileIndex : 0)
            : -1;
        if (previous !== "") {
            for (let i = 0; i < entries.length; i++) {
                if (entries[i].path === previous) {
                    index = i;
                    break;
                }
            }
        }
        grid.currentIndex = index;
    }

    function navigateTo(path) {
        if (root.creatingFolder)
            root.cancelNewFolder();
        if (path === "" || path === root.currentDir)
            return;

        // Opening a folder leaves search mode, like the Nautilus search view.
        if (root.searching)
            root.resetSearch();
        root.currentDir = path;
        root.resetEntries();
        root.resetPreviewQueue();

        if (scanProc.running) {
            // The worker cannot be retargeted: stop it and start the new
            // directory from onExited, so its stdout never mixes two folders.
            root.discardingEntries = true;
            root.restartPending = true;
            scanProc.running = false;
        } else {
            root.beginScan();
        }
    }

    function goUp() {
        const dir = root.currentDir;
        if (dir === "" || dir === "/")
            return;
        const slash = dir.lastIndexOf("/");
        root.navigateTo(slash <= 0 ? "/" : dir.substring(0, slash));
    }

    function goHome() {
        root.navigateTo(ShellPaths.home);
    }

    // Re-reads the current folder after a creation without moving anywhere.
    // A running listing worker is stopped and restarted from onExited, so its
    // old records can never mix with the new listing.
    function refreshCurrentDir() {
        if (root.searching)
            root.resetSearch();
        root.resetEntries();
        if (scanProc.running) {
            root.discardingEntries = true;
            root.restartPending = true;
            scanProc.running = false;
        } else {
            root.beginScan();
        }
    }

    // ── Search ───────────────────────────────────────────────────────────
    // Type-to-search from the grid.  A printable key only seeds a query when
    // no inline row owns input: the new-folder and path rows keep their text,
    // modified shortcuts belong to the panel, and navigation keys never become
    // a query even if a keyboard reports text for them.  A lone space must not
    // open an empty search, while spaces inside an existing query are ordinary
    // typing.
    function canTypeToSearch(event) {
        if (!event || event.text === "")
            return false;
        if (root.creatingFolder || root.editingPath)
            return false;
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        if (event.text.trim() === "" && !(root.searching && searchInput.text !== ""))
            return false;
        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Escape:
        case Qt.Key_Backspace:
        case Qt.Key_Delete:
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
        case Qt.Key_Left:
        case Qt.Key_Right:
        case Qt.Key_Up:
        case Qt.Key_Down:
        case Qt.Key_Home:
        case Qt.Key_End:
        case Qt.Key_PageUp:
        case Qt.Key_PageDown:
        case Qt.Key_Insert:
            return false;
        }
        if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35)
            return false;
        return true;
    }

    // Seeds the query with the key that opened the field.  beginSearch's focus
    // timer selects all text after a delay, which would make the next keystroke
    // replace the seed, so this path takes the focus synchronously and stops
    // that timer.  Assigning searchInput.text keeps the normal onTextChanged
    // debounce as the single search path; keys typed while the grid still owns
    // focus append (or replace the current selection) the same way.
    function typeToSearch(text) {
        searchFocusTimer.stop();
        if (!root.searching) {
            root.beginSearch();
            searchFocusTimer.stop();
            if (searchInput.text !== "")
                searchInput.text = "";
            searchInput.forceActiveFocus();
            searchInput.text = text;
            searchInput.cursorPosition = searchInput.text.length;
            return;
        }
        searchInput.forceActiveFocus();
        const current = searchInput.text;
        const selected = searchInput.selectedText;
        if (selected !== "") {
            const start = Math.min(searchInput.selectionStart, searchInput.selectionEnd);
            searchInput.text = current.substring(0, start) + text
                + current.substring(start + selected.length);
            searchInput.cursorPosition = start + text.length;
            return;
        }
        searchInput.text = current + text;
        searchInput.cursorPosition = searchInput.text.length;
    }

    function beginSearch() {
        if (root.creatingFolder)
            root.cancelNewFolder();
        if (root.searching) {
            searchInput.forceActiveFocus();
            searchInput.selectAll();
            return;
        }
        if (root.editingPath)
            root.cancelPathEdit();
        root.searching = true;
        root.searchText = "";
        root.searchError = "";
        root.searchResults = [];
        root.searchTruncated = false;
        root.searchBusy = false;
        searchFocusTimer.restart();
    }

    // Drops the search state without touching the model; closePanel and a new
    // request use it, while exitSearch also restores the folder listing.
    function resetSearch() {
        root.searching = false;
        searchTimer.stop();
        searchFlush.stop();
        root.stopSearch();
        searchInput.text = "";
        root.searchText = "";
        root.searchError = "";
        root.searchResults = [];
        root.searchTruncated = false;
        root.searchBusy = false;
    }

    function exitSearch() {
        if (!root.searching)
            return;
        root.resetSearch();
        root.resetPreviewQueue();
        root.rebuildModel();
    }

    function stopSearch() {
        searchFlush.stop();
        root.searchBusy = false;
        if (!searchProc.running) {
            root.discardingSearch = false;
            root.searchRestartPending = false;
            return;
        }
        root.discardingSearch = true;
        root.searchRestartPending = false;
        searchProc.running = false;
    }

    function startSearch() {
        if (!root.searching)
            return;
        const query = root.searchQuery;
        if (query === "")
            return;
        if (searchProc.running) {
            // The worker cannot be retargeted: stop it and launch the current
            // query from onExited so the old results never mix in.
            root.discardingSearch = true;
            root.searchRestartPending = true;
            searchProc.running = false;
            return;
        }
        root.launchSearch();
    }

    function launchSearch() {
        const query = root.searchQuery;
        if (!root.searching || query === "") {
            root.searchBusy = false;
            return;
        }
        root.searchResults = [];
        root.searchTruncated = false;
        root.searchError = "";
        root.searchBusy = true;
        root.resetPreviewQueue();
        root.rebuildModel();
        searchProc.command = [
            "sh", ShellPaths.searchFiles, root.currentDir, query,
        ];
        searchProc.running = true;
        searchFlush.restart();
    }

    function clearSearchText() {
        if (searchInput.text !== "")
            searchInput.text = "";
        else
            searchTimer.stop();
    }

    function moveSelection(step) {
        if (entryModel.count === 0)
            return;
        let index = grid.currentIndex;
        if (index < 0)
            index = step > 0 ? -1 : entryModel.count;
        index = (index + step + entryModel.count) % entryModel.count;
        grid.currentIndex = index;
        grid.positionViewAtIndex(index, GridView.Contain);
    }

    function activateEntry(kind, path, index) {
        grid.currentIndex = index;

        if (kind === "dir") {
            root.navigateTo(path);
            return;
        }

        if (root.directoryMode || root.mode === "saveFiles")
            return;

        if (root.mode === "saveFile") {
            // A search hit can live in a subfolder: leave search, move there
            // and fill the name so the portal receives the path the tile
            // showed.
            if (root.searching)
                root.exitSearch();
            const slash = path.lastIndexOf("/");
            const parent = slash > 0 ? path.substring(0, slash) : "/";
            if (parent !== root.currentDir)
                root.navigateTo(parent);
            root.currentName = root.displayName(path);
            nameInput.text = root.currentName;
            root.nameError = "";
            nameFocusTimer.restart();
            return;
        }

        if (root.multiple) {
            root.toggleChecked(path);
            return;
        }

        root.finish([path]);
    }

    function activateCurrent() {
        const entry = root.currentEntry();
        if (entry)
            root.activateEntry(entry.kind, entry.path, grid.currentIndex);
    }

    function toggleChecked(path) {
        const next = Object.assign({}, root.checkedPaths);
        if (next[path])
            delete next[path];
        else
            next[path] = true;
        root.checkedPaths = next;
        root.checkedCount = Object.keys(next).length;
    }

    function followHover(index) {
        if (index < 0 || index >= entryModel.count)
            return;
        grid.currentIndex = index;
    }

    // ── New folder ───────────────────────────────────────────────────────
    function resetNewFolder() {
        folderFocusTimer.stop();
        root.creatingFolder = false;
        root.folderError = "";
        folderInput.text = "";
    }

    function beginNewFolder() {
        if (root.creatingFolder) {
            folderInput.forceActiveFocus();
            folderInput.selectAll();
            return;
        }
        if (root.editingPath)
            root.cancelPathEdit();
        root.folderError = "";
        root.creatingFolder = true;
        folderInput.text = "";
        // Focus synchronously so the very next keystroke reaches the field;
        // the timer is the same retry the search and path fields use after a
        // window reveal.
        folderInput.forceActiveFocus();
        folderInput.selectAll();
        folderFocusTimer.restart();
    }

    function cancelNewFolder() {
        root.resetNewFolder();
        if (root.active)
            focusTimer.restart();
    }

    function folderNameProblem(name) {
        if (name === "")
            return "Enter a folder name";
        if (name.includes("/"))
            return "A folder name cannot contain /";
        if (name === "." || name === "..")
            return "Choose a different folder name";
        return "";
    }

    function submitNewFolder() {
        root.createFolder(folderInput.text);
    }

    // Shared by the row and the `newFolder` IPC hook.  The name is validated
    // here, before anything reaches the filesystem, and mkdir receives the
    // target as one argv entry so no shell ever parses it.
    function createFolder(rawName) {
        const name = String(rawName === undefined || rawName === null ? "" : rawName).trim();
        root.creatingFolder = true;
        const problem = root.folderNameProblem(name);
        if (problem !== "") {
            root.folderError = problem;
            if (root.active) {
                folderInput.forceActiveFocus();
                folderInput.selectAll();
            }
            return;
        }
        if (mkdirProc.running)
            return;
        const dir = root.currentDir.replace(/\/+$/, "");
        root.folderError = "";
        mkdirProc.target = dir + "/" + name;
        mkdirProc.request = root.requestId;
        mkdirProc.errorText = "";
        mkdirProc.command = ["mkdir", "--", mkdirProc.target];
        mkdirProc.running = true;
    }

    function folderErrorMessage(message) {
        const text = String(message || "");
        if (/file exists/i.test(text))
            return "An item with that name already exists";
        if (/permission denied/i.test(text))
            return "Permission denied";
        if (/read-only file system/i.test(text))
            return "The folder is on a read-only filesystem";
        if (/no such file or directory/i.test(text))
            return "The current folder no longer exists";
        if (/file name too long/i.test(text))
            return "That folder name is too long";
        if (/not a directory/i.test(text))
            return "The current folder is no longer available";
        if (text !== "")
            return text.replace(/^mkdir:\s*/, "");
        return "Could not create the folder";
    }

    // ── Path editing / completion ────────────────────────────────────────
    function normalizePath(raw) {
        let path = raw.trim();
        if (path === "")
            return "";
        if (path === "~")
            path = ShellPaths.home;
        else if (path.startsWith("~/"))
            path = ShellPaths.home + path.substring(1);
        else if (!path.startsWith("/"))
            path = root.currentDir + "/" + path;
        if (path.length > 1)
            path = path.replace(/\/+$/, "");
        return path;
    }

    function beginPathEdit() {
        if (root.creatingFolder)
            root.cancelNewFolder();
        if (root.searching)
            root.exitSearch();
        root.pathError = "";
        root.clearCompletions();
        root.editingPath = true;
        pathInput.text = root.currentDir;
        pathInput.forceActiveFocus();
        pathInput.selectAll();
        pathFocusTimer.restart();
        completionTimer.restart();
    }

    function cancelPathEdit() {
        completionTimer.stop();
        root.clearCompletions();
        root.editingPath = false;
        root.pathError = "";
        focusTimer.restart();
    }

    function submitPath() {
        if (root.pathBusy)
            return;
        const target = root.normalizePath(pathInput.text);
        if (target === "") {
            root.pathError = "Enter a folder path";
            return;
        }
        root.pathBusy = true;
        root.pathError = "";
        pathCheckProc.resolved = "";
        pathCheckProc.command = [
            "sh", "-c",
            'p=$(readlink -f -- "$1") || exit 1; [ -d "$p" ] && [ -r "$p" ] || exit 1; printf "%s\\n" "$p"',
            "kolir-path",
            target,
        ];
        pathCheckProc.running = true;
    }

    function clearCompletions() {
        root.completions = [];
        root.completionIndex = -1;
    }

    function requestCompletions() {
        if (!root.editingPath)
            return;
        const query = pathInput.text;
        completeProc.query = query;
        if (completeProc.running) {
            completeProc.restartPending = true;
            return;
        }
        root.startCompletion();
    }

    function startCompletion() {
        completeProc.activeQuery = completeProc.query;
        completeOut.runQuery = completeProc.activeQuery;
        completeProc.command = [
            "sh",
            ShellPaths.completeDirs,
            root.currentDir,
            completeProc.activeQuery,
        ];
        completeProc.running = true;
    }

    function applyCompletions(query, output) {
        if (!root.editingPath || query !== pathInput.text)
            return;
        const lines = output.split("\n").map(line => line.trim())
            .filter(line => line !== "");
        root.completions = lines.slice(0, 8);
        root.completionIndex = -1;
    }

    function completeSuggestion(index) {
        if (index < 0 || index >= root.completions.length)
            return;
        pathInput.text = root.completions[index] + "/";
        pathInput.cursorPosition = pathInput.text.length;
        root.completionIndex = -1;
        completionTimer.restart();
    }

    function chooseSuggestion(index) {
        if (index < 0 || index >= root.completions.length)
            return;
        pathInput.text = root.completions[index];
        root.submitPath();
    }

    function handleEscape() {
        // The inline creation row is the innermost mode: Escape closes it
        // before it clears a search, cancels a path edit or dismisses the
        // panel.
        if (root.creatingFolder) {
            root.cancelNewFolder();
            return;
        }
        if (root.editingPath) {
            if (root.completions.length > 0)
                root.clearCompletions();
            else
                root.cancelPathEdit();
            return;
        }
        if (root.searching) {
            if (searchInput.text !== "") {
                root.clearSearchText();
            } else {
                root.exitSearch();
                focusTimer.restart();
            }
            return;
        }
        if (root.completions.length > 0) {
            root.clearCompletions();
            return;
        }
        root.cancel();
    }

    IpcHandler {
        target: "filePicker"

        function open(request: string): void {
            root.openRequest(request);
        }

        function cancel(id: string): void {
            root.cancelRequest(id);
        }

        // Automation/debug hook: confirms the current selection exactly like
        // the Accept button. The portal itself never needs it.
        function accept(): void {
            root.accept();
        }

        // Automation/debug hook: toggles one grid row in multi-select mode.
        function toggleIndex(index: int): void {
            if (index < 0 || index >= entryModel.count)
                return;
            const entry = entryModel.get(index);
            if (entry.kind === "file")
                root.toggleChecked(entry.path);
        }

        // Automation/debug hook: opens the search field and applies a query
        // exactly as if it had been typed.
        function search(query: string): void {
            root.beginSearch();
            searchInput.text = String(query);
        }

        // Automation/debug hook: leaves search mode and shows the folder again.
        // Restores grid focus like the Escape and header-search exits do, so
        // type-to-search keeps working after this call.
        function closeSearch(): void {
            root.exitSearch();
            focusTimer.restart();
        }

        // Automation/debug hook: runs the new-folder row's creation path.  The
        // outcome is visible through creatingFolder/folderError in status().
        function newFolder(name: string): void {
            root.beginNewFolder();
            folderInput.text = String(name);
            root.submitNewFolder();
        }

        function status(): string {
            return JSON.stringify({
                active: root.active,
                id: root.requestId,
                mode: root.mode,
                dir: root.currentDir,
                canAccept: root.canAccept,
                checked: root.checkedCount,
                files: root.fileCount,
                name: root.currentName,
                input: nameInput.text,
                searching: root.searching,
                query: root.searchQuery,
                matches: root.searchActive ? root.fileCount : 0,
                searchBusy: root.searchBusy,
                truncated: root.searchTruncated,
                creatingFolder: root.creatingFolder,
                folderError: root.folderError,
                previews: root.previewsLoaded,
                previewQueue: root.previewQueue.length,
            });
        }
    }

    ListModel {
        id: entryModel
    }

    Process {
        id: scanProc

        running: false
        command: ["sh", ShellPaths.listFiles, root.currentDir]

        stdout: SplitParser {
            onRead: line => root.consumeLine(line)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "") {
                    root.scanError = message;
                    console.warn("FilePicker: listing worker:", message);
                }
            }
        }

        onExited: code => {
            if (root.restartPending) {
                root.restartPending = false;
                root.discardingEntries = false;
                root.resetEntries();
                root.beginScan();
                return;
            }
            root.scanning = false;
            root.rebuildModel();
            if (entryModel.count > 0 && grid.currentIndex < 0)
                grid.currentIndex = 0;
        }
    }

    Process {
        id: searchProc

        running: false

        stdout: SplitParser {
            onRead: line => root.consumeSearchLine(line)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "") {
                    root.searchError = message;
                    console.warn("FilePicker: search worker:", message);
                }
            }
        }

        onExited: code => {
            searchFlush.stop();
            if (root.discardingSearch) {
                root.discardingSearch = false;
                root.searchBusy = false;
                if (root.searchRestartPending) {
                    root.searchRestartPending = false;
                    root.launchSearch();
                }
                return;
            }
            root.searchBusy = false;
            root.rebuildModel();
        }
    }

    Process {
        id: pathCheckProc

        property string resolved: ""

        running: false

        stdout: StdioCollector {
            onStreamFinished: pathCheckProc.resolved = text.trim()
        }

        onExited: code => {
            root.pathBusy = false;
            if (!root.editingPath)
                return;
            if (code === 0 && pathCheckProc.resolved !== "") {
                completionTimer.stop();
                root.clearCompletions();
                root.editingPath = false;
                root.pathError = "";
                root.navigateTo(pathCheckProc.resolved);
                focusTimer.restart();
                return;
            }
            root.pathError = "Folder not found";
            pathInput.forceActiveFocus();
        }
    }

    Process {
        id: completeProc

        property string query: ""
        property string activeQuery: ""
        property bool restartPending: false

        running: false

        stdout: StdioCollector {
            id: completeOut

            property string runQuery: ""

            onStreamFinished: root.applyCompletions(runQuery, text)
        }

        onExited: code => {
            if (completeProc.restartPending) {
                completeProc.restartPending = false;
                root.startCompletion();
            }
        }
    }

    Process {
        id: resultProc

        running: false

        onExited: code => {
            if (code !== 0)
                console.warn("FilePicker: writing the result failed, exit code", code);
        }
    }

    // One poster at a time: previewProc runs file-thumbnail.sh for the head of
    // the queue and the next path starts only from onExited, so a fast scroll
    // cannot spawn parallel ffmpeg runs. The stdout collector always completes
    // before onExited, which is when the record is mapped into previewMap.
    Process {
        id: previewProc

        property string target: ""
        property int generation: 0
        property string output: ""

        running: false

        stdout: StdioCollector {
            onStreamFinished: previewProc.output = text
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("FilePicker: thumbnail worker:", text.trim());
            }
        }

        onExited: code => root.finishPreview(
            previewProc.generation, previewProc.target, code, previewProc.output)
    }

    // mkdir runs in argv form: the folder name is never handed to a shell.
    Process {
        id: mkdirProc

        property string target: ""
        // The request this creation belongs to, so a late result cannot
        // navigate a panel that has already moved on.
        property string request: ""
        property string errorText: ""

        running: false

        stderr: StdioCollector {
            onStreamFinished: mkdirProc.errorText = text.trim()
        }

        onExited: (exitCode, exitStatus) => {
            if (mkdirProc.request !== root.requestId)
                return;
            if (!root.active) {
                // The panel closed while mkdir ran; drop any pending row state.
                root.resetNewFolder();
                return;
            }

            if (exitCode !== 0) {
                if (!root.creatingFolder)
                    return;
                root.folderError = root.folderErrorMessage(mkdirProc.errorText);
                console.warn("FilePicker: mkdir failed:", mkdirProc.errorText);
                folderInput.forceActiveFocus();
                return;
            }

            const created = mkdirProc.target;
            // Escape may have closed the row while mkdir was running: the
            // folder still exists, but the panel should not jump into it.
            const shouldEnter = root.creatingFolder;
            root.creatingFolder = false;
            root.folderError = "";
            folderInput.text = "";
            if (shouldEnter && (root.directoryMode || root.saveMode))
                root.navigateTo(created);
            else
                root.refreshCurrentDir();
            focusTimer.restart();
        }
    }

    NumberAnimation {
        id: revealIn

        target: root
        property: "reveal"
        to: 1
        duration: Motion.popupEnter
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: revealOut

        target: root
        property: "reveal"
        to: 0
        duration: Motion.popupExit
        easing.type: Easing.InCubic

        onFinished: {
            if (root.reveal <= 0.01) {
                root.reveal = 0;
                win.visible = false;
            }
        }
    }

    Timer {
        id: focusTimer

        interval: root.focusDelay
        repeat: false
        onTriggered: grid.forceActiveFocus()
    }

    Timer {
        id: nameFocusTimer

        interval: root.focusDelay
        repeat: false
        onTriggered: {
            if (root.saveNameMode) {
                nameInput.text = root.currentName;
                nameInput.forceActiveFocus();
                nameInput.selectAll();
            }
        }
    }

    Timer {
        id: pathFocusTimer

        interval: root.focusDelay
        repeat: false
        onTriggered: {
            if (root.editingPath) {
                pathInput.forceActiveFocus();
                pathInput.selectAll();
            }
        }
    }

    Timer {
        id: completionTimer

        interval: root.completionDelay
        repeat: false
        onTriggered: root.requestCompletions()
    }

    Timer {
        id: folderFocusTimer

        interval: root.focusDelay
        repeat: false
        onTriggered: {
            if (root.active && root.creatingFolder) {
                folderInput.forceActiveFocus();
                folderInput.selectAll();
            }
        }
    }

    Timer {
        id: searchFocusTimer

        interval: root.focusDelay
        repeat: false
        onTriggered: {
            if (root.searching) {
                searchInput.forceActiveFocus();
                searchInput.selectAll();
            }
        }
    }

    Timer {
        id: searchTimer

        interval: root.searchDelay
        repeat: false
        onTriggered: root.startSearch()
    }

    // Results stream in while find is walking the tree; rebuilding on every
    // line would reset the grid constantly, so the model follows the growing
    // result array on its own short beat.
    Timer {
        id: searchFlush

        interval: root.searchFlushDelay
        repeat: true
        onTriggered: root.rebuildModel()
    }

    PanelWindow {
        id: win

        visible: false
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        implicitWidth: screen ? screen.width : 0
        implicitHeight: screen ? screen.height : 0

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "filepicker"
        WlrLayershell.exclusiveZone: 0

        onVisibleChanged: {
            if (!visible) {
                revealIn.stop();
                revealOut.stop();
                root.reveal = 0;
            }
        }

        // Clicking anywhere outside the panel dismisses it without a choice.
        MouseArea {
            anchors.fill: parent
            onClicked: root.cancel()
        }

        Item {
            anchors.fill: parent
            opacity: root.reveal
            transform: Translate { y: -(1.0 - root.reveal) * 8 }

            Surface {
                id: panel

                anchors.centerIn: parent
                width: Math.min(root.panelWidth, win.width - root.screenMargin * 2)
                height: Math.min(root.panelHeight, win.height - root.screenMargin * 2)
                radius: Dimensions.radius.extraLarge
                surfaceColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.80)
                borderWidth: 2
                borderColor: Colors.primary

                // Clicks inside the panel must not reach the dismissal layer.
                MouseArea {
                    anchors.fill: parent
                }

                // Opens the inline new-folder row from any focus state in the
                // panel (grid, save name, search or path field).
                Shortcut {
                    sequence: "Ctrl+Shift+N"
                    enabled: root.active && !root.creatingFolder
                    onActivated: root.beginNewFolder()
                }

                Item {
                    id: headerBar

                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    height: root.headerHeight

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 20
                            verticalCenter: parent.verticalCenter
                        }
                        text: root.saveMode ? Icons.save : Icons.file
                        color: Colors.primary
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.extraLarge
                    }

                    Column {
                        id: titleColumn

                        anchors {
                            left: parent.left
                            leftMargin: 52
                            right: headerControls.left
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 1

                        Text {
                            text: root.dialogTitle
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.titleSmall
                            font.weight: Typography.weight.bold
                            elide: Text.ElideRight
                        }

                        Item {
                            id: pathRow

                            width: parent.width
                            height: 24

                            Text {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                visible: !root.editingPath
                                text: root.currentDir
                                color: Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideMiddle

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: root.beginPathEdit()
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: root.editingPath
                                radius: Dimensions.radius.small
                                color: Colors.surfaceContainerHighest
                                border.width: 1
                                border.color: root.pathError !== ""
                                    ? Colors.error
                                    : Colors.primary

                                TextInput {
                                    id: pathInput

                                    anchors {
                                        fill: parent
                                        leftMargin: 8
                                        rightMargin: 8
                                    }
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Colors.onSurface
                                    selectionColor: Colors.withAlpha(Colors.primary, 0.35)
                                    selectedTextColor: Colors.onSurface
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.labelMedium
                                    clip: true
                                    selectByMouse: true

                                    onTextChanged: {
                                        if (!root.editingPath)
                                            return;
                                        root.completionIndex = -1;
                                        if (text === "") {
                                            root.clearCompletions();
                                            return;
                                        }
                                        completionTimer.restart();
                                    }

                                    Keys.onPressed: event => {
                                        const count = root.completions.length;
                                        if (event.key === Qt.Key_Down && count > 0) {
                                            root.completionIndex = (root.completionIndex + 1) % count;
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Up && count > 0) {
                                            root.completionIndex = root.completionIndex <= 0
                                                ? count - 1 : root.completionIndex - 1;
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Tab) {
                                            if (count > 0)
                                                root.completeSuggestion(root.completionIndex >= 0
                                                    ? root.completionIndex : 0);
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Escape) {
                                            root.handleEscape();
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Return
                                                   || event.key === Qt.Key_Enter) {
                                            if (root.completionIndex >= 0 && root.completionIndex < count)
                                                root.chooseSuggestion(root.completionIndex);
                                            else
                                                root.submitPath();
                                            event.accepted = true;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        id: headerControls

                        anchors {
                            right: parent.right
                            rightMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        IconButton {
                            icon: root.searching ? Icons.searchOff : Icons.search
                            iconSize: Dimensions.icon.medium
                            active: root.searching
                            onClicked: {
                                if (root.searching) {
                                    root.exitSearch();
                                    focusTimer.restart();
                                } else {
                                    root.beginSearch();
                                }
                            }
                        }

                        IconButton {
                            icon: Icons.edit
                            iconSize: Dimensions.icon.medium
                            active: root.editingPath
                            onClicked: root.editingPath
                                ? root.cancelPathEdit()
                                : root.beginPathEdit()
                        }

                        IconButton {
                            icon: Icons.createNewFolder
                            iconSize: Dimensions.icon.medium
                            active: root.creatingFolder
                            onClicked: root.creatingFolder
                                ? root.cancelNewFolder()
                                : root.beginNewFolder()
                        }

                        IconButton {
                            icon: Icons.home
                            iconSize: Dimensions.icon.medium
                            iconColor: root.currentDir === ShellPaths.home
                                ? Colors.withAlpha(Colors.onSurfaceVariant, 0.45)
                                : Colors.onSurface
                            onClicked: root.goHome()
                        }

                        IconButton {
                            icon: Icons.chevronUp
                            iconSize: Dimensions.icon.medium
                            visible: root.currentDir !== "/" && root.currentDir !== ""
                            onClicked: root.goUp()
                        }

                        IconButton {
                            icon: Icons.close
                            iconSize: Dimensions.icon.medium
                            onClicked: root.cancel()
                        }
                    }

                    Rectangle {
                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                            right: parent.right
                        }
                        height: 1
                        color: Colors.withAlpha(Colors.outlineVariant, 0.25)
                    }
                }

                Item {
                    id: searchBar

                    anchors {
                        top: headerBar.bottom
                        left: parent.left
                        right: parent.right
                    }
                    height: root.searching ? root.searchHeight : 0
                    visible: root.searching
                    clip: true

                    Item {
                        id: searchRow

                        anchors {
                            fill: parent
                            leftMargin: root.contentPadding
                            rightMargin: root.contentPadding
                        }

                        Text {
                            id: searchGlyph

                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            text: Icons.search
                            color: Colors.primary
                            font.family: Typography.iconFont
                            font.pixelSize: Dimensions.icon.medium
                        }

                        IconButton {
                            id: searchClear

                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            icon: Icons.close
                            iconSize: Dimensions.icon.small
                            visible: searchInput.text !== ""
                            onClicked: {
                                root.clearSearchText();
                                searchInput.forceActiveFocus();
                            }
                        }

                        Rectangle {
                            id: searchField

                            anchors {
                                left: searchGlyph.right
                                right: searchClear.left
                                leftMargin: 10
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            height: 34
                            radius: Dimensions.radius.small
                            color: Colors.surfaceContainerHighest
                            border.width: 1
                            border.color: root.searchError !== ""
                                ? Colors.error
                                : Colors.primary

                            TextInput {
                                id: searchInput

                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                verticalAlignment: TextInput.AlignVCenter
                                color: Colors.onSurface
                                selectionColor: Colors.withAlpha(Colors.primary, 0.35)
                                selectedTextColor: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                clip: true
                                selectByMouse: true

                                onTextChanged: {
                                    if (!root.searching)
                                        return;
                                    root.searchText = text;
                                    root.searchError = "";
                                    if (root.searchQuery === "") {
                                        searchTimer.stop();
                                        root.stopSearch();
                                        root.searchResults = [];
                                        root.searchTruncated = false;
                                        root.rebuildModel();
                                        return;
                                    }
                                    searchTimer.restart();
                                }

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Down) {
                                        root.moveSelection(1);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Up) {
                                        root.moveSelection(-1);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Escape) {
                                        root.handleEscape();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Return
                                               || event.key === Qt.Key_Enter) {
                                        root.activateCurrent();
                                        event.accepted = true;
                                    }
                                }
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 10
                                    right: parent.right
                                    rightMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                visible: searchInput.text === ""
                                text: "Search in " + root.currentDir
                                color: Colors.withAlpha(Colors.onSurfaceVariant, 0.7)
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                            right: parent.right
                        }
                        height: 1
                        color: Colors.withAlpha(Colors.outlineVariant, 0.25)
                    }
                }

                Item {
                    id: filterBar

                    anchors {
                        top: searchBar.bottom
                        left: parent.left
                        right: parent.right
                    }
                    height: root.hasFilters ? root.filterHeight : 0
                    visible: root.hasFilters
                    clip: true

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: root.contentPadding
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 8

                        Repeater {
                            model: root.filterModel

                            delegate: Pill {
                                id: filterPill

                                required property var modelData
                                required property int index

                                text: modelData.name
                                textSize: Typography.size.labelSmall
                                horizontalPadding: 12
                                active: index === root.filterIndex

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setFilter(filterPill.index)
                                }
                            }
                        }
                    }
                }

                Item {
                    id: folderBar

                    anchors {
                        top: filterBar.bottom
                        left: parent.left
                        right: parent.right
                    }
                    height: root.creatingFolder ? root.folderRowHeight : 0
                    visible: root.creatingFolder
                    clip: true

                    Item {
                        anchors {
                            fill: parent
                            leftMargin: root.contentPadding
                            rightMargin: root.contentPadding
                        }

                        Text {
                            id: folderGlyph

                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            text: Icons.createNewFolder
                            color: Colors.primary
                            font.family: Typography.iconFont
                            font.pixelSize: Dimensions.icon.medium
                        }

                        Row {
                            id: folderActions

                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 8

                            Pill {
                                icon: Icons.check
                                text: "Create"
                                textSize: Typography.size.labelSmall
                                horizontalPadding: 12

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.submitNewFolder()
                                }
                            }

                            Pill {
                                icon: Icons.close
                                text: "Cancel"
                                textSize: Typography.size.labelSmall
                                horizontalPadding: 12

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.cancelNewFolder()
                                }
                            }
                        }

                        Surface {
                            anchors {
                                left: folderGlyph.right
                                right: folderActions.left
                                leftMargin: 10
                                rightMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            height: 32
                            radius: Dimensions.radius.small
                            surfaceColor: Colors.surfaceContainerHighest
                            borderWidth: 1
                            borderColor: root.folderError !== "" ? Colors.error : Colors.primary

                            TextInput {
                                id: folderInput

                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                verticalAlignment: TextInput.AlignVCenter
                                color: Colors.onSurface
                                selectionColor: Colors.withAlpha(Colors.primary, 0.35)
                                selectedTextColor: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                clip: true
                                selectByMouse: true

                                onTextEdited: root.folderError = ""

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape) {
                                        root.cancelNewFolder();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Return
                                               || event.key === Qt.Key_Enter) {
                                        root.submitNewFolder();
                                        event.accepted = true;
                                    }
                                }
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 10
                                    right: parent.right
                                    rightMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                visible: folderInput.text === ""
                                text: "Folder name"
                                color: Colors.withAlpha(Colors.onSurfaceVariant, 0.7)
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Item {
                    id: nameBar

                    anchors {
                        top: folderBar.bottom
                        left: parent.left
                        right: parent.right
                    }
                    height: root.saveMode ? root.nameHeight : 0
                    visible: root.saveMode
                    clip: true

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: root.contentPadding
                            right: parent.right
                            rightMargin: root.contentPadding
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.saveNameMode ? "Name" : "Files"
                            color: Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            font.weight: Typography.weight.bold
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.saveNameMode
                            width: parent.width - 60
                            height: 32
                            radius: Dimensions.radius.small
                            color: Colors.surfaceContainerHighest
                            border.width: 1
                            border.color: root.nameError !== "" ? Colors.error : Colors.primary

                            TextInput {
                                id: nameInput

                                anchors {
                                    fill: parent
                                    leftMargin: 8
                                    rightMargin: 8
                                }
                                verticalAlignment: TextInput.AlignVCenter
                                color: Colors.onSurface
                                selectionColor: Colors.withAlpha(Colors.primary, 0.35)
                                selectedTextColor: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                clip: true
                                selectByMouse: true

                                onTextEdited: {
                                    root.currentName = text;
                                    root.nameError = "";
                                }

                                onAccepted: root.accept()

                                Keys.onEscapePressed: root.handleEscape()
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !root.saveNameMode
                            width: parent.width - 60
                            text: root.filesToSave.length > 0
                                ? root.filesToSave.join(", ")
                                : "No names supplied"
                            color: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            elide: Text.ElideMiddle
                        }
                    }
                }

                GridView {
                    id: grid

                    anchors {
                        top: nameBar.bottom
                        bottom: footerBar.top
                        left: parent.left
                        right: parent.right
                        margins: root.contentPadding
                    }

                    clip: true
                    focus: true
                    model: entryModel
                    currentIndex: -1
                    keyNavigationWraps: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: root.tileHeight

                    onMovingChanged: {
                        if (!moving && root.hoveredIndex >= 0)
                            root.followHover(root.hoveredIndex);
                    }

                    cellWidth: root.cellWidth
                    cellHeight: root.tileHeight + root.tileSpacing

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => {
                            const pixel = event.pixelDelta.y;
                            const angle = event.angleDelta.y;
                            grid.cancelFlick();
                            const max = Math.max(0, grid.contentHeight - grid.height);
                            if (angle !== 0)
                                grid.contentY = Math.max(0, Math.min(max,
                                    grid.contentY - angle / 120 * grid.cellHeight * 0.7));
                            else if (pixel !== 0)
                                grid.contentY = Math.max(0, Math.min(max,
                                    grid.contentY - pixel));
                            event.accepted = true;
                        }
                    }

                    Keys.onReturnPressed: root.activateCurrent()
                    Keys.onEnterPressed: root.activateCurrent()
                    Keys.onEscapePressed: root.handleEscape()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Backspace) {
                            if (root.searching) {
                                // Backspace edits the query, it does not leave
                                // the searched folder.
                                searchInput.forceActiveFocus();
                                searchInput.selectAll();
                            } else {
                                root.goUp();
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_F
                                   && (event.modifiers & Qt.ControlModifier)) {
                            root.beginSearch();
                            event.accepted = true;
                        } else if (root.canTypeToSearch(event)) {
                            root.typeToSearch(event.text);
                            event.accepted = true;
                        }
                    }

                    delegate: FileTile {
                        required property int index
                        required property string kind
                        required property string path
                        required property string name
                        required property string icon

                        width: root.tileWidth
                        height: root.tileHeight
                        fileName: name
                        fileIcon: icon
                        folder: kind === "dir"
                        multiple: root.multiple && kind === "file"
                        checked: root.checkedPaths[path] === true
                        selected: GridView.isCurrentItem
                        previewSource: root.previewMap[path]
                            ? root.previewMap[path].source : ""
                        previewKind: root.previewMap[path]
                            ? root.previewMap[path].kind : ""

                        onPreviewRequested: root.requestPreview(path)

                        onHoveredChanged: {
                            root.hoveredIndex = hovered
                                ? index
                                : (root.hoveredIndex === index ? -1 : root.hoveredIndex);
                            if (hovered && !grid.moving)
                                root.followHover(index);
                        }

                        onActivated: root.activateEntry(kind, path, index)
                    }
                }

                Surface {
                    id: completionPopup

                    z: 10
                    x: 52
                    y: root.headerHeight
                    width: titleColumn.width
                    height: Math.min(root.completions.length, 8)
                        * root.completionRowHeight + 8
                    visible: root.editingPath && root.completions.length > 0
                    radius: Dimensions.radius.medium
                    surfaceColor: Colors.withAlpha(Colors.surfaceContainerHigh, 0.98)
                    borderWidth: 1
                    borderColor: Colors.withAlpha(Colors.primary, 0.35)

                    ListView {
                        anchors {
                            fill: parent
                            margins: 4
                        }
                        clip: true
                        interactive: false
                        model: root.completions

                        delegate: Rectangle {
                            id: completionRow

                            required property string modelData
                            required property int index

                            readonly property bool highlighted: index === root.completionIndex

                            width: ListView.view.width
                            height: root.completionRowHeight
                            radius: Dimensions.radius.small
                            color: completionRow.highlighted
                                ? Colors.stateLayer(Colors.primary, 0.16)
                                : "transparent"

                            Row {
                                anchors {
                                    fill: parent
                                    leftMargin: 8
                                    rightMargin: 8
                                }
                                spacing: 8

                                Text {
                                    id: completionIcon

                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Icons.folder
                                    color: completionRow.highlighted
                                        ? Colors.primary
                                        : Colors.onSurfaceVariant
                                    font.family: Typography.iconFont
                                    font.pixelSize: Dimensions.icon.small
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - completionIcon.width - parent.spacing
                                    text: completionRow.modelData
                                    color: Colors.onSurface
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.labelSmall
                                    elide: Text.ElideMiddle
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.completionIndex = completionRow.index
                                onClicked: root.chooseSuggestion(completionRow.index)
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: grid
                    spacing: 10
                    visible: entryModel.count === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.scanning || (root.searchActive && root.searchBusy)
                            ? (root.searchActive ? Icons.search : Icons.folder)
                            : Icons.searchOff
                        color: Colors.withAlpha(Colors.onSurfaceVariant, 0.55)
                        font.family: Typography.iconFont
                        font.pixelSize: 32
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(implicitWidth, panel.width - 80)
                        text: root.scanError !== ""
                            ? root.scanError
                            : root.searchActive && root.searchError !== ""
                                ? root.searchError
                                : root.searchActive
                                    ? root.searchBusy
                                        ? "Searching " + root.currentDir
                                        : "No matches for \"" + root.searchQuery
                                            + "\" in " + root.currentDir
                                    : root.scanning
                                        ? "Loading " + root.currentDir
                                        : "No files in " + root.currentDir
                        color: root.scanError !== ""
                            || (root.searchActive && root.searchError !== "")
                            ? Colors.error : Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelMedium
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Item {
                    id: footerBar

                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }
                    height: root.footerHeight

                    Rectangle {
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        height: 1
                        color: Colors.withAlpha(Colors.outlineVariant, 0.25)
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 20
                            right: footerControls.left
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        text: root.folderError !== ""
                            ? root.folderError
                            : root.nameError !== ""
                                ? root.nameError
                                : root.pathError !== ""
                                    ? root.pathError
                                    : root.creatingFolder
                                        ? "[Enter] Create folder   [Esc] Cancel"
                                        : root.editingPath
                                            ? (root.completions.length > 0
                                                ? "[Tab] Complete   [Up/Down] Select   [Enter] Go   [Esc] Cancel"
                                                : "[Enter] Go   [Esc] Cancel")
                                            : root.searching
                                                ? (root.searchActive
                                                    ? "[Type] Search   [Up/Down] Select   [Enter] Open   [Esc] Clear"
                                                        + "   [Ctrl+Shift+N] New folder"
                                                    : "[Type] Search   [Esc] Close"
                                                        + "   [Ctrl+Shift+N] New folder")
                                                : root.directoryMode
                                                    ? "[Arrows] Move   [Enter] Open folder   [Backspace] Up"
                                                        + "   [Esc] Close   [Type] Search   [Ctrl+Shift+N] New folder"
                                                    : root.saveNameMode
                                                        ? "[Enter] Save   [Backspace] Up   [Esc] Close"
                                                            + "   [Type] Search   [Ctrl+Shift+N] New folder"
                                                        : root.multiple
                                                            ? "[Click] Select   [Enter] Open   [Backspace] Up"
                                                                + "   [Esc] Close   [Type] Search   [Ctrl+Shift+N] New folder"
                                                            : "[Arrows] Select   [Enter] Open   [Backspace] Up"
                                                                + "   [Esc] Close   [Type] Search   [Ctrl+Shift+N] New folder"
                        color: root.folderError !== "" || root.nameError !== ""
                            || root.pathError !== ""
                            || (root.searchActive && root.searchError !== "")
                            ? Colors.error : Colors.onSurfaceVariant
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelSmall
                        elide: Text.ElideRight
                    }

                    Row {
                        id: footerControls

                        anchors {
                            right: parent.right
                            rightMargin: 20
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.multiple
                                ? root.checkedCount + " selected"
                                : root.searchActive
                                    ? root.searchBusy
                                        ? "Searching…"
                                        : (root.searchTruncated
                                            ? root.fileCount + "+"
                                            : root.fileCount)
                                            + (root.fileCount === 1 ? " match" : " matches")
                                    : root.fileCount + (root.fileCount === 1 ? " file" : " files")
                            color: Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                        }

                        Pill {
                            id: cancelPill

                            icon: Icons.close
                            text: "Cancel"
                            horizontalPadding: 12

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cancel()
                            }
                        }

                        Pill {
                            id: acceptPill

                            icon: Icons.check
                            text: root.acceptLabel
                            horizontalPadding: 14
                            active: root.canAccept
                            opacity: root.canAccept ? 1 : 0.45

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.canAccept
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.accept()
                            }
                        }
                    }
                }
            }
        }
    }
}
