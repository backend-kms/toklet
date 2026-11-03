import Foundation
import Combine

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var body: String
    var updatedAt = Date()
}

final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var error: String?
    private(set) var canWrite = true
    private let file: URL

    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacNote", isDirectory: true).appendingPathComponent("notes.json")
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                notes = try JSONDecoder().decode([Note].self, from: Data(contentsOf: file))
            }
        } catch {
            canWrite = false
            self.error = "메모를 읽지 못했어요. 원본 보호를 위해 편집을 중지했어요.\n\(file.path)\n\(error.localizedDescription)"
        }
    }

    var storagePath: String { file.path }

    private func commit(_ next: [Note]) -> Bool {
        guard canWrite else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(next).write(to: file, options: .atomic)
            notes = next
            return true
        } catch {
            self.error = "저장하지 못했어요. 저장 위치와 디스크 여유 공간을 확인해주세요.\n\(error.localizedDescription)"
            return false
        }
    }

    func add() -> UUID? {
        let note = Note(title: "", body: "")
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

    func delete(_ id: UUID) { _ = commit(notes.filter { $0.id != id }) }
}
