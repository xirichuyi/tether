#if canImport(SwiftUI)
import SwiftUI
import RemoteCCCore

struct MachineHomeView: View {
    @EnvironmentObject private var model: AppModel
    private var recent: [ChatSession] { Array(model.machineSessions.filter { $0.archived != true && !model.projectMissing($0) }.prefix(6)) }
    private var syncing: Bool { model.currentConfig.map { model.syncingMachines.contains($0.key) } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.currentConfig == nil {
                    GettingStartedView()
                } else if let config = model.currentConfig {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("开始工作").font(.system(size: 26, weight: .semibold)).foregroundStyle(WorkbenchTheme.ink)
                        Text(config.displayName).font(.callout).foregroundStyle(WorkbenchTheme.inkMuted).lineSpacing(4)
                    }
                    if !model.isConnected {
                        if model.connectionState.status == .error, !model.connectionState.error.isEmpty {
                            ConnectionFailureNotice(config: config, error: model.connectionState.error)
                        } else {
                            HStack(spacing: 12) {
                                Button(syncing ? "正在连接…" : "连接机器") { model.perform { try await model.connect(config) } }
                                    .buttonStyle(WorkbenchButtonStyle(prominent: true)).disabled(syncing)
                                if syncing { ProgressView().controlSize(.small) }
                            }
                        }
                    }
                    MachineHealthBanner()
                    HStack(spacing: 10) {
                        startAction(
                            title: "在主目录开始", detail: "直接使用这台机器的主目录", icon: "house",
                            prominent: model.isConnected && recent.isEmpty
                        ) {
                            model.perform { try await model.chooseProject("~") }
                        }
                        startAction(title: "打开项目", detail: "浏览或新建远端文件夹", icon: "folder.badge.plus") {
                            model.openProjectPicker()
                        }
                    }
                    .disabled(!model.isConnected).opacity(model.isConnected ? 1 : 0.45)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("最近对话").font(.callout.weight(.medium)).foregroundStyle(WorkbenchTheme.inkMuted)
                            Spacer()
                            if syncing { ProgressView().controlSize(.small) }
                            else {
                                Button { if let config = model.currentConfig { Task { await model.discoverHistory(config) } } } label: { Image(systemName: "arrow.clockwise") }
                                    .buttonStyle(.plain).disabled(!model.isConnected).help("同步远端历史")
                            }
                        }
                        if recent.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(syncing ? "正在读取远端历史…" : "还没有对话").font(WorkbenchMetrics.ui)
                                Text(model.historyStatus)
                                    .font(.callout).foregroundStyle(WorkbenchTheme.inkMuted)
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .background(WorkbenchTheme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: WorkbenchTheme.Radius.medium))
                        } else {
                            VStack(spacing: 4) {
                                ForEach(recent) { session in
                                    Button { model.select(session.id) } label: {
                                        HStack(spacing: 10) {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(historyDisplayTitle(session.name)).font(WorkbenchMetrics.ui).lineLimit(1)
                                                Text(session.directory).font(WorkbenchMetrics.caption).foregroundStyle(WorkbenchTheme.inkMuted).lineLimit(1).truncationMode(.middle)
                                            }
                                            Spacer(minLength: 12)
                                            Text(Date(timeIntervalSince1970: session.updatedAt / 1000), format: .dateTime.month().day())
                                                .font(.caption2).foregroundStyle(WorkbenchTheme.inkDim)
                                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(WorkbenchTheme.inkDim)
                                        }.padding(.vertical, 4).padding(.horizontal, 4).contentShape(Rectangle())
                                    }.buttonStyle(SidebarNavigationStyle())
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 580).padding(.horizontal, 32).padding(.top, 36).padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func startAction(
        title: String, detail: String, icon: String, prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                WorkbenchIcon(symbol: icon).foregroundStyle(prominent ? WorkbenchTheme.accent : WorkbenchTheme.inkMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(WorkbenchMetrics.ui.weight(.medium)).foregroundStyle(WorkbenchTheme.ink)
                    Text(detail).font(WorkbenchMetrics.caption).foregroundStyle(WorkbenchTheme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(WorkbenchTheme.inkDim)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        }
        .buttonStyle(WorkbenchCardButtonStyle(prominent: prominent))
    }
}

/// First launch: a heading and the way to add a server.
struct GettingStartedView: View {
    @EnvironmentObject private var model: AppModel
    static let helpURL = URL(string: "https://github.com/xirichuyi/tether/blob/HEAD/docs/getting-started.md")!

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                BrandIcon(size: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text("欢迎使用 Tether")
                        .font(.system(size: 26, weight: .semibold)).foregroundStyle(WorkbenchTheme.ink)
                    Text("把 macOS 变成远端 Claude 项目的清晰工作台。")
                        .font(.callout).foregroundStyle(WorkbenchTheme.inkMuted)
                }
            }
            HStack(spacing: 12) {
                Button { model.showConnect = true } label: { Label("添加服务器", systemImage: "plus") }
                    .buttonStyle(WorkbenchButtonStyle(prominent: true))
                Link("入门指南", destination: Self.helpURL).font(.callout)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: WorkbenchTheme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: WorkbenchTheme.Radius.card)
                .strokeBorder(WorkbenchTheme.border.opacity(0.7))
        )
    }
}
#endif
