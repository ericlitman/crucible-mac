import SwiftUI

enum MenuBarPanelMetrics {
    /// Floor for the scrollable overview so transient measurement states never
    /// collapse the panel body below a usable viewport.
    static let minimumOverviewHeight: CGFloat = 120
    /// Cap for the scrollable overview; content beyond this scrolls.
    static let maximumOverviewHeight: CGFloat = 560
}

struct MenuBarContentView: View {
    let state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var overviewContentHeight: CGFloat = MenuBarPanelMetrics.maximumOverviewHeight

    private let metricColumns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("MenuBarIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Crucible Fleet")
                        .font(.headline)
                    Text("Operator overview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if state.presentation.isPreviewData {
                    PreviewDataBadge()
                }
                if state.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing fleet")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    FreshnessView(presentation: state.presentation, compact: true)

                    if let errorMessage = state.presentation.errorMessage {
                        ErrorMessageView(message: errorMessage)
                    }

                    if let snapshot = state.snapshot {
                        let overview = FleetOverview(snapshot: snapshot)

                        LazyVGrid(columns: metricColumns, spacing: 7) {
                            ForEach(WorkState.allCases) { workState in
                                StateCountCard(state: workState, count: overview.count(for: workState))
                            }
                        }

                        if !snapshot.conditions.isEmpty {
                            sectionHeader("Conditions", count: snapshot.conditions.count)

                            VStack(spacing: 8) {
                                ForEach(snapshot.conditions) { condition in
                                    FleetConditionRow(condition: condition, compact: true)
                                }
                            }
                        }

                        sectionHeader("Hosts", count: overview.hosts.count)

                        VStack(spacing: 2) {
                            ForEach(overview.hosts) { host in
                                Button {
                                    state.selectHost(host.id)
                                    state.dashboardRequested()
                                    openWindow(id: "fleet-dashboard")
                                } label: {
                                    HostRow(host: host)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens host detail in the dashboard")
                            }
                        }

                        sectionHeader("Queue", count: overview.queue.count)

                        VStack(spacing: 5) {
                            ForEach(overview.queue) { item in
                                Button {
                                    state.selectJob(item.id)
                                    state.dashboardRequested()
                                    openWindow(id: "fleet-dashboard")
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: item.state.symbolName)
                                            .foregroundStyle(item.state.tint)
                                            .frame(width: 16)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.id)
                                                .font(.caption.weight(.semibold))
                                            if item.title != item.id {
                                                Text(item.title)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer(minLength: 4)
                                        Text(item.state.title)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens job detail in the dashboard")
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .padding(14)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    overviewContentHeight = height
                }
            }
            // Inside MenuBarExtra(.window) the panel sizes to the content's ideal
            // height, and a ScrollView's ideal height is zero — an explicit height
            // clamped to the measured content keeps the panel content-sized until
            // it reaches the cap, then scrolls.
            .frame(height: min(max(overviewContentHeight, MenuBarPanelMetrics.minimumOverviewHeight), MenuBarPanelMetrics.maximumOverviewHeight))

            Divider()

            HStack(spacing: 8) {
                Button {
                    state.dashboardRequested()
                    openWindow(id: "fleet-dashboard")
                } label: {
                    Label("Open Dashboard", systemImage: "rectangle.3.group")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("o")

                SettingsLink {
                    Image(systemName: "bell.badge")
                        .frame(width: 24)
                        .accessibilityLabel("Notification Settings")
                }
                .help("Notification Settings")
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .frame(width: 370)
        .onAppear {
            state.menuBarDidAppear()
        }
        .onDisappear {
            state.menuBarDidDisappear()
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Text(count, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
