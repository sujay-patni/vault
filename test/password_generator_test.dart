import 'package:flutter_test/flutter_test.dart';
import 'package:pwm/security/password_generator.dart';

void main() {
  group('generatePassword', () {
    test('produces requested length', () {
      for (final length in [minGeneratedLength, 20, maxGeneratedLength]) {
        final pw = generatePassword(PasswordGeneratorOptions(length: length));
        expect(pw.length, length);
      }
    });

    test('uses only characters from enabled sets', () {
      const options = PasswordGeneratorOptions(
        length: 32,
        upper: false,
        symbols: false,
      );
      final allowed = (lowerChars + digitChars).split('').toSet();
      for (var i = 0; i < 20; i++) {
        final pw = generatePassword(options);
        for (final ch in pw.split('')) {
          expect(allowed.contains(ch), isTrue, reason: 'unexpected char $ch');
        }
      }
    });

    test('contains at least one character from every enabled set', () {
      const options = PasswordGeneratorOptions(length: 8);
      for (var i = 0; i < 50; i++) {
        final pw = generatePassword(options);
        expect(pw.split('').any(upperChars.contains), isTrue);
        expect(pw.split('').any(lowerChars.contains), isTrue);
        expect(pw.split('').any(digitChars.contains), isTrue);
        expect(pw.split('').any(symbolChars.contains), isTrue);
      }
    });

    test('successive outputs differ', () {
      final seen = <String>{};
      for (var i = 0; i < 50; i++) {
        seen.add(generatePassword(const PasswordGeneratorOptions()));
      }
      expect(seen.length, 50);
    });

    test('rejects no enabled sets and out-of-range lengths', () {
      expect(
        () => generatePassword(
          const PasswordGeneratorOptions(
            upper: false,
            lower: false,
            digits: false,
            symbols: false,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => generatePassword(
          PasswordGeneratorOptions(length: minGeneratedLength - 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => generatePassword(
          PasswordGeneratorOptions(length: maxGeneratedLength + 1),
        ),
        throwsArgumentError,
      );
    });

    test('covers every character of each set over many draws', () {
      final remaining = (upperChars + lowerChars + digitChars + symbolChars)
          .split('')
          .toSet();
      for (var i = 0; i < 200 && remaining.isNotEmpty; i++) {
        final pw = generatePassword(
          const PasswordGeneratorOptions(length: 64),
        );
        remaining.removeAll(pw.split(''));
      }
      expect(remaining, isEmpty);
    });
  });
}
