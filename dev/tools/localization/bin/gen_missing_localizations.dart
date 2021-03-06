// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This program updates the language locale arb files with any missing resource
// entries that are included in the English arb files. This is useful when
// adding new resources for localization. You can just add the appropriate
// entries to the English arb file and then run this script. It will then check
// all of the other language locale arb files and update them with new 'TBD'
// entries for any missing resources. These will be picked up by the localization
// team and then translated.
//
// ## Usage
//
// Run this program from the root of the git repository.
//
// ```
// dart dev/tools/localization/bin/gen_missing_localizations.dart
// ```

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../localizations_utils.dart';
import '../localizations_validator.dart';

Future<void> main(List<String> rawArgs) async {
  checkCwdIsRepoRoot('gen_missing_localizations');

  final String localizationPath = path.join('packages', 'flutter_localizations', 'lib', 'src', 'l10n');
  updateMissingResources(localizationPath, 'material');
  updateMissingResources(localizationPath, 'cupertino');
}

Map<String, dynamic> loadBundle(File file) {
  if (!FileSystemEntity.isFileSync(file.path))
    exitWithError('Unable to find input file: ${file.path}');
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

void writeBundle(File file, Map<String, dynamic> bundle) {
  final StringBuffer contents = StringBuffer();
  contents.writeln('{');
  for (final String key in bundle.keys) {
    contents.writeln('  "$key": ${json.encode(bundle[key])}${key == bundle.keys.last ? '' : ','}');
  }
  contents.writeln('}');
  file.writeAsStringSync(contents.toString());
}

Set<String> resourceKeys(Map<String, dynamic> bundle) {
  return Set<String>.from(
    // Skip any attribute keys
    bundle.keys.where((String key) => !key.startsWith('@'))
  );
}

bool intentionallyOmitted(String key, Map<String, dynamic> bundle) {
  final String attributeKey = '@$key';
  final dynamic attribute = bundle[attributeKey];
  return attribute is Map && attribute.containsKey('notUsed');
}

/// Whether `key` corresponds to one of the plural variations of a key with
/// the same prefix and suffix "Other".
bool isPluralVariation(String key, Map<String, dynamic> bundle) {
  final Match pluralMatch = kPluralRegexp.firstMatch(key);
  if (pluralMatch == null)
    return false;
  final String prefix = pluralMatch[1];
  return bundle.containsKey('${prefix}Other');
}

void updateMissingResources(String localizationPath, String groupPrefix) {
  final Directory localizationDir = Directory(localizationPath);
  final RegExp filenamePattern = RegExp('${groupPrefix}_(\\w+)\.arb');

  final Set<String> requiredKeys = resourceKeys(loadBundle(File(path.join(localizationPath, '${groupPrefix}_en.arb'))));

  for (final FileSystemEntity entity in localizationDir.listSync().toList()..sort(sortFilesByPath)) {
    final String entityPath = entity.path;
    if (FileSystemEntity.isFileSync(entityPath) && filenamePattern.hasMatch(entityPath)) {
      final String localeString = filenamePattern.firstMatch(entityPath)[1];
      final LocaleInfo locale = LocaleInfo.fromString(localeString);

      // Only look at top-level language locales
      if (locale.length == 1) {
        final File arbFile = File(entityPath);
        final Map<String, dynamic> localeBundle = loadBundle(arbFile);
        final Set<String> localeResources = resourceKeys(localeBundle);
        final Set<String> missingResources = requiredKeys.difference(localeResources).where(
          (String key) => !isPluralVariation(key, localeBundle) && !intentionallyOmitted(key, localeBundle)
        ).toSet();
        if (missingResources.isNotEmpty) {
          localeBundle.addEntries(missingResources.map((String k) => MapEntry<String, String>(k, 'TBD')));
          writeBundle(arbFile, localeBundle);
          print('Updated $entityPath with missing entries for $missingResources');
        }
      }
    }
  }
}
