import 'package:flutter_test/flutter_test.dart';
import 'package:jobfilter/domain/parsers/uber_job_parser.dart';

void main() {
  const parser = UberJobParser();

  group('fare/distance variations (spec section 8/38)', () {
    test('£12.50 / 5.2 miles', () {
      final result = parser.parse('Trip request\nFare £12.50\n5.2 miles\nAccept');
      expect(result.fare, 12.50);
      expect(result.tripDistanceMiles, closeTo(5.2, 0.001));
    });

    test('£12.50 / 5.2 mi (abbreviated unit)', () {
      final result = parser.parse('Fare £12.50\nTrip 5.2 mi\nAccept');
      expect(result.fare, 12.50);
      expect(result.tripDistanceMiles, closeTo(5.2, 0.001));
    });

    test('12.50 GBP / 8.4 km converts km to miles', () {
      final result = parser.parse('New trip\n12.50 GBP\nTrip 8.4 km\nAccept');
      expect(result.fare, 12.50);
      expect(result.tripDistanceMiles, closeTo(8.4 * 0.621371, 0.001));
    });

    test('£12 with no decimal places', () {
      final result = parser.parse('Fare £12\nTrip 5 miles\nAccept');
      expect(result.fare, 12.0);
    });

    test('comma as decimal separator (£12,50)', () {
      final result = parser.parse('Fare £12,50\nTrip 5 miles\nAccept');
      expect(result.fare, 12.50);
    });
  });

  group('pickup vs. trip distance disambiguation (spec section 38)', () {
    test('does not confuse a labeled pickup distance with the trip distance', () {
      final result = parser.parse('Fare £15\nPickup 1.8 mi\nTrip 6.4 mi\nAccept');
      expect(result.fare, 15.0);
      expect(result.pickupDistanceMiles, closeTo(1.8, 0.001));
      expect(result.tripDistanceMiles, closeTo(6.4, 0.001));
    });

    test('a single unlabeled distance is treated as the trip distance', () {
      final result = parser.parse('Fare £12.50\n5.2 miles\nAccept');
      expect(result.tripDistanceMiles, closeTo(5.2, 0.001));
      expect(result.pickupDistanceMiles, isNull);
    });
  });

  group('duration extraction', () {
    test('extracts minutes from "18 min" style text', () {
      final result = parser.parse('Fare £12.50\nTrip 5.2 mi\n18 min\nAccept');
      expect(result.estimatedDurationMinutes, 18);
    });
  });

  group('safety: never guess (spec section 8)', () {
    test('fare is null when no currency-marked amount is present', () {
      final result = parser.parse('Trip 5.2 miles to destination\nAccept');
      expect(result.fare, isNull);
    });

    test('job card not detected on an unrelated screen', () {
      final result = parser.parse("You're offline. Go online to start driving.");
      expect(result.jobCardDetected, isFalse);
    });
  });
}
