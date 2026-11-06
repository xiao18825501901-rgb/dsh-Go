package io.github.ccch1mneyyy.dsh_app.pet

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.zip.ZipInputStream

/**
 * MethodChannel `dsh/pet_pack` (Dart: `lib/pets/custom_pets.dart`).
 *
 * Packs live in `filesDir/pets/<id>/`, the folder `PetSprites.sourceFor` already falls back to,
 * so a pack imported here works for the in-app pet and the overlay without touching the APK.
 *
 * - `list` → `[{id, name}]`
 * - `pick` → `{id, name}` | `{problem}`: the system picker (pack.json + its PNG sheets, or one zip)
 * - `delete {id}` → bool
 * - `root` → the install folder, for the settings footnote
 *
 * Nothing is read outside the picked URIs; a pack is only installed when its `pack.json` parses and
 * every `.png` it references is present.
 */
class PetPackImportPlugin : FlutterPlugin, ActivityAware, ActivityPluginBinding.OnActivityResultListener {
    private var context: Context? = null
    private var channel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val appContext = binding.applicationContext
        context = appContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { c ->
            c.setMethodCallHandler { call, result -> onCall(call, result) }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("no-context", "no context", null)
        when (call.method) {
            "list" -> result.success(store(ctx).list())
            "root" -> result.success(File(ctx.filesDir, "pets").absolutePath)
            "delete" -> {
                val id = call.argument<String>("id")
                result.success(id != null && store(ctx).delete(id))
            }
            "pick" -> pick(result)
            else -> result.notImplemented()
        }
    }

    private fun pick(result: MethodChannel.Result) {
        val binding = activityBinding
        if (pending != null) return result.error("busy", "another import is running", null)
        if (binding == null) return result.error("no-activity", "the app is not in the foreground", null)
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        binding.activity.startActivityForResult(intent, REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val result = pending ?: return true
        pending = null
        val ctx = context
        if (resultCode != Activity.RESULT_OK || data == null || ctx == null) {
            result.success(mapOf("problem" to "cancelled"))
            return true
        }
        val uris = ArrayList<Uri>().apply {
            data.clipData?.let { clip -> for (i in 0 until clip.itemCount) add(clip.getItemAt(i).uri) }
            data.data?.let { add(it) }
        }
        if (uris.isEmpty()) {
            result.success(mapOf("problem" to "cancelled"))
            return true
        }
        result.success(store(ctx).importFrom(ctx, uris))
        return true
    }

    private fun store(context: Context) = PetPackStore(context)

    companion object {
        private const val CHANNEL = "dsh/pet_pack"
        private const val REQUEST = 0x5A4B
    }
}

/** Validates and installs pet packs into `filesDir/pets/<id>/`. */
class PetPackStore(private val context: Context) {
    private val root: File get() = File(context.filesDir, "pets")

    private val idPattern = Regex("^[a-z0-9][a-z0-9-]{0,39}$")

    fun list(): List<Map<String, Any?>> {
        val dirs = root.listFiles()?.filter { it.isDirectory } ?: return emptyList()
        return dirs.mapNotNull { dir ->
            val meta = readMeta(dir) ?: return@mapNotNull null
            val name = meta.optString("name").ifBlank { dir.name }
            mapOf("id" to dir.name, "name" to name)
        }.sortedBy { (it["name"] as String).lowercase() }
    }

    fun delete(id: String): Boolean {
        if (!idPattern.matches(id)) return false
        val dir = File(root, id)
        return dir.isDirectory && dir.deleteRecursively()
    }

