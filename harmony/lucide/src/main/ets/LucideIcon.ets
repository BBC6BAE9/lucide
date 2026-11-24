import { ColorMetrics, LengthMetricsUnit } from '@kit.ArkUI';
import { LucideGlyph } from './LucideGlyph';
import { LucideName } from './LucideName';
import { LucidePipeline } from './LucidePipeline';

export interface LucideIconOptions {
  name: LucideName;
  size?: number;
  strokeWidth?: number;
  absoluteStrokeWidth?: boolean;
  tint?: ResourceColor;
  pipeline?: LucidePipeline;
}

/** Draws a vector icon and reserves the same layout space while it loads. */
@Builder
export function LucideIcon($$: LucideIconOptions) {
  LucideIconView({
    name: $$.name,
    iconSize: $$.size ?? 24,
    strokeWidth: $$.strokeWidth,
    absoluteStrokeWidth: $$.absoluteStrokeWidth ?? false,
    tint: $$.tint ?? $r('sys.color.font_primary'),
    pipeline: $$.pipeline
  })
}

@ComponentV2
struct LucideIconView {
  @Param @Require name: LucideName;
  @Param iconSize: number = 24;
  @Param strokeWidth: number | undefined = undefined;
  @Param absoluteStrokeWidth: boolean = false;
  @Param tint: ResourceColor = $r('sys.color.font_primary');
  @Param pipeline: LucidePipeline | undefined = undefined;

  private readonly canvas = new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  private ready = false;
  private glyph?: LucideGlyph;
  private generation = 0;

  aboutToAppear(): void {
    this.loadGlyph();
  }

  aboutToDisappear(): void {
    this.generation++;
    this.ready = false;
  }

  @Monitor('name', 'pipeline')
  private loadGlyph(): void {
    const generation = ++this.generation;
    const pipeline = this.pipeline ?? LucidePipeline.shared(this.getUIContext().getHostContext());
    this.glyph = pipeline.localGlyph(this.name);
    this.redraw();
    if (this.glyph === undefined) {
      pipeline.glyph(this.name).then((glyph: LucideGlyph) => {
        if (generation === this.generation) {
          this.glyph = glyph;
          this.redraw();
        }
      }).catch(() => {
        // The component keeps its layout on a failed load.
      });
    }
  }

  @Monitor('iconSize', 'strokeWidth', 'absoluteStrokeWidth', 'tint')
  private redraw(): void {
    if (!this.ready) {
      return;
    }
    const width = this.canvas.width;
    const height = this.canvas.height;
    this.canvas.clearRect(0, 0, width, height);
    const glyph = this.glyph;
    if (glyph === undefined) {
      return;
    }
    let tint = '#000000';
    try {
      tint = ColorMetrics.resourceColor(this.tint).color;
    } catch {
      // A color resource that cannot be resolved falls back to black.
    }
    const strokeWidth = this.absoluteStrokeWidth ?
      this.getUIContext().vp2px(this.strokeWidth ?? glyph.strokeWidth) : this.strokeWidth;
    glyph.draw(this.canvas, width, height, tint, strokeWidth, this.absoluteStrokeWidth);
  }

  build() {
    Canvas(this.canvas)
      .width(this.iconSize)
      .height(this.iconSize)
      .onReady(() => {
        this.ready = true;
        this.redraw();
      })
      .onSizeChange(() => this.redraw())
  }
}
