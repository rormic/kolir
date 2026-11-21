import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

// Clipboard history for the launcher. Lives at the launcher root Scope, not
// inside the PanelWindow, so the wl-paste watchers keep storing entries while
// the launcher is closed.
Scope {
    id: root

    property var items: []

    // ── Автоматичні фонові демони збереження буфера обміну ──
    // Окремо для тексту та зображень з переміщенням дублікатів нагору списку.
    // Обгортка cliphist-watch.sh зупиняє слухача, що лишився від попереднього
    // запуску Quickshell, інакше кожен рестарт додавав би ще одну пару.
    Process {
        id: clipDaemonText
        command: [ShellPaths.cliphistWatch, "text"]
        running: true
    }

    Process {
        id: clipDaemonImage
        command: [ShellPaths.cliphistWatch, "image"]
        running: true
    }

    // Процес оновлення списку буфера обміну
    Process {
        id: clipListProc
        command: ["cliphist", "list"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim()
                if (!raw) {
                    root.items = []
                    return
                }
                const lines = raw.split("\n")
                const items = []
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i]
                    if (!line) continue
                    const tabIdx = line.indexOf("\t")
                    if (tabIdx !== -1) {
                        const itemId = line.substring(0, tabIdx)
                        const preview = line.substring(tabIdx + 1)
                        // Розпізнаємо будь-які зображення (B, KiB, MiB тощо)
                        const isImage = preview.startsWith("[[ binary data") ||
                                        preview.startsWith("\uFFFDPNG") ||
                                        (preview.includes("PNG") && preview.includes("IHDR"))
                        let displayPreview = preview
                        let imageDims = ""
                        let imageInfo = ""
                        if (preview.startsWith("[[ binary data")) {
                            const m = preview.match(/^\[\[ binary data\s+(.+?)\s+([a-zA-Z]+)\s+(\d+x\d+)\s*\]\]$/)
                            if (m) {
                                imageDims = m[3].replace("x", " × ")
                                imageInfo = m[1] + " · " + m[2].toUpperCase()
                                displayPreview = imageDims + " (" + imageInfo + ")"
                            } else {
                                displayPreview = preview.replace(/^\[\[ binary data\s*/, "").replace(/\s*\]\]$/, "")
                                imageDims = displayPreview
                            }
                        }
                        items.push({
                            raw: line,
                            id: itemId,
                            preview: preview,
                            displayPreview: displayPreview,
                            imageDims: imageDims,
                            imageInfo: imageInfo,
                            isImage: isImage,
                            // Шлях до кешованого превью
                            imagePath: isImage ? (ShellPaths.clipboardPreviewDir + "/" + itemId + ".png") : ""
                        })
                    } else {
                        items.push({
                            raw: line,
                            id: "",
                            preview: line,
                            displayPreview: line,
                            isImage: false,
                            imagePath: ""
                        })
                    }
                }
                root.items = items
                // Генеруємо превью для всіх зображень в одну команду
                const imgItems = items.filter(it => it.isImage)
                if (imgItems.length > 0) {
                    imgPreviewProc.running = true
                }
            }
        }
    }

    // Процес генерації превью для зображень з буфера обміну
    Process {
        id: imgPreviewProc
        running: false
        command: [ShellPaths.cliphistPreviews, ShellPaths.clipboardPreviewDir]
        onRunningChanged: {
            // Після генерації превью — оновлюємо модель щоб Image перемалювалися
            if (!running) {
                const items = root.items
                root.items = []
                root.items = items
            }
        }
    }

    // Процес копіювання вибраного запису з cliphist
    Process {
        id: copyProc
        command: ["sh", "-c", "echo -n \"$1\" | cliphist decode | wl-copy", "_", ""]
        running: false
    }

    // Процес видалення запису з cliphist
    Process {
        id: deleteProc
        command: ["sh", "-c", "echo -n \"$1\" | cliphist delete", "_", ""]
        running: false
        onRunningChanged: {
            if (!running) clipListProc.running = true
        }
    }

    function refresh() {
        clipListProc.running = true;
    }

    function copyItem(item) {
        if (!item || !item.raw)
            return false;

        copyProc.command = ["sh", "-c", "echo -n \"$1\" | cliphist decode | wl-copy", "_", item.raw]
        copyProc.running = true;
        return true;
    }

    function deleteItem(item) {
        if (!item || !item.raw)
            return;

        deleteProc.command = ["sh", "-c", "echo -n \"$1\" | cliphist delete", "_", item.raw]
        deleteProc.running = true;
    }
}
