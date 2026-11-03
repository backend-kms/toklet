import AppKit
import XCTest
@testable import Toklet

private final class EditingTarget: NSObject, NSMenuItemValidation {
    var commands: [String] = []
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }
    @objc func cut(_ sender: Any?) { commands.append("cut") }
    @objc func copy(_ sender: Any?) { commands.append("copy") }
    @objc func paste(_ sender: Any?) { commands.append("paste") }
    @objc func selectAll(_ sender: Any?) { commands.append("selectAll") }
    @objc func undo(_ sender: Any?) { commands.append("undo") }
    @objc func redo(_ sender: Any?) { commands.append("redo") }
}

final class AppMenuTests: XCTestCase {
    func testEditingShortcutsDispatchToTheEditingTarget() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let menu = AppMenu.make()
            let edit = try XCTUnwrap(menu.items.first { $0.title == "편집" }?.submenu)
            let target = EditingTarget()
            for item in edit.items where !item.isSeparatorItem {
                XCTAssertNil(item.target, "Editing commands must follow the current first responder in the app")
                item.target = target
            }
            let commands: [(String, UInt16, NSEvent.ModifierFlags, String)] = [
                ("c", 8, .command, "copy"),
                ("v", 9, .command, "paste"),
                ("a", 0, .command, "selectAll"),
                ("x", 7, .command, "cut"),
                ("z", 6, .command, "undo"),
                ("z", 6, [.command, .shift], "redo")
            ]
            for (key, code, modifiers, expected) in commands {
                let event = try XCTUnwrap(NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                    windowNumber: 0, context: nil, characters: modifiers.contains(.shift) ? key.uppercased() : key,
                    charactersIgnoringModifiers: modifiers.contains(.shift) ? key.uppercased() : key,
                    isARepeat: false, keyCode: code))
                let previousCount = target.commands.count
                XCTAssertTrue(menu.performKeyEquivalent(with: event), expected)
                XCTAssertEqual(target.commands.count, previousCount + 1, expected)
                XCTAssertEqual(target.commands.last, expected)
            }
        }
    }
}
