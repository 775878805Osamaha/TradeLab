package com.example.core.market

import java.io.File
import java.io.IOException
import java.security.MessageDigest

/** Optional, bounded cache of completed public archive files. Never stores credentials. */
internal class ChartArchiveDiskCache(private val directory: File, private val maxBytes: Long = 16L * 1024 * 1024) {
    private fun file(path: String): File {
        val hash = MessageDigest.getInstance("SHA-256").digest(path.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        return File(directory, "$hash.bi5")
    }

    fun read(path: String): ByteArray? = try {
        val file = file(path)
        if (!file.isFile) null else if (file.length() !in 1..200_000L) {
            file.delete(); null
        } else file.readBytes().also { file.setLastModified(System.currentTimeMillis()) }
    } catch (_: IOException) { null }

    fun remove(path: String) { file(path).delete() }

    fun write(path: String, bytes: ByteArray) {
        if (bytes.isEmpty() || bytes.size > 200_000 || bytes.size > maxBytes) return
        var temporary: File? = null
        try {
            if (!directory.isDirectory && !directory.mkdirs()) return
            temporary = File.createTempFile("archive-", ".tmp", directory)
            temporary.writeBytes(bytes)
            if (!temporary.renameTo(file(path))) return
            val files = directory.listFiles { f -> f.name.endsWith(".bi5") }?.sortedBy { it.lastModified() } ?: return
            var total = files.sumOf { it.length() }
            for (entry in files) {
                if (total <= maxBytes) break
                val size = entry.length()
                if (entry.delete()) total -= size
            }
        } catch (_: IOException) {
            // Disk full or unavailable: verified network data remains usable.
        } finally { temporary?.delete() }
    }
}
