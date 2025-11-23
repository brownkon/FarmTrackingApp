import UIKit
import Flutter
import background_locator_2   // 👈 ADD THIS

func registerPlugins(registry: FlutterPluginRegistry) {
    // Avoid double registration
    if !registry.hasPlugin("BackgroundLocatorPlugin") {
        GeneratedPluginRegistrant.register(with: registry)
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Normal Flutter plugin registration
        GeneratedPluginRegistrant.register(with: self)

        // 👇 THIS IS THE IMPORTANT LINE
        BackgroundLocatorPlugin.setPluginRegistrantCallback(registerPlugins)

        return super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
    }
}