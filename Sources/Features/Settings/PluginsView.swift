import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 插件管理

/// 设置 → 插件管理：本地 / 在线导入、插件市场、启用开关与配置
struct PluginsView: View {
    @ObservedObject private var manager = PluginManager.shared

    @State private var tab: PluginTab = .installed
    @State private var showFileImporter = false
    @State private var showURLImport = false
    @State private var settingsPluginID: String?
    @State private var pendingUninstall: InstalledPlugin?
    @State private var message: PluginAlert?

    private enum PluginTab: String, CaseIterable, Identifiable {
        case installed = "已安装"
        case market = "插件市场"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                securityBanner
                importActions

                Picker("插件来源", selection: $tab) {
                    ForEach(PluginTab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch tab {
                case .installed:
                    installedSection
                case .market:
                    marketSection
                }

                Text("iOS 版支持插件导入、启用、配置、网络请求与播放事件（trackChange / lyricChange / lineChange）；音源与歌词覆盖类钩子暂未接入播放链路。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("插件管理")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .sheet(isPresented: $showURLImport) {
            PluginURLImportSheet(manager: manager)
        }
        .sheet(
            isPresented: Binding(
                get: { settingsPluginID != nil },
                set: { if !$0 { settingsPluginID = nil } }
            )
        ) {
            if let settingsPluginID {
                PluginSettingsSheet(manager: manager, pluginID: settingsPluginID)
            }
        }
        .confirmationDialog(
            "卸载插件？",
            isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingUninstall
        ) { plugin in
            Button("卸载", role: .destructive) {
                manager.uninstall(pluginID: plugin.id)
                message = PluginAlert(title: "已卸载", message: "「\(plugin.name)」已从设备移除。")
            }
            Button("取消", role: .cancel) {}
        } message: { plugin in
            Text("将删除「\(plugin.name)」的脚本、配置与本地数据，操作不可恢复。")
        }
        .alert(item: $message) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("好"))
            )
        }
        .task { @MainActor in
            manager.start()
            if manager.marketPlugins.isEmpty {
                await manager.loadMarket()
            }
        }
    }

    // MARK: 顶部

    private var securityBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("安全提示")
                    .font(.subheadline.weight(.semibold))
                Text("插件可以执行脚本、访问网络并读取播放信息，请仅导入可信来源的插件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            Color.orange.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
        }
    }

    private var importActions: some View {
        HStack(spacing: 10) {
            Button {
                showFileImporter = true
            } label: {
                Label("本地导入", systemImage: "doc.badge.plus")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showURLImport = true
            } label: {
                Label("在线导入", systemImage: "link.badge.plus")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: 已安装

    @ViewBuilder
    private var installedSection: some View {
        if manager.plugins.isEmpty {
            ContentUnavailableView(
                "还没有插件",
                systemImage: "puzzlepiece.extension",
                description: Text("从本地选择 .js 插件文件，或填写插件直链导入。")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
        } else {
            VStack(spacing: 10) {
                ForEach(manager.plugins) { plugin in
                    PluginCard(
                        plugin: plugin,
                        manager: manager,
                        hasSettings: !manager.settings(for: plugin.id).isEmpty,
                        isCheckingUpdate: manager.installingIDs.contains(plugin.id),
                        onSettings: { settingsPluginID = plugin.id },
                        onCheckUpdate: { checkUpdate(plugin) },
                        onUninstall: { pendingUninstall = plugin },
                        onMessage: { title, text in
                            message = PluginAlert(title: title, message: text)
                        }
                    )
                }
            }
        }
    }

    // MARK: 插件市场

    @ViewBuilder
    private var marketSection: some View {
        HStack {
            Text("共 \(manager.marketPlugins.count) 个插件")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                Task { await manager.loadMarket() }
            } label: {
                if manager.isLoadingMarket {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.splayerAccent)
            .disabled(manager.isLoadingMarket)
        }

        if manager.isLoadingMarket, manager.marketPlugins.isEmpty {
            ProgressView("正在获取插件市场…")
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
        } else if let error = manager.marketError, manager.marketPlugins.isEmpty {
            ContentUnavailableView(
                "无法加载插件市场",
                systemImage: "wifi.exclamationmark",
                description: Text(error)
            )
            .frame(maxWidth: .infinity)
        } else if manager.marketPlugins.isEmpty {
            ContentUnavailableView(
                "暂无可用插件",
                systemImage: "shippingbox",
                description: Text("插件市场暂时没有内容，稍后再试。")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
        } else {
            VStack(spacing: 10) {
                ForEach(manager.marketPlugins) { item in
                    MarketPluginRow(
                        item: item,
                        isInstalled: manager.isInstalled(marketID: item.id),
                        isInstalling: manager.installingIDs.contains(item.id),
                        onInstall: { installMarket(item) }
                    )
                }
            }
        }
    }

    // MARK: 操作

    private var allowedTypes: [UTType] {
        var types: [UTType] = []
        if let js = UTType(filenameExtension: "js") {
            types.append(js)
        }
        types.append(.plainText)
        return types
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var succeeded = 0
            var failures: [String] = []

            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let data = try Data(contentsOf: url)
                    guard data.count <= PluginManager.maxScriptSize else {
                        throw PluginError.scriptTooLarge
                    }
                    guard let script = String(data: data, encoding: .utf8) else {
                        throw PluginError.downloadFailed("文件不是 UTF-8 文本")
                    }
                    let result = try manager.install(script: script, origin: url.lastPathComponent)
                    succeeded += 1
                    NSLog("[Plugin] 本地导入成功：%@ v%@", result.plugin.name, result.plugin.version)
                } catch {
                    failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                }
            }

            if failures.isEmpty {
                message = PluginAlert(title: "导入完成", message: "已导入 \(succeeded) 个插件。")
            } else {
                let summary = succeeded > 0 ? "成功 \(succeeded) 个。\n" : ""
                message = PluginAlert(
                    title: succeeded > 0 ? "部分导入失败" : "导入失败",
                    message: summary + failures.joined(separator: "\n")
                )
            }
        case .failure(let error):
            message = PluginAlert(title: "导入失败", message: error.localizedDescription)
        }
    }

    private func checkUpdate(_ plugin: InstalledPlugin) {
        Task { @MainActor in
            do {
                let result = try await manager.checkUpdate(pluginID: plugin.id)
                switch result {
                case .upToDate(let version):
                    message = PluginAlert(
                        title: "检查更新",
                        message: "「\(plugin.name)」已是最新版本 v\(version)。"
                    )
                case .updated(let from, let to):
                    message = PluginAlert(
                        title: "已更新",
                        message: "「\(plugin.name)」已从 v\(from) 更新到 v\(to)。"
                    )
                }
            } catch {
                message = PluginAlert(title: "检查更新失败", message: error.localizedDescription)
            }
        }
    }

    private func installMarket(_ item: MarketPlugin) {
        Task { @MainActor in
            do {
                let result = try await manager.installFromMarket(item)
                message = PluginAlert(
                    title: result.isUpdate ? "已更新" : "安装成功",
                    message: "「\(result.plugin.name)」v\(result.plugin.version) 已就绪。"
                )
            } catch {
                message = PluginAlert(title: "安装失败", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - 已安装插件卡片

private struct PluginCard: View {
    let plugin: InstalledPlugin
    @ObservedObject var manager: PluginManager
    let hasSettings: Bool
    let isCheckingUpdate: Bool
    let onSettings: () -> Void
    let onCheckUpdate: () -> Void
    let onUninstall: () -> Void
    let onMessage: (String, String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        LinearGradient(
                            colors: [Color.orange, Color.splayerAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plugin.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Text("v\(plugin.version)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)

                        if isCheckingUpdate {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Text(plugin.author.map { "作者：\($0)" } ?? "未知作者")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { plugin.enabled },
                        set: { manager.setEnabled($0, pluginID: plugin.id) }
                    )
                )
                .labelsHidden()
                .accessibilityLabel("启用 \(plugin.name)")
            }

            if let summary = plugin.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = manager.runtimeErrors[plugin.id], !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if !plugin.grants.isEmpty {
                    Text("权限：\(plugin.grants.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                if hasSettings {
                    Button(action: onSettings) {
                        Label("设置", systemImage: "slider.horizontal.3")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Menu {
                    Button(action: onCheckUpdate) {
                        Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                    }

                    if let homepage = plugin.homepage, let url = URL(string: homepage) {
                        Button {
                            openURL(url)
                        } label: {
                            Label("打开主页", systemImage: "safari")
                        }
                    }

                    Button {
                        UIPasteboard.general.string = plugin.id
                        onMessage("已复制", "插件 ID：\(plugin.id)")
                    } label: {
                        Label("复制插件 ID", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive, action: onUninstall) {
                        Label("卸载插件", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(13)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .opacity(plugin.enabled ? 1 : 0.72)
    }
}

// MARK: - 市场条目

private struct MarketPluginRow: View {
    let item: MarketPlugin
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.splayerAccent)
                    .frame(width: 32, height: 32)
                    .background(
                        Color.splayerAccent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        if let version = item.version, !version.isEmpty {
                            Text("v\(version)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(item.author.map { "作者：\($0)" } ?? "未知作者")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 54)
                } else if isInstalled {
                    Text("已安装")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 54)
                } else {
                    Button("安装", action: onInstall)
                        .font(.caption.weight(.medium))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }
}

// MARK: - 在线导入

private struct PluginURLImportSheet: View {
    @ObservedObject var manager: PluginManager
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var isImporting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/plugin.js", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("插件地址")
                } footer: {
                    Text("填写 .js 插件文件的 http(s) 直链；也可以填写插件市场条目的更新地址。")
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("在线导入")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isImporting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Button("导入") { importPlugin() }
                            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func importPlugin() {
        isImporting = true
        errorText = nil

        Task { @MainActor in
            do {
                let result = try await manager.installFromURL(urlText)
                NSLog("[Plugin] 在线导入成功：%@ v%@", result.plugin.name, result.plugin.version)
                isImporting = false
                dismiss()
            } catch {
                isImporting = false
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - 插件配置

private struct PluginSettingsSheet: View {
    @ObservedObject var manager: PluginManager
    let pluginID: String
    @Environment(\.dismiss) private var dismiss

    private var plugin: InstalledPlugin? {
        manager.plugins.first { $0.id == pluginID }
    }

    private var settings: [PluginSetting] {
        manager.settings(for: pluginID)
    }

    var body: some View {
        NavigationStack {
            Form {
                if settings.isEmpty {
                    Section {
                        Text("该插件没有可配置项。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(settings) { setting in
                            settingRow(setting)
                        }
                    } header: {
                        Text("插件设置")
                    } footer: {
                        Text("修改会立即保存在本地，并通过 onSettingChange 通知插件。")
                    }
                }
            }
            .navigationTitle(plugin.map { "\($0.name) 设置" } ?? "插件设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func settingRow(_ setting: PluginSetting) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if setting.kind == .toggle {
                HStack {
                    Text(setting.label)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    control(for: setting)
                }
            } else {
                Text(setting.label)
                    .font(.subheadline.weight(.medium))
                control(for: setting)
            }

            if let description = setting.description, !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if setting.kind == .number, setting.minValue != nil || setting.maxValue != nil {
                Text("范围：\(minText(setting)) ~ \(maxText(setting))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func control(for setting: PluginSetting) -> some View {
        switch setting.kind {
        case .toggle:
            Toggle(
                "",
                isOn: Binding(
                    get: { value(for: setting).boolValue },
                    set: { manager.updateSetting(pluginID: pluginID, key: setting.key, value: .bool($0)) }
                )
            )
            .labelsHidden()

        case .text:
            TextField(
                setting.placeholder ?? "",
                text: Binding(
                    get: { value(for: setting).stringValue },
                    set: { manager.updateSetting(pluginID: pluginID, key: setting.key, value: .string($0)) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

        case .number:
            TextField(
                "",
                value: Binding(
                    get: { value(for: setting).doubleValue },
                    set: { manager.updateSetting(pluginID: pluginID, key: setting.key, value: .number($0)) }
                ),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .keyboardType(.numbersAndPunctuation)

        case .select:
            Picker(
                setting.label,
                selection: Binding(
                    get: {
                        let current = value(for: setting)
                        if setting.options.contains(where: { $0.value == current }) {
                            return current
                        }
                        return setting.options.first?.value ?? current
                    },
                    set: { manager.updateSetting(pluginID: pluginID, key: setting.key, value: $0) }
                )
            ) {
                ForEach(setting.options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func value(for setting: PluginSetting) -> PluginValue {
        manager.settingValue(pluginID: pluginID, key: setting.key)
            ?? setting.defaultValue
            ?? .string("")
    }

    private func minText(_ setting: PluginSetting) -> String {
        setting.minValue.map { PluginValue.number($0).displayText } ?? "不限"
    }

    private func maxText(_ setting: PluginSetting) -> String {
        setting.maxValue.map { PluginValue.number($0).displayText } ?? "不限"
    }
}

// MARK: - 提示

private struct PluginAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
