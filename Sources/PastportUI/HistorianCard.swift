import PastportKit
import SwiftUI

/// "The story of this window": up to five dated chapters of the imported history. Dates, counts and sites come from
/// code and sit under "Based on"; Apple Intelligence phrases a chapter only when it can, and each chapter says which
/// wrote it. Nothing here is copied, shared or saved.
struct HistorianCard: View {
    let model: TimelineModel

    var body: some View {
        if model.importedHistoryActive, model.historyLoaded {
            VStack(alignment: .leading, spacing: 10) {
                Label("The story of this window", systemImage: "book.closed")
                    .font(.headline).foregroundStyle(Palette.ink)
                if let story = model.historian {
                    ForEach(story.chapters) { chapter in
                        ChapterView(chapter: chapter)
                    }
                    if story.isRunning {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Writing…").font(.footnote) }
                            .foregroundStyle(Palette.muted)
                    } else if story.chapters.isEmpty {
                        Text("Nothing to tell: no pages in this window.").font(.footnote).foregroundStyle(Palette.muted)
                    }
                } else {
                    Text("Up to five short chapters built from the pages in this window. The facts come from code; Apple Intelligence phrases them on this device when it can.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                    Button { model.tellStory() } label: {
                        Label("Tell the story", systemImage: "text.book.closed").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).disabled(model.busy)
                }
            }
            .paperCard()
        }
    }

    private struct ChapterView: View {
        let chapter: HistorianChapter

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(chapter.narration).font(.callout).foregroundStyle(Palette.ink)
                DisclosureGroup("Based on") {
                    Text(chapter.facts.joined(separator: "\n")).font(.caption).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
                Text(chapter.origin == .model ? "Phrased by Apple Intelligence on this device and checked against the facts."
                                              : "Plain summary from the facts.")
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
            .accessibilityElement(children: .contain)
        }
    }
}
