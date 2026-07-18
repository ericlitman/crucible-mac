import SwiftUI

struct HostWorkView: View {
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

                if host.jobsTruncated, !host.jobs.isEmpty {
                    Section {
                        Label(
                            "Job detail truncated — this list is not the host's complete work.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                ForEach(host.jobs) { job in
                    Section(job.id) {
                        WorkHierarchyRow(
                            title: job.title,
                            subtitle: job.currentStage ?? "Select to inspect lanes",
                            state: job.state,
                            symbol: "shippingbox"
                        )
                        .tag(FleetSelection.job(jobID: job.id))

                        ForEach(job.lanes) { lane in
                            WorkHierarchyRow(
                                title: lane.name,
                                subtitle: lane.currentStage ?? "Stage unavailable",
                                state: lane.state,
                                symbol: "arrow.triangle.branch"
                            )
                            .padding(.leading, 12)
                            .tag(FleetSelection.lane(jobID: job.id, laneID: lane.id))
                        }
                    }
                }

                if host.jobs.isEmpty {
                    if host.jobsTruncated {
                        ContentUnavailableView(
                            "Job detail truncated",
                            systemImage: "exclamationmark.triangle",
                            description: Text("The CLI truncated this host's job list in the current snapshot; its work is not visible here.")
                        )
                    } else {
                        ContentUnavailableView(
                            "No jobs in this snapshot",
                            systemImage: "tray",
                            description: Text("The current snapshot supplies no jobs for this host.")
                        )
                    }
                }
            }
            .navigationTitle(host.displayName)
        } else {
            ContentUnavailableView("Select a host", systemImage: "desktopcomputer")
        }
    }
}

struct QueueWorkView: View {
    let state: AppState
    let snapshot: FleetSnapshot

    private var selection: Binding<FleetSelection?> {
        Binding(
            get: { state.selection },
            set: { newSelection in
                if let newSelection { state.select(newSelection) }
            }
        )
    }

    var body: some View {
        List(snapshot.queue, selection: selection) { item in
            WorkHierarchyRow(
                title: item.id,
                subtitle: item.title,
                state: item.state,
                symbol: "tray.full"
            )
            .tag(FleetSelection.job(jobID: item.id))
        }
        .navigationTitle("Queue")
    }
}

struct WorkHierarchyRow: View {
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
                if subtitle != title {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: state.symbolName)
                .foregroundStyle(state.tint)
                .accessibilityLabel(state.title)
        }
        .accessibilityElement(children: .combine)
    }
}
