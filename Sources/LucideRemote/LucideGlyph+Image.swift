import CoreGraphics

extension LucideGlyph {
  /// Rasterizes into a transparent bitmap, `scale` pixels per point. Strokes and fills are black;
  /// the platform wrappers below mark the result as a template so it takes the tint color.
  public func cgImage(pointSize: CGFloat = 24, strokeWidth: CGFloat? = nil, absoluteStrokeWidth: Bool = false,
                      scale: CGFloat = 3) -> CGImage? {
    let pixels = Int((pointSize * scale).rounded(.up))
    guard pixels > 0, scale > 0,
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // Glyph geometry is y-down like SVG; Core Graphics bitmaps are y-up.
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: scale, y: -scale)
    let rect = CGRect(x: 0, y: 0, width: pointSize, height: pointSize)
    let black = CGColor(colorSpace: space, components: [0, 0, 0, 1]) ?? CGColor(gray: 0, alpha: 1)

    context.setFillColor(black)
    context.addPath(path(.fill, in: rect))
    context.fillPath()
    context.setStrokeColor(black)
    context.setLineWidth(lineWidth(strokeWidth, absolute: absoluteStrokeWidth, in: rect))
    context.setLineCap(lineCap.cgLineCap)
    context.setLineJoin(lineJoin.cgLineJoin)
    context.addPath(path(.stroke, in: rect))
    context.strokePath()
    return context.makeImage()
  }
}

extension LucideGlyph.LineCap {
  var cgLineCap: CGLineCap {
    switch self { case .butt: .butt; case .round: .round; case .square: .square }
  }
}

extension LucideGlyph.LineJoin {
  var cgLineJoin: CGLineJoin {
    switch self { case .miter: .miter; case .round: .round; case .bevel: .bevel }
  }
}

#if canImport(UIKit)
import UIKit

extension LucideGlyph {
  /// A template image for UIKit surfaces that only take `UIImage`, such as `UIAction`.
  public func image(pointSize: CGFloat = 24, strokeWidth: CGFloat? = nil, absoluteStrokeWidth: Bool = false,
                    scale: CGFloat = 3) -> UIImage? {
    guard let cgImage = cgImage(pointSize: pointSize, strokeWidth: strokeWidth,
                                absoluteStrokeWidth: absoluteStrokeWidth, scale: scale) else { return nil }
    return UIImage(cgImage: cgImage, scale: scale, orientation: .up).withRenderingMode(.alwaysTemplate)
  }
}

extension LucidePipeline {
  public func image(_ name: LucideName, pointSize: CGFloat = 24, strokeWidth: CGFloat? = nil,
                    absoluteStrokeWidth: Bool = false, scale: CGFloat = 3) async throws -> UIImage? {
    try await glyph(name).image(pointSize: pointSize, strokeWidth: strokeWidth,
                                       absoluteStrokeWidth: absoluteStrokeWidth, scale: scale)
  }
}
#elseif canImport(AppKit)
import AppKit

extension LucideGlyph {
  /// A template image for AppKit surfaces that only take `NSImage`, such as `NSMenuItem`.
  public func image(pointSize: CGFloat = 24, strokeWidth: CGFloat? = nil, absoluteStrokeWidth: Bool = false,
                    scale: CGFloat = 2) -> NSImage? {
    guard let cgImage = cgImage(pointSize: pointSize, strokeWidth: strokeWidth,
                                absoluteStrokeWidth: absoluteStrokeWidth, scale: scale) else { return nil }
    let image = NSImage(cgImage: cgImage, size: NSSize(width: pointSize, height: pointSize))
    image.isTemplate = true
    return image
  }
}

extension LucidePipeline {
  public func image(_ name: LucideName, pointSize: CGFloat = 24, strokeWidth: CGFloat? = nil,
                    absoluteStrokeWidth: Bool = false, scale: CGFloat = 2) async throws -> NSImage? {
    try await glyph(name).image(pointSize: pointSize, strokeWidth: strokeWidth,
                                       absoluteStrokeWidth: absoluteStrokeWidth, scale: scale)
  }
}
#endif
