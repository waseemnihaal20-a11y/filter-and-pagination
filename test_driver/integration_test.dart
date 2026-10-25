import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Runs the on-device integration tests and saves every screenshot they take
/// to `docs/screenshots/<name>.png`.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('docs/screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
