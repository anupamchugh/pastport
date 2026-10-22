import PastportKit
import SwiftUI

/// The iPhone and iPad window choices as chips. Changing the window locks the timeline.
public struct WindowChips: View {
    @Binding var days: Int

    public init(days: Binding<Int>) { _days = days }

    private func title(_ value: Int) -> String { value == 365 ? "1 year" : "\(value) days" }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) { chips }
            }
            Text("Changing the window locks the timeline.")
                .font(.caption).foregroundStyle(Palette.muted)
        }
    }

    private var chips: some View {
        ForEach(TimelineModel.iPhoneWindows, id: \.self) { value in
            let selected = value == days
            Button { days = value } label: {
                Text(title(value))
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(Palette.onAccent) : AnyShapeStyle(Palette.ink))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(selected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.card2), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

/// Before anything is read: the window, one Unlock, and what iOS lets Pastport read.
public struct LockedTimelineView: View {
    @Bindable var model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    private var failed: Bool { model.photoStatus == TimelineModel.unlockFailed }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "lock.fill").font(.title2).foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Text("Timeline is locked").font(.system(.largeTitle, design: .serif).bold())
                        .foregroundStyle(Palette.ink)
                    Text("Nothing has been read yet.").font(.title3).foregroundStyle(Palette.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Timeline locked. Nothing has been read yet.")

                WindowChips(days: $model.days)

                if failed {
                    NoticeBanner(TimelineModel.unlockFailed, symbol: "faceid")
                }

                Button { model.unlock() } label: {
                    HStack(spacing: 8) {
                        if model.busy { ProgressView().controlSize(.small) }
                        Label(failed ? "Try again" : "Unlock", systemImage: "faceid")
                    }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(Palette.accent.light)
                .disabled(model.busy)
                .accessibilityHint("Asks for Face ID or your passcode, then reads photo activity for this window")

                VStack(alignment: .leading, spacing: 12) {
                    Label(TimelineModel.photoCopy, systemImage: "photo.on.rectangle")
                    Label(TimelineModel.safariCopy, systemImage: "safari")
                }
                .font(.footnote).foregroundStyle(Palette.muted)
                .paperCard()

                NoticeBanner(TimelineModel.offlineCopy, symbol: "wifi.slash")
            }
            .padding(16)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }
}

#if DEBUG
#Preview("Locked") {
    LockedTimelineView(model: TimelineModel(history: nil, days: 30))
}

#Preview("Locked, dark") {
    LockedTimelineView(model: TimelineModel(history: nil, days: 30))
        .preferredColorScheme(.dark)
}
#endif
