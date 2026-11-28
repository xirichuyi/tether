#if canImport(SwiftUI)
import SwiftUI
import AppKit
import RemoteCCCore

/// Opens from the composer. Picking the server's own default stores nothing, so the chat keeps following it.
struct PermissionMenu: View {
    @EnvironmentObject private var model: AppModel
    /// The remote Claude default; nil while unknown, and then every choice is stored explicitly.
    let remoteMode: String?
    @State private var error = ""

    struct Mode { let id, title, detail, symbol: String }
    static let modes = [
        Mode(id: "default", title: "请求时确认", detail: "改文件、运行命令前先问你", symbol: "hand.raised"),
        Mode(id: "acceptEdits", title: "自动编辑", detail: "直接改文件，运行命令前先问", symbol: "pencil.line"),
        Mode(id: "plan", title: "计划", detail: "只读，先给方案", symbol: "list.bullet.clipboard"),
        Mode(id: "bypassPermissions", title: "Full Access", detail: "不再询问，可执行任何操作", symbol: "exclamationmark.shield"),
    ]
    private static let others = ["dontAsk": "拒绝未授权", "auto": "自动权限"]
    static let danger = Color.orange
    static func label(_ mode: String?) -> String { modes.first { $0.id == mode }?.title ?? mode.flatMap { others[$0] } ?? "请求时确认" }
    static func symbol(_ mode: String?) -> String { modes.first { $0.id == mode }?.symbol ?? "hand.raised" }
    static func effective(_ session: Session?, remote: String?) -> String {
        session?.preferences?.permissionMode.flatMap { $0.isEmpty ? nil : $0 } ?? remote ?? "default"
    }

    var body: some View {
        let current = Self.effective(model.active, remote: remoteMode)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Self.modes, id: \.id) { mode in
                Button { choose(mode.id) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: mode.symbol).font(.system(size: 13)).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(mode.title).font(.system(size: 13, weight: .medium))
                                if mode.id == remoteMode { Text("默认").font(.system(size: 10)).foregroundStyle(WorkbenchTheme.inkMuted) }
                            }
                            Text(mode.detail).font(.system(size: 11)).opacity(0.7)
                        }
                        Spacer(minLength: 12)
                        if mode.id == current { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
                    }
                    .foregroundStyle(mode.id == "bypassPermissions" ? Self.danger : WorkbenchTheme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
                }
                .buttonStyle(PermissionRowStyle())
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(WorkbenchTheme.error).padding(.horizontal, 10).padding(.vertical, 4) }
        }
        .padding(6).frame(width: 300)
    }

    private func choose(_ id: String) {
        guard let engine = model.engine, let session = model.active else { return }
        var next = session.preferences ?? Preferences()
        next.permissionMode = id == remoteMode ? nil : id
        guard next.permissionMode != session.preferences?.permissionMode else { model.showPreferences = false; return }
        error = ""
        Task {
            do { try await engine.configure(session.id, next); model.showPreferences = false }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct PermissionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }
    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(WorkbenchTheme.ink.opacity(configuration.isPressed ? 0.08 : hovering ? 0.05 : 0), in: RoundedRectangle(cornerRadius: WorkbenchTheme.Radius.medium))
                .onHover { hovering = $0 }
        }
    }
}

struct CommandPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    private func dismiss() { model.presentation = nil }
    let interaction: CommandInteraction
    @State private var value = ""
    @State private var custom = ""

    private var options: [CommandOption] {
        var list = interaction.options
        if interaction.kind == .model, let selected = interaction.selected, !list.contains(where: { $0.value == selected }) {
            list.append(CommandOption(value: selected, label: selected))
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("/" + interaction.command).font(.headline)
            WorkbenchSelect(title: interaction.kind == .model ? "选择模型" : "选择参数", selection: $value,
                            options: options.map { WorkbenchOption($0.value, $0.label) })
            if interaction.kind == .model { TextField("或输入自定义模型 ID", text: $custom).textFieldStyle(WorkbenchTextFieldStyle()) }
            if let description = options.first(where: { $0.value == value })?.description ?? interaction.description {
                Text(description).font(.caption).foregroundStyle(WorkbenchTheme.inkMuted)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(interaction.kind == .model ? "切换模型" : "执行") {
                    let choice = custom.trimmingCharacters(in: .whitespaces)
                    model.applyCommandPicker(interaction, value: choice.isEmpty ? value : choice)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(value.isEmpty && custom.isEmpty)
            }
        }
        .padding(20).frame(width: 440)
        .onAppear { value = interaction.selected ?? options.first?.value ?? "" }
    }
}

