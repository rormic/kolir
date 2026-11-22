.pragma library

// Pure title cleanup and cover fallback shared by the now-playing island.
// Browser players put the tab title in xesam:title, which carries a tab
// counter ("(3) ") and a site suffix (" - YouTube"). Stripping both turns it
// back into the track name. Kept free of QML types and state so it can be
// exercised on its own.
function cleanTitle(title) {
    if (typeof title !== "string")
        return "";

    return title
        .replace(/^\(\d+\)\s*/, "")
        .replace(/\s+-\s+YouTube\s*$/, "")
        .trim();
}

// YouTube does not always expose mpris:artUrl (Firefox/Zen regular videos are
// the common case), but its Media Session URL still identifies the video. Its
// public thumbnail is a 16:9 image that fits the square cover slot. Returns ""
// for every other site so the app icon stays the fallback there.
function youtubeThumbnail(url) {
    if (typeof url !== "string")
        return "";

    const match = url.match(
        /(?:youtube(?:-nocookie)?\.com\/(?:watch\?(?:.*&)?v=|shorts\/|embed\/)|youtu\.be\/)([A-Za-z0-9_-]{6,})/i);

    return match ? "https://i.ytimg.com/vi/" + match[1] + "/mqdefault.jpg" : "";
}
