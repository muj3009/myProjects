import 'package:flutter_test/flutter_test.dart';
import 'package:jobfilter/domain/parsers/bolt_job_parser.dart';

void main() {
  const parser = BoltJobParser();

  test('parses fare and trip distance from a typical Bolt order card', () {
    final result = parser.parse('New order\nFare £9.80\nRide 4.1 mi\nAccept');
    expect(result.length, 1);
    final card = result.single;
    expect(card.fare, 9.80);
    expect(card.tripDistanceMiles, closeTo(4.1, 0.001));
    expect(card.jobCardDetected, isTrue);
  });

  test('distinguishes pickup from trip distance using Bolt-specific keywords', () {
    final result = parser.parse('Fare £11\nPickup 0.9 mi\nTrip 5.0 mi\nAccept');
    final card = result.single;
    expect(card.pickupDistanceMiles, closeTo(0.9, 0.001));
    expect(card.tripDistanceMiles, closeTo(5.0, 0.001));
  });

  test('does not detect a job card on the idle/waiting screen', () {
    final result = parser.parse("You're offline. Go online to start driving.");
    final card = result.single;
    expect(card.jobCardDetected, isFalse);
    expect(card.fare, isNull);
  });

  test('does not detect the daily earnings "£X.XX Today" summary as a job', () {
    var result = parser.parse('£0.00 Today\nAvailable trips');
    expect(result.single.jobCardDetected, isFalse);

    result = parser.parse('£44.00 Today\nAvailable trips\nRide 2.0 mi');
    expect(result.single.jobCardDetected, isFalse);
  });

  test('does not drop a genuine card swept alongside the earnings summary', () {
    // When the persistent summary and a real card share one (no-split)
    // segment, the card must still be detected — the exclusion only fires
    // when the summary is the segment's sole fare.
    final result =
        parser.parse('£44.00 Today\nFare £9.80\nRide 4.1 mi\nAccept');
    expect(result.single.jobCardDetected, isTrue);
  });
}
