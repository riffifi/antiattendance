import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'package:antiattendance/translations.dart';

class TranslationSource {
  const TranslationSource(this.english, this.russian, this.path);
  final String english;
  final String russian;
  final String path;
}

class _TranslationVisitor extends RecursiveAstVisitor<void> {
  _TranslationVisitor(this.path, this.entries);
  final String path;
  final List<TranslationSource> entries;
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (path.endsWith('l10n.dart') &&
        node.name.lexeme == 'messages' &&
        node.initializer is SetOrMapLiteral) {
      for (final element
          in (node.initializer as SetOrMapLiteral).elements
              .whereType<MapLiteralEntry>()) {
        if (element.key is StringLiteral && element.value is StringLiteral) {
          final ru = (element.key as StringLiteral).stringValue;
          final en = (element.value as StringLiteral).stringValue;
          if (ru != null && en != null) {
            entries.add(TranslationSource(en, ru, path));
          }
        }
      }
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (const {'tr', 'trf', '_countText'}.contains(node.methodName.name)) {
      final args = node.argumentList.arguments;
      if (args.length >= 3 &&
          args[1] is StringLiteral &&
          args[2] is StringLiteral) {
        final ru = (args[1] as StringLiteral).stringValue;
        final en = (args[2] as StringLiteral).stringValue;
        if (en != null && ru != null) {
          entries.add(TranslationSource(en, ru, path));
        }
      }
    }
    super.visitMethodInvocation(node);
  }
}

List<TranslationSource> translationSources() {
  final entries = <TranslationSource>[];
  for (final file in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    parseString(
      content: file.readAsStringSync(),
      throwIfDiagnostics: false,
    ).unit.accept(_TranslationVisitor(file.path, entries));
  }
  return entries;
}

void main() {
  final missing = <String, TranslationSource>{};
  for (final entry in translationSources()) {
    if (!translations.containsKey(entry.english)) {
      missing[entry.english] = entry;
    }
  }
  for (final entry in missing.values) {
    stdout.writeln('${entry.path}\n${entry.english}\n${entry.russian}\n');
  }
  stdout.writeln('${missing.length} untranslated strings.');
  if (missing.isNotEmpty) exitCode = 1;
}
