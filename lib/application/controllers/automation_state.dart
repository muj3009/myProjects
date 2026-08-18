import 'package:equatable/equatable.dart';

import '../../domain/entities/rule_evaluation.dart';
import '../../domain/entities/taxi_job.dart';

/// Diagnostic snapshot for the Developer Debug screen (spec section 34).
/// Never shown in production builds beyond what's safe — see
/// presentation/screens/debug for the kDebugMode gate.
class AutomationDebugInfo extends Equatable {
  const AutomationDebugInfo({
    this.accessibilityConnected = false,
    this.foregroundPackage,
    this.lastDetectedText,
    this.parserUsed,
    this.confidencePercent,
    this.lastAction,
  });

  final bool accessibilityConnected;
  final String? foregroundPackage;
  final String? lastDetectedText;
  final String? parserUsed;
  final double? confidencePercent;
  final String? lastAction;

  AutomationDebugInfo copyWith({
    bool? accessibilityConnected,
    String? foregroundPackage,
    String? lastDetectedText,
    String? parserUsed,
    double? confidencePercent,
    String? lastAction,
  }) {
    return AutomationDebugInfo(
      accessibilityConnected: accessibilityConnected ?? this.accessibilityConnected,
      foregroundPackage: foregroundPackage ?? this.foregroundPackage,
      lastDetectedText: lastDetectedText ?? this.lastDetectedText,
      parserUsed: parserUsed ?? this.parserUsed,
      confidencePercent: confidencePercent ?? this.confidencePercent,
      lastAction: lastAction ?? this.lastAction,
    );
  }

  @override
  List<Object?> get props => [
        accessibilityConnected,
        foregroundPackage,
        lastDetectedText,
        parserUsed,
        confidencePercent,
        lastAction,
      ];
}

/// Live state shown on the Dashboard/Live Monitor screens (spec sections
/// 4/23). Session counters (jobsProcessed/accepted/rejected) reset each time
/// automation starts; the Statistics screen reads persisted history instead,
/// so a restart never loses historical figures.
class AutomationState extends Equatable {
  const AutomationState({
    this.isActive = false,
    this.jobsProcessed = 0,
    this.accepted = 0,
    this.rejected = 0,
    this.lastJob,
    this.lastEvaluations = const [],
    this.statusMessage = 'Automation is off',
    this.debug = const AutomationDebugInfo(),
    this.unsupportedReason,
  });

  final bool isActive;
  final int jobsProcessed;
  final int accepted;
  final int rejected;
  final TaxiJob? lastJob;
  final List<RuleEvaluation> lastEvaluations;
  final String statusMessage;
  final AutomationDebugInfo debug;

  /// Non-null when this platform/build cannot run automation at all (e.g.
  /// iOS) — the dashboard uses this to show an explanatory message instead
  /// of a non-functional toggle (spec section 48).
  final String? unsupportedReason;

  bool get isSupported => unsupportedReason == null;

  AutomationState copyWith({
    bool? isActive,
    int? jobsProcessed,
    int? accepted,
    int? rejected,
    TaxiJob? lastJob,
    List<RuleEvaluation>? lastEvaluations,
    String? statusMessage,
    AutomationDebugInfo? debug,
    String? unsupportedReason,
  }) {
    return AutomationState(
      isActive: isActive ?? this.isActive,
      jobsProcessed: jobsProcessed ?? this.jobsProcessed,
      accepted: accepted ?? this.accepted,
      rejected: rejected ?? this.rejected,
      lastJob: lastJob ?? this.lastJob,
      lastEvaluations: lastEvaluations ?? this.lastEvaluations,
      statusMessage: statusMessage ?? this.statusMessage,
      debug: debug ?? this.debug,
      unsupportedReason: unsupportedReason ?? this.unsupportedReason,
    );
  }

  @override
  List<Object?> get props => [
        isActive,
        jobsProcessed,
        accepted,
        rejected,
        lastJob,
        lastEvaluations,
        statusMessage,
        debug,
        unsupportedReason,
      ];
}
