import Foundation

/// Curated demo content. Real videos with titles verified against YouTube, used
/// only when someone clicks "Try it with examples" (or runs `--seed-demo`).
public enum SampleShelf {
    public static var all: [Video] {
        [
            Video(
                youtubeID: "VEtU4Co08yY",
                title: "YOUR FIRST SOURDOUGH (Sourdough Bread For Complete Beginners)",
                channel: "Brian Lagerstrom",
                tags: ["Cooking"],
                addedAt: Date(timeIntervalSince1970: 1_759_000_000),
                durationSeconds: 848
            ),
            Video(
                youtubeID: "HyQgpxX__-A",
                title: "WWDC24: SwiftUI essentials | Apple",
                channel: "Apple Developer",
                tags: ["Programming", "Design"],
                addedAt: Date(timeIntervalSince1970: 1_759_040_000),
                durationSeconds: 1456
            ),
            Video(
                youtubeID: "kw-Rs6I2H5s",
                title: "Science of the James Webb Telescope Explained!",
                channel: "PBS Space Time",
                tags: ["Science"],
                addedAt: Date(timeIntervalSince1970: 1_759_080_000),
                durationSeconds: 1084
            ),
            Video(
                youtubeID: "mrKKW3riVIA",
                title: "Index Funds for Beginners: A Step-by-Step Guide to Passive Investing",
                channel: "Austin Williams",
                tags: ["Finance"],
                addedAt: Date(timeIntervalSince1970: 1_759_120_000),
                durationSeconds: 865
            ),
            Video(
                youtubeID: "jK_nYq4ZpgY",
                title: "How to Color Grade in DaVinci Resolve for Beginners!",
                channel: "Think Media",
                tags: ["Film & Video", "Education"],
                addedAt: Date(timeIntervalSince1970: 1_759_160_000),
                durationSeconds: 952
            ),
            Video(
                youtubeID: "gk2s7BekuIA",
                title: "Ultimate TOKYO Travel Guide!",
                channel: "Tokyo Creative",
                tags: ["Travel"],
                addedAt: Date(timeIntervalSince1970: 1_759_200_000),
                durationSeconds: 1311
            ),
            Video(
                youtubeID: "EIkeRBP5nDg",
                title: "Ten Minute History - The Fall of Rome (Short Documentary)",
                channel: "History Matters",
                tags: ["History", "Education"],
                addedAt: Date(timeIntervalSince1970: 1_759_240_000),
                durationSeconds: 600
            )
        ]
    }
}
