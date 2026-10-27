import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  /// A bug report's screenshot of a full-screen map (noise compresses
  /// worst) stays under the 4 MB the API takes (feedback issue 40).
  func testScreenshotFitsTheAPI() {
    let (width, height) = (804, 1748)  // an iPhone 17 Pro at twice its points
    var rng = SystemRandomNumberGenerator()
    let pixels = Data((0..<width * height * 4).map { _ in UInt8.random(in: 0...255, using: &rng) })
    let cgImage = CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: CGDataProvider(data: pixels as CFData)!, decode: nil, shouldInterpolate: false,
      intent: .defaultIntent)!
    let data = screenshotData(UIImage(cgImage: cgImage, scale: 2, orientation: .up))
    XCTAssertNotNil(data)
    XCTAssertLessThan(data!.count, 4 << 20)
  }

}
