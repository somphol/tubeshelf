import SwiftUI
import AppKit

#if DEBUG
/// Developer-only window snapshot. Screen recording permission is not needed
/// because the app renders its own view hierarchy into a bitmap.
///
///   TUBESHELF_SNAPSHOT=/tmp/shot.png TUBESHELF_SNAPSHOT_MODE=shelf open -a TubeShelf
enum Snapshotter {
    @MainActor private static var previewWindow: NSWindow?

    @MainActor
    static func runIfRequested(model: AppModel) {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["TUBESHELF_SNAPSHOT"] else { return }
        let mode = environment["TUBESHELF_SNAPSHOT_MODE"] ?? "shelf"

        Task { @MainActor in
            // Safety net: never leave a headless build running.
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { exit(0) }

            try? await Task.sleep(for: .seconds(2))
            NSApp.activate(ignoringOtherApps: true)
            switch SnapshotConfig.appearance {
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            default: break
            }
            if let main = NSApp.windows.first(where: { $0.isVisible }) {
                main.setContentSize(NSSize(
                    width: SnapshotConfig.width ?? 1240,
                    height: SnapshotConfig.height ?? 800
                ))
                main.center()
                main.makeKeyAndOrderFront(nil)
            }
            try? await Task.sleep(for: .milliseconds(700))

            switch mode {
            case "deck":
                if let first = model.visibleVideos.first { model.openDeck(startAt: first) }
            case "add":
                model.isAddPresented = true
            case "manager":
                model.isCategoryManagerPresented = true
            case "channels":
                model.isChannelBrowserPresented = true
            case "channel":
                if let top = model.library.channelCounts().first {
                    model.showChannel(top.name)
                }
            case "edit":
                model.editingVideoID = model.visibleVideos.first?.id
            case "page2":
                model.goToPage(1)
            case "page3":
                model.goToPage(2)
            case "settings":
                let hosting = NSHostingView(rootView: SettingsView(model: model))
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: false
                )
                window.title = "Settings"
                window.contentView = hosting
                window.center()
                window.makeKeyAndOrderFront(nil)
                previewWindow = window
            case "deck-mid":
                if model.visibleVideos.count > 60 {
                    let target = model.visibleVideos[60]
                    model.openDeck(startAt: model.visibleVideos.first ?? target)
                    model.deck?.jump(to: target.id)
                } else if let first = model.visibleVideos.first {
                    model.openDeck(startAt: first)
                }
            default:
                break
            }
            try? await Task.sleep(for: .seconds(2.5))

            let windowDump = NSApp.windows.map { "[\($0.title) \($0.frame.size) visible=\($0.isVisible) sheet=\($0.attachedSheet != nil)]" }
            print("mode=\(mode) add=\(model.isAddPresented) deck=\(model.deck != nil) windows=\(windowDump)")
            let host = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.attachedSheet == nil })
            let window = (mode == "settings" ? Snapshotter.previewWindow : nil)
                ?? host?.attachedSheet
                ?? host
            // Capture the frame view so the titlebar and toolbar appear too.
            guard let window, let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else {
                FileHandle.standardError.write(Data("snapshot: no window\n".utf8))
                NSApp.terminate(nil)
                return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
                print("snapshot \(rep.pixelsWide)x\(rep.pixelsHigh) window=\(window.frame.size) bounds=\(view.bounds.size) → \(path)")
            }
            NSApp.terminate(nil)
        }
    }
}
#endif

#if DEBUG
/// Test hook: pre-fill the category picker so the suggestion list can be
/// captured in a headless screenshot.
enum SnapshotConfig {
    static var pickerPrefill: String? {
        ProcessInfo.processInfo.environment["TUBESHELF_PICKER_PREFILL"]
    }

    static var width: CGFloat? {
        ProcessInfo.processInfo.environment["TUBESHELF_SNAPSHOT_WIDTH"].flatMap(Double.init).map { CGFloat($0) }
    }

    static var height: CGFloat? {
        ProcessInfo.processInfo.environment["TUBESHELF_SNAPSHOT_HEIGHT"].flatMap(Double.init).map { CGFloat($0) }
    }

    static var appearance: String? {
        ProcessInfo.processInfo.environment["TUBESHELF_SNAPSHOT_APPEARANCE"]
    }

    static var libraryDirectory: URL? {
        ProcessInfo.processInfo.environment["TUBESHELF_LIBRARY_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }
}
#endif
