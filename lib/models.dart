import 'dart:convert';

import 'package:yaml/yaml.dart';

class DiaryEntryFile {
  const DiaryEntryFile({
    required this.path,
    required this.fileName,
    required this.rawContent,
    required this.bodyMarkdown,
    required this.frontmatter,
    required this.modifiedAt,
  });

  final String path;
  final String fileName;
  final String rawContent;
  final String bodyMarkdown;
  final Map<String, Object?> frontmatter;
  final DateTime modifiedAt;
}

class MarkdownFrontmatter {
  static MarkdownFrontmatterResult parse(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      return MarkdownFrontmatterResult(frontmatter: const {}, body: raw);
    }
    final end = normalized.indexOf('\n---\n', 4);
    if (end == -1) {
      return MarkdownFrontmatterResult(frontmatter: const {}, body: raw);
    }

    final yamlPart = normalized.substring(4, end);
    final body = normalized.substring(end + 5);
    try {
      final doc = loadYaml(yamlPart);
      if (doc is YamlMap) {
        return MarkdownFrontmatterResult(
          frontmatter: _yamlToMap(doc),
          body: body,
        );
      }
    } catch (_) {}
    return MarkdownFrontmatterResult(frontmatter: const {}, body: body);
  }

  static Map<String, Object?> _yamlToMap(YamlMap yaml) {
    final result = <String, Object?>{};
    yaml.nodes.forEach((keyNode, valueNode) {
      result[keyNode.toString()] = _normalizeYamlValue(valueNode.value);
    });
    return result;
  }

  static Object? _normalizeYamlValue(Object? value) {
    if (value is YamlMap) {
      final map = <String, Object?>{};
      value.nodes.forEach((k, v) {
        map[k.toString()] = _normalizeYamlValue(v.value);
      });
      return map;
    }
    if (value is YamlList) {
      return value.nodes.map((e) => _normalizeYamlValue(e.value)).toList();
    }
    return value;
  }

  static String compose({
    required Map<String, Object?> frontmatter,
    required String body,
  }) {
    final cleaned = <String, Object?>{};
    for (final entry in frontmatter.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      final value = entry.value;
      if (value is String && value.trim().isEmpty) continue;
      if (value is List && value.isEmpty) continue;
      cleaned[key] = value;
    }

    if (cleaned.isEmpty) return body;

    final buffer = StringBuffer()..writeln('---');
    for (final entry in cleaned.entries) {
      buffer.writeln('${entry.key}: ${_toYamlInline(entry.value)}');
    }
    buffer.writeln('---');
    if (body.isNotEmpty && !body.startsWith('\n')) {
      buffer.writeln();
    }
    buffer.write(body);
    return buffer.toString();
  }

  static String _toYamlInline(Object? value) {
    if (value == null) return 'null';
    if (value is bool || value is num) return '$value';
    if (value is List) return '[${value.map(_toYamlInline).join(', ')}]';
    if (value is Map) {
      final pairs = value.entries
          .map((e) => '${e.key}: ${_toYamlInline(e.value)}')
          .join(', ');
      return '{$pairs}';
    }
    final text = value.toString();
    final safe = RegExp(r'^[A-Za-z0-9 _./:+-]+$').hasMatch(text) &&
        !text.startsWith(' ') &&
        !text.endsWith(' ') &&
        text != 'null' &&
        text != 'true' &&
        text != 'false';
    return safe ? text : jsonEncode(text);
  }
}

class MarkdownFrontmatterResult {
  const MarkdownFrontmatterResult({
    required this.frontmatter,
    required this.body,
  });

  final Map<String, Object?> frontmatter;
  final String body;
}

extension IterableFirstOrNullX<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

