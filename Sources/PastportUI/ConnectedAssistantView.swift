import FoundationLabCore
import PastportKit
import SwiftUI

/// A small, explicit surface for connected tools. It never receives HistoryJourney data.
public struct ConnectedAssistantView: View {
    @Bindable private var model: ConnectedAssistant

    public init(model: ConnectedAssistant) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            toolPicker
            transcript
            composer
            metrics
        }
        .padding(16)
        .sheet(item: Binding(
            get: { model.pendingApproval },
            set: { _ in model.denyPending() }
        )) { request in
            ConnectedToolApprovalSheet(request: request, model: model)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Connected tools", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
            Text("No Safari history attached")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Each tool call shows its exact destination and arguments before it runs.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var toolPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tools")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.selectedTools.count)/\(ConnectedAssistantPolicy.maximumSelectedTools)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                ForEach(FoundationLabBuiltInTool.allCases) { tool in
                    let available = ConnectedAssistantPolicy.isAvailable(tool)
                    Button {
                        model.toggleTool(tool)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(tool.displayName, systemImage: tool.systemImage)
                            if let label = ConnectedAssistantPolicy.tier(for: tool).label {
                                Text(label).font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.selectedTools.contains(tool) ? .accentColor : .secondary)
                    .disabled(!available || (!model.selectedTools.contains(tool)
                        && model.selectedTools.count >= ConnectedAssistantPolicy.maximumSelectedTools))
                    .overlay(alignment: .trailing) {
                        if !available {
                            Text("Unavailable")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 8)
                        }
                    }

                }
            }
        }
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if model.messages.isEmpty {
                    Text("Choose up to three tools, then ask about weather, contacts, web search, or another selected service.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                }
                ForEach(model.messages) { message in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(message.role == .user ? "You" : "Assistant")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(message.text.isEmpty ? "…" : message.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(message.role == .user ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.10))
                            )
                    }
                }
                ForEach(model.toolReceipts) { receipt in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: receipt.status == .completed ? "checkmark.circle" : "xmark.circle")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(receipt.toolName) · \(receipt.status.rawValue)")
                                .font(.caption.weight(.semibold))
                            Text(receipt.arguments)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .foregroundStyle(receipt.status == .completed ? .green : .orange)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.topLeading, for: .alignment)
        .frame(minHeight: 150, maxHeight: 360)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask the connected assistant…", text: $model.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.send() }
            if model.isLoading {
                Button("Stop") { model.cancel() }
                    .buttonStyle(.bordered)
            } else {
                Button("Send") { model.send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.status)
            Text(model.contextSummary)
                .font(.caption.monospacedDigit())
            if let usage = model.lastTurnUsage {
                Text("Last turn: \(usage.totalTokenCount) tokens · \(usage.measurement.rawValue) response usage")
                    .font(.caption2.monospacedDigit())
            }
            if let receipt = model.toolReceipts.last, let elapsed = receipt.elapsedSeconds {
                Text(String(format: "Last tool: %.2fs · %@", elapsed, receipt.status.rawValue))
                    .font(.caption2.monospacedDigit())
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ConnectedToolApprovalSheet: View {
    let request: ConnectedToolApprovalRequest
    let model: ConnectedAssistant
    @ScaledMetric private var labelWidth: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Allow connected tool?", systemImage: "hand.raised")
                .font(.title3.weight(.semibold))
            Text("Pastport will share this exact request with the selected service. This session has no Safari history attached.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let label = ConnectedAssistantPolicy.tier(forDestination: request.destination)?.label {
                Label(label, systemImage: "arrow.up.forward.app")
                    .font(.callout.weight(.medium)).foregroundStyle(.orange)
            }
            detail("Tool", request.toolName)
            detail("Destination", request.destination)
            detail("Service", request.service)
            VStack(alignment: .leading, spacing: 4) {
                Text("Arguments")
                    .font(.caption.weight(.semibold))
                Text(request.arguments)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button("Cancel") { model.denyPending() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Allow Once") { model.allowPending() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .presentationDetents([.medium, .large])
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(.callout)
        }
    }
}
