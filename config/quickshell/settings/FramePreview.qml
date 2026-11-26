import QtQuick
import QtQuick.Layouts
import "../services"
import "../theme"

// One visual screen mock-up for the Screen frame picker. The tile draws the
// whole screen at a glance — bar, window and the frame around it — so the
// picture itself explains the mode. Both variants share the same window, bar
// and colours; only the edge treatment changes:
//
//   ring    — an even bar-coloured border on all four sides,
//   corners — the window runs into the left, right and bottom edges, with the
//             bar colour in the upper corners and black in the lower ones.
//
// Adding a mode means extending FrameService.styles and adding a drawing
// branch here next to its Frame.qml rendering.
Item {
    id: root

    property string mode: ""
    property bool selected: false

    readonly property bool hovered: previewMouse.containsMouse
    readonly property bool cornersMode: root.mode === FrameService.cornersStyle

    signal activated()

    implicitWidth: 170
    implicitHeight: body.implicitHeight + 12

    Accessible.name: FrameService.labelFor(root.mode)
    Accessible.description: FrameService.hintFor(root.mode)

    onCornersModeChanged: preview.requestPaint()

    // Selection and hover live on the whole tile, not on the miniature
    // screen: a primary outline around the picture would read as another
    // frame — exactly the thing the preview is explaining.
    Rectangle {
        id: tileBackground

        anchors.fill: parent
        radius: 12
        color: root.selected
            ? Colors.withAlpha(Colors.primary, 0.06)
            : root.hovered
                ? Colors.withAlpha(Colors.primary, 0.07)
                : "transparent"
        border.width: root.selected ? 2 : 1
        border.color: root.selected
            ? Colors.primary
            : root.hovered
                ? Colors.withAlpha(Colors.primary, 0.45)
                : Colors.withAlpha(Colors.outlineVariant, 0.28)

        Behavior on color {
            ColorAnimation {
                duration: Motion.fade
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: Motion.fade
                easing.type: Easing.Bezier
                easing.bezierCurve: Motion.standardDecelerateCurve
            }
        }
    }

    ColumnLayout {
        id: body

        anchors.fill: parent
        anchors.margins: 6
        spacing: 5

        // The screen sits in its own recess so the tile border, the screen
        // edge and the miniature frame stay three distinct things.
        Rectangle {
            id: screenBox

            Layout.fillWidth: true
            Layout.preferredHeight: 102
            color: "transparent"

            Canvas {
                id: preview

                anchors.fill: parent
                anchors.margins: 4

                // The mini-screen uses the real chrome, window and corner
                // colours, so the tiles read as the actual frame shapes.
                property color frameColor: Colors.surfaceContainerLow
                property color windowColor: Colors.surfaceContainerHighest
                property color titleColor: Colors.surfaceContainerHigh
                property color contentColor: Colors.withAlpha(Colors.onSurfaceVariant, 0.42)
                property color edgeColor: Colors.withAlpha(Colors.outlineVariant, 0.7)
                property color bottomCornerColor: Colors.frameCorner

                onFrameColorChanged: preview.requestPaint()
                onWindowColorChanged: preview.requestPaint()
                onTitleColorChanged: preview.requestPaint()
                onContentColorChanged: preview.requestPaint()
                onEdgeColorChanged: preview.requestPaint()
                onBottomCornerColorChanged: preview.requestPaint()
                onWidthChanged: preview.requestPaint()
                onHeightChanged: preview.requestPaint()

                function roundedPath(ctx, x, y, w, h, r) {
                    r = Math.max(0, Math.min(r, w / 2, h / 2));
                    ctx.beginPath();
                    ctx.moveTo(x + r, y);
                    ctx.lineTo(x + w - r, y);
                    ctx.arc(x + w - r, y + r, r, -Math.PI / 2, 0, false);
                    ctx.lineTo(x + w, y + h - r);
                    ctx.arc(x + w - r, y + h - r, r, 0, Math.PI / 2, false);
                    ctx.lineTo(x + r, y + h);
                    ctx.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI, false);
                    ctx.lineTo(x, y + r);
                    ctx.arc(x + r, y + r, r, Math.PI, Math.PI * 1.5, false);
                    ctx.closePath();
                }

                // The square screen corner minus the rounded window corner.
                // corner: 0 = top-left, 1 = top-right, 2 = bottom-left,
                // 3 = bottom-right. (boxX, boxY) is the corner of the r×r
                // square the window leaves uncovered; the arc follows the
                // window's rounded corner exactly.
                function spandrel(ctx, boxX, boxY, corner, r) {
                    ctx.beginPath();

                    if (corner === 0) {
                        // From the screen corner along the bar edge, around
                        // the quarter circle, back down the left edge.
                        ctx.moveTo(boxX, boxY);
                        ctx.lineTo(boxX + r, boxY);
                        ctx.arc(boxX + r, boxY + r, r,
                                -Math.PI / 2, Math.PI, true);
                    } else if (corner === 1) {
                        ctx.moveTo(boxX + r, boxY);
                        ctx.lineTo(boxX, boxY);
                        ctx.arc(boxX, boxY + r, r, -Math.PI / 2, 0, false);
                    } else if (corner === 2) {
                        ctx.moveTo(boxX, boxY);
                        ctx.lineTo(boxX, boxY + r);
                        ctx.lineTo(boxX + r, boxY + r);
                        ctx.arc(boxX + r, boxY, r,
                                Math.PI / 2, Math.PI, false);
                    } else {
                        ctx.moveTo(boxX, boxY + r);
                        ctx.lineTo(boxX + r, boxY + r);
                        ctx.lineTo(boxX + r, boxY);
                        ctx.arc(boxX, boxY, r, 0, Math.PI / 2, false);
                    }

                    ctx.closePath();
                }

                // Three workspace dots, a clock pill and a right-hand status
                // pill turn the top strip into a recognisable bar.
                function drawBar(ctx, w, barHeight) {
                    ctx.fillStyle = preview.contentColor;
                    const dotY = barHeight / 2;
                    for (let i = 0; i < 3; i++) {
                        ctx.beginPath();
                        ctx.arc(6 + i * 4, dotY, 1.2, 0, Math.PI * 2);
                        ctx.fill();
                    }
                    roundedPath(ctx, w / 2 - 9, dotY - 1.5, 18, 3, 1.5);
                    ctx.fill();
                    roundedPath(ctx, w - 17, dotY - 1.5, 11, 3, 1.5);
                    ctx.fill();
                }

                // A window with a title bar (three buttons) and three text
                // lines, so the surface reads as an application window rather
                // than an empty colour block.
                function drawWindow(ctx, x, y, w, h, r) {
                    preview.roundedPath(ctx, x, y, w, h, r);
                    ctx.fillStyle = preview.windowColor;
                    ctx.fill();

                    ctx.save();
                    preview.roundedPath(ctx, x, y, w, h, r);
                    ctx.clip();

                    const titleHeight = Math.min(16, Math.round(h * 0.26));
                    ctx.fillStyle = preview.titleColor;
                    ctx.fillRect(x, y, w, titleHeight);

                    const dotY = y + titleHeight / 2;
                    for (let i = 0; i < 3; i++) {
                        ctx.beginPath();
                        ctx.arc(x + 7 + i * 4.5, dotY, 1.3, 0, Math.PI * 2);
                        ctx.fillStyle = preview.contentColor;
                        ctx.fill();
                    }

                    const pad = Math.max(7, Math.round(w * 0.055));
                    const lineX = x + pad;
                    const lineY = y + titleHeight + Math.max(6, Math.round(h * 0.1));
                    const gap = 3;
                    ctx.fillStyle = preview.contentColor;
                    const widths = [0.46, 0.34, 0.24];
                    for (let i = 0; i < widths.length; i++) {
                        const lineW = Math.max(14, Math.round(w * widths[i]));
                        preview.roundedPath(ctx, lineX, lineY + i * (gap + 3),
                                            lineW, 3, 1.5);
                        ctx.fill();
                    }
                    ctx.restore();

                    // Hairline outline keeps the window edge crisp against
                    // the black corner wedges and the frame.
                    preview.roundedPath(ctx, x + 0.5, y + 0.5, w - 1, h - 1, r);
                    ctx.strokeStyle = preview.edgeColor;
                    ctx.lineWidth = 1;
                    ctx.stroke();
                }

                onPaint: {
                    const ctx = preview.getContext("2d");
                    ctx.reset();

                    const w = preview.width;
                    const h = preview.height;
                    const barHeight = Math.max(10, Math.round(h * 0.11));
                    const radius = 12;
                    const margin = Math.max(8, Math.round(w * 0.06));

                    ctx.save();
                    ctx.beginPath();
                    ctx.rect(0, 0, w, h);
                    ctx.clip();

                    // The desktop. Both variants leave it almost fully
                    // covered, but it is the colour the corners reveal.
                    ctx.fillStyle = preview.windowColor;
                    ctx.fillRect(0, 0, w, h);

                    // Bar strip. In the ring style the frame below it uses
                    // the same colour, so bar and frame read as one surface.
                    ctx.fillStyle = preview.frameColor;
                    ctx.fillRect(0, 0, w, barHeight);

                    if (root.cornersMode) {
                        preview.drawWindow(ctx, 0, barHeight, w, h - barHeight,
                                           radius);

                        // Upper spandrels continue the bar, lower ones are
                        // black — the signature of this mode.
                        ctx.fillStyle = preview.frameColor;
                        preview.spandrel(ctx, 0, barHeight, 0, radius);
                        ctx.fill();
                        preview.spandrel(ctx, w - radius, barHeight, 1, radius);
                        ctx.fill();

                        ctx.fillStyle = preview.bottomCornerColor;
                        preview.spandrel(ctx, 0, h - radius, 2, radius);
                        ctx.fill();
                        preview.spandrel(ctx, w - radius, h - radius, 3, radius);
                        ctx.fill();
                    } else {
                        // Full frame: the bar colour fills every outer gap.
                        ctx.fillStyle = preview.frameColor;
                        ctx.fillRect(0, barHeight, w, h - barHeight);

                        preview.drawWindow(ctx, margin, barHeight + margin,
                                           w - margin * 2,
                                           h - barHeight - margin * 2, radius);
                    }

                    preview.drawBar(ctx, w, barHeight);

                    // Physical screen edge, so “flush” and “inset” read at a
                    // glance. The display itself has square corners; only the
                    // bezel around it is rounded.
                    ctx.strokeStyle = preview.edgeColor;
                    ctx.lineWidth = 1;
                    ctx.strokeRect(0.5, 0.5, w - 1, h - 1);

                    ctx.restore();
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            Text {
                id: selectedCheck

                visible: root.selected
                text: Icons.check
                color: Colors.primary
                font.family: Typography.iconFont
                font.pixelSize: Typography.size.bodyMedium
            }

            Text {
                text: FrameService.labelFor(root.mode)
                color: root.selected ? Colors.primary : Colors.onSurface
                font.family: Typography.barFont
                font.pixelSize: Typography.size.bodyMedium
                font.weight: Typography.weight.medium
                elide: Text.ElideRight
            }

            // Balances the check on the left, so the mode name itself stays
            // exactly centred over the caption instead of shifting right.
            Item {
                visible: root.selected
                Layout.preferredWidth: selectedCheck.implicitWidth
                Layout.preferredHeight: 1
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: FrameService.hintFor(root.mode)
            color: Colors.onSurfaceVariant
            font.family: Typography.barFont
            font.pixelSize: Typography.size.labelSmall
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: previewMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
