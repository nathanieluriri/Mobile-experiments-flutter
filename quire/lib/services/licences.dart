import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The licence each bundled font was released under, and the asset it is
/// kept in. The SIL Open Font License asks that it travel with the font.
const kFontLicences = <String, String>{
  'Inter': 'assets/fonts/OFL-Inter.txt',
  'Quicksand': 'assets/fonts/OFL-Quicksand.txt',
};

/// Adds the fonts' licences to the ones the framework already lists, so the
/// licence page shows them beside the packages'.
void registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in kFontLicences.entries) {
      yield LicenseEntryWithLineBreaks(
        <String>[entry.key],
        await rootBundle.loadString(entry.value),
      );
    }
  });
}
