import SwiftUI

struct FleetDashboardView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            DashboardStatusBar(presentation: state.presentation)
            Divider()

            if let snapshot = state.snapshot {
                NavigationSplitView {
                    HostSidebarView(state: state, snapshot: snapshot)
                } content: {
                    HostWorkView(state: state)
                } detail: {
                    FleetDetailView(detail: state.selectionDetail)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                ContentUnavailableView(
                    "Fleet data unavailable",
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text("Crucible.app will remain empty until a versioned CLI snapshot is available.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .onAppear {
            state.dashboardDidAppear()
        }
    }
}

private struct DashboardStatusBar: View {
    let presentation: FleetPresentation

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                FreshnessView(presentation: presentation, compact: true)
                if presentation.isPreviewData {
                    PreviewDataBadge()
                }
            }

            if let errorMessage = presentation.errorMessage {
                ErrorMessageView(message: errorMessage)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct HostSidebarView: View {
    let state: AppState
    let snapshot: FleetSnapshot

    private var selection: Binding<String?> {
        Binding(
            get: { state.selectedHostID },
            set: { hostID in
                if let hostID {
                    state.selectHost(hostID)
                }
            }
        )
    }

    var body: some View {
        List(snapshot.hosts, selection: selection) { host in
            HostRow(host: host)
                .tag(host.id)
        }
        .listStyle(.sidebar)
        .navigationTitle("Hosts")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
    }
}

private struct HostWorkView: View {
    let state: AppState

    private var selection: Binding<FleetSelection?> {
        Binding(
            get: { state.selection },
            set: { newSelection in
                if let newSelection {
                    state.select(newSelection)
                }
            }
        )
    }

    var body: some View {
        if let host = state.selectedHost {
            List(selection: selection) {
                Section("Host") {
                    Label(host.displayName, systemImage: host.condition.symbolName)
                        .tag(FleetSelection.host(hostID: host.id))
                }

                ForEach(host.jobs) { job in
                    Section(job.id) {
                        WorkHierarchyRow(
                            title: job.title,
                            subtitle: job.currentStage,
                            state: job.state,
                            symbol: "shippingbox"
                        )
                        .tag(FleetSelection.job(hostID: host.id, jobID: job.id))

                        ForEach(job.lanes) { lane in
                            WorkHierarchyRow(
                                title: lane.name,
                                subtitle: lane.currentStage,
                                state: lane.state,
                                symbol: "arrow.triangle.branch"
                            )
                            .padding(.leading, 12)
                            .tag(FleetSelection.lane(hostID: host.id, jobID: job.id, laneID: lane.id))
                        }
                    }
                }

                if host.jobs.isEmpty {
                    ContentUnavailableView(
                        "No active work",
                        systemImage: "checkmark.circle",
                        description: Text("This host has no fixture jobs.")
                    )
                }
            }
            .navigationTitle(host.displayName)
        } else {
            ContentUnavailableView("Select a host", systemImage: "desktopcomputer")
        }
    }
}

private struct WorkHierarchyRow: View {
    let title: String
    let subtitle: String
    let state: WorkState
    let symbol: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: state.symbolName)
                .foregroundStyle(state.tint)
                .accessibilityLabel(state.title)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FleetDetailView: View {
    let detail: FleetSelectionDetail?

    var body: some View {
        if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail.eyebrow)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(detail.title)
                            .font(.title2.weight(.semibold))
                        if let state = detail.state {
                            WorkStateLabel(state: state)
                        }
                    }

                    if detail.currentStage != nil || detail.elapsedSeconds != nil || detail.tokenUse != nil {
                        DetailMetricsGrid(detail: detail)
                    }

                    if let lastProgress = detail.lastMeaningfulProgressAt {
                        DetailLine(
                            title: "Last meaningful progress",
                            value: lastProgress.formatted(.relative(presentation: .named)),
                            systemImage: "waveform.path.ecg"
                        )
                    }

                    if let retries = detail.retryCount, let restarts = detail.restartCount {
                        DetailLine(
                            title: "Recovery history",
                            value: "\(retries) retries · \(restarts) restarts",
                            systemImage: "arrow.counterclockwise"
                        )
                    }

                    if !detail.recoverableFailures.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Recoverable failures", systemImage: "bandage")
                                .font(.subheadline.weight(.semibold))
                            ForEach(detail.recoverableFailures, id: \.self) { failure in
                                Text("• \(failure)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    Label {
                        Text("Source snapshot \(detail.sourceTimestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute().second()))")
                    } icon: {
                        Image(systemName: "terminal")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
            }
            .navigationTitle("Details")
        } else {
            ContentUnavailableView(
                "Select a host, job, or lane",
                systemImage: "sidebar.right",
                description: Text("Lifecycle and bound details appear here.")
            )
        }
    }
}

private struct DetailMetricsGrid: View {
    let detail: FleetSelectionDetail

    private let columns = [GridItem(.adaptive(minimum: 125), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            if let stage = detail.currentStage {
                MetricTile(title: "Stage", value: stage, symbol: "point.3.connected.trianglepath.dotted")
            }
            if let elapsed = detail.elapsedSeconds {
                MetricTile(title: "Elapsed", value: FleetFormat.duration(elapsed), symbol: "timer")
            }
            if let tokens = detail.tokenUse {
                MetricTile(title: "Tokens", value: FleetFormat.tokens(tokens), symbol: "number.circle")
            }
            if let timeBound = detail.timeBoundSeconds {
                MetricTile(title: "Time bound", value: FleetFormat.duration(timeBound), symbol: "hourglass")
            }
            if let bounds = detail.tokenBounds {
                if let soft = bounds.soft {
                    MetricTile(title: "Soft bound", value: FleetFormat.tokens(soft), symbol: "gauge.with.dots.needle.33percent")
                }
                if let hard = bounds.hard {
                    MetricTile(title: "Hard bound", value: FleetFormat.tokens(hard), symbol: "gauge.with.dots.needle.67percent")
                }
            }
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct DetailLine: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
