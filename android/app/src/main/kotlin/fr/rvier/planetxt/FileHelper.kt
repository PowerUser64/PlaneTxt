package fr.rvier.planetxt

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Log
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

object FileHelper {
    private const val TAG = "FileHelper"
    private const val SHARED_PREFERENCES_NAME = "group.fr.rvier.planetxt"
    private const val FLUTTER_SHARED_PREFERENCES_NAME = "FlutterSharedPreferences"
    private const val FLUTTER_KEY_PREFIX = "flutter."
    private const val STORAGE_PATH_KEY = "storage_path"
    private const val STORAGE_TREE_URI_KEY = "storage_tree_uri"
    private const val DAILY_PATH_FORMAT_KEY = "daily_path_format"
    private const val DEFAULT_DAILY_PATH_FORMAT = "dailies/%Y%m%d.md"
    private const val ORG_DIR_NAME = "Org"
    private const val WIDGET_DAILY_CONTENT_KEY = "widget_daily_content"
    private const val WIDGET_DATE_KEY = "widget_date"

    /**
     * SAF document-tree URI of the user-selected storage folder, if any.
     * Only returned when the app still holds a persisted read grant for it.
     */
    fun getStorageTreeUri(context: Context): Uri? {
        val widgetPrefs = HomeWidgetPlugin.getData(context)
        var uriString = widgetPrefs.getString(STORAGE_TREE_URI_KEY, null)
        if (uriString.isNullOrEmpty()) {
            val flutterPrefs = context.getSharedPreferences(
                FLUTTER_SHARED_PREFERENCES_NAME,
                Context.MODE_PRIVATE
            )
            uriString = flutterPrefs.getString(
                "${FLUTTER_KEY_PREFIX}$STORAGE_TREE_URI_KEY", null
            ) ?: flutterPrefs.getString(STORAGE_TREE_URI_KEY, null)
        }
        if (uriString.isNullOrEmpty()) return null

        val uri = Uri.parse(uriString)
        val granted = context.contentResolver.persistedUriPermissions
            .any { it.uri == uri && it.isReadPermission }
        if (!granted) {
            Log.w(TAG, "No persisted grant for tree $uri")
            return null
        }
        return uri
    }

    /**
     * Read today's note from a SAF tree, using the configured daily file
     * layout (e.g. `dailies/<date>.md`, or `cal/%Y/%m/%d/daily.md`). Returns
     * null when the file doesn't exist or can't be read.
     */
    fun readDailyContentFromTree(context: Context, treeUri: Uri, date: String): String? {
        return try {
            val relPath = applyDailyPathFormat(getDailyPathFormat(context), date)
            val parts = relPath.split('/')
            if (parts.isEmpty()) return null
            val fileName = parts.last()
            val dirParts = parts.dropLast(1)

            var dirId = DocumentsContract.getTreeDocumentId(treeUri)
            for (segment in dirParts) {
                dirId = findChildDocumentId(context, treeUri, dirId, segment)
                    ?: return null
            }
            // When the directory carries the date tokens, every .md note in
            // that day's directory is a daily note: resolve the actual file
            // (preferring the configured name). Otherwise read the literal
            // path built from the file name setting.
            val fileId = if (directoryHasDate(getDailyPathFormat(context))) {
                findAnyMarkdownChild(context, treeUri, dirId, fileName)
            } else {
                findChildDocumentId(context, treeUri, dirId, fileName)
            } ?: return null
            val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, fileId)
            context.contentResolver.openInputStream(docUri)?.use { input ->
                BufferedReader(InputStreamReader(input)).readText()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error reading daily file from SAF tree", e)
            null
        }
    }

