import SwiftUI
import AppKit

struct NoteEditorView: View {
    @ObservedObject var store: NoteStore
    let noteID: UUID
    let focusTitle: Bool
    let copy: (String) -> Void
    let copyTitle: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var copied = false
    @State private var copyToken = UUID()
    @State private var showDelete = false

    private enum Field: Hashable { case title, body }
    private var note: Note? { store.notes.first { $0.id == noteID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(focusTitle ? "새 메모" : "메모 편집").font(.title3.weight(.semibold))
                Spacer()
                Button("완료") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let note {
                HStack {
                    Picker("프로젝트", selection: Binding<UUID?>(
                        get: { self.note?.projectID }, set: { store.move(noteID, to: $0) })) {
                        Text("기본").tag(nil as UUID?)
                        ForEach(store.projects) { project in Text(project.name).tag(project.id as UUID?) }
                    }.frame(maxWidth: 300).disabled(!store.canWrite)
                    Spacer()
                    Text(note.updatedAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("제목").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextField("메모 제목", text: Binding(
                        get: { self.note?.title ?? "" }, set: { store.update(noteID, title: $0) }))
                        .font(.system(size: 22, weight: .semibold)).textFieldStyle(.plain)
                        .focused($focusedField, equals: .title)
                        .onSubmit { focusedField = .body }
                        .frame(height: 34).padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor).opacity(0.35)))
                        .accessibilityLabel("메모 제목").disabled(!store.canWrite)
                }.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("내용")
                        Spacer()
                        Text("\(note.body.count)자")
                    }.font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { self.note?.body ?? "" }, set: { store.update(noteID, body: $0) }))
                        .font(.system(size: 14, design: .monospaced))
                        .focused($focusedField, equals: .body).scrollContentBackground(.hidden)
                        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor).opacity(0.35)))
                        .accessibilityLabel("메모 본문").disabled(!store.canWrite)
                }
                HStack(spacing: 14) {
                    Button(role: .destructive) { showDelete = true } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("메모 삭제").disabled(!store.canWrite)
                    Button {
                        if copyTitle(note.title) { copied = true; copyToken = UUID() }
                    } label: {
                        Label(copied ? "복사됨" : "제목 복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }.buttonStyle(.borderless).disabled(note.title.isEmpty)
                    Spacer()
                    Button("본문 복사 ⌘↩") {
                        dismiss()
                        DispatchQueue.main.async { copy(note.body) }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command).disabled(note.body.isEmpty)
                }
            } else {
                Text("메모를 찾을 수 없어요.").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(24).frame(width: 600, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { focusedField = focusTitle ? .title : .body }
        .task(id: copyToken) {
            guard copied else { return }
            do { try await Task.sleep(nanoseconds: 1_600_000_000) }
            catch { return }
            copied = false
        }
        .alert("메모를 삭제할까요?", isPresented: $showDelete) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) { if store.delete(noteID) { dismiss() } }
        } message: { Text("삭제한 메모는 되돌릴 수 없어요.") }
        .alert("확인이 필요해요", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("확인") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct ProjectNameView: View {
    @ObservedObject var store: NoteStore
    let project: NoteProject?
    let save: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(project == nil ? "새 프로젝트" : "프로젝트 이름 변경").font(.title3.weight(.semibold))
            TextField("프로젝트 이름", text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
                .onSubmit { submit() }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(project == nil ? "추가" : "저장", action: submit)
                    .keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { name = project?.name ?? ""; nameFocused = true }
        .alert("확인이 필요해요", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("확인") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private func submit() { if save(name) { dismiss() } }
}
