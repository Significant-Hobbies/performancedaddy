import AppKit
import PerformanceCore
import SwiftUI
import SaaSMakerUI

struct ConfigurationView: View {
    @State private var scan: ConfigurationScan?
    @State private var scanning = false
    @State private var search = ""
    @State private var selection: String?
    @State private var sort = SortKey.path
    @State private var ascending = true
    private enum SortKey { case path, owner, status }

    private var rows: [ConfigurationFile] {
        (scan?.files ?? []).filter {
            search.isEmpty || "\($0.path) \($0.owner) \($0.scope) \($0.status)".localizedCaseInsensitiveContains(search)
        }.sorted {
            let a = sort == .path ? $0.path : sort == .owner ? $0.owner : $0.status
            let b = sort == .path ? $1.path : sort == .owner ? $1.owner : $1.status
            if a == b { return $0.path < $1.path }
            return ascending ? a < b : a > b
        }
    }
    private var selected: ConfigurationFile? { rows.first { $0.id == selection } }

    var body: some View {
        GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    SMSectionHeader("Configuration", size: 30).accessibilityLabel("Configuration").accessibilityAddTraits(.isHeader)
                    Text("Find settings for your local shell and agent tools.")
                        .foregroundStyle(PerformanceTheme.secondaryInk)
                }
                DaddyArtwork(topic: 5).frame(width: 72, height: 72)
                Spacer()
                Button(scanning ? "Scanning…" : "Refresh") { Task { await refresh() } }
                    .disabled(scanning)
            }
            VStack(alignment: .leading, spacing: 6) {
                SMDisplay("Metadata only. Nothing edited or deleted.", size: 17).accessibilityLabel("Metadata only. Nothing edited or deleted.").foregroundStyle(PerformanceTheme.mintInk)
                Text("Known shell and agent paths under your home folder. No project directories or file contents are scanned. Presence and age do not prove use or junk.")
                    .font(.callout).foregroundStyle(PerformanceTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(PerformanceTheme.divider).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(PerformanceTheme.divider).frame(height: 1) }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(PerformanceTheme.secondaryInk)
                TextField("Search file, path, tool or status", text: $search).textFieldStyle(.plain)
                    .accessibilityLabel("Search configuration files")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear configuration search")
                }
            }.padding(10).overlay(RoundedRectangle(cornerRadius: 7).stroke(PerformanceTheme.mintInk.opacity(0.35)))
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    sortHeader("FILE", .path).frame(maxWidth: .infinity, alignment: .leading)
                    sortHeader("TOOL", .owner).frame(width: 110, alignment: .leading)
                    sortHeader("STATUS", .status).frame(width: 180, alignment: .leading)
                }.padding(.horizontal, 4).padding(.bottom, 8)
                Rectangle().fill(PerformanceTheme.divider).frame(height: 1)
                List(rows, selection: $selection) { file in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.name).fontWeight(.medium).lineLimit(1)
                            Text(displayPath(file.path)).font(.caption).foregroundStyle(PerformanceTheme.secondaryInk).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading).help(file.path)
                        Text(file.owner).frame(width: 110, alignment: .leading).lineLimit(1)
                        SMStatusPill(file.status, tone: file.status == "Present" ? .success : .neutral)
                            .frame(width: 180, alignment: .leading)
                    }.padding(.vertical, 6).tag(file.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                        .listRowBackground(selection == file.id ? PerformanceTheme.mintInk.opacity(0.1) : Color.black)
                        .accessibilityElement(children: .combine)
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
            .frame(minHeight: 100, maxHeight: .infinity)
            .layoutPriority(-1)
            .overlay {
                if scan == nil { ProgressView("Checking known configuration paths…") }
                else if scan != nil && rows.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No files found in checked paths" : "No matching files",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(search.isEmpty ? "This is a bounded inventory, not a whole-disk scan." : "Try another file name or tool."))
                }
            }
            if let selected {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selected.path).textSelection(.enabled).font(.caption).lineLimit(2)
                    Text("\(selected.scope) · \(selected.bytes.map(LiveViewModel.bytes) ?? "Size unavailable") · Modified \(selected.modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "unavailable")")
                        .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                    HStack {
                        Text("Known tool location. Loading this file is not verified.")
                            .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
                        Spacer()
                        Button("reveal in finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: selected.path)]) }.accessibilityLabel("Reveal in Finder")
                            .disabled(selected.status != "Present" && selected.status != "Symlink · not followed")
                    }
                }
            }
            if let scan {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(rows.count) shown · \(scan.checkedPaths) paths checked")
                    Text("Metadata: \(scan.sampledAt.formatted(date: .omitted, time: .standard))")
                }.font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            }
        }.padding(24).frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(PerformanceTheme.fog)
            .task { if scan == nil { await refresh() } }
        }
    }

    private func sortHeader(_ title: String, _ key: SortKey) -> some View {
        Button {
            if sort == key { ascending.toggle() } else { sort = key; ascending = true }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if sort == key { Image(systemName: ascending ? "chevron.up" : "chevron.down") }
            }.font(.system(size: 10, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(sort == key ? PerformanceTheme.mintInk : PerformanceTheme.secondaryInk)
            .accessibilityLabel("Sort configurations by \(title.lowercased())")
            .accessibilityValue(sort == key ? (ascending ? "Ascending" : "Descending") : "Not sorted")
    }
    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
    private func refresh() async {
        guard !scanning else { return }
        scanning = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        scan = await Task.detached(priority: .utility) { ConfigurationInventory.scan(home: home) }.value
        selection = nil
        scanning = false
    }
}
