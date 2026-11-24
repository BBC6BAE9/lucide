import { LengthMetricsUnit } from '@kit.ArkUI';
import { drawing } from '@kit.ArkGraphics2D';
import { util, xml } from '@kit.ArkTS';
import { LucideGlyph, LucideViewBox } from './LucideGlyph';

export enum LucideSVGError {
  malformedDocument,
  notSVG,
  invalidViewBox,
  invalidPathData,
  tooManyElements
}

export class LucideSVGException extends Error {
  readonly code: LucideSVGError;
  readonly element?: number;

  constructor(code: LucideSVGError, element?: number) {
    super(LucideSVGError[code]);
    this.code = code;
    this.element = element;
  }
}

class SVGPaint {
  readonly fill: string;
  readonly stroke: string;

  constructor(fill: string = 'black', stroke: string = 'none') {
    this.fill = fill;
    this.stroke = stroke;
  }

  inheriting(attributes: Map<string, string>): SVGPaint {
    return new SVGPaint(attributes.get('fill')?.trim() ?? this.fill,
      attributes.get('stroke')?.trim() ?? this.stroke);
  }
}

class SVGTag {
  readonly name: string;
  readonly attributes = new Map<string, string>();

  constructor(name: string) {
    this.name = name;
  }
}

/** Parses Lucide's shape and paint subset. Other elements and their descendants are ignored. */
export class LucideSVG {
  static readonly maximumElementCount = 512;
  private static readonly svgNumber = /^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$/;

  static parse(data: Uint8Array): LucideGlyph {
    let document: string;
    try {
      document = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(data);
    } catch {
      throw new LucideSVGException(LucideSVGError.malformedDocument);
    }
    if (/<!DOCTYPE|<!ENTITY|\u0000/.test(document)) {
      throw new LucideSVGException(LucideSVGError.malformedDocument);
    }
    const reader = new SVGReader();
    try {
      const parser = new xml.XmlPullParser(new DataView(data.buffer, data.byteOffset, data.byteLength));
      const options: xml.ParseOptions = {
        supportDoctype: false,
        ignoreNameSpace: true,
        tokenValueCallbackFunction: (event: xml.EventType, info: xml.ParseInfo): boolean => reader.token(event, info),
        attributeValueCallbackFunction: (name: string, value: string): boolean => reader.attribute(name, value)
      };
      parser.parseXml(options);
    } catch {
      throw reader.failure ?? new LucideSVGException(LucideSVGError.malformedDocument);
    }
    return reader.glyph();
  }

  static number(value?: string): number | undefined {
    const text = value?.trim().replace(/px$/, '');
    if (text === undefined || !LucideSVG.svgNumber.test(text)) {
      return undefined;
    }
    const result = Number(text);
    return Number.isFinite(result) ? result : undefined;
  }

  static numbers(value: string, error: LucideSVGError): number[] {
    const result: number[] = [];
    for (const token of value.trim().split(/[,\s]+/)) {
      if (token.length > 0) {
        const number = Number(token);
        if (!LucideSVG.svgNumber.test(token) || !Number.isFinite(number)) {
          throw new LucideSVGException(error);
        }
        result.push(number);
      }
    }
    return result;
  }
}

class SVGReader {
  failure?: LucideSVGException;
  private pending?: SVGTag;
  private readonly stack: string[] = [];
  private readonly paints: SVGPaint[] = [];
  private readonly fill = new Path2D(LengthMetricsUnit.PX);
  private readonly stroke = new Path2D(LengthMetricsUnit.PX);
  private viewBox?: LucideViewBox;
  private strokeWidth = 1;
  private lineCap: CanvasLineCap = 'butt';
  private lineJoin: CanvasLineJoin = 'miter';
  private skippedDepth = 0;
  private elements = 0;
  private sawRoot = false;
  private completed = false;

  token(event: xml.EventType, info: xml.ParseInfo): boolean {
    try {
      // The pull parser emits a start token before invoking its attribute callbacks.
      if (this.pending !== undefined) {
        this.start(this.pending);
        this.pending = undefined;
      }
      switch (event) {
        case xml.EventType.START_TAG:
          this.pending = new SVGTag(info.getName());
          break;
        case xml.EventType.END_TAG:
          this.end(info.getName());
          break;
        case xml.EventType.END_DOCUMENT:
          this.completed = true;
          break;
      }
      return true;
    } catch (error) {
      this.failure = error instanceof LucideSVGException ? error :
        new LucideSVGException(LucideSVGError.malformedDocument);
      return false;
    }
  }

  attribute(name: string, value: string): boolean {
    this.pending?.attributes.set(name, value);
    return true;
  }

  glyph(): LucideGlyph {
    if (this.failure !== undefined) {
      throw this.failure;
    }
    if (!this.completed || !this.sawRoot || this.stack.length !== 0) {
      throw new LucideSVGException(LucideSVGError.malformedDocument);
    }
    if (this.viewBox === undefined) {
      throw new LucideSVGException(LucideSVGError.notSVG);
    }
    return new LucideGlyph(this.viewBox, this.strokeWidth, this.lineCap, this.lineJoin, this.fill, this.stroke);
  }

