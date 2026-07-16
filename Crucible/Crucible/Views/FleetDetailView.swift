import SwiftUI

struct FleetDetailView: View {
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

                    if detail.hasMetrics {
                        DetailMetricsGrid(detail: detail)
                    }

                    if let lastProgress = detail.lastMeaningfulProgressAt {
                        DetailLine(
                            title: "Last meaningful progress",
                            value: lastProgress.formatted(.relative(presentation: .named)),
                            systemImage: "waveform.path.ecg"
                        )
                    }

                    if let recoveryHistory = detail.recoveryHistoryLabel {
                        DetailLine(
                            title: "Recovery history",
                            value: recoveryHistory,
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

                    if !detail.conditions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CLI conditions")
                                .font(.headline)
                            ForEach(detail.conditions) { condition in
                                FleetConditionRow(condition: condition)
                            }
                        }
                    }

                    if !detail.lanes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Lanes")
                                .font(.headline)
                            ForEach(detail.lanes) { lane in
                                LaneDetailCard(lane: lane)
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
            if let softTimeBound = detail.timeBounds?.softSeconds {
                MetricTile(title: "Soft time bound", value: FleetFormat.duration(softTimeBound), symbol: "hourglass")
            }
            if let hardTimeBound = detail.timeBounds?.hardSeconds {
                MetricTile(title: "Hard time bound", value: FleetFormat.duration(hardTimeBound), symbol: "hourglass.bottomhalf.filled")
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
