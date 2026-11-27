import QtQuick
import "../bar/components"
import "../theme"

// Main settings grid. Entries are data-driven so future categories only
// need an object here plus their own page component.
Item {
    id: root

    signal open(string page)

    property int revealTick: 0
    property int topInset: 0

    implicitWidth: 388
    implicitHeight: 530

    readonly property var entries: [
        {
            icon: Icons.bluetooth,
            title: "Bluetooth",
            subtitle: "Devices & pairing",
            soon: false,
            page: "bluetooth",
        },
        {
            icon: Icons.wifi,
            title: "Internet",
            subtitle: "Networks & Ethernet",
            soon: false,
            page: "internet",
        },
        {
            icon: Icons.palette,
            title: "Appearance",
            subtitle: "Palette & theme mode",
            soon: false,
            page: "appearance",
        },
        {
            icon: Icons.fontDownload,
            title: "Fonts",
            subtitle: "Interface, terminal & Obsidian",
            soon: false,
            page: "fonts",
        },
        {
            icon: Icons.calendar,
            title: "Calendar",
            subtitle: "Google Calendar sync",
            soon: false,
            page: "calendar",
        },
    ]

    Column {
        anchors.fill: parent
        anchors.margins: 16
        anchors.topMargin: root.topInset
        spacing: 12

        Text {
            text: "Settings"
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.titleLarge
            font.weight: Typography.weight.bold
        }

        Column {
            width: parent.width
            spacing: 8

            Repeater {
                model: root.entries

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index

                    readonly property bool soon: modelData.soon
                    readonly property bool hovered: rowMouse.containsMouse && !row.soon

                    property real appear: 0

                    width: parent.width
                    height: 58

                    opacity: row.appear * (row.soon ? 0.7 : 1.0)
                    transform: Translate { y: (1.0 - row.appear) * 8 }

                    SequentialAnimation {
                        id: enterAnim

                        PauseAnimation { duration: 20 + row.index * 25 }
                        NumberAnimation {
                            target: row
                            property: "appear"
                            to: 1
                            duration: Motion.listEnter
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Motion.emphasizedDecelerateCurve
                        }
                    }

                    Connections {
                        target: root

                        function onRevealTickChanged() {
                            row.appear = 0;
                            enterAnim.restart();
                        }
                    }

                    Component.onCompleted: {
                        if (root.revealTick > 0)
                            enterAnim.start();
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Dimensions.radius.medium
                        color: row.soon
                            ? Colors.withAlpha(Colors.surfaceContainerHigh, 0.55)
                            : Colors.surfaceContainerHigh

                        Behavior on color {
                            ColorAnimation {
                                duration: Motion.color
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Motion.standardDecelerateCurve
                            }
                        }

                        StateLayer {
                            shown: row.hovered
                            strength: 0.14
                        }
                    }

                    Rectangle {
                        id: iconBox

                        anchors {
                            left: parent.left
                            leftMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        width: 38
                        height: 38
                        radius: Dimensions.radius.small + 2
                        color: Colors.withAlpha(Colors.primary, row.hovered ? 0.2 : 0.11)

                        Behavior on color {
                            ColorAnimation {
                                duration: Motion.hover
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Motion.standardDecelerateCurve
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: row.modelData.icon
                            color: row.soon
                                ? Colors.withAlpha(Colors.onSurfaceVariant, 0.6)
                                : Colors.primary
                            font.family: Typography.iconFont
                            font.pixelSize: Dimensions.icon.large
                        }
                    }

                    Column {
                        anchors {
                            left: iconBox.right
                            leftMargin: 12
                            right: chevron.left
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 2

                        Text {
                            text: row.modelData.title
                            color: row.soon
                                ? Colors.withAlpha(Colors.onSurface, 0.7)
                                : Colors.onSurface
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelLarge
                            font.weight: Typography.weight.medium
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: row.modelData.subtitle
                            color: Colors.onSurfaceVariant
                            font.family: Typography.barFont
                            font.pixelSize: Typography.size.labelSmall
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Text {
                        id: chevron

                        anchors {
                            right: parent.right
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        text: Icons.chevronRight
                        color: Colors.withAlpha(Colors.onSurfaceVariant, row.hovered ? 0.95 : 0.55)
                        font.family: Typography.iconFont
                        font.pixelSize: Dimensions.icon.medium

                        Behavior on color {
                            ColorAnimation {
                                duration: Motion.hover
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Motion.standardDecelerateCurve
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !row.soon
                        cursorShape: row.soon ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (row.modelData.page)
                                root.open(row.modelData.page);
                        }
                    }
                }
            }
        }

        CaffeineCard {
            width: parent.width
        }
    }
}
