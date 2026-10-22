import FoundationLabCore
import PastportKit
import SwiftUI

/// The Privacy tab: what iOS lets Pastport read, the connected tools and where their data
/// goes, Health as a connected tool, and Lock and Clear.
public struct PrivacyScreen: View {
    let model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Privacy").font(.system(.title, design: .serif).bold()).foregroundStyle(Palette.ink)
                readable
                connected
                health
                lock
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }

    private func heading(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.headline).foregroundStyle(Palette.ink)
    }

    private var readable: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("What iPhone can read", "iphone")
            Text(TimelineModel.photoCopy)
            Text("Screenshots you add are read on this iPhone. Emails, one-time codes and card numbers are hidden before you see them.")
            Text(TimelineModel.safariCopy)
        }
        .font(.callout).foregroundStyle(Palette.muted)
        .paperCard()
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Connected tools", "point.3.connected.trianglepath.dotted")
            Text("Off until you choose them, up to three at a time. Every call waits for Allow once or Decline, and never receives your timeline.")
                .font(.callout).foregroundStyle(Palette.muted)
            ForEach(FoundationLabBuiltInTool.allCases) { tool in
                HStack(alignment: .firstTextBaseline) {
                    Label(tool.displayName, systemImage: tool.systemImage).font(.callout).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(ConnectedAssistantPolicy.tier(for: tool).label ?? "Stays on this iPhone")
                        .font(.caption).multilineTextAlignment(.trailing)
                        .foregroundStyle(ConnectedAssistantPolicy.tier(for: tool) == .onDevice
                                         ? AnyShapeStyle(Palette.muted) : AnyShapeStyle(Color.orange))
                }
                .accessibilityElement(children: .combine)
            }
            let receipts = model.connectedAssistant.toolReceipts
            Text(receipts.isEmpty ? "No connected tool has run yet." : "Receipts")
                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted).padding(.top, 4)
            ForEach(receipts) { receipt in
                Text("\(receipt.toolName) · \(receipt.status.rawValue) · \(receipt.arguments)")
                    .font(.caption.monospaced()).foregroundStyle(Palette.muted).lineLimit(2)
            }
        }
        .paperCard()
    }

    private var health: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Health", "heart")
            Text("Health is one of the connected tools, off by default. When you turn it on and allow a call, it reads steps, heart rate, workouts, sleep, active energy and distance, read-only. Health is not shown on the timeline.")
                .font(.callout).foregroundStyle(Palette.muted)
        }
        .paperCard()
    }

    private var lock: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Lock and Clear", "lock")
            Text("Clears everything read in this session: photo activity, screenshots, answers and receipts. Leaving the app does the same.")
                .font(.callout).foregroundStyle(Palette.muted)
            Button("Lock and clear", systemImage: "lock") { model.lockAndClear() }
                .buttonStyle(.bordered).frame(minHeight: 44)
        }
        .paperCard()
    }
}

#if DEBUG
#Preview("Privacy") {
    PrivacyScreen(model: TimelineModel(history: nil, days: 30))
}
#endif
