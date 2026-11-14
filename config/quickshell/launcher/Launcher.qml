import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../bar/components"
import "../theme"

Scope {
    id: root

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            win.visible = !win.visible
        }
        function openClipboard(): void {
            win.visible = true
            search.text = ";"
        }
        function openWith(query: string): void {
            win.visible = true
            search.text = query
        }
        function testSearch(query: string): void {
            const res = root.getFilteredApplications(query)
            console.log("TEST_SEARCH for " + query + ":")
            for (let i = 0; i < Math.min(res.length, 5); i++) {
                console.log("  " + (i + 1) + ". " + res[i].name + " (id: " + res[i].id + ")")
            }
        }
    }

    // ── Автоматичні фонові демони збереження буфера обміну ──
    // Окремо для тексту та зображень з переміщенням дублікатів нагору списку
    Process {
        id: clipDaemonText
        command: ["wl-paste", "--type", "text", "--watch", "/home/sakura/.local/share/kolir/config/quickshell/launcher/cliphist-store.py"]
        running: true
    }

    Process {
        id: clipDaemonImage
        command: ["wl-paste", "--type", "image", "--watch", "/home/sakura/.local/share/kolir/config/quickshell/launcher/cliphist-store.py"]
        running: true
    }

    // Список записів історії буфера обміну
    property var clipboardItems: []

    function getFilteredApplications(queryText) {
        const apps = DesktopEntries.applications.values
        if (!apps || apps.length === 0) return []

        const q = (queryText || "").trim().toLowerCase()

        // 1. Порожній запит: показуємо всі програми
        if (q === "") {
            return apps.slice()
        }

        // 2. Пошук за запитом
        const scored = []
        for (let i = 0; i < apps.length; i++) {
            const app = apps[i]
            const name = (app.name || "").toLowerCase()
            const id = (app.id || "").toLowerCase()
            const genericName = (app.genericName || "").toLowerCase()

            let matchScore = 0

            // Перевіряємо збіги за релевантністю
            if (name === q) {
                matchScore = 1000
            } else if (name.startsWith(q)) {
                matchScore = 500
            } else {
                const words = name.split(/[\s\-_]+/)
                let wordPrefixMatch = false
                for (let w = 0; w < words.length; w++) {
                    if (words[w].startsWith(q)) {
                        wordPrefixMatch = true
                        break
                    }
                }

                if (wordPrefixMatch) {
                    matchScore = 350
                } else if (name.includes(q)) {
                    matchScore = 150
                } else if (id.startsWith(q)) {
                    matchScore = 120
                } else if (id.includes(q)) {
                    matchScore = 70
                } else if (genericName.startsWith(q)) {
                    matchScore = 90
                } else if (genericName.includes(q)) {
                    matchScore = 50
                }
            }

            if (matchScore > 0) {
                scored.push({
                    app: app,
                    score: matchScore,
                    name: app.name || ""
                })
            }
        }

        // Сортуємо за найвищим балом; при рівності — за алфавітом
        scored.sort((a, b) => {
            if (b.score !== a.score) return b.score - a.score
            return a.name.localeCompare(b.name)
        })

        return scored.map(item => item.app)
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
                    root.clipboardItems = []
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
                            imagePath: isImage ? ("/tmp/qs-clip-previews/" + itemId + ".png") : ""
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
                root.clipboardItems = items
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
        command: ["/home/sakura/.local/share/kolir/config/quickshell/launcher/cliphist-previews.py"]
        onRunningChanged: {
            // Після генерації превью — оновлюємо модель щоб Image перемалювалися
            if (!running) {
                const items = root.clipboardItems
                root.clipboardItems = []
                root.clipboardItems = items
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

    // Процес для швидкого копіювання довільного тексту (наприклад, результату калькулятора)
    Process {
        id: directCopyProc
        command: ["wl-copy", ""]
        running: false
    }

    // ── Безпечна функція математичного калькулятора ──
    function evalMath(input) {
        if (!input) return null
        let s = input.trim()
        if (s.startsWith("=")) {
            s = s.substring(1).trim()
        }
        if (s === "") return null

        // Ігноруємо якщо це режим буфера обміну (починається з ;)
        if (s.startsWith(";")) return null

        // Має містити математичні оператори або починатися з =
        const hasOp = /[\+\-\*\/\%\^]/.test(s)
        if (!hasOp && !input.trim().startsWith("=")) return null

        // Дозволені тільки цифри, пробіли, крапка, оператори та дужки
        if (!/^[\d\s\+\-\*\/\%\^\(\)\.]+$/.test(s)) return null

        // Обов'язкова наявність хоча б однієї цифри
        if (!/\d/.test(s)) return null

        // Не обчислюємо незавершені вирази з оператором на кінці (наприклад, "2 +")
        if (/[\+\-\*\/\%\^]\s*$/.test(s)) return null

        try {
            let expr = s.replace(/\^/g, "**")
            const res = Function('"use strict"; return (' + expr + ')')()
            if (typeof res === "number" && !isNaN(res) && isFinite(res)) {
                let formatted = parseFloat(res.toPrecision(12)).toString()
                return {
                    expr: s,
                    result: formatted,
                    num: res
                }
            }
        } catch (e) {
            return null
        }
        return null
    }

    PanelWindow {
        id: win

        visible: false
        implicitWidth: 620
        implicitHeight: 500
        color: Colors.surfaceContainer

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "launcher"

        readonly property bool isClipboardMode: search.text.startsWith(";")
        readonly property string clipQuery: isClipboardMode ? search.text.substring(1).trim().toLowerCase() : ""
        readonly property var mathResult: !isClipboardMode ? root.evalMath(search.text) : null

        onVisibleChanged: if (visible) {
            search.text = ""
            list.currentIndex = 0
            clipListProc.running = true
            search.forceActiveFocus()
        }

        // ── Головне вікно у стилі Aseprite ──
        PixelBox {
            anchors.fill: parent
            style: "raised"
            bgColor: Colors.surfaceContainer

            Item {
                anchors.fill: parent

                // ══════════════════════════════════════════════════════
                // 1. Заголовок вікна (Title bar)
                // ══════════════════════════════════════════════════════
                Rectangle {
                    id: titleBar
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    height: 24
                    color: Colors.surfaceContainerHigh

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Colors.shadow
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 1
                        text: win.isClipboardMode ? "Clipboard History" : "Applications"
                        font.family: Typography.mainFont
                        font.pixelSize: 14
                        font.hintingPreference: Font.PreferFullHinting
                        renderType: Text.NativeRendering
                        color: win.isClipboardMode ? Colors.primary : Colors.onSurface
                    }

                    // Кнопка закриття [X]
                    PixelBox {
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        style: "raised"
                        pressed: closeMouse.pressed
                        bgColor: closeMouse.containsMouse ? Colors.errorContainer : Colors.surfaceContainerHigh

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 1
                            text: "x"
                            font.family: Typography.mainFont
                            font.pixelSize: 14
                            font.hintingPreference: Font.PreferFullHinting
                            renderType: Text.NativeRendering
                            color: closeMouse.containsMouse ? Colors.onErrorContainer : Colors.onSurface
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.visible = false
                        }
                    }
                }

                // ══════════════════════════════════════════════════════
                // 2. Підвал вікна (Status / Hints footer)
                // ══════════════════════════════════════════════════════
                Rectangle {
                    id: footer
                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }
                    height: 22
                    color: Colors.surfaceContainerHigh

                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width
                        height: 1
                        color: Colors.shadow
                    }

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 1
                            text: win.isClipboardMode
                                ? (list.count > 0 ? (list.currentIndex + 1) + " of " + list.count + " clips" : "0 clips")
                                : (list.count + " apps")
                            font.family: Typography.mainFont
                            font.pixelSize: 14
                            font.hintingPreference: Font.PreferFullHinting
                            renderType: Text.NativeRendering
                            color: Colors.outlineVariant
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 1
                            text: {
                                if (win.isClipboardMode) return "[Enter] Copy  [Del] Remove  [Esc] Close"
                                if (win.mathResult) return "[Enter] Copy Result  [Esc] Close"
                                return "[Enter] Run  [Esc] Close"
                            }
                            font.family: Typography.mainFont
                            font.pixelSize: 14
                            font.hintingPreference: Font.PreferFullHinting
                            renderType: Text.NativeRendering
                            color: Colors.outlineVariant
                        }
                    }
                }

                // ══════════════════════════════════════════════════════
                // 3. Заглиблене поле пошуку (Sunken input)
                // ══════════════════════════════════════════════════════
                PixelBox {
                    id: searchBox
                    anchors {
                        top: titleBar.bottom
                        topMargin: 6
                        left: parent.left
                        leftMargin: 6
                        right: parent.right
                        rightMargin: 6
                    }
                    height: 26
                    style: "sunken"
                    bgColor: Colors.surfaceContainerLow

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 1
                            text: ">"
                            color: Colors.primary
                            font.family: Typography.mainFont
                            font.pixelSize: 14
                            font.hintingPreference: Font.PreferFullHinting
                            renderType: Text.NativeRendering
                        }

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 18
                            height: parent.height

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: 1
                                visible: search.text === ""
                                text: win.isClipboardMode
                                    ? "Search clipboard history..."
                                    : "Search apps or type math (e.g. 2+2, 100/4)..."
                                font.family: Typography.mainFont
                                font.pixelSize: 14
                                font.hintingPreference: Font.PreferFullHinting
                                renderType: Text.NativeRendering
                                color: Colors.outlineVariant
                            }

                            TextInput {
                                id: search
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                color: Colors.onSurface
                                font.family: Typography.mainFont
                                font.pixelSize: 14
                                font.hintingPreference: Font.PreferFullHinting
                                renderType: Text.NativeRendering

                                Keys.onEscapePressed: win.visible = false
                                Keys.onDownPressed: list.incrementCurrentIndex()
                                Keys.onUpPressed: list.decrementCurrentIndex()

                                Keys.onDeletePressed: {
                                    if (win.isClipboardMode && list.currentItem && list.model && list.model.length > 0) {
                                        const item = list.model[list.currentIndex]
                                        if (item && item.raw) {
                                            deleteProc.command = ["sh", "-c", "echo -n \"$1\" | cliphist delete", "_", item.raw]
                                            deleteProc.running = true
                                        }
                                    }
                                }

                                Keys.onReturnPressed: {
                                    // 1. Пріоритет: Результат математичного калькулятора
                                    if (win.mathResult && list.currentIndex === -1) {
                                        directCopyProc.command = ["wl-copy", win.mathResult.result]
                                        directCopyProc.running = true
                                        Quickshell.clipboardText = win.mathResult.result
                                        win.visible = false
                                        return
                                    }

                                    // 2. Режим буфера обміну
                                    if (win.isClipboardMode) {
                                        if (list.currentItem && list.model && list.model.length > 0) {
                                            const item = list.model[list.currentIndex]
                                            if (item && item.raw) {
                                                copyProc.command = ["sh", "-c", "echo -n \"$1\" | cliphist decode | wl-copy", "_", item.raw]
                                                copyProc.running = true
                                                win.visible = false
                                            }
                                        }
                                        return
                                    }

                                    // 3. Якщо є результат калькулятора і нічого конкретного не вибрано, копіюємо його
                                    if (win.mathResult) {
                                        directCopyProc.command = ["wl-copy", win.mathResult.result]
                                        directCopyProc.running = true
                                        Quickshell.clipboardText = win.mathResult.result
                                        win.visible = false
                                        return
                                    }

                                    // 4. Запуск програми
                                    if (list.currentItem && list.model && list.model.length > 0) {
                                        list.model[list.currentIndex].execute()
                                        win.visible = false
                                    }
                                }

                                onTextChanged: {
                                    list.currentIndex = 0
                                    if (search.text.startsWith(";")) {
                                        clipListProc.running = true
                                    }
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════════════════════
                // 4. Картка результату калькулятора (Aseprite style)
                // ══════════════════════════════════════════════════════
                PixelBox {
                    id: calcBox
                    anchors {
                        top: searchBox.bottom
                        topMargin: 4
                        left: parent.left
                        leftMargin: 6
                        right: parent.right
                        rightMargin: 6
                    }
                    height: 28
                    visible: win.mathResult !== null
                    style: "sunken"
                    bgColor: Colors.surfaceContainerHighest

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 1
                            text: win.mathResult ? ("= " + win.mathResult.result) : ""
                            font.family: Typography.mainFont
                            font.pixelSize: 14
                            font.hintingPreference: Font.PreferFullHinting
                            renderType: Text.NativeRendering
                            color: Colors.primary
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 1
                            text: "[Enter] Copy"
                            font.family: Typography.mainFont
                            font.pixelSize: 14
                            font.hintingPreference: Font.PreferFullHinting
                            renderType: Text.NativeRendering
                            color: Colors.outlineVariant
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (win.mathResult) {
                                    directCopyProc.command = ["wl-copy", win.mathResult.result]
                                    directCopyProc.running = true
                                    Quickshell.clipboardText = win.mathResult.result
                                    win.visible = false
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════════════════════
                // 5. Заглиблена область зі списком (Програми / Буфер)
                // ══════════════════════════════════════════════════════
                PixelBox {
                    id: listBox
                    anchors {
                        top: calcBox.visible ? calcBox.bottom : searchBox.bottom
                        topMargin: 6
                        bottom: footer.top
                        bottomMargin: 6
                        left: parent.left
                        leftMargin: 6
                        right: parent.right
                        rightMargin: 6
                    }
                    style: "sunken"
                    bgColor: Colors.surfaceContainerLowest

                    ListView {
                        id: list
                        anchors.fill: parent
                        anchors.margins: 1
                        clip: true
                        currentIndex: 0
                        boundsBehavior: Flickable.StopAtBounds

                        // Модель динамічно перемикається між буфером обміну та програмами
                        model: {
                            if (win.isClipboardMode) {
                                if (win.clipQuery === "") {
                                    return root.clipboardItems
                                }
                                return root.clipboardItems.filter(item =>
                                    item.preview.toLowerCase().includes(win.clipQuery)
                                )
                            } else {
                                return root.getFilteredApplications(search.text)
                            }
                        }

                        delegate: Rectangle {
                            id: delegateRoot
                            required property var modelData
                            required property int index

                            width: list.width
                            height: (win.isClipboardMode && modelData.isImage) ? 120 : 28
                            color: ListView.isCurrentItem
                                ? Colors.primaryContainer
                                : (itemMouse.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                            // 1px рамка для вибраного пункту у стилі Aseprite
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.width: 1
                                border.color: ListView.isCurrentItem ? Colors.primary : "transparent"
                                visible: ListView.isCurrentItem
                            }

                            // ── Іконка (для програм) або нумерація 1., 2., 3... (для буфера обміну) ──
                            Item {
                                id: iconBox
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                width: win.isClipboardMode ? 28 : 16
                                height: 16

                                Image {
                                    anchors.fill: parent
                                    visible: !win.isClipboardMode
                                    sourceSize: Qt.size(16, 16)
                                    source: !win.isClipboardMode
                                        ? Quickshell.iconPath(modelData.icon, "application-x-executable")
                                        : ""
                                    smooth: false
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: 1
                                    visible: win.isClipboardMode
                                    text: (delegateRoot.index + 1) + "."
                                    font.family: Typography.mainFont
                                    font.pixelSize: 14
                                    font.hintingPreference: Font.PreferFullHinting
                                    renderType: Text.NativeRendering
                                    color: ListView.isCurrentItem ? Colors.onPrimaryContainer : Colors.primary
                                }
                            }

                            // ── Рамка та велике прев'ю зображення (у стилі Aseprite) ──
                            Rectangle {
                                id: imgFrame
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: iconBox.right
                                anchors.leftMargin: 8
                                width: 160
                                height: 104
                                visible: win.isClipboardMode && modelData.isImage
                                color: Colors.surfaceContainerLowest
                                border.width: 1
                                border.color: ListView.isCurrentItem ? Colors.primary : Colors.shadow

                                Image {
                                    id: clipImgPreview
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    cache: false
                                    source: (win.isClipboardMode && modelData.isImage && modelData.imagePath !== "")
                                        ? ("file://" + modelData.imagePath) : ""
                                }
                            }

                            // ── Текст / Інформація для зображень (роздільна здатність, розмір, тип) ──
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: imgFrame.right
                                anchors.leftMargin: 14
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                visible: win.isClipboardMode && modelData.isImage
                                spacing: 6

                                Text {
                                    width: parent.width
                                    text: modelData.imageDims || modelData.displayPreview || "Image"
                                    color: ListView.isCurrentItem ? Colors.onPrimaryContainer : Colors.onSurface
                                    font.family: Typography.mainFont
                                    font.pixelSize: 16
                                    font.hintingPreference: Font.PreferFullHinting
                                    renderType: Text.NativeRendering
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.imageInfo || ""
                                    color: ListView.isCurrentItem ? Colors.onPrimaryContainer : Colors.outlineVariant
                                    font.family: Typography.mainFont
                                    font.pixelSize: 13
                                    font.hintingPreference: Font.PreferFullHinting
                                    renderType: Text.NativeRendering
                                    visible: text !== ""
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: "[Enter] Copy Image"
                                    color: ListView.isCurrentItem ? Colors.onPrimaryContainer : Colors.outlineVariant
                                    font.family: Typography.mainFont
                                    font.pixelSize: 12
                                    font.hintingPreference: Font.PreferFullHinting
                                    renderType: Text.NativeRendering
                                    visible: ListView.isCurrentItem
                                    elide: Text.ElideRight
                                }
                            }

                            // ── Звичайний текст (для текстових записів буфера або програм) ──
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: 1
                                anchors.left: iconBox.right
                                anchors.leftMargin: 8
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                visible: !win.isClipboardMode || !modelData.isImage
                                text: win.isClipboardMode
                                    ? (modelData.displayPreview || modelData.preview)
                                    : modelData.name
                                color: ListView.isCurrentItem
                                    ? Colors.onPrimaryContainer
                                    : Colors.onSurface
                                font.family: Typography.mainFont
                                font.pixelSize: 14
                                font.hintingPreference: Font.PreferFullHinting
                                renderType: Text.NativeRendering
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    list.currentIndex = delegateRoot.index
                                    if (win.isClipboardMode) {
                                        if (modelData && modelData.raw) {
                                            copyProc.command = ["sh", "-c", "echo -n \"$1\" | cliphist decode | wl-copy", "_", modelData.raw]
                                            copyProc.running = true
                                            win.visible = false
                                        }
                                    } else {
                                        modelData.execute()
                                        win.visible = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
