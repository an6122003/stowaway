import Cocoa
import ApplicationServices

/// The other apps' menu bar items, read through the Accessibility API.
///
/// There is no public way to *move* another app's status item into our own
/// window, but there is a way to find it and to press it. That is enough to
/// list every item vertically — where there is no shortage of room — and act on
/// the one you pick.
enum MenuBarItems {

    struct Item {
        let appName: String
        let bundleIdentifier: String?
        let icon: NSImage?
        let title: String?
        let element: AXUIElement
        /// Screen position of the real item. Negative or beyond the screen
        /// means macOS has nowhere to draw it.
        let position: CGPoint
        let size: CGSize

        var isOffScreen: Bool {
            let width = NSScreen.main?.frame.width ?? 0
            return position.x < 0 || position.x > width
        }

        /// What the row should say: the item's own label where it has one,
        /// falling back to the app that owns it.
        var label: String { title ?? appName }
        var subtitle: String? { title == nil ? nil : appName }

        /// Collapses the many identical rows a single agent can publish.
        var identity: String { "\(appName)|\(title ?? "")" }

        /// Apple's own indicators — Wi-Fi, battery, clock, Spotlight, input
        /// source. Worth keeping on screen even when the rest is tucked away.
        var isSystemItem: Bool { bundleIdentifier?.hasPrefix("com.apple.") ?? false }

        /// Right edge in screen coordinates.
        var maxX: CGFloat { position.x + size.width }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system's own permission dialog, which deep-links to the
    /// Accessibility pane. Granting is the user's call, not ours.
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Each attribute read is an IPC round-trip, and an unresponsive app would
    /// otherwise block for the default timeout — several seconds — so every
    /// request is capped and the apps are scanned in parallel.
    private static let messagingTimeout: Float = 0.15

    /// Apps found to own menu bar items, and every app already examined.
    /// Most processes have no extras and answering that question costs a full
    /// timeout each, so after the first pass only the owners and anything newly
    /// launched are re-scanned.
    private static var ownerPIDs: Set<pid_t> = []
    private static var examinedPIDs: Set<pid_t> = []
    private static let registry = NSLock()

    static func all() -> [Item] {
        guard isTrusted else { return [] }

        let running = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier > 0 && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }

        registry.lock()
        let owners = ownerPIDs
        let examined = examinedPIDs
        registry.unlock()

        let apps = examined.isEmpty ? running : running.filter {
            owners.contains($0.processIdentifier) || !examined.contains($0.processIdentifier)
        }

        let lock = NSLock()
        var result: [Item] = []

        var scannedOwners: Set<pid_t> = []
        if !apps.isEmpty {
            DispatchQueue.concurrentPerform(iterations: apps.count) { index in
                let app = apps[index]
                let found = items(of: app)
                lock.lock()
                if !found.isEmpty {
                    result.append(contentsOf: found)
                    scannedOwners.insert(app.processIdentifier)
                }
                lock.unlock()
            }
        }

        registry.lock()
        examinedPIDs.formUnion(apps.map(\.processIdentifier))
        ownerPIDs.formUnion(scannedOwners)
        // An app that stopped vending items should not be scanned forever.
        ownerPIDs.subtract(apps.map(\.processIdentifier).filter { !scannedOwners.contains($0) })
        let liveePIDs = Set(running.map(\.processIdentifier))
        examinedPIDs.formIntersection(liveePIDs)
        ownerPIDs.formIntersection(liveePIDs)
        registry.unlock()

        // One row per distinct item: agents like Control Center publish a
        // status item for every module they own, including ones switched off,
        // which arrive unnamed and zero-width.
        var seen = Set<String>()
        return result
            .sorted { $0.position.x < $1.position.x }
            .filter { seen.insert($0.identity).inserted }
    }

    private static func items(of app: NSRunningApplication) -> [Item] {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)

        var extras: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, "AXExtrasMenuBar" as CFString, &extras) == .success,
              let extrasElement = extras else { return [] }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(extrasElement as! AXUIElement,
                                            kAXChildrenAttribute as CFString, &children) == .success,
              let elements = children as? [AXUIElement] else { return [] }

        return elements.compactMap { element in
            AXUIElementSetMessagingTimeout(element, messagingTimeout)

            var size = CGSize.zero
            var sizeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
               let sizeValue {
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            }
            // Zero-width items are not in the bar at all.
            guard size.width >= 1 else { return nil }

            var point = CGPoint.zero
            var positionValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
               let positionValue {
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
            }

            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
            var descriptionValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descriptionValue)

            let label = [(titleValue as? String), (descriptionValue as? String)]
                .compactMap { $0 }
                .first { !$0.isEmpty && $0 != app.localizedName }

            return Item(
                appName: app.localizedName ?? "Unknown",
                bundleIdentifier: app.bundleIdentifier,
                icon: app.icon,
                title: label,
                element: element,
                position: point,
                size: size
            )
        }
    }

    static func dump() {
        print("AXIsProcessTrusted: \(AXIsProcessTrusted())")
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.25)
            var extras: CFTypeRef?
            guard AXUIElementCopyAttributeValue(application, "AXExtrasMenuBar" as CFString, &extras) == .success,
                  let extrasElement = extras else { continue }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(extrasElement as! AXUIElement,
                                                kAXChildrenAttribute as CFString, &children) == .success,
                  let items = children as? [AXUIElement] else { continue }

            for (index, element) in items.enumerated() {
                func string(_ attribute: String) -> String {
                    var value: CFTypeRef?
                    AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
                    return (value as? String) ?? ""
                }
                var size = CGSize.zero
                var sizeValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
                   let sizeValue { AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) }
                var point = CGPoint.zero
                var positionValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
                   let positionValue { AXValueGetValue(positionValue as! AXValue, .cgPoint, &point) }

                print(String(format: "%@[%d] title=%@ desc=%@ id=%@ help=%@ roleDesc=%@ size=%.0fx%.0f at=%.0f,%.0f",
                             app.localizedName ?? "?", index,
                             string(kAXTitleAttribute), string(kAXDescriptionAttribute),
                             string("AXIdentifier"), string(kAXHelpAttribute), string(kAXRoleDescriptionAttribute),
                             size.width, size.height, point.x, point.y))
            }
        }
    }

    @discardableResult
    static func press(_ item: Item) -> Bool {
        AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success
    }
}
