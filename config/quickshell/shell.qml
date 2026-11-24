import Quickshell
import "bar"
import "capture"
import "filepicker"
import "launcher"
import "notification"
import "osd"
import "recording"
import "screenshot"
import "shortcuts"

ShellRoot {
    // Decorative Bottom-layer screen frame; the bar and its popout stay above
    // it on the Top layer.
    Frame {}
    Bar {}
    CaptureHistory {}
    FilePicker {}
    Launcher {}
    Notification {}
    VolumeOsd {}
    BrightnessOsd {}
    RecordingSetup {}
    ScreenshotOverlay {}
    Shortcuts {}

}
