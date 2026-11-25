pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../services"
import "../../services/calendar/CalendarModel.js" as CalendarModel

// Calendar sheet for the clock's date. It is the same EmbeddedSheet as the
// night-light, sound, battery and notification sheets — same surface, scrim,
// reveal and dismissal — but anchored under the date instead of a screen edge:
// the floating mode centers a symmetric panel on the date's x position and
// drops it from the bar strip. Only the date carries the affordance; the clock
// otherwise stays flat information.
//
// The grid shows one dot row on days that have events. Clicking a day selects
// it (a tail/head day also moves the month) and the card under the grid lists
// that day's events, with the + control opening a small inline form (title,
// all-day, start/end). Events are owned by CalendarService and stored in the
// Google-compatible shape described in calendar/CalendarModel.js.
//
// Opening always returns to the current month with today selected, and the
// Today action appears while another month is on screen, so today is never
// more than one click away.
EmbeddedSheet {
    id: root

    readonly property int cellWidth: 44
    readonly property int cellHeight: 44
    readonly property int dayCircleSize: 28
    readonly property int dotSize: 4
    readonly property int dotSpacing: 3
    readonly property int maxDots: 3
    readonly property int countPillHeight: 12
    readonly property int countPillMinWidth: 14
    readonly property int countFontSize: 9
    readonly property int gridRows: 6
    readonly property int gridWidth: cellWidth * 7
    readonly property int gridHeight: cellHeight * gridRows
    readonly property int cardPadding: 12
    readonly property int cardHeaderHeight: 28
    readonly property int weekdayHeight: 16
    readonly property int cardSpacing: 8
    readonly property int cardHeight: cardPadding * 2 + cardHeaderHeight
        + cardSpacing + weekdayHeight + cardSpacing + gridHeight

    // Day card under the grid. The form replaces the list while it is open.
    readonly property int detailsHeaderHeight: 26
    readonly property int eventRowHeight: 32
    readonly property int detailsMaxRows: 3
    readonly property int detailsEmptyHeight: 26
    readonly property int detailsSpacing: 8

    readonly property int fieldHeight: 32
    readonly property int formToggleHeight: 22
    readonly property int formActionsHeight: 24
    readonly property int formErrorHeight: 14
    readonly property int formSpacing: 8

    // These mirror the content layout below, like the battery sheet.
    readonly property int titleBlockHeight: 44
    readonly property int contentColumnMargins: 14
    readonly property int contentColumnSpacing: 12
    readonly property int contentBottomReserve: 6
    readonly property int maxPanelHeight: Math.max(
        320, root.height - Dimensions.bar.height - 8)

    // Today's cell key (yyyymmdd), cheap to compare while the grid is built.
    readonly property date today: sysClock.date
    readonly property int todayKey: {
        const d = root.today;
        return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
    }
    readonly property string todayLabel: Qt.formatDate(
        root.today, "dddd, d MMMM yyyy")

    // Month currently shown by the grid. open() resets it to the real today.
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()

    // Day whose events the lower card lists. open() selects today.
    property int selectedKey: root.todayKey

    // Inline add form state.
    property bool formOpen: false
    property string formTitle: ""
    property bool formAllDay: false
    property string formStart: "09:00"
    property string formEnd: "10:00"
    property string formError: ""
    property string formErrorField: ""

    readonly property bool viewingToday: root.viewYear === root.today.getFullYear()
        && root.viewMonth === root.today.getMonth()
    readonly property string monthLabel: Qt.formatDate(
        new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")

    readonly property date selectedDate: CalendarModel.keyToDate(root.selectedKey)
    readonly property string selectedLabel: root.selectedKey === root.todayKey
        ? "Today · " + Qt.formatDate(root.selectedDate, "d MMMM")
        : Qt.formatDate(root.selectedDate, "ddd, d MMMM")
    readonly property var dayEvents: CalendarService.eventsOn(root.selectedKey)
    readonly property var eventCounts: CalendarService.dayCounts

    readonly property int formBodyHeight: root.fieldHeight + root.formSpacing
        + root.formToggleHeight + root.formSpacing
        + (root.formAllDay ? 0 : root.fieldHeight + root.formSpacing)
        + root.formActionsHeight
        + (root.formError !== "" ? root.formSpacing + root.formErrorHeight : 0)
    readonly property int listBodyHeight: root.dayEvents.length === 0
        ? root.detailsEmptyHeight
        : Math.min(root.detailsMaxRows, root.dayEvents.length) * root.eventRowHeight
    readonly property int detailsBodyHeight: root.formOpen
        ? root.formBodyHeight : root.listBodyHeight
    readonly property int detailsCardHeight: root.cardPadding * 2
        + root.detailsHeaderHeight + root.detailsSpacing + root.detailsBodyHeight
    readonly property int detailsBodyWidth: root.popupWidth
        - root.contentLeftInset - root.contentRightInset
        - 2 * root.contentColumnMargins - root.cardPadding * 2

    panelHeight: Math.min(root.maxPanelHeight,
        root.contentTopInset + 2 * root.contentColumnMargins
        + root.titleBlockHeight + root.contentColumnSpacing
        + root.cardHeight + root.contentColumnSpacing
        + root.detailsCardHeight + root.contentBottomReserve)

    // The form and the list swap inside the same card, so the sheet grows and
    // shrinks instead of jumping between two heights.
    Behavior on panelHeight {
        NumberAnimation { duration: Motion.move; easing.type: Easing.OutCubic }
    }

    // Monday-first, because the grid always starts on a Monday.
    readonly property var weekdayLabels: {
        const locale = Qt.locale();
        const labels = [];
        for (let day = 1; day <= 7; day++)
            labels.push(locale.dayName(day, Locale.ShortFormat));
        return labels;
    }

    // 42 cells: the days of the month padded with the tail of the previous
    // month and the head of the next one, so every row is full.
    readonly property var cells: {
        const firstWeekday = (new Date(root.viewYear, root.viewMonth, 1).getDay() + 6) % 7;
        const daysInMonth = new Date(root.viewYear, root.viewMonth + 1, 0).getDate();
        const daysInPrevMonth = new Date(root.viewYear, root.viewMonth, 0).getDate();
        const todayKey = root.todayKey;
        const counts = root.eventCounts;
        const result = [];

        for (let i = 0; i < root.gridRows * 7; i++) {
            let day;
            let month = root.viewMonth;
            let year = root.viewYear;
            let inMonth = true;

            if (i < firstWeekday) {
                day = daysInPrevMonth - firstWeekday + i + 1;
                inMonth = false;
                month -= 1;
                if (month < 0) {
                    month = 11;
                    year -= 1;
                }
            } else if (i >= firstWeekday + daysInMonth) {
                day = i - firstWeekday - daysInMonth + 1;
                inMonth = false;
                month += 1;
                if (month > 11) {
                    month = 0;
                    year += 1;
                }
            } else {
                day = i - firstWeekday + 1;
            }

            const key = year * 10000 + (month + 1) * 100 + day;

            result.push({
                day: day,
                year: year,
                month: month,
                inMonth: inMonth,
                key: key,
                today: key === todayKey,
                count: counts[String(key)] || 0,
            });
        }

        return result;
    }

    function resetToToday() {
        const now = new Date();
        root.viewYear = now.getFullYear();
        root.viewMonth = now.getMonth();
    }

    function shiftMonth(delta) {
        const target = new Date(root.viewYear, root.viewMonth + delta, 1);
        root.viewYear = target.getFullYear();
        root.viewMonth = target.getMonth();
    }

    // Selecting a tail/head day also moves the grid to that month, so the
    // highlighted cell is never left on a dimmed edge.
    function selectCell(cell) {
        root.selectedKey = cell.key;
        if (!cell.inMonth) {
            root.viewYear = cell.year;
            root.viewMonth = cell.month;
        }
    }

    // ── Add form ───────────────────────────────────────────────────────────
    function beginAdd() {
        const now = new Date();
        let startMinutes = 9 * 60;
        if (root.selectedKey === root.todayKey) {
            startMinutes = Math.min((now.getHours() + 1) * 60, 23 * 60);
        }

        root.formTitle = "";
        root.formAllDay = false;
        root.formStart = CalendarModel.formatClock(startMinutes);
        root.formEnd = CalendarModel.formatClock(Math.min(startMinutes + 60, 24 * 60 - 1));
        root.formError = "";
        root.formErrorField = "";

        titleField.text = "";
        startField.text = root.formStart;
        endField.text = root.formEnd;

        root.formOpen = true;
        Qt.callLater(function () {
            titleField.forceFocus();
        });
    }

    function cancelForm() {
        if (!root.formOpen)
            return;

        root.formOpen = false;
        root.formError = "";
        root.formErrorField = "";
        root.forceActiveFocus();
    }

    function commitForm() {
        const title = root.formTitle.trim();
        if (title === "") {
            root.formError = "Enter an event title";
            root.formErrorField = "title";
            titleField.forceFocus();
            return;
        }

        let startMinutes = 0;
        let endMinutes = 0;
        if (!root.formAllDay) {
            startMinutes = CalendarModel.parseTime(root.formStart);
            endMinutes = CalendarModel.parseTime(root.formEnd);

            if (startMinutes < 0) {
                root.formError = "Start must be a time like 09:30";
                root.formErrorField = "start";
                startField.forceFocus();
                return;
            }

            if (endMinutes < 0) {
                root.formError = "End must be a time like 10:30";
                root.formErrorField = "end";
                endField.forceFocus();
                return;
            }

            if (endMinutes <= startMinutes) {
                root.formError = "End must be after the start";
                root.formErrorField = "end";
                endField.forceFocus();
                return;
            }
        }

        const event = CalendarService.addEvent({
            summary: title,
            dayKey: root.selectedKey,
            allDay: root.formAllDay,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
        });
        if (!event) {
            root.formError = CalendarService.lastError || "Could not save the event";
            root.formErrorField = "";
            return;
        }

        root.formOpen = false;
        root.formError = "";
        root.formErrorField = "";
        root.forceActiveFocus();
    }

    function open() {
        if (root.opened)
            return;

        root.resetToToday();
        root.selectedKey = root.todayKey;
        root.formOpen = false;
        root.formError = "";
        root.formErrorField = "";
        root.revealOpen();
    }

    function close() {
        if (!root.opened)
            return;

        root.revealClose();
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open();
    }

    onDismissalRequested: root.close()

    onDidClose: {
        root.formOpen = false;
        root.formError = "";
        root.formErrorField = "";
    }

    Keys.onEscapePressed: function (event) {
        if (root.formOpen) {
            root.cancelForm();
        } else {
            root.close();
        }
        event.accepted = true;
    }

    IpcHandler {
        target: "calendar"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        // day is a yyyymmdd key ("20261126"); times are "HH:mm" and are only
        // read when allDay is false. Returns the new event's uid, or "".
        function eventAdd(day: string, title: string, allDay: bool,
                          start: string, end: string): string {
            const key = Number.parseInt(day, 10);
            const event = CalendarService.addEvent({
                summary: title,
                dayKey: key,
                allDay: allDay,
                startMinutes: CalendarModel.parseTime(start),
                endMinutes: CalendarModel.parseTime(end),
            });
            return event ? event.uid : "";
        }

        function eventRemove(uid: string): bool {
            return CalendarService.removeEvent(uid);
        }

        function eventList(day: string): string {
            return JSON.stringify(CalendarService.eventsOn(
                Number.parseInt(day, 10)));
        }

        function status(): string {
            return JSON.stringify({
                open: root.opened,
                modal: root.modal,
                year: root.viewYear,
                month: root.viewMonth + 1,
                today: root.todayKey,
                selected: root.selectedKey,
                count: CalendarService.events.length,
                provider: CalendarService.provider,
            });
        }
    }

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.contentTopInset + root.contentColumnMargins
            leftMargin: root.contentColumnMargins
            rightMargin: root.contentColumnMargins
            bottomMargin: root.contentColumnMargins
        }
        spacing: root.contentColumnSpacing

        PopupHeader {
            Layout.fillWidth: true
            Layout.preferredHeight: root.titleBlockHeight
            title: "Calendar"
            subtitle: root.todayLabel
        }

        // One card, like the night-light and notification rows, holding the
        // month header, the weekday labels and the day grid.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: root.cardHeight
            radius: Dimensions.radius.medium
            color: Colors.surfaceContainerHigh
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

            Column {
                anchors {
                    fill: parent
                    margins: root.cardPadding
                }
                spacing: root.cardSpacing

                RowLayout {
                    width: parent.width
                    height: root.cardHeaderHeight
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: root.monthLabel
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.bodyLarge
                        font.weight: Typography.weight.semibold
                        elide: Text.ElideRight
                    }

                    // Only offered while another month is on screen.
                    Rectangle {
                        id: todayButton

                        Layout.alignment: Qt.AlignVCenter
                        visible: !root.viewingToday
                        implicitWidth: todayText.implicitWidth + 12
                        implicitHeight: 24
                        radius: height / 2
                        color: "transparent"

                        StateLayer {
                            shown: todayMouse.containsMouse
                            tint: Colors.primary
                            strength: 0.14
                        }

                        Text {
                            id: todayText

                            anchors.centerIn: parent
                            text: "Today"
                            color: Colors.primary
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelMedium
                            font.weight: Typography.weight.medium
                        }

                        MouseArea {
                            id: todayMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.resetToToday();
                                root.selectedKey = root.todayKey;
                            }
                        }
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        icon: Icons.chevronLeft
                        iconSize: Dimensions.icon.medium
                        onClicked: root.shiftMonth(-1)
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        icon: Icons.chevronRight
                        iconSize: Dimensions.icon.medium
                        onClicked: root.shiftMonth(1)
                    }
                }

                Row {
                    x: (parent.width - width) / 2
                    width: root.gridWidth
                    height: root.weekdayHeight

                    Repeater {
                        model: root.weekdayLabels

                        delegate: Item {
                            id: weekdayCell

                            required property var modelData

                            width: root.cellWidth
                            height: root.weekdayHeight

                            Text {
                                anchors.centerIn: parent
                                text: weekdayCell.modelData
                                color: Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelSmall
                                font.weight: Typography.weight.medium
                            }
                        }
                    }
                }

                Grid {
                    x: (parent.width - width) / 2
                    width: root.gridWidth
                    height: root.gridHeight
                    columns: 7

                    Repeater {
                        model: root.cells

                        delegate: Item {
                            id: dayCell

                            required property var modelData

                            readonly property bool selected: root.selectedKey === dayCell.modelData.key
                            readonly property bool hovered: cellMouse.containsMouse

                            width: root.cellWidth
                            height: root.cellHeight

                            Rectangle {
                                id: dayBackground

                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 2
                                width: root.dayCircleSize
                                height: root.dayCircleSize
                                radius: width / 2
                                color: dayCell.modelData.today
                                    ? Colors.primary
                                    : dayCell.selected
                                        ? Colors.withAlpha(Colors.primary, 0.16)
                                        : dayCell.hovered
                                            ? Colors.stateLayer(Colors.onSurface, 0.08)
                                            : "transparent"
                                border.width: dayCell.selected ? 1 : 0
                                border.color: dayCell.modelData.today
                                    ? Colors.withAlpha(Colors.onPrimary, 0.8)
                                    : Colors.withAlpha(Colors.primary, 0.55)

                                Behavior on color {
                                    ColorAnimation { duration: Motion.hover }
                                }
                            }

                            Text {
                                anchors.centerIn: dayBackground
                                text: dayCell.modelData.day
                                color: dayCell.modelData.today
                                    ? Colors.onPrimary
                                    : dayCell.selected
                                        ? Colors.primary
                                        : dayCell.modelData.inMonth
                                            ? Colors.onSurface
                                            : Colors.withAlpha(Colors.onSurfaceVariant, 0.38)
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                font.weight: dayCell.modelData.today || dayCell.selected
                                    ? Typography.weight.bold
                                    : Typography.weight.regular
                            }

                            // Presence marker: one dot per event up to `maxDots`,
                            // then a small count pill instead — three dots for
                            // an unknown "many" was indistinguishable from
                            // exactly three.
                            Row {
                                visible: dayCell.modelData.count > 0
                                    && dayCell.modelData.count <= root.maxDots
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: dayBackground.y + dayBackground.height + 4
                                spacing: root.dotSpacing

                                Repeater {
                                    model: Math.min(dayCell.modelData.count, root.maxDots)

                                    delegate: Rectangle {
                                        required property int index

                                        width: root.dotSize
                                        height: root.dotSize
                                        radius: width / 2
                                        // The dots sit below the day circle,
                                        // on the card, so they stay primary
                                        // even for today's filled cell.
                                        color: Colors.primary
                                    }
                                }
                            }

                            Rectangle {
                                id: countPill

                                visible: dayCell.modelData.count > root.maxDots
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: dayBackground.y + dayBackground.height
                                width: Math.max(root.countPillMinWidth,
                                    countLabel.implicitWidth + 7)
                                height: root.countPillHeight
                                radius: height / 2
                                color: Colors.withAlpha(Colors.primary, 0.22)

                                Text {
                                    id: countLabel

                                    anchors.centerIn: parent
                                    text: dayCell.modelData.count > 99
                                        ? "99+" : dayCell.modelData.count
                                    color: Colors.primary
                                    font.family: Typography.barFont
                                    font.pixelSize: root.countFontSize
                                    font.weight: Typography.weight.bold
                                }
                            }

                            MouseArea {
                                id: cellMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectCell(dayCell.modelData)
                            }
                        }
                    }
                }
            }
        }

        // Selected day: its events, or the inline add form.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: root.detailsCardHeight
            radius: Dimensions.radius.medium
            color: Colors.surfaceContainerHigh
            border.width: 1
            border.color: Colors.withAlpha(Colors.outlineVariant, 0.22)

            Column {
                anchors {
                    fill: parent
                    margins: root.cardPadding
                }
                spacing: root.detailsSpacing

                RowLayout {
                    width: parent.width
                    height: root.detailsHeaderHeight
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: root.selectedLabel
                        color: Colors.onSurface
                        font.family: Typography.barFont
                        font.pixelSize: Typography.size.labelLarge
                        font.weight: Typography.weight.semibold
                        elide: Text.ElideRight
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        icon: root.formOpen ? Icons.close : Icons.add
                        iconSize: Dimensions.icon.medium
                        active: root.formOpen
                        onClicked: root.formOpen ? root.cancelForm() : root.beginAdd()
                    }
                }

                Item {
                    id: detailsBody

                    width: root.detailsBodyWidth
                    height: root.detailsBodyHeight

                    // ── Event list ─────────────────────────────────────────
                    Item {
                        id: listViewport

                        anchors.fill: parent
                        visible: !root.formOpen

                        Flickable {
                            anchors.fill: parent
                            visible: root.dayEvents.length > 0
                            contentWidth: width
                            contentHeight: listColumn.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: listColumn

                                width: listViewport.width
                                spacing: 0

                                Repeater {
                                    model: root.dayEvents

                                    delegate: Item {
                                        id: eventRow

                                        required property var modelData

                                        readonly property bool hovered: eventHover.containsMouse

                                        width: listColumn.width
                                        height: root.eventRowHeight

                                        StateLayer {
                                            shown: eventRow.hovered
                                            strength: 0.08
                                            radius: Dimensions.radius.small
                                        }

                                        // Hover only: it must not swallow the
                                        // delete button's click or the list's
                                        // wheel scrolling.
                                        MouseArea {
                                            id: eventHover

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.NoButton
                                        }

                                        RowLayout {
                                            anchors {
                                                fill: parent
                                                leftMargin: 6
                                                rightMargin: 2
                                            }
                                            spacing: 8

                                            Rectangle {
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredWidth: 3
                                                Layout.preferredHeight: 16
                                                radius: 1.5
                                                color: Colors.primary
                                            }

                                            Text {
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredWidth: 76
                                                text: CalendarModel.timeLabel(eventRow.modelData)
                                                color: Colors.onSurfaceVariant
                                                font.family: Typography.barFont
                                                font.pixelSize: Typography.size.labelSmall
                                                font.weight: Typography.weight.medium
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                text: eventRow.modelData.summary
                                                color: Colors.onSurface
                                                font.family: Typography.barFont
                                                font.pixelSize: Typography.size.labelLarge
                                                elide: Text.ElideRight
                                            }

                                            IconButton {
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredWidth: 22
                                                Layout.preferredHeight: 22
                                                icon: Icons.trash
                                                iconSize: Dimensions.icon.small
                                                iconColor: Colors.onSurfaceVariant
                                                iconHoverColor: Colors.error
                                                stateColor: Colors.error
                                                onClicked: CalendarService.removeEvent(eventRow.modelData.uid)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.dayEvents.length === 0
                            anchors {
                                left: parent.left
                                right: parent.right
                                leftMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            text: "No events · use + to add one"
                            color: Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            elide: Text.ElideRight
                        }
                    }

                    // ── Add form ───────────────────────────────────────────
                    Column {
                        id: formColumn

                        width: parent.width
                        visible: root.formOpen
                        spacing: root.formSpacing

                        TextField {
                            id: titleField

                            width: root.detailsBodyWidth
                            height: root.fieldHeight
                            placeholder: "Event title"
                            invalid: root.formErrorField === "title"

                            onTextChanged: {
                                root.formTitle = text;
                                if (root.formError !== "") {
                                    root.formError = "";
                                    root.formErrorField = "";
                                }
                            }

                            onAccepted: root.commitForm()
                            onCanceled: root.cancelForm()
                        }

                        RowLayout {
                            width: root.detailsBodyWidth
                            height: root.formToggleHeight
                            spacing: 8

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "All day"
                                color: Colors.onSurface
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelLarge
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Toggle {
                                Layout.alignment: Qt.AlignVCenter
                                checked: root.formAllDay
                                onToggled: value => {
                                    root.formAllDay = value;
                                    if (root.formError !== "") {
                                        root.formError = "";
                                        root.formErrorField = "";
                                    }
                                }
                            }
                        }

                        RowLayout {
                            width: root.detailsBodyWidth
                            height: root.fieldHeight
                            visible: !root.formAllDay
                            spacing: 6

                            TextField {
                                id: startField

                                Layout.preferredWidth: 62
                                Layout.preferredHeight: root.fieldHeight
                                placeholder: "09:00"
                                invalid: root.formErrorField === "start"

                                onTextChanged: {
                                    root.formStart = text;
                                    if (root.formError !== "") {
                                        root.formError = "";
                                        root.formErrorField = "";
                                    }
                                }

                                onAccepted: root.commitForm()
                                onCanceled: root.cancelForm()
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "–"
                                color: Colors.onSurfaceVariant
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                            }

                            TextField {
                                id: endField

                                Layout.preferredWidth: 62
                                Layout.preferredHeight: root.fieldHeight
                                placeholder: "10:00"
                                invalid: root.formErrorField === "end"

                                onTextChanged: {
                                    root.formEnd = text;
                                    if (root.formError !== "") {
                                        root.formError = "";
                                        root.formErrorField = "";
                                    }
                                }

                                onAccepted: root.commitForm()
                                onCanceled: root.cancelForm()
                            }

                            Item {
                                Layout.fillWidth: true
                            }
                        }

                        Text {
                            width: root.detailsBodyWidth
                            height: root.formErrorHeight
                            visible: root.formError !== ""
                            text: root.formError
                            color: Colors.error
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            width: root.detailsBodyWidth
                            height: root.formActionsHeight
                            spacing: 8

                            Item {
                                Layout.fillWidth: true
                            }

                            // Cancel: flat text action, like the Today pill.
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: cancelLabel.implicitWidth + 16
                                implicitHeight: root.formActionsHeight
                                radius: height / 2
                                color: "transparent"

                                StateLayer {
                                    shown: cancelMouse.containsMouse
                                    tint: Colors.onSurface
                                    strength: 0.10
                                }

                                Text {
                                    id: cancelLabel

                                    anchors.centerIn: parent
                                    text: "Cancel"
                                    color: Colors.onSurfaceVariant
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.labelMedium
                                    font.weight: Typography.weight.medium
                                }

                                MouseArea {
                                    id: cancelMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.cancelForm()
                                }
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: addLabel.implicitWidth + 20
                                implicitHeight: root.formActionsHeight
                                radius: height / 2
                                color: Colors.primary

                                StateLayer {
                                    shown: addMouse.containsMouse
                                    tint: Colors.onPrimary
                                    strength: 0.12
                                }

                                Text {
                                    id: addLabel

                                    anchors.centerIn: parent
                                    text: "Add"
                                    color: Colors.onPrimary
                                    font.family: Typography.barFont
                                    font.pixelSize: Typography.size.labelMedium
                                    font.weight: Typography.weight.semibold
                                }

                                MouseArea {
                                    id: addMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.commitForm()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