  private start(tag: SVGTag): void {
    const isRoot = this.stack.length === 0;
    if (isRoot && this.sawRoot) {
      throw new LucideSVGException(LucideSVGError.malformedDocument);
    }
    this.sawRoot = true;
    this.stack.push(tag.name);
    if (this.skippedDepth > 0 || (isRoot && tag.name !== 'svg')) {
      this.skippedDepth++;
      return;
    }
    const paint = (this.paints[this.paints.length - 1] ?? new SVGPaint()).inheriting(tag.attributes);
    if (isRoot) {
      this.readRoot(tag.attributes);
    } else if (tag.name !== 'g') {
      switch (tag.name) {
        case 'path':
        case 'circle':
        case 'ellipse':
        case 'rect':
        case 'line':
        case 'polyline':
        case 'polygon':
          this.addShape(tag, paint);
          break;
        default:
          this.skippedDepth = 1;
          return;
      }
    }
    this.paints.push(paint);
  }

  private end(name: string): void {
    if (this.stack.pop() !== name) {
      throw new LucideSVGException(LucideSVGError.malformedDocument);
    }
    if (this.skippedDepth > 0) {
      this.skippedDepth--;
    } else {
      this.paints.pop();
    }
  }

  private readRoot(attributes: Map<string, string>): void {
    const value = attributes.get('viewBox');
    const box = value !== undefined ? LucideSVG.numbers(value, LucideSVGError.invalidViewBox) :
      [0, 0, LucideSVG.number(attributes.get('width')) ?? 24, LucideSVG.number(attributes.get('height')) ?? 24];
    if (box.length !== 4 || box[2] <= 0 || box[3] <= 0 ||
      !Number.isFinite(box[0] + box[2]) || !Number.isFinite(box[1] + box[3])) {
      throw new LucideSVGException(LucideSVGError.invalidViewBox);
    }
    this.viewBox = { x: box[0], y: box[1], width: box[2], height: box[3] };
    this.strokeWidth = LucideSVG.number(attributes.get('stroke-width')) ?? 1;
    const cap = attributes.get('stroke-linecap');
    const join = attributes.get('stroke-linejoin');
    this.lineCap = cap === 'round' || cap === 'square' ? cap : 'butt';
    this.lineJoin = join === 'round' || join === 'bevel' ? join : 'miter';
  }

  private addShape(tag: SVGTag, paint: SVGPaint): void {
    if (this.elements >= LucideSVG.maximumElementCount) {
      throw new LucideSVGException(LucideSVGError.tooManyElements);
    }
    let path: Path2D | undefined;
    try {
      path = this.shape(tag);
    } catch {
      throw new LucideSVGException(LucideSVGError.invalidPathData, this.elements);
    }
    if (path === undefined) {
      return;
    }
    if (paint.fill !== 'none') {
      this.fill.addPath(path);
    }
    if (paint.stroke !== 'none') {
      this.stroke.addPath(path);
    }
    this.elements++;
  }

  private shape(tag: SVGTag): Path2D | undefined {
    const a = tag.attributes;
    const value = (key: string): number => LucideSVG.number(a.get(key)) ?? 0;
    const path = new Path2D(LengthMetricsUnit.PX);
    switch (tag.name) {
      case 'path': {
        const data = a.get('d')?.trim() ?? '';
        if (data.length === 0) {
          return undefined;
        }
        if (!/^[Mm]/.test(data) || !new drawing.Path().buildFromSvgString(data)) {
          throw new LucideSVGException(LucideSVGError.invalidPathData);
        }
        return new Path2D(data, LengthMetricsUnit.PX);
      }
      case 'circle':
      case 'ellipse': {
        const rx = tag.name === 'circle' ? value('r') : value('rx');
        const ry = tag.name === 'circle' ? rx : value('ry');
        if (rx <= 0 || ry <= 0) {
          return undefined;
        }
        const cx = value('cx');
        const cy = value('cy');
        path.moveTo(cx + rx, cy);
        path.ellipse(cx, cy, rx, ry, 0, 0, 2 * Math.PI);
        path.closePath();
        break;
      }
      case 'rect':
        return this.rect(a, value('x'), value('y'), value('width'), value('height'));
      case 'line':
        path.moveTo(value('x1'), value('y1'));
        path.lineTo(value('x2'), value('y2'));
        break;
      case 'polyline':
      case 'polygon': {
        const points = LucideSVG.numbers(a.get('points') ?? '', LucideSVGError.invalidPathData);
        if (points.length < 4) {
          return undefined;
        }
        path.moveTo(points[0], points[1]);
        for (let index = 2; index + 1 < points.length; index += 2) {
          path.lineTo(points[index], points[index + 1]);
        }
        if (tag.name === 'polygon') {
          path.closePath();
        }
        break;
      }
    }
    return path;
  }

  private rect(attributes: Map<string, string>, x: number, y: number, width: number, height: number):
    Path2D | undefined {
    if (width <= 0 || height <= 0) {
      return undefined;
    }
    const rx = LucideSVG.number(attributes.get('rx'));
    const ry = LucideSVG.number(attributes.get('ry'));
    const h = Math.min(Math.max(rx ?? ry ?? 0, 0), width / 2);
    const v = Math.min(Math.max(ry ?? rx ?? 0, 0), height / 2);
    if (h === 0 || v === 0) {
      const path = new Path2D(LengthMetricsUnit.PX);
      path.rect(x, y, width, height);
      return path;
    }
    const r = x + width;
    const b = y + height;
    return new Path2D(
      `M ${x + h} ${y} H ${r - h} A ${h} ${v} 0 0 1 ${r} ${y + v} V ${b - v} A ${h} ${v} 0 0 1 ${r - h} ${b} ` +
      `H ${x + h} A ${h} ${v} 0 0 1 ${x} ${b - v} V ${y + v} A ${h} ${v} 0 0 1 ${x + h} ${y} Z`,
      LengthMetricsUnit.PX);
  }
}
