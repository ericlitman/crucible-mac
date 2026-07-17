import SwiftUI

extension WorkState {
    var tint: Color {
        switch self {
        case .active: .blue
        case .waiting: .secondary
        case .completed: .green
        case .failed: .red
        case .blocked: .orange
        case .stalled: .purple
        case .unknown: .secondary
        }
    }
}

extension HostCondition {
    var tint: Color {
        switch self {
        case .available: .green
        case .busy: .blue
        case .degraded: .orange
        case .offline: .secondary
        }
    }
}

extension FleetConditionSeverity {
    var tint: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .error, .critical: .red
        }
    }

    var symbolName: String {
        switch self {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

struct FleetConditionRow: View {
    let condition: FleetConditionSnapshot
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: condition.severity.symbolName)
                .foregroundStyle(condition.severity.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: compact ? 1 : 4) {
                Text(condition.title)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                if !condition.affectedLabel.isEmpty {
                    Text(condition.affectedLabel)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let actual = condition.actual, let bound = condition.bound {
                    Text("Observed \(condition.formattedMeasure(actual)) · bound \(condition.formattedMeasure(bound))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !compact, let action = condition.action {
                    Text(action)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(condition.severity.rawValue), \(condition.title), \(condition.affectedLabel)")
    }
}

struct PreviewDataBadge: View {
    var body: some View {
        Text("Preview Data")
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.13), in: Capsule())
            .accessibilityLabel("Preview Data")
    }
}

struct FreshnessView: View {
    let presentation: FleetPresentation
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: presentation.freshness.symbolName)
                .foregroundStyle(presentation.freshness.isCurrent ? .green : .orange)

            VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                Text(presentation.freshness.title)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))

                if let sourceDate = presentation.freshness.sourceDate {
                    Text("Source \(sourceDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !presentation.freshness.isCurrent, let lastSuccess = presentation.lastSuccessfulRefresh {
                    Text("Last complete refresh \(lastSuccess.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ErrorMessageView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StateCountCard: View {
    let state: WorkState
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: state.symbolName)
                .foregroundStyle(state.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(count, format: .number)
                    .font(.headline.monospacedDigit())
                Text(state.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.title), \(count)")
    }
}

struct WorkStateLabel: View {
    let state: WorkState

    var body: some View {
        Label(state.title, systemImage: state.symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(state.tint)
    }
}

struct HostRow: View {
    let host: HostSnapshot

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: host.condition.symbolName)
                .foregroundStyle(host.condition.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(host.condition.title) · \(host.capacityLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

enum FleetFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func tokens(_ value: Double) -> String {
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}
