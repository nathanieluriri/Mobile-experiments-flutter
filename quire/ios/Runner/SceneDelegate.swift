import Flutter
import UIKit

/// Hands documents opened from outside the app over to the Dart side.
///
/// This app declares a scene delegate in its Info.plist, so the method that
/// fires when another app opens a document is this one and not the app
/// delegate's. A file opened in place lives outside the sandbox and is reached
/// through a security scoped resource, so it is copied into the caches
/// directory while the access is held and it is that copy's path that goes
/// over.
class SceneDelegate: FlutterSceneDelegate {
    private var channel: FlutterMethodChannel?

    /// The document a cold start arrived with, waiting for Dart to ask.
    private var pending: String?

    private static let channelName = "ng.com.uriri.quire/incoming"
    private static let initialCall = "getInitialFile"
    private static let openedCall = "opened"

    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: options)
        if let first = options.urlContexts.first {
            pending = copyIn(first.url)
        }
        attach(scene)
    }

    override func scene(
        _ scene: UIScene,
        openURLContexts contexts: Set<UIOpenURLContext>
    ) {
        super.scene(scene, openURLContexts: contexts)
        guard let url = contexts.first?.url, let path = copyIn(url) else {
            return
        }
        guard let open = channel else {
            pending = path
            return
        }
        open.invokeMethod(SceneDelegate.openedCall, arguments: path)
    }

    /// Finds the engine this scene is showing and opens the channel on it.
    private func attach(_ scene: UIScene) {
        guard
            let window = (scene as? UIWindowScene)?.windows.first,
            let controller = window.rootViewController as? FlutterViewController
        else { return }
        let open = FlutterMethodChannel(
            name: SceneDelegate.channelName,
            binaryMessenger: controller.binaryMessenger
        )
        open.setMethodCallHandler { [weak self] call, result in
            guard call.method == SceneDelegate.initialCall else {
                result(FlutterMethodNotImplemented)
                return
            }
            result(self?.pending)
            self?.pending = nil
        }
        channel = open
    }

    /// The document at [url], copied somewhere this app can read it later.
    private func copyIn(_ url: URL) -> String? {
        // A document opened in place is outside the sandbox, and the right to
        // read it lasts only as long as this call.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard
            let caches = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first
        else { return nil }

        let into = caches.appendingPathComponent("incoming", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: into,
            withIntermediateDirectories: true
        )
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let file = into.appendingPathComponent("\(stamp)_\(url.lastPathComponent)")
        do {
            let bytes = try Data(contentsOf: url)
            try bytes.write(to: file, options: .atomic)
            return file.path
        } catch {
            return nil
        }
    }
}
