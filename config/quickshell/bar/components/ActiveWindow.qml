import "../../theme"
import Quickshell.Hyprland
import QtQuick

// Active window chip: neon left-accent bar + fade on title change.
Surface {
    id: root

    readonly property var client: {
        if (Hyprland.activeToplevel)
            return Hyprland.activeToplevel;
        const workspace = Hyprland.focusedWorkspace?.id;
        return Hyprland.toplevels.values.find(t => t.workspace?.id === workspace && t.lastIpcObject?.focusHistoryID === 0)
            ?? Hyprland.toplevels.values.find(t => t.activated)
            ?? null;
    }
    readonly property string appClass: client
        ? (client.wayland?.appId ?? client.lastIpcObject?.class ?? "")
        : ""
    readonly property string title: client
        ? (client.title !== "" ? client.title : root.appClass)
        : ""

    visible: client !== null
    implicitWidth: 190
    implicitHeight: Dimensions.control.height
    radius: Dimensions.radius.full
    surfaceColor: Colors.surfaceContainerHigh

    // Neon left accent bar
    Rectangle {
        z: 2
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: 11
        radius: 1
        color: Colors.primary
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 15
        anchors.rightMargin: 12
        spacing: 6

        AppIcon {
            id: appIcon
            appClass: root.appClass
            iconSize: Dimensions.icon.medium
            anchors.verticalCenter: parent.verticalCenter
            visible: ready
        }

        Text {
            id: titleText
            width: parent.width - (appIcon.visible ? appIcon.width + parent.spacing : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.bold
            elide: Text.ElideRight

            onTextChanged: fadeAnim.restart()
            // Title change: the old label dips out on the leaving curve, the new
            // one settles in on the entering curve.
            SequentialAnimation {
                id: fadeAnim

                NumberAnimation {
                    target: titleText
                    property: "opacity"
                    to: 0.3
                    duration: Motion.durationShort2
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Motion.standardAccelerateCurve
                }

                NumberAnimation {
                    target: titleText
                    property: "opacity"
                    to: 1.0
                    duration: Motion.durationShort4
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Motion.emphasizedDecelerateCurve
                }
            }
        }
    }
}
