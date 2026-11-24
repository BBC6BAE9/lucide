import CoreGraphics

/// A parsed icon: resolution-independent geometry in its SVG `viewBox` space.
public struct LucideGlyph: Sendable, Equatable {
  public enum LineCap: Sendable, Equatable { case butt, round, square }
  public enum LineJoin: Sendable, Equatable { case miter, round, bevel }

  public struct Element: Sendable, Equatable {
    public var segments: [PathSegment]
    public var isFilled: Bool
    public var isStroked: Bool
  }

  public var viewBox: CGRect
  public var strokeWidth: CGFloat
  public var lineCap: LineCap
  public var lineJoin: LineJoin
  public var elements: [Element]

  /// Stroked or filled geometry, mapped from `viewBox` into `rect` with aspect fit.
  public func path(_ part: Part, in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let transform = viewBoxTransform(in: rect)
    for element in elements where part == .stroke ? element.isStroked : element.isFilled {
      element.segments.append(to: path, transform: transform)
    }
    return path
  }

  /// Points per `viewBox` unit when drawn aspect-fit into `rect`.
  public func scale(in rect: CGRect) -> CGFloat {
    guard viewBox.width > 0, viewBox.height > 0 else { return 1 }
    return min(rect.width / viewBox.width, rect.height / viewBox.height)
  }

  /// Line width in points. `absolute` keeps `strokeWidth` points at any size, like Lucide's
  /// `absoluteStrokeWidth`; otherwise the stroke scales with the icon.
  public func lineWidth(_ strokeWidth: CGFloat? = nil, absolute: Bool = false, in rect: CGRect) -> CGFloat {
    let width = strokeWidth ?? self.strokeWidth
    return absolute ? width : width * scale(in: rect)
  }

  public enum Part: Sendable { case stroke, fill }

  private func viewBoxTransform(in rect: CGRect) -> CGAffineTransform {
    let scale = scale(in: rect)
    let x = rect.midX - viewBox.midX * scale
    let y = rect.midY - viewBox.midY * scale
    return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y)
  }
}

public enum PathSegment: Sendable, Equatable {
  case move(CGPoint)
  case line(CGPoint)
  case quad(CGPoint, control: CGPoint)
  case cubic(CGPoint, control1: CGPoint, control2: CGPoint)
  case close
}

extension [PathSegment] {
  func append(to path: CGMutablePath, transform: CGAffineTransform) {
    for segment in self {
      switch segment {
      case .move(let p): path.move(to: p, transform: transform)
      case .line(let p): path.addLine(to: p, transform: transform)
      case .quad(let p, let c): path.addQuadCurve(to: p, control: c, transform: transform)
      case .cubic(let p, let c1, let c2): path.addCurve(to: p, control1: c1, control2: c2, transform: transform)
      case .close: path.closeSubpath()
      }
    }
  }
}
