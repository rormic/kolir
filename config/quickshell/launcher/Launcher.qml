import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../bar/components"
import "../theme"

Scope {
    id: root

    // Компактна підказка клавіші у стилі налаштувань.
    component KeyHint: Row {
        id: keyHint

        property string key: ""
        property string label: ""

        height: 18
        spacing: 5

        Rectangle {
            width: keyLabel.implicitWidth + 10
            height: 18
            radius: Dimensions.radius.extraSmall + 2
            color: Colors.surfaceContainerHigh
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

            Text {
                id: keyLabel
                anchors.centerIn: parent
                text: keyHint.key
                color: Colors.onSurfaceVariant
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelSmall
                font.weight: Typography.weight.medium
            }
        }

        Text {
            height: 18
            verticalAlignment: Text.AlignVCenter
            text: keyHint.label
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
        }
    }

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
        implicitHeight: 520
        color: "transparent"

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

        // ── Головна картка у стилі налаштувань ──
        Surface {
            id: card
            anchors.fill: parent
            radius: Dimensions.radius.extraLarge
            surfaceColor: Colors.withAlpha(Colors.surfaceContainerLow, 0.98)
            borderWidth: 2
            borderColor: Colors.primary

            opacity: win.visible ? 1 : 0
            scale: win.visible ? 1 : 0.97
            transformOrigin: Item.Center

            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Item {
                id: content
                anchors.fill: parent

                Item {
                    id: body
                    anchors {
                        fill: parent
                        margins: 14
                    }

                    // ══════════════════════════════════════════════════════
                    // 2. Рядок пошуку
                    // ══════════════════════════════════════════════════════
                    Rectangle {
                        id: searchField
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        height: 40
                        radius: Dimensions.radius.full
                        color: Colors.surfaceContainerHigh
                        border.width: 1
                        border.color: search.activeFocus
                            ? Colors.withAlpha(Colors.primary, 0.55)
                            : Colors.withAlpha(Colors.outlineVariant, 0.22)

                        Behavior on border.color {
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

                        Text {
                            id: searchIcon
                            anchors {
                                left: parent.left
                                leftMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            text: win.isClipboardMode
                                ? Icons.contentPaste
                                : (win.mathResult !== null ? Icons.calculate : Icons.search)
                            color: search.activeFocus ? Colors.primary : Colors.onSurfaceVariant
                            font.family: Typography.iconFont
                            font.pixelSize: 18
                            font.weight: Font.Normal

                            Behavior on color {
                                ColorAnimation { duration: 140 }
                            }
                        }

                        Text {
                            id: placeholder
                            anchors {
                                left: searchIcon.right
                                leftMargin: 10
                                right: parent.right
                                rightMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            visible: search.text === ""
                            text: win.isClipboardMode
                                ? "Search clipboard history…"
                                : "Search apps or type math (e.g. 2+2)…"
                            color: Colors.onSurfaceVariant
                            opacity: 0.78
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.bodyMedium
                            elide: Text.ElideRight
                        }

                        TextInput {
                            id: search
                            anchors {
                                left: searchIcon.right
                                leftMargin: 10
                                right: parent.right
                                rightMargin: 14
                                top: parent.top
                                bottom: parent.bottom
                            }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.onSurface
                            selectionColor: Colors.withAlpha(Colors.primary, 0.35)
                            selectedTextColor: Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.bodyLarge
                            font.weight: Typography.weight.regular
                            clip: true

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

                    // ══════════════════════════════════════════════════════
                    // 3. Результат калькулятора
                    // ══════════════════════════════════════════════════════
                    Rectangle {
                        id: calcCard
                        anchors {
                            top: searchField.bottom
                            topMargin: 10
                            left: parent.left
                            right: parent.right
                        }
                        height: 44
                        visible: win.mathResult !== null
                        radius: Dimensions.radius.medium
                        color: calcMouse.containsMouse
                            ? Colors.stateLayer(Colors.primary, 0.12)
                            : Colors.surfaceContainerHigh
                        border.width: 1
                        border.color: calcMouse.containsMouse
                            ? Colors.withAlpha(Colors.primary, 0.45)
                            : Colors.withAlpha(Colors.outlineVariant, 0.22)

                        Behavior on color {
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on border.color {
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

                        Row {
                            anchors {
                                left: parent.left
                                leftMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Icons.calculate
                                color: Colors.primary
                                font.family: Typography.iconFont
                                font.pixelSize: 18
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: win.mathResult ? ("= " + win.mathResult.result) : ""
                                color: Colors.primary
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.titleSmall
                                font.weight: Typography.weight.bold
                            }
                        }

                        KeyHint {
                            anchors {
                                right: parent.right
                                rightMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            key: "Enter"
                            label: "Copy"
                        }

                        MouseArea {
                            id: calcMouse
                            anchors.fill: parent
                            hoverEnabled: true
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

                    // ══════════════════════════════════════════════════════
                    // 4. Список програм / буфера обміну
                    // ══════════════════════════════════════════════════════
                    Rectangle {
                        id: listCard
                        anchors {
                            top: calcCard.visible ? calcCard.bottom : searchField.bottom
                            topMargin: 10
                            bottom: footer.top
                            bottomMargin: 8
                            left: parent.left
                            right: parent.right
                        }
                        radius: Dimensions.radius.medium
                        color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.5)
                        border.width: 1
                        border.color: Colors.withAlpha(Colors.outlineVariant, 0.14)
                        clip: true

                        ListView {
                            id: list
                            anchors.fill: parent
                            anchors.margins: 4
                            clip: true
                            currentIndex: 0
                            boundsBehavior: Flickable.StopAtBounds
                            spacing: 2

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

                            delegate: Item {
                                id: delegateRoot
                                required property var modelData
                                required property int index

                                readonly property bool isSelected: ListView.isCurrentItem
                                readonly property bool isImageClip: win.isClipboardMode && modelData.isImage

                                width: list.width
                                height: delegateRoot.isImageClip ? 124 : 40

                                Rectangle {
                                    id: rowBackground
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: Dimensions.radius.medium
                                    color: delegateRoot.isSelected
                                        ? Colors.stateLayer(Colors.primary, 0.16)
                                        : itemMouse.containsMouse
                                            ? Colors.stateLayer(Colors.onSurface, 0.06)
                                            : "transparent"
                                    border.width: delegateRoot.isSelected ? 1 : 0
                                    border.color: Colors.withAlpha(Colors.primary, 0.35)

                                    Behavior on color {
                                        ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on border.color {
                                        ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                                    }
                                }

                                // Акцент вибраного рядка
                                Rectangle {
                                    anchors {
                                        left: parent.left
                                        leftMargin: 6
                                        verticalCenter: parent.verticalCenter
                                    }
                                    width: 2
                                    height: 18
                                    radius: 1
                                    visible: delegateRoot.isSelected
                                    color: Colors.primary
                                }

                                Item {
                                    id: leading
                                    anchors {
                                        left: parent.left
                                        leftMargin: 14
                                        verticalCenter: parent.verticalCenter
                                    }
                                    width: 22
                                    height: 22

                                    Image {
                                        anchors.fill: parent
                                        visible: !win.isClipboardMode
                                        sourceSize: Qt.size(20, 20)
                                        source: !win.isClipboardMode
                                            ? Quickshell.iconPath(modelData.icon, "application-x-executable")
                                            : ""
                                        smooth: true
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        visible: win.isClipboardMode
                                        radius: Dimensions.radius.small
                                        color: delegateRoot.isSelected
                                            ? Colors.primaryContainer
                                            : Colors.surfaceContainerHigh
                                        border.width: delegateRoot.isSelected ? 0 : 1
                                        border.color: Colors.withAlpha(Colors.outlineVariant, 0.18)

                                        Text {
                                            anchors.centerIn: parent
                                            text: delegateRoot.index + 1
                                            color: delegateRoot.isSelected
                                                ? Colors.onPrimaryContainer
                                                : Colors.primary
                                            font.family: Typography.barFont
                                            font.pixelSize: Typography.size.labelSmall
                                            font.weight: Typography.weight.bold
                                        }
                                    }
                                }

                                // Прев'ю зображення з буфера обміну
                                Rectangle {
                                    id: imageFrame
                                    anchors {
                                        left: leading.right
                                        leftMargin: 10
                                        verticalCenter: parent.verticalCenter
                                    }
                                    width: 152
                                    height: 100
                                    radius: Dimensions.radius.medium
                                    visible: delegateRoot.isImageClip
                                    color: Colors.surfaceContainerLow
                                    border.width: 1
                                    border.color: delegateRoot.isSelected
                                        ? Colors.withAlpha(Colors.primary, 0.35)
                                        : Colors.withAlpha(Colors.outlineVariant, 0.30)
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        cache: false
                                        source: (delegateRoot.isImageClip && modelData.imagePath !== "")
                                            ? ("file://" + modelData.imagePath) : ""
                                    }
                                }

                                // Метадані зображення
                                Column {
                                    anchors {
                                        left: imageFrame.right
                                        leftMargin: 14
                                        right: parent.right
                                        rightMargin: 14
                                        verticalCenter: parent.verticalCenter
                                    }
                                    visible: delegateRoot.isImageClip
                                    spacing: 4

                                    Text {
                                        width: parent.width
                                        text: modelData.imageDims || modelData.displayPreview || "Image"
                                        color: Colors.onSurface
                                        font.family: Typography.barFont
                                        font.pixelSize: Typography.size.titleSmall
                                        font.weight: delegateRoot.isSelected ? Typography.weight.bold : Typography.weight.medium
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        visible: text !== ""
                                        text: modelData.imageInfo || ""
                                        color: Colors.onSurfaceVariant
                                        font.family: Typography.barFont
                                        font.pixelSize: Typography.size.labelSmall
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        visible: delegateRoot.isSelected
                                        text: "Enter to copy"
                                        color: Colors.primary
                                        font.family: Typography.barFont
                                        font.pixelSize: Typography.size.labelSmall
                                        elide: Text.ElideRight
                                    }
                                }

                                // Назва програми або текст із буфера
                                Text {
                                    anchors {
                                        left: leading.right
                                        leftMargin: 10
                                        right: enterHint.visible ? enterHint.left : parent.right
                                        rightMargin: enterHint.visible ? 8 : 14
                                        verticalCenter: parent.verticalCenter
                                    }
                                    visible: !delegateRoot.isImageClip
                                    text: win.isClipboardMode
                                        ? (modelData.displayPreview || modelData.preview)
                                        : modelData.name
                                    color: Colors.onSurface
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.bodyMedium
                                    font.weight: delegateRoot.isSelected ? Typography.weight.bold : Typography.weight.medium
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: enterHint
                                    anchors {
                                        right: parent.right
                                        rightMargin: 14
                                        verticalCenter: parent.verticalCenter
                                    }
                                    visible: delegateRoot.isSelected && !delegateRoot.isImageClip
                                    text: Icons.keyboardReturn
                                    color: Colors.primary
                                    font.family: Typography.iconFont
                                    font.pixelSize: 16
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

                        // Порожній стан
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            visible: list.count === 0

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: win.isClipboardMode ? Icons.contentPaste : Icons.searchOff
                                color: Colors.withAlpha(Colors.onSurfaceVariant, 0.55)
                                font.family: Typography.iconFont
                                font.pixelSize: 28
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: win.isClipboardMode ? "Clipboard is empty" : "No apps found"
                                color: Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                            }
                        }
                    }

                    // ══════════════════════════════════════════════════════
                    // 5. Футер
                    // ══════════════════════════════════════════════════════
                    Item {
                        id: footer
                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                            right: parent.right
                        }
                        height: 34

                        Rectangle {
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                            }
                            height: 1
                            color: Colors.withAlpha(Colors.outlineVariant, 0.25)
                        }

                        Row {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 6

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5
                                height: 5
                                radius: 2.5
                                color: Colors.primary
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (win.isClipboardMode) {
                                        if (list.count === 0) return "0 clips"
                                        return (list.currentIndex + 1) + " of " + list.count + " clips"
                                    }
                                    return list.count + (list.count === 1 ? " app" : " apps")
                                }
                                color: Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                font.weight: Typography.weight.medium
                            }
                        }

                        Row {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 12

                            KeyHint {
                                key: "Enter"
                                label: win.isClipboardMode
                                    ? "Copy"
                                    : (win.mathResult ? "Copy result" : "Run")
                            }
                            KeyHint {
                                visible: win.isClipboardMode
                                key: "Del"
                                label: "Delete"
                            }
                            KeyHint {
                                visible: !win.isClipboardMode && !win.mathResult
                                key: ";"
                                label: "Clips"
                            }
                            KeyHint {
                                key: "Esc"
                                label: "Close"
                            }
                        }
                    }
                }
            }
        }
    }
}
