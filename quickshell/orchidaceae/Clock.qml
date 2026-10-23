import QtQuick
import Quickshell

Text {
    SystemClock { id: clk; precision: SystemClock.Minutes }
    text: Qt.formatDateTime(clk.date, "HH:mm")
    color: Theme.foreground
    font { family: Theme.fontFamily; pixelSize: 15 }
}
