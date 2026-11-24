# Lucide

原生矢量 Lucide 图标包，支持 iOS 17+、macOS 14+、Android API 26+ 和 HarmonyOS NEXT API 14+。Swift、Kotlin 和 ArkTS 的图标目录由同一个脚本从 `lucide-static 1.70.0` 生成，包含相同的图标名和弃用别名。三端按内存、随包 SVG、磁盘缓存、网络的顺序加载图标，同名并发请求共用一次加载。

## 安装

**Apple** 在 SwiftPM 中添加远程仓库并链接 `Lucide` 产品。

```swift
.package(url: "https://github.com/BBC6BAE9/lucide.git", exact: "1.0.0")
.product(name: "Lucide", package: "lucide")
```

**Android** 拉取 `1.0.0` 标签，在 `settings.gradle.kts` 中引入 Android library 模块。路径相对于使用方的 Gradle 根目录。

```kotlin
include(":lucide")
project(":lucide").projectDir = file("../lucide/android")
```

在 app 模块的 `dependencies` 中添加 `implementation(project(":lucide"))`。包使用 AGP 8.13.2、Kotlin 和 Compose 编译器插件 2.2.21，以及 JDK 17 和 compileSdk 36。

**HarmonyOS** 用 DevEco Studio 6.1.1 打开 `harmony/` 工程生成 HAR，或在该目录使用 DevEco 自带的 OHPM 和 Hvigor 执行以下命令。

```sh
ohpm install
hvigorw --mode module -p module=lucide@default -p product=default assembleHar
```

将生成的 `harmony/lucide/build/default/outputs/default/lucide.har` 添加到应用模块的 `oh-package.json5`。路径相对于该文件。

```json5
"dependencies": {
  "lucide": "file:../libs/lucide.har"
}
```

同步 OHPM 依赖后，在 ArkUI 中使用 `import { LucideIcon, LucideName, LucidePipeline } from 'lucide'`。使用远程图标的应用需要在入口模块的 `module.json5` 的 `requestPermissions` 中声明 `{ "name": "ohos.permission.INTERNET" }`。

## 调用对照

| 用途 | Swift | Kotlin | ArkTS |
| --- | --- | --- | --- |
| 矢量图标 | `LucideIcon(.arrowUpRight, size: 20)` | `LucideIcon(LucideName.arrowUpRight, size = 20.dp)` | `LucideIcon({ name: LucideName.arrowUpRight, size: 20 })` |
| 自定义笔画 | `LucideIcon(.search, size: 48, strokeWidth: 1.5, absoluteStrokeWidth: true)` | `LucideIcon(LucideName.search, size = 48.dp, strokeWidth = 1.5f, absoluteStrokeWidth = true)` | `LucideIcon({ name: LucideName.search, size: 48, strokeWidth: 1.5, absoluteStrokeWidth: true })` |
| 服务端图标名 | `LucideName(rawValue: "book-open")` | `LucideName.fromRawValue("book-open")` | `LucideName.fromRawValue('book-open')` |
| 立即取图，仅读取本地 | `pipeline.localGlyph(.trash)?.image(pointSize: 17)` | `pipeline.localGlyph(LucideName.trash)?.image(pointSize = 17f)` | `pipeline.localGlyph(LucideName.trash)?.image(17)` |
| 异步取图，允许下载 | `try await pipeline.image(.trash, pointSize: 17)` | `pipeline.image(LucideName.trash, pointSize = 17f)` | `await pipeline.image(LucideName.trash, 17)` |

Swift 使用 `import Lucide`，在 SwiftUI 中通过 `.foregroundStyle(...)` 着色。`image()` 返回 UIKit 或 AppKit 的模板图像。Android 使用 `import dev.lucide.*`，给 `LucideIcon` 传 `tint` 或继承 Compose 的内容色。`image()` 返回可着色的透明背景 `Bitmap`，`pointSize * scale` 是像素边长。Kotlin 的 `glyph` 和 `image` 为 `suspend` 函数。

ArkUI 的 `LucideIcon` 使用 vp 为单位。传入 `tint` 可自定义颜色，默认使用系统主文字色。`glyph` 和 `image` 返回 `Promise`。同步 `LucideGlyph.image()` 返回可用颜色滤镜着色的透明 `PixelMap`，像素边长为 `ceil(pointSize * scale)`。

图标名遇到 Kotlin 关键字时用反引号，例如 `` LucideName.`package` `` 对应 Swift 的 `.package`。

三端的 `LucidePipeline` 还提供 `cachedGlyph`、`glyph`、`prefetch`、`removeAllFromMemory`，以及 `LucideSource.jsDelivr()`、`.unpkg()` 和 `.mirror(...)`。默认下载源为 jsDelivr，也可指定自部署的镜像目录。

### 离线首帧

将随应用发货的 `<name>.svg` 放进应用资源，并使用同版本 SVG。

```swift
let pipeline = LucidePipeline(bundle: .main, bundleSubdirectory: "LucideIcons")
LucideIcon(.search).environment(\.lucidePipeline, pipeline)
```

```kotlin
// app/src/main/assets/LucideIcons/search.svg
val context = LocalContext.current
val pipeline = remember(context) {
    LucidePipeline(bundle = context, bundleSubdirectory = "LucideIcons")
}
CompositionLocalProvider(LocalLucidePipeline provides pipeline) {
    LucideIcon(LucideName.search)
}
```

Android 的默认 Compose 入口使用 `LucidePipeline.shared(context)` 启用应用磁盘缓存。非 Compose 调用也可用这个入口。自定义管线可以提供 `bundle` 或 `diskCache`，也可以显式传入 `diskCache = null` 关闭磁盘缓存。

HarmonyOS 将资源放在应用模块的 `src/main/resources/rawfile/LucideIcons/search.svg`。在调用方用应用上下文创建一次管线，并传入 `LucideIcon`。

```typescript
const pipeline = new LucidePipeline({ bundle: context, bundleSubdirectory: 'LucideIcons' });
// 在 ArkUI 的 build() 中
LucideIcon({ name: LucideName.search, pipeline: pipeline })
```

ArkUI 默认使用 `LucidePipeline.shared(context)` 启用应用磁盘缓存。自定义管线可通过 `diskCache` 指定目录，或传入 `diskCache: null` 关闭磁盘缓存。

## 更新图标目录

```sh
./Scripts/generate-names.py 1.70.0
LUCIDE_ICONS_DIR=/path/to/lucide-static/icons swift test
```

Swift 实现源自 [LucideRemote 上游修订](https://github.com/BBC6BAE9/LucideRemote/tree/4425b384e040b82ab0eec6433975bb72dc579746)。Lucide 图标授权见 [Lucide License](https://lucide.dev/license)。
