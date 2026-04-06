import AppKit
import PhotosUI
import UniformTypeIdentifiers

/// Uses Apple's PHPickerViewController to let users select a video from their Photos library.
/// No authorization required — PHPicker runs out-of-process with full Photos access.
@MainActor
final class PhotosPickerController: NSObject {

    private var panel: NSPanel?
    private var continuation: CheckedContinuation<URL?, Never>?
    private var picker: PHPickerViewController?

    /// Tracks whether a picker is currently showing to prevent duplicates.
    static var isShowing = false

    /// Show the Photos picker and wait for user selection. Returns nil if cancelled.
    func run() async -> URL? {
        guard !Self.isShowing else { return nil }
        Self.isShowing = true
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current

        let pickerVC = PHPickerViewController(configuration: config)
        pickerVC.delegate = self
        self.picker = pickerVC

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Choose a Video from Photos"
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.contentViewController = pickerVC
        self.panel = window

        return await withCheckedContinuation { cont in
            self.continuation = cont
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func finish(with url: URL?) {
        let cont = continuation
        continuation = nil

        Self.isShowing = false
        panel?.close()

        cont?.resume(returning: url)
    }
}

// MARK: - NSWindowDelegate

extension PhotosPickerController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            Self.isShowing = false
            NSApp.setActivationPolicy(.accessory)
            let cont = continuation
            continuation = nil
            cont?.resume(returning: nil)
        }
    }
}

// MARK: - PHPickerViewControllerDelegate

extension PhotosPickerController: PHPickerViewControllerDelegate {
    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let result = results.first,
              result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
            Task { @MainActor in self.finish(with: nil) }
            return
        }

        let cacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MovingPaper/Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let provider = result.itemProvider
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { tempURL, _ in
            var cachedURL: URL?
            if let tempURL {
                let ext = tempURL.pathExtension
                let name = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
                let dest = cacheDir.appendingPathComponent(name)
                try? FileManager.default.copyItem(at: tempURL, to: dest)
                cachedURL = dest
            }
            Task { @MainActor in self.finish(with: cachedURL) }
        }
    }
}
