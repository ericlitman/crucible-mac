import SwiftUI

struct FleetDashboardView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            DashboardStatusBar(state: state)
            Divider()

            if let unresolvedTarget = state.unresolvedNotificationTarget,
               state.snapshot == nil {
                UnresolvedNotificationTargetView(target: unresolvedTarget)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = state.snapshot {
                NavigationSplitView {
                    HostSidebarView(state: state, snapshot: snapshot)
                } content: {
                    if state.selectedHost != nil {
                        HostWorkView(state: state)
                    } else if let job = state.selectedHostlessJob {
                        JobWorkView(state: state, job: job)
                    } else {
                        QueueWorkView(state: state, snapshot: snapshot)
                    }
                } detail: {
                    if let unresolvedTarget = state.unresolvedNotificationTarget {
                        UnresolvedNotificationTargetView(target: unresolvedTarget)
                    } else if let unresolved = state.unresolvedSelection {
                        UnresolvedSelectionView(
                            unresolved: unresolved,
                            sourceTimestamp: snapshot.sourceTimestamp
                        )
                    } else {
                        FleetDetailView(detail: state.selectionDetail)
                    }
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
        .onDisappear {
            state.dashboardDidDisappear()
        }
    }
}

private struct UnresolvedSelectionView: View {
    let unresolved: UnresolvedSelection
    let sourceTimestamp: Date

    var body: some View {
        ContentUnavailableView {
            Label("Selected \(unresolved.kindLabel) unavailable", systemImage: "questionmark.circle")
        } description: {
            VStack(spacing: 8) {
                Text(unresolved.identityLabel)
                    .font(.body.monospaced())
                Text(unresolved.explanation)
                Text("Source snapshot \(sourceTimestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute().second()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct UnresolvedNotificationTargetView: View {
    let target: UnresolvedNotificationTarget

    var body: some View {
        ContentUnavailableView {
            Label("Alert target unavailable", systemImage: "bell.badge.slash")
        } description: {
            VStack(spacing: 8) {
                Text(reasonText)
                Text("\(target.route.hostID) · \(target.route.jobID) · \(target.route.laneID)")
                    .font(.caption.monospaced())
                Text("\(target.route.conditionType) · Source \(target.route.sourceTimestamp.formatted(.iso8601))")
                    .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var reasonText: String {
        switch target.reason {
        case .partialSnapshot:
            "The current CLI snapshot is partial, so Crucible cannot safely resolve this alert yet."
        case .targetUnavailable:
            "The current CLI snapshot does not contain this exact lane. The requested target is preserved for a later refresh."
        }
    }
}

private struct DashboardStatusBar: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                FreshnessView(presentation: state.presentation, compact: true)
                if state.presentation.isPreviewData {
                    PreviewDataBadge()
                }
                if state.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing fleet")
                }
                if let count = state.snapshot?.conditions.count, count > 0 {
                    Label("\(count) conditions", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    Task { await state.refreshNow() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(state.isRefreshing)
            }

            if let errorMessage = state.presentation.errorMessage {
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

    private enum SidebarDestination: Hashable {
        case queue
        case host(String)
    }

    private var selection: Binding<SidebarDestination?> {
        Binding(
            get: {
                // The highlight mirrors the content column's actual scope. An
                // unresolved alert target renders its own view (no highlight);
                // a host-less job shows its job context (no highlight); every
                // other non-host state keeps the queue content visible, so the
                // Queue row stays highlighted — including a selection whose
                // record is missing from a truncated snapshot.
                if state.unresolvedNotificationTarget != nil { return nil }
                if let host = state.selectedHost { return .host(host.id) }
                if state.selectedHostlessJob != nil { return nil }
                // An unresolved entity selection highlights nothing: List never
                // fires the setter for an already-selected row, so keeping the
                // Queue row unhighlighted preserves it as the clickable escape
                // back to queue scope while the detail pane explains the
                // unresolved selection.
                if state.unresolvedSelection != nil { return nil }
                return .queue
            },
            set: { destination in
                switch destination {
                case .queue: state.selectQueue()
                case let .host(hostID): state.selectHost(hostID)
                case nil: break
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section {
                Label("Queue", systemImage: "tray.full")
                    .badge(snapshot.queue.count)
                    .tag(SidebarDestination.queue)
                    .accessibilityLabel("Queue, \(snapshot.queue.count) items")
            }
            Section("Hosts") {
                ForEach(snapshot.hosts) { host in
                    HostRow(host: host)
                        .tag(SidebarDestination.host(host.id))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Fleet")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
    }
}
