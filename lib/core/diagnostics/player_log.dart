import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum LogLevel { info, warn, error }

class LogLine {
  final DateTime time;
  final LogLevel level;
  final String message;
  const LogLine(this.time, this.level, this.message);
}

class PlayerLog {
  PlayerLog._();
  static final PlayerLog instance = PlayerLog._();

  static const int _maxLines = 800;
  final Queue<LogLine> _lines = Queue<LogLine>();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<String, String> _context = <String, String>{};

  String _appVersion = '';
  String _device = '';

  List<LogLine> get lines => List.unmodifiable(_lines);

  Future<void> init() async {
    if (_appVersion.isNotEmpty) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = 'unknown';
    }
    try {
      _device = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      _device = 'unknown';
    }
  }

  void setContext(Map<String, String?> values) {
    values.forEach((k, v) {
      if (v == null || v.isEmpty) {
        _context.remove(k);
      } else {
        _context[k] = v;
      }
    });
    _bump();
  }

  void clearContext() {
    _context.clear();
    _bump();
  }

  void add(String message, {LogLevel level = LogLevel.info}) {
    if (kDebugMode) {
      final prefix = switch (level) {
        LogLevel.error => '[PLAYER] ✗',
        LogLevel.warn => '[PLAYER] ⚠',
        LogLevel.info => '[PLAYER]',
      };
      debugPrint('$prefix $message');
    }
    _lines.add(LogLine(DateTime.now(), level, message));
    while (_lines.length > _maxLines) {
      _lines.removeFirst();
    }
    _bump();
  }

  void i(String message) => add(message);
  void w(String message) => add(message, level: LogLevel.warn);
  void e(String message) => add(message, level: LogLevel.error);

  void clear() {
    _lines.clear();
    _bump();
  }

  void _bump() => revision.value++;

  String _two(int n) => n.toString().padLeft(2, '0');
  String _three(int n) => n.toString().padLeft(3, '0');

  String stamp(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${_three(t.millisecond)}';

  String formatForShare() {
    final b = StringBuffer()
      ..writeln('Soplay player logs')
      ..writeln('app: ${_appVersion.isEmpty ? 'unknown' : _appVersion}')
      ..writeln('device: ${_device.isEmpty ? 'unknown' : _device}')
      ..writeln('captured: ${DateTime.now().toIso8601String()}');
    if (_context.isNotEmpty) {
      b.writeln('--- context ---');
      _context.forEach((k, v) => b.writeln('$k: $v'));
    }
    b.writeln('--- log (${_lines.length}) ---');
    for (final l in _lines) {
      final tag = switch (l.level) {
        LogLevel.error => 'E',
        LogLevel.warn => 'W',
        LogLevel.info => 'I',
      };
      b.writeln('${stamp(l.time)} $tag  ${l.message}');
    }
    return b.toString();
  }
}
