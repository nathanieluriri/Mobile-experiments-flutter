import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// Flutter's view controller, keeping the launch screen's light status bar
/// from the first frame. Flutter starts every controller on the default style,
/// which is dark in light mode, and Dart's own style lands a few frames later,
/// so the clock would blink out over the dark ground as the app took over.
class QuireViewController: FlutterViewController {
  override var preferredStatusBarStyle: UIStatusBarStyle {
    let asked = super.preferredStatusBarStyle
    return asked == .default ? .lightContent : asked
  }
}
