import Quickshell
import "bar"
import "launcher"
import "notification"
import "osd"
import "recording"
import "shortcuts"
import "wallpaper"

ShellRoot {
    // Decorative Bottom-layer screen frame; the bar and its popout stay above
    // it on the Top layer.
    Frame {}
    Bar {}
    Launcher {}
    Notification {}
    VolumeOsd {}
    BrightnessOsd {}
    RecordingSetup {}
    Shortcuts {}
    WallpaperPicker {}

}
