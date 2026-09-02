import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/state/settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'presentation/navigation/root_navigation.dart';

class JobFilterApp extends ConsumerWidget {
  const JobFilterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);

    return MaterialApp(
      title: settings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      home: const RootNavigation(),
    );
  }
}
