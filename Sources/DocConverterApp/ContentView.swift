import SwiftUI
import AppKit
import DocCore

struct ContentView: View {
    @EnvironmentObject var model: ConverterModel
    // 命令行工具链缺少 SwiftUI 宏插件，这里直接使用 State 结构体而不是 @State
    private var dropTargetedState = State(initialValue: false)
    private var showAdvancedState = State(initialValue: ProcessInfo.processInfo.environment["DOCCONVERTER_SNAPSHOT_ADVANCED"] == "1")
    private var rejectedState = State<String?>(initialValue: nil)
    private var dropTargeted: Bool { dropTargetedState.wrappedValue }
    private var rejectedMessage: String? { rejectedState.wrappedValue }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.jobs.isEmpty {
                    DropZone(targeted: dropTargeted, extensions: model.supportedExtensions) { model.chooseFiles() }
                        .padding(20)
                } else {
                    FileList(rejectedMessage: rejectedState.projectedValue)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 190, maxHeight: .infinity)
            .clipped()

            Divider()
            SettingsPanel(showAdvanced: showAdvancedState.projectedValue)
                .layoutPriority(1)
        }
        .frame(minWidth: 780, minHeight: 640)
        .dropDestination(for: URL.self) { urls, _ in
            let rejected = model.add(urls)
            showRejected(rejected)
            return true
        } isTargeted: { dropTargetedState.wrappedValue = $0 }
        .overlay(alignment: .top) {
            if let msg = rejectedMessage {
                Text(msg)
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: rejectedMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { LanguageMenu() }
        }
        .navigationTitle(L.appName)   // 窗口标题随语言切换更新
    }

    func showRejected(_ names: [String]) {
        guard !names.isEmpty else { return }
        let shown = Array(names.prefix(3))
        rejectedState.wrappedValue = L.ignoredFiles(L.list(shown), shown: shown.count, total: names.count)
        let state = rejectedState
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { state.wrappedValue = nil }
    }
}

// MARK: - 拖放区

struct DropZone: View {
    let targeted: Bool
    let extensions: [String]
    let choose: () -> Void

    var body: some View {
        // 区域较矮时（窗口小、高级选项展开）依次省略图标和提示，保证按钮可见
        ViewThatFits(in: .vertical) {
            content(icon: true, hint: true)
            content(icon: false, hint: true)
            content(icon: false, hint: false)
            Button(action: choose) { Label(L.chooseFiles, systemImage: "plus") }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(targeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: targeted ? 2 : 1.2, dash: [7, 5]))
        )
        .animation(.easeOut(duration: 0.15), value: targeted)
    }

    private func content(icon: Bool, hint: Bool) -> some View {
        VStack(spacing: icon ? 18 : 12) {
            if icon {
                ZStack {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(Color.accentColor.opacity(0.25))
                        .offset(x: -16, y: -6)
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .offset(x: 14, y: 6)
                }
                .frame(height: 84)
            }
            VStack(spacing: 6) {
                Text(L.dropTitle)
                    .font(.title2.weight(.semibold))
                Text(L.dropSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: choose) {
                Label(L.chooseFiles, systemImage: "plus")
                    .padding(.horizontal, 8)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            if hint {
                Text(L.dropHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - 文件列表

struct FileList: View {
    @EnvironmentObject var model: ConverterModel
    @Binding var rejectedMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(L.fileCount(model.jobs.count))
                    .font(.headline)
                if model.isConverting {
                    Text(L.convertingProgress(min(model.completed + 1, model.totalToConvert), model.totalToConvert))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.chooseFiles() } label: { Label(L.add, systemImage: "plus") }
                if model.jobs.contains(where: \.isFinished) {
                    Button(L.removeFinished) { model.clearFinished() }.disabled(model.isConverting)
                }
                Button(L.clear) { model.clear() }.disabled(model.isConverting)
            }
            .controlSize(.regular)
            .padding(.horizontal, 20).padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.jobs) { job in
                        JobRow(job: job)
                        Divider().padding(.leading, 70)
                    }
                }
            }
        }
    }
}

struct FormatIcon: View {
    let format: Format?
    var size: CGFloat = 38

