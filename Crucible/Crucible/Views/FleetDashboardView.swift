import SwiftUI

struct FleetDashboardView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            DashboardStatusBar(state: state)
            Divider()

            if let snapshot = state.snapshot {
                NavigationSplitView {
                    HostSidebarView(state: state, snapshot: snapshot)
                } content: {
                    if state.selectedHost != nil {
                        HostWorkView(state: state)
                    } else {
                        QueueWorkView(state: state, snapshot: snapshot)
                    }
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
        .onDisappear {
            state.dashboardDidDisappear()
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
