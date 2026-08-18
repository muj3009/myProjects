import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../application/state/providers.dart';
import '../../../application/state/settings_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/rule_evaluation.dart';
import '../../../domain/entities/taxi_job.dart';
import '../../../domain/enums/job_decision.dart';
import '../../../domain/enums/platform_type.dart';
import '../../../domain/enums/rule_result.dart';
import '../../widgets/decision_badge.dart';
import '../../widgets/section_card.dart';

/// Simulation / Test Mode (spec section 33). Does NOT touch Uber/Bolt or any
/// platform channel — it runs a manually entered job straight through the
/// same [JobDecisionEngine] automation uses, so the rule engine can be
/// verified without a live driver-app session.
class SimulationScreen extends ConsumerStatefulWidget {
  const SimulationScreen({super.key});

  @override
  ConsumerState<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends ConsumerState<SimulationScreen> {
  final _fareController = TextEditingController();
  final _tripController = TextEditingController();
  final _pickupController = TextEditingController();
  final _durationController = TextEditingController();
  final _postcodeController = TextEditingController();
  PlatformType _platform = PlatformType.uber;
  DecisionOutcome? _outcome;
  TaxiJob? _job;

  @override
  void dispose() {
    _fareController.dispose();
    _tripController.dispose();
    _pickupController.dispose();
    _durationController.dispose();
    _postcodeController.dispose();
    super.dispose();
  }

  void _runTest() {
    final fare = double.tryParse(_fareController.text);
    final trip = double.tryParse(_tripController.text);
    final pickup = double.tryParse(_pickupController.text);
    final duration = int.tryParse(_durationController.text);
    final postcodeRaw = _postcodeController.text.trim();
    final postcode = postcodeRaw.isEmpty ? null : postcodeRaw.toUpperCase();

    final job = TaxiJob(
      id: const Uuid().v4(),
      platform: _platform,
      detectedAt: DateTime.now(),
      decision: JobDecision.pending,
      fare: fare,
      tripDistanceMiles: trip,
      pickupDistanceMiles: pickup,
      estimatedDurationMinutes: duration,
      destinationPostcode: postcode,
      isSimulated: true,
    );

    final settings = ref.read(settingsControllerProvider);
    final engine = ref.read(decisionEngineProvider);
    final outcome = engine.evaluate(job, settings);

    setState(() {
      _job = job.copyWith(
        decision: outcome.decision,
        poundsPerMile: outcome.poundsPerMile,
        estimatedHourlyRate: outcome.estimatedHourlyRate,
        decisionReason: outcome.reason,
      );
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simulation Mode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Enter a hypothetical job to see exactly how the rule engine would decide it. '
            'Nothing here interacts with Uber or Bolt.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              children: [
                SegmentedButton<PlatformType>(
                  segments: const [
                    ButtonSegment(
                        value: PlatformType.uber, label: Text('Uber')),
                    ButtonSegment(
                        value: PlatformType.bolt, label: Text('Bolt')),
                  ],
                  selected: {_platform},
                  onSelectionChanged: (s) =>
                      setState(() => _platform = s.first),
                ),
                const SizedBox(height: 16),
                _NumberField(label: 'Fare (£)', controller: _fareController),
                const SizedBox(height: 12),
                _NumberField(
                    label: 'Trip distance (miles)',
                    controller: _tripController),
                const SizedBox(height: 12),
                _NumberField(
                    label: 'Pickup distance (miles)',
                    controller: _pickupController),
                const SizedBox(height: 12),
                _NumberField(
                  label: 'Duration (minutes)',
                  controller: _durationController,
                  isInteger: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _postcodeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Destination postcode area (optional, e.g. LE4)',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      onPressed: _runTest, child: const Text('TEST JOB')),
                ),
              ],
            ),
          ),
          if (_outcome != null && _job != null) ...[
            const SizedBox(height: 24),
            _ResultCard(job: _job!, outcome: _outcome!),
          ],
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField(
      {required this.label, required this.controller, this.isInteger = false});

  final String label;
  final TextEditingController controller;
  final bool isInteger;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: !isInteger),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.job, required this.outcome});

  final TaxiJob job;
  final DecisionOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RESULT',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: onSurfaceVariant, letterSpacing: 1.2),
              ),
              DecisionBadge(decision: job.decision),
            ],
          ),
          if (outcome.poundsPerMile != null) ...[
            const SizedBox(height: 8),
            Text(
              '£${outcome.poundsPerMile!.toStringAsFixed(2)}/mile',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
          if (outcome.estimatedHourlyRate != null)
            Text(
              '£${outcome.estimatedHourlyRate!.toStringAsFixed(2)}/hour estimated',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: onSurfaceVariant),
            ),
          if (job.decisionReason != null) ...[
            const SizedBox(height: 8),
            Text(job.decisionReason!,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          Divider(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.6)),
          const SizedBox(height: 8),
          Text(
            'RULE-BY-RULE',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: onSurfaceVariant, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          for (final evaluation in outcome.evaluations)
            _RuleResultRow(evaluation: evaluation),
        ],
      ),
    );
  }
}

class _RuleResultRow extends StatelessWidget {
  const _RuleResultRow({required this.evaluation});

  final RuleEvaluation evaluation;

  @override
  Widget build(BuildContext context) {
    final label = switch (evaluation.result) {
      RuleResult.pass => 'PASS',
      RuleResult.fail => 'FAIL',
      RuleResult.unknown => 'UNKNOWN',
    };
    final color = switch (evaluation.result) {
      RuleResult.pass => StatusColors.accepted,
      RuleResult.fail => StatusColors.rejected,
      RuleResult.unknown => StatusColors.pendingOrUnknown,
    };
    final icon = switch (evaluation.result) {
      RuleResult.pass => Icons.check_circle,
      RuleResult.fail => Icons.cancel,
      RuleResult.unknown => Icons.help,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(evaluation.ruleName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (evaluation.detail != null)
                  Text(
                    evaluation.detail!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}
