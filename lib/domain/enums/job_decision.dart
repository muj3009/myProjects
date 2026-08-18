/// Final outcome recorded for a job. `ignored` covers jobs seen but not from a
/// monitored platform; `pending` covers jobs mid-evaluation; `error` covers
/// jobs that failed to process safely (never treated as an accept).
enum JobDecision {
  accepted,
  rejected,
  ignored,
  error,
  pending,
  counterOffered,
}

extension JobDecisionX on JobDecision {
  bool get isFinal =>
      this == JobDecision.accepted || this == JobDecision.rejected || this == JobDecision.counterOffered;

  String get label => switch (this) {
        JobDecision.accepted => 'ACCEPTED',
        JobDecision.rejected => 'REJECTED',
        JobDecision.ignored => 'IGNORED',
        JobDecision.error => 'ERROR',
        JobDecision.pending => 'PENDING',
        JobDecision.counterOffered => 'COUNTER-OFFERED',
      };
}
