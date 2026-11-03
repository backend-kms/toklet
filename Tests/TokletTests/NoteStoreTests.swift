import XCTest
@testable import Toklet

final class NoteStoreTests: XCTestCase {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("notes.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testLegacyNotesLoadWithoutWritingAndAreBackedUpOnFirstSave() throws {
        let original = Data("""
        [{"id":"D2389F93-1BDA-40A9-BC6C-4C814A973EBD","title":"기존 제목","body":"기존 본문","updatedAt":800000000}]
        """.utf8)
        try original.write(to: file)
        let store = NoteStore(file: file)
        XCTAssertTrue(store.canWrite)
        XCTAssertEqual(store.notes.first?.title, "기존 제목")
        XCTAssertNil(store.notes.first?.projectID)
        XCTAssertEqual(try Data(contentsOf: file), original)

        let projectID = try XCTUnwrap(store.addProject("개발"))
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("legacy-backup")), original)
        let restored = NoteStore(file: file)
        XCTAssertEqual(restored.projects.first?.id, projectID)
        XCTAssertEqual(restored.notes, store.notes)
    }

    func testProjectNotesMoveAndSurviveProjectDeletionAndReload() throws {
        let store = NoteStore(file: file)
        let first = try XCTUnwrap(store.addProject("업무"))
        let second = try XCTUnwrap(store.addProject("개인"))
        let noteID = try XCTUnwrap(store.add(projectID: first))
        store.update(noteID, title: "메모 제목", body: "메모 본문")
        let updatedAt = try XCTUnwrap(store.notes.first?.updatedAt)

        XCTAssertTrue(store.move(noteID, to: second))
        XCTAssertTrue(store.renameProject(second, to: "개인 프로젝트"))
        XCTAssertEqual(store.notes.first?.projectID, second)
        XCTAssertEqual(store.notes.first?.updatedAt, updatedAt)
        XCTAssertTrue(store.deleteProject(second))
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertNil(store.notes.first?.projectID)
        XCTAssertEqual(store.notes.first?.body, "메모 본문")

        let restored = NoteStore(file: file)
        XCTAssertEqual(restored.notes, store.notes)
        XCTAssertEqual(restored.projects.map(\.id), [first])
    }

    func testLegacyMigrationPreservesAnExistingBackup() throws {
        let original = Data("[]".utf8)
        let previousBackup = Data("previous backup".utf8)
        try original.write(to: file)
        let backup = file.appendingPathExtension("legacy-backup")
        try previousBackup.write(to: backup)

        let store = NoteStore(file: file)
        XCTAssertNotNil(store.addProject("새 프로젝트"))
        XCTAssertEqual(try Data(contentsOf: backup), previousBackup)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("notes.json.legacy-backup.") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    }

    func testInvalidAndDuplicateProjectNamesDoNotChangeStorage() throws {
        let store = NoteStore(file: file)
        let projectID = try XCTUnwrap(store.addProject("  Backend  "))
        let original = try Data(contentsOf: file)
        XCTAssertEqual(store.projects.first?.name, "Backend")
        XCTAssertNil(store.addProject("backend"))
        XCTAssertNil(store.addProject("\n "))
        XCTAssertNil(store.addProject("기본"))
        XCTAssertFalse(store.renameProject(projectID, to: "전체 메모"))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testUnknownProjectCannotCreateOrMoveNotes() throws {
        let store = NoteStore(file: file)
        let noteID = try XCTUnwrap(store.add())
        let original = try Data(contentsOf: file)
        XCTAssertNil(store.add(projectID: UUID()))
        XCTAssertFalse(store.move(noteID, to: UUID()))
        XCTAssertNil(store.notes.first?.projectID)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testCorruptStorageCannotBeOverwritten() throws {
        let original = Data("{broken".utf8)
        try original.write(to: file)
        let store = NoteStore(file: file)
        XCTAssertFalse(store.canWrite)
        XCTAssertNotNil(store.error)
        XCTAssertNil(store.add())
        XCTAssertNil(store.addProject("새 프로젝트"))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testFailedSaveKeepsProjectAndNoteState() throws {
        let store = NoteStore(file: file)
        let projectID = try XCTUnwrap(store.addProject("업무"))
        let noteID = try XCTUnwrap(store.add(projectID: projectID))
        let notes = store.notes
        let projects = store.projects
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)

        XCTAssertFalse(store.deleteProject(projectID))
        XCTAssertFalse(store.move(noteID, to: nil))
        XCTAssertEqual(store.notes, notes)
        XCTAssertEqual(store.projects, projects)
        XCTAssertNotNil(store.error)
    }

    func testRenamingImportsExistingProjectsAndPreservesThePreviousFile() throws {
        let previousFile = directory.appendingPathComponent("MacNote/notes.json")
        let previous = NoteStore(file: previousFile)
        let projectID = try XCTUnwrap(previous.addProject("기존 프로젝트"))
        let noteID = try XCTUnwrap(previous.add(projectID: projectID))
        previous.update(noteID, title: "기존 제목", body: "기존 본문")
        let original = try Data(contentsOf: previousFile)

        let store = NoteStore(applicationSupportDirectory: directory)
        let currentFile = directory.appendingPathComponent("Toklet/notes.json")
        XCTAssertEqual(store.storagePath, currentFile.path)
        XCTAssertEqual(store.notes, previous.notes)
        XCTAssertEqual(store.projects, previous.projects)
        XCTAssertFalse(FileManager.default.fileExists(atPath: currentFile.path))
        store.update(noteID, body: "Toklet에서 수정")
        XCTAssertEqual(try Data(contentsOf: previousFile), original)
        let restored = NoteStore(applicationSupportDirectory: directory)
        XCTAssertEqual(restored.notes.first?.body, "Toklet에서 수정")
        XCTAssertEqual(restored.projects.first?.id, projectID)
    }

    func testRenamingAlsoImportsAndBacksUpTheOriginalArrayFormat() throws {
        let previousFile = directory.appendingPathComponent("MacNote/notes.json")
        try FileManager.default.createDirectory(at: previousFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = try JSONEncoder().encode([Note(title: "이전 메모", body: "본문")])
        try original.write(to: previousFile)

        let store = NoteStore(applicationSupportDirectory: directory)
        XCTAssertEqual(store.notes.first?.title, "이전 메모")
        XCTAssertNotNil(store.addProject("새 프로젝트"))
        let backup = directory.appendingPathComponent("Toklet/notes.json.legacy-backup")
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try Data(contentsOf: previousFile), original)
    }

    func testExistingTokletStorageTakesPriorityAndCorruptionDoesNotRestoreOlderData() throws {
        let previous = NoteStore(file: directory.appendingPathComponent("MacNote/notes.json"))
        let oldID = try XCTUnwrap(previous.add())
        previous.update(oldID, title: "이전 값")
        let currentFile = directory.appendingPathComponent("Toklet/notes.json")
        let current = NoteStore(file: currentFile)
        let newID = try XCTUnwrap(current.add())
        current.update(newID, title: "최신 값")

        XCTAssertEqual(NoteStore(applicationSupportDirectory: directory).notes.first?.title, "최신 값")
        let corrupt = Data("invalid JSON".utf8)
        try corrupt.write(to: currentFile)
        let store = NoteStore(applicationSupportDirectory: directory)
        XCTAssertFalse(store.canWrite)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNil(store.add())
        XCTAssertEqual(try Data(contentsOf: currentFile), corrupt)
    }
}
