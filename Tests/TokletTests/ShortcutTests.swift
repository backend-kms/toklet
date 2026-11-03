import Carbon
import XCTest
@testable import Toklet

private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    var values: [String: Any] = [:]
    var domains: [String: [String: Any]] = [:]
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func persistentDomain(forName domainName: String) -> [String: Any]? { domains[domainName] }
}

final class ShortcutTests: XCTestCase {
    func testPreviousBundleShortcutIsRestoredAndCurrentPreferencesTakePriority() {
        let defaults = MemoryDefaults()
        defaults.domains["local.mac-note.app"] = ["shortcut.key": 45, "shortcut.modifiers": Int(controlKey | optionKey)]
        XCTAssertEqual(Shortcut.load(from: defaults), Shortcut(key: 45, modifiers: UInt32(controlKey | optionKey)))

        defaults.values = ["shortcut.key": 46, "shortcut.modifiers": Int(cmdKey | optionKey)]
        XCTAssertEqual(Shortcut.load(from: defaults), Shortcut(key: 46, modifiers: UInt32(cmdKey | optionKey)))
    }

    func testPreviousCommandLinePreferencesAreAlsoRecognized() {
        let defaults = MemoryDefaults()
        defaults.domains["MacNote"] = ["shortcut.key": 38, "shortcut.modifiers": Int(cmdKey | shiftKey)]
        XCTAssertEqual(Shortcut.load(from: defaults), Shortcut(key: 38, modifiers: UInt32(cmdKey | shiftKey)))
    }
}
