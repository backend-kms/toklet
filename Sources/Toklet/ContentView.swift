import SwiftUI
import AppKit

extension Notification.Name {
    static let focusNoteSearch = Notification.Name("Toklet.focusSearch")
}

private enum ProjectFilter: Hashable {
    case all, unfiled, project(UUID)

    var projectID: UUID? {
        if case let .project(id) = self { return id }
        return nil
    }

    func contains(_ note: Note) -> Bool {
        switch self {
        case .all: return true
        case .unfiled: return note.projectID == nil
        case let .project(id): return note.projectID == id
        }
    }
}

private struct EditingNote: Identifiable {
    let id: UUID
    var isNew = false
}

private struct EditingProject: Identifiable {
    let id = UUID()
    var project: NoteProject?
}

struct ContentView: View {
    @ObservedObject var store: NoteStore
    let copy: (String) -> Void
    let copyTitle: (String) -> Bool
    let applyShortcut: (Shortcut) -> Bool
    @State private var query = ""
    @State private var filter: ProjectFilter = .all
    @State private var selectedID: UUID?
    @State private var editingNote: EditingNote?
    @State private var editingProject: EditingProject?
    @State private var showSettings = false
    @State private var pendingDelete: UUID?
    @State private var pendingProjectDelete: NoteProject?
    @State private var copiedTitleID: UUID?
    @FocusState private var searchFocused: Bool

