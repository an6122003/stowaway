import Cocoa
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

/// Reaches menu bar items that macOS has no room to draw.
///
/// The first version of this app put its own control in the menu bar, which on
/// a bar that is already overflowing lands in the overflow — unreachable, and
/// impossible to drag somewhere better. So by default Stowaway claims no bar
/// space at all: the keyboard opens it, and the list it shows is vertical,
/// where the screen has room to spare.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private enum Defaults {
        static let showsStatusItem = "ShowsStatusItem"
        static let hideGroupEnabled = "HideGroupEnabled"
        static let hidden = "ItemsHidden"
        static let hasLaunched = "HasLaunchedBefore"
        static let warnedAboutRoom = "WarnedAboutRoom"
        static let keepsSystemItems = "KeepsSystemItems"
        static let learnedLeftEdge = "LearnedLeftEdge"
        static let learnedRightmost = "LearnedRightmostThirdParty"
        static let widthTrim = "HideWidthTrim"
        static let screenWidth = "LearnedScreenWidth"
        static let spacerPosition = "SpacerPreferredPosition"
    }

    /// Wide enough to consume any menu bar; macOS clamps the drawn width.
    private static let expandedWidth: CGFloat = 10_000
    private static let gapWidth: CGFloat = 10
    static let hotKeyDisplay = "⌃⌥⌘B"

    /// Optional, off by default: the control in the bar.
    private var toggleItem: NSStatusItem?
    /// Optional, off by default: the width lever that hides a group.
    private var spacerItem: NSStatusItem?

    private var hotKey: GlobalHotKey?
    private var listedItems: [MenuBarItems.Item] = []
    /// Scanning every app costs IPC, so the list is kept warm in the
    /// background and the menu renders from the cache instantly.
    private var cachedItems: [MenuBarItems.Item] = []
    private var refreshTimer: Timer?
    private var restoreTimer: Timer?
    /// Left edge of the status area, learned while everything is on show.
    private var statusAreaLeftEdge: CGFloat = 0

    /// Layout and trust diagnostics, off unless explicitly enabled.
    private var isDebugging: Bool { UserDefaults.standard.bool(forKey: "DebugDiagnostics") }
    private var lastReveal = Date.distantPast
    private var spacerPositionAttempts = 0

    private var keepsSystemItems: Bool {
        get { UserDefaults.standard.object(forKey: Defaults.keepsSystemItems) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.keepsSystemItems) }
    }

    private var showsStatusItem: Bool {
        get { UserDefaults.standard.object(forKey: Defaults.showsStatusItem) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.showsStatusItem) }
    }

    private var hideGroupEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Defaults.hideGroupEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.hideGroupEnabled) }
    }

    private var isHidden: Bool {
        get { UserDefaults.standard.object(forKey: Defaults.hidden) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.hidden) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_B),
                              modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            self?.showItemList()
        }
        NSLog("Stowaway: shortcut %@ %@", AppDelegate.hotKeyDisplay, hotKey == nil ? "UNAVAILABLE" : "registered")

        rebuildStatusItems()
        startRefreshing()
        showWelcomeIfNeeded()
    }

    private func startRefreshing() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        // Recorded so the state can be inspected from outside: a process
        // launched from a terminal inherits that terminal's TCC identity, so
        // asking the question there answers it for the wrong app.
        let trusted = MenuBarItems.isTrusted
        if isDebugging { UserDefaults.standard.set(trusted, forKey: "DiagnosticTrusted") }
        guard trusted else { return }
        DispatchQueue.global(qos: .utility).async {
            let items = MenuBarItems.all()
            DispatchQueue.main.async {
                self.cachedItems = items
                self.learnGeometry(from: items)
                if self.isDebugging { UserDefaults.standard.set(items.count, forKey: "DiagnosticItemCount") }
                self.calibrateSpacerSlot(with: items)
                self.calibrateHiding(with: items)
                if self.isHidden, self.hideGroupEnabled, self.keepsSystemItems,
                   self.spacerItem?.length != self.hidingWidth() {
                    self.applyHideState()
                }
                if self.isDebugging { self.writeLayoutDiagnostic(items) }
            }
        }
    }

    /// Opening the app again from Spotlight or Finder brings up the list, so it
    /// is reachable even with no icon and no working shortcut.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showItemList()
        return true
    }

    // MARK: - Optional bar presence

    /// Status item placement is steerable through an undocumented default,
    /// where a *lower* value sits further right. Pinning our two items to the
    /// right edge is what makes hiding work: the spacer can only push items
    /// that sit to its left, so it has to be right of everything else.
    private func pinToRightEdge() {
        UserDefaults.standard.set(0, forKey: "NSStatusItem Preferred Position StowawayToggle")
        // The spacer belongs between the third-party icons and Apple's, so that
        // expanding it clears the former while the latter — being to its right
        // — do not move at all. Its slot is found by observation below.
        let stored = UserDefaults.standard.object(forKey: Defaults.spacerPosition) as? Double ?? 320
        UserDefaults.standard.set(stored, forKey: "NSStatusItem Preferred Position StowawaySpacer")
    }

    /// Nudges the spacer's slot until it sits in the gap between the two
    /// clusters. Position values are an opaque sort key, so the only way to
    /// land in the gap is to try, measure, and correct.
    private func calibrateSpacerSlot(with items: [MenuBarItems.Item]) {
        guard hideGroupEnabled, keepsSystemItems, !isHidden,
              spacerPositionAttempts < 8,
              Date().timeIntervalSince(lastReveal) > 3,
              let spacerX = spacerItem?.button?.window?.frame.minX else { return }

        let onScreen = items.filter { $0.position.x > 0 }
        let thirdParty = onScreen.filter { !$0.isSystemItem }
        guard let lastThirdParty = thirdParty.map(\.maxX).max() else { return }
        let systemRightOfThem = onScreen.filter { $0.isSystemItem && $0.position.x >= lastThirdParty }
        guard let firstSystem = systemRightOfThem.map(\.position.x).min(),
              firstSystem > lastThirdParty else { return }

        let target = (lastThirdParty + firstSystem) / 2
        let error = spacerX - target
        guard abs(error) > 18 else { return }

        // Measured slope: roughly 0.8pt of travel per unit of position, and a
        // larger value sits further left.
        let stored = UserDefaults.standard.object(forKey: Defaults.spacerPosition) as? Double ?? 320
        let adjusted = max(0, min(stored + Double(error) * 1.25, 100_000))
        UserDefaults.standard.set(adjusted, forKey: Defaults.spacerPosition)
        spacerPositionAttempts += 1

        if let spacerItem { NSStatusBar.system.removeStatusItem(spacerItem) }
        spacerItem = nil
        rebuildStatusItems()
    }

    private func rebuildStatusItems() {
        pinToRightEdge()
        if showsStatusItem, toggleItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "StowawayToggle"
            item.button?.target = self
            item.button?.action = #selector(handleToggleClick)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let image = NSImage(systemSymbolName: "ellipsis.rectangle", accessibilityDescription: "Menu bar items")
                ?? NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Menu bar items")
            image?.isTemplate = true
            item.button?.image = image
            toggleItem = item
            verifyIconIsVisible()
        } else if !showsStatusItem, let toggleItem {
            NSStatusBar.system.removeStatusItem(toggleItem)
            self.toggleItem = nil
        }

        if hideGroupEnabled, spacerItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: AppDelegate.gapWidth)
            item.autosaveName = "StowawaySpacer"
            item.button?.image = dividerImage()
            spacerItem = item
        } else if !hideGroupEnabled, let spacerItem {
            NSStatusBar.system.removeStatusItem(spacerItem)
            self.spacerItem = nil
        }
        applyHideState()
    }

    /// The bar may have no room left for our own icon — the very problem this
    /// app exists for. Our button's window tells us: off-screen items sit at a
    /// large negative x.
    private func verifyIconIsVisible() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.showsStatusItem,
                  let frame = self.toggleItem?.button?.window?.frame,
                  let screen = NSScreen.main else { return }

            let visible = frame.minX >= 0 && frame.maxX <= screen.frame.maxX
            guard !visible, !UserDefaults.standard.bool(forKey: Defaults.warnedAboutRoom) else { return }
            UserDefaults.standard.set(true, forKey: Defaults.warnedAboutRoom)

            let alert = NSAlert()
            alert.messageText = "There is no room for Stowaway's icon"
            alert.informativeText = [
                "Your menu bar is full, so macOS has nowhere to draw Stowaway's own icon — the same thing that happens to your other icons.",
                "Press \(AppDelegate.hotKeyDisplay) to open the list instead. It works whether or not the icon is visible.",
                "To make room: hold Command and drag an icon you rarely use toward the left, or quit a menu bar app.",
            ].joined(separator: "\n\n")
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open the List Now")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn { self.showItemList() }
        }
    }

    private func dividerImage() -> NSImage? {
        let image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Divider")
        image?.isTemplate = true
        return image
    }

    private func applyHideState() {
        guard let spacerItem else { return }
        let collapsed = hideGroupEnabled && isHidden
        spacerItem.length = collapsed ? hidingWidth() : AppDelegate.gapWidth
        // While expanded the button is hundreds of points wide, so its glyph
        // would be drawn marooned in the middle of the gap.
        spacerItem.button?.image = collapsed ? nil : dividerImage()
        // While expanded the spacer overlaps the whole bar, so it must not
        // swallow clicks meant for the app menus underneath.
        spacerItem.button?.window?.ignoresMouseEvents = collapsed
    }

    /// Expanding the spacer shifts everything to its left by the same amount,
    /// so the width decides how many items fall off the left edge. Pushing
    /// just past the last third-party item leaves Apple's indicators on screen,
    /// merely shifted along.
    private func hidingWidth() -> CGFloat {
        guard keepsSystemItems else { return AppDelegate.expandedWidth }

        // Measured while everything was on show and remembered since: once the
        // items are pushed away their positions say nothing useful.
        let leftEdge = UserDefaults.standard.double(forKey: Defaults.learnedLeftEdge)
        let rightmost = UserDefaults.standard.double(forKey: Defaults.learnedRightmost)
        guard leftEdge > 0, rightmost > leftEdge else { return AppDelegate.expandedWidth }

        // The applied shift runs wider than the requested length by a layout
        // margin, so a trim is kept and tuned against what actually happens.
        let trim = CGFloat(UserDefaults.standard.double(forKey: Defaults.widthTrim))
        let distance = CGFloat(rightmost - leftEdge) + 12 - trim
        return max(AppDelegate.gapWidth, min(distance, AppDelegate.expandedWidth))
    }

    /// Widens the push until no third-party icon is left on screen.
    ///
    /// Only items to the *left* of the spacer move, and Apple's main
    /// indicators sit to its right, so over-pushing cannot cost them anything —
    /// which makes this a one-directional search rather than a balancing act.
    /// Control Center does shuffle its transient modules (Now Playing, Focus)
    /// to the left on its own; those travel with the third-party icons and
    /// cannot be kept without keeping everything.
    private func calibrateHiding(with items: [MenuBarItems.Item]) {
        guard isHidden, hideGroupEnabled, keepsSystemItems else { return }
        guard Date().timeIntervalSince(lastReveal) > 3 else { return }
        let edge = drawableLeftEdge
        guard edge > 0 else { return }

        let spacerRight = (spacerItem?.button?.window?.frame.maxX) ?? .greatestFiniteMagnitude
        let stray = items.contains { !$0.isSystemItem && $0.position.x < spacerRight && $0.maxX > edge }
        guard stray else { return }

        let trim = UserDefaults.standard.double(forKey: Defaults.widthTrim)
        UserDefaults.standard.set(max(trim - 10, -400), forKey: Defaults.widthTrim)
    }

    /// Where drawable menu bar actually begins.
    ///
    /// On a notched display macOS reports the usable region beside the notch,
    /// which is authoritative: anything left of it is behind the notch and
    /// invisible, however healthy its coordinates look. Inferring this edge
    /// from the leftmost icon was wrong — on this Mac items sit at x=860 while
    /// the bar only starts at 948, which is exactly why those icons were
    /// unreachable in the first place.
    private var drawableLeftEdge: CGFloat {
        if let area = NSScreen.main?.auxiliaryTopRightArea, area.width > 0 {
            return area.minX
        }
        let learned = CGFloat(UserDefaults.standard.double(forKey: Defaults.learnedLeftEdge))
        return learned > 0 ? learned : 0
    }

    /// Records the geometry needed to hide precisely. Only valid while the bar
    /// is intact, so it is captured whenever nothing is pushed away.
    private func learnGeometry(from items: [MenuBarItems.Item]) {
        guard !isHidden || !hideGroupEnabled else { return }
        // A reveal is momentary and the bar re-flows for a beat afterwards;
        // measuring during it reads a left edge that is too far right.
        guard Date().timeIntervalSince(lastReveal) > 3 else { return }

        let onScreen = items.filter { $0.position.x > 0 }
        let thirdParty = onScreen.filter { !$0.isSystemItem }
        guard let leftEdge = onScreen.map(\.position.x).min(),
              let rightmost = thirdParty.map(\.maxX).max(),
              thirdParty.count >= 2, rightmost > leftEdge else { return }

        // Only a fallback now, for displays with no notch to ask about.
        let defaults = UserDefaults.standard
        let storedEdge = defaults.double(forKey: Defaults.learnedLeftEdge)
        let bestEdge = storedEdge > 0 ? min(storedEdge, Double(leftEdge)) : Double(leftEdge)
        statusAreaLeftEdge = CGFloat(bestEdge)
        defaults.set(bestEdge, forKey: Defaults.learnedLeftEdge)
        defaults.set(Double(rightmost), forKey: Defaults.learnedRightmost)
    }

    @objc private func handleToggleClick() {
        NSApp.currentEvent?.type == .rightMouseUp ? showSettings() : showItemList()
    }

    /// Development aid: the real geometry of the bar, which is the only way to
    /// know where our divider sits relative to everyone else.
    private func writeLayoutDiagnostic(_ items: [MenuBarItems.Item]) {
        var lines = ["hidden=\(isHidden) screen=\(NSScreen.main?.frame.width ?? 0)"]
        if let frame = toggleItem?.button?.window?.frame {
            lines.append(String(format: "  Stowaway toggle   x=%7.0f w=%4.0f", frame.minX, frame.width))
        }
        if let frame = spacerItem?.button?.window?.frame {
            lines.append(String(format: "  Stowaway spacer   x=%7.0f w=%4.0f", frame.minX, frame.width))
        }
        for item in items.sorted(by: { $0.position.x < $1.position.x }) {
            lines.append(String(format: "  %-28@ x=%7.0f w=%4.0f", item.label as NSString, item.position.x, item.size.width))
        }
        try? lines.joined(separator: "\n").write(toFile: (NSTemporaryDirectory() as NSString).appendingPathComponent("stowaway-layout.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - The vertical list

    @objc private func showItemList() {
        let menu = NSMenu()

        guard MenuBarItems.isTrusted else {
            let explain = NSMenuItem(title: "Allow Stowaway to list your menu bar items…",
                                     action: #selector(requestAccessibility), keyEquivalent: "")
            explain.target = self
            menu.addItem(explain)
            let why = NSMenuItem(title: "Needs Accessibility permission — you grant it in System Settings",
                                 action: nil, keyEquivalent: "")
            why.isEnabled = false
            menu.addItem(why)
            menu.addItem(.separator())
            appendSettingsEntry(to: menu)
            popUp(menu)
            return
        }

        // Render from the warm cache; a fresh scan runs behind the menu.
        listedItems = cachedItems.isEmpty ? MenuBarItems.all() : cachedItems
        refresh()
        if listedItems.isEmpty {
            let empty = NSMenuItem(title: "No menu bar items found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let offScreen = listedItems.filter(\.isOffScreen).count
            let header = NSMenuItem(
                title: offScreen > 0
                    ? "\(listedItems.count) items · \(offScreen) with no room in the bar"
                    : "\(listedItems.count) menu bar items",
                action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())

            for (index, item) in listedItems.enumerated() {
                let entry = NSMenuItem(title: item.label, action: #selector(openItem(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = index
                if let subtitle = item.subtitle, #available(macOS 14.4, *) {
                    entry.subtitle = subtitle
                }
                if let icon = item.icon {
                    entry.image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                        icon.draw(in: rect)
                        return true
                    }
                }
                if item.isOffScreen { entry.toolTip = "Off-screen — the bar has no room to draw it" }
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        appendSettingsEntry(to: menu)
        popUp(menu)
    }

    @objc private func openItem(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, index < listedItems.count else { return }
        let item = listedItems[index]

        // An item we pushed off-screen would open its menu nowhere visible, so
        // bring the group back, press it, then tidy up again shortly after.
        let wasHidden = hideGroupEnabled && isHidden
        if wasHidden {
            lastReveal = Date()
            isHidden = false
            applyHideState()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            MenuBarItems.press(item)
            guard wasHidden else { return }
            self.scheduleRestore(after: item)
        }
    }

    /// Anchored to the screen, not to a status item: the whole point is that
    /// our own icon may have nowhere to live.
    private func popUp(_ menu: NSMenu) {
        if let button = toggleItem?.button, button.window?.frame.minX ?? -1 >= 0 {
            toggleItem?.menu = menu
            button.performClick(nil)
            toggleItem?.menu = nil
            return
        }
        guard let screen = NSScreen.main else { return }
        let point = NSPoint(x: screen.frame.maxX - 340, y: screen.frame.maxY - 26)
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    // MARK: - Settings

    private func appendSettingsEntry(to menu: NSMenu) {
        if hideGroupEnabled {
            let state = NSMenuItem(title: isHidden ? "Show Other Icons in the Bar" : "Hide Other Icons",
                                   action: #selector(toggleHidden), keyEquivalent: "b")
            state.target = self
            state.keyEquivalentModifierMask = [.control, .option, .command]
            menu.addItem(state)
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit Stowaway", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func showSettings() {
        let menu = NSMenu()

        if !MenuBarItems.isTrusted {
            let permission = NSMenuItem(title: "Allow Listing Menu Bar Items…",
                                        action: #selector(requestAccessibility), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
            menu.addItem(.separator())
        }

        let icon = NSMenuItem(title: "Show Stowaway's Own Icon", action: #selector(toggleStatusItem), keyEquivalent: "")
        icon.target = self
        icon.state = showsStatusItem ? .on : .off
        icon.toolTip = "Off by default so Stowaway costs no menu bar space"
        menu.addItem(icon)

        let group = NSMenuItem(title: "Hide Other Icons", action: #selector(toggleHideGroup), keyEquivalent: "")
        group.target = self
        group.state = hideGroupEnabled ? .on : .off
        group.toolTip = "Pushes every other menu bar icon off the bar; reach them from Stowaway's list"
        menu.addItem(group)

        if hideGroupEnabled {
            let state = NSMenuItem(title: isHidden ? "Show Hidden Group" : "Hide Group",
                                   action: #selector(toggleHidden), keyEquivalent: "")
            state.target = self
            menu.addItem(state)
        }

        let keep = NSMenuItem(title: "Keep Wi-Fi, Battery and Clock Visible",
                              action: #selector(toggleKeepsSystemItems), keyEquivalent: "")
        keep.target = self
        keep.state = keepsSystemItems ? .on : .off
        keep.toolTip = "Hides only third-party icons; Apple's own indicators stay on screen"
        menu.addItem(keep)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let help = NSMenuItem(title: "How Stowaway Works…", action: #selector(showGuide), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        menu.addItem(NSMenuItem(title: "Quit Stowaway", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        popUp(menu)
    }

    @objc private func toggleStatusItem() {
        showsStatusItem.toggle()
        rebuildStatusItems()
    }

    @objc private func toggleHideGroup() {
        hideGroupEnabled.toggle()
        if !hideGroupEnabled { isHidden = false }
        rebuildStatusItems()
    }

    @objc private func toggleKeepsSystemItems() {
        keepsSystemItems.toggle()
        applyHideState()
    }

    @objc private func toggleHidden() {
        isHidden.toggle()
        applyHideState()
    }

    /// Watches the item you opened and tucks the bar away again the moment its
    /// menu closes, rather than leaving everything on show for a fixed spell.
    private func scheduleRestore(after item: MenuBarItems.Item) {
        restoreTimer?.invalidate()
        let deadline = Date().addingTimeInterval(30)
        restoreTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self, self.hideGroupEnabled else { timer.invalidate(); return }

            var selected: CFTypeRef?
            AXUIElementCopyAttributeValue(item.element, kAXSelectedAttribute as CFString, &selected)
            let stillOpen = (selected as? Bool) ?? false
            guard !stillOpen || Date() > deadline else { return }

            timer.invalidate()
            self.restoreTimer = nil
            self.isHidden = true
            self.applyHideState()
        }
    }

    @objc private func requestAccessibility() {
        MenuBarItems.requestPermission()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Guidance

    private func showWelcomeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Defaults.hasLaunched) else { return }
        UserDefaults.standard.set(true, forKey: Defaults.hasLaunched)
        showGuide()
    }

    @objc private func showGuide() {
        let alert = NSAlert()
        alert.messageText = "Click Stowaway's icon to see every menu bar item"
        alert.informativeText = [
            "Stowaway pins one icon to the right edge of your menu bar and pushes the other icons off it, so the bar stops overflowing.",
            "Click Stowaway's icon — or press \(AppDelegate.hotKeyDisplay) — for a vertical list of every item, hidden ones included. Click a row to open that app's menu; Stowaway brings the bar back for a moment so the menu has somewhere to appear.",
            MenuBarItems.isTrusted
                ? "Accessibility permission is granted, so the list is ready."
                : "The list needs Accessibility permission, which only you can grant: the first time you open the list, pick “Allow Stowaway to list your menu bar items” and enable Stowaway under Privacy & Security → Accessibility.",
            "Opening Stowaway again from Spotlight also brings up the list, in case the shortcut is taken by another app.",
        ].joined(separator: "\n\n")
        alert.addButton(withTitle: "Got It")
        if !MenuBarItems.isTrusted { alert.addButton(withTitle: "Grant Permission…") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { MenuBarItems.requestPermission() }
    }
}
