import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../bar/components"
import "../theme"
import "SearchLogic.js" as SearchLogic

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
            const res = SearchLogic.filterApplications(DesktopEntries.applications.values, query)
            console.log("TEST_SEARCH for " + query + ":")
            for (let i = 0; i < Math.min(res.length, 5); i++) {
                console.log("  " + (i + 1) + ". " + res[i].name + " (id: " + res[i].id + ")")
            }
        }
    }

    ClipboardController {
        id: clipboard
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
            : (mathResult !== null
                ? compactHeight + contentGap + calcCardHeight + contentBottom
                : compactHeight + contentGap
                    + Math.max(listHeight, emptyListHeight) + contentBottom)

        function rowHeightFor(item) {
            return (isClipboardMode && item && item.isImage) ? imageRowHeight : appRowHeight
        }

        visible: false
        implicitWidth: 620
        // Вікно завжди розгорнутого розміру: анімуємо картку, а не Wayland-поверхню,
        // інакше композитор масштабує старий буфер і анімація виглядає рваною.
        implicitHeight: expandedHeight
        color: "transparent"

        anchors.top: true
        margins.top: win.screen
            ? Math.max(8, Math.min(
                (win.screen.height - Dimensions.bar.height - Dimensions.bar.margin - compactHeight) / 2,
                win.screen.height - Dimensions.bar.height - Dimensions.bar.margin - expandedHeight - 8))
            : 0

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "launcher"
        WlrLayershell.exclusiveZone: 0

        readonly property bool isClipboardMode: search.text.startsWith(";")
        readonly property string clipQuery: isClipboardMode ? search.text.substring(1).trim().toLowerCase() : ""
        readonly property var mathResult: !isClipboardMode ? SearchLogic.evalMath(search.text) : null

        onVisibleChanged: {
            if (visible) {
                search.text = ""
                searching = false
                list.currentIndex = 0
                clipboard.refresh()
                search.forceActiveFocus()
            } else {
                // Згортаємо одразу, поки вікно приховане — без видимого стрибка
                searching = false
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
                left: parent.left
                right: parent.right
            }
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
                                    clipboard.deleteItem(item)
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
                                if (search.text.startsWith(";")) {
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
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.titleSmall
                                font.weight: Typography.weight.bold
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
                        visible: win.mathResult === null

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
                                        return clipboard.items
                                    }
                                    return clipboard.items.filter(item =>
                                        item.preview.toLowerCase().includes(win.clipQuery)
                                    )
                                } else {
                                    if (search.text.trim() === "") return []
                                    return SearchLogic.filterApplications(DesktopEntries.applications.values, search.text)
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
