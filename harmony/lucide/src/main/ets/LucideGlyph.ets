import { LengthMetricsUnit } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';

export interface LucideViewBox {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export enum LucideGlyphPart {
  fill,
  stroke
}

/** Resolution-independent geometry in SVG viewBox coordinates. */
export class LucideGlyph {
  readonly viewBox: LucideViewBox;
  readonly strokeWidth: number;
  readonly lineCap: CanvasLineCap;
  readonly lineJoin: CanvasLineJoin;
  private readonly fill: Path2D;
  private readonly stroke: Path2D;

  constructor(viewBox: LucideViewBox, strokeWidth: number, lineCap: CanvasLineCap, lineJoin: CanvasLineJoin,
    fill: Path2D, stroke: Path2D) {
    this.viewBox = viewBox;
    this.strokeWidth = strokeWidth;
    this.lineCap = lineCap;
    this.lineJoin = lineJoin;
    this.fill = fill;
    this.stroke = stroke;
  }

  scale(rect: LucideViewBox): number {
    return Math.min(rect.width / this.viewBox.width, rect.height / this.viewBox.height);
  }

  lineWidth(strokeWidth: number | undefined, absolute: boolean, rect: LucideViewBox): number {
    const width = strokeWidth ?? this.strokeWidth;
    return absolute ? width : width * this.scale(rect);
  }

  path(part: LucideGlyphPart, rect: LucideViewBox): Path2D {
    const scale = this.scale(rect);
    const box = this.viewBox;
    const transform = new Matrix2D(LengthMetricsUnit.PX);
    transform.scaleX = scale;
    transform.scaleY = scale;
    transform.translateX = rect.x + (rect.width - box.width * scale) / 2 - box.x * scale;
    transform.translateY = rect.y + (rect.height - box.height * scale) / 2 - box.y * scale;
    const result = new Path2D(LengthMetricsUnit.PX);
    result.addPath(part === LucideGlyphPart.fill ? this.fill : this.stroke, transform);
    return result;
  }

  /** Rasterizes in black on a transparent PixelMap suitable for applying a color filter. */
  image(pointSize: number = 24, strokeWidth?: number, absoluteStrokeWidth: boolean = false,
    scale: number = 3): image.PixelMap | undefined {
    const side = pointSize * scale;
    const pixels = Math.ceil(side);
    if (!Number.isSafeInteger(pixels) || pixels <= 0 || scale <= 0) {
      return undefined;
    }
    try {
      const canvas = new OffscreenCanvasRenderingContext2D(
        pixels, pixels, new RenderingContextSettings(true), LengthMetricsUnit.PX);
      const width = absoluteStrokeWidth ? (strokeWidth ?? this.strokeWidth) * scale : strokeWidth;
      this.draw(canvas, side, side, '#000000', width, absoluteStrokeWidth);
      return canvas.getPixelMap(0, 0, pixels, pixels);
    } catch {
      return undefined;
    }
  }

  draw(canvas: CanvasRenderer, width: number, height: number, tint: string | number,
    strokeWidth: number | undefined, absoluteStrokeWidth: boolean): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    const rect: LucideViewBox = { x: 0, y: 0, width, height };
    canvas.fillStyle = tint;
    canvas.fill(this.path(LucideGlyphPart.fill, rect));
    const lineWidth = this.lineWidth(strokeWidth, absoluteStrokeWidth, rect);
    if (Number.isFinite(lineWidth) && lineWidth > 0) {
      canvas.strokeStyle = tint;
      canvas.lineWidth = lineWidth;
      canvas.lineCap = this.lineCap;
      canvas.lineJoin = this.lineJoin;
      canvas.stroke(this.path(LucideGlyphPart.stroke, rect));
    }
  }
}
