import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';

class PaddockImportScreen extends StatefulWidget {
  const PaddockImportScreen({super.key});

  @override
  State<PaddockImportScreen> createState() => _PaddockImportScreenState();
}

class _PaddockImportScreenState extends State<PaddockImportScreen> {
  final storage = Storage();
  final uuid = const Uuid();

  bool busy = false;

  PlatformFile? picked;
  String? rawText;

  // Parsed candidate rows (each row is a properties map)
  List<Map<String, dynamic>> rows = [];
  List<String> keys = [];

  String? nameKey;
  String? areaKey;

  bool skipDuplicatesByName = true;
  bool includeInRotationDefault = true;

  String? error;

  Future<void> _pickFile() async {
    setState(() {
      busy = true;
      error = null;
      picked = null;
      rawText = null;
      rows = [];
      keys = [];
      nameKey = null;
      areaKey = null;
    });

    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['geojson', 'json', 'csv'],
        withData: false,
      );

      if (res == null || res.files.isEmpty) {
        setState(() => busy = false);
        return;
      }

      final f = res.files.first;
      if (f.path == null) {
        setState(() {
          busy = false;
          error = 'Could not read file path.';
        });
        return;
      }

      final text = await File(f.path!).readAsString();

      picked = f;
      rawText = text;

      final ext = (f.extension ?? '').toLowerCase();
      if (ext == 'csv') {
        _parseCsv(text);
      } else {
        _parseJsonOrGeoJson(text);
      }

      // Pick sensible defaults
      _guessDefaults();

