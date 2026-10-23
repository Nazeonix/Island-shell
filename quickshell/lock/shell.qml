import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pam
import Quickshell.Services.UPower

// macOS-style lock screen (ext-session-lock: Hyprland, niri, sway, river, ...)
// Save as ~/.config/quickshell/lock/shell.qml and run:  qs -c lock
Scope {
    id: root

    // ---- config ----------------------------------------------------------
    property string wallpaperPath: Quickshell.env("HOME") + "/Pictures/lockscreen.jpg"
    property string avatarPath: Quickshell.env("HOME") + "/.face"
    property string username: Quickshell.env("USER") || "user"
    property string fontFamily: "Inter"
    property string iconFont: "JetBrainsMono Nerd Font"
    property bool use24h: true
    property real blurAmount: 1.0
    property real dim: 0.55
    property bool quitOnUnlock: true

    // follow the wallpaper daemon's current wallpaper when its state file exists
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell-wallpaper"
        onLoaded: { const p = text().trim(); if (p !== "") root.wallpaperPath = p; }
    }

    // ---- shared state (every monitor shows the same thing) ---------------
    property string password: ""
    property bool passwordMode: false
    property bool authenticating: false
    property string errorText: ""
    property int shakeTick: 0

    readonly property var bat: UPower.displayDevice
    property string net: "none"

    SystemClock { id: clock; precision: SystemClock.Minutes }

    function submit() {
        if (pam.active) return;
        if (password.length === 0) return;
        errorText = "";
        authenticating = true;
        if (!pam.start()) {
            authenticating = false;
            errorText = "Unable to start authentication";
        }
    }

    // ---- PAM -------------------------------------------------------------
    PamContext {
        id: pam
        user: root.username
        config: "login"      // /etc/pam.d/login; try "system-auth" if this rejects a correct password

        onPamMessage: { if (pam.responseRequired) pam.respond(root.password); }

        onCompleted: result => {
            root.authenticating = false;
            if (result === PamResult.Success) {
                root.errorText = "";
                root.password = "";
                lock.locked = false;
                if (root.quitOnUnlock) quitTimer.start();
            } else {
                root.errorText = "Incorrect password";
                root.password = "";
                root.shakeTick++;
            }
        }

        onError: {
            root.authenticating = false;
            root.errorText = "Authentication error";
        }
    }

    // give the unlock request time to reach the compositor before exiting
    Timer { id: quitTimer; interval: 250; onTriggered: Qt.quit() }

    // ---- wifi (nmcli poll) -----------------------------------------------
    Process {
        id: nm
        command: ["nmcli", "-t", "-f", "TYPE,STATE", "device", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = "none";
                text.split("\n").forEach(l => {
                    if (l === "wifi:connected") r = "wifi";
                    else if (l === "ethernet:connected" && r !== "wifi") r = "ethernet";
                });
                root.net = r;
            }
        }
    }
    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!nm.running) nm.running = true
    }

    // ---- session lock ----------------------------------------------------
    WlSessionLock {
        id: lock
        locked: true

        surface: Component {
            WlSessionLockSurface {
                id: surf
                color: "#071016"

                Item {
                    id: scene
                    anchors.fill: parent

                    // ---- background: blurred wallpaper + solid dim --------
                    Image {
                        anchors.fill: parent
                        source: "file://" + root.wallpaperPath
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blur: root.blurAmount
                            blurMax: 64
                            blurMultiplier: 1.25
                            brightness: -0.1
                            saturation: -0.1
                            autoPaddingEnabled: false
                        }
                    }
                    Rectangle { anchors.fill: parent; color: "#090f14"; opacity: root.dim }

                    // ---- top-right: battery + network ---------------------
                    Row {
                        anchors { top: parent.top; right: parent.right; topMargin: 14; rightMargin: 18 }
                        spacing: 12

                        Row {
                            visible: root.bat.isPresent
                            spacing: 5
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(root.bat.percentage * 100)
                                color: "white"; opacity: 0.8
                                font { family: root.fontFamily; pixelSize: 12; weight: Font.Medium }
                            }
                            Item {
                                width: 27; height: 12
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    width: 24; height: 12; radius: 3.5
                                    color: "transparent"
                                    border { width: 1; color: Qt.rgba(1, 1, 1, 0.7) }
                                    Rectangle {
                                        x: 2.5; anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(1, 17 * root.bat.percentage); height: 7; radius: 1.5
                                        color: root.bat.percentage <= 0.15 ? "#ff6b6b" : "white"
                                        opacity: 0.9
                                    }
                                }
                                Rectangle {
                                    x: 25; anchors.verticalCenter: parent.verticalCenter
                                    width: 2; height: 5; radius: 1
                                    color: "white"; opacity: 0.6
                                }
                            }
                            Text {
                                visible: root.bat.state === UPowerDeviceState.Charging
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\uf0e7"
                                color: "white"; opacity: 0.8
                                font { family: root.iconFont; pixelSize: 12 }
                            }
                        }

                        Text {
                            visible: root.net !== "none"
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.net === "ethernet" ? "\uf0e8" : "\uf1eb"
                            color: "white"; opacity: 0.8
                            font { family: root.iconFont; pixelSize: 15 }
                        }
                    }

                    // ---- date + time -------------------------------------
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height * 0.1
                        spacing: -6
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDate(clock.date, "dddd, MMMM d")
                            color: "white"; opacity: 0.75
                            font { family: root.fontFamily; pixelSize: 22; weight: Font.Medium }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatTime(clock.date, root.use24h ? "HH:mm" : "h:mm")
                            color: "white"; opacity: 0.95
                            font { family: root.fontFamily; pixelSize: 124; weight: Font.DemiBold; letterSpacing: -3 }
                        }
                    }

                    // ---- bottom: avatar, name, password -------------------
                    Column {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 72 }
                        spacing: 12

                        ClippingRectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 68; height: 68; radius: 34
                            color: Qt.rgba(1, 1, 1, 0.2)
                            Image {
                                id: avatarImg
                                anchors.fill: parent
                                source: "file://" + root.avatarPath
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                            Item {
                                anchors.fill: parent
                                visible: avatarImg.status !== Image.Ready
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 16; width: 17; height: 17; radius: 8.5
                                    color: "white"; opacity: 0.92
                                }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 37; width: 36; height: 20; radius: 18
                                    color: "white"; opacity: 0.92
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.username
                            color: "white"; opacity: 0.92
                            font { family: root.fontFamily; pixelSize: 17; weight: Font.Medium }
                        }

                        // prompt and password pill share one slot (no layout jump)
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 260; height: 40

                            Text {
                                anchors.centerIn: parent
                                text: "Press any key to enter password"
                                color: "white"
                                opacity: root.passwordMode ? 0 : 0.5
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                                font { family: root.fontFamily; pixelSize: 13; weight: Font.Medium }
                            }

                            Item {
                                id: field
                                anchors.fill: parent
                                opacity: root.passwordMode ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                                transform: Translate { id: shk }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: Qt.rgba(1, 1, 1, 0.16)
                                    border {
                                        width: 1
                                        color: root.errorText !== "" ? Qt.rgba(1, 0.42, 0.42, 0.7) : Qt.rgba(1, 1, 1, 0.28)
                                    }
                                }

                                TextInput {
                                    id: input
                                    anchors { fill: parent; leftMargin: 48; rightMargin: 48 }
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    color: "white"
                                    font { family: root.fontFamily; pixelSize: 20 }
                                    echoMode: TextInput.Password
                                    passwordCharacter: "•"
                                    inputMethodHints: Qt.ImhSensitiveData
                                    cursorDelegate: Item {}
                                    clip: true
                                    focus: true
                                    readOnly: root.authenticating

                                    onTextChanged: {
                                        root.password = text;
                                        if (text.length > 0) {
                                            root.passwordMode = true;
                                            root.errorText = "";
                                        }
                                    }
                                    Keys.onReturnPressed: root.submit()
                                    Keys.onEnterPressed: root.submit()
                                    Keys.onEscapePressed: {
                                        root.password = "";
                                        root.passwordMode = false;
                                        root.errorText = "";
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: input.text.length === 0
                                    text: "Enter Password"
                                    color: "white"; opacity: 0.35
                                    font { family: root.fontFamily; pixelSize: 14 }
                                }

                                // submit arrow
                                Rectangle {
                                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                    width: 28; height: 28; radius: 14
                                    color: "white"
                                    opacity: root.password.length > 0 && !root.authenticating ? 0.9 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "\uf061"
                                        color: "#0b1116"
                                        font { family: root.iconFont; pixelSize: 12 }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.submit() }
                                }
                            }
                        }

                        // status / error
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 16
                            text: root.authenticating ? "Authenticating…" : root.errorText
                            color: root.authenticating ? "white" : "#ff8585"
                            opacity: text !== "" ? 0.85 : 0
                            font { family: root.fontFamily; pixelSize: 12 }
                        }
                    }

                    // ---- behaviour ----------------------------------------
                    Connections {
                        target: root
                        function onPasswordChanged() { if (input.text !== root.password) input.text = root.password; }
                        function onShakeTickChanged() { shake.restart(); }
                    }
                    SequentialAnimation {
                        id: shake
                        NumberAnimation { target: shk; property: "x"; to: -14; duration: 50 }
                        NumberAnimation { target: shk; property: "x"; to: 14; duration: 90 }
                        NumberAnimation { target: shk; property: "x"; to: -9; duration: 80 }
                        NumberAnimation { target: shk; property: "x"; to: 5; duration: 70 }
                        NumberAnimation { target: shk; property: "x"; to: 0; duration: 50 }
                    }

                    Component.onCompleted: input.forceActiveFocus()
                }
            }
        }
    }
}
