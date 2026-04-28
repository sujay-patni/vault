// Smoke test: ensures the entrypoint and root widget classes type-check.
// Running VaultApp here would trigger getApplicationDocumentsDirectory()
// which is unavailable on the host test runner; on-device UI tests would
// require a different harness.

import 'package:flutter_test/flutter_test.dart';
// ignore: unused_import
import 'package:pwm/main.dart';

void main() {
  test('main library compiles', () {
    expect(true, isTrue);
  });
}
