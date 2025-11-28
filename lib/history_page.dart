import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _LogSummary {
  final int totalBytes;
  final int fileCount;
  final DateTime? lastSync;

  _LogSummary({
    required this.totalBytes,
    required this.fileCount,
    required this.lastSync,
  });
}

class _HistoryPageState extends State<HistoryPage> {
  Future<List<Map<String, dynamic>>> _futureLocations =
      Future.value(<Map<String, dynamic>>[]);
  Future<_LogSummary> _futureSummary =
      Future.value(_LogSummary(totalBytes: 0, fileCount: 0, lastSync: null));

  bool _syncing = false;
  String? _syncError;
  bool _autoSyncAttempted = false;

  @override
  void initState() {
    super.initState();
    _futureLocations = _loadLocations();
    _futureSummary = _loadSummary();
  }

  Future<_LogSummary> _loadSummary() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      int totalBytes = 0;
      int fileCount = 0;

      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith('location_log_') && name.endsWith('.jsonl')) {
            fileCount++;
            totalBytes += await entity.length();
          }
        }
      }

      DateTime? lastSync;
      final metaFile = File('${dir.path}/location_sync_meta.json');
      if (await metaFile.exists()) {
        final text = await metaFile.readAsString();
        final data = jsonDecode(text);
        if (data is Map<String, dynamic>) {
          final iso = data['lastSyncIso'] as String?;
          if (iso != null) {
            lastSync = DateTime.tryParse(iso);
          }
        }
      }

      return _LogSummary(
        totalBytes: totalBytes,
        fileCount: fileCount,
        lastSync: lastSync,
      );
    } catch (e, st) {
      debugPrint('Error loading summary: $e');
      debugPrint('$st');
      return _LogSummary(totalBytes: 0, fileCount: 0, lastSync: null);
    }
  }

  Future<List<Map<String, dynamic>>> _loadLocations() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final List<File> logFiles = [];

      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith('location_log_') && name.endsWith('.jsonl')) {
            logFiles.add(entity);
          }
        }
      }

      if (logFiles.isEmpty) return [];

      // Sort files by name so older logs come first.
      logFiles.sort((a, b) => a.path.compareTo(b.path));

      final List<Map<String, dynamic>> items = [];

      for (final file in logFiles) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          try {
            final data = jsonDecode(trimmed);
            if (data is Map<String, dynamic>) {
              items.add(data);
            }
          } catch (_) {
            // ignore malformed lines
          }
        }
      }

      // Newest first by timestamp if present.
      items.sort((a, b) {
        final ta = DateTime.tryParse(a['timestamp']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final tb = DateTime.tryParse(b['timestamp']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });

      return items;
    } catch (e, st) {
      debugPrint('Error loading locations: $e');
      debugPrint('$st');
      return [];
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  String _formatLastSync(DateTime? dt) {
    if (dt == null) return 'Never';
    return dt.toLocal().toString();
  }

  Future<void> _syncToServer() async {
    setState(() {
      _syncing = true;
      _syncError = null;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final List<File> logFiles = [];

      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith('location_log_') && name.endsWith('.jsonl')) {
            logFiles.add(entity);
          }
        }
      }

      final List<Map<String, dynamic>> allPoints = [];
      for (final file in logFiles) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          try {
            final data = jsonDecode(trimmed);
            if (data is Map<String, dynamic>) {
              allPoints.add(data);
            }
          } catch (_) {
            // ignore malformed lines
          }
        }
      }

      await _uploadBatches(allPoints);

      // Write sync metadata
      final metaFile = File('${dir.path}/location_sync_meta.json');
      await metaFile.writeAsString(jsonEncode({
        'lastSyncIso': DateTime.now().toIso8601String(),
        'pointCount': allPoints.length,
      }));

      // Refresh summary after sync
      setState(() {
        _futureSummary = _loadSummary();
      });
    } catch (e, st) {
      debugPrint('Sync error: $e');
      debugPrint('$st');
      setState(() {
        _syncError = e.toString();
      });
    } finally {
      setState(() {
        _syncing = false;
      });
    }
  }

  Future<void> _uploadBatches(List<Map<String, dynamic>> points) async {
    const batchSize = 500;
    final supabase = Supabase.instance.client;

for (var i = 0; i < points.length; i += batchSize) {
  final batch = points.sublist(
    i,
    i + batchSize > points.length ? points.length : i + batchSize,
  );

  final rows = batch.map((p) {
    return {
      'session_id': p['sessionId'],     // you already store this locally
      'ts': p['timestamp'],             // ISO8601 string
      'lat': p['lat'],
      'lon': p['lon'],
      'accuracy': p['accuracy'],
      'raw_time_ms': p['timeMs'],       // optional
    };
  }).toList();

  final res = await supabase.from('locations').insert(rows);

  if (res.error != null) {
    throw Exception('Supabase insert error: ${res.error!.message}');
  }
}
  }

  Future<void> _refresh() async {
    setState(() {
      _futureLocations = _loadLocations();
      _futureSummary = _loadSummary();
    });
  }

  Future<void> _clearHistory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith('location_log_') && name.endsWith('.jsonl')) {
            await entity.delete();
          }
        }
      }

      final metaFile = File('${dir.path}/location_sync_meta.json');
      if (await metaFile.exists()) {
        await metaFile.delete();
      }
    } catch (e, st) {
      debugPrint('Error clearing history: $e');
      debugPrint('$st');
    }

    // Reload summary and locations after clearing.
    if (mounted) {
      setState(() {
        _futureLocations = _loadLocations();
        _futureSummary = _loadSummary();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: FutureBuilder<_LogSummary>(
            future: _futureSummary,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final summary = snapshot.data ??
                  _LogSummary(totalBytes: 0, fileCount: 0, lastSync: null);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location Log Summary',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('Files: ${summary.fileCount}'),
                  Text('Size: ${_formatBytes(summary.totalBytes)}'),
                  Text('Last sync: ${_formatLastSync(summary.lastSync)}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _syncing ? null : _syncToServer,
                        icon: _syncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_upload),
                        label: Text(_syncing ? 'Syncing...' : 'Sync to server'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                      TextButton.icon(
                        onPressed: _clearHistory,
                        icon: const Icon(Icons.delete),
                        label: const Text('Clear history'),
                      ),
                    ],
                  ),
                  if (_syncError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Sync error: $_syncError',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _futureLocations,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading history: ${snapshot.error}'),
                );
              }

              final data = snapshot.data ?? [];
              if (data.isEmpty) {
                return const Center(
                  child: Text('No location history yet.'),
                );
              }

              return ListView.builder(
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final entry = data[index];
                  final ts = entry['timestamp']?.toString() ?? 'Unknown time';
                  final latVal = entry['lat'];
                  final lonVal = entry['lon'];
                  final lat = latVal is num
                      ? latVal.toStringAsFixed(5)
                      : latVal?.toString() ?? '?';
                  final lon = lonVal is num
                      ? lonVal.toStringAsFixed(5)
                      : lonVal?.toString() ?? '?';
                  final acc = entry['accuracy']?.toString() ?? '?';

                  return ListTile(
                    leading: const Icon(Icons.location_on),
                    title: Text('$lat, $lon'),
                    subtitle: Text('$ts\nAccuracy: $acc'),
                    isThreeLine: true,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}