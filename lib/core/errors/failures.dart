/// Base type for recoverable, expected failures surfaced to callers instead of
/// thrown exceptions. Automation and parsing code must never let an unexpected
/// exception crash the app — see docs/architecture.md "Error handling".
sealed class Failure {
  const Failure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class ParsingFailure extends Failure {
  const ParsingFailure(super.message);
}

class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

class AutomationFailure extends Failure {
  const AutomationFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}
