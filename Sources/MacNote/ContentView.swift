import SwiftUI
import AppKit

extension Notification.Name {
    static let focusNoteSearch = Notification.Name("MacNote.focusSearch")
}

struct ContentView: View {
    @ObservedObject var store: NoteStore
    let copy: (String) -> Void
    let copyTitle: (String) -> Bool
    let applyShortcut: (Shortcut) -> Bool
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var showSettings = false
    @State private var pendingDelete: UUID?
    @State private var copiedTitleID: UUID?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case search
        case title(UUID)
        case body(UUID)
    }

    private var results: [Note] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.notes.filter { q.isEmpty || $0.title.localizedStandardContains(q) || $0.body.localizedStandardContains(q) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    private var selected: Note? { store.notes.first { $0.id == selectedID } }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 250)
            Divider()
            Group {
                if let note = selected {
                    editor(for: note).id(note.id)
                } else {
                    emptyEditor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 520)
        .onAppear { selectFirstIfNeeded(); focusedField = .search }
        .onChange(of: query) { _ in selectFirstIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .focusNoteSearch)) { _ in
            focusedField = .search
            selectFirstIfNeeded()
        }
        .task(id: copiedTitleID) {
            guard copiedTitleID != nil else { return }
            do { try await Task.sleep(nanoseconds: 1_600_000_000) }
            catch { return }
            copiedTitleID = nil
        }
        .sheet(isPresented: $showSettings) { SettingsView(storagePath: store.storagePath, apply: applyShortcut) }
        .alert("메모를 삭제할까요?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("취소", role: .cancel) { pendingDelete = nil }
            Button("삭제", role: .destructive) {
                if let id = pendingDelete { store.delete(id) }
                pendingDelete = nil
                selectFirstIfNeeded()
            }
        } message: { Text("삭제한 메모는 되돌릴 수 없어요.") }
        .alert("확인이 필요해요", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("확인") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Mac Note").font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Button(action: createNote) { Image(systemName: "square.and.pencil").font(.system(size: 16)) }
                        .buttonStyle(.plain).help("새 메모 · ⌘N")
                        .keyboardShortcut("n").disabled(!store.canWrite)
                        .accessibilityLabel("새 메모")
                }
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("메모 검색", text: $query)
                        .textFieldStyle(.plain).focused($focusedField, equals: .search)
                        .onSubmit {
                            if let note = results.first(where: { $0.id == selectedID }) ?? results.first { copy(note.body) }
                        }
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).help("검색 지우기")
                    }
                }
                .font(.system(size: 13)).padding(9)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }.padding(18)

            if results.isEmpty {
                VStack(spacing: 8) {
                    Text(query.isEmpty ? "메모가 없어요" : "검색 결과가 없어요").font(.callout)
                    if query.isEmpty {
                        Button("새 메모 만들기", action: createNote).disabled(!store.canWrite)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(results) { note in
                        noteRow(note).tag(note.id)
                    }
                }
                .listStyle(.sidebar).scrollContentBackground(.hidden)
            }

            Divider().padding(.horizontal, 18)
            HStack {
                Text("\(results.count)개의 메모").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("설정 · ⌘,").keyboardShortcut(",")
            }.padding(.horizontal, 18).padding(.vertical, 14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { copyNoteTitle(note) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(note.title.isEmpty ? "제목 없음" : note.title)
                        .font(.system(size: 14, weight: .semibold)).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if copiedTitleID == note.id {
                        Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
                    }
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("제목 텍스트 복사").disabled(note.title.isEmpty)
            Text(note.body.isEmpty ? "내용을 입력하세요" : note.body)
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(note.updatedAt, style: .date).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
    }

    private func editor(for note: Note) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(note.updatedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { pendingDelete = note.id } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("메모 삭제").disabled(!store.canWrite)
            }
            .padding(.horizontal, 24).frame(height: 48)
            Divider()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("제목").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextField("메모 제목", text: Binding(
                        get: { store.notes.first { $0.id == note.id }?.title ?? "" },
                        set: { store.update(note.id, title: $0) }))
                        .font(.system(size: 22, weight: .semibold)).textFieldStyle(.plain)
                        .focused($focusedField, equals: .title(note.id))
                        .onSubmit { focusedField = .body(note.id) }
                        .accessibilityLabel("메모 제목")
                        .frame(height: 34).padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor).opacity(0.35)))
                        .disabled(!store.canWrite)
                }
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("내용").font(.caption.weight(.medium))
                        Spacer()
                        Text("\(note.body.count)자").font(.caption)
                    }.foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { store.notes.first { $0.id == note.id }?.body ?? "" },
                        set: { store.update(note.id, body: $0) }))
                        .font(.system(size: 14, design: .monospaced))
                        .focused($focusedField, equals: .body(note.id))
                        .scrollContentBackground(.hidden).padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor).opacity(0.35)))
                        .accessibilityLabel("메모 본문").disabled(!store.canWrite)
                }.frame(maxHeight: .infinity)
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            HStack(spacing: 12) {
                Button { copyNoteTitle(note) } label: {
                    Label(copiedTitleID == note.id ? "복사됨" : "제목 복사",
                          systemImage: copiedTitleID == note.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless).disabled(note.title.isEmpty)
                Spacer()
                Text("⌘↩").font(.caption).foregroundStyle(.tertiary)
                Button("본문 복사") { copy(note.body) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command).disabled(note.body.isEmpty)
            }
            .padding(.horizontal, 24).frame(height: 64)
        }
    }

    private var emptyEditor: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.pencil").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text("메모를 작성해보세요").font(.title3.weight(.medium))
            Button("새 메모", action: createNote).disabled(!store.canWrite)
            Text("⌘N 새 메모 · Esc 닫기").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyNoteTitle(_ note: Note) {
        guard copyTitle(note.title) else { return }
        selectedID = note.id
        copiedTitleID = note.id
    }

    private func createNote() {
        query = ""
        if let id = store.add() {
            selectedID = id
            DispatchQueue.main.async { focusedField = .title(id) }
        }
    }
    private func selectFirstIfNeeded() {
        if !results.contains(where: { $0.id == selectedID }) { selectedID = results.first?.id }
    }
}

struct SettingsView: View {
    let storagePath: String
    let apply: (Shortcut) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var shortcut = Shortcut.saved
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Mac Note 설정").font(.title2.bold())
            Text("어떤 앱에서든 단축키로 메모장을 열고 닫아요.").foregroundStyle(.secondary)
            Picker("보조 키", selection: $shortcut.modifiers) {
                ForEach(Shortcut.modifierOptions, id: \.1) { item in Text(item.0).tag(item.1) }
            }
            Picker("키", selection: $shortcut.key) {
                ForEach(Shortcut.keys, id: \.1) { item in Text(item.0).tag(item.1) }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Divider()
            Text("저장 위치").font(.headline)
            Text(storagePath).font(.caption).textSelection(.enabled)
            Text("서버 전송 없이 이 맥에 저장해요. 기밀 정보나 비밀번호 보관용 암호화 저장소는 아니에요.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("앱 종료") { NSApp.terminate(nil) }
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("저장") {
                    if apply(shortcut) { dismiss() }
                    else { error = "단축키를 등록하지 못했어요. 다른 조합을 선택해주세요. 기존 설정은 유지돼요." }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 440)
    }
}
