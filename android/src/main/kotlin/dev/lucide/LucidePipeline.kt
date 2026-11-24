package dev.lucide

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.launch

/** Locates the SVGs for a version of lucide-static. */
class LucideSource(val version: String, private val url: (String) -> URL) {
    fun url(name: LucideName): URL = url(name.rawValue)

    companion object {
        const val defaultVersion = LucideName.version

        fun jsDelivr(version: String = defaultVersion) = LucideSource(version) {
            URL("https://cdn.jsdelivr.net/npm/lucide-static@$version/icons/$it.svg")
        }

        fun unpkg(version: String = defaultVersion) = LucideSource(version) {
            URL("https://unpkg.com/lucide-static@$version/icons/$it.svg")
        }

        fun mirror(base: URL, version: String = defaultVersion) = LucideSource(version) {
            URL(Uri.parse(base.toExternalForm()).buildUpon().appendPath("$it.svg").build().toString())
        }
    }
}

sealed class LucideIconError(message: String, cause: Throwable? = null) : IOException(message, cause) {
    class NotFound(val name: LucideName) : LucideIconError("Icon ${name.rawValue} was not found")
    class HttpStatus(val status: Int) : LucideIconError("HTTP $status")
    class TooLarge : LucideIconError("SVG exceeds the maximum document size")
    class InvalidSVG(val error: LucideSVGException) : LucideIconError("Invalid SVG", error)
}

/** Reads memory, bundled assets, disk, then the network. Concurrent misses share one request. */
class LucidePipeline(
    val source: LucideSource = LucideSource.jsDelivr(),
    private val session: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection },
    bundle: Context? = null,
    bundleSubdirectory: String? = null,
    diskCache: File? = bundle?.let { defaultDiskCache(it) },
    memoryLimit: Int = 1024,
) {
    private val assets = bundle?.assets
    private val assetPrefix = bundleSubdirectory?.trim('/')?.takeIf(String::isNotEmpty)
        ?.let { "$it/" }.orEmpty()
    private val cacheVersion = source.version.replace(Regex("[^A-Za-z0-9.-]"), "_")
        .takeUnless { it.isEmpty() || it == "." || it == ".." } ?: "_"
    @Volatile private var diskDirectory = diskCache?.resolve(cacheVersion)
    private val memoryLimit = memoryLimit.coerceAtLeast(1)
    private val memory = LinkedHashMap<LucideName, LucideGlyph>()
    private val inFlight = mutableMapOf<LucideName, Deferred<LucideGlyph>>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    companion object {
        const val maximumDocumentSize = 64 * 1024
        val shared = LucidePipeline()

        /** Enables the application cache directory on the shared instance. */
        fun shared(context: Context): LucidePipeline = shared.apply {
            if (diskDirectory == null) diskDirectory = defaultDiskCache(context).resolve(cacheVersion)
        }

        fun defaultDiskCache(context: Context): File = context.cacheDir.resolve("LucideRemote")
    }

    fun cachedGlyph(name: LucideName): LucideGlyph? = synchronized(memory) { memory[name] }

    /** Returns an icon synchronously without accessing the network. */
    fun localGlyph(name: LucideName): LucideGlyph? {
        cachedGlyph(name)?.let { return it }
        return try {
            loadLocal(name)?.also { remember(name, it) }
        } catch (_: IOException) {
            null
        }
    }

    suspend fun glyph(name: LucideName): LucideGlyph {
        cachedGlyph(name)?.let { return it }
        val request = synchronized(inFlight) {
            cachedGlyph(name)?.let { return it }
            inFlight[name] ?: scope.async(start = CoroutineStart.LAZY) {
                try {
                    val glyph = loadLocal(name) ?: download(name)
                    remember(name, glyph)
                    glyph
                } finally {
                    synchronized(inFlight) { inFlight.remove(name) }
                }
            }.also { inFlight[name] = it }
        }
        return request.await()
    }

    fun prefetch(names: Iterable<LucideName>) {
        for (name in names) {
            scope.launch {
                try {
                    glyph(name)
                } catch (_: IOException) {
                    // The next call to glyph can retry.
                }
            }
        }
    }

    fun removeAllFromMemory() = synchronized(memory) { memory.clear() }

    suspend fun image(
        name: LucideName,
        pointSize: Float = 24f,
        strokeWidth: Float? = null,
        absoluteStrokeWidth: Boolean = false,
        scale: Float = 3f,
    ): Bitmap? = glyph(name).image(pointSize, strokeWidth, absoluteStrokeWidth, scale)

    private fun remember(name: LucideName, glyph: LucideGlyph) {
        synchronized(memory) {
            memory[name] = glyph
            if (memory.size > memoryLimit) memory.remove(memory.keys.first())
        }
    }

    private fun loadLocal(name: LucideName): LucideGlyph? {
        val file = "${name.rawValue}.svg"
        try {
            assets?.open(assetPrefix + file)?.use { return decode(it.readDocument()) }
        } catch (_: FileNotFoundException) {
            // Most icons are not in the application bundle.
        }
        return try {
            diskDirectory?.resolve(file)?.inputStream()?.use { decode(it.readDocument()) }
        } catch (_: IOException) {
            null
        }
    }

    private fun download(name: LucideName): LucideGlyph {
        val connection = session(source.url(name))
        val data = try {
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            val status = connection.responseCode
            if (status == 404) throw LucideIconError.NotFound(name)
            if (status !in 200..299) throw LucideIconError.HttpStatus(status)
            connection.inputStream.use { it.readDocument() }
        } finally {
            connection.disconnect()
        }
        val glyph = decode(data)
        diskDirectory?.let { cache(it, "${name.rawValue}.svg", data) }
        return glyph
    }

    private fun decode(data: ByteArray): LucideGlyph {
        return try {
            LucideSVG.parse(data)
        } catch (error: LucideSVGException) {
            throw LucideIconError.InvalidSVG(error)
        }
    }

    private fun InputStream.readDocument(): ByteArray {
        val buffer = ByteArray(maximumDocumentSize + 1)
        var count = 0
        while (count < buffer.size) {
            val read = read(buffer, count, buffer.size - count)
            if (read < 0) return buffer.copyOf(count)
            count += read
        }
        throw LucideIconError.TooLarge()
    }

    private fun cache(directory: File, name: String, data: ByteArray) {
        try {
            Files.createDirectories(directory.toPath())
            val temporary = Files.createTempFile(directory.toPath(), "icon-", ".tmp")
            try {
                Files.write(temporary, data)
                Files.move(
                    temporary, directory.resolve(name).toPath(),
                    StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING,
                )
            } finally {
                Files.deleteIfExists(temporary)
            }
        } catch (_: IOException) {
            // A failed cache write does not prevent rendering the downloaded icon.
        }
    }
}
