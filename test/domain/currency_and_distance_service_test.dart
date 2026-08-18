import 'package:flutter_test/flutter_test.dart';
import 'package:jobfilter/domain/enums/distance_unit.dart';
import 'package:jobfilter/domain/services/currency_service.dart';
import 'package:jobfilter/domain/services/distance_conversion_service.dart';

void main() {
  group('CurrencyService', () {
    test('rounds to the nearest penny', () {
      expect(CurrencyService.roundToPence(2.4038461538), 2.40);
    });

    test('formats with the currency symbol', () {
      expect(CurrencyService.format(2.5), '£2.50');
    });
  });

  group('DistanceConversionService', () {
    test('converts kilometres to miles using the standard factor', () {
      expect(DistanceConversionService.kilometresToMiles(8.4), closeTo(5.2195, 0.001));
    });

    test('round-trips miles -> km -> miles', () {
      const miles = 10.0;
      final km = DistanceConversionService.milesToKilometres(miles);
      final backToMiles = DistanceConversionService.kilometresToMiles(km);
      expect(backToMiles, closeTo(miles, 0.0001));
    });

    test('displays in kilometres when the driver prefers km', () {
      final formatted = DistanceConversionService.formatDistance(1.0, DistanceUnit.kilometres);
      expect(formatted, contains('km'));
    });
  });
}
