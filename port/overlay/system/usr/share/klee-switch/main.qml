// klee dual boot: "Switch to Android" / "Switch to Recovery". The root work is done
// by systemd units (klee-switch-android / klee-reboot-recovery) that polkit
// lets the phone user start; this page only asks for confirmation.
import QtQuick 2.12
import Lomiri.Components 1.3
import io.thp.pyotherside 1.4

MainView {
    id: root
    applicationName: "klee-switch"
    width: units.gu(45)
    height: units.gu(80)

    readonly property bool recovery: Qt.application.arguments.indexOf("recovery") >= 0
    property bool asked: false
    property string status: ""

    Python {
        id: py
        Component.onCompleted: importModule("subprocess", function() {})
        function start(unit) {
            call("subprocess.run",
                 [["systemctl", "start", "--no-block", unit]],
                 function(r) {})
        }
    }

    Page {
        anchors.fill: parent
        header: PageHeader {
            title: root.recovery ? "Switch to Recovery" : "Switch to Android"
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - units.gu(6)
            spacing: units.gu(3)

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                textSize: Label.Large
                text: root.recovery
                    ? "The phone restarts into OrangeFox recovery."
                    : "The phone restarts into OrangeFox. Enter your lock screen PIN there; Axion is installed and started automatically."
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: units.gu(7)
                color: root.asked ? theme.palette.normal.negative : "#3DDC84"
                text: root.asked ? "Emin misin? Tekrar dokun"
                                 : (root.recovery ? "Switch to recovery" : "Switch to Android")
                enabled: root.status === ""
                onClicked: {
                    if (!root.asked) {
                        root.asked = true
                        return
                    }
                    root.status = "Restarting..."
                    py.start(root.recovery ? "klee-reboot-recovery.service"
                                           : "klee-switch-android.service")
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                text: "Cancel"
                visible: root.asked && root.status === ""
                onClicked: root.asked = false
            }

            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.status
            }
        }
    }
}
