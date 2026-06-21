import Flutter
import UIKit
import CoreMotion

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let barometerChannel = "com.example.whami/barometer"
  private let altimeter = CMAltimeter()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // Method Channel to check if the barometer is available
    let methodChannel = FlutterMethodChannel(name: "\(barometerChannel)/method",
                                              binaryMessenger: controller.binaryMessenger)
    methodChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "isAvailable" {
        result(CMAltimeter.isRelativeAltitudeAvailable())
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    // Event Channel to stream pressure readings
    let eventChannel = FlutterEventChannel(name: "\(barometerChannel)/stream",
                                            binaryMessenger: controller.binaryMessenger)
    eventChannel.setStreamHandler(BarometerStreamHandler(altimeter: altimeter))

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
      return FlutterError(code: "UNAVAILABLE", message: "Barometer relative altitude is not available", details: nil)
    }
    
    // Start relative altitude/pressure updates
    altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { [weak self] (data, error) in
      guard let self = self else { return }
      if let error = error {
        self.eventSink?(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil))
        return
      }
      if let data = data {
        // data.pressure is in kilopascals (kPa). Convert to hectopascals (hPa) / millibars (mbar).
        let pressureKpa = data.pressure.doubleValue
        let pressureHpa = pressureKpa * 10.0
        self.eventSink?(pressureHpa)
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    altimeter.stopRelativeAltitudeUpdates()
    self.eventSink = nil
    return nil
  }
}
