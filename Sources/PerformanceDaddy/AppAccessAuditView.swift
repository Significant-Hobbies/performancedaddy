import SaaSMakerUI
import AppKit
import PerformanceCore
import ServiceManagement
import SwiftUI

struct AppAccessAuditView: View {
    @ObservedObject var live: LiveViewModel
    @State private var audit: AppAccessAudit?
    @State private var scanning = false
    @State private var search = ""
    @State private var selectedPath: String?
    @State private var section = Section.apps
    @State private var reviewNotes: [AppAccessReviewNote] = []
    @State private var reviewSaveFailed = false
    @State private var showOtherAreas = false
    @State private var codeEvidence: InstalledAppCodeEvidence?
    @State private var checkingCode = false
    @State private var fileReview: LaunchFileTrashCandidate?
    @State private var permissionReview: PermissionResetCandidate?
    @State private var actionMessage: String?
    @State private var acting = false
    private let reader = AppAccessAuditReader()
    private let codeReader = InstalledAppCodeEvidenceReader()
    private let reviewStore = AppAccessReviewStore()
    private let permissionResetter = PermissionDecisionResetter()

    private enum Section: String, CaseIterable { case apps = "Apps", startup = "Launch files" }
    private static let primaryAreas = ["Full Disk Access", "Accessibility", "Input Monitoring", "Screen Recording"]
    private static let otherAreas = AppAccessReviewStore.privacyAreas.filter { !primaryAreas.contains($0) }

