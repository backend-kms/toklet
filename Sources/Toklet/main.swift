import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = NoteStore()
    private let hotKey = HotKeyManager()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var escapeMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var activeShortcut = Shortcut.saved

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = AppMenu.make()
        let view = ContentView(store: store, copy: { [weak self] text in self?.copyAndClose(text) },
                               copyTitle: { [weak self] text in self?.copyToClipboard(text) ?? false },
                               applyShortcut: { [weak self] shortcut in self?.applyShortcut(shortcut) ?? false })
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Toklet"
        panel.contentMinSize = NSSize(width: 780, height: 520)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: view)
        panel.center()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "</>"
        statusItem.button?.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        statusItem.button?.setAccessibilityLabel("Toklet 열기")
        statusItem.button?.toolTip = "Toklet · \(activeShortcut.label)"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        hotKey.onPress = { [weak self] in self?.toggle() }
        if !hotKey.register(activeShortcut) {
            store.error = "기본 단축키를 등록하지 못했어요. 설정에서 다른 키를 선택해주세요. 메뉴 막대 아이콘으로는 계속 열 수 있어요."
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.attachedSheet == nil else { return event }
            if event.keyCode == 53 { self.hide(); return nil }
            return event
        }
        show()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            let quitItem = NSMenuItem(title: "앱 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quitItem.target = NSApp
            menu.addItem(quitItem)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggle()
        }
    }

    @objc private func toggle() {
        if panel.isVisible && panel.isKeyWindow { hide() } else { show() }
    }
    private func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = frontmost }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { NotificationCenter.default.post(name: .focusNoteSearch, object: nil) }
    }
    private func hide() {
        panel.orderOut(nil)
        previousApp?.activate(options: [])
    }
    private func copyAndClose(_ text: String) {
        if copyToClipboard(text) { hide() }
    }
    private func copyToClipboard(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            store.error = "클립보드에 복사하지 못했어요. 다시 시도해주세요."
            return false
        }
        return true
    }
    private func applyShortcut(_ shortcut: Shortcut) -> Bool {
        guard shortcut != activeShortcut else { return true }
        guard hotKey.register(shortcut) else { return false }
        activeShortcut = shortcut
        shortcut.persist()
        statusItem.button?.toolTip = "Toklet · \(shortcut.label)"
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
