import '../enums/platform_type.dart';
import 'parsed_job_data.dart';

/// Common contract implemented by [UberJobParser] and [BoltJobParser] (spec
/// section 8). Uber and Bolt do NOT display job information identically, so
/// each platform gets its own adapter rather than one shared regex set —
/// see docs/parser-design.md.
abstract interface class JobParser {
  PlatformType get platform;

  /// Parses whatever text the active [ScreenTextProvider] extracted from the
  /// driver app's visible UI. A single screen can show more than one
  /// simultaneous offer (e.g. Bolt's "Available trips" list) — each is
  /// returned as its own [ParsedJobData] so the caller can evaluate and act
  /// on them independently, rather than conflating multiple offers into one.
  /// Must never throw on malformed input — return nulls for anything a card
  /// couldn't reliably determine.
  List<ParsedJobData> parse(String rawText);
}
