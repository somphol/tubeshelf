import SwiftUI
import AppKit
import TubeShelfCore

struct DeckView: View {
    let model: AppModel

    @State private var showPlayer = false

    private var deck: DeckModel? { model.deck }
    private var current: Video? { deck?.current }

    var body: some View {
        ZStack {
            BlurredBackdrop(videoID: current?.youtubeID ?? "")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                if let current {
                    GeometryReader { geo in
                        let infoWidth = min(340, max(290, geo.size.width * 0.23))
                        let availableWidth = geo.size.width - infoWidth - 28 - 56
                        let widthFromHeight = max(320, geo.size.height - 24) * 16.0 / 9.0
                        let mediaWidth = min(availableWidth, widthFromHeight, 1120)

                        HStack(alignment: .center, spacing: 28) {
                            media(for: current)
                                .frame(width: max(360, mediaWidth))
                            info(for: current)
                                .frame(width: infoWidth, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 8)
                    }
                } else {
                    Spacer()
                    Text("Nothing to present")
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
                filmstrip
                controls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.deckBackground)
        .clipped()
        .onChange(of: current?.id) { _, _ in
            showPlayer = false
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                model.closeDeck()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "house.fill").font(.system(size: 10, weight: .semibold))
                    Text("Shelf").font(.system(size: 11.5, weight: .semibold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(.white.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Back to the shelf (esc)")

            Text(model.filter.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(deck.map { "\($0.position) / \($0.total)" } ?? "")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))

            Button {
                model.closeDeck()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .padding(7)
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    // MARK: - Media

    private func media(for video: Video) -> some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if showPlayer {
                    InlinePlayer(videoID: video.youtubeID) {
                        model.flash("This video cannot play inline — open it on YouTube")
                        showPlayer = false
                    }
                } else {
                    ThumbnailView(videoID: video.youtubeID, cornerRadius: 16)
                        .overlay {
                            Button {
                                showPlayer = true
                            } label: {
                                ZStack {
                                    Circle().fill(.black.opacity(0.5))
                                        .frame(width: 62, height: 62)
                                    Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1)
                                        .frame(width: 62, height: 62)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(.white)
                                        .offset(x: 2)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Play here")
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
    }

    // MARK: - Info

    private func info(for video: Video) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("SLIDE \(deck?.position ?? 0) OF \(deck?.total ?? 0)")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.accent)

            Text(video.title)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    model.showChannel(video.channel)
                    model.closeDeck()
                } label: {
                    Text(video.channel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Show every saved video from this channel")
                if !video.durationLabel.isEmpty {
                    Text("·").foregroundStyle(.white.opacity(0.3))
                    Text(video.durationLabel)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text("·").foregroundStyle(.white.opacity(0.3))
                Text("saved \(video.addedTimestamp())")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if video.tags.isEmpty {
                Text("No category yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                FlowWrap(items: video.tags) { tag in
                    Button {
                        model.select(.tag(tag))
                        model.closeDeck()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: SymbolLibrary.category(tag))
                                .font(.system(size: 9, weight: .semibold))
                            Text(tag)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                }
            }

            if !video.note.isEmpty {
                Text(video.note)
                    .font(.system(size: 12.5))
                    .italic()
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    showPlayer.toggle()
                } label: {
                    Label(showPlayer ? "Hide player" : "Play here",
                          systemImage: showPlayer ? "rectangle.slash" : "play.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)

                Button {
                    NSWorkspace.shared.open(video.watchURL)
                } label: {
                    Label("Open on YouTube", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.small)
            }
            .padding(.top, 2)

            HStack(spacing: 12) {
                Button {
                    model.editingVideoID = video.id
                } label: {
                    Label("Edit", systemImage: "tag")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))

                Button {
                    model.toggleFavorite(video)
                } label: {
                    Label(video.isFavorite ? "Favorited" : "Favorite",
                          systemImage: video.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(video.isFavorite ? .yellow : .white.opacity(0.6))

                Button {
                    model.toggleWatched(video)
                } label: {
                    Label(video.watchStatus == .done ? "Watched" : "Mark watched",
                          systemImage: video.watchStatus == .done ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(video.watchStatus == .done ? .green : .white.opacity(0.6))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(video.watchURL.absoluteString, forType: .string)
                    model.flash("Link copied")
                } label: {
                    Label("Copy link", systemImage: "link")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.top, 2)

            Text("← → move · esc back to shelf")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        VStack(spacing: 8) {
            if let deck {
                ViewThatFits(in: .horizontal) {
                    filmStripItems(deck: deck)
                        .padding(.horizontal, 30)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            filmStripItems(deck: deck)
                                .padding(.horizontal, 30)
                        }
                        .onChange(of: current?.id) { _, newValue in
                            guard let newValue else { return }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 62)
    }

    /// Only the neighbourhood of the current slide is built. A category with a
    /// thousand videos must not create a thousand thumbnail views.
    private var filmstripWindow: [Video] {
        guard let deck else { return [] }
        let radius = 20
        let lower = max(0, deck.index - radius)
        let upper = min(deck.slides.count, deck.index + radius + 1)
        guard lower < upper else { return [] }
        return Array(deck.slides[lower..<upper])
    }

    private func filmStripItems(deck: DeckModel) -> some View {
        HStack(spacing: 7) {
            ForEach(filmstripWindow) { slide in
                Button {
                    model.deck?.jump(to: slide.id)
                } label: {
                    ThumbnailView(videoID: slide.youtubeID, cornerRadius: 6)
                        .frame(width: 92)
                        .opacity(slide.id == current?.id ? 1 : 0.45)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    slide.id == current?.id ? Theme.accent : .clear,
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(.plain)
                .id(slide.id)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule()
                        .fill(Theme.accentGradient)
                        .frame(width: max(4, geo.size.width * (deck?.progress ?? 0)))
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 34)

            HStack(spacing: 10) {
                Button {
                    model.deck?.showPrevious()
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(deck?.isFirst ?? true)
                .opacity((deck?.isFirst ?? true) ? 0.35 : 1)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Spacer()

                Button {
                    NSWorkspace.shared.open(current?.watchURL ?? URL(string: "https://youtube.com")!)
                } label: {
                    Text("Open on YouTube")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    model.deck?.showNext()
                } label: {
                    HStack(spacing: 6) {
                        Text("Next").font(.system(size: 11.5, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(deck?.isLast ?? true)
                .opacity((deck?.isLast ?? true) ? 0.35 : 1)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 16)
        }
        .padding(.top, 6)
    }
}

struct BlurredBackdrop: View {
    let videoID: String
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.deckBackground
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 64)
                        .opacity(0.32)
                }
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.45),
                        Color.black.opacity(0.80),
                        Color.black.opacity(0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .background(Theme.deckBackground)
        .task(id: videoID) {
            guard let data = await ThumbnailCache.shared.data(for: videoID) else { return }
            image = NSImage(data: data)
        }
    }
}
