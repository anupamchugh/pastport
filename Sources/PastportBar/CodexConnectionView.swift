import PastportKit
import PastportMac
import SwiftUI

/// The opt-in Codex connection. Off at every launch. While it is on, each kind of access a client asks for
/// waits here for Allow or Decline, and locking Pastport ends every approval.
struct CodexConnectionView: View {
    let model: TimelineModel
    @State private var choice = 0

    private var codex: McpConnection { model.codex }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Codex connection").font(.title2.bold())
                Text("Lets a coding agent on this Mac, such as Codex, ask Pastport about your history through a local connection. It sees small, cleaned results only after you allow each kind of access here. Nothing is sent over the network.")
                    .foregroundStyle(.secondary)

                Toggle("Allow Codex to connect", isOn: Binding(
                    get: { codex.enabled }, set: { codex.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!codex.enabled && !model.historyLoaded)
                if !model.historyLoaded && !codex.enabled {
                    Text("Unlock your history first. Nothing is shared while Pastport is locked.").font(.callout)
                }
                if let problem = codex.problem { Text(problem).font(.callout).foregroundStyle(.red) }

                if codex.enabled {
                    Text("On until you turn it off, lock Pastport or quit. Add this to Codex: command pastport, argument mcp.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(codex.pending) { request in card(request) }
                    if codex.pending.isEmpty {
                        Text("No requests waiting.").font(.callout).foregroundStyle(.secondary)
                    }
                }

                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("What a client can ask").font(.headline)
                    ForEach(McpScope.allCases, id: \.self) { scope in
                        Label(scope.summary, systemImage: "checkmark.shield").font(.callout)
                    }
                    Text("It cannot read files, open pages, use the network, run commands, see screenshots or photos, or see topics Pastport hides until you ask. Each approval ends when it expires, when you lock Pastport, or when the client disconnects.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 720, alignment: .leading).padding(24)
        }
    }

    private func card(_ request: McpApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(request.client.label) wants to").font(.headline)
            Text(request.scope.summary)
            Text("The program name above comes from the client and from macOS; only continue if you started it.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                ForEach(Array(McpConnection.grantChoices.enumerated()), id: \.offset) { _, option in
                    Button(option.title) { codex.respond(to: request, .approve(lifetime: option.seconds)) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Decline") { codex.respond(to: request, .deny) }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}
