import 'package:flutter_test/flutter_test.dart';
import 'package:jobfilter/domain/parsers/parsed_text_utils.dart';

void main() {
  group('extractFare', () {
    test('£ prefixed with decimals', () => expect(ParsedTextUtils.extractFare('£12.50'), 12.50));
    test('£ prefixed, whole number', () => expect(ParsedTextUtils.extractFare('£12'), 12.0));
    test('comma decimal separator', () => expect(ParsedTextUtils.extractFare('£12,50'), 12.50));
    test('GBP suffix', () => expect(ParsedTextUtils.extractFare('12.50 GBP'), 12.50));
    test('GBP prefix', () => expect(ParsedTextUtils.extractFare('GBP 12.50'), 12.50));
    test('no currency marker returns null (never guess)',
        () => expect(ParsedTextUtils.extractFare('12.50'), isNull));
  });

  group('extractAllDistances', () {
    test('miles token', () {
      final matches = ParsedTextUtils.extractAllDistances('5.2 miles');
      expect(matches, hasLength(1));
      expect(matches.first.miles, closeTo(5.2, 0.001));
    });

    test('mi abbreviation', () {
      final matches = ParsedTextUtils.extractAllDistances('5.2 mi');
      expect(matches.first.miles, closeTo(5.2, 0.001));
    });

    test('whole-number miles', () {
      final matches = ParsedTextUtils.extractAllDistances('5 miles');
      expect(matches.first.miles, closeTo(5.0, 0.001));
    });

    test('km converts using the 0.621371 factor', () {
      final matches = ParsedTextUtils.extractAllDistances('8.4 km');
      expect(matches.first.miles, closeTo(8.4 * 0.621371, 0.0001));
    });

    test('finds multiple distances in one string', () {
      final matches = ParsedTextUtils.extractAllDistances('Pickup 1.8 mi, Trip 6.4 mi');
      expect(matches, hasLength(2));
    });
  });

  group('extractDurationMinutes', () {
    test('parses "18 min"', () => expect(ParsedTextUtils.extractDurationMinutes('18 min'), 18));
    test('parses "45 minutes"', () => expect(ParsedTextUtils.extractDurationMinutes('45 minutes'), 45));
    test('returns null when absent', () => expect(ParsedTextUtils.extractDurationMinutes('no duration here'), isNull));
  });
}
