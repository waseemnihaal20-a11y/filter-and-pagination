import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces the Clean Architecture dependency rule for every feature:
/// presentation → domain ← data, with domain depending on nothing outside
/// itself (not even Flutter).
void main() {
  const feature = 'lib/features/transaction_history';

  /// Every import/export target of the Dart files under [dir], resolved to a
  /// path under `lib/` (package imports of this app) or left as written.
  Map<String, List<String>> importsUnder(String dir) {
    final result = <String, List<String>>{};
    final files = Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    final directive = RegExp(r"^(?:import|export) '([^']+)'", multiLine: true);
    for (final file in files) {
      result[file.path] = [
        for (final match in directive.allMatches(file.readAsStringSync()))
          _resolve(file.path, match.group(1)!),
      ];
    }
    return result;
  }

  void expectNoImports(
    String layer,
    bool Function(String target) forbidden,
    String rule,
  ) {
    final imports = importsUnder('$feature/$layer');
    expect(imports, isNotEmpty, reason: 'no files found in $layer');
    final violations = [
      for (final MapEntry(key: file, value: targets) in imports.entries)
        for (final target in targets)
          if (forbidden(target)) '$file → $target',
    ];
    expect(violations, isEmpty, reason: rule);
  }

  test('domain depends on nothing outside the domain layer', () {
    expectNoImports(
      'domain',
      (target) =>
          target.startsWith('package:flutter/') ||
          target.startsWith('package:flutter_bloc/') ||
          target.startsWith('package:shared_preferences/') ||
          (target.startsWith('lib/') && !target.startsWith('$feature/domain/')),
      'domain must be pure Dart and self-contained',
    );
  });

  test('data does not depend on presentation', () {
    expectNoImports(
      'data',
      (target) => target.startsWith('$feature/presentation/'),
      'data may depend on domain (and core) only',
    );
  });

  test('presentation does not depend on data', () {
    expectNoImports(
      'presentation',
      (target) =>
          target.startsWith('$feature/data/') ||
          target.startsWith('package:shared_preferences/'),
      'presentation may depend on domain (and core) only',
    );
  });

  test('core does not depend on features', () {
    final imports = importsUnder('lib/core');
    final violations = [
      for (final MapEntry(key: file, value: targets) in imports.entries)
        for (final target in targets)
          if (target.startsWith('lib/features/')) '$file → $target',
    ];
    expect(violations, isEmpty);
  });
}

String _resolve(String fromFile, String target) {
  const self = 'package:filter_and_pagination/';
  if (target.startsWith(self)) return 'lib/${target.substring(self.length)}';
  if (target.contains(':')) return target;
  return Uri.file(fromFile).resolve(target).toFilePath();
}
