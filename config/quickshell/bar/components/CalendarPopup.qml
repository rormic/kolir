pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"

// Calendar sheet for the clock's date. It is the same EmbeddedSheet as the
// night-light, sound, battery and notification sheets — same surface, scrim,
// reveal and dismissal — but anchored under the date instead of a screen edge:
// the floating mode centers a symmetric panel on the date's x position and
// drops it from the bar strip. Only the date carries the affordance; the clock
// otherwise stays flat information.
//
// The grid is read-only: today is filled with the primary colour, the days of
// the neighbouring months are dimmed, and the card header navigates by month.
// Opening always returns to the current month, and the Today action appears
// while another month is on screen, so today is never more than one click
// away.
EmbeddedSheet {
    id: root

    readonly property int cellWidth: 44
    readonly property int cellHeight: 34
    readonly property int gridRows: 6
    readonly property int gridWidth: cellWidth * 7
    readonly property int gridHeight: cellHeight * gridRows
    readonly property int cardPadding: 12
    readonly property int cardHeaderHeight: 28
    readonly property int weekdayHeight: 16
    readonly property int cardSpacing: 8
    readonly property int cardHeight: cardPadding * 2 + cardHeaderHeight
        + cardSpacing + weekdayHeight + cardSpacing + gridHeight

    // These mirror the content layout below, like the battery sheet.
    readonly property int titleBlockHeight: 44
    readonly property int contentColumnMargins: 14
    readonly property int contentColumnSpacing: 12
    readonly property int contentBottomReserve: 6
    readonly property int maxPanelHeight: Math.max(
        320, root.height - Dimensions.bar.height - 8)

    panelHeight: Math.min(root.maxPanelHeight,
        root.contentTopInset + 2 * root.contentColumnMargins
        + root.titleBlockHeight + root.contentColumnSpacing
        + root.cardHeight + root.contentBottomReserve)

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

    readonly property bool viewingToday: root.viewYear === root.today.getFullYear()
        && root.viewMonth === root.today.getMonth()
    readonly property string monthLabel: Qt.formatDate(
        new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")

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
        const key = root.todayKey;
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

            result.push({
                day: day,
                inMonth: inMonth,
                today: (year * 10000 + (month + 1) * 100 + day) === key
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

    function open() {
        if (root.opened)
            return;

        root.resetToToday();
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

    Keys.onEscapePressed: function (event) {
        root.close();
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

        function status(): string {
            return JSON.stringify({
                open: root.opened,
                modal: root.modal,
                year: root.viewYear,
                month: root.viewMonth + 1,
                today: root.todayKey
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
                            onClicked: root.resetToToday()
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

                            width: root.cellWidth
                            height: root.cellHeight

                            Rectangle {
                                anchors.centerIn: parent
                                width: 28
                                height: 28
                                radius: width / 2
                                visible: dayCell.modelData.today
                                color: Colors.primary
                            }

                            Text {
                                anchors.centerIn: parent
                                text: dayCell.modelData.day
                                color: dayCell.modelData.today
                                    ? Colors.onPrimary
                                    : dayCell.modelData.inMonth
                                        ? Colors.onSurface
                                        : Colors.withAlpha(Colors.onSurfaceVariant, 0.38)
                                font.family: Typography.barFont
                                font.pixelSize: Typography.size.labelMedium
                                font.weight: dayCell.modelData.today
                                    ? Typography.weight.bold
                                    : Typography.weight.regular
                            }
                        }
                    }
                }
            }
        }
    }
}
