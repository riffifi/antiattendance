import 'package:antiattendance/translations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/check_translations.dart';

void main() {
  test(
    'every UI translation and attendance result has all supported translations',
    () {
      final missing = translationSources()
          .where((entry) => !translations.containsKey(entry.english))
          .map((entry) => '${entry.path}: ${entry.english}')
          .toSet();
      expect(
        missing,
        isEmpty,
        reason: 'Add French, Portuguese and Chinese copy for new UI strings.',
      );
      final placeholder = RegExp(r'\{([a-zA-Z][a-zA-Z0-9_]*)\}');
      Set<String> names(String value) =>
          placeholder.allMatches(value).map((match) => match.group(1)!).toSet();
      for (final entry in translations.entries) {
        for (final localized in [
          entry.value.$1,
          entry.value.$2,
          entry.value.$3,
        ]) {
          expect(localized.trim(), isNotEmpty, reason: entry.key);
          expect(names(localized), names(entry.key), reason: entry.key);
        }
      }
    },
  );
}
