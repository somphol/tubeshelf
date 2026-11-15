import SwiftUI
import AppKit
import TubeShelfCore

struct DeckView: View {
    let model: AppModel

    @State private var scrollMonitor: Any?
    @State private var lastScroll = Date.distantPast

    private var deck: DeckModel? { model.deck }
    private var current: DeckSlide? { deck?.current }

    var body: some View {
        ZStack {
            BlurredBackdrop(videoID: current?.thumbnailVideoID ?? "")
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
                                .overlay { slideArrows }
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
        .background {
            // Home / End move to the ends of the deck without adding chrome.
            HStack(spacing: 0) {
                Button("") { model.deck?.jumpToFirst() }
                    .keyboardShortcut(.home, modifiers: [])
                Button("") { model.deck?.jumpToLast() }
                    .keyboardShortcut(.end, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .onAppear(perform: installScrollMonitor)
        .onDisappear(perform: removeScrollMonitor)
    }

    // MARK: - Scroll to move

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.window == NSApp.keyWindow else { return event }
            // Leave the filmstrip and controls alone.
            guard event.locationInWindow.y > 120 else { return event }

            // A trackpad reports large precise deltas; a classic mouse wheel reports
            // about one line per notch, which used to fall under the threshold.
            let vertical = event.scrollingDeltaY != 0
                ? event.scrollingDeltaY
                : CGFloat(event.deltaY)
            let horizontal = event.scrollingDeltaX != 0
                ? event.scrollingDeltaX
                : CGFloat(event.deltaX)
            let delta = abs(vertical) >= abs(horizontal) ? vertical : horizontal

            let precise = event.hasPreciseScrollingDeltas
            let threshold: CGFloat = precise ? 10 : 1
            let cooldown: TimeInterval = precise ? 0.35 : 0.12
            guard abs(delta) >= threshold else { return event }

            let now = Date()
            guard now.timeIntervalSince(lastScroll) > cooldown else { return event }
            lastScroll = now

            if delta < 0 {
                model.deck?.showNext()
            } else {
                model.deck?.showPrevious()
            }
            return event
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
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

            Text(model.deckTitle ?? model.filter.title)
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

    @ViewBuilder
    private func media(for slide: DeckSlide) -> some View {
        switch slide {
        case .video(let video): videoMedia(video)
        case .playlist(let playlist): coursePoster(playlist)
        }
    }

    private func videoMedia(_ video: Video) -> some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                ThumbnailView(videoID: video.youtubeID, cornerRadius: 16)
                    .overlay {
                        Button {
                            NSWorkspace.shared.open(video.watchURL)
                        } label: {
                            playBadge
                        }
                        .buttonStyle(.plain)
                        .help("Play on YouTube")
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
    }

    /// A course gets a poster, not a player: nine chapter stills in a grid, the
    /// course title, and its progress.
    private func coursePoster(_ playlist: PlaylistRecord) -> some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottomLeading) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3),
                        spacing: 3
                    ) {
                        ForEach(Array(playlist.items.prefix(9))) { item in
                            ThumbnailView(videoID: item.videoID, cornerRadius: 0)
                                .frame(maxWidth: .infinity)
                                .clipped()
                        }
                    }
                    .background(Color.white.opacity(0.04))

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.35), .black.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("COURSE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(Theme.accent)
                        Text(playlist.title)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        HStack(spacing: 8) {
                            Text("\(playlist.chapterCount) chapters")
                            Text("·")
                            Text("\(playlist.watchedCount) watched")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(20)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
    }

    private var playBadge: some View {
        ZStack {
            Circle().fill(.black.opacity(0.5)).frame(width: 62, height: 62)
            Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1).frame(width: 62, height: 62)
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 2)
        }
    }

    /// Mouse controls over the artwork: the same moves as the arrow keys.
    private var slideArrows: some View {
        HStack {
            arrowButton(forward: false)
            Spacer()
            arrowButton(forward: true)
        }
        .padding(.horizontal, 12)
    }

    private func arrowButton(forward: Bool) -> some View {
        let disabled = forward ? (deck?.isLast ?? true) : (deck?.isFirst ?? true)
        return Button {
            if forward {
                model.deck?.showNext()
            } else {
                model.deck?.showPrevious()
            }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.25 : 1)
        .help(forward ? "Next slide (→)" : "Previous slide (←)")
    }

    // MARK: - Info

    @ViewBuilder
    private func info(for slide: DeckSlide) -> some View {
        switch slide {
        case .video(let video): videoInfo(video)
        case .playlist(let playlist): courseInfo(playlist)
        }
    }

    private func videoInfo(_ video: Video) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            slideKicker

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
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .help("Show every saved video from this channel")
                if !video.durationLabel.isEmpty {
                    Text("·").foregroundStyle(.white.opacity(0.3))
                    Text(video.durationLabel)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize()
                }
            }

            Text("saved \(video.addedTimestamp())")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.42))

            tagRow(video.tags)

            if !video.note.isEmpty {
                Text(video.note)
                    .font(.system(size: 12.5))
                    .italic()
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                NSWorkspace.shared.open(video.watchURL)
            } label: {
                Label("Play on YouTube", systemImage: "play.fill")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.small)
            .padding(.top, 2)

            HStack(spacing: 10) {
                Button {
                    model.editingVideoID = video.id
                } label: {
                    Label("Edit", systemImage: "tag").font(.system(size: 10.5)).lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))

                Button {
                    model.toggleFavorite(video)
                } label: {
                    Label(video.isFavorite ? "Favorited" : "Favorite",
                          systemImage: video.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(video.isFavorite ? .yellow : .white.opacity(0.6))

                Button {
                    model.toggleWatched(video)
                } label: {
                    Label(video.watchStatus == .done ? "Watched" : "Mark watched",
                          systemImage: video.watchStatus == .done ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(video.watchStatus == .done ? .green : .white.opacity(0.6))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(video.watchURL.absoluteString, forType: .string)
                    model.flash("Link copied")
                } label: {
                    Label("Copy", systemImage: "link").font(.system(size: 10.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .help("Copy the YouTube link")
            }
            .padding(.top, 2)

            hint
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func courseInfo(_ playlist: PlaylistRecord) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            slideKicker

            Text(playlist.title)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            if !playlist.channel.isEmpty {
                Text(playlist.channel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("\(playlist.watchedCount) of \(playlist.chapterCount) watched")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                    if playlist.isTruncated {
                        Text("first batch").font(.system(size: 9.5)).foregroundStyle(.orange)
                    }
                }
                Capsule()
                    .fill(.white.opacity(0.12))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(Theme.accentGradient)
                                .frame(width: max(2, geo.size.width * playlist.progress))
                        }
                    }
                    .frame(height: 4)
            }

            tagRow(playlist.tags)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(playlist.items.prefix(6).enumerated()), id: \.element.videoID) { index, item in
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(width: 14, alignment: .trailing)
                        Image(systemName: playlist.isWatched(item.videoID)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 8))
                            .foregroundStyle(playlist.isWatched(item.videoID)
                                             ? Theme.accent : .white.opacity(0.3))
                        Text(item.title)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                if playlist.chapterCount > 6 {
                    Text("+ \(playlist.chapterCount - 6) more chapters")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.leading, 20)
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.openPlaylistCatalog(id: playlist.id)
                    model.closeDeck()
                } label: {
                    Label("Open course", systemImage: "list.bullet.rectangle")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)

                Button {
                    if let url = playlist.shareURL { NSWorkspace.shared.open(url) }
                } label: {
                    Label("YouTube", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.small)
            }
            .padding(.top, 2)

            hint
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var slideKicker: some View {
        Text("SLIDE \(deck?.position ?? 0) OF \(deck?.total ?? 0)")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Theme.accent)
    }

    private var hint: some View {
        Text("← → move · esc back to shelf")
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.3))
            .padding(.top, 4)
    }

    @ViewBuilder
    private func tagRow(_ tags: [String]) -> some View {
        if tags.isEmpty {
            Text("No category yet")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        } else {
            FlowWrap(items: tags) { tag in
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

    private var filmstripWindow: [DeckSlide] {
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
                    ThumbnailView(videoID: slide.thumbnailVideoID ?? "", cornerRadius: 6)
                        .frame(width: 92)
                        .opacity(slide.id == current?.id ? 1 : 0.45)
                        .overlay(alignment: .bottomTrailing) {
                            if slide.playlist != nil {
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.system(size: 7, weight: .bold))
                                    .padding(3)
                                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(.white)
                                    .padding(2)
                            }
                        }
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
                    if let url = currentURL { NSWorkspace.shared.open(url) }
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

    private var currentURL: URL? {
        switch current {
        case .video(let video): video.watchURL
        case .playlist(let playlist): playlist.shareURL
        case nil: URL(string: "https://youtube.com")
        }
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
