import 'dart:async';

import 'package:home_widget/home_widget.dart';
import 'package:planetxt/services/shared_prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';

import 'package:planetxt/constants/app_constants.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/services/widget_service.dart';
import 'package:planetxt/themes/app_themes.dart';
import 'package:planetxt/utils/logger.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  AppTheme _appTheme = AppTheme.gruvbox;
  String? _customStoragePath;
  String? _storageTreeUri;
  String? _storageTreeName;
  String _dailyTemplate = '';
  String _dailyPathDir = AppConstants.defaultDailyPathDir;
  String _dailyPathFileName = AppConstants.defaultDailyPathFileName;
  bool _widgetDarkTheme = false;
  double _widgetTransparency =
      1.0; // 1.0 = fully opaque, 0.0 = fully transparent
  double _widgetTextSize = 14.0;
  String _todoHeaderRegex = r'^#{1,2}\s+.*(Todos?|Tasks?)';
  String _eventHeaderRegex = r'^#{1,2}\s+.*Events?';
  String _logHeaderRegex = r'^#{1,2}\s+.*(Journal|Logs?)';
  static const String _themeKey = 'theme_mode';
  static const String _appThemeKey = 'app_theme';
  static const String _storagePathKey = 'storage_path';
  static const String _templateKey = 'daily_template';
  // Legacy keys used by older versions (kept for migration).
  // Older code incorrectly included the `flutter.` prefix, which ends up being
  // double-prefixed on Android (`flutter.flutter.*`).
  static const String _legacyWidgetThemeKey = 'flutter.widget_dark_theme';
  static const String _legacyWidgetTransparencyKey =
      'flutter.widget_transparency';
  static const String _todoHeaderRegexKey = 'todo_header_regex';
  static const String _eventHeaderRegexKey = 'event_header_regex';
  static const String _logHeaderRegexKey = 'log_header_regex';

  ThemeMode get themeMode => _themeMode;
  AppTheme get appTheme => _appTheme;
  String? get customStoragePath => _customStoragePath;
  String? get storageTreeUri => _storageTreeUri;
  String? get storageTreeName => _storageTreeName;
  String get dailyTemplate => _dailyTemplate;
  String get dailyPathDir => _dailyPathDir;
  String get dailyPathFileName => _dailyPathFileName;

  /// Combined `dir/file` layout, written to the Android widget data so the
  /// native widget can rebuild today's path without the app running.
  String get dailyPathFormat => _combinedDailyPathFormat();
  bool get widgetDarkTheme => _widgetDarkTheme;
  double get widgetTransparency => _widgetTransparency;
  double get widgetTextSize => _widgetTextSize;
  String get todoHeaderRegex => _todoHeaderRegex;
  String get eventHeaderRegex => _eventHeaderRegex;
  String get logHeaderRegex => _logHeaderRegex;

  bool get isInitialized => true;

  ThemeProvider() {
    Log.i('🚀 ThemeProvider: Constructor called');
    _initialize();
  }

  /// SharedPreferences is loaded before runApp (SharedPrefsService), so all
  /// values are available synchronously - no loading gate needed. Only the
  /// side effects (widget sync, legacy key migration) stay async.
  void _initialize() {
    final prefs = SharedPrefsService.instance;

    _themeMode = ThemeMode.values[prefs.getInt(_themeKey) ?? 0];
    _appTheme =
        AppTheme.values[prefs.getInt(_appThemeKey) ?? AppTheme.gruvbox.index];
    _customStoragePath = prefs.getString(_storagePathKey);
    _storageTreeUri = prefs.getString(AppConstants.storageTreeUriKey);
    _storageTreeName = prefs.getString(AppConstants.storageTreeNameKey);
    _dailyTemplate = prefs.getString(_templateKey) ?? _getDefaultTemplate();
    _loadDailyPathSettings(prefs);
    StorageService.applyDailyPathFormat(_dailyPathDir, _dailyPathFileName);
    _widgetDarkTheme = prefs.getBool(AppConstants.widgetThemeKey) ??
        prefs.getBool(_legacyWidgetThemeKey) ??
        false;
    _widgetTransparency = prefs.getDouble(AppConstants.widgetTransparencyKey) ??
        prefs.getDouble(_legacyWidgetTransparencyKey) ??
        1.0;
    _widgetTextSize =
        prefs.getDouble(AppConstants.widgetTextSizeKey) ?? _widgetTextSize;
    _todoHeaderRegex =
        prefs.getString(_todoHeaderRegexKey) ?? r'^#{1,2}\s+.*(Todos?|Tasks?)';
    _eventHeaderRegex =
        prefs.getString(_eventHeaderRegexKey) ?? r'^#{1,2}\s+.*Events?';
    _logHeaderRegex =
        prefs.getString(_logHeaderRegexKey) ?? r'^#{1,2}\s+.*(Journal|Logs?)';

    unawaited(_runInitSideEffects(prefs));
    Log.i('🚀 ThemeProvider: Initialization completed');
  }

  /// Load the daily file layout's two settings (directory + file name). On a
  /// first run after the old single-string layout, migrate it by splitting on
  /// the last `/` and dropping the `*` wildcard.
  void _loadDailyPathSettings(SharedPreferences prefs) {
    final dir = prefs.getString(AppConstants.dailyPathDirKey);
    final fileName = prefs.getString(AppConstants.dailyPathFileNameKey);
    if (dir != null && fileName != null) {
      _dailyPathDir = dir;
      _dailyPathFileName = fileName.isEmpty
          ? AppConstants.defaultDailyPathFileName
          : fileName;
      return;
    }

    final legacy = prefs.getString(AppConstants.dailyPathFormatKey);
    if (legacy != null && legacy.isNotEmpty) {
      final last = legacy.lastIndexOf('/');
      if (last == -1) {
        _dailyPathDir = '';
        _dailyPathFileName = _dropWildcard(legacy);
      } else {
        _dailyPathDir = legacy.substring(0, last);
        _dailyPathFileName = _dropWildcard(legacy.substring(last + 1));
      }
      _persistDailyPathSettings(prefs);
      return;
    }

    _dailyPathDir = AppConstants.defaultDailyPathDir;
    _dailyPathFileName = AppConstants.defaultDailyPathFileName;
  }

  /// The legacy `*` wildcard is dropped: new daily notes are named after the
  /// configured file name, and scanning already accepts every `.md` note in
  /// a day directory. The canonical create name is `daily`.
  String _dropWildcard(String value) => value.replaceAll('*', 'daily');

  void _persistDailyPathSettings(SharedPreferences prefs) {
    prefs.setString(AppConstants.dailyPathDirKey, _dailyPathDir);
    prefs.setString(AppConstants.dailyPathFileNameKey, _dailyPathFileName);
  }

  /// Combined `dir/file` layout for the Android widget.
  String _combinedDailyPathFormat() =>
      _dailyPathDir.isEmpty ? _dailyPathFileName : '$_dailyPathDir/$_dailyPathFileName';

  Future<void> _runInitSideEffects(SharedPreferences prefs) async {
    // Migrate legacy (double-prefixed) keys to their canonical names.
    if (prefs.getBool(AppConstants.widgetThemeKey) == null &&
        prefs.getBool(_legacyWidgetThemeKey) != null) {
      await prefs.setBool(AppConstants.widgetThemeKey, _widgetDarkTheme);
    }
    if (prefs.getDouble(AppConstants.widgetTransparencyKey) == null &&
        prefs.getDouble(_legacyWidgetTransparencyKey) != null) {
      await prefs.setDouble(
          AppConstants.widgetTransparencyKey, _widgetTransparency);
    }

    try {
      if (_customStoragePath != null && _customStoragePath!.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>(
          AppConstants.storagePathKey,
          _customStoragePath!,
        );
      }
      // The Android widget reads the SAF tree URI to fetch today's file.
      await HomeWidget.saveWidgetData<String>(
        AppConstants.storageTreeUriKey,
        _storageTreeUri ?? '',
      );
      // The widget also needs the daily file layout to build today's path
      // (written as a combined `dir/file` format).
      await HomeWidget.saveWidgetData<String>(
        AppConstants.dailyPathFormatKey,
        dailyPathFormat,
      );
    } catch (e, stackTrace) {
      Log.w('⚠️ ThemeProvider: Failed to sync widget storage config on load',
          error: e, stackTrace: stackTrace);
    }
  }

  String _getDefaultTemplate() {
    return '''# 📅 Events

# ✅ Todos

# 📝 Logs

# 🗒️ Notes
''';
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = SharedPrefsService.instance;
    await prefs.setInt(_themeKey, mode.index);
    notifyListeners();
  }

  Future<void> setAppTheme(AppTheme theme) async {
    _appTheme = theme;
    final prefs = SharedPrefsService.instance;
    await prefs.setInt(_appThemeKey, theme.index);
    notifyListeners();

    await WidgetService.updateWidgetColors();
  }

  /// Configure a raw filesystem custom path (desktop). Clears any SAF tree.
  Future<void> setStoragePath(String? path) async {
    Log.d('💾 ThemeProvider: Setting storage path to: $path');
    _customStoragePath = path;
    _storageTreeUri = null;
    _storageTreeName = null;
    final prefs = SharedPrefsService.instance;
    if (path != null) {
      await prefs.setString(_storagePathKey, path);
    } else {
      await prefs.remove(_storagePathKey);
    }
    await prefs.remove(AppConstants.storageTreeUriKey);
    await prefs.remove(AppConstants.storageTreeNameKey);
    await _syncWidgetStorageConfig();
    notifyListeners();
  }

  /// Configure an Android SAF document tree as storage root. Clears any raw
  /// custom path.
  Future<void> setStorageTree(String? treeUri, String? displayName) async {
    Log.d('💾 ThemeProvider: Setting storage tree to: $treeUri ($displayName)');
    _storageTreeUri = treeUri;
    _storageTreeName = displayName;
    _customStoragePath = null;
    final prefs = SharedPrefsService.instance;
    if (treeUri != null) {
      await prefs.setString(AppConstants.storageTreeUriKey, treeUri);
      await prefs.setString(
          AppConstants.storageTreeNameKey, displayName ?? treeUri);
    } else {
      await prefs.remove(AppConstants.storageTreeUriKey);
      await prefs.remove(AppConstants.storageTreeNameKey);
    }
    await prefs.remove(_storagePathKey);
    await _syncWidgetStorageConfig();
    notifyListeners();
  }

  Future<void> _syncWidgetStorageConfig() async {
    try {
      await HomeWidget.saveWidgetData<String>(
        AppConstants.storagePathKey,
        _customStoragePath ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        AppConstants.storageTreeUriKey,
        _storageTreeUri ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        AppConstants.dailyPathFormatKey,
        dailyPathFormat,
      );
    } catch (e, stackTrace) {
      Log.w('⚠️ ThemeProvider: Failed to sync widget storage config',
          error: e, stackTrace: stackTrace);
    }
  }

  Future<void> setDailyTemplate(String template) async {
    _dailyTemplate = template;
    final prefs = SharedPrefsService.instance;
    await prefs.setString(_templateKey, template);
    notifyListeners();
  }

  /// Configure the directory part of the daily file layout (see
  /// lib/utils/daily_path_format.dart): where each date's note lives,
  /// supporting date expansion (`%Y`, `%m`, `%d`). The caller should reload
  /// the daily files afterwards so the new layout takes effect.
  Future<void> setDailyPathDir(String dir) async {
    // An empty directory is a valid flat layout at the storage root; the
    // dialog still requires a date token in at least one of the two parts.
    _dailyPathDir = dir.trim();
    final prefs = SharedPrefsService.instance;
    await prefs.setString(AppConstants.dailyPathDirKey, _dailyPathDir);
    StorageService.applyDailyPathFormat(_dailyPathDir, _dailyPathFileName);
    await _syncWidgetStorageConfig();
    notifyListeners();
    Log.i('🚀 ThemeProvider: Daily path directory set to $_dailyPathDir');
  }

  /// Configure the file name part of the daily file layout (see
  /// lib/utils/daily_path_format.dart): the name new daily notes are created
  /// with, supporting date expansion (`%Y`, `%m`, `%d`). The caller should
  /// reload the daily files afterwards so the new layout takes effect.
  Future<void> setDailyPathFileName(String fileName) async {
    final trimmed = fileName.trim();
    _dailyPathFileName = trimmed.isEmpty
        ? AppConstants.defaultDailyPathFileName
        : trimmed;
    final prefs = SharedPrefsService.instance;
    await prefs.setString(
        AppConstants.dailyPathFileNameKey, _dailyPathFileName);
    StorageService.applyDailyPathFormat(_dailyPathDir, _dailyPathFileName);
    await _syncWidgetStorageConfig();
    notifyListeners();
    Log.i(
        '🚀 ThemeProvider: Daily path file name set to $_dailyPathFileName');
  }

  Future<void> setWidgetTheme(bool isDark) async {
    _widgetDarkTheme = isDark;
    final prefs = SharedPrefsService.instance;
    await prefs.setBool(AppConstants.widgetThemeKey, isDark);
    notifyListeners();

    // Update widget with new theme
    await _updateWidgetWithNewTheme(isDark);
  }

  Future<void> setWidgetTransparency(double transparency) async {
    _widgetTransparency = transparency.clamp(0.0, 1.0);
    final prefs = SharedPrefsService.instance;
    await prefs.setDouble(
        AppConstants.widgetTransparencyKey, _widgetTransparency);
    notifyListeners();

    // Update widget with new transparency
    await _updateWidgetWithNewTransparency(_widgetTransparency);
  }

  Future<void> setWidgetTextSize(double size) async {
    _widgetTextSize = size.clamp(10.0, 24.0);
    await SharedPrefsService.instance
        .setDouble(AppConstants.widgetTextSizeKey, _widgetTextSize);
    notifyListeners();
    await WidgetService.updateWidgetTextSize(_widgetTextSize);
  }

  Future<void> setTodoHeaderRegex(String regex) async {
    _todoHeaderRegex = regex;
    final prefs = SharedPrefsService.instance;
    await prefs.setString(_todoHeaderRegexKey, regex);
    notifyListeners();
  }

  Future<void> setEventHeaderRegex(String regex) async {
    _eventHeaderRegex = regex;
    final prefs = SharedPrefsService.instance;
    await prefs.setString(_eventHeaderRegexKey, regex);
    notifyListeners();
  }

  Future<void> setLogHeaderRegex(String regex) async {
    _logHeaderRegex = regex;
    final prefs = SharedPrefsService.instance;
    await prefs.setString(_logHeaderRegexKey, regex);
    notifyListeners();
  }

  String getDisplayStoragePath() {
    if (_storageTreeUri != null) {
      return _storageTreeName ?? _storageTreeUri!;
    }
    if (_customStoragePath != null) {
      return _customStoragePath!;
    }
    return 'Default (App Documents/Org)';
  }

  /// Kept for API compatibility - initialization is now synchronous.
  Future<void> waitForInitialization() async {}

  ThemeData get lightTheme {
    return AppThemes.getTheme(_appTheme).lightTheme;
  }

  ThemeData get darkTheme {
    return AppThemes.getTheme(_appTheme).darkTheme;
  }

  /// Update widget with new theme
  Future<void> _updateWidgetWithNewTheme(bool isDarkTheme) async {
    try {
      // We need to get the daily file content, but we don't have access to FileProvider here
      // So we'll just update the widget with the theme preference
      // The widget will use the existing content with the new theme
      await WidgetService.updateWidgetTheme(isDarkTheme);
    } catch (e) {
      Log.e('❌ ThemeProvider: Error updating widget with new theme', error: e);
    }
  }

  /// Update widget with new transparency
  Future<void> _updateWidgetWithNewTransparency(double transparency) async {
    try {
      // Update widget with new transparency
      await WidgetService.updateWidgetTransparency(transparency);
    } catch (e) {
      Log.e('❌ ThemeProvider: Error updating widget with new transparency',
          error: e);
    }
  }
}
