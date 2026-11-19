import Flutter
import UIKit
import CoreMotion

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let barometerChannel = "global.whami.app/barometer"
  private let connectivityChannel = "global.whami.app/maplibre_connectivity"
  private let altimeter = CMAltimeter()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Do not touch FlutterViewController / window here — under UIScene the
    // engine is not ready yet and force-unwrapping crashes the process.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupChannels(messenger: engineBridge.applicationRegistrar.messenger())
  }

  private func setupChannels(messenger: FlutterBinaryMessenger) {
    // Android-only MapLibre connectivity override — no-op success on iOS so
    // Dart's MissingPluginException path is never hit.
    let connectivity = FlutterMethodChannel(
      name: connectivityChannel,
      binaryMessenger: messenger
    )
    connectivity.setMethodCallHandler { call, result in
      if call.method == "forceConnected" {
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let methodChannel = FlutterMethodChannel(
      name: "\(barometerChannel)/method",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { call, result in
      if call.method == "isAvailable" {
        result(CMAltimeter.isRelativeAltitudeAvailable())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: "\(barometerChannel)/stream",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(BarometerStreamHandler(altimeter: altimeter))
  }
}

class BarometerStreamHandler: NSObject, FlutterStreamHandler {
  private let altimeter: CMAltimeter
  private var eventSink: FlutterEventSink?

  init(altimeter: CMAltimeter) {
    self.altimeter = altimeter
    super.init()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    if !CMAltimeter.isRelativeAltitudeAvailable() {
      return FlutterError(
        code: "UNAVAILABLE",
        message: "Barometer relative altitude is not available",
        details: nil
      )
    }

    altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { [weak self] data, error in
      guard let self = self else { return }
      if let error = error {
        self.eventSink?(
          FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)
        )
        return
      }
      if let data = data {
        let pressureKpa = data.pressure.doubleValue
        let pressureHpa = pressureKpa * 10.0
        self.eventSink?(pressureHpa)
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    altimeter.stopRelativeAltitudeUpdates()
    eventSink = nil
    return nil
  }
}
