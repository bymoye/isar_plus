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
        plugin.dummyMethodToEnforceBundling()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterMethodNotImplemented)
    }
    public func dummyMethodToEnforceBundling() {
        var dummy: UnsafePointer<UInt8>? = nil
        isar_plus_get_error(&dummy)
        _ = isar_plus_version()
    }
}
