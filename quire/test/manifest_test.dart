import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The manifest is where the app makes promises Android enforces, so the
/// promises the ledger repeats are checked here rather than trusted.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('the library is kept out of cloud backup', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    // From Android 12 allowBackup no longer stops a transfer to a new phone.
    expect(manifest, contains('android:dataExtractionRules'));
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    expect(rules, contains('<device-transfer>'));
    expect(rules, contains('<cloud-backup>'));
  });

  test('the only permissions are the notice and its schedule', () {
    final asked = RegExp(r'uses-permission android:name="([^"]+)"')
        .allMatches(manifest)
        .map((m) => m[1])
        .toList();
    expect(asked, <String>[
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.RECEIVE_BOOT_COMPLETED',
    ]);
  });

  test('no format is claimed that the app cannot read', () {
    expect(manifest, isNot(contains('application/msword')));
    expect(manifest, isNot(contains('application/vnd.ms-excel')));
    expect(manifest, isNot(contains('application/vnd.ms-powerpoint')));
  });

  test('no permission reaches the network', () {
    expect(manifest, isNot(contains('android.permission.INTERNET')));
  });
}
