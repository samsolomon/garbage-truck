import AppKit

@MainActor
final class AppPresentationCoordinator: NSObject {
    private var statusItem: NSStatusItem?
    private var wantsMenuBarExtra = false
    private var wantsDockIcon = true
    private var isMainWindowReady = false
    private var openMainWindowAction: (() -> Void)?

    func configure(menuBarExtraEnabled: Bool, dockIconVisible: Bool) {
        wantsMenuBarExtra = menuBarExtraEnabled
        wantsDockIcon = dockIconVisible
        applyPresentationStateIfPossible()
    }

    func markMainWindowReady() {
        guard !isMainWindowReady else { return }
        isMainWindowReady = true
        applyPresentationStateIfPossible()
    }

    func setOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    private func applyPresentationStateIfPossible() {
        guard isMainWindowReady else { return }
        if wantsMenuBarExtra {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
        applyDockState()
    }

    private func applyDockState() {
        let desiredPolicy: NSApplication.ActivationPolicy = wantsDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != desiredPolicy else { return }
        NSApp.setActivationPolicy(desiredPolicy)
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Garbage Truck")
            button.imagePosition = .imageOnly
            button.toolTip = "Garbage Truck"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Garbage Truck", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Garbage Truck", action: #selector(quitApp), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }

        item.menu = menu
        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    func revealMainWindow() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            return
        }
        openMainWindowAction?()
    }

    func revealSettings() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }
        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    @objc private func openMainWindow() {
        revealMainWindow()
    }

    @objc private func openSettings() {
        revealSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
