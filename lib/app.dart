import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/state/settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'presentation/navigation/root_navigation.dart';

class JobFilterApp extends ConsumerWidget {
  const JobFilterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appName = ref.watch(settingsControllerProvider).appName;

    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const RootNavigation(),
    );
  }
}
