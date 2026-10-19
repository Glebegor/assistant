import QuickLookThumbnailing
import SwiftUI

/// Shelf tab, in two rows: what you copied (clipboard) and what you put here (files,
/// screenshots and folders). Inside a folder there is one row with its contents.
struct ShelfView: View {
    let store: ShelfStore
    @State private var renamingFolderID: UUID?

    var body: some View {
        let folder = store.openFolder
        let items = store.items(in: folder?.id)

        VStack(alignment: .leading, spacing: 10) {
            header(folder: folder, count: folder == nil ? items.count + store.folders.count : items.count)
            if folder != nil {
                row(items: items, empty: "Empty folder. Drop files or Shelf items here.")
            } else {
                let clipboard = items.filter { $0.source == .clipboard }
                let files = items.filter { $0.source != .clipboard }

                section("Clipboard", systemImage: "doc.on.clipboard", count: clipboard.count) {
                    Button("Clear") { store.clearClipboard() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .disabled(clipboard.isEmpty)
                        .help("Remove all copied items")
                }
                row(items: clipboard, empty: "Text, images and files you copy appear here.")

                section("Files", systemImage: "doc", count: files.count + store.folders.count) {
                    if store.needsScreenshotFolderAccess {
                        Button("Allow screenshots…", systemImage: "exclamationmark.triangle.fill", action: PrivacySettings.openFilesAndFolders)
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("RightHand needs access to your Desktop to add screenshots automatically")
                    }
                }
                row(items: files, folders: store.folders, empty: "Drop files here. New screenshots appear here too.")
            }
        }
    }

    private func section(_ title: String, systemImage: String, count: Int,
                         @ViewBuilder accessory: () -> some View) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(title).fontWeight(.semibold)
            Text("\(count)").foregroundStyle(.secondary)
            Spacer()
            accessory()
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.8))
        .padding(.bottom, -4)
    }

    /// One horizontally scrolling row of cards.
    private func row(items: [ShelfItem], folders: [ShelfFolder] = [], empty: String) -> some View {
        Group {
            if items.isEmpty && folders.isEmpty {
                Text(empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(folders) { folder in
                            ShelfFolderCard(folder: folder, store: store, renamingFolderID: $renamingFolderID)
                        }
                        ForEach(items) { item in
                            ShelfItemCard(item: item, store: store)
                        }
                    }
                }
            }
        }
        .frame(height: ShelfCard.height)
    }

    private func header(folder: ShelfFolder?, count: Int) -> some View {
        HStack {
            if let folder {
                Button("Back", systemImage: "chevron.left") { store.openFolderID = nil }
                    .buttonStyle(.notchPill())
                    .labelStyle(.iconOnly)
                    .help("Back to Shelf")
                Text(folder.name).font(.headline).lineLimit(1)
            } else {
                Text("Shelf").font(.headline)
            }
            Text("\(count)").foregroundStyle(.secondary)
            Spacer()
            Button("Show in Finder", systemImage: "folder") { store.revealDirectory(for: folder?.id) }
                .buttonStyle(.notchPill())
                .labelStyle(.iconOnly)
                .help("Show the files in Finder")
            if folder == nil {
                Button("New Folder", systemImage: "folder.badge.plus") {
                    renamingFolderID = store.createFolder().id
                }
                .buttonStyle(.notchPill())
                .labelStyle(.iconOnly)
                .help("New folder")
            }
            Button("Clear", systemImage: "trash") { store.clear(folderID: folder?.id) }
                .buttonStyle(.notchPill())
                .disabled(count == 0)
                .help(folder == nil ? "Remove everything from the Shelf" : "Remove everything from this folder")
        }
    }
}

/// Card sizes shared by item and folder cards.
private enum ShelfCard {
    static let width: CGFloat = 92
    static let previewHeight: CGFloat = 62
    static let titleHeight: CGFloat = 24
    static let spacing: CGFloat = 6
    static var height: CGFloat { previewHeight + spacing + titleHeight }
}

/// A folder on the Shelf. Click to open it; drop files or Shelf items on it to put them inside.
private struct ShelfFolderCard: View {
    let folder: ShelfFolder
    let store: ShelfStore
    @Binding var renamingFolderID: UUID?
    @State private var isDropTargeted = false
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private var isRenaming: Bool { renamingFolderID == folder.id }

