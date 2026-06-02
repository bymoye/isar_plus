#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
import Cocoa
#endif
import CIsarCore

public class IsarPlusFlutterLibsPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = IsarPlusFlutterLibsPlugin()
        plugin.enforceCoreBundling()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterMethodNotImplemented)
    }
    private func enforceCoreBundling() {
        isar_plus_force_link_all_symbols()
    }
}
