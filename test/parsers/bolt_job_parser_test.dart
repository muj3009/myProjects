import 'package:flutter_test/flutter_test.dart';
import 'package:jobfilter/domain/parsers/bolt_job_parser.dart';

void main() {
  const parser = BoltJobParser();

  test('parses fare and trip distance from a typical Bolt order card', () {
    final result = parser.parse('New order\nFare £9.80\nRide 4.1 mi\nAccept');
    expect(result.fare, 9.80);
    expect(result.tripDistanceMiles, closeTo(4.1, 0.001));
    expect(result.jobCardDetected, isTrue);
  });

  test('distinguishes pickup from trip distance using Bolt-specific keywords', () {
    final result = parser.parse('Fare £11\nPickup 0.9 mi\nTrip 5.0 mi\nAccept');
    expect(result.pickupDistanceMiles, closeTo(0.9, 0.001));
    expect(result.tripDistanceMiles, closeTo(5.0, 0.001));
  });

  test('does not detect a job card on the idle/waiting screen', () {
    final result = parser.parse("You're offline. Go online to start driving.");
    expect(result.jobCardDetected, isFalse);
    expect(result.fare, isNull);
  });
}
