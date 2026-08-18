import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/sqflite_job_repository.dart';
import '../../data/repositories/sqflite_settings_repository.dart';
import '../../domain/enums/platform_type.dart';
import '../../domain/parsers/bolt_job_parser.dart';
import '../../domain/parsers/job_parser.dart';
import '../../domain/parsers/uber_job_parser.dart';
import '../../domain/repositories/job_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/services/job_decision_engine.dart';
import '../../domain/services/job_fingerprint_service.dart';
import '../../platform/automation/automation_method_channel.dart';
import '../../platform/automation/platform_action_executor.dart';
import '../../platform/automation/platform_action_executor_factory.dart';
import '../../platform/ocr/ocr_text_provider.dart';
import '../../platform/permissions/permission_status_service.dart';
import '../../platform/vision/uber_visual_understanding_engine.dart';

/// Composition root for dependencies shared across the app. Kept as plain
/// Riverpod [Provider]s (not autoDispose) so a single [JobFingerprintService]
/// and database connection live for the app's lifetime, per spec section 46's
/// layering — screens never construct repositories/services themselves.

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SqfliteSettingsRepository();
});

final jobRepositoryProvider = Provider<JobRepository>((ref) {
  return SqfliteJobRepository();
});

final decisionEngineProvider = Provider<JobDecisionEngine>((ref) {
  return JobDecisionEngine();
});

final fingerprintServiceProvider = Provider<JobFingerprintService>((ref) {
  return JobFingerprintService();
});

final platformActionExecutorProvider = Provider<PlatformActionExecutor>((ref) {
  return PlatformActionExecutorFactory.create();
});

final automationMethodChannelProvider = Provider<AutomationMethodChannel>((ref) {
  return AutomationMethodChannel();
});

final permissionStatusServiceProvider = Provider<PermissionStatusService>((ref) {
  return PermissionStatusService(channel: ref.watch(automationMethodChannelProvider));
});

final jobParsersProvider = Provider<Map<PlatformType, JobParser>>((ref) {
  return const {
    PlatformType.uber: UberJobParser(),
    PlatformType.bolt: BoltJobParser(),
  };
});

/// Uber's job-offer card is never exposed to the accessibility tree at all
/// (confirmed on a real device — only dashboard chrome ever comes through),
/// so OCR is the only way [AutomationController] can actually see it.
final ocrTextProviderProvider = Provider<OcrTextProvider>((ref) {
  return OcrTextProvider(channel: ref.watch(automationMethodChannelProvider));
});

/// Diagnostic-only for now (spec: production visual architecture, section
/// 26) — proves the visual pipeline can correctly read a live Uber offer
/// before anything is allowed to act on what it sees. Not read by
/// [AutomationController]'s live accept/reject loop yet.
final uberVisualUnderstandingEngineProvider = Provider<UberVisualUnderstandingEngine>((ref) {
  return UberVisualUnderstandingEngine();
});
