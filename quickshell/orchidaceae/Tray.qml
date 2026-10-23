import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Row {
    visible: SystemTray.items.values.length > 0
    spacing: 8

    Repeater {
        model: SystemTray.items
        delegate: Item {
            id: d
            required property var modelData
            implicitWidth: 20
            implicitHeight: 20

            IconImage { anchors.fill: parent; source: d.modelData.icon }

            QsMenuAnchor {
                id: menu
                menu: d.modelData.menu
                anchor.item: d
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: m => {
                    if (m.button === Qt.LeftButton) {
                        if (d.modelData.onlyMenu && d.modelData.hasMenu) menu.open();
                        else d.modelData.activate();
                    }
                    else if (m.button === Qt.MiddleButton) d.modelData.secondaryActivate();
                    else if (d.modelData.hasMenu) menu.open();
                }
            }
        }
    }
}
