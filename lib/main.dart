import 'package:flutter/material.dart';
import 'package:planetxt/constants/app_constants.dart';
import 'package:planetxt/providers/directory_provider.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/providers/theme_provider.dart';
import 'package:planetxt/screens/main_screen.dart';
import 'package:planetxt/services/shared_prefs_service.dart';
import 'package:planetxt/services/widget_service.dart';
import 'package:planetxt/utils/daily_file_naming.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize shared preferences (must be first)
  await SharedPrefsService.initialize();

  // The days' file names, before anything reads or writes one.
  DailyFileNaming.useTemplate(SharedPrefsService.instance
      .getString(AppConstants.dailyFileNameTemplateKey));

  // Initialize widget service
  await WidgetService.initialize();

  // Notification service init + permission request happen after first
  // frame, in MainScreen's background startup tasks — they must not block
  // first paint.

  runApp(const PlaneTxtApp());
}

class PlaneTxtApp extends StatelessWidget {
  const PlaneTxtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => DirectoryProvider()),
        ChangeNotifierProvider(create: (_) => DailyFileProvider()),
        ChangeNotifierProvider(create: (_) => NoteFileProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'PlaneTxt',
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const MainScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
