# Lucide

Native vector icons for SwiftUI, Jetpack Compose, and ArkUI. All three libraries share the [Lucide](https://lucide.dev/) icon catalog, support bundled SVGs for offline use, and cache downloads.

## Apple

Requires iOS 17+ or macOS 14+ and Swift 6.2.1+. Add the Swift package and link its `Lucide` product.

```swift
.package(url: "https://github.com/BBC6BAE9/lucide.git", exact: "1.0.0")
.product(name: "Lucide", package: "lucide")
```

```swift
import Lucide

LucideIcon(.search, size: 20)
```

## Android

Requires API 26+, JDK 17, and compile SDK 36. Use AGP 8.13.2 and Kotlin and Compose compiler plugins 2.2.21. Clone the `1.0.0` tag next to your Gradle project and include the module in `settings.gradle.kts`.

```kotlin
include(":lucide")
project(":lucide").projectDir = file("../lucide/android")
```

Add `implementation(project(":lucide"))` to your app dependencies.

```kotlin
import dev.lucide.LucideIcon
import dev.lucide.LucideName
import androidx.compose.ui.unit.dp

LucideIcon(LucideName.search, size = 20.dp)
```

## HarmonyOS

Requires HarmonyOS NEXT API 14+. Build the HAR from `harmony/` with the DevEco Studio 6.1.1 tools.

```sh
ohpm install
hvigorw --mode module -p module=lucide@default -p product=default assembleHar
```

Copy `lucide/build/default/outputs/default/lucide.har` to your app's `libs/` directory. Add `"lucide": "file:../libs/lucide.har"` to your app module's `oh-package.json5` dependencies. Declare `ohos.permission.INTERNET` in the app module for icon downloads.

```typescript
import { LucideIcon, LucideName } from 'lucide';

LucideIcon({ name: LucideName.search, size: 20 })
```

## License

Icons follow the [Lucide License](https://lucide.dev/license). The Swift implementation is based on [LucideRemote](https://github.com/BBC6BAE9/LucideRemote/tree/4425b384e040b82ab0eec6433975bb72dc579746).
