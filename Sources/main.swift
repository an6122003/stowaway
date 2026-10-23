import Cocoa

// Development aid: `Stowaway --dump` prints what the Accessibility API exposes
// for every menu bar item, then exits.
if CommandLine.arguments.contains("--dump") {
    MenuBarItems.dump()
    exit(0)
}

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