      setState(() => busy = false);
    } catch (e) {
      setState(() {
        busy = false;
        error = 'Import failed: $e';
      });
    }
  }

  void _guessDefaults() {
    if (keys.isEmpty) return;

    String? guessName;
    String? guessArea;

    // Common name keys
    const nameCandidates = [
      'name',
      'paddock',
      'paddock_name',
      'pdk',
      'id',
      'number',
      'title',
      'label',
    ];

    // Common area keys
    const areaCandidates = [
      'area',
      'area_ha',
      'areaHa',
      'ha',
      'hectares',
      'hectare',
      'areahectares',
    ];

    for (final c in nameCandidates) {
      final found = keys.firstWhere(
        (k) => k.toLowerCase() == c,
        orElse: () => '',
      );
      if (found.isNotEmpty) {
        guessName = found;
        break;
      }
    }

    for (final c in areaCandidates) {
      final found = keys.firstWhere(
        (k) => k.toLowerCase() == c,
        orElse: () => '',
      );
      if (found.isNotEmpty) {
        guessArea = found;
        break;
      }
    }

    // Fallbacks
    guessName ??= keys.first;
    guessArea ??= keys.length > 1 ? keys[1] : keys.first;

    nameKey = guessName;
    areaKey = guessArea;
  }

  void _parseJsonOrGeoJson(String text) {
    final decoded = jsonDecode(text);

    // If GeoJSON FeatureCollection
    if (decoded is Map<String, dynamic> &&
        (decoded['type'] == 'FeatureCollection') &&
        decoded['features'] is List) {
      final feats = (decoded['features'] as List).cast<dynamic>();

      final out = <Map<String, dynamic>>[];
      for (final f in feats) {
        if (f is Map<String, dynamic>) {
          final props = (f['properties'] is Map)
              ? Map<String, dynamic>.from(f['properties'] as Map)
              : <String, dynamic>{};

          // Some GeoJSONs put name at top-level too; we’ll merge if present.
          for (final entry in f.entries) {
            if (entry.key == 'properties' ||
                entry.key == 'geometry' ||
                entry.key == 'type') {
              continue;
            }
            props.putIfAbsent(entry.key, () => entry.value);
          }

          out.add(props);
        }
      }

      rows = out;
      keys = _collectKeys(out);
      return;
    }

    // If plain JSON list of objects
    if (decoded is List) {
      final out = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is Map) {
          out.add(Map<String, dynamic>.from(item));
        }
      }
      rows = out;
      keys = _collectKeys(out);
      return;
    }

    // If a single object with a list under some key (best-effort)
    if (decoded is Map<String, dynamic>) {
      final listKey = decoded.keys.firstWhere(
        (k) => decoded[k] is List,
        orElse: () => '',
      );

      if (listKey.isNotEmpty) {
        final list = (decoded[listKey] as List).cast<dynamic>();
        final out = <Map<String, dynamic>>[];
        for (final item in list) {
          if (item is Map) {
            out.add(Map<String, dynamic>.from(item));
          }
        }
        rows = out;
        keys = _collectKeys(out);
        return;
      }
    }

    throw Exception('Unsupported JSON format.');
  }

  void _parseCsv(String text) {
    // Basic CSV parser (commas, no fancy quotes handling). Works for most simple exports.
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.length < 2) {
      throw Exception('CSV must have a header row and at least one data row.');
    }

    final header = lines.first.split(',').map((s) => s.trim()).toList();

    final out = <Map<String, dynamic>>[];
    for (int i = 1; i < lines.length; i++) {
      final cols = lines[i].split(',').map((s) => s.trim()).toList();
      final m = <String, dynamic>{};
      for (int c = 0; c < header.length && c < cols.length; c++) {
        m[header[c]] = cols[c];
      }
      out.add(m);
    }

    rows = out;
    keys = _collectKeys(out);
  }

  List<String> _collectKeys(List<Map<String, dynamic>> list) {
    final set = <String>{};
    for (final r in list) {
      set.addAll(r.keys.where((k) => k.trim().isNotEmpty));
    }
    final out = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  double _parseAreaHa(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();

    final s = v.toString().trim();
    if (s.isEmpty) return 0.0;

    // allow "12.3", "12,3", "12 ha"
    final cleaned = s
        .replaceAll('ha', '')
        .replaceAll('HA', '')
        .trim()
        .replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0.0;
  }

  String _asString(dynamic v) => (v ?? '').toString().trim();

  Future<void> _import() async {
    if (nameKey == null || areaKey == null) return;
    if (rows.isEmpty) return;

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final existing = await storage.loadPaddocks();

      // Build a set of existing names (lowercase) if skipping duplicates
      final existingNames = existing
          .map((p) => p.name.trim().toLowerCase())
          .toSet();

      int nextOrder = 1;
      if (existing.isNotEmpty) {
        nextOrder =
            (existing
                .map((p) => p.recordOrder)
                .reduce((a, b) => a > b ? a : b)) +
            1;
      }

      final toAdd = <Paddock>[];

      for (final r in rows) {
        final name = _asString(r[nameKey]);
        final area = _parseAreaHa(r[areaKey]);

        if (name.isEmpty) continue;
        if (area <= 0) continue;

        if (skipDuplicatesByName &&
            existingNames.contains(name.toLowerCase())) {
          continue;
        }

        toAdd.add(
          Paddock(
            id: uuid.v4(),
            name: name,
            areaHa: area,
            recordOrder: nextOrder++,
            includeInRotation: includeInRotationDefault,
          ),
        );
      }

      if (toAdd.isEmpty) {
        setState(() {
          busy = false;
          error =
              'No valid paddocks found to import (check name/area mapping).';
        });
        return;
      }

      final updated = [...existing, ...toAdd];
      await storage.savePaddocks(updated);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        busy = false;
        error = 'Import failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = picked != null;
    final canMap = rows.isNotEmpty && keys.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Import paddocks')),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                const Text(
                  'Import paddocks from a file',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Supports GeoJSON (.geojson/.json) and CSV (.csv). '
                  'Pick which fields contain the paddock name and area (ha).',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 14),

                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Choose file'),
                ),

                const SizedBox(height: 10),
                if (hasFile)
                  Text(
                    'Selected: ${picked!.name}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),

                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],

                const SizedBox(height: 18),
                if (canMap) ...[
                  Text(
                    'Found ${rows.length} rows',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),

                  _dropdown(
                    label: 'Field to use as paddock name',
                    value: nameKey,
                    items: keys,
                    onChanged: (v) => setState(() => nameKey = v),
                  ),
                  const SizedBox(height: 12),
                  _dropdown(
                    label: 'Field to use as area (ha)',
                    value: areaKey,
                    items: keys,
                    onChanged: (v) => setState(() => areaKey = v),
                  ),

                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Skip duplicates by paddock name'),
                    subtitle: const Text(
                      'If a paddock with the same name already exists, it won’t be imported.',
                    ),
                    value: skipDuplicatesByName,
                    onChanged: (v) => setState(() => skipDuplicatesByName = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include imported paddocks in rotation'),
                    subtitle: const Text(
                      'Turn this off if importing a mix that includes cropped paddocks.',
                    ),
                    value: includeInRotationDefault,
                    onChanged: (v) =>
                        setState(() => includeInRotationDefault = v),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'Preview (first 8):',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _preview(),

                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (nameKey == null || areaKey == null)
                          ? null
                          : _import,
                      child: const Text(
                        'Import paddocks',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: items
              .map((k) => DropdownMenuItem(value: k, child: Text(k)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _preview() {
    final nk = nameKey;
    final ak = areaKey;

    final list = rows.take(8).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (int i = 0; i < list.length; i++)
            Column(
              children: [
                ListTile(
                  dense: true,
                  title: Text(
                    nk == null ? '—' : _asString(list[i][nk]),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    ak == null
                        ? '—'
                        : '${_parseAreaHa(list[i][ak]).toStringAsFixed(2)} ha',
                  ),
                ),
                if (i != list.length - 1) const Divider(height: 1),
              ],
            ),
        ],
      ),
    );
  }
}
