import AppKit
import ConversionKit
import SwiftUI

/// The main window (SPEC §9): a drop zone on top, the Jobs list underneath.
struct ContentView: View {
    let model: JobsModel
    @AppStorage(OnboardingView.completedKey) private var onboardingCompleted = false

    var body: some View {
        VStack(spacing: 0) {
            DropZoneView(model: model)
                .padding(16)
                .frame(height: 210)

            Divider()

            JobsListView(model: model)
        }
        .frame(width: 520, height: 420)
        .sheet(isPresented: Binding(get: { !onboardingCompleted }, set: { _ in })) {
            OnboardingView { onboardingCompleted = true }
        }
    }
}

// MARK: - Drop zone

struct DropZoneView: View {
    let model: JobsModel
    @State private var isTargeted = false
    @State private var isImporting = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: model.dropped.isEmpty ? [6] : []))

            if model.dropped.isEmpty {
                emptyState
            } else {
                selection
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.dropped.add(urls.filter(\.isFileURL))
            return true
        } isTargeted: {
            isTargeted = $0
        }
        .fileImporter(
            isPresented: $isImporting, allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.dropped.add(urls)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Drop files to convert")
                .font(.title3.weight(.medium))
            Button("Choose Files…") { isImporting = true }
                .keyboardShortcut("o")
            Text("Everything stays on your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop zone")
    }

    private var selection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.dropped.summary)
                        .font(.headline)
                        .accessibilityIdentifier("source-summary")
                    if let note = model.dropped.skippedNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Add…") { isImporting = true }
                Button("Clear") { model.dropped = FileSelection(registry: model.registry) }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            if model.dropped.offeredTargets.isEmpty {
                Text("Morph can't convert these files yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Convert to")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TargetChips(model: model)
                Spacer(minLength: 0)
            }
        }
        .padding(16)
    }
}

/// One button per target format. A target that doesn't suit every dropped
/// file is shown disabled, with the reason in its tooltip (SPEC §9).
struct TargetChips: View {
    let model: JobsModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
            ForEach(model.dropped.offeredTargets) { target in
                let enabled = model.dropped.isAvailableForAll(target)
                Button {
                    model.convertDropped(to: target)
                } label: {
                    Text(target.displayName)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(!enabled)
                .help(enabled ? "Convert to \(target.displayName)" : reason(target))
                .accessibilityIdentifier("target-\(target.id)")
                .accessibilityHint(enabled ? "" : reason(target))
            }
        }
    }

    private func reason(_ target: FileFormat) -> String {
        let blockers = model.dropped.blockers(for: target)
        let names = blockers.prefix(3).map(\.url.lastPathComponent).joined(separator: ", ")
        let more = blockers.count > 3 ? " and \(blockers.count - 3) more" : ""
        return "Can't convert \(names)\(more) to \(target.displayName)."
    }
}

// MARK: - Jobs list

struct JobsListView: View {
    let model: JobsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Jobs")
                    .font(.headline)
                if !model.rows.isEmpty {
                    Text(model.progressSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if model.hasActiveJobs {
                    Button("Cancel All") { model.cancelAll() }
                }
                if model.hasFinishedJobs {
                    Button("Clear") { model.clearFinished() }
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if model.rows.isEmpty {
                Text("Converted files appear here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.rows.reversed()) { row in
                    JobRowView(row: row, model: model)
                }
                .listStyle(.plain)
            }
        }
    }
}

struct JobRowView: View {
    let row: JobsModel.JobRow
    let model: JobsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(row.sourceName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("to")
                Text(row.request.target.displayName)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                status
            }
            if case .failed(let error) = row.state {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("job-error")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var status: some View {
        switch row.state {
        case .queued:
            Text("Waiting")
                .foregroundStyle(.secondary)
            cancelButton
        case .running(let fraction):
            ProgressView(value: fraction)
                .frame(width: 80)
                .accessibilityLabel("Converting")
            cancelButton
        case .finished(let output):
            Button("Reveal") { model.reveal(output) }
                .accessibilityIdentifier("reveal")
                .help(output.lastPathComponent)
        case .failed(let error):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(error.recoverySuggestion ?? error.localizedDescription)
                .accessibilityLabel("Failed")
            Button("Retry") { model.retry(row) }
        case .cancelled:
            Text("Cancelled")
                .foregroundStyle(.secondary)
            Button("Retry") { model.retry(row) }
        }
    }

    private var cancelButton: some View {
        Button {
            model.cancel(row)
        } label: {
            Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Cancel")
    }
}

#Preview {
    ContentView(model: JobsModel())
}
