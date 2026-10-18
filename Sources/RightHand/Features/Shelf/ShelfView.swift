import QuickLookThumbnailing
import SwiftUI

/// Shelf tab: files, screenshots and clipboard entries kept at hand.
struct ShelfView: View {
    let store: ShelfStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shelf").font(.headline)
                Text("\(store.items.count)").foregroundStyle(.secondary)
                Spacer()
                Button("Clear", systemImage: "trash") { store.clear() }
                    .buttonStyle(.notchPill())
                    .disabled(store.items.isEmpty)
            }
            if store.items.isEmpty {
                PlaceholderView(
                    systemImage: "tray",
                    title: "Nothing here yet",
                    message: "Drop files here. Screenshots and copied items appear automatically."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(store.items) { item in
                            ShelfItemCard(item: item, store: store)
                        }
                    }
                }
            }
        }
    }
}

/// One card on the Shelf. Click: open the file / copy the text. Drag it out to use it elsewhere.
private struct ShelfItemCard: View {
    let item: ShelfItem
    let store: ShelfStore
    @State private var isHovered = false
    @State private var showsCopied = false

    var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(width: 100, height: 76)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomLeading) { sourceBadge }
                .overlay { if showsCopied { copiedBadge } }
            Text(item.title)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 100, height: 26, alignment: .top)
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
        case .clipboard: "doc.on.clipboard"
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
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 100, height: 76),
                                                       scale: 2, representationTypes: .thumbnail)
            guard let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            else { return }
            Self.cache.setObject(image, forKey: key)
            thumbnail = image
        }
    }
}
