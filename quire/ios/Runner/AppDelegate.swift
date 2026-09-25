import Flutter
import PDFKit
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QuirePages") {
      PageRenderer.register(with: registrar)
    }
  }
}

/// Draws PDF pages with PDFKit, so a page is shown in its own fonts rather
/// than set again in the app's.
///
/// Every call runs on one serial queue, in order, and answers on the main
/// queue. A document under a password is refused: the app draws it itself,
/// with the key it already holds, rather than keeping what somebody typed.
class PageRenderer: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "ng.com.uriri.quire.pages")
  private var open: [Int: PDFDocument] = [:]
  private var next = 1
  private static let maxPixels = 4096 * 4096

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "ng.com.uriri.quire/pages",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(PageRenderer(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    queue.async {
      let reply: Any?
      switch call.method {
      case "open": reply = self.openDocument(arguments)
      case "render": reply = self.render(arguments)
      case "close":
        if let id = arguments["id"] as? Int { self.open[id] = nil }
        reply = NSNull()
      default:
        DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
        return
      }
      DispatchQueue.main.async {
        if let reply = reply {
          result(reply)
        } else {
          result(FlutterError(code: "unreadable", message: nil, details: nil))
        }
      }
    }
  }

  private func openDocument(_ arguments: [String: Any]) -> Any? {
    let document: PDFDocument?
    if let path = arguments["path"] as? String {
      document = PDFDocument(url: URL(fileURLWithPath: path))
    } else if let bytes = arguments["bytes"] as? FlutterStandardTypedData {
      document = PDFDocument(data: bytes.data)
    } else {
      document = nil
    }
    guard let document = document else { return nil }
    if document.isLocked && !document.unlock(withPassword: "") { return nil }
    let id = next
    next += 1
    open[id] = document
    return ["id": id, "pages": document.pageCount]
  }

  private func render(_ arguments: [String: Any]) -> Any? {
    guard
      let id = arguments["id"] as? Int,
      let document = open[id],
      let index = arguments["page"] as? Int,
      let width = arguments["width"] as? Int,
      let height = arguments["height"] as? Int,
      width > 0, height > 0, width * height <= PageRenderer.maxPixels,
      let page = document.page(at: index)
    else { return nil }
    let stride = width * 4
    var pixels = Data(count: stride * height)
    let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard
        let context = CGContext(
          data: raw.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: stride,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { return false }
      context.setFillColor(UIColor.white.cgColor)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      // The page as it is meant to be read: its crop box, turned by its own
      // rotation, then scaled to the bitmap, which already has its shape.
      let box = page.bounds(for: .cropBox)
      let turned = page.rotation % 180 != 0
      let upright = turned
        ? CGSize(width: box.height, height: box.width)
        : box.size
      guard upright.width > 0, upright.height > 0 else { return false }
      context.scaleBy(
        x: CGFloat(width) / upright.width,
        y: CGFloat(height) / upright.height
      )
      page.draw(with: .cropBox, to: context)
      return true
    }
    guard drawn else { return nil }
    return [
      "width": width,
      "height": height,
      "pixels": FlutterStandardTypedData(bytes: pixels),
    ]
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