    private var apps: [AppAccessAuditItem] {
        (audit?.apps ?? []).filter {
            search.isEmpty || "\($0.name) \($0.path) \($0.bundleID ?? "") \($0.declaredRequests.joined(separator: " "))"
                .localizedCaseInsensitiveContains(search)
        }.sorted {
            if reviewPriority($0) != reviewPriority($1) { return reviewPriority($0) > reviewPriority($1) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private var allStartupItems: [StartupAuditItem] {
        (audit?.apps.flatMap(\.startupItems) ?? []) + (audit?.otherStartupItems ?? [])
    }
    private var startupItems: [StartupAuditItem] {
        allStartupItems.filter {
            search.isEmpty || "\($0.label) \($0.context) \($0.source) \($0.executable ?? "")"
                .localizedCaseInsensitiveContains(search)
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    private var selectedApp: AppAccessAuditItem? { apps.first { $0.path == selectedPath } }
    private var selectedStartup: StartupAuditItem? { startupItems.first { $0.id == selectedPath } }

    private func note(for app: AppAccessAuditItem, area: String) -> AppAccessReviewNote? {
        reviewNotes.first { $0.appPath == app.path && $0.bundleID == app.bundleID && $0.area == area }
    }

    private func reviewPriority(_ app: AppAccessAuditItem) -> Int {
        let primaryAllowed = Self.primaryAreas.contains { note(for: app, area: $0)?.status == .shownAllowed }
        let loginEnabled = note(for: app, area: AppAccessReviewStore.loginItemsArea)?.status == .shownAllowed
        let startup = !app.startupItems.isEmpty || loginEnabled
        if primaryAllowed && startup { return 4 }
        if primaryAllowed { return 3 }
        if startup { return 2 }
        if reviewNotes.contains(where: { $0.appPath == app.path && $0.bundleID == app.bundleID }) { return 1 }
        return 0
    }

    private func listCue(_ app: AppAccessAuditItem) -> String {
        switch reviewPriority(app) {
        case 4: return "Review access + startup · Settings notes"
        case 3: return "Sensitive access marked allowed · Settings notes"
        case 2: return app.startupItems.isEmpty ? "Login Item marked enabled · Settings note" : "Launch file found · approval unknown"
        case 1: return "Settings notes saved · check dates in detail"
        default: return "No launch-file match · grants unverified"
        }
    }

    var body: some View {
        GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                PerformancePageHeader(title: "App access", subtitle: "Review launch files and keep dated notes from System Settings.", icon: "lock.shield")
                Button("Review Login Items") { SMAppService.openSystemSettingsLoginItems() }
                Button(scanning ? "Checking…" : "Refresh audit") { Task { await refresh() } }
                    .disabled(scanning)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Partial audit · reviewed actions").font(.headline).foregroundStyle(PerformanceTheme.amber)
                Text("Launch files and Open at Login are separate. Check Login Items and privacy categories in Settings, then record what you see. Dated notes are not live grants. Exact-item Trash and permission-reset actions require a separate review.")
                    .font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 10)
                .overlay(alignment: .top) { Rectangle().fill(PerformanceTheme.divider).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(PerformanceTheme.divider).frame(height: 1) }
            if let actionMessage {
                Text(actionMessage).font(.callout).foregroundStyle(PerformanceTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Picker("Audit section", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 250)
                Image(systemName: "magnifyingglass").foregroundStyle(PerformanceTheme.secondaryInk)
                TextField("Search apps, declarations or launch files", text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search app access audit")
            }.padding(9).overlay(RoundedRectangle(cornerRadius: 7).stroke(PerformanceTheme.mintInk.opacity(0.35)))
            HStack(spacing: 16) {
                List(selection: $selectedPath) {
                    if section == .apps {
                        ForEach(apps) { app in
                            HStack(spacing: 8) {
                                AppBundleIcon(path: app.path, size: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name).fontWeight(.medium).lineLimit(1)
                                    Text(listCue(app))
                                        .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk).lineLimit(1)
                                }
                                Spacer()
                                if app.observedProcesses > 0 {
                                    Text("Observed").font(.caption).foregroundStyle(PerformanceTheme.mintInk)
                                }
                            }.padding(.vertical, 5).tag(app.path)
                                .listRowBackground(selectedPath == app.path ? PerformanceTheme.mintInk.opacity(0.1) : Color.black)
                                .accessibilityElement(children: .combine)
                        }
                    } else {
                        ForEach(startupItems) { item in
                            HStack(spacing: 8) {
                                if let appPath = item.appPath {
                                    AppBundleIcon(path: appPath, size: 28)
                                } else {
                                    Image(systemName: "gearshape.2")
                                        .foregroundStyle(PerformanceTheme.amber).frame(width: 28, height: 28)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.label).fontWeight(.medium).lineLimit(1)
                                    Text(item.context + " · " + item.launch)
                                        .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk).lineLimit(1)
                                }
                                Spacer()
                                if item.observedRunning {
                                    Text("Observed").font(.caption).foregroundStyle(PerformanceTheme.mintInk)
                                }
                            }.padding(.vertical, 5).tag(item.id)
                                .listRowBackground(selectedPath == item.id ? PerformanceTheme.mintInk.opacity(0.1) : Color.black)
                                .accessibilityElement(children: .combine)
                        }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden).tint(PerformanceTheme.mintInk)
                    .frame(minWidth: 280, maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)
                    .layoutPriority(-1)
                    .overlay {
                        if audit == nil { ProgressView("Checking app and startup metadata…") }
                        else if section == .apps && apps.isEmpty { ContentUnavailableView("No matching apps", systemImage: "app.dashed") }
                        else if section == .startup && startupItems.isEmpty { ContentUnavailableView("No matching launch files", systemImage: "gearshape.2") }
                    }
                Rectangle().fill(PerformanceTheme.divider).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if section == .apps, let app = selectedApp { appDetail(app) }
                        else if section == .startup, let item = selectedStartup { startupDetail(item) }
                        else {
                            Text("Choose an app to review").font(.title2.bold())
                            Text("Open its Login Items and Privacy & Security settings, record only what you can see, and use the dated notes to decide which access is still needed.")
                                .foregroundStyle(PerformanceTheme.secondaryInk)
                            Text("Launch files and app declarations are clues, not permission results.")
                                .font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minWidth: 280, maxWidth: .infinity)
                    .id(selectedPath)
            }.frame(minHeight: 100, maxHeight: .infinity)
                .layoutPriority(-1)
            if let audit {
                let userAgents = allStartupItems.filter { $0.context == "User login agent" }.count
                let sharedAgents = allStartupItems.filter { $0.context == "All-user login agent" }.count
                let systemDaemons = allStartupItems.filter { $0.context == "System startup daemon" }.count
                Text("\(audit.apps.count) top-level apps · \(audit.checkedStartupFiles) launch files checked · \(audit.unavailable) unavailable entries\(audit.limited ? " · scan limit reached" : "") · \(audit.date.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                Text("\(userAgents) user agents · \(sharedAgents) all-user agents · \(systemDaemons) system daemons · Open at Login is reviewed in Settings")
                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            }
        }.padding(24)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(PerformanceTheme.fog)
            .task {
                reviewNotes = await reviewStore.load()
                if audit == nil { await refresh() }
            }
            .onChange(of: section) { _, _ in selectedPath = nil }
            .onChange(of: selectedPath) { _, _ in
                codeEvidence = nil
                showOtherAreas = false
                reviewSaveFailed = false
            }
            .sheet(item: $fileReview) { candidate in fileReviewSheet(candidate) }
            .sheet(item: $permissionReview) { candidate in permissionReviewSheet(candidate) }
        }
    }

    @ViewBuilder
    private func appDetail(_ app: AppAccessAuditItem) -> some View {
        HStack(spacing: 10) {
            AppBundleIcon(path: app.path, size: 44)
            Text(app.name).font(.title2.bold()).accessibilityAddTraits(.isHeader)
        }
        Text(app.path).font(.caption).foregroundStyle(PerformanceTheme.secondaryInk).textSelection(.enabled)
        if let bundleID = app.bundleID {
            Text("Bundle ID: \(bundleID)").font(.caption).textSelection(.enabled)
        }
        Text("Review in System Settings").font(.headline).accessibilityAddTraits(.isHeader)
        Text("Record only what you see. Saved notes show when you checked; they are not a live permission readout.")
            .font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
        Button("Review Login Items in Settings") { SMAppService.openSystemSettingsLoginItems() }
        reviewRow(app, area: AppAccessReviewStore.loginItemsArea)
        Button("Open System Settings") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
        ForEach(Self.primaryAreas, id: \.self) { area in
            reviewRow(app, area: area)
        }
        DisclosureGroup("Other privacy categories", isExpanded: $showOtherAreas) {
            ForEach(Self.otherAreas, id: \.self) { area in
                reviewRow(app, area: area)
            }
        }
        if reviewPriority(app) == 4 {
            Text("Review cue: a sensitive category was marked allowed and startup evidence exists. Check whether both are still needed.")
                .foregroundStyle(PerformanceTheme.amber)
        }
        if reviewSaveFailed {
            Text("Could not save the Settings note. Try again; the previous notes are unchanged.")
                .foregroundStyle(PerformanceTheme.coral)
        }
        Text("Read-only evidence").font(.headline).accessibilityAddTraits(.isHeader)
        Text(audit?.liveSampleAvailable == false ? "Live process sample unavailable. Running state is unknown." :
             app.observedProcesses > 0 ? "\(app.observedProcesses) process(es) observed in the latest live sample." : "No process observed in the latest live sample.")
        Text("Launch files").font(.subheadline.bold())
        if app.startupItems.isEmpty {
            Text("No matching launch file found. This does not cover Login Items or prove the app cannot start automatically.")
        } else {
            ForEach(app.startupItems) { item in startupSummary(item) }
        }
        Text("App declarations").font(.subheadline.bold())
        Text(app.declaredRequests.isEmpty
             ? "No known privacy purpose string found. This does not prove the app lacks sensitive access."
             : "App declares possible requests for: \(app.declaredRequests.joined(separator: ", ")). These are not current grants.")
            .foregroundStyle(PerformanceTheme.secondaryInk)
        Text("App bundle code declarations").font(.headline).accessibilityAddTraits(.isHeader)
        if let codeEvidence {
            if codeEvidence.status == .valid {
                Text("On-disk app bundle signature valid. This does not verify running code, notarization or safety.")
                if let team = codeEvidence.team { Text("Team: \(team)").textSelection(.enabled) }
                Text(codeEvidence.sandboxed == true ? "App Sandbox declared" : "App Sandbox not declared")
                Text(codeEvidence.declaredCapabilities.isEmpty ? "No mapped capabilities found; absence does not rule out access." :
                     "Declared entitlements: \(codeEvidence.declaredCapabilities.joined(separator: ", ")). These are not privacy grants.")
                    .foregroundStyle(PerformanceTheme.secondaryInk)
            } else {
                Text("Code identity unavailable. This does not establish that the app is unsafe.")
                    .foregroundStyle(PerformanceTheme.secondaryInk)
            }
            Text("Checked \(codeEvidence.checkedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
        }
        Button(checkingCode ? "Checking code…" : "Inspect app bundle code") {
            checkingCode = true
            Task {
                let result = await codeReader.inspect(path: app.path)
                if selectedPath == app.path { codeEvidence = result }
                checkingCode = false
            }
        }.disabled(checkingCode)
    }

    private func reviewRow(_ app: AppAccessAuditItem, area: String) -> some View {
        let observation = note(for: app, area: area)
        let enabled = area == AppAccessReviewStore.loginItemsArea
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(area)
                Spacer()
                if observation?.status == .shownAllowed {
                    if let reset = PermissionResetCandidate(app: app, area: area) {
                        Button("Reset…") { permissionReview = reset }
                            .font(.caption)
                            .accessibilityLabel("Reset \(area) decision for \(app.name)")
                    } else {
                        Button("Change in Settings") {
                            if enabled { SMAppService.openSystemSettingsLoginItems() }
                            else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
                        }.font(.caption)
                    }
                }
                Menu {
                    Button(enabled ? "Shown enabled" : "Shown allowed") {
                        Task { await record(.shownAllowed, app: app, area: area) }
                    }
                    Button("Shown off") { Task { await record(.shownOff, app: app, area: area) } }
                    Button("Not listed") { Task { await record(.notListed, app: app, area: area) } }
                    if observation != nil {
                        Divider()
                        Button("Clear note") { Task { await removeNote(app: app, area: area) } }
                    }
                } label: {
                    Text(statusText(observation?.status, enabled: enabled))
                        .font(.callout).foregroundStyle(observation?.status == .shownAllowed ? PerformanceTheme.amber : PerformanceTheme.secondaryInk)
                }.accessibilityLabel("\(area): \(statusText(observation?.status, enabled: enabled))")
            }
            if let observation {
                Text("You checked \(observation.checkedAt.formatted(date: .abbreviated, time: .shortened)) · recheck if settings changed")
                    .font(.caption2).foregroundStyle(PerformanceTheme.secondaryInk)
            }
        }.padding(.vertical, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(PerformanceTheme.divider).frame(height: 1) }
    }

    private func statusText(_ status: AppAccessReviewStatus?, enabled: Bool) -> String {
        switch status {
        case .shownAllowed: enabled ? "Shown enabled" : "Shown allowed"
        case .shownOff: "Shown off"
        case .notListed: "Not listed"
        case nil: "Not checked"
        }
    }

    private func record(_ status: AppAccessReviewStatus, app: AppAccessAuditItem, area: String) async {
        do {
            reviewNotes = try await reviewStore.record(appPath: app.path, bundleID: app.bundleID,
                                                       area: area, status: status)
            reviewSaveFailed = false
        } catch { reviewSaveFailed = true }
    }

    private func removeNote(app: AppAccessAuditItem, area: String) async {
        do {
            reviewNotes = try await reviewStore.remove(appPath: app.path, area: area)
            reviewSaveFailed = false
        } catch { reviewSaveFailed = true }
    }

    @ViewBuilder
    private func startupDetail(_ item: StartupAuditItem) -> some View {
        Text(item.label).font(.title2.bold()).accessibilityAddTraits(.isHeader)
        startupSummary(item)
        Text("Configuration plus a running process does not establish what launched it, whether the item is approved, or whether it will launch at next login.")
            .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
        Button("Review Login Items in Settings") { SMAppService.openSystemSettingsLoginItems() }
    }

    private func startupSummary(_ item: StartupAuditItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.context).fontWeight(.medium)
            if let appPath = item.appPath {
                Text("App: \(appPath)").font(.caption).textSelection(.enabled)
            }
            Text(item.launch)
            Text(item.keepAlive)
            Text(audit?.liveSampleAvailable == false ? "Live process sample unavailable" :
                 item.observedRunning ? "Exact executable observed running" : "Exact executable not observed in latest sample")
            Text(item.executable ?? "Executable unavailable in launch file")
                .font(.caption).textSelection(.enabled)
            Text(item.source).font(.caption).foregroundStyle(PerformanceTheme.secondaryInk).textSelection(.enabled)
            HStack {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.source)])
                }
                if item.context == "User login agent" {
                    Button("Move launch file to Trash…", role: .destructive) { prepareTrash(item) }
                }
            }
        }.padding(.vertical, 8)
            .overlay(alignment: .top) { Rectangle().fill(PerformanceTheme.divider).frame(height: 1) }
    }

    private func refresh() async {
        guard !scanning else { return }
        scanning = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let processes = live.snapshot?.processes ?? []
        audit = await reader.scan(home: home, processes: processes, liveSampleAvailable: live.snapshot != nil)
        selectedPath = nil
        scanning = false
    }

    private func prepareTrash(_ item: StartupAuditItem) {
        do {
            fileReview = try LaunchFileTrashCandidate(item: item,
                home: FileManager.default.homeDirectoryForCurrentUser.path)
            actionMessage = nil
        } catch { actionMessage = error.localizedDescription }
    }

    private func moveToTrash(_ candidate: LaunchFileTrashCandidate) async {
        guard !acting else { return }
        acting = true
        do {
            try await candidate.moveToTrash()
            fileReview = nil
            actionMessage = "Moved \(candidate.item.label)'s launch file to Trash. A running process was not stopped; the app may recreate the file."
            await refresh()
        } catch { actionMessage = error.localizedDescription; fileReview = nil }
        acting = false
    }

    private func resetPermission(_ candidate: PermissionResetCandidate) async {
        guard !acting else { return }
        acting = true
        do {
            try await permissionResetter.reset(candidate)
            permissionReview = nil
            do {
                reviewNotes = try await reviewStore.remove(appPath: candidate.appPath, area: candidate.area)
                actionMessage = "macOS reset \(candidate.area) for \(candidate.appName). The app may ask again; recheck System Settings."
            } catch {
                actionMessage = "macOS reset the decision, but the saved note could not be cleared. Recheck System Settings."
            }
        } catch { actionMessage = error.localizedDescription; permissionReview = nil }
        acting = false
    }

    private func fileReviewSheet(_ candidate: LaunchFileTrashCandidate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move launch file to Trash?").font(.title2.bold())
            Text(candidate.item.label).fontWeight(.medium)
            Text(candidate.item.source).font(.caption).textSelection(.enabled)
            Text("Only this file will move to Trash. A running service will not stop, and its app may recreate the file. You can restore the file from Trash.")
                .foregroundStyle(PerformanceTheme.secondaryInk)
            HStack {
                Spacer()
                Button("Cancel") { fileReview = nil }.keyboardShortcut(.cancelAction)
                Button("Move to Trash", role: .destructive) { Task { await moveToTrash(candidate) } }
                    .disabled(acting)
            }
        }.padding(24).frame(width: 520).background(Color.black)
            .preferredColorScheme(.dark).tint(PerformanceTheme.mintInk).buttonStyle(SMButtonStyle(.outline, size: .compact))
    }

    private func permissionReviewSheet(_ candidate: PermissionResetCandidate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reset macOS permission decision?").font(.title2.bold())
            Text(candidate.appName).fontWeight(.medium)
            Text("\(candidate.area) · \(candidate.bundleID)").font(.callout).textSelection(.enabled)
            Text("Your dated note says this was allowed; PerformanceDaddy cannot verify the live grant. macOS will forget this decision and the app may ask again. To keep access off, turn it off in System Settings.")
                .foregroundStyle(PerformanceTheme.secondaryInk)
            HStack {
                Spacer()
                Button("Cancel") { permissionReview = nil }.keyboardShortcut(.cancelAction)
                Button("Reset decision", role: .destructive) { Task { await resetPermission(candidate) } }
                    .disabled(acting)
            }
        }.padding(24).frame(width: 520).background(Color.black)
            .preferredColorScheme(.dark).tint(PerformanceTheme.mintInk).buttonStyle(SMButtonStyle(.outline, size: .compact))
    }
}
