import Cocoa

// Entry point. Kept as top-level code in a file named main.swift so this runs
// before anything else, exactly like an @main-less AppKit executable.
let app = NSApplication.shared

// Menu-bar-only app: no Dock icon even if run as a raw binary.
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
