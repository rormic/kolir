import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import "../bar/components"
import "../services"
import "../theme"
import "SearchLogic.js" as SearchLogic

Scope {
    id: root

    // Keyboard layouts the launcher translates queries between. The helper
    // reads every configured layout from libxkbcommon (see
    // scripts/layout-map.py), so search works for any language instead of a
    // table per layout. Until the helper answers the list is empty and search
    // stays literal.
    property var layoutMap: []

    function reloadLayoutMap() {
        layoutMapProc.running = true
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            win.visible = !win.visible
        }
        function close(): void {
            win.visible = false
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
            const res = SearchLogic.filterApplications(
                DesktopEntries.applications.values, query, root.layoutMap)
            console.log("TEST_SEARCH for " + query + ":")
            for (let i = 0; i < Math.min(res.length, 5); i++) {
                console.log("  " + (i + 1) + ". " + res[i].name + " (id: " + res[i].id + ")")
            }
        }
    }

    ClipboardController {
        id: clipboard
    }

    // Layout pairs handed to SearchLogic. One short-lived process per shell
    // start (and per Hyprland config reload) builds them; a failing helper only
    // leaves `layoutMap` empty, so search keeps working literally.
    Process {
        id: layoutMapProc
        command: ["python3", ShellPaths.layoutMapScript]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim()
                if (!raw) return
                try {
                    const parsed = JSON.parse(raw)
                    root.layoutMap = parsed && parsed.layouts ? parsed.layouts : []
                } catch (e) {
                    console.warn("launcher: unexpected layout-map output")
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("launcher: layout-map helper exited with " + exitCode)
        }
    }

    // Switching keyboard layouts is a compositor config change, so re-read the
    // map on reload instead of waiting for the next shell restart.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event && event.name === "configreloaded")
                root.reloadLayoutMap()
        }
    }

    // Процес для швидкого копіювання довільного тексту (наприклад, результату калькулятора)
    Process {
        id: directCopyProc
        command: ["wl-copy", ""]
        running: false
    }

    PanelWindow {
        id: win

        readonly property int compactHeight: 40
        readonly property int expandedHeight: 520
        readonly property int calcCardHeight: 44
        readonly property int noteCardHeight: 58

        // Відступи всередині панелі: зверху під рядком пошуку і знизу під списком
        readonly property int contentGap: 10
        readonly property int contentBottom: 14
        readonly property int emptyListHeight: 140
        readonly property int appRowHeight: 40
        readonly property int imageRowHeight: 124

        // Порожній запит — показуємо лише рядок пошуку
        property bool searching: false

        // Висота списку за кількістю знайдених елементів (з обмеженням, далі скрол)
        readonly property int maxListHeight: expandedHeight - compactHeight - contentGap - contentBottom
        readonly property int listHeight: {
            const items = list.model
            if (!items || items.length === 0) return 0
            let total = 8 // відступи ListView зверху/знизу
            for (let i = 0; i < items.length; i++)
                total += win.rowHeightFor(items[i])
            total += Math.max(0, items.length - 1) * list.spacing
            return Math.min(total, maxListHeight)
        }

        // Калькулятор не потребує списку — тримаємо панель компактною
        readonly property int targetHeight: !searching
            ? compactHeight
            : (isNoteMode
                ? compactHeight + contentGap + noteCardHeight + contentBottom
                : (mathResult !== null
                    ? compactHeight + contentGap + calcCardHeight + contentBottom
                    : compactHeight + contentGap
                        + Math.max(listHeight, emptyListHeight) + contentBottom))

        function rowHeightFor(item) {
            return (isClipboardMode && item && item.isImage) ? imageRowHeight : appRowHeight
        }

        // Rich-text markup is avoided here: the idle hint renders the two
        // prefix keys as small keycaps, so the characters people have to type
        // read as keys instead of punctuation in a sentence. The shortcut
        // sheet's KeyChip is 24px and belongs to another feature, so this
        // lighter 20px variant stays local to the launcher.
        component SearchHintKey: Rectangle {
            id: hintKey

            property string keyLabel: ""

            implicitWidth: 22
            implicitHeight: 20
            radius: Dimensions.radius.small
            color: Colors.withAlpha(Colors.primary, 0.12)
            border.width: 1
            border.color: Colors.withAlpha(Colors.primary, 0.38)

            Text {
                anchors.centerIn: parent
                text: hintKey.keyLabel
                color: Colors.primary
                font.family: Typography.barFont
                font.pixelSize: 16
                font.weight: Typography.weight.bold
            }
        }

        component SearchHint: Row {
            id: hint

            property string keyLabel: ""
            property string hintLabel: ""

            spacing: 5

            SearchHintKey {
                keyLabel: hint.keyLabel
            }

            Text {
                height: 20
                verticalAlignment: Text.AlignVCenter
                text: hint.hintLabel
                color: Colors.onSurfaceVariant
                opacity: 0.78
                font.family: Typography.barFont
                font.pixelSize: Typography.size.labelMedium
            }
        }

        // A workspace switch dismisses the launcher. Keeping it open would
        // leave the new workspace without a focused window while the layer
        // holds exclusive keyboard focus, so its windows would animate with
        // inactive opacity.
        Connections {
            target: Hyprland
            function onFocusedWorkspaceChanged() {
                if (win.visible)
                    win.visible = false
            }
        }

        // Поверхня завжди повноекранна: картка анімується всередині неї, а
        // прозора решта площі ловить клік повз картку (див. MouseArea нижче).
        // Маленьке вікно розміром із картку не отримувало таких кліків взагалі,
        // бо вони йшли повз його поверхню.
        visible: false
        implicitWidth: screen ? screen.width : 0
        implicitHeight: screen ? screen.height : 0
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Ignore, not a normal exclusive zone: the dismissal layer has to cover
        // the bar strip too, so a click there closes the launcher instead of
        // leaving it open behind the bar.
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "launcher"

        // Вертикальне положення картки в межах усієї поверхні: смугу бару
        // віднімаємо тут, бо поверхня тепер покриває і її.
        readonly property int cardTop: Dimensions.bar.height
            + Math.max(8, Math.min(
                (height - Dimensions.bar.height - Dimensions.bar.margin - compactHeight) / 2,
                height - Dimensions.bar.height - Dimensions.bar.margin - expandedHeight - 8))

        // Картка трохи вужча за поверхню на малих екранах.
        readonly property int cardWidth: Math.min(620, width - 16)

        readonly property bool isClipboardMode: search.text.startsWith(";")
        readonly property bool isNoteMode: search.text.startsWith(".")
        readonly property string noteText: isNoteMode ? search.text.substring(1).trim() : ""
        readonly property string clipQuery: isClipboardMode ? search.text.substring(1).trim().toLowerCase() : ""
        readonly property var mathResult: (!isClipboardMode && !isNoteMode) ? SearchLogic.evalMath(search.text) : null

        // ── Швидка задача в щоденну нотатку Obsidian ──
        // Хелпер сам знаходить vault, формат і теку щоденних нотаток, тож QML
        // не будує жодних шляхів. Результат завжди один JSON-об'єкт.
        property var noteTarget: null
        property string noteError: ""
        property bool noteBusy: false

        function refreshNoteTarget() {
            noteTarget = null
            noteError = ""
            noteTargetProc.command = [ShellPaths.quickNoteScript, "target"]
            noteTargetProc.running = true
        }

        function submitNote() {
            if (!isNoteMode || noteBusy || noteText === "") return
            noteError = ""
            noteBusy = true
            noteAddProc.command = [ShellPaths.quickNoteScript, "add", noteText]
            noteAddProc.running = true
        }

        function handleNoteResult(result) {
            noteBusy = false
            if (result && result.ok) {
                noteTarget = result
                win.visible = false
            } else {
                noteError = (result && result.error) ? result.error : "Could not save the note"
            }
        }

        function failNote(message) {
            noteBusy = false
            noteError = message
        }

        function noteStatusText() {
            if (noteError !== "") return noteError
            if (noteBusy) return "Saving…"
            if (!noteTarget) return "Looking up the Obsidian vault…"
            if (!noteTarget.ok) return noteTarget.error || "Obsidian vault not found"
            const kind = noteTarget.exists ? "Daily note" : "New daily note"
            return kind + " · " + noteTarget.note
        }

        Process {
            id: noteTargetProc
            running: false
            stdout: StdioCollector {
                onStreamFinished: {
                    const raw = text.trim()
                    if (!raw) return
                    try {
                        win.noteTarget = JSON.parse(raw)
                    } catch (e) {
                        win.noteTarget = { ok: false, error: "Unexpected quick-note output" }
                    }
                }
            }
            onExited: (exitCode, exitStatus) => {
                if (exitCode !== 0 && !win.noteTarget)
                    win.noteTarget = { ok: false, error: "Quick-note helper failed" }
            }
        }

        Process {
            id: noteAddProc
            running: false
            stdout: StdioCollector {
                onStreamFinished: {
                    const raw = text.trim()
                    if (!raw) return
                    try {
                        win.handleNoteResult(JSON.parse(raw))
                    } catch (e) {
                        win.failNote("Unexpected quick-note output")
                    }
                }
            }
            onExited: (exitCode, exitStatus) => {
                // Немає придатної відповіді (хелпер упав) — лишаємо поле відкритим.
                if (win.noteBusy)
                    win.failNote("Could not save the note")
            }
        }

        onVisibleChanged: {
            if (visible) {
                search.text = ""
                searching = false
                list.currentIndex = 0
                noteTarget = null
                noteError = ""
                noteBusy = false
                clipboard.refresh()
                search.forceActiveFocus()
            } else {
                // Згортаємо одразу, поки вікно приховане — без видимого стрибка
                searching = false
                noteTargetProc.running = false
                noteAddProc.running = false
            }
        }

        // Клік повз картку закриває лаунчер
        MouseArea {
            anchors.fill: parent
            onClicked: win.visible = false
        }

        // ── Головна картка у стилі налаштувань ──
        Surface {
            id: card
            anchors {
                top: parent.top
                topMargin: win.cardTop
                horizontalCenter: parent.horizontalCenter
            }
            width: win.cardWidth
            height: win.targetHeight
            radius: Dimensions.radius.largeIncreased
            // Напівпрозора панель, як вікна Hyprland: крізь неї видно шпалери
            // та вміст вікон, а композитор додає blur (layer_rule "launcher-blur")
            surfaceColor: Colors.withAlpha(Colors.surfaceContainerHigh, 0.8)
            borderWidth: 2
            borderColor: Colors.primary

            opacity: win.visible ? 1 : 0
            scale: win.visible ? 1 : 0.97
            transformOrigin: Item.Top

            Behavior on height {
                enabled: win.visible
                NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            // Поглинаємо кліки всередині картки, щоб вони не закривали лаунчер
            MouseArea {
                anchors.fill: parent
            }

            Item {
                id: content
                anchors.fill: parent

                Item {
                    id: body
                    anchors.fill: parent

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
                        height: win.compactHeight
                        radius: Dimensions.radius.largeIncreased
                        color: "transparent"
                        border.width: 0

                        Text {
                            id: searchIcon
                            anchors {
                                left: parent.left
                                leftMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            text: win.isNoteMode
                                ? Icons.addTask
                                : win.isClipboardMode
                                    ? Icons.contentPaste
                                    : (win.mathResult !== null ? Icons.calculate : Icons.search)
                            color: search.activeFocus || win.isNoteMode
                                ? Colors.primary
                                : Colors.onSurfaceVariant
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
                                right: idleHints.left
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            visible: search.text === ""
                            text: win.isClipboardMode
                                ? "Search clipboard history…"
                                : "Search apps or type math (e.g. 2+2)"
                            color: Colors.onSurfaceVariant
                            opacity: 0.78
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.bodyMedium
                            elide: Text.ElideRight
                        }

                        // Idle affordance: the two launcher prefixes as keys,
                        // with the mode name next to each, so it is obvious
                        // that "." starts a note instead of hiding at the end
                        // of the placeholder sentence. Hidden as soon as the
                        // user types, so it never competes with the query.
                        Row {
                            id: idleHints

                            anchors {
                                right: parent.right
                                rightMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 12
                            visible: search.text === ""

                            SearchHint {
                                keyLabel: "."
                                hintLabel: "note"
                            }

                            SearchHint {
                                keyLabel: ";"
                                hintLabel: "clipboard"
                            }
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
                            font.family: Typography.launcherFont
                            font.pixelSize: Typography.size.bodyLarge
                            font.weight: Typography.weight.semibold
                            clip: true

                            HoverHandler {
                                cursorShape: Qt.IBeamCursor
                            }

                            Keys.onEscapePressed: win.visible = false
                            Keys.onDownPressed: list.incrementCurrentIndex()
                            Keys.onUpPressed: list.decrementCurrentIndex()

                            Keys.onDeletePressed: {
                                if (win.isClipboardMode && list.currentItem && list.model && list.model.length > 0) {
                                    const item = list.model[list.currentIndex]
                                    clipboard.deleteItem(item)
                                }
                            }

                            Keys.onReturnPressed: {
                                // 0. Швидка задача в щоденну нотатку Obsidian
                                if (win.isNoteMode) {
                                    win.submitNote()
                                    return
                                }

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
                                        if (clipboard.copyItem(item))
                                            win.visible = false
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
                                win.searching = search.text.trim() !== ""
                                list.currentIndex = 0
                                if (win.noteError !== "")
                                    win.noteError = ""
                                // Check the text directly: win.isNoteMode is a
                                // binding that may still be stale inside this
                                // signal handler.
                                const typed = search.text
                                if (typed.startsWith(".")) {
                                    if (win.noteTarget === null && !noteTargetProc.running)
                                        win.refreshNoteTarget()
                                } else if (typed.startsWith(";")) {
                                    clipboard.refresh()
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
                            topMargin: win.contentGap
                            left: parent.left
                            leftMargin: 14
                            right: parent.right
                            rightMargin: 14
                        }
                        height: win.calcCardHeight
                        visible: win.mathResult !== null
                        radius: Dimensions.radius.medium
                        color: calcMouse.containsMouse
                            ? Colors.stateLayer(Colors.primary, 0.12)
                            : "transparent"
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
                                font.family: Typography.launcherFont
                                font.pixelSize: Typography.size.titleSmall
                                font.weight: Typography.weight.semibold
                            }
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
                    // 3b. Швидка задача в щоденну нотатку Obsidian (префікс ".")
                    // ══════════════════════════════════════════════════════
                    Rectangle {
                        id: noteCard
                        anchors {
                            top: searchField.bottom
                            topMargin: win.contentGap
                            left: parent.left
                            leftMargin: 14
                            right: parent.right
                            rightMargin: 14
                        }
                        height: win.noteCardHeight
                        visible: win.isNoteMode
                        radius: Dimensions.radius.medium
                        color: noteMouse.containsMouse || win.noteBusy
                            ? Colors.stateLayer(Colors.primary, 0.12)
                            : "transparent"
                        border.width: 1
                        border.color: win.noteError !== ""
                            ? Colors.withAlpha(Colors.error, 0.60)
                            : noteMouse.containsMouse
                                ? Colors.withAlpha(Colors.primary, 0.45)
                                : Colors.withAlpha(Colors.outlineVariant, 0.22)

                        Behavior on color {
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on border.color {
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

                        Text {
                            id: noteIcon
                            anchors {
                                left: parent.left
                                leftMargin: 14
                                top: parent.top
                                topMargin: 13
                            }
                            text: win.noteError !== "" ? Icons.warning : Icons.addTask
                            color: win.noteError !== "" ? Colors.error : Colors.primary
                            font.family: Typography.iconFont
                            font.pixelSize: 18
                        }

                        Column {
                            anchors {
                                left: noteIcon.right
                                leftMargin: 10
                                right: noteEnter.left
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 3

                            Text {
                                width: parent.width
                                text: win.noteText !== "" ? win.noteText : "Type a task…"
                                color: win.noteText !== "" ? Colors.onSurface : Colors.onSurfaceVariant
                                opacity: win.noteText !== "" ? 1 : 0.78
                                font.family: win.noteText !== "" ? Typography.launcherFont : Typography.barFont
                                font.pixelSize: Typography.size.bodyMedium
                                font.weight: win.noteText !== ""
                                    ? Typography.weight.semibold
                                    : Typography.weight.regular
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: win.noteStatusText()
                                color: win.noteError !== "" ? Colors.error : Colors.onSurfaceVariant
                                opacity: 0.8
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                elide: Text.ElideMiddle
                            }
                        }

                        Text {
                            id: noteEnter
                            anchors {
                                right: parent.right
                                rightMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            visible: win.noteText !== "" && !win.noteBusy
                            text: Icons.keyboardReturn
                            color: Colors.primary
                            font.family: Typography.iconFont
                            font.pixelSize: 16
                        }

                        MouseArea {
                            id: noteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: win.submitNote()
                        }
                    }

                    // ══════════════════════════════════════════════════════
                    // 4. Список програм / буфера обміну
                    // ══════════════════════════════════════════════════════
                    Rectangle {
                        id: listCard
                        anchors {
                            top: calcCard.visible ? calcCard.bottom : searchField.bottom
                            topMargin: win.contentGap
                            left: parent.left
                            leftMargin: 14
                            right: parent.right
                            rightMargin: 14
                        }
                        height: Math.max(win.listHeight, win.emptyListHeight)
                        color: "transparent"
                        border.width: 0
                        clip: true
                        visible: win.mathResult === null && !win.isNoteMode

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
                                if (win.isNoteMode) return []
                                if (win.isClipboardMode) {
                                    if (win.clipQuery === "") {
                                        return clipboard.items
                                    }
                                    return clipboard.items.filter(item =>
                                        SearchLogic.matchesText(item.preview, win.clipQuery, root.layoutMap)
                                    )
                                } else {
                                    if (search.text.trim() === "") return []
                                    return SearchLogic.filterApplications(
                                        DesktopEntries.applications.values, search.text, root.layoutMap)
                                }
                            }

                            delegate: LauncherResultRow {
                                id: resultRow
                                required property var modelData
                                required property int index

                                width: list.width
                                item: resultRow.modelData
                                itemIndex: resultRow.index
                                selected: ListView.isCurrentItem
                                clipboardMode: win.isClipboardMode
                                isImageClip: win.isClipboardMode && resultRow.modelData.isImage
                                rowHeight: resultRow.isImageClip ? win.imageRowHeight : win.appRowHeight
                                onActivated: {
                                    list.currentIndex = resultRow.index
                                    if (win.isClipboardMode) {
                                        if (clipboard.copyItem(resultRow.modelData))
                                            win.visible = false
                                    } else {
                                        resultRow.modelData.execute()
                                        win.visible = false
                                    }
                                }
                            }
                        }

                        // Порожній стан
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            visible: list.count === 0 && win.searching

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

                }
            }
        }
    }
}
