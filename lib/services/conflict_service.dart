import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/utils/conflict_files.dart';
import 'package:planetxt/utils/exceptions.dart';
import 'package:planetxt/utils/logger.dart';

/// What the user keeps of a file that was changed in two places at once.
enum ConflictChoice {
  /// Drop the copy, keep the file as it is now.
  keepCurrent,

  /// Make the copy the file, and drop the copy itself.
  keepCopy,

  /// Keep both, the copy becoming an ordinary file of its own.
  keepBoth,
}

/// The two versions of a file a sync tool could not merge.
class ConflictVersions {
  /// Store path of the copy the sync tool (or PlaneTxt) wrote aside.
  final String copyPath;

  /// Store path of the file the copy was made from.
  final String originalPath;

  /// Content of [originalPath], or null when that file is gone: a copy
  /// outlives what it was made from.
  final String? current;

  /// Content of [copyPath].
  final String copy;

  const ConflictVersions({
    required this.copyPath,
    required this.originalPath,
    required this.current,
    required this.copy,
  });

  /// The copy is all that is left of the file.
  bool get currentIsGone => current == null;

  /// The sync tool kept a copy of what turned out to be the same text.
  bool get versionsMatch => current == copy;
}

/// Reads and resolves the conflict copies [isConflictCopy] recognises.
///
/// Nothing here touches the repositories' caches: the caller reloads the
/// providers afterwards, which rescans the store and rebuilds the list of
/// copies left to resolve.
class ConflictService {
  final StorageService storageService;

  ConflictService([StorageService? storageService])
      : storageService = storageService ?? StorageService();

  /// Matches the copies PlaneTxt writes of a day under `notes/conflicts/`,
  /// whose name no longer says which file on disk they came from.
  static final RegExp _dailyCopyName = RegExp(r'^daily (\d{8})$');

  /// Both versions of the file [copyPath] is a second version of.
  Future<ConflictVersions> read(String copyPath) async {
    final store = storageService.store;
    if (store == null) {
      throw const FileOperationException('Storage is not ready');
    }
    final originalPath = await _originalOf(copyPath);
    final copy = await store.read(copyPath);
    if (copy == null) {
      throw FileOperationException('The copy is gone', filePath: copyPath);
    }
    return ConflictVersions(
      copyPath: copyPath,
      originalPath: originalPath,
      current: await store.read(originalPath),
      copy: copy,
    );
  }

  /// Apply [choice] to [versions]. Returns the path the copy's text ended up
  /// in, or null when it was dropped.
  Future<String?> resolve(ConflictVersions versions, ConflictChoice choice) async {
    final store = storageService.store;
    if (store == null) {
      throw const FileOperationException('Storage is not ready');
    }
    switch (choice) {
      case ConflictChoice.keepCurrent:
        await store.delete(versions.copyPath);
        Log.i('🔀 ConflictService: Dropped ${versions.copyPath}');
        return null;
      case ConflictChoice.keepCopy:
        // Written before the copy is dropped: an interrupted resolution
        // leaves the copy behind rather than losing its text.
        await store.write(versions.originalPath, versions.copy);
        await store.delete(versions.copyPath);
        Log.i('🔀 ConflictService: ${versions.copyPath} is now '
            '${versions.originalPath}');
        return versions.originalPath;
      case ConflictChoice.keepBoth:
        final kept = await _freePathFor(versions);
        // SAF renames into an existing folder only; `notes/conflicts` is
        // there on a copy PlaneTxt wrote, not on one a sync tool left.
        await store.ensureDirectory(kept.substring(0, kept.lastIndexOf('/')));
        await store.rename(versions.copyPath, kept);
        Log.i('🔀 ConflictService: ${versions.copyPath} kept as $kept');
        return kept;
    }
  }

  /// Store path of the file [copyPath] is a second version of. PlaneTxt's own
  /// copies of a day are named after the day rather than after its file, so
  /// the day's file is looked up when the name alone leads nowhere.
  Future<String> _originalOf(String copyPath) async {
    final named = originalPathOf(copyPath);
    if (named == null) {
      throw FileOperationException('Not a conflict copy', filePath: copyPath);
    }
    final store = storageService.store;
    if (store != null && !await store.exists(named)) {
      final day = _dailyCopyName.firstMatch(_baseName(named));
      if (day != null) return StorageService.dailyPath(day.group(1)!);
    }
    return named;
  }

  /// Where the copy goes when both versions are kept: beside the file it came
  /// from when that one is a note, else among the notes, where it can be read
  /// in the app. A day's file is named after its date, so a copy could not
  /// stay in `dailies/` without passing for another day.
  Future<String> _freePathFor(ConflictVersions versions) async {
    final store = storageService.store;
    final original = versions.originalPath;
    final inNotes = original.startsWith('${StorageService.notesDirName}/');
    final directory = inNotes
        ? original.substring(0, original.lastIndexOf('/'))
        : '${StorageService.notesDirName}/conflicts';
    final base = _baseName(original);
    for (var i = 1;; i++) {
      final suffix = i == 1 ? ' (copy)' : ' (copy $i)';
      final candidate = '$directory/$base$suffix.md';
      if (store == null || !await store.exists(candidate)) return candidate;
    }
  }

  /// File name of [relPath], without its extension.
  String _baseName(String relPath) {
    final name = relPath.substring(relPath.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
