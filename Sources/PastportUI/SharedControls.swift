import PastportKit
import SwiftUI

/// The retained window. Changing it locks and clears, then the person reads again.
public struct WindowPicker: View {
    @Binding var days: Int

    public init(days: Binding<Int>) { _days = days }

    public var body: some View {
        Picker("Window", selection: $days) {
            Text("7 days").tag(7); Text("30 days").tag(30)
            Text("90 days").tag(90); Text("1 year").tag(365)
            Text("All retained").tag(0)
        }
    }
}

/// Coverage, session details and the current status line. Progress is a static spinner.
public struct SessionStatus: View {
    let model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !model.coverage.isEmpty {
                Text(model.coverage).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if !model.profile.isEmpty {
                DisclosureGroup("Session details") {
                    Text(model.profile).font(.caption2).foregroundStyle(.secondary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.caption2)
            }
            if !model.status.isEmpty {
                HStack(spacing: 6) {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Evidence answers versus the separate connected-tools conversation.
public struct AssistantSourcePicker: View {
    @Bindable var model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        Picker("Assistant", selection: $model.assistantSource) {
            Text(model.evidenceSourceTitle).tag(TimelineModel.AssistantSource.evidence)
            Text("Connected tools").tag(TimelineModel.AssistantSource.connected)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
