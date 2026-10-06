import SwiftUI
import DesignSystem
import Persistence

/// Where a page goes: each shelf first, then its folders with their depth as
/// an indent, and a way to make a folder without leaving. The one picker
/// behind the editor's chip and the Inbox swipe.
struct NoteFilingSheet: View {
    let targets: [NoteMoveTarget]
    var currentBucket: NoteBucket?
    var currentFolderID: UUID?
    var onPick: (NoteMoveTarget) -> Void
    /// Makes a folder and answers its id, or nil when it could not.
    var onCreateFolder: (String, NoteBucket) -> UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var newName = ""
    @State private var newBucket: NoteBucket = .projects

    var body: some View {
        NavigationStack {
            List {
                ForEach(NoteBucket.filing) { bucket in
                    Section {
                        ForEach(targets.filter { $0.bucket == bucket }) { target in
                            Button {
                                onPick(target)
                                dismiss()
                            } label: {
                                HStack(spacing: Space.x1) {
                                    Image(systemName: target.folderID == nil ? "tray" : "folder")
                                        .foregroundStyle(Editorial.quietInk(scheme))
                                    Text(target.folderID == nil ? "On \(bucket.title)" : target.leafName)
                                        .font(LifeOSType.secondary)
                                }
                                .padding(.leading, CGFloat(max(0, target.depth - 1)) * Space.x2)
                            }
                            .disabled(target.isCurrentHome(bucket: currentBucket ?? .projects, folderID: currentFolderID)
                                      && currentBucket != nil)
                        }
                    } header: {
                        Text(bucket.title).editorialEyebrow()
                    }
                }
                Section {
                    HairlineField(text: $newName, placeholder: "New folder name", glyph: "folder.badge.plus",
                                  submitLabel: .done, onSubmit: createAndFile)
                    Picker("Shelf", selection: $newBucket) {
                        ForEach(NoteBucket.filing) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("Create and file here", action: createAndFile)
                        .buttonStyle(.editorial(.primary, size: .compact))
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("New folder").editorialEyebrow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(LifeOSTokens.canvas.resolve(scheme))
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .navigationTitle("File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func createAndFile() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let id = onCreateFolder(name, newBucket) else { return }
        onPick(NoteMoveTarget(bucket: newBucket, folderID: id, title: name, depth: 1))
        dismiss()
    }
}
