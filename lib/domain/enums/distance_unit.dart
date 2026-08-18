/// Driver-facing display unit (spec section 43). Internally, every distance is
/// normalized to and stored as miles; this only controls presentation.
enum DistanceUnit { miles, kilometres }

/// Which distance figure feeds the £/mile calculation (spec section 12 — "dead miles").
enum DistanceCalculationMode {
  /// Passenger-carrying distance only (fare / tripDistanceMiles). Default.
  tripDistance,

  /// Pickup + trip distance, i.e. total driving for the job
  /// (fare / (pickupDistanceMiles + tripDistanceMiles)).
  totalDrivingDistance,
}
