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
            Image(systemName: presentationSymbol)
                .foregroundStyle(presentationTint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: compact ? 1 : 4) {
                Text(condition.title)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                if !condition.affectedLabel.isEmpty {
                    Text(condition.affectedLabel)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let measures = measuresLine {
                    Text(measures)
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
        .accessibilityLabel(accessibilitySummary)
    }

    /// Glyph and tint follow the presentation class: over-time is a timer,
    /// over-tokens a gauge, no-recent-progress an hourglass — all amber,
    /// because the CLI cannot yet prove the work is dead. Red is reserved
    /// for genuine failure-grade conditions.
    private var presentationSymbol: String {
        switch condition.presentationClass {
        case .overTime: "timer"
        case .overTokens: "gauge.with.needle"
        case .noRecentProgress: "hourglass"
        case .failure: condition.severity.symbolName
        case .advisory: condition.severity.symbolName
        }
    }

    private var presentationTint: Color {
        switch condition.presentationClass {
        case .overTime, .overTokens, .noRecentProgress: .orange
        case .failure: .red
        case .advisory: condition.severity.tint
        }
    }

    private var measuresLine: String? {
        guard let actual = condition.actual, let bound = condition.bound else { return nil }
        var line: String
        switch condition.presentationClass {
        case .overTime, .overTokens:
            let over = actual - bound
            line = "\(condition.formattedMeasure(over)) over the \(condition.formattedMeasure(bound)) bound"
        case .noRecentProgress:
            line = "No reported progress for \(condition.formattedMeasure(actual)) — may still be working"
        case .failure, .advisory:
            line = "Observed \(condition.formattedMeasure(actual)) · bound \(condition.formattedMeasure(bound))"
        }
        line += " · seen \(condition.lastObservedAt.formatted(.relative(presentation: .named)))"
        return line
    }

    private var accessibilitySummary: String {
        var parts = [condition.severity.rawValue, condition.title, condition.affectedLabel]
        if let measures = measuresLine {
            parts.append(measures)
        }
        if !compact, let action = condition.action {
            parts.append(action)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
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
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let age = context.date.timeIntervalSince(sourceDate)
                        let relative = age < 60
                            ? "just now"
                            : sourceDate.formatted(.relative(presentation: .named))
                        Text("Source \(sourceDate.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · \(relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
