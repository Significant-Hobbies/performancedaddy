import AppKit
import Charts
import PerformanceCore
import SwiftUI
import SaaSMakerUI

struct LiveWorkloadsView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var showingStopHistory = false
    @State private var showingAgentHookSetup = false
    @ObservedObject var model: LiveViewModel
    let page: LivePage
    @State private var showingResourceEvidence = false
    @State private var showingHelp = false
    @State private var topMetric: LiveViewModel.ToolbarMetric?
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 18) {
            header.zIndex(20)
            metrics
            if page == .memory { memoryChart }
            controls
            if model.snapshot == nil {
                ProgressView("Reading local processes and listeners…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    processTable.frame(minWidth: min(440, max(300, geometry.size.width - 320)), minHeight: 0, maxHeight: .infinity)
                    if let selected = model.rows(for: page).first(where: { model.selection.contains($0.id) }) ?? model.selected {
                        inspector(selected).frame(minWidth: 260, idealWidth: 320, maxWidth: 390)
                    }
                }
                .frame(minHeight: 100, maxHeight: .infinity)
                .layoutPriority(-1)
            }
            footer
        }
        .padding(24)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .background(PerformanceTheme.fog)
        .helpOverlay()
        .sheet(item: $model.review) { review in StopReviewView(model: model, review: review) }
        .sheet(isPresented: $showingAgentHookSetup) { AgentHookSetupView() }
        .onChange(of: page) { _, page in
            model.selection = []; model.search = ""
            model.sortOrder = page == .memory ? [KeyPathComparator(\LiveProcess.memory, order: .reverse)] :
                page == .ports ? [KeyPathComparator(\LiveProcess.sortPort)] : [KeyPathComparator(\LiveProcess.sortCPU, order: .reverse)]
        }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) { heading; headerActions }
            VStack(alignment: .leading, spacing: 12) {
                heading
                HStack { headerActions }
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                SMSectionHeader(page.rawValue, size: 30).accessibilityLabel(page.rawValue).accessibilityAddTraits(.isHeader)
                Text(page.subtitle).foregroundStyle(PerformanceTheme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            DaddyArtwork(topic: page == .agents ? 8 : 5).frame(width: 72, height: 72)
            Spacer()
        }
    }

    @ViewBuilder private var headerActions: some View {
            if page == .agents {
                Button("insight agent sessions") { openWindow(id: "agent-wall") }.accessibilityLabel("Insight Agent Sessions")
                    .visibleHelp("Open the focused agent activity wall")
                Button("set up statuses…") { showingAgentHookSetup = true }.accessibilityLabel("Set up statuses…")
                    .visibleHelp("Copy local lifecycle hooks for Codex, Claude or Devin")
            }
            Button { showingHelp = true } label: { Image(systemName: "questionmark.circle") }
                .accessibilityLabel("Help with processes and measurements")
                .visibleHelp("Explain columns, memory measurements and safe process actions")
                .popover(isPresented: $showingHelp) { WorkloadHelpView() }
            Button { showingStopHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                .accessibilityLabel("Stop history")
                .visibleHelp("Review stops and later matching process observations")
                .popover(isPresented: $showingStopHistory) { ProcessStopHistoryView(model: model) }
            Button { model.exportSnapshot() } label: { Image(systemName: "square.and.arrow.up") }
                .disabled(model.snapshot == nil)
                .accessibilityLabel("Export redacted snapshot")
                .visibleHelp("Save a local JSON snapshot without names, paths, raw PIDs or bind addresses")
            Button { model.paused.toggle() } label: {
                Label(model.paused ? "resume" : "pause", systemImage: model.paused ? "play.fill" : "pause.fill")
                    .accessibilityLabel(model.paused ? "Resume" : "Pause")
            }.visibleHelp(model.paused ? "Resume live process updates" : "Pause live updates to inspect a stable snapshot")
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(model.refreshing || model.performingAction)
                .accessibilityLabel("Refresh processes")
                .visibleHelp("Refresh processes now. Socket scans are spaced at least thirty seconds apart.")
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            metricButton(.ram, title: "RAM in use · estimate", value: model.usedMemory, detail: "of \(LiveViewModel.bytes(ProcessInfo.processInfo.physicalMemory))", color: PerformanceTheme.mintInk)
            Divider()
            metricButton(.pressure, title: "Memory pressure", value: model.snapshot?.pressure ?? "—", detail: "macOS signal", color: model.snapshot?.pressure == "Normal" ? PerformanceTheme.mintInk : PerformanceTheme.amber)
            Divider()
            metricButton(.swap, title: "Swap", value: model.snapshot?.system.swapUsedBytes.map(LiveViewModel.bytes) ?? "—", detail: "allocated on disk", color: PerformanceTheme.blue)
            Divider()
            metricButton(.sockets, title: "Open sockets", value: model.snapshot == nil || model.snapshot?.portsDate == .distantPast ? "—" : "\(model.portCount)", detail: "TCP listeners · bound UDP", color: PerformanceTheme.cyan)
        }
        .frame(height: 82)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(PerformanceTheme.divider).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(PerformanceTheme.divider).frame(height: 1) }
        .popover(item: $topMetric, arrowEdge: .top) { metric in
            TopContributorsView(metric: metric, model: model)
        }
    }

    private func metricButton(_ kind: LiveViewModel.ToolbarMetric, title: String, value: String, detail: String, color: Color) -> some View {
        Button { topMetric = kind } label: {
            metric(title, value: value, detail: detail, color: color)
        }
        .buttonStyle(MetricButtonStyle())
        .disabled(model.snapshot == nil)
        .accessibilityHint("Show the largest observed processes for this metric")
        .visibleHelp("Show the largest observed processes behind \(title.lowercased())")
    }

    private func metric(_ title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(color)
            Text(detail).font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
            .accessibilityElement(children: .combine)
    }

    private var memoryChart: some View {
        SMCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SMDisplay("RAM over the last five minutes", size: 17).accessibilityLabel("RAM over the last five minutes")
                    Spacer()
                    Text("Compressed: \(model.snapshot?.compressed.map(LiveViewModel.bytes) ?? "—")").foregroundStyle(.secondary)
                }
                Chart(model.memoryHistory) { point in
                    AreaMark(x: .value("Time", point.date), y: .value("Used", point.used * 100))
                        .foregroundStyle(PerformanceTheme.action.opacity(0.10))
                    LineMark(x: .value("Time", point.date), y: .value("Used", point.used * 100))
                        .foregroundStyle(PerformanceTheme.action)
                }.chartYScale(domain: 0...100).frame(height: 110)
                    .accessibilityLabel("Estimated RAM usage history, percentage of physical memory")
                Text("RAM estimate excludes free and inactive pages. Resident process totals include shared memory; they do not add up to system RAM.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { search; actions }
            VStack(alignment: .leading, spacing: 8) { search; HStack { actions } }
        }
    }
    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(PerformanceTheme.secondaryInk)
            TextField("Search name, PID, project or port", text: $model.search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("Search processes, projects and ports")
                .help("Search by process name, PID, role, app, project or port. Command-F focuses search.")
            if !model.search.isEmpty {
                Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Clear search").help("Clear search")
            }
        }.padding(.horizontal, 10).padding(.vertical, 8).frame(minWidth: 180)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(PerformanceTheme.mintInk.opacity(0.35)))
            .background {
                Button("find process") { searchFocused = true }.accessibilityLabel("Find process").keyboardShortcut("f", modifiers: .command).hidden()
            }
    }
    @ViewBuilder private var actions: some View {
        Toggle("include system", isOn: $model.includeSystem).toggleStyle(.checkbox)
            .accessibilityLabel("Include system")
            .help("Include system and other-user processes when macOS allows inspection")
        if page == .workloads || page == .memory {
            Menu("group · \(model.grouping.rawValue.lowercased())") {
                ForEach(LiveViewModel.ProcessGrouping.allCases) { mode in
                    Button { model.grouping = mode } label: {
                        if model.grouping == mode {
                            Label(mode.rawValue.lowercased(), systemImage: "checkmark").accessibilityLabel(mode.rawValue)
                        } else {
                            Text(mode.rawValue.lowercased()).accessibilityLabel(mode.rawValue)
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(PerformanceTheme.mintInk)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(PerformanceTheme.mintInk.opacity(0.35)))
            .fixedSize()
            .accessibilityLabel("Group list rows")
            .accessibilityValue(model.grouping.rawValue)
            .help("Group rows by kind, owning app or service category. App and agent groups are evidence hints, not verified ownership.")
        }
        Menu("stop…") {
            Button("Selected processes (\(model.selection.count))…") { model.prepareSelected() }
                .disabled(model.selection.isEmpty)
            Button("All matching \(page == .ports ? "listeners" : "processes") (\(model.rows(for: page).filter { $0.stopRestriction == nil }.count))…") {
                model.prepare(model.rows(for: page))
            }
            if page == .agents {
                Divider()
                Button("all shown agent families…") { model.prepareFamilies(model.rows(for: page)) }.accessibilityLabel("All shown agent families…")
                    .disabled(model.rows(for: page).isEmpty)
            }
        }.accessibilityLabel("Stop…").menuStyle(.borderlessButton)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(PerformanceTheme.mintInk)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(PerformanceTheme.mintInk.opacity(0.35)))
            .fixedSize().disabled(model.snapshot == nil || model.performingAction)
            .help("Review exact targets before stopping anything. Force stop is a separate explicit choice.")
    }

    private var processTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if page == .ports {
                    sortHeader("PORTS", key: \.sortPort, alignment: .leading).frame(width: 160)
                }
                Color.clear.frame(width: 28, height: 1)
                sortHeader("PROCESS", key: \.sortName, alignment: .leading)
                if page != .ports {
                    sortHeader("RUNNING", key: \.sortRunning, initial: .reverse).frame(width: 64)
                    sortHeader("CPU", key: \.sortCPU, initial: .reverse).frame(width: 54)
                }
                sortHeader("RAM", key: \.memory, initial: .reverse).frame(width: 72)
                if page != .ports {
                    sortHeader("PORTS", key: \.sortPort, alignment: .leading).frame(width: 72)
                }
            }.padding(.horizontal, 4).zIndex(10)
            Rectangle().fill(PerformanceTheme.divider).frame(height: 1)
            if groupsRows {
                List(selection: $model.selection) {
                    ForEach(model.groupedRows(for: page)) { group in
                        Section {
                            ForEach(group.rows) { processRow($0) }
                        } header: {
                            Text("\(group.title) · \(group.rows.count)")
                                .font(.system(size: 10, weight: .semibold)).tracking(1)
                                .foregroundStyle(PerformanceTheme.secondaryInk)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden).background(Color.black)
            } else {
                List(model.rows(for: page), selection: $model.selection) { process in
                    processRow(process)
                }.listStyle(.plain).scrollContentBackground(.hidden).background(Color.black)
            }
        }
        .font(.custom(PerformanceTheme.palette.sansFont, size: 13))
        .overlay {
            if model.rows(for: page).isEmpty {
                ContentUnavailableView {
                    Label(model.search.isEmpty ? "No matching processes observed" : "No matches", systemImage: page.icon)
                } description: {
                    Text(page == .agents ? "Known local agent sessions appear here, including idle ones. Nested agent tools stay in the owning workload and process list." : model.includeSystem ? "Try another name, app, role or port. Inspection can be limited by macOS permissions." : "Try another name, app, role or port, or include system processes.")
                } actions: {
                    if !model.search.isEmpty { Button("clear search") { model.search = "" }.accessibilityLabel("Clear search") }
                }
            }
        }
    }

    private var groupsRows: Bool {
        (page == .workloads || page == .memory) && model.grouping != .none
    }

    private func processRow(_ process: LiveProcess) -> some View {
        HStack(spacing: 6) {
            if page == .ports { prominentPorts(process) }
            ProcessIcon(process: process)
            VStack(alignment: .leading, spacing: 3) {
                Text(process.sortName).fontWeight(.medium).lineLimit(2)
                Text(model.processSubtitle(process))
                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading).help(process.executable)
            if page != .ports {
            Text(uptime(process)).monospacedDigit().frame(width: 64, alignment: .trailing)
                .accessibilityLabel("Running for \(uptime(process))")
            Text(process.cpu.map { String(format: "%.1f%%", $0) } ?? "—").monospacedDigit()
                .accessibilityLabel(process.cpu.map { String(format: "CPU %.1f percent", $0) } ?? "CPU not yet measured")
                .frame(width: 54, alignment: .trailing)
                .help(process.cpu == nil ? "CPU needs two readable samples. Refresh to measure again." : "100% CPU represents one logical core.")
            }
            Text(LiveViewModel.bytes(process.memory)).monospacedDigit()
                .accessibilityLabel("Resident RAM \(LiveViewModel.bytes(process.memory))")
                .foregroundStyle(PerformanceTheme.mintInk).frame(width: 72, alignment: .trailing)
            if page != .ports {
            Text(process.ports.isEmpty ? (process.portsIncomplete ? "Unknown" : "—") : process.portLabel)
                .accessibilityLabel(process.ports.isEmpty ? (process.portsIncomplete ? "Ports unavailable" : "No observed ports") : "Ports \(process.portLabel)")
                .monospacedDigit().foregroundStyle(process.ports.isEmpty ? PerformanceTheme.secondaryInk : PerformanceTheme.cyan)
                .lineLimit(2).frame(width: 72, alignment: .leading)
                .help(process.ports.map { "\($0.transport) \($0.endpoint)" }.joined(separator: "\n"))
            }
        }.padding(.vertical, 6).tag(process.id)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .listRowBackground(model.selection.contains(process.id) ? PerformanceTheme.mintInk.opacity(0.1) : Color.black)
            .contextMenu {
                Button("copy pid") { copy(String(process.id.pid)) }.accessibilityLabel("Copy PID")
                if !process.directory.isEmpty {
                    Button("copy project path") { copy(process.directory) }.accessibilityLabel("Copy project path")
                    Button("open project folder") { NSWorkspace.shared.open(URL(fileURLWithPath: process.directory)) }.accessibilityLabel("Open project folder")
                }
                if !process.executable.isEmpty {
                    Button("reveal executable in finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.executable)])
                    }.accessibilityLabel("Reveal executable in Finder")
                }
                if !process.ports.isEmpty {
                    Button("copy endpoints") { copy(process.ports.map { "\($0.transport) \($0.endpoint)" }.joined(separator: "\n")) }.accessibilityLabel("Copy endpoints")
                }
                Divider()
                Button("stop this process…") { model.prepare([process]) }.accessibilityLabel("Stop this process…").disabled(process.stopRestriction != nil)
                Button("review family stop…") { model.prepareTree(process) }.accessibilityLabel("Review family stop…")
                    .disabled(model.family(of: process).allSatisfy { $0.stopRestriction != nil })
            }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func prominentPorts(_ process: LiveProcess) -> some View {
        let numbers = Set(process.ports.map(\.port)).sorted()
        let query = model.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty ? [] : numbers.filter { String($0).contains(query) }
        let ordered = matches + numbers.filter { !matches.contains($0) }
        return VStack(alignment: .leading, spacing: 5) {
            Text(ordered.prefix(6).map(String.init).joined(separator: ", "))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(PerformanceTheme.cyan)
                .fixedSize(horizontal: false, vertical: true)
            if numbers.count > 6 {
                Text("+\(numbers.count - 6) more · select to inspect")
                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            }
            Text(process.ports.allSatisfy(\.loopback) ? "Observed localhost" :
                    process.ports.allSatisfy({ !$0.loopback }) ? "Observed non-loopback" : "Observed mixed binds")
                .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            if process.portsIncomplete {
                Text("Partial coverage").font(.caption).foregroundStyle(PerformanceTheme.amber)
            }
        }
        .frame(width: 160, alignment: .leading)
        .accessibilityElement(children: .combine)
        .help(process.ports.map { "\($0.transport) \($0.endpoint) · \($0.scope)" }.joined(separator: "\n") +
              "\nBind scope does not prove network reachability. Select the process for every endpoint.")
    }

    private func sortHeader<Value: Comparable>(_ title: String, key: KeyPath<LiveProcess, Value> & Sendable,
                                               initial: SortOrder = .forward, alignment: Alignment = .trailing) -> some View {
        let active = model.sortOrder.first?.keyPath == key
        let ascending = model.sortOrder.first?.order == .forward
        return Button {
            let order: SortOrder = active ? (ascending ? .reverse : .forward) : initial
            model.sortOrder = [KeyPathComparator(key, order: order)]
        } label: {
            HStack(spacing: 4) {
                Text(title.lowercased())
                Image(systemName: active && ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold)).opacity(active ? 1 : 0)
            }.frame(maxWidth: .infinity, minHeight: 28, alignment: alignment).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(active ? PerformanceTheme.mintInk : PerformanceTheme.secondaryInk)
            .accessibilityLabel("Sort by \(title.lowercased())")
            .accessibilityValue(active ? (ascending ? "Ascending" : "Descending") : "Not sorted")
            .accessibilityAddTraits(active ? .isSelected : [])
            .visibleHelp(active ? "Click to reverse sort order" : "Sort by \(title.lowercased())", leading: title == "PROCESS")
    }

    private func inspector(_ process: LiveProcess) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(process.agent ?? process.name).font(.title2.bold()).textSelection(.enabled)
                    Spacer()
                    Button { model.selection = [] } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Close inspector").help("Close inspector")
                }
                Text("PID \(process.id.pid) · \(process.cpu.map { String(format: "%.1f%% CPU", $0) } ?? "Measuring CPU")")
                    .foregroundStyle(.secondary)
                if page == .agents {
                    Text("CPU, RAM and ports include this agent's observed children. Same-provider wrappers are grouped here; separate launches stay separate. Nested providers and shared resident pages can overlap, so do not sum agent rows.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Recognizes \(AgentIdentity.supportedNames.joined(separator: ", ")). The Insight wall adds lifecycle status for locally instrumented Codex, Claude and Devin processes; other agents show status unavailable.")
                        .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                }
                DaddyDetailSection("What is this?") {
                    ProcessUnderstandingView(process: process, ancestor: model.ancestorApp(of: process)).id(ProcessEvidenceKey(process))
                }
                DaddyDetailSection("Context") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Parent: \(parentName(process))")
                        Text("Running for: \(uptime(process))")
                        Text("RAM: \(LiveViewModel.bytes(process.memory))")
                        if !process.directory.isEmpty {
                            Text(process.directory).font(.caption).textSelection(.enabled)
                            Button("open project folder") { NSWorkspace.shared.open(URL(fileURLWithPath: process.directory)) }.accessibilityLabel("Open project folder")
                        }
                        Text(process.executable.isEmpty ? "Executable unavailable" : process.executable)
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                DaddyDetailSection("Resource history") {
                    VStack(alignment: .leading, spacing: 10) {
                        if page == .agents {
                            Text("Root process only · not the combined agent family")
                                .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                        }
                        if let observed = model.observedProcess(process) {
                            if let trend = model.memoryTrend(for: observed) {
                                Text("Resident RAM \(trend.delta >= 0 ? "+" : "−")\(LiveViewModel.bytes(UInt64(trend.delta.magnitude))) over \(Int(trend.seconds))s")
                                Text("Peak \(LiveViewModel.bytes(trend.peak)) · \(trend.samples) observations")
                                    .font(.caption).foregroundStyle(.secondary)
                                if trend.growing {
                                    Text("Large net increase during this window; this does not establish a memory leak.")
                                        .font(.caption).foregroundStyle(PerformanceTheme.amber)
                                }
                            } else {
                                Text("History warming up or outside the 512 largest resident processes.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Physical footprint: \(observed.footprint.map(LiveViewModel.bytes) ?? "Unavailable")")
                            Text("Disk read: \(observed.diskReadBytes.map(LiveViewModel.bytes) ?? "Unavailable")")
                            Text("Disk written: \(observed.diskWrittenBytes.map(LiveViewModel.bytes) ?? "Unavailable")")
                            Text("Disk totals are kernel-accounted bytes since this process started, not current throughput or file contents. Physical footprint and resident RAM are different measures; do not add them.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Process no longer observed.").foregroundStyle(.secondary)
                        }
                        Text("Up to five minutes in memory only. Missing observations, pause and long sampling gaps reset continuity.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                DaddyDetailSection("Ports · \(process.ports.count)") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(process.ports) { port in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .top) {
                                    Text("\(port.transport) \(port.endpoint)").monospaced().textSelection(.enabled)
                                    Spacer()
                                    Button { copy(port.endpoint) } label: { Image(systemName: "doc.on.doc") }
                                        .accessibilityLabel("Copy \(port.transport) endpoint \(port.endpoint)")
                                        .help("Copy \(port.endpoint)")
                                }
                                Text(port.scope).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if process.ports.isEmpty { Text(process.portsIncomplete ? "Socket details unavailable" : "No TCP listeners or bound UDP ports observed").foregroundStyle(.secondary) }
                        if process.ports.contains(where: { !$0.loopback }) {
                            Text("A non-loopback bind can accept traffic on a network interface. Firewall and routing determine reachability.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                let tree = model.family(of: process)
                DaddyDetailSection("Process family · \(tree.count)") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tree.prefix(40)) { child in
                            HStack {
                                Text(child.id == process.id ? child.name : "↳ \(child.name)").lineLimit(1)
                                Spacer()
                                Text(String(child.id.pid)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        if tree.count > 40 { Text("\(tree.count - 40) more descendants").font(.caption) }
                    }.padding(8)
                }
                if let reason = process.stopRestriction {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("stop process…") { model.prepare([process]) }.accessibilityLabel("Stop process…")
                        if tree.count > 1 { Button("stop family…") { model.prepareTree(process) }.accessibilityLabel("Stop family…") }
                    }
                }
                Text("100% CPU represents one logical core. Session rows identify running agent processes, not conversation contents or whether an agent is waiting for input.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.leading, 16).padding(.vertical, 10)
        }
    }
    private func parentName(_ process: LiveProcess) -> String {
        let parent = model.snapshot?.processes.first { $0.id.pid == process.parent }
        return "\(parent?.name ?? "Unavailable") (\(process.parent))"
    }
    private func uptime(_ process: LiveProcess) -> String {
        guard let duration = ProcessUnderstanding.duration(process.id, at: model.snapshot?.date ?? Date()),
              duration < Double(Int.max) else { return "Unknown" }
        let seconds = Int(duration)
        if seconds >= 86_400 { return "\(seconds / 86_400)d \(seconds % 86_400 / 3600)h" }
        return seconds >= 3600 ? "\(seconds / 3600)h \(seconds % 3600 / 60)m" : "\(seconds / 60)m \(seconds % 60)s"
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let notice = model.exportNotice {
                HStack {
                    Text(notice)
                    Button("dismiss") { model.exportNotice = nil }.accessibilityLabel("Dismiss").buttonStyle(.plain)
                }
            }
            if !model.outcomes.isEmpty {
                DisclosureGroup("Last process action · \(model.outcomes.count) targets") {
                    ScrollView {
                        ForEach(Array(model.outcomes.enumerated()), id: \.offset) { _, result in
                            Text("\(result.process.name) (\(result.process.id.pid)): \(model.outcomeText(result))")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.frame(maxHeight: 100)
                }
            }
            HStack {
                Circle().fill(model.paused ? Color.orange : PerformanceTheme.mintInk).frame(width: 6, height: 6)
                Text(model.paused ? "Paused" : "Live · adaptive refresh")
                Text("\(model.rows(for: page).count) shown")
                Spacer()
                if let snapshot = model.snapshot {
                    if snapshot.portsDate == .distantPast { Text("Sockets awaiting refresh") }
                    else { Text("Ports \(snapshot.portsDate, style: .time)") }
                    let partial = snapshot.processes.filter(\.portsIncomplete).count
                    if snapshot.unavailableProcesses > 0 || partial > 0 {
                        Text("Partial coverage")
                            .help("\(snapshot.unavailableProcesses) processes and \(partial) socket inventories unavailable. Permissions, process exits and scan limits can leave partial results.")
                    }
                }
            }
            HStack {
              Text(model.observerSummary)
                .help("PerformanceDaddy's own process CPU and resident memory, plus the most recent collection duration. CPU includes its UI and sampling. This is measured overhead, not a performance-budget pass.")
              Spacer()
              Button { showingResourceEvidence = true } label: {
                  Label("Memory & thermals", systemImage: "thermometer.medium")
              }
              .buttonStyle(DaddyButtonStyle())
              .popover(isPresented: $showingResourceEvidence, arrowEdge: .top) {
                  ResourceEvidenceView(snapshot: model.snapshot, paused: model.paused)
              }
            }
        }.font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
    }
}

private struct StopReviewView: View {
    @ObservedObject var model: LiveViewModel
    let review: LiveViewModel.Review
    @State private var force = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Stop \(review.targets.count) \(review.targets.count == 1 ? "process" : "processes")?").font(.title2.bold())
            Text("Review the exact targets below. Stopping a process can interrupt builds, disconnect clients or lose unsaved work.")
            List(review.targets) { process in
                HStack {
                    VStack(alignment: .leading) {
                        Text(process.name).fontWeight(.medium)
                        Text(process.directory).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("PID \(process.id.pid)").monospacedDigit()
                }
                .listRowBackground(Color.black)
            }.frame(height: 240).listStyle(.plain).scrollContentBackground(.hidden)
            Toggle("Force stop (SIGKILL)", isOn: $force)
            Text(force ? "Force stop does not allow cleanup or saving." : "Requests termination with SIGTERM. Processes that remain running are reported after the action.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("cancel") { model.review = nil }.accessibilityLabel("Cancel").keyboardShortcut(.cancelAction)
                Button(force ? "Force stop \(review.targets.count)" : "Stop \(review.targets.count)", role: .destructive) {
                    Task { await model.confirmStop(force: force) }
                }
            }
        }.padding(24).frame(width: 520).background(Color.black)
            .preferredColorScheme(.dark).tint(PerformanceTheme.mintInk).buttonStyle(DaddyButtonStyle())
    }
}

private struct MetricButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovering && isEnabled ? PerformanceTheme.mint : .clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct DaddyDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SMDisplay(title, size: 10).accessibilityLabel(title.uppercased())
                .foregroundStyle(PerformanceTheme.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(PerformanceTheme.divider).frame(height: 1) }
    }
}
