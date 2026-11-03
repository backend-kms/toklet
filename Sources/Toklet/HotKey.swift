import AppKit
import Carbon

struct Shortcut: Equatable {
    var key: UInt32
    var modifiers: UInt32
    static let keys: [(String, UInt32)] = [("Space", 49), ("N", 45), ("M", 46), ("J", 38), ("K", 40)]
    static let modifierOptions: [(String, UInt32)] = [
        ("⌥ Option", UInt32(optionKey)),
        ("⌃⌥ Control + Option", UInt32(controlKey | optionKey)),
        ("⌘⇧ Command + Shift", UInt32(cmdKey | shiftKey)),
        ("⌘⌥ Command + Option", UInt32(cmdKey | optionKey))
    ]
    static var saved: Shortcut { load() }

    static func load(from defaults: UserDefaults = .standard) -> Shortcut {
        let legacy = defaults.persistentDomain(forName: "local.mac-note.app")
            ?? defaults.persistentDomain(forName: "MacNote") ?? [:]
        return Shortcut(key: UInt32(defaults.object(forKey: "shortcut.key") as? Int ?? legacy["shortcut.key"] as? Int ?? 49),
                        modifiers: UInt32(defaults.object(forKey: "shortcut.modifiers") as? Int ?? legacy["shortcut.modifiers"] as? Int ?? Int(optionKey)))
    }
    var label: String {
        let modifier = Self.modifierOptions.first { $0.1 == modifiers }?.0 ?? ""
        let keyName = Self.keys.first { $0.1 == key }?.0 ?? "?"
        return "\(modifier) + \(keyName)"
    }
    func persist() {
        UserDefaults.standard.set(Int(key), forKey: "shortcut.key")
        UserDefaults.standard.set(Int(modifiers), forKey: "shortcut.modifiers")
    }
}

final class HotKeyManager {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { manager.onPress?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: Shortcut) -> Bool {
        // Register first: a conflicting replacement must not disable the current shortcut.
        var next: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x544F4B4C), id: 1)
        let result = RegisterEventHotKey(shortcut.key, shortcut.modifiers, id,
                                        GetApplicationEventTarget(), 0, &next)
        guard result == noErr else { return false }
        if let reference { UnregisterEventHotKey(reference) }
        reference = next
        return true
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