    /** Copies [uris] into a staging folder, resolves the pack and installs it. */
    fun importFrom(context: Context, uris: List<Uri>): Map<String, Any?> {
        val staging = File(context.cacheDir, "pet-import-${System.currentTimeMillis()}")
        if (!staging.mkdirs()) return problem("no-space")
        try {
            for ((index, uri) in uris.withIndex()) {
                val name = nameOf(context, uri, index)
                if (name.contains('/') || name.contains("..")) continue
                val target = File(staging, name)
                context.contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                } ?: continue
            }
            expandZips(staging)
            val packJson = findPackJson(staging) ?: return problem("missing-pack-json")
            return install(packJson.parentFile!!)
        } catch (e: Exception) {
            return problem("io:${e.message?.take(60) ?: "failed"}")
        } finally {
            staging.deleteRecursively()
        }
    }

    private fun install(dir: File): Map<String, Any?> {
        val meta = readMeta(dir) ?: return problem("bad-pack-json")
        val id = meta.optString("id").ifBlank { dir.name }
        if (!idPattern.matches(id)) return problem("bad-id")
        val sheets = pngReferences(meta)
        for (sheet in sheets) {
            if (!File(dir, sheet).isFile) return problem("missing-sheet:$sheet")
        }
        val bytes = dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        if (bytes > MAX_BYTES) return problem("too-large")
        val target = File(root, id)
        if (target.exists() && !target.deleteRecursively()) return problem("locked")
        root.mkdirs()
        if (!dir.renameTo(target)) {
            if (!dir.copyRecursively(target, overwrite = true)) return problem("io")
        }
        val name = meta.optString("name").ifBlank { id }
        return mapOf("id" to id, "name" to name)
    }

    private fun readMeta(dir: File): JSONObject? {
        val file = File(dir, "pack.json")
        if (!file.isFile || file.length() > MAX_JSON) return null
        return try {
            JSONObject(file.readText())
        } catch (_: Exception) {
            null
        }
    }

    /** Every `.png` the pack mentions, wherever it sits in the schema. */
    private fun pngReferences(meta: JSONObject): Set<String> {
        val out = LinkedHashSet<String>()
        fun walk(value: Any?) {
            when (value) {
                is JSONObject -> for (key in value.keys()) walk(value.opt(key))
                is JSONArray -> for (i in 0 until value.length()) walk(value.opt(i))
                is String -> if (value.endsWith(".png", true)) out.add(value)
            }
        }
        walk(meta)
        return out.filterNot { it.startsWith("/") || it.contains("..") }.toSet()
    }

    private fun expandZips(staging: File) {
        for (file in staging.listFiles().orEmpty()) {
            if (!file.name.endsWith(".zip", true)) continue
            val out = File(staging, file.nameWithoutExtension)
            out.mkdirs()
            ZipInputStream(file.inputStream().buffered()).use { zip ->
                var entry = zip.nextEntry
                var guard = 0
                while (entry != null && guard++ < MAX_ENTRIES) {
                    val name = entry.name
                    if (!entry.isDirectory && !name.startsWith("/") && !name.contains("..")) {
                        val target = File(out, name)
                        target.parentFile?.mkdirs()
                        target.outputStream().use { output -> zip.copyTo(output) }
                    }
                    zip.closeEntry()
                    entry = zip.nextEntry
                }
            }
            file.delete()
        }
    }

    private fun findPackJson(dir: File, depth: Int = 3): File? {
        if (depth < 0) return null
        File(dir, "pack.json").takeIf { it.isFile }?.let { return it }
        for (child in dir.listFiles().orEmpty()) {
            if (child.isDirectory) findPackJson(child, depth - 1)?.let { return it }
        }
        return null
    }

    private fun nameOf(context: Context, uri: Uri, index: Int): String {
        val fromProvider = context.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        val fallback = uri.lastPathSegment?.substringAfterLast('/') ?: "file-$index"
        return (fromProvider ?: fallback).substringAfterLast('/')
    }

    private fun problem(code: String) = mapOf("problem" to code)

    companion object {
        private const val MAX_JSON = 1L * 1024 * 1024
        private const val MAX_BYTES = 48L * 1024 * 1024
        private const val MAX_ENTRIES = 512
    }
}
