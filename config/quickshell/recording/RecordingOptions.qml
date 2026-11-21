import QtQuick
import "../theme"

// Options list for the recording setup panel. Selection state and cycling
// stay in RecordingSetup; this component only renders the rows and reports
// the interactions.
Rectangle {
    id: root

    property var options: []
    property var indexes: []
    property int selectedRow: 0

    signal cycled(int row, int direction)
    signal activated(int row)

    radius: Dimensions.radius.large
    color: Colors.withAlpha(Colors.surfaceContainerLowest, 0.55)
    border.width: 1
    border.color: Colors.withAlpha(Colors.outlineVariant, 0.20)

    Column {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        Repeater {
            model: root.options

            delegate: OptionRow {
                required property var modelData
                required property int index

                title: modelData.title
                value: modelData.labels[root.indexes[index]]
                active: root.selectedRow === index
                onPrevious: root.cycled(index, -1)
                onNext: root.cycled(index, 1)
                onActivated: root.activated(index)
            }
        }
    }
}
