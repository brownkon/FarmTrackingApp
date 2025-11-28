import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_locator_2/location_dto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

@pragma('vm:entry-point')
class LocationCallbackHandler {
  static String? _logFilePath;
  static final List<Map<String, dynamic>> _buffer = [];
  static const int _flushThreshold = 1; // flush on every point (for now)

  @pragma('vm:entry-point')
  static Future<void> initCallback(Map<dynamic, dynamic> params) async {
    debugPrint('BG initCallback: $params');
    await _ensureLogFilePath();
    debugPrint('BG log file: $_logFilePath');
  }

  @pragma('vm:entry-point')
  static Future<void> callback(LocationDto locationDto) async {
    await _ensureLogFilePath();

    final point = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'lat': locationDto.latitude,
      'lon': locationDto.longitude,
      'accuracy': locationDto.accuracy,
      'rawTime': locationDto.time,
    };

    _buffer.add(point);
    debugPrint('BG buffered point (#${_buffer.length})');

    if (_buffer.length >= _flushThreshold) {
      await _flushBuffer();
    }
  }

  @pragma('vm:entry-point')
  static Future<void> disposeCallback() async {
    debugPrint('BG disposeCallback: flushing buffer...');
    await _flushBuffer();
  }

  static Future<void> _ensureLogFilePath() async {
    if (_logFilePath != null) return;

    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    // Per-day log file labeled with date.
    _logFilePath = '${dir.path}/location_log_$dateStr.jsonl';
  }

  static Future<void> _flushBuffer() async {
    if (_logFilePath == null || _buffer.isEmpty) return;

    try {
      final file = File(_logFilePath!);
      final sink = file.openWrite(mode: FileMode.append);

      for (final point in _buffer) {
        sink.writeln(jsonEncode(point));
      }

      await sink.flush();
      await sink.close();

      debugPrint('BG flushed ${_buffer.length} points to disk');
      _buffer.clear();
    } catch (e, st) {
      debugPrint('BG flush error: $e');
      debugPrint('$st');
    }
  }
}