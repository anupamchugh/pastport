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

/// Progress while something is being read or answered. Quiet otherwise.
public struct SessionStatus: View {
    let model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        if model.busy, !model.status.isEmpty {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(model.status).font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Which source answers: what was read from this device, or the separate connected tools.
public struct AnswerSourceMenu: View {
    @Bindable var model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        Menu {
            Picker("Answer from", selection: $model.assistantSource) {
                Text(model.canReadHistory ? "My history" : "My timeline").tag(TimelineModel.AssistantSource.evidence)
                Text("Connected tools").tag(TimelineModel.AssistantSource.connected)
            }
        } label: {
            Label("Answer from", systemImage: "slider.horizontal.3")
        }
        .help("Choose where answers come from")
    }
}
