pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "../../../theme"
import ".."

// 24-hour day dial for the night-light schedule and the Appearance page.
//
// Midnight sits at the top and the scale runs clockwise, so 06:00 is at the
// right, noon at the bottom and 18:00 at the left. The ring is a 24-hour
// track: the sunrise-to-sunset arc is the lighter day band, the rest is the
// darker night band, and the two radial marks separate them. A sun marker
// travels the band once per day and the hub shows the current time.
//
// Everything the dial knows is attached to the ring: the day and night
// durations sit at their band midpoints and the two solar times at their
// boundary marks, each joined to the ring by a short leader. The location and
// the refresh action ride above the circle, so no data is left in a side
// column. Callers bind the service values in and handle `refreshRequested()`.
Item {
    id: root

    property string city: ""
    property string country: ""
    // Shown in place of the city line while the service has no place name
    // (detecting, an error, or no location yet).
    property string fallback: "Location unavailable"
    property string dayLength: "—"
    property string nightLength: "—"
    property string sunrise: "—"
    property string sunset: "—"
    // Minutes since local midnight for the two solar events; -1 when the
    // service has no location or the date has no sunrise/sunset.
    property real sunriseMinutes: -1
    property real sunsetMinutes: -1
    property bool refreshing: false

    signal refreshRequested()

    readonly property int headerHeight: 24
    readonly property int dialWidth: 220
    readonly property int dialHeight: 204

    implicitWidth: root.dialWidth
    implicitHeight: root.headerHeight + root.dialHeight

    readonly property bool hasSunTimes: root.sunriseMinutes >= 0
        && root.sunsetMinutes > root.sunriseMinutes
    // Light and dark palettes put their surface containers on opposite sides
    // of the scale, so the band tints are derived from the palette instead of
    // assuming a dark theme.
    readonly property bool darkPalette: Colors.surfaceContainerLow.hslLightness < 0.5

    readonly property real centerX: root.dialWidth / 2
    readonly property real centerY: root.dialHeight / 2
    readonly property real ringOuter: 68
    readonly property real ringInner: 47
    readonly property real ringMid: (root.ringOuter + root.ringInner) / 2
    readonly property real ringWidth: root.ringOuter - root.ringInner

    // Clearance between the ring and the closest edge of every callout. The
    // hour marks live inside it, so the leaders never fight with the ticks.
    // The durations sit further out than the times: a short winter day crams
    // both solar times next to the day label, and the extra ring keeps the
    // three of them apart.
    readonly property int durationGap: 20
    readonly property int timeGap: 8
    readonly property int calloutHeight: 16
    readonly property int durationLabelWidth: 112
    readonly property int timeLabelWidth: 40
    // Distance from the dial's top and bottom edge to the duration callouts.
    readonly property int calloutEdge: 2

    readonly property real sunriseAngle: root.sunriseMinutes / 1440 * 360
    readonly property real sunsetAngle: root.sunsetMinutes / 1440 * 360
    // Clockwise day arc. A normal day is shorter than 360 degrees, so the two
    // events always resolve to one sector; equal times are treated as missing.
    readonly property real daySweep: root.hasSunTimes
        ? ((root.sunsetAngle - root.sunriseAngle) + 360) % 360
        : 0
    readonly property real dayMidAngle: root.sunriseAngle + root.daySweep / 2
    readonly property real nightMidAngle: root.dayMidAngle + 180

    property date now: new Date()
    readonly property real nowMinutes: root.now.getHours() * 60
        + root.now.getMinutes() + root.now.getSeconds() / 60
    readonly property real sunAngle: root.nowMinutes / 1440 * 360
    readonly property string nowLabel: root.pad2(root.now.getHours())
        + ":" + root.pad2(root.now.getMinutes())

    // The day band is the palette accent; the night band is a dark wash in the
    // dark palette and a darker grey wash in the light one, so the day always
    // reads as the lighter half. The hub stays on the card colour, so the
    // current time reads as plain chrome.
    readonly property color dayBandColor: root.darkPalette
        ? Colors.withAlpha(Colors.primary, 0.72)
        : Colors.primaryContainer
    readonly property color nightBandColor: root.darkPalette
        ? Colors.withAlpha(Colors.surfaceContainerLow, 0.92)
        : Colors.withAlpha(Colors.onSurface, 0.16)
    readonly property color bezelColor: Colors.withAlpha(Colors.outlineVariant, 0.55)
    readonly property color boundaryColor: Colors.withAlpha(Colors.onSurfaceVariant, 0.55)
    readonly property color tickColor: Colors.withAlpha(Colors.onSurfaceVariant, 0.38)
    readonly property color majorTickColor: Colors.withAlpha(Colors.onSurfaceVariant, 0.62)
    readonly property color timeLeaderColor: Colors.withAlpha(Colors.onSurfaceVariant, 0.8)
    readonly property color sunHalo: Colors.withAlpha(Colors.primary, 0.20)

    // ── Geometry ──────────────────────────────────────────────────────────
    function pointOnCircle(angle, radius) {
        const rad = angle * Math.PI / 180;
        return {
            x: root.centerX + Math.sin(rad) * radius,
            y: root.centerY - Math.cos(rad) * radius,
        };
    }

    // A callout is a horizontal text box nudged out from the ring along its
    // angle. The radius includes the box's own extent along that direction, so
    // a wide label on a diagonal still starts outside the track; the result is
    // then clamped to the dial so seasonal extremes cannot push it off-canvas.
    function clamp(value, low, high) {
        return Math.max(low, Math.min(high, value));
    }

    function calloutCenter(angle, w, h, gap) {
        const ux = Math.sin(angle * Math.PI / 180);
        const uy = -Math.cos(angle * Math.PI / 180);
        const radius = root.ringOuter + gap
            + (Math.abs(ux) * w + Math.abs(uy) * h) / 2;
        return {
            x: root.clamp(root.centerX + ux * radius, w / 2 + 2,
                root.dialWidth - w / 2 - 2),
            y: root.clamp(root.centerY + uy * radius, h / 2 + 2,
                root.dialHeight - h / 2 - 2),
        };
    }

    // A solar time is clamped out of the duration bands, so the three labels
    // around a short winter day never sit on top of each other.
    function timeCalloutCenter(angle) {
        const point = root.calloutCenter(angle, root.timeLabelWidth,
            root.calloutHeight, root.timeGap);
        return {
            x: point.x,
            y: root.clamp(point.y,
                root.calloutEdge + root.calloutHeight * 1.5 + 4,
                root.dialHeight - root.calloutEdge - root.calloutHeight * 1.5 - 4),
        };
    }

    // A leader runs from the ring's outer edge to the nearest point of the
    // callout, so it stops at the text instead of crossing it.
    function leaderPath(angle, center, w, h) {
        const start = root.pointOnCircle(angle, root.ringOuter);
        const dx = center.x - root.centerX;
        const dy = center.y - root.centerY;
        const length = Math.sqrt(dx * dx + dy * dy);
        if (length < 0.001)
            return "";

        const ux = dx / length;
        const uy = dy / length;
        const back = (Math.abs(ux) * w + Math.abs(uy) * h) / 2;
        return "M " + start.x + " " + start.y
            + " L " + (center.x - ux * back) + " " + (center.y - uy * back);
    }

    readonly property point dayCallout: root.calloutCenter(
        root.dayMidAngle, root.durationLabelWidth, root.calloutHeight,
        root.durationGap)
    readonly property point nightCallout: root.calloutCenter(
        root.nightMidAngle, root.durationLabelWidth, root.calloutHeight,
        root.durationGap)
    readonly property point sunriseCallout: root.timeCalloutCenter(root.sunriseAngle)
    readonly property point sunsetCallout: root.timeCalloutCenter(root.sunsetAngle)

    // ── Paths ─────────────────────────────────────────────────────────────
    readonly property string trackPath: {
        const cx = root.centerX;
        const cy = root.centerY;
        const r = root.ringMid;
        return "M " + (cx - r) + " " + cy
            + " A " + r + " " + r + " 0 1 0 " + (cx + r) + " " + cy
            + " A " + r + " " + r + " 0 1 0 " + (cx - r) + " " + cy + " Z";
    }

    readonly property string outerPath: {
        const cx = root.centerX;
        const cy = root.centerY;
        const r = root.ringOuter;
        return "M " + (cx - r) + " " + cy
            + " A " + r + " " + r + " 0 1 0 " + (cx + r) + " " + cy
            + " A " + r + " " + r + " 0 1 0 " + (cx - r) + " " + cy + " Z";
    }

    readonly property string innerPath: {
        const cx = root.centerX;
        const cy = root.centerY;
        const r = root.ringInner;
        return "M " + (cx - r) + " " + cy
            + " A " + r + " " + r + " 0 1 0 " + (cx + r) + " " + cy
            + " A " + r + " " + r + " 0 1 0 " + (cx - r) + " " + cy + " Z";
    }

    readonly property string dayArcPath: {
        if (!root.hasSunTimes)
            return "";

        const start = root.pointOnCircle(root.sunriseAngle, root.ringMid);
        const end = root.pointOnCircle(root.sunsetAngle, root.ringMid);
        const largeArc = root.daySweep > 180 ? 1 : 0;

        return "M " + start.x + " " + start.y
            + " A " + root.ringMid + " " + root.ringMid + " 0 "
            + largeArc + " 1 " + end.x + " " + end.y;
    }

    readonly property string boundaryPath: {
        if (!root.hasSunTimes)
            return "";

        const riseOuter = root.pointOnCircle(root.sunriseAngle, root.ringOuter);
        const riseInner = root.pointOnCircle(root.sunriseAngle, root.ringInner);
        const setOuter = root.pointOnCircle(root.sunsetAngle, root.ringOuter);
        const setInner = root.pointOnCircle(root.sunsetAngle, root.ringInner);

        return "M " + riseInner.x + " " + riseInner.y
            + " L " + riseOuter.x + " " + riseOuter.y
            + " M " + setInner.x + " " + setInner.y
            + " L " + setOuter.x + " " + setOuter.y;
    }

    readonly property string dayLeaderPath: root.hasSunTimes
        ? root.leaderPath(root.dayMidAngle, root.dayCallout,
            root.durationLabelWidth, root.calloutHeight)
        : ""
    readonly property string nightLeaderPath: root.hasSunTimes
        ? root.leaderPath(root.nightMidAngle, root.nightCallout,
            root.durationLabelWidth, root.calloutHeight)
        : ""
    readonly property string sunriseLeaderPath: root.hasSunTimes
        ? root.leaderPath(root.sunriseAngle, root.sunriseCallout,
            root.timeLabelWidth, root.calloutHeight)
        : ""
    readonly property string sunsetLeaderPath: root.hasSunTimes
        ? root.leaderPath(root.sunsetAngle, root.sunsetCallout,
            root.timeLabelWidth, root.calloutHeight)
        : ""

    function pad2(value) {
        return value < 10 ? "0" + value : "" + value;
    }

    // The sun advances once a minute; when the sheet is hidden there is no
    // reason to run the timer. Reopening refreshes the position immediately.
    Timer {
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: root.visible
        onTriggered: root.now = new Date()
    }

    Component.onCompleted: root.now = new Date()
    onVisibleChanged: {
        if (root.visible)
            root.now = new Date();
    }

    // ── Location row ──────────────────────────────────────────────────────
    Item {
        id: header

        width: root.width
        height: root.headerHeight

        Text {
            anchors.centerIn: parent
            width: root.width - refreshButton.width - 24
            text: root.city !== ""
                ? (root.country !== "" ? root.city + ", " + root.country : root.city)
                : root.fallback
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: Typography.weight.medium
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        IconButton {
            id: refreshButton

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 22
            implicitHeight: 22
            icon: Icons.refresh
            iconSize: Dimensions.icon.small
            iconColor: Colors.onSurfaceVariant
            enabled: !root.refreshing
            opacity: root.refreshing ? 0.55 : 1.0
            onClicked: root.refreshRequested()
        }
    }

    // ── Dial ──────────────────────────────────────────────────────────────
    Item {
        id: dial

        x: (root.width - root.dialWidth) / 2
        y: root.headerHeight
        width: root.dialWidth
        height: root.dialHeight

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            antialiasing: true

            // Night band first: the full 24-hour track.
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.nightBandColor
                strokeWidth: root.ringWidth
                PathSvg { path: root.trackPath }
            }

            // The day arc is drawn over the night track; flat caps stop it
            // exactly on the two boundary marks.
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.dayBandColor
                strokeWidth: root.ringWidth
                PathSvg { path: root.dayArcPath }
            }

            // Neutral leaders first, so the primary day leader sits on top.
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.timeLeaderColor
                strokeWidth: 1.5
                capStyle: ShapePath.RoundCap
                PathSvg { path: root.sunriseLeaderPath }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.timeLeaderColor
                strokeWidth: 1.5
                capStyle: ShapePath.RoundCap
                PathSvg { path: root.sunsetLeaderPath }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Colors.withAlpha(Colors.onSurfaceVariant, 0.85)
                strokeWidth: 2
                capStyle: ShapePath.RoundCap
                PathSvg { path: root.nightLeaderPath }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Colors.primary
                strokeWidth: 2
                capStyle: ShapePath.RoundCap
                PathSvg { path: root.dayLeaderPath }
            }

            // Crisp bezel and hub edges.
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.bezelColor
                strokeWidth: 1
                PathSvg { path: root.outerPath }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.bezelColor
                strokeWidth: 1
                PathSvg { path: root.innerPath }
            }

            // The two solar marks divide the track into day and night.
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.boundaryColor
                strokeWidth: 1
                capStyle: ShapePath.RoundCap
                PathSvg { path: root.boundaryPath }
            }
        }

        // 24 hour marks sit just outside the bezel: a short stub every hour and
        // a longer one every six, far enough in to stay clear of the callouts.
        Repeater {
            model: 24

            delegate: Item {
                id: tick

                required property int index

                x: root.centerX
                y: root.centerY - (root.ringOuter + 5)
                width: 0
                height: root.ringOuter + 5
                transformOrigin: Item.Bottom
                rotation: tick.index * 15

                Rectangle {
                    x: -width / 2
                    y: 0
                    width: tick.index % 6 === 0 ? 1.5 : 1
                    height: tick.index % 6 === 0 ? 5 : 2.5
                    radius: width / 2
                    color: tick.index % 6 === 0 ? root.majorTickColor : root.tickColor
                }
            }
        }

        // Sun marker on the middle of the band. The card-coloured rim keeps it
        // legible on the light day band and on the dark night band alike.
        Item {
            id: sunMarker

            x: root.centerX + Math.sin(root.sunAngle * Math.PI / 180)
                * root.ringMid - width / 2
            y: root.centerY - Math.cos(root.sunAngle * Math.PI / 180)
                * root.ringMid - height / 2
            width: 20
            height: 20
            visible: root.hasSunTimes
            z: 1

            Behavior on x {
                NumberAnimation {
                    duration: Motion.move
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Motion.standardDecelerateCurve
                }
            }

            Behavior on y {
                NumberAnimation {
                    duration: Motion.move
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Motion.standardDecelerateCurve
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 24
                height: 24
                radius: width / 2
                color: root.sunHalo
            }

            // A card-coloured disc with the sun glyph reads as a punched-out
            // marker on the light day band and on the dark night band alike.
            Rectangle {
                anchors.centerIn: parent
                width: 18
                height: 18
                radius: width / 2
                color: Colors.surfaceContainerHigh

                Text {
                    anchors.centerIn: parent
                    text: Icons.lightMode
                    color: Colors.primary
                    font.family: Typography.iconFont
                    font.pixelSize: 13
                }
            }
        }

        // Current time in the hub, so the marker has an anchor in the day.
        Text {
            anchors.centerIn: parent
            text: root.nowLabel
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.titleLarge
            font.weight: Typography.weight.medium
        }

        // ── Duration callouts ─────────────────────────────────────────────
        Text {
            z: 2
            width: root.durationLabelWidth
            height: root.calloutHeight
            x: root.dayCallout.x - width / 2
            y: root.dayCallout.y - height / 2
            visible: root.hasSunTimes
            text: "Daylight " + root.dayLength
            color: Colors.primary
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: Typography.weight.medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            z: 2
            width: root.durationLabelWidth
            height: root.calloutHeight
            x: root.nightCallout.x - width / 2
            y: root.nightCallout.y - height / 2
            visible: root.hasSunTimes
            text: "Night " + root.nightLength
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            font.weight: Typography.weight.medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // ── Sunrise / sunset callouts ─────────────────────────────────────
        Text {
            z: 2
            width: root.timeLabelWidth
            height: root.calloutHeight
            x: root.sunriseCallout.x - width / 2
            y: root.sunriseCallout.y - height / 2
            visible: root.hasSunTimes
            text: root.sunrise
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            z: 2
            width: root.timeLabelWidth
            height: root.calloutHeight
            x: root.sunsetCallout.x - width / 2
            y: root.sunsetCallout.y - height / 2
            visible: root.hasSunTimes
            text: root.sunset
            color: Colors.onSurface
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelMedium
            font.weight: Typography.weight.medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
