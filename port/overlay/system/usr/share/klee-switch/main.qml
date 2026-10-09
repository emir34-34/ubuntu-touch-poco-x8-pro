// klee dual boot: "Android'e Geç" / "Recovery'ye Geç". The root work is done
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
            title: root.recovery ? "Recovery'ye Geç" : "Android'e Geç"
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
                    ? "Telefon OrangeFox recovery ile yeniden başlar."
                    : "Telefon OrangeFox'a yeniden başlar. Orada ekran kilidi PIN'ini gir, Axion otomatik kurulup açılır."
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: units.gu(7)
                color: root.asked ? theme.palette.normal.negative : "#3DDC84"
                text: root.asked ? "Emin misin? Tekrar dokun"
                                 : (root.recovery ? "Recovery'ye geç" : "Android'e geç")
                enabled: root.status === ""
                onClicked: {
                    if (!root.asked) {
                        root.asked = true
                        return
                    }
                    root.status = "Yeniden başlatılıyor..."
                    py.start(root.recovery ? "klee-reboot-recovery.service"
                                           : "klee-switch-android.service")
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                text: "Vazgeç"
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
