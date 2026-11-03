import Foundation
import Combine

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var body: String
    var updatedAt = Date()
    var projectID: UUID?
}

struct NoteProject: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
}

private struct Notebook: Codable {
    var version = 1
    var projects: [NoteProject]
    var notes: [Note]
}

final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var projects: [NoteProject] = []
    @Published var error: String?
    private(set) var canWrite = true
    private let file: URL
    private var legacySource: URL?
    private var needsLegacyBackup = false

    init(file: URL? = nil, applicationSupportDirectory: URL? = nil) {
        let support = applicationSupportDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.file = file ?? support.appendingPathComponent("Toklet", isDirectory: true).appendingPathComponent("notes.json")
        let previousFile = support.appendingPathComponent("MacNote", isDirectory: true).appendingPathComponent("notes.json")
        let source: URL
        if file == nil, !FileManager.default.fileExists(atPath: self.file.path),
           FileManager.default.fileExists(atPath: previousFile.path) {
            source = previousFile
            legacySource = previousFile
        } else {
            source = self.file
        }
        do {
            if FileManager.default.fileExists(atPath: source.path) {
                let data = try Data(contentsOf: source)
                let decoder = JSONDecoder()
                if data.first(where: { ![9, 10, 13, 32].contains($0) }) == UInt8(ascii: "[") {
                    notes = try decoder.decode([Note].self, from: data)
                    needsLegacyBackup = true
                } else {
                    let notebook = try decoder.decode(Notebook.self, from: data)
                    let ids = Set(notebook.projects.map(\.id))
                    guard notebook.version == 1,
                          ids.count == notebook.projects.count,
                          Set(notebook.notes.map(\.id)).count == notebook.notes.count,
                          notebook.notes.allSatisfy({ $0.projectID.map(ids.contains) ?? true }) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    projects = notebook.projects
                    notes = notebook.notes
                }
            }
        } catch {
            canWrite = false
            self.error = "메모를 읽지 못했어요. 원본 보호를 위해 편집을 중지했어요.\n\(source.path)\n\(error.localizedDescription)"
        }
    }

    var storagePath: String { file.path }

    private func commit(_ next: [Note], projects nextProjects: [NoteProject]? = nil) -> Bool {
        guard canWrite else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Notebook(projects: nextProjects ?? projects, notes: next))
            if needsLegacyBackup {
                var backup = file.appendingPathExtension("legacy-backup")
                if FileManager.default.fileExists(atPath: backup.path) { backup.appendPathExtension(UUID().uuidString) }
                try FileManager.default.copyItem(at: legacySource ?? file, to: backup)
            }
            try data.write(to: file, options: .atomic)
            notes = next
            if let nextProjects { projects = nextProjects }
            legacySource = nil
            needsLegacyBackup = false
            return true
        } catch {
            self.error = "저장하지 못했어요. 저장 위치와 디스크 여유 공간을 확인해주세요.\n\(error.localizedDescription)"
            return false
        }
    }

    func add(projectID: UUID? = nil) -> UUID? {
        guard validProject(projectID) else { return nil }
        let note = Note(title: "", body: "", projectID: projectID)
        return commit([note] + notes) ? note.id : nil
    }

    func update(_ id: UUID, title: String? = nil, body: String? = nil) {
        var next = notes
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        if let title { next[index].title = title }
        if let body { next[index].body = body }
        next[index].updatedAt = Date()
        _ = commit(next)
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool { commit(notes.filter { $0.id != id }) }

    func projectName(for id: UUID?) -> String {
        projects.first { $0.id == id }?.name ?? "기본"
    }

    @discardableResult
    func move(_ id: UUID, to projectID: UUID?) -> Bool {
        guard validProject(projectID) else { return false }
        var next = notes
        guard let index = next.firstIndex(where: { $0.id == id }) else { return false }
        next[index].projectID = projectID
        return commit(next)
    }

    func addProject(_ name: String) -> UUID? {
        guard let name = validatedProjectName(name) else { return nil }
        let project = NoteProject(name: name)
        return commit(notes, projects: projects + [project]) ? project.id : nil
    }

    @discardableResult
    func renameProject(_ id: UUID, to name: String) -> Bool {
        guard let name = validatedProjectName(name, excluding: id) else { return false }
        var next = projects
        guard let index = next.firstIndex(where: { $0.id == id }) else { return false }
        next[index].name = name
        return commit(notes, projects: next)
    }

    @discardableResult
    func deleteProject(_ id: UUID) -> Bool {
        guard projects.contains(where: { $0.id == id }) else { return false }
        let next = notes.map { note in
            var note = note
            if note.projectID == id { note.projectID = nil }
            return note
        }
        return commit(next, projects: projects.filter { $0.id != id })
    }

    private func validProject(_ id: UUID?) -> Bool {
        guard let id else { return true }
        guard projects.contains(where: { $0.id == id }) else {
            error = "프로젝트를 찾을 수 없어요. 다른 프로젝트를 선택해주세요."
            return false
        }
        return true
    }

    private func validatedProjectName(_ name: String, excluding id: UUID? = nil) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "프로젝트 이름을 입력해주세요."; return nil }
        guard !["기본", "전체 메모"].contains(name),
              !projects.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            error = "이미 사용 중인 프로젝트 이름이에요. 다른 이름을 입력해주세요."
            return nil
        }
        return name
    }
}
