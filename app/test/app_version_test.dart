import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lnmarkets_bot/app_version.dart';

void main() {
  test('AppVersion matches pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*([0-9.]+)\+([0-9]+)\s*$', multiLine: true)
            .firstMatch(pubspec);

    expect(match, isNotNull);
    expect(AppVersion.version, match!.group(1));
    expect(AppVersion.build, match.group(2));
  });
}
