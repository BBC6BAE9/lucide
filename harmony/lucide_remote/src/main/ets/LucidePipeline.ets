import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { LucideGlyph } from './LucideGlyph';
import { LucideName } from './LucideName';
import { LucideSVG, LucideSVGException } from './LucideSVG';

/** Locates the SVGs for a version of lucide-static. */
export class LucideSource {
  static readonly defaultVersion: string = LucideName.version;
  readonly version: string;
  private readonly resolve: (name: string) => string;

  constructor(version: string, url: (name: string) => string) {
    this.version = version;
    this.resolve = url;
  }

  url(name: LucideName): string {
    return this.resolve(name.rawValue);
  }

  static jsDelivr(version: string = LucideSource.defaultVersion): LucideSource {
    return new LucideSource(version, (name: string) =>
      `https://cdn.jsdelivr.net/npm/lucide-static@${version}/icons/${name}.svg`);
  }

  static unpkg(version: string = LucideSource.defaultVersion): LucideSource {
    return new LucideSource(version, (name: string) => `https://unpkg.com/lucide-static@${version}/icons/${name}.svg`);
  }

  static mirror(base: string, version: string = LucideSource.defaultVersion): LucideSource {
    const suffixStart = base.search(/[?#]/);
    const directory = suffixStart < 0 ? base : base.slice(0, suffixStart);
    const suffix = suffixStart < 0 ? '' : base.slice(suffixStart);
    return new LucideSource(version, (name: string) => `${directory.replace(/\/+$/, '')}/${name}.svg${suffix}`);
  }
}

export enum LucideIconErrorCode {
  notFound,
  httpStatus,
  tooLarge,
  invalidSVG
}

export class LucideIconError extends Error {
  readonly code: LucideIconErrorCode;
  readonly name: string = 'LucideIconError';
  readonly icon?: LucideName;
  readonly status?: number;
  readonly svgError?: LucideSVGException;

  constructor(code: LucideIconErrorCode, icon?: LucideName, status?: number, svgError?: LucideSVGException) {
    super(LucideIconErrorCode[code]);
    this.code = code;
    this.icon = icon;
    this.status = status;
    this.svgError = svgError;
  }
}

export interface LucidePipelineOptions {
  source?: LucideSource;
  session?: () => http.HttpRequest;
  bundle?: common.Context;
  bundleSubdirectory?: string;
  diskCache?: string | null;
  memoryLimit?: number;
}

/** Reads memory, bundled rawfiles, disk, then the network. Concurrent misses share one request. */
export class LucidePipeline {
  static readonly maximumDocumentSize = 64 * 1024;
  private static readonly sharedPipeline = new LucidePipeline();

  readonly source: LucideSource;
  private readonly session: () => http.HttpRequest;
  private readonly bundle?: common.Context;
  private readonly assetPrefix: string;
  private readonly cacheVersion: string;
  private readonly memoryLimit: number;
  private readonly memory = new Map<LucideName, LucideGlyph>();
  private readonly inFlight = new Map<LucideName, Promise<LucideGlyph>>();
  private diskDirectory?: string;

  constructor(options?: LucidePipelineOptions) {
    this.source = options?.source ?? LucideSource.jsDelivr();
    this.session = options?.session ?? http.createHttp;
    this.bundle = options?.bundle;
    const subdirectory = options?.bundleSubdirectory?.replace(/^\/+|\/+$/g, '') ?? '';
    this.assetPrefix = subdirectory.length > 0 ? subdirectory + '/' : '';
    const version = this.source.version.replace(/[^A-Za-z0-9.-]/g, '_');
    this.cacheVersion = version === '' || version === '.' || version === '..' ? '_' : version;
    const cache = options?.diskCache === undefined && this.bundle !== undefined ?
      LucidePipeline.defaultDiskCache(this.bundle) : options?.diskCache;
    if (cache) {
      this.diskDirectory = cache + '/' + this.cacheVersion;
    }
    const limit = options?.memoryLimit ?? 1024;
    this.memoryLimit = Number.isFinite(limit) ? Math.max(1, Math.floor(limit)) : 1024;
  }

  static shared(context?: common.Context): LucidePipeline {
    const pipeline = LucidePipeline.sharedPipeline;
    if (context !== undefined && pipeline.diskDirectory === undefined) {
      pipeline.diskDirectory = LucidePipeline.defaultDiskCache(context) + '/' + pipeline.cacheVersion;
    }
    return pipeline;
  }

  static defaultDiskCache(context: common.Context): string {
    return context.cacheDir + '/LucideRemote';
  }

  cachedGlyph(name: LucideName): LucideGlyph | undefined {
    return this.memory.get(name);
  }

  /** Returns an icon synchronously using the available local caches. */
  localGlyph(name: LucideName): LucideGlyph | undefined {
    const cached = this.cachedGlyph(name);
    if (cached !== undefined) {
      return cached;
    }
    return this.loadBundled(name) ?? this.loadDisk(name);
  }

  glyph(name: LucideName): Promise<LucideGlyph> {
    const cached = this.cachedGlyph(name);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    const existing = this.inFlight.get(name);
    if (existing !== undefined) {
      return existing;
    }
    const request = Promise.resolve().then(async (): Promise<LucideGlyph> => {
      const local = this.localGlyph(name);
      if (local !== undefined) {
        return local;
      }
      const glyph = await this.download(name);
      return this.remember(name, glyph);
    }).finally(() => {
      this.inFlight.delete(name);
    });
    this.inFlight.set(name, request);
    return request;
  }

  prefetch(names: Iterable<LucideName>): void {
    for (const name of names) {
      this.glyph(name).catch(() => {
        // A later glyph() call can retry.
      });
    }
  }

  removeAllFromMemory(): void {
    this.memory.clear();
  }

  async image(name: LucideName, pointSize: number = 24, strokeWidth?: number, absoluteStrokeWidth: boolean = false,
    scale: number = 3): Promise<image.PixelMap | undefined> {
    const glyph = await this.glyph(name);
    return glyph.image(pointSize, strokeWidth, absoluteStrokeWidth, scale);
  }

  private remember(name: LucideName, glyph: LucideGlyph): LucideGlyph {
    this.memory.set(name, glyph);
    if (this.memory.size > this.memoryLimit) {
      this.memory.delete(this.memory.keys().next().value);
    }
    return glyph;
  }

  private loadBundled(name: LucideName): LucideGlyph | undefined {
    if (this.bundle === undefined) {
      return undefined;
    }
    try {
      const data = this.bundle.resourceManager.getRawFileContentSync(this.assetPrefix + this.filename(name));
      return this.remember(name, this.decode(data));
    } catch {
      return undefined;
    }
  }

  private loadDisk(name: LucideName): LucideGlyph | undefined {
    if (this.diskDirectory === undefined) {
      return undefined;
    }
    try {
      const file = fileIo.openSync(this.diskDirectory + '/' + this.filename(name), fileIo.OpenMode.READ_ONLY);
      try {
        const size = fileIo.statSync(file.fd).size;
        if (size <= 0 || size > LucidePipeline.maximumDocumentSize) {
          return undefined;
        }
        const buffer = new ArrayBuffer(size);
        let count = 0;
        while (count < size) {
          const chunk = new ArrayBuffer(size - count);
          const length = fileIo.readSync(file.fd, chunk);
          if (length <= 0) {
            return undefined;
          }
          new Uint8Array(buffer).set(new Uint8Array(chunk, 0, length), count);
          count += length;
        }
        return this.remember(name, this.decode(new Uint8Array(buffer)));
      } finally {
        fileIo.closeSync(file);
      }
    } catch {
      return undefined;
    }
  }

  private async download(name: LucideName): Promise<LucideGlyph> {
    const request = this.session();
    let response: http.HttpResponse;
    try {
      response = await request.request(this.source.url(name), {
        method: http.RequestMethod.GET,
        connectTimeout: 10_000,
        readTimeout: 10_000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        maxLimit: LucidePipeline.maximumDocumentSize + 1
      });
    } catch (error) {
      if ((error as BusinessError).code === 2300063) {
        throw new LucideIconError(LucideIconErrorCode.tooLarge, name);
      }
      throw error as Error;
    } finally {
      request.destroy();
    }
    const status = response.responseCode;
    if (status === 404) {
      throw new LucideIconError(LucideIconErrorCode.notFound, name, status);
    }
    if (status < 200 || status >= 300) {
      throw new LucideIconError(LucideIconErrorCode.httpStatus, name, status);
    }
    const data = response.result;
    if (!(data instanceof ArrayBuffer)) {
      throw new LucideIconError(LucideIconErrorCode.invalidSVG, name);
    }
    const glyph = this.decode(new Uint8Array(data));
    this.cache(name, data);
    return glyph;
  }

  private decode(data: Uint8Array): LucideGlyph {
    if (data.byteLength > LucidePipeline.maximumDocumentSize) {
      throw new LucideIconError(LucideIconErrorCode.tooLarge);
    }
    try {
      return LucideSVG.parse(data);
    } catch (error) {
      throw new LucideIconError(LucideIconErrorCode.invalidSVG, undefined, undefined, error as LucideSVGException);
    }
  }

  private cache(name: LucideName, data: ArrayBuffer): void {
    const directory = this.diskDirectory;
    if (directory === undefined) {
      return;
    }
    const temporary = directory + '/icon-' + util.generateRandomUUID() + '.tmp';
    try {
      try {
        fileIo.mkdirSync(directory, true);
      } catch (error) {
        if ((error as BusinessError).code !== 13900015) {
          throw error as Error;
        }
      }
      const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      let size: number;
      try {
        size = fileIo.writeSync(file.fd, data);
      } finally {
        fileIo.closeSync(file);
      }
      if (size === data.byteLength) {
        fileIo.renameSync(temporary, directory + '/' + this.filename(name));
        return;
      }
    } catch {
      // A failed cache write does not prevent rendering the downloaded icon.
    }
    try {
      fileIo.unlinkSync(temporary);
    } catch {
      // The temporary file may never have been created.
    }
  }

  private filename(name: LucideName): string {
    return name.rawValue + '.svg';
  }
}
