import SwiftUI

struct LaneDetailCard: View {
    let lane: LaneSnapshot

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 9)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lane.name)
                        .font(.subheadline.weight(.semibold))
                    Text(lane.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                WorkStateLabel(state: lane.state)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
                if let stage = lane.currentStage {
                    LaneMetric(title: "Stage", value: stage)
                }
                if let elapsed = lane.elapsedSeconds {
                    LaneMetric(title: "Elapsed", value: FleetFormat.duration(elapsed))
                }
                if let tokens = lane.tokenUse {
                    LaneMetric(title: "Token use", value: FleetFormat.tokens(tokens))
                }
                if let soft = lane.timeBounds.softSeconds {
                    LaneMetric(title: "Soft time bound", value: FleetFormat.duration(soft))
                }
                if let hard = lane.timeBounds.hardSeconds {
                    LaneMetric(title: "Hard time bound", value: FleetFormat.duration(hard))
                }
                if let soft = lane.tokenBounds.soft {
                    LaneMetric(title: "Soft token bound", value: FleetFormat.tokens(soft))
                }
                if let hard = lane.tokenBounds.hard {
                    LaneMetric(title: "Hard token bound", value: FleetFormat.tokens(hard))
                }
            }

            if let progress = lane.lastMeaningfulProgressAt {
                Label(
                    "Last meaningful progress \(progress.formatted(.relative(presentation: .named)))",
                    systemImage: "waveform.path.ecg"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let retries = lane.retryCount, let restarts = lane.restartCount {
                Label("\(retries) retries · \(restarts) restarts", systemImage: "arrow.counterclockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(lane.recoverableFailures, id: \.self) { failure in
                Label(failure, systemImage: "bandage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct LaneMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }
}
