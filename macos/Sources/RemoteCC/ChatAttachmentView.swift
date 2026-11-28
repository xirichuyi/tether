#if canImport(SwiftUI)
import SwiftUI
import AppKit
import RemoteCCCore

struct ChatAttachmentView: View {
    @EnvironmentObject private var model: AppModel
    let file: Attachment
    @State private var thumbnail: NSImage?
    @State private var loading = false
    @State private var loadTask: Task<Void, Never>?
    @State private var error = ""
    static func isImage(_ name: String) -> Bool { ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains((name as NSString).pathExtension.lowercased()) }
    private var imageFile: Bool { Self.isImage(file.name) }
    var body: some View {
        Group {
            if imageFile && (thumbnail != nil || error.isEmpty) { image } else { chip }
        }
        .contextMenu {
            Button("打开") { model.open(file.path) }
            Button("下载") { model.download(file.path) }
        }
        .task(id: model.isConnected) { if imageFile && thumbnail == nil && model.isConnected { load() } }
        .onDisappear { loadTask?.cancel() }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: WorkbenchTheme.Radius.card) }

    private var image: some View {
        Button { model.open(file.path) } label: {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    WorkbenchTheme.sidebar.frame(width: 200, height: 140)
                        .overlay { Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(WorkbenchTheme.inkMuted.opacity(loading ? 0.35 : 0.7)) }
                }
            }
            .frame(maxWidth: 280, maxHeight: 200).clipShape(shape).overlay(shape.strokeBorder(WorkbenchTheme.border))
        }
        .buttonStyle(.plain).help(file.name).accessibilityLabel(file.name)
    }

    private var chip: some View {
        HStack(spacing: 6) {
            Button { model.open(file.path) } label: {
                HStack(spacing: 8) {
                    Image(systemName: imageFile ? "photo" : "doc.text").foregroundStyle(WorkbenchTheme.accent)
                    Text(file.name).lineLimit(1).truncationMode(.middle)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).foregroundStyle(WorkbenchTheme.inkMuted)
                }
                .font(.caption).padding(.horizontal, 10).padding(.vertical, 7)
                .background(WorkbenchTheme.surface, in: shape).overlay(shape.strokeBorder(WorkbenchTheme.border))
            }
            .buttonStyle(.plain).frame(maxWidth: 320).help(error.isEmpty ? file.name : error)
            if !error.isEmpty {
                Button { load() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(QuietButtonStyle()).help("重试").disabled(loading || !model.isConnected)
            }
        }
    }

    private func load() {
        if let url = model.localImages[file.path], let image = NSImage(contentsOf: url) { thumbnail = image; return }
        guard let session = model.active, let engine = model.engine else { return }
        loading = true; error = ""
        loadTask?.cancel()
        loadTask = Task {
            defer { loading = false }
            if let cached = await engine.files.cachedPreview(session.config, file.path), let data = cached.data {
                thumbnail = NSImage(data: data)
            }
            do {
                let preview = try await engine.files.preview(session.config, file.path)
                guard let data = preview.data, let image = NSImage(data: data) else { error = "此文件无法生成图片预览"; return }
                thumbnail = image
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
#endif