    private fun findChildDocumentId(
        context: Context,
        treeUri: Uri,
        parentDocId: String,
        name: String
    ): String? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri, parentDocId
        )
        context.contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            ),
            null, null, null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == name) return cursor.getString(0)
            }
        }
        return null
    }

    /**
     * Find any `.md` child of [parentDocId] (preferring [preferName]),
     * skipping conflict copies. Used when the directory carries the date
     * tokens: every `.md` note in that day's directory is a daily note.
     */
    private fun findAnyMarkdownChild(
        context: Context,
        treeUri: Uri,
        parentDocId: String,
        preferName: String
    ): String? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri, parentDocId
        )
        var preferred: String? = null
        var first: String? = null
        context.contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            ),
            null, null, null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(1) ?: continue
                if (!name.endsWith(".md") || name.contains(".sync-conflict-")) {
                    continue
                }
                val id = cursor.getString(0)
                if (first == null) first = id
                if (name == preferName) preferred = id
            }
        }
        return preferred ?: first
    }

    /**
     * Get the daily file layout format from SharedPreferences, or the
     * default (`dailies/%Y%m%d.md`).
     */
    fun getDailyPathFormat(context: Context): String {
        val widgetPrefs = HomeWidgetPlugin.getData(context)
        val widgetFormat = widgetPrefs.getString(DAILY_PATH_FORMAT_KEY, null)
        if (!widgetFormat.isNullOrEmpty()) {
            return widgetFormat
        }
        val flutterPrefs = context.getSharedPreferences(
            FLUTTER_SHARED_PREFERENCES_NAME,
            Context.MODE_PRIVATE
        )
        val format = flutterPrefs.getString(
            "${FLUTTER_KEY_PREFIX}$DAILY_PATH_FORMAT_KEY", null
        ) ?: flutterPrefs.getString(DAILY_PATH_FORMAT_KEY, null)
        if (!format.isNullOrEmpty()) return format

        val prefs = context.getSharedPreferences(
            SHARED_PREFERENCES_NAME,
            Context.MODE_PRIVATE
        )
        return prefs.getString(DAILY_PATH_FORMAT_KEY, null)
            ?: DEFAULT_DAILY_PATH_FORMAT
    }

    /**
     * Replace the date tokens (`%Y`, `%m`, `%d`) of a daily file layout format
     * with the components of a `yyyyMMdd` [date].
     */
    fun applyDailyPathFormat(format: String, date: String): String {
        if (date.length != 8) return format
        val year = date.substring(0, 4)
        val month = date.substring(4, 6)
        val day = date.substring(6, 8)
        return format
            .replace("%Y", year)
            .replace("%m", month)
            .replace("%d", day)
    }

    /**
     * Whether the directory part of the layout (everything before the last
     * `/`) carries a date token: each date then lives in its own directory,
     * so the widget must resolve the day's actual `.md` note.
     */
    private fun directoryHasDate(format: String): Boolean {
        val dir = format.substringBeforeLast('/')
        // No `/`: the layout has no directory part (a root file-name layout),
        // so the date lives in the file name and the literal path is used.
        if (dir == format) return false
        return dir.contains("%Y") || dir.contains("%m") || dir.contains("%d")
    }

    /**
     * Get storage path from SharedPreferences or default
     */
    fun getStoragePath(context: Context): String? {
        val widgetPrefs = HomeWidgetPlugin.getData(context)
        val widgetPath = widgetPrefs.getString(STORAGE_PATH_KEY, null)
        if (!widgetPath.isNullOrEmpty()) {
            val dir = File(widgetPath)
            if (dir.exists() && dir.isDirectory) {
                Log.d(TAG, "Using widget storage path: $widgetPath")
                return widgetPath
            }
            Log.w(TAG, "Widget storage path does not exist: $widgetPath")
        }

        val flutterPrefs = context.getSharedPreferences(
            FLUTTER_SHARED_PREFERENCES_NAME,
            Context.MODE_PRIVATE
        )
        val flutterPath = flutterPrefs.getString(
            "${FLUTTER_KEY_PREFIX}$STORAGE_PATH_KEY",
            null
        ) ?: flutterPrefs.getString(STORAGE_PATH_KEY, null)
        if (!flutterPath.isNullOrEmpty()) {
            val dir = File(flutterPath)
            if (dir.exists() && dir.isDirectory) {
                Log.d(TAG, "Using Flutter storage path: $flutterPath")
                return flutterPath
            }
            Log.w(TAG, "Flutter storage path does not exist: $flutterPath")
        }

        val prefs = context.getSharedPreferences(
            SHARED_PREFERENCES_NAME,
            Context.MODE_PRIVATE
        )
        val customPath = prefs.getString(STORAGE_PATH_KEY, null)
        
        if (!customPath.isNullOrEmpty()) {
            val dir = File(customPath)
            if (dir.exists() && dir.isDirectory) {
                Log.d(TAG, "Using custom storage path: $customPath")
                return customPath
            }
            Log.w(TAG, "Custom storage path does not exist: $customPath")
        }
        
        val defaultPath = getDefaultStoragePath(context)
        if (defaultPath.exists()) {
            Log.d(TAG, "Using default storage path: ${defaultPath.absolutePath}")
            return defaultPath.absolutePath
        }
        
        Log.e(TAG, "Storage path not configured")
        return null
    }

    /**
     * Default storage path: the app's own Org folder, where the Flutter side
     * puts it. path_provider's application documents directory is
     * getDir("flutter"), i.e. app_flutter/ - not filesDir/documents/.
     */
    fun getDefaultStoragePath(context: Context): File {
        return context.getDir("flutter", Context.MODE_PRIVATE).resolve(ORG_DIR_NAME)
    }

    /**
     * Read file content with error handling
     */
    fun readFile(path: File): String? {
        return try {
            if (!path.exists()) {
                Log.w(TAG, "File does not exist: ${path.absolutePath}")
                return null
            }
            
            val content = path.readText()
            Log.d(TAG, "Read file: ${path.absolutePath}, ${content.length} bytes")
            content
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission denied reading file: ${path.absolutePath}", e)
            null
        } catch (e: Exception) {
            Log.e(TAG, "Error reading file: ${path.absolutePath}", e)
            null
        }
    }

    /**
     * Check if file exists
     */
    fun fileExists(path: File): Boolean {
        return try {
            path.exists() && path.isFile
        } catch (e: Exception) {
            Log.e(TAG, "Error checking file existence: ${path.absolutePath}", e)
            false
        }
    }

    /**
     * Construct path to today's note file from the configured daily file
     * layout. When the directory carries the date tokens, every `.md` note
     * in that day's directory is a daily note: resolve the actual file
     * (preferring the configured name); otherwise the literal format path
     * built from the file name setting is used.
     */
    fun getDailyFilePath(context: Context, storagePath: String, date: String): File {
        val format = getDailyPathFormat(context)
        val relPath = applyDailyPathFormat(format, date)
        val literal = File(storagePath, relPath)

        if (directoryHasDate(format)) {
            val dir = File(storagePath, relPath.substringBeforeLast('/'))
            val files = dir.listFiles { f ->
                f.isFile && f.name.endsWith(".md") && !f.name.contains(".sync-conflict-")
            } ?: emptyArray()
            if (files.isNotEmpty()) {
                val daily = files.firstOrNull { it.name == relPath.substringAfterLast('/') }
                    ?: files.sortedBy { it.name }.first()
                return daily
            }
        }
        return literal
    }

    /**
     * Show error message on widget
     */
    fun showWidgetError(
        context: Context,
        message: String,
        triggerWidgetUpdate: Boolean = true
    ) {
        try {
            Log.w(TAG, "Showing widget error: $message")
            
            val prefs = HomeWidgetPlugin.getData(context)
            val todayDate = WidgetDataManager.getTodayDateString()
            prefs.edit()
                .putString(WIDGET_DAILY_CONTENT_KEY, message)
                .putString(WIDGET_DATE_KEY, todayDate)
                .apply()
            
            if (triggerWidgetUpdate) {
                // Trigger widget update to show error
                WidgetDataManager.triggerWidgetUpdate(context)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error showing widget error", e)
        }
    }

    fun clearWidgetContent(context: Context) {
        try {
            val prefs = HomeWidgetPlugin.getData(context)
            prefs.edit().remove(WIDGET_DAILY_CONTENT_KEY).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing widget content", e)
        }
    }
}
