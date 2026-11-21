import QtQuick
import Quickshell.Io
import "../../components"
import "../../theme"

// Sound popup for the bar volume pill: output/input volume, mute, device
// selection and Bluetooth codec switching. The content is the same
// SoundControls component the settings popup used to host.
AnchoredPopup {
    id: root

    panelWidth: 380
    panelHeight: 600
    headerHeight: 46

    onOpened: controls.refresh()

    IpcHandler {
        target: "volume"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }
    }

    headerContent: [
        Text {
            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: "Sound"
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.titleSmall
            font.weight: Typography.weight.bold
        },

        IconButton {
            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            icon: Icons.close
            iconSize: Dimensions.icon.medium
            onClicked: root.close()
        }
    ]

    SoundControls {
        id: controls

        anchors.fill: parent
    }
}