    var body: some View {
        let tint = format?.tint ?? .gray
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(tint.gradient)
            Image(systemName: format?.symbol ?? "questionmark")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxHeight: .infinity)
                .offset(y: -size * 0.08)
            Text((format?.rawValue ?? "?").uppercased())
                .font(.system(size: size * 0.2, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.bottom, size * 0.07)
        }
        .frame(width: size, height: size)
    }
}

struct JobRow: View {
    @EnvironmentObject var model: ConverterModel
    @ObservedObject var job: Job
    private var hoverState = State(initialValue: false)
    private var hovering: Bool { hoverState.wrappedValue }

    init(job: Job) { self.job = job }

    var body: some View {
        HStack(spacing: 14) {
            FormatIcon(format: job.format)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusLine
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hoverState.wrappedValue = $0 }
        .contextMenu {
            Button(L.revealSource) { model.reveal([job.url]) }
            if case .done(let outs) = job.status {
                Button(L.revealResult) { model.reveal(outs) }
                Button(L.openResult) { outs.first.map(model.open) }
            }
            Divider()
            Button(L.removeFromList) { model.remove(job) }.disabled(model.isConverting)
        }
    }

    /// 文件大小（十进制单位，与 Finder 一致；不随系统地区变化，避免与界面语言不一致）
    static func formatSize(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1000 { return "\(bytes) B" }
        if b < 1_000_000 { return "\(Int((b / 1000).rounded())) KB" }
        if b < 1_000_000_000 { return String(format: "%.1f MB", b / 1_000_000) }
        return String(format: "%.2f GB", b / 1_000_000_000)
    }

    @ViewBuilder var statusLine: some View {
        switch job.status {
        case .waiting:
            Text("\(job.format?.displayName ?? L.unknownFormat) · \(Self.formatSize(job.size))")
                .font(.caption).foregroundStyle(.secondary)
        case .running:
            Text(L.convertingStatus).font(.caption).foregroundStyle(.secondary)
        case .done(let outs):
            Text("→ " + L.list(outs.map(\.lastPathComponent)))
                .font(.caption).foregroundStyle(.green).lineLimit(1).truncationMode(.middle)
        case .failed(let msg):
            Text(msg).font(.caption).foregroundStyle(.red).lineLimit(2)
        case .skipped(let msg):
            Text(L.skipped(msg)).font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder var trailing: some View {
        switch job.status {
        case .waiting:
            if !model.isConverting {
                Button { model.remove(job) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0.0)
                    .help(L.removeFromList)
            }
        case .running:
            ProgressView().controlSize(.small)
        case .done(let outs):
            HStack(spacing: 6) {
                Button(L.open) { outs.first.map(model.open) }
                Button { model.reveal(outs) } label: { Image(systemName: "magnifyingglass") }
                    .help(L.showInFinder)
            }
            .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .skipped:
            Image(systemName: "arrow.uturn.right.circle").foregroundStyle(.orange)
        }
    }
}

// MARK: - 设置面板

/// 设置区的内容高度：窗口够高时完整显示，不够高时设置区内部滚动，「开始转换」按钮始终可见
private struct SettingsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SettingsPanel: View {
    @EnvironmentObject var model: ConverterModel
    @Binding var showAdvanced: Bool
    private var contentHeightState = State(initialValue: CGFloat(360))

    init(showAdvanced: Binding<Bool>) { _showAdvanced = showAdvanced }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                options
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: SettingsHeightKey.self, value: g.size.height)
                    })
            }
            .frame(maxHeight: max(80, contentHeightState.wrappedValue))
            .onPreferenceChange(SettingsHeightKey.self) { h in
                if h > 0, abs(h - contentHeightState.wrappedValue) > 0.5 { contentHeightState.wrappedValue = h }
            }
            actionBar
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .background(.bar)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.convertTo).font(.headline)
            TargetGrid()

            if let note = model.fidelityNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Text(L.saveTo).font(.headline)
                Picker("", selection: $model.outputLocation) {
                    ForEach(ConverterModel.OutputLocation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if model.outputLocation == .custom {
                    Button(L.chooseEllipsis) { model.chooseFolder() }
                }
                Text(model.outputFolderDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            DisclosureGroup(isExpanded: $showAdvanced) {
                AdvancedOptions().padding(.top, 8)
            } label: {
                Text(L.advancedOptions).font(.subheadline.weight(.medium))
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { showAdvanced.toggle() } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if model.isConverting {
                ProgressView(value: Double(model.completed), total: Double(max(1, model.totalToConvert)))
                    .frame(maxWidth: 260)
                Text("\(model.completed) / \(model.totalToConvert)")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            } else if !model.lastOutputs.isEmpty {
                Label(L.outputsDone(model.lastOutputs.count), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
                Button(L.showInFinder) { model.reveal(model.lastOutputs) }
            }
            Spacer(minLength: 8)
            Button {
                model.start()
            } label: {
                Text(model.isConverting ? L.convertingButton : (model.pendingCount > 0 ? L.startConvertCount(model.pendingCount) : L.startConvert))
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canStart)
        }
    }
}

struct TargetGrid: View {
    @EnvironmentObject var model: ConverterModel
    let columns = [GridItem(.adaptive(minimum: 136, maximum: 190), spacing: 8)]

    var body: some View {
        let available = Set(model.availableTargets)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(model.engine.outputFormats) { f in
                let enabled = available.contains(f)
                let selected = model.target == f
                Button { model.target = f } label: {
                    HStack(spacing: 8) {
                        Image(systemName: f.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? .white : f.tint)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(f.shortName).font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Text(f.targetSubtitle).font(.system(size: 10)).opacity(0.75)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? .white : .primary)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? AnyShapeStyle(f.tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.05)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? Color.clear : Color.primary.opacity(0.08))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled || model.isConverting)
                .opacity(enabled ? 1 : 0.35)
                .help(enabled ? f.displayName : L.cannotConvertTo(f.displayName))
            }
        }
    }
}