    var body: some View {
        VStack(spacing: ShelfCard.spacing) {
            Image(systemName: isDropTargeted ? "folder.fill.badge.plus" : "folder.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
                .frame(width: ShelfCard.width, height: ShelfCard.previewHeight)
                .background(isDropTargeted ? .blue.opacity(0.3) : .white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomTrailing) {
                    Text("\(store.items(in: folder.id).count)")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(5)
                }
            if isRenaming {
                TextField("Folder name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .focused($isNameFocused)
                    .onSubmit(finishRenaming)
                    .onAppear {
                        draftName = folder.name
                        isNameFocused = true
                    }
                    .onChange(of: isNameFocused) { _, focused in
                        if !focused { finishRenaming() }
                    }
                    .frame(width: ShelfCard.width, height: ShelfCard.titleHeight, alignment: .top)
            } else {
                Text(folder.name)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: ShelfCard.width, height: ShelfCard.titleHeight, alignment: .top)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isRenaming { store.openFolderID = folder.id } }
        .onDrag { store.dragProvider(for: folder) }
        .onDrop(of: ShelfStore.dropTypes, isTargeted: $isDropTargeted) { providers in
            store.addDropped(providers, into: folder.id)
        }
        .help(folder.name)
        .contextMenu {
            Button("Open") { store.openFolderID = folder.id }
            Button("Show in Finder") { store.revealDirectory(for: folder.id) }
            Button("Rename") { renamingFolderID = folder.id }
            Divider()
            Button("Delete Folder", role: .destructive) { store.deleteFolder(folder) }
        }
    }

    private func finishRenaming() {
        guard isRenaming else { return }
        store.rename(folder, to: draftName)
        renamingFolderID = nil
    }
}

/// One card on the Shelf. Click: open the file / copy the text. Drag it out to use it elsewhere.
private struct ShelfItemCard: View {
    let item: ShelfItem
    let store: ShelfStore
    @State private var isHovered = false
    @State private var showsCopied = false

    var body: some View {
        VStack(spacing: ShelfCard.spacing) {
            preview
                .frame(width: ShelfCard.width, height: ShelfCard.previewHeight)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomLeading) { sourceBadge }
                .overlay { if showsCopied { copiedBadge } }
            Text(item.title)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: ShelfCard.width, height: ShelfCard.titleHeight, alignment: .top)
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button { store.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: primaryAction)
        .onDrag { store.dragProvider(for: item) }
        .help(item.title)
        .contextMenu {
            if item.fileURL != nil {
                Button("Open") { store.open(item) }
                Button("Show in Finder") { store.revealInFinder(item) }
            }
            Button("Copy") { copy() }
            if !store.folders.isEmpty {
                Menu("Move to") {
                    if item.folderID != nil {
                        Button("Shelf") { store.move(itemID: item.id, to: nil) }
                    }
                    ForEach(store.folders.filter { $0.id != item.folderID }) { folder in
                        Button(folder.name) { store.move(itemID: item.id, to: folder.id) }
                    }
                }
            }
            Divider()
            Button("Remove from Shelf") { store.remove(item) }
        }
    }

    @ViewBuilder private var preview: some View {
        switch item.content {
        case .text(let text):
            Text(text)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.85))
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .file, .image:
            if let url = item.fileURL { FileThumbnail(url: url) }
        }
    }

    @ViewBuilder private var sourceBadge: some View {
        let symbol: String? = switch item.source {
        case .screenshot: "camera.viewfinder"
        case .clipboard: nil // already in the Clipboard row
        case .dropped: nil
        }
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .padding(4)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                .padding(4)
        }
    }

    private var copiedBadge: some View {
        Text("Copied")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.green, in: Capsule())
            .foregroundStyle(.black)
    }

    private func primaryAction() {
        if case .text = item.content { copy() } else { store.open(item) }
    }

    private func copy() {
        store.copyToClipboard(item)
        showsCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            showsCopied = false
        }
    }
}

/// Quick Look preview of a file (falls back to its Finder icon).
private struct FileThumbnail: View {
    let url: URL
    @State private var thumbnail: NSImage?

    @MainActor private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(14)
            }
        }
        .task(id: url) {
            let key = url.path as NSString
            if let cached = Self.cache.object(forKey: key) {
                thumbnail = cached
                return
            }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: ShelfCard.width, height: ShelfCard.previewHeight),
                                                       scale: 2, representationTypes: .thumbnail)
            guard let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            else { return }
            Self.cache.setObject(image, forKey: key)
            thumbnail = image
        }
    }
}
