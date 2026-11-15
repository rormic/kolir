import Quickshell
import "bar"
import "launcher"
import "corners"
import "notification"
import "osd"
import "rec"

ShellRoot {
    Bar {}
    Launcher {}
    Notification {}
    VolumeOsd {}
    RecordingSetup {}

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            required property var modelData

            // The bar spans the full top edge, so the screen-corner masks are
            // only needed at the bottom.
            Corner {
                screen: modelData
                pos: 2
            }
            Corner {
                screen: modelData
                pos: 3
            }
        }
    }
}
