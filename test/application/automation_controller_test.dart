import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobfilter/application/controllers/automation_controller.dart';
import 'package:jobfilter/application/state/providers.dart';
import 'package:jobfilter/core/utils/result.dart';
import 'package:jobfilter/domain/entities/driver_settings.dart';
import 'package:jobfilter/domain/entities/taxi_job.dart';
import 'package:jobfilter/domain/enums/job_decision.dart';
import 'package:jobfilter/domain/repositories/job_repository.dart';
import 'package:jobfilter/domain/repositories/settings_repository.dart';
import 'package:jobfilter/platform/accessibility/accessibility_status.dart';
import 'package:jobfilter/platform/automation/automation_method_channel.dart';
import 'package:jobfilter/platform/automation/platform_action_executor.dart';
import 'package:mocktail/mocktail.dart';

/// Spec section 39 — "Create mocked accessibility/UI data... Do NOT use a
/// real Uber/Bolt account during automated unit tests." This suite feeds
/// fabricated Accessibility Service text straight into
/// [AutomationController] and asserts on the resulting
/// parser -> decision engine -> [PlatformActionExecutor] call sequence,
/// with no platform channel or real database involved.

class MockAutomationMethodChannel extends Mock implements AutomationMethodChannel {}

class MockPlatformActionExecutor extends Mock implements PlatformActionExecutor {}

class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository(this._settings);
  DriverSettings _settings;

  @override
  Future<Result<DriverSettings>> load() async => Result.ok(_settings);

  @override
  Future<Result<void>> save(DriverSettings settings) async {
    _settings = settings;
    return const Result.ok(null);
  }
}

class InMemoryJobRepository implements JobRepository {
  final List<TaxiJob> saved = [];

  @override
  Future<Result<void>> save(TaxiJob job) async {
    saved.add(job);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<TaxiJob>>> getHistory({JobHistoryFilter filter = const JobHistoryFilter()}) async =>
      Result.ok(List.unmodifiable(saved));

  @override
  Future<Result<JobStatistics>> getStatistics({StatsRange range = StatsRange.today}) async =>
      const Result.ok(JobStatistics.empty);

  @override
  Future<Result<void>> clearHistory() async {
    saved.clear();
    return const Result.ok(null);
  }
}

Future<void> _settle() async {
  // Lets the chain of awaits inside AutomationController._handleDetectedText
  // (foreground package lookup -> parse -> decide -> act -> save) resolve.
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MockAutomationMethodChannel channel;
  late MockPlatformActionExecutor executor;
  late InMemoryJobRepository jobRepository;
  late StreamController<String> textEvents;
  late StreamController<void> controlEvents;
  late ProviderContainer container;

  setUp(() {
    channel = MockAutomationMethodChannel();
    executor = MockPlatformActionExecutor();
    jobRepository = InMemoryJobRepository();
    textEvents = StreamController<String>.broadcast();
    controlEvents = StreamController<void>.broadcast();

    when(() => channel.getAccessibilityStatus())
        .thenAnswer((_) async => AccessibilityStatus.enabled);
    when(() => channel.startForegroundMonitoring()).thenAnswer((_) async {});
    when(() => channel.stopForegroundMonitoring()).thenAnswer((_) async {});
    when(() => channel.detectedTextEvents()).thenAnswer((_) => textEvents.stream);
    when(() => channel.stopRequestedFromNotificationEvents()).thenAnswer((_) => controlEvents.stream);
    when(() => channel.getForegroundPackageName()).thenAnswer((_) async => 'com.ubercab.driver');

    when(() => executor.isAutomationSupportedOnThisPlatform).thenReturn(true);
    when(() => executor.canPerformActions()).thenAnswer((_) async => true);
    when(() => executor.acceptJob()).thenAnswer((_) async => const Result.ok(null));
    when(() => executor.rejectJob()).thenAnswer((_) async => const Result.ok(null));

    container = ProviderContainer(overrides: [
      automationMethodChannelProvider.overrideWithValue(channel),
      platformActionExecutorProvider.overrideWithValue(executor),
      jobRepositoryProvider.overrideWithValue(jobRepository),
      settingsRepositoryProvider.overrideWithValue(InMemorySettingsRepository(const DriverSettings())),
    ]);
  });

  tearDown(() {
    container.dispose();
    textEvents.close();
    controlEvents.close();
  });

  test('a job above the minimum £/mile is accepted and the executor is invoked', () async {
    final controller = container.read(automationControllerProvider.notifier);
    await controller.start();

    textEvents.add('Trip request\nFare £12.50\nTrip 5.2 miles\nAccept');
    await _settle();

    final state = container.read(automationControllerProvider);
    expect(state.jobsProcessed, 1);
    expect(state.accepted, 1);
    expect(jobRepository.saved.single.decision, JobDecision.accepted);
    verify(() => executor.acceptJob()).called(1);
    verifyNever(() => executor.rejectJob());
  });

  test('a job below the minimum £/mile is rejected and the executor is invoked', () async {
    final controller = container.read(automationControllerProvider.notifier);
    await controller.start();

    textEvents.add('Trip request\nFare £8.50\nTrip 6.0 miles\nAccept');
    await _settle();

    final state = container.read(automationControllerProvider);
    expect(state.rejected, 1);
    expect(jobRepository.saved.single.decision, JobDecision.rejected);
    verify(() => executor.rejectJob()).called(1);
    verifyNever(() => executor.acceptJob());
  });

  test('missing distance results in no action being taken (spec section 8/35)', () async {
    final controller = container.read(automationControllerProvider.notifier);
    await controller.start();

    textEvents.add('Trip request\nFare £12.50\nAccept');
    await _settle();

    final state = container.read(automationControllerProvider);
    expect(state.jobsProcessed, 1);
    expect(state.accepted, 0);
    expect(state.rejected, 0);
    expect(jobRepository.saved.single.decision, JobDecision.pending);
    verifyNever(() => executor.acceptJob());
    verifyNever(() => executor.rejectJob());
  });

  test('the same job detected twice is only processed once (spec section 18)', () async {
    final controller = container.read(automationControllerProvider.notifier);
    await controller.start();

    const text = 'Trip request\nFare £12.50\nTrip 5.2 miles\nAccept';
    textEvents.add(text);
    await _settle();
    textEvents.add(text);
    await _settle();

    final state = container.read(automationControllerProvider);
    expect(state.jobsProcessed, 1);
    verify(() => executor.acceptJob()).called(1);
  });

  test('emergency stop halts further processing immediately (spec section 19)', () async {
    final controller = container.read(automationControllerProvider.notifier);
    await controller.start();
    await controller.stop();

    textEvents.add('Trip request\nFare £12.50\nTrip 5.2 miles\nAccept');
    await _settle();

    final state = container.read(automationControllerProvider);
    expect(state.jobsProcessed, 0);
    expect(jobRepository.saved, isEmpty);
    verifyNever(() => executor.acceptJob());
  });

  test('does not start monitoring when the Accessibility Service is disabled', () async {
    when(() => channel.getAccessibilityStatus())
        .thenAnswer((_) async => AccessibilityStatus.disabled);

    final controller = container.read(automationControllerProvider.notifier);
    await controller.start();

    expect(container.read(automationControllerProvider).isActive, isFalse);
  });
}