struct SessionToolsSheet: View {
    @EnvironmentObject private var model: AppModel
    private func dismiss() { model.presentation = nil }
    @State private var localPort = ""
    @State private var remotePort = ""
    @State private var tunnels: [Tunnel] = []
    @State private var error = ""

    private let destinations = [("skills", "技能", "sparkles"), ("commands", "命令", "terminal"),
        ("mcp", "连接器", "point.3.connected.trianglepath.dotted"), ("plugins", "插件", "puzzlepiece.extension"),
        ("agents", "Agents", "person.2"), ("tasks", "后台任务", "checklist"),
        ("config", "记忆与配置", "doc.text"), ("models", "模型", "cpu"),
        ("tools", "工具", "wrench.and.screwdriver"), ("status", "会话状态", "info.circle"), ("ssh", "端口转发", "network")]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: destinations.first { $0.0 == model.sessionToolsSection }?.1 ?? "扩展与配置") { dismiss() }
                .padding(.horizontal, 20).frame(height: 52)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 3) {
                    ForEach(destinations, id: \.0) { item in
                        Button { model.sessionToolsSection = item.0 } label: {
                            Label { Text(item.1) } icon: { WorkbenchIcon(symbol: item.2) }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(SidebarNavigationStyle(selected: model.sessionToolsSection == item.0))
                    }
                    Spacer()
                }.padding(12).frame(width: 160).background(WorkbenchTheme.sidebar)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    if let session = model.active {
                        if model.sessionToolsSection == "ssh" { portForwarding(session) }
                        else { ClaudeToolsView(sessionID: session.id, section: SessionToolSection(rawValue: model.sessionToolsSection) ?? .skills).id(session.id + ":" + model.sessionToolsSection) }
                    } else {
                        Text("打开对话后管理该项目的扩展和配置。").foregroundStyle(WorkbenchTheme.inkMuted)
                        Spacer()
                    }
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.frame(width: 820, height: 600)
        .onAppear { if let session = model.active { tunnels = model.connections?.tunnels(session.config) ?? [] } }
    }

    private func portForwarding(_ session: ChatSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("本地端口", text: $localPort).frame(width: 110)
                TextField("远端端口", text: $remotePort).frame(width: 110)
                Button("转发") { forward(session) }.disabled(Int(localPort) == nil || Int(remotePort) == nil)
            }.textFieldStyle(WorkbenchTextFieldStyle())
            ForEach(tunnels) { tunnel in
                HStack {
                    Button("localhost:\(tunnel.localPort) → 远端 \(tunnel.remotePort)") {
                        if let url = URL(string: "http://127.0.0.1:\(tunnel.localPort)") { NSWorkspace.shared.open(url) }
                    }.buttonStyle(.link)
                    Button("关闭") { close(tunnel, session) }
                }
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(WorkbenchTheme.error) }
            Spacer()
        }
    }

    private func forward(_ session: ChatSession) {
        guard let local = Int(localPort), let remote = Int(remotePort), let connections = model.connections else { return }
        error = ""
        Task {
            do { try await connections.forward(session.config, Tunnel(localPort: local, remotePort: remote)); tunnels = connections.tunnels(session.config) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func close(_ tunnel: Tunnel, _ session: ChatSession) {
        guard let connections = model.connections else { return }
        Task {
            do { try await connections.forward(session.config, tunnel, remove: true); tunnels = connections.tunnels(session.config) }
            catch { self.error = error.localizedDescription }
        }
    }
}
#endif