struct AdvancedOptions: View {
    @EnvironmentObject var model: ConverterModel

    /// 左侧标签列宽度：按当前语言实际文字宽度计算，保证任何语言都完整显示
    private var labelWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .callout)
        let labels = [L.pageLabel, L.readPDF, "PowerPoint", L.imagesLabel, L.highFidelity]
        let widest = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 80
        return ceil(widest) + 2
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(L.pageLabel) {
                HStack {
                    Picker("", selection: $model.options.pageSize) {
                        ForEach(PageSize.allCases) { Text($0.displayName).tag($0) }
                    }.labelsHidden().fixedSize()
                    Toggle(L.landscape, isOn: $model.options.landscape)
                    Stepper(L.bodyFontSize(Int(model.options.baseFontSize)), value: $model.options.baseFontSize, in: 8...20, step: 1)
                        .fixedSize()
                    Picker(L.margins, selection: $model.options.marginPt) {
                        Text(L.marginNarrow).tag(36.0); Text(L.marginNormal).tag(56.0); Text(L.marginWide).tag(72.0)
                    }.fixedSize()
                }
            }
            row(L.readPDF) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $model.options.pdfReadMode) {
                        ForEach(PDFReadMode.allCases) { Text($0.displayName).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                    Toggle(L.ocrScannedPages, isOn: $model.options.ocrScannedPages)
                }
            }
            row("PowerPoint") {
                HStack {
                    Picker(L.slideSplitLabel, selection: $model.options.slideSplitLevel) {
                        ForEach(1...3, id: \.self) { Text(L.headingLevel($0)).tag($0) }
                    }.fixedSize()
                    Toggle(L.includeSpeakerNotes, isOn: $model.options.includeSpeakerNotes)
                }
            }
            row(L.imagesLabel) {
                HStack {
                    Picker(L.resolution, selection: $model.options.imageDPI) {
                        Text("72 DPI").tag(72.0); Text("150 DPI").tag(150.0); Text("300 DPI").tag(300.0)
                    }.fixedSize()
                    Toggle(L.embedImagesInMarkdown, isOn: $model.options.embedImagesInMarkdown)
                }
            }
            row(L.highFidelity) {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(L.useLibreOffice, isOn: $model.options.useLibreOffice)
                        .disabled(!model.libreOfficeAvailable)
                    if !model.libreOfficeAvailable {
                        Text(L.libreOfficeMissing)
                            .font(.caption).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(.callout)
        .disabled(model.isConverting)
    }
}