    private var results: [Note] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.notes.filter {
            filter.contains($0) && (q.isEmpty || $0.title.localizedStandardContains(q) || $0.body.localizedStandardContains(q))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selected: Note? { results.first { $0.id == selectedID } ?? results.first }
    private var folderName: String {
        switch filter {
        case .all: return "전체 메모"
        case .unfiled: return "기본"
        case let .project(id): return store.projectName(for: id)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Divider()
            board.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 520)
        .onAppear { selectFirstIfNeeded(); searchFocused = true }
        .onChange(of: query) { _ in selectFirstIfNeeded() }
        .onChange(of: filter) { _ in selectFirstIfNeeded() }
        .onChange(of: store.notes) { _ in selectFirstIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .focusNoteSearch)) { _ in
            searchFocused = true
            selectFirstIfNeeded()
        }
        .task(id: copiedTitleID) {
            guard copiedTitleID != nil else { return }
            do { try await Task.sleep(nanoseconds: 1_600_000_000) }
            catch { return }
            copiedTitleID = nil
        }
        .sheet(item: $editingNote) { item in
            NoteEditorView(store: store, noteID: item.id, focusTitle: item.isNew, copy: copy, copyTitle: copyTitle)
        }
        .sheet(item: $editingProject) { item in
            ProjectNameView(store: store, project: item.project) { name in
                if let project = item.project { return store.renameProject(project.id, to: name) }
                guard let id = store.addProject(name) else { return false }
                query = ""
                filter = .project(id)
                return true
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(storagePath: store.storagePath, apply: applyShortcut) }
        .alert("메모를 삭제할까요?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("취소", role: .cancel) { pendingDelete = nil }
            Button("삭제", role: .destructive) {
                if let id = pendingDelete { store.delete(id) }
                pendingDelete = nil
            }
        } message: { Text("삭제한 메모는 되돌릴 수 없어요.") }
        .alert("프로젝트를 삭제할까요?", isPresented: Binding(get: { pendingProjectDelete != nil }, set: { if !$0 { pendingProjectDelete = nil } })) {
            Button("취소", role: .cancel) { pendingProjectDelete = nil }
            Button("프로젝트 삭제", role: .destructive) {
                if let project = pendingProjectDelete, store.deleteProject(project.id), filter == .project(project.id) {
                    filter = .unfiled
                }
                pendingProjectDelete = nil
            }
        } message: { Text("프로젝트 안의 메모는 삭제되지 않고 ‘기본’ 폴더로 이동해요.") }
        .alert("확인이 필요해요", isPresented: Binding(
            get: { store.error != nil && editingNote == nil && editingProject == nil },
            set: { if !$0 { store.error = nil } })) {
            Button("확인") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text("</>").font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(Color.accentColor)
                Text("Toklet").font(.system(size: 17, weight: .semibold))
            }.padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 30)

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    folderRow("전체 메모", icon: "square.grid.2x2", count: store.notes.count, value: .all)
                    folderRow("기본", icon: "folder", count: store.notes.filter { $0.projectID == nil }.count, value: .unfiled)
                    HStack {
                        Text("프로젝트").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Button { editingProject = EditingProject() } label: { Image(systemName: "plus") }
                            .buttonStyle(.plain).help("프로젝트 추가").disabled(!store.canWrite)
                            .accessibilityLabel("프로젝트 추가")
                    }.padding(.horizontal, 11).padding(.top, 25).padding(.bottom, 7)
                    ForEach(store.projects) { project in
                        folderRow(project.name, icon: "folder", count: store.notes.filter { $0.projectID == project.id }.count,
                                  value: .project(project.id))
                            .contextMenu {
                                Button("이름 변경") { editingProject = EditingProject(project: project) }.disabled(!store.canWrite)
                                Button("프로젝트 삭제", role: .destructive) { pendingProjectDelete = project }.disabled(!store.canWrite)
                            }
                    }
                    if store.projects.isEmpty {
                        Text("프로젝트를 추가해\n메모를 나눠보세요.")
                            .font(.caption).foregroundStyle(.tertiary).lineSpacing(4)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                    }
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 0)
            Divider().padding(.horizontal, 20)
            HStack {
                Text("맥에 자동 저장").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("설정 · ⌘,").keyboardShortcut(",")
            }.padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func folderRow(_ name: String, icon: String, count: Int, value: ProjectFilter) -> some View {
        Button { filter = value } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 18)
                Text(name).font(.system(size: 13, weight: filter == value ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .foregroundStyle(filter == value ? Color.accentColor : Color.primary)
            .padding(.horizontal, 11).padding(.vertical, 11)
            .background(filter == value ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help(name)
    }

    private var board: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(folderName).font(.system(size: 25, weight: .bold)).lineLimit(1).help(folderName)
                        Text("\(results.count)개의 메모").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button(action: createNote) { Label("새 메모", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut("n").disabled(!store.canWrite).help("새 메모 · ⌘N")
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("이 폴더에서 메모 검색", text: $query)
                        .textFieldStyle(.plain).focused($searchFocused)
                        .onSubmit { if let note = selected { copy(note.body) } }
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).help("검색 지우기")
                    }
                }
                .font(.system(size: 13)).padding(11)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color(nsColor: .separatorColor).opacity(0.3)))
            }.padding(24)

            if results.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: query.isEmpty ? "note.text" : "magnifyingglass")
                        .font(.system(size: 32, weight: .light)).foregroundStyle(.tertiary)
                    Text(query.isEmpty ? "이 폴더에 첫 메모를 만들어보세요" : "검색 결과가 없어요").font(.callout).foregroundStyle(.secondary)
                    if query.isEmpty { Button("새 메모 만들기", action: createNote).disabled(!store.canWrite) }
                    else { Button("검색 지우기") { query = "" } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10), count: 4),
                              alignment: .leading, spacing: 10) {
                        ForEach(results) { note in
                            NoteCard(note: note, projectName: store.projectName(for: note.projectID),
                                     isSelected: selectedID == note.id, isCopied: copiedTitleID == note.id,
                                     open: { open(note) }, copyTitle: { copyNoteTitle(note) }, copyBody: { copy(note.body) })
                                .contextMenu {
                                    Button("메모 열기") { open(note) }
                                    Button("제목 복사") { copyNoteTitle(note) }.disabled(note.title.isEmpty)
                                    Button("본문 복사") { copy(note.body) }.disabled(note.body.isEmpty)
                                    Menu("프로젝트로 이동") {
                                        Button("기본") { store.move(note.id, to: nil) }
                                        ForEach(store.projects) { project in
                                            Button(project.name) { store.move(note.id, to: project.id) }
                                        }
                                    }.disabled(!store.canWrite)
                                    Divider()
                                    Button("메모 삭제", role: .destructive) { pendingDelete = note.id }.disabled(!store.canWrite)
                                }
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
            }

            HStack {
                Text("제목 클릭 복사 · 카드 본문 클릭 편집").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("본문 복사 ⌘↩") { if let note = selected { copy(note.body) } }
                    .buttonStyle(.borderless).font(.caption)
                    .keyboardShortcut(.return, modifiers: .command).disabled(selected?.body.isEmpty ?? true)
            }.padding(.horizontal, 24).frame(height: 44)
        }.background(Color(nsColor: .textBackgroundColor).overlay(Color.primary.opacity(0.025)))
    }

    private func createNote() {
        guard let id = store.add(projectID: filter.projectID) else { return }
        query = ""
        selectedID = id
        editingNote = EditingNote(id: id, isNew: true)
    }

    private func open(_ note: Note) {
        selectedID = note.id
        editingNote = EditingNote(id: note.id)
    }

    private func copyNoteTitle(_ note: Note) {
        guard copyTitle(note.title) else { return }
        selectedID = note.id
        copiedTitleID = note.id
    }

    private func selectFirstIfNeeded() {
        if !results.contains(where: { $0.id == selectedID }) { selectedID = results.first?.id }
    }
}

private struct NoteCard: View {
    let note: Note
    let projectName: String
    let isSelected: Bool
    let isCopied: Bool
    let open: () -> Void
    let copyTitle: () -> Void
    let copyBody: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 5) {
                Button(action: copyTitle) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(note.title.isEmpty ? "제목 없음" : note.title)
                            .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            .multilineTextAlignment(.leading).foregroundStyle(.primary)
                        if isCopied { Image(systemName: "checkmark").font(.caption).foregroundStyle(.green) }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help(isCopied ? "복사됨" : "\(note.title) · 클릭해서 제목 복사").disabled(note.title.isEmpty)
                Button(action: open) { Image(systemName: "square.and.pencil").font(.system(size: 11)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("메모 편집")
            }.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            Button(action: open) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(note.body.isEmpty ? "내용을 입력하세요" : note.body)
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).help("클릭해서 편집")
            HStack(spacing: 5) {
                Image(systemName: "folder").font(.system(size: 10))
                Text(projectName).lineLimit(1)
                Spacer(minLength: 0)
                Button(action: copyBody) { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).help("본문 복사 후 닫기").disabled(note.body.isEmpty)
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(10).frame(maxWidth: .infinity).frame(height: 88, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
            isSelected ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.025), radius: 3, y: 1)
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
            Text("Toklet 설정").font(.title2.bold())
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
