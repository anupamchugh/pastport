import PastportKit
import SwiftUI

/// "Challenge this answer": a button under a finished answer, then the findings the Skeptic made. Every finding
/// quotes words from the answer. Nothing here is copied, shared or sent anywhere.
struct SkepticCard: View {
    let state: SkepticState?
    let onChallenge: () -> Void

    var body: some View {
        switch state {
        case nil:
            Button(action: onChallenge) { Label("Challenge this answer", systemImage: "questionmark.bubble") }
                .font(.caption).buttonStyle(.bordered)
                .accessibilityHint("Checks the answer against the recorded facts on this device")
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking against the facts…").font(.footnote) }
                .foregroundStyle(Palette.muted)
        case .done(let review):
            VStack(alignment: .leading, spacing: 8) {
                Label(review.verdict == .holds ? "Holds up against the facts" : "Needs care",
                      systemImage: review.verdict == .holds ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink)
                ForEach(review.findings) { finding in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.issue.title).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                        Text("“\(finding.quote)”").font(.footnote).foregroundStyle(Palette.ink)
                        Text(finding.why).font(.caption).foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                Text(footnote(review)).font(.caption2).foregroundStyle(Palette.muted)
            }
            .padding(10)
            .background(Palette.card2, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func footnote(_ review: SkepticReview) -> String {
        switch review.model {
        case .reviewed: "Checked by code, then reviewed by Apple Intelligence on this device."
        case .notRun: "Checked by code only. Apple Intelligence did not review this answer."
        case .failed: "Checked by code. The Apple Intelligence review could not finish."
        }
    }
}

#if DEBUG
@MainActor private func skepticPreview(_ state: SkepticState?) -> some View {
    let turn = AskTurn(prompt: "How many pages did I open?", answer: "You opened 99 pages and you spent hours on guide.example.", status: .answered)
    return AskTurnView(turn: turn, skeptic: state, onChallenge: {}).padding()
}

#Preview("Skeptic, offered") { skepticPreview(nil) }
#Preview("Skeptic, findings, dark") {
    skepticPreview(.done(SkepticReview(findings: [
        SkepticFinding(issue: .unsupportedNumber, quote: "99", why: "The recorded facts do not contain this number."),
        SkepticFinding(issue: .timeOrIntentClaim, quote: "you spent", why: "A visit shows a page was opened, not that it was read or for how long."),
    ], model: .reviewed))).preferredColorScheme(.dark)
}
#endif
