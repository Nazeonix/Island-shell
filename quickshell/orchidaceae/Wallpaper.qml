pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wallpaper daemon state (stop swww / hyprpaper / swaybg first).
//   qs ipc call wallpaper set <path> | next | prev | random | picker | toggleSlideshow | reload | get
Singleton {
    id: root

    // ---- config ----------------------------------------------------------
    property string dir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    property bool slideshow: false
    property int slideshowMinutes: 15
    readonly property string stateFile:
        (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell-wallpaper"

    // ---- state -----------------------------------------------------------
    property var files: []
    property string current: ""
    property bool ready: false
    property bool pickerOpen: false       // thumbnail card (WallpaperSwitcher)
    readonly property int index: files.indexOf(current)

    function set(path) {
        if (!path) return;
        if (path.startsWith("~/")) path = Quickshell.env("HOME") + path.slice(1);
        current = path;
    }
    function next() {
        const n = files.length;
        if (n === 0) return;
        set(files[(index + 1 + n) % n]);
    }
    function prev() {
        const n = files.length;
        if (n === 0) return;
        set(files[(index - 1 + n) % n]);
    }
    function random() {
        const n = files.length;
        if (n === 0) return;
        if (n === 1) { set(files[0]); return; }
        let i = Math.floor(Math.random() * n);
        if (i === index) i = (i + 1) % n;
        set(files[i]);
    }
    function reload() { scan.running = true }

    // drag & drop: copy images into `dir` (never overwrites) and switch to the first one
    property string pendingDest: ""
    function importFiles(paths) {
        const ok = paths.filter(p => /\.(jpe?g|png|webp|bmp)$/i.test(p));
        if (ok.length === 0 || importer.running) return;
        pendingDest = dir + "/" + ok[0].split("/").pop();
        importer.command = ["sh", "-c", 'd="$1"; shift; mkdir -p "$d" && cp -n -- "$@" "$d"/', "sh", dir].concat(ok);
        importer.running = true;
    }
    Process {
        id: importer
        onExited: code => { if (code === 0) root.set(root.pendingDest); root.reload(); }
    }

    // ---- persistence -----------------------------------------------------
    FileView {
        id: store
        path: root.stateFile
        onLoaded: { root.current = text().trim(); root.ready = true; }
        onLoadFailed: root.ready = true
    }
    onCurrentChanged: if (ready && current !== "") store.setText(current)

    // ---- scan the wallpaper folder ---------------------------------------
    Process {
        id: scan
        running: true
        command: ["find", "-L", root.dir, "-type", "f", "(",
                  "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png",
                  "-o", "-iname", "*.webp", "-o", "-iname", "*.bmp", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.files = text.split("\n").filter(l => l !== "").sort();
                // nothing chosen yet (first run): start with the first image
                if (root.current === "" && root.files.length > 0 && root.ready) root.set(root.files[0]);
            }
        }
    }
    // state file may load after the scan finished
    onReadyChanged: if (ready && current === "" && files.length > 0) set(files[0])

    // ---- slideshow -------------------------------------------------------
    Timer {
        interval: root.slideshowMinutes * 60000
        running: root.slideshow && root.files.length > 1
        repeat: true
        onTriggered: root.next()
    }

    IpcHandler {
        target: "wallpaper"
        function set(path: string): void { root.set(path) }
        function next(): void { root.next() }
        function prev(): void { root.prev() }
        function random(): void { root.random() }
        function toggleSlideshow(): void { root.slideshow = !root.slideshow }
        function reload(): void { root.reload() }
        function picker(): void { root.pickerOpen = !root.pickerOpen }
        function get(): string { return root.current }
    }
}
