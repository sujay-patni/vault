import '../crypto/aes_gcm.dart';

const String upperChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const String lowerChars = 'abcdefghijklmnopqrstuvwxyz';
const String digitChars = '0123456789';
const String symbolChars = '!@#\$%^&*()-_=+[]{};:,.?/';

const int minGeneratedLength = 8;
const int maxGeneratedLength = 64;

class PasswordGeneratorOptions {
  const PasswordGeneratorOptions({
    this.length = 20,
    this.upper = true,
    this.lower = true,
    this.digits = true,
    this.symbols = true,
  });

  final int length;
  final bool upper;
  final bool lower;
  final bool digits;
  final bool symbols;

  PasswordGeneratorOptions copyWith({
    int? length,
    bool? upper,
    bool? lower,
    bool? digits,
    bool? symbols,
  }) {
    return PasswordGeneratorOptions(
      length: length ?? this.length,
      upper: upper ?? this.upper,
      lower: lower ?? this.lower,
      digits: digits ?? this.digits,
      symbols: symbols ?? this.symbols,
    );
  }

  List<String> get enabledSets => [
    if (upper) upperChars,
    if (lower) lowerChars,
    if (digits) digitChars,
    if (symbols) symbolChars,
  ];
}

/// Generates a random password from the secure RNG with at least one
/// character from each enabled set.
String generatePassword(PasswordGeneratorOptions options) {
  final sets = options.enabledSets;
  if (sets.isEmpty) {
    throw ArgumentError('at least one character set must be enabled');
  }
  if (options.length < minGeneratedLength ||
      options.length > maxGeneratedLength) {
    throw ArgumentError(
      'length must be between $minGeneratedLength and $maxGeneratedLength',
    );
  }
  final all = sets.join();
  final chars = List<String>.generate(
    options.length,
    (_) => all[_secureBelow(all.length)],
  );
  // Overwrite the first slots with one char from each enabled set, then
  // shuffle so the guaranteed chars do not sit at predictable positions.
  for (var i = 0; i < sets.length; i++) {
    chars[i] = sets[i][_secureBelow(sets[i].length)];
  }
  for (var i = chars.length - 1; i > 0; i--) {
    final j = _secureBelow(i + 1);
    final tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }
  return chars.join();
}

/// Uniform random int in [0, maxExclusive) via rejection sampling — a plain
/// modulo would bias toward low values.
int _secureBelow(int maxExclusive) {
  assert(maxExclusive > 0 && maxExclusive <= 256);
  final limit = 256 - (256 % maxExclusive);
  while (true) {
    final b = randomBytes(1)[0];
    if (b < limit) return b % maxExclusive;
  }
}
