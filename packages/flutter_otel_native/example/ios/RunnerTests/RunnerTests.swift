import Flutter
import UIKit
import XCTest

// If your plugin has been explicitly set to "type: .dynamic" in the Package.swift,
// you will need to add your plugin as a dependency of RunnerTests within Xcode.

@testable import flutter_otel_native

// This demonstrates a simple unit test of the Swift portion of this plugin's implementation.
//
// See https://developer.apple.com/documentation/xctest for more information about using XCTest.

class RunnerTests: XCTestCase {
    func testDrainQueue() {
        let plugin = FlutterOtelNativePlugin()

        let call = FlutterMethodCall(methodName: "drainQueue", arguments: [])

        let resultExpectation = expectation(description: "result block must be called.")
        plugin.handle(call) { result in
            let payload = result as? [String: Any]
            XCTAssertNotNil(payload)
            XCTAssertNotNil(payload?["records"] as? [String])
            XCTAssertNotNil(payload?["droppedSinceLastDrain"] as? Int)
            resultExpectation.fulfill()
        }
        waitForExpectations(timeout: 1)
    }
}
