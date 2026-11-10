import AppKit
import PhotosUI
import UniformTypeIdentifiers

/// Uses Apple's PHPickerViewController to let users select a video from their Photos library.
/// No authorization required — PHPicker runs out-of-process with full Photos access.
@MainActor
final class PhotosPickerController: NSObject {

    private var panel: NSPanel?
    private var continuation: CheckedContinuation<URL?, Never>?

    /// Show the Photos picker and wait for user selection. Returns nil if cancelled.
    func run() async -> URL? {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current

        let pickerVC = PHPickerViewController(configuration: config)
        pickerVC.delegate = self

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
        // NSPanel defaults hidesOnDeactivate = true, which would remove the picker
        // from screen the moment the app deactivates (e.g. the user Cmd-Tabs away).
        // Keep it visible until the user actually picks or cancels.
        window.hidesOnDeactivate = false
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

    /// Resolve the pending `run()` once. Closing the panel lands in
    /// `windowWillClose`, which calls back in with nothing left to resume.
    private func finish(with url: URL?) {
        guard let continuation else { return }
        self.continuation = nil
        panel?.close()
        continuation.resume(returning: url)
    }
}

// MARK: - NSWindowDelegate

extension PhotosPickerController: NSWindowDelegate {
    /// The user closed the panel without picking.
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            finish(with: nil)
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

        let cacheDir = AppPaths.photosPickerCache
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // The temporary file exists only inside this callback, so the copy happens here.
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { tempURL, _ in
            var cachedURL: URL?
            if let tempURL {
                let ext = tempURL.pathExtension
                let name = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
                let dest = cacheDir.appendingPathComponent(name)
                // Only hand back a URL if the copy actually landed a file — otherwise
                // the caller would try to render a path that doesn't exist.
                if (try? FileManager.default.copyItem(at: tempURL, to: dest)) != nil {
                    cachedURL = dest
                }
            }
            Task { @MainActor in self.finish(with: cachedURL) }
        }
    }
}
