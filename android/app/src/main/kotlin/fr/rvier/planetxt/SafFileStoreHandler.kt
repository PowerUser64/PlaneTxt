package fr.rvier.planetxt

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.FileNotFoundException
import java.io.InputStreamReader
import java.io.SyncFailedException
import java.nio.charset.CodingErrorAction
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Storage Access Framework backend for PlaneTxt's user-selected storage root.
 *
 * Exposes a method channel ("fr.rvier.planetxt/saf") that addresses files by
 * paths relative to a persisted document-tree URI, mirroring the Dart
 * FileStore interface. No storage permission is required: access comes from
 * the persistable URI grant the user gives via ACTION_OPEN_DOCUMENT_TREE.
 */
class SafFileStoreHandler(private val activity: Activity) {

    companion object {
        const val CHANNEL = "fr.rvier.planetxt/saf"
        const val PICK_TREE_REQUEST_CODE = 4217
        private const val TAG = "SafFileStore"
        private const val DIR_MIME = DocumentsContract.Document.MIME_TYPE_DIR

        // Hidden temp document a write goes through before replacing the
        // original: ".<name><suffix>", never matched by a ".md" listing.
        private const val TEMP_SUFFIX = ".planetxt-tmp"
        private const val TEMP_MIME = "application/octet-stream"
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPickResult: MethodChannel.Result? = null

    /** Cache of resolved directory document IDs, keyed by "treeUri|relDir". */
    private val dirIdCache = ConcurrentHashMap<String, String>()

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickTree" -> pickTree(result)
                "persistedTrees" -> result.success(
                    activity.contentResolver.persistedUriPermissions
                        .filter { it.isReadPermission && it.isWritePermission }
                        .map { it.uri.toString() }
                )
                "releaseTree" -> {
                    val uri = Uri.parse(call.argument<String>("treeUri")!!)
                    try {
                        activity.contentResolver.releasePersistableUriPermission(
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        )
                    } catch (e: SecurityException) {
                        Log.w(TAG, "releaseTree: no persisted permission for $uri")
                    }
                    dirIdCache.clear()
                    result.success(true)
                }
                "treeDisplayName" -> runInBackground(result) {
                    treeDisplayName(Uri.parse(call.argument<String>("treeUri")!!))
                }
                "listTree" -> runInBackground(result) {
                    listTree(
                        Uri.parse(call.argument<String>("treeUri")!!),
                        call.argument<String>("relDir")!!,
                        call.argument<String>("extension")!!,
                        call.argument<Boolean>("recursive")!!
                    )
                }
                "readFile" -> runInBackground(result) {
                    readFile(
                        Uri.parse(call.argument<String>("treeUri")!!),
                        call.argument<String>("relPath")!!
                    )
                }
                "readFiles" -> runInBackground(result) {
                    readFiles(
                        Uri.parse(call.argument<String>("treeUri")!!),
                        call.argument<List<String>>("relPaths")!!
                    )
                }
                "writeFile" -> runInBackground(result) {
                    writeFile(
                        Uri.parse(call.argument<String>("treeUri")!!),
                        call.argument<String>("relPath")!!,
                        call.argument<String>("content")!!
                    )
                    true
                }
                "deleteFile" -> runInBackground(result) {
                    deleteFile(
                        Uri.parse(call.argument<String>("treeUri")!!),
                        call.argument<String>("relPath")!!
                    )
                    true
                }
                "statFile" -> runInBackground(result) {
                    statFile(
                        Uri.parse(call.argument<String>("treeUri")!!),
                        call.argument<String>("relPath")!!
                    )
                }
                "renameFile" -> runInBackground(result) {
                    renameFile(
                        Uri.parse(call.argument<String>("treeUri")!!),
                        call.argument<String>("fromRelPath")!!,
                        call.argument<String>("toRelPath")!!
                    )
                    true
                }
                "ensureDirectory" -> runInBackground(result) {
                    resolveDirId(
                        Uri.parse(call.argument<String>("treeUri")!!),
                        call.argument<String>("relDir")!!,
                        create = true
                    )
                    true
                }
                else -> result.notImplemented()
            }
        }
    }

    // --- tree picker -----------------------------------------------------

    private fun pickTree(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("PICK_IN_PROGRESS", "A folder picker is already open", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        }
        activity.startActivityForResult(intent, PICK_TREE_REQUEST_CODE)
    }

    /** Call from the activity's onActivityResult. Returns true when handled. */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_TREE_REQUEST_CODE) return false
        val result = pendingPickResult ?: return true
        pendingPickResult = null

        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            result.success(uri.toString())
        } catch (e: SecurityException) {
            Log.e(TAG, "Could not persist permission for $uri", e)
            result.error("PERSIST_FAILED", e.message, null)
        }
        return true
    }

    // --- operations (background thread) ----------------------------------

    private fun treeDisplayName(treeUri: Uri): String {
        // "primary:Sync/Org" → "Sync/Org"; fall back to the root doc name.
        val treeDocId = DocumentsContract.getTreeDocumentId(treeUri)
        val path = treeDocId.substringAfter(':', "")
        if (path.isNotEmpty()) return path
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocId)
        activity.contentResolver.query(
            rootUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { c -> if (c.moveToFirst()) return c.getString(0) }
        return treeUri.lastPathSegment ?: treeUri.toString()
    }

    private fun listTree(
        treeUri: Uri,
        relDir: String,
        extension: String,
        recursive: Boolean
    ): List<Map<String, Any?>> {
        val dirId = resolveDirId(treeUri, relDir, create = false)
            ?: return emptyList()
        val out = mutableListOf<Map<String, Any?>>()
        listInto(treeUri, dirId, relDir.trim('/'), extension, recursive, out)
        return out
    }

    private fun listInto(
        treeUri: Uri,
        dirDocId: String,
        relDir: String,
        extension: String,
        recursive: Boolean,
        out: MutableList<Map<String, Any?>>
    ) {
        val fileIds = HashMap<String, String>()
        var temps = 0
        queryChildren(treeUri, dirDocId) { c ->
            val docId = c.getString(0)
            val name = c.getString(1)
            val mime = c.getString(2)
            val mtime = c.getLong(3)
            val childRel = if (relDir.isEmpty()) name else "$relDir/$name"
            if (mime == DIR_MIME) {
                if (recursive) {
                    listInto(treeUri, docId, childRel, extension, true, out)
                }
            } else {
                fileIds[name] = docId
                if (originalNameFor(name) != null) temps++
                if (name.endsWith(extension)) {
                    out.add(mapOf("relPath" to childRel, "mtime" to mtime))
                }
            }
        }
        if (temps == 0) return
        for (name in recoverTempFiles(treeUri, fileIds)) {
            if (name.endsWith(extension)) {
                val childRel = if (relDir.isEmpty()) name else "$relDir/$name"
                out.add(mapOf("relPath" to childRel, "mtime" to System.currentTimeMillis()))
            }
        }
    }

    private fun readFile(treeUri: Uri, relPath: String): String? {
        val docUri = resolveFileUri(treeUri, relPath) ?: return null
        return try {
            readText(docUri)
        } catch (e: FileNotFoundException) {
            null
        }
    }

    /**
     * Strict UTF-8 decode: malformed bytes throw instead of turning into
     * U+FFFD, which the next save would write back - silently and for good.
     */
    private fun readText(docUri: Uri): String? =
        activity.contentResolver.openInputStream(docUri)?.use { input ->
            val decoder = Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            BufferedReader(InputStreamReader(input, decoder)).readText()
        }

    /**
     * Bulk read: resolves each directory once (a single children query maps
     * every file name to its document id), then streams each requested file.
     * Missing files map to null. Orders of magnitude faster than per-file
     * [readFile] calls, which each re-scan their parent directory.
     */
    private fun readFiles(treeUri: Uri, relPaths: List<String>): Map<String, String?> {
        val out = HashMap<String, String?>(relPaths.size)
        val byParent = relPaths.groupBy { splitParent(it).first }
        for ((parentRel, paths) in byParent) {
            val parentId = resolveDirId(treeUri, parentRel, create = false)
            if (parentId == null) {
                paths.forEach { out[it] = null }
                continue
            }
            val nameToDocId = HashMap<String, String>()
            queryChildren(treeUri, parentId) { c ->
                if (c.getString(2) != DIR_MIME) {
                    nameToDocId[c.getString(1)] = c.getString(0)
                }
            }
            for (path in paths) {
                val docId = nameToDocId[splitParent(path).second]
                out[path] = if (docId == null) null else try {
                    readText(DocumentsContract.buildDocumentUriUsingTree(treeUri, docId))
                } catch (e: FileNotFoundException) {
                    null
                }
            }
        }
        return out
    }

    private fun writeFile(treeUri: Uri, relPath: String, content: String) {
        val (parentRel, name) = splitParent(relPath)
        val parentId = resolveDirId(treeUri, parentRel, create = true)
            ?: throw IllegalStateException("Cannot create directory $parentRel")
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, parentId)
        val bytes = content.toByteArray(Charsets.UTF_8)
        val tempName = tempNameFor(name)
        val children = findChildren(treeUri, parentId, setOf(name, tempName))
        val existing = children[name]

        if (existing == null) {
            // New file: an interrupted write loses nothing that existed.
            val docUri = DocumentsContract.createDocument(
                activity.contentResolver, parentUri, mimeFor(name), name
            ) ?: throw IllegalStateException("Cannot create document $relPath")
            writeBytes(docUri, bytes, relPath)
            // A temp left by a failed swap holds older content than this.
            children[tempName]?.let { deleteQuietly(treeUri, it.docId) }
            return
        }

        val existingUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, existing.docId)
        // Leftover of a write interrupted before the swap: the original is
        // still the committed version, so the temp is garbage.
        children[tempName]?.let { deleteQuietly(treeUri, it.docId) }

        val flags = documentFlags(existingUri)
        val canSwap = (flags and DocumentsContract.Document.FLAG_SUPPORTS_RENAME) != 0 &&
            (flags and DocumentsContract.Document.FLAG_SUPPORTS_DELETE) != 0
        val tempUri = if (canSwap) createQuietly(parentUri, tempName) else null
        if (tempUri == null) {
            // Provider cannot rename or refuses the temp: write in place.
            writeBytes(existingUri, bytes, relPath)
            return
        }

        // Crash-safe replace: the original is only removed once the new
        // content is complete and synced in the temp document. An
        // interruption leaves the intact original, or a complete temp that
        // [recoverTempFiles] renames back on the next listing.
        try {
            writeBytes(tempUri, bytes, relPath)
        } catch (e: Exception) {
            deleteQuietly(tempUri)
            throw e
        }
        DocumentsContract.deleteDocument(activity.contentResolver, existingUri)
        DocumentsContract.renameDocument(activity.contentResolver, tempUri, name)
            ?: throw IllegalStateException("Rename failed for $relPath")
    }

    private fun writeBytes(docUri: Uri, bytes: ByteArray, relPath: String) {
        val pfd = activity.contentResolver.openFileDescriptor(docUri, "wt")
            ?: throw IllegalStateException("Cannot open $relPath for writing")
        ParcelFileDescriptor.AutoCloseOutputStream(pfd).use { output ->
            output.write(bytes)
            output.flush()
            try {
                pfd.fileDescriptor.sync()
            } catch (e: SyncFailedException) {
                // Pipe-backed providers cannot sync; they commit on close.
            }
        }
    }

    /**
     * Finish writes interrupted between deleting the original and renaming
     * the temp over it ([writeFile]): a temp whose original is missing holds
     * the complete new content. A temp next to its original is garbage.
     * [names] maps each child name of the directory to its document id.
     */
    private fun recoverTempFiles(treeUri: Uri, names: Map<String, String>): List<String> {
        val recovered = mutableListOf<String>()
        for ((childName, docId) in names) {
            val original = originalNameFor(childName) ?: continue
            if (names.containsKey(original)) {
                deleteQuietly(treeUri, docId)
                continue
            }
            val tempUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
            try {
                DocumentsContract.renameDocument(activity.contentResolver, tempUri, original)
                Log.w(TAG, "Recovered $original from an interrupted write")
                recovered.add(original)
            } catch (e: Exception) {
                Log.e(TAG, "Could not recover $original from $childName", e)
            }
        }
        return recovered
    }

    private fun tempNameFor(name: String) = ".$name$TEMP_SUFFIX"

    private fun originalNameFor(tempName: String): String? =
        if (tempName.startsWith('.') && tempName.endsWith(TEMP_SUFFIX))
            tempName.substring(1, tempName.length - TEMP_SUFFIX.length)
        else null

    private fun documentFlags(docUri: Uri): Int =
        activity.contentResolver.query(
            docUri, arrayOf(DocumentsContract.Document.COLUMN_FLAGS), null, null, null
        )?.use { c -> if (c.moveToFirst()) c.getInt(0) else 0 } ?: 0

    private fun createQuietly(parentUri: Uri, name: String): Uri? =
        try {
            DocumentsContract.createDocument(activity.contentResolver, parentUri, TEMP_MIME, name)
        } catch (e: Exception) {
            Log.w(TAG, "Cannot create temp document $name, writing in place", e)
            null
        }

    private fun deleteQuietly(treeUri: Uri, docId: String) =
        deleteQuietly(DocumentsContract.buildDocumentUriUsingTree(treeUri, docId))

    private fun deleteQuietly(docUri: Uri) {
        try {
            DocumentsContract.deleteDocument(activity.contentResolver, docUri)
        } catch (e: Exception) {
            Log.w(TAG, "Could not delete $docUri", e)
        }
    }

    private fun deleteFile(treeUri: Uri, relPath: String) {
        val docUri = resolveFileUri(treeUri, relPath) ?: return
        DocumentsContract.deleteDocument(activity.contentResolver, docUri)
    }

    private fun statFile(treeUri: Uri, relPath: String): Map<String, Any?>? {
        val (parentRel, name) = splitParent(relPath)
        val parentId = resolveDirId(treeUri, parentRel, create = false) ?: return null
        val child = findChild(treeUri, parentId, name) ?: return null
        return mapOf("mtime" to child.mtime)
    }

    private fun renameFile(treeUri: Uri, fromRelPath: String, toRelPath: String) {
        val (fromParent, _) = splitParent(fromRelPath)
        val (toParent, toName) = splitParent(toRelPath)
        val fromUri = resolveFileUri(treeUri, fromRelPath)
            ?: throw FileNotFoundException(fromRelPath)

        if (fromParent == toParent) {
            DocumentsContract.renameDocument(activity.contentResolver, fromUri, toName)
                ?: throw IllegalStateException("Rename failed for $fromRelPath")
        } else {
            // Cross-directory move: copy + delete (moveDocument support is
            // provider-dependent, copy is universal).
            val content = readFile(treeUri, fromRelPath)
                ?: throw FileNotFoundException(fromRelPath)
            writeFile(treeUri, toRelPath, content)
            deleteFile(treeUri, fromRelPath)
        }
    }

    // --- path resolution --------------------------------------------------

    private data class ChildDoc(val docId: String, val mime: String, val mtime: Long)

    private fun resolveFileUri(treeUri: Uri, relPath: String): Uri? {
        val (parentRel, name) = splitParent(relPath)
        val parentId = resolveDirId(treeUri, parentRel, create = false) ?: return null
        val child = findChild(treeUri, parentId, name) ?: return null
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, child.docId)
    }

    /**
     * Resolve the document ID of [relDir] under [treeUri], walking segment by
     * segment. With [create], missing directories are created on the way.
     */
    private fun resolveDirId(treeUri: Uri, relDir: String, create: Boolean): String? {
        val clean = relDir.trim('/')
        val cacheKey = "$treeUri|$clean"
        dirIdCache[cacheKey]?.let { return it }

        var currentId = DocumentsContract.getTreeDocumentId(treeUri)
        if (clean.isNotEmpty()) {
            for (segment in clean.split('/')) {
                val child = findChild(treeUri, currentId, segment)
                currentId = when {
                    child != null && child.mime == DIR_MIME -> child.docId
                    child != null -> return null // a file blocks the path
                    create -> {
                        val parentUri =
                            DocumentsContract.buildDocumentUriUsingTree(treeUri, currentId)
                        val created = DocumentsContract.createDocument(
                            activity.contentResolver, parentUri, DIR_MIME, segment
                        ) ?: return null
                        DocumentsContract.getDocumentId(created)
                    }
                    else -> return null
                }
            }
        }
        dirIdCache[cacheKey] = currentId
        return currentId
    }

    /** One children query for several names (missing ones are absent). */
    private fun findChildren(
        treeUri: Uri,
        parentDocId: String,
        names: Set<String>
    ): Map<String, ChildDoc> {
        val found = HashMap<String, ChildDoc>()
        queryChildren(treeUri, parentDocId) { c ->
            val childName = c.getString(1)
            if (childName in names) {
                found[childName] = ChildDoc(c.getString(0), c.getString(2) ?: "", c.getLong(3))
            }
        }
        return found
    }

    private fun findChild(treeUri: Uri, parentDocId: String, name: String): ChildDoc? {
        var found: ChildDoc? = null
        queryChildren(treeUri, parentDocId) { c ->
            if (found == null && c.getString(1) == name) {
                found = ChildDoc(c.getString(0), c.getString(2) ?: "", c.getLong(3))
            }
        }
        return found
    }

    private inline fun queryChildren(
        treeUri: Uri,
        parentDocId: String,
        onRow: (Cursor) -> Unit
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri, parentDocId
        )
        activity.contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED
            ),
            null, null, null
        )?.use { cursor ->
            while (cursor.moveToNext()) onRow(cursor)
        }
    }

    private fun splitParent(relPath: String): Pair<String, String> {
        val clean = relPath.trim('/')
        val idx = clean.lastIndexOf('/')
        return if (idx < 0) Pair("", clean)
        else Pair(clean.substring(0, idx), clean.substring(idx + 1))
    }

    private fun mimeFor(name: String): String =
        if (name.endsWith(".md")) "text/markdown"
        else if (name.endsWith(".json")) "application/json"
        else "application/octet-stream"

    // --- threading ---------------------------------------------------------

    private fun <T> runInBackground(result: MethodChannel.Result, block: () -> T) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                Log.e(TAG, "SAF operation failed", e)
                // On any structural failure, drop the directory-id cache: the
                // tree may have been reorganised by another app (Syncthing).
                dirIdCache.clear()
                mainHandler.post { result.error("SAF_ERROR", e.message, null) }
            }
        }
    }
}
