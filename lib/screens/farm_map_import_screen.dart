import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:shapefile/shapefile.dart' as shp;

import '../models.dart';
import '../storage.dart';

class FarmMapImportScreen extends StatefulWidget {
  const FarmMapImportScreen({super.key});

  @override
  State<FarmMapImportScreen> createState() => _FarmMapImportScreenState();
}

class _FarmMapImportScreenState extends State<FarmMapImportScreen> {
  final storage = Storage();
  final uuid = const Uuid();

  bool busy = false;
  String? error;

  PlatformFile? picked;
  String? sourceType;

  // GeoJSON FeatureCollection-ish
  Map<String, dynamic>? featureCollection;
  List<Map<String, dynamic>> features = [];

  // Attribute keys for choosing paddock identifier and area
  List<String> keys = [];
  String? nameKey;
  String? areaKey;

  // Replace vs merge
  bool? mergeMode;
  bool? overwriteNamesOnMerge;

  // Feature index -> selected paddockId (only for unmatched)
  final Map<int, String> featureToPaddockId = {};

  Future<void> _pickFile() async {
    setState(() {
      busy = true;
      error = null;
      picked = null;
      sourceType = null;
      featureCollection = null;
      features = [];
      keys = [];
      nameKey = null;
      areaKey = null;
      mergeMode = null;
      overwriteNamesOnMerge = null;
      featureToPaddockId.clear();
    });

    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['geojson', 'json', 'zip'],
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

      picked = f;
      final ext = (f.extension ?? '').toLowerCase();
      if (ext == 'zip') {
        sourceType = 'zip';
        await _parseShapefileZip(await File(f.path!).readAsBytes());
      } else {
        sourceType = 'geojson';
        final text = await File(f.path!).readAsString();
        _parseGeoJson(text);
      }

      _guessDefaults();

      setState(() => busy = false);
    } catch (e) {
      setState(() {
        busy = false;
        error = 'Import failed: $e';
      });
    }
  }

  void _parseGeoJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('GeoJSON must be an object');
    }

    if (decoded['type'] != 'FeatureCollection') {
      throw Exception('GeoJSON must be a FeatureCollection');
    }

    final feats = decoded['features'];
    if (feats is! List) {
      throw Exception('GeoJSON missing features');
    }

    final out = <Map<String, dynamic>>[];
    for (final f in feats) {
      if (f is Map) {
        out.add(Map<String, dynamic>.from(f));
      }
    }

    featureCollection = decoded;
    features = out;
    keys = _collectPropKeys(out);
  }

  Future<void> _parseShapefileZip(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? shpFile;
    ArchiveFile? dbfFile;
    ArchiveFile? prjFile;

    for (final f in archive) {
      final name = f.name.toLowerCase();
      if (name.endsWith('.shp')) shpFile = f;
      if (name.endsWith('.dbf')) dbfFile = f;
      if (name.endsWith('.prj')) prjFile = f;
    }

    if (shpFile == null || dbfFile == null) {
      throw Exception('Zip must contain .shp and .dbf');
    }

    // Note: shapefile package does not parse .prj; we still capture it for metadata.
    final fc = await shp.featureCollection(
      Stream.value(shpFile.content as List<int>),
      dbf: Stream.value(dbfFile.content as List<int>),
    );

    final feats = fc['features'];
    if (feats is! List) {
      throw Exception('Shapefile read produced no features');
    }

    featureCollection = Map<String, dynamic>.from(fc);
    features = feats
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    // Keys from properties
    keys = _collectPropKeys(features);

    // Store prj text for metadata if present.
    if (prjFile != null) {
      final prj = utf8.decode(
        (prjFile.content as List<int>),
        allowMalformed: true,
      );
      featureCollection!['__prj'] = prj;
    }
  }

  List<String> _collectPropKeys(List<Map<String, dynamic>> feats) {
    final set = <String>{};
    for (final f in feats) {
      final props = f['properties'];
      if (props is Map) {
        set.addAll(
          props.keys.map((k) => k.toString()).where((k) => k.isNotEmpty),
        );
      }
    }
    final out = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  void _guessDefaults() {
    if (keys.isEmpty) return;

    String? guessName;
    String? guessArea;

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

    const areaCandidates = [
      'area',
      'area_ha',
      'areaha',
      'ha',
      'hectares',
      'hectare',
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

    guessName ??= keys.first;
    guessArea ??= keys.length > 1 ? keys[1] : keys.first;

    nameKey = guessName;
    areaKey = guessArea;
  }

  double _parseAreaHa(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return 0.0;
    final cleaned = s
        .replaceAll('ha', '')
        .replaceAll('HA', '')
        .trim()
        .replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0.0;
  }

  String _asString(dynamic v) => (v ?? '').toString().trim();

  String _normName(String s) {
    final t = s.trim().toLowerCase();
    return t.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normNameForMatch(String s) {
    final t = s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.isEmpty) return '';
    final parts = t.split(' ');
    final out = <String>[];
    for (final p in parts) {
      if (p.isEmpty) continue;
      if (RegExp(r'^\d+$').hasMatch(p)) {
        final asInt = int.tryParse(p);
        out.add(asInt == null ? p : asInt.toString());
      } else {
        out.add(p);
      }
    }
    return out.join(' ');
  }

  String? _suggestExistingId({
    required String importedName,
    required Map<String, Paddock> byMatchNorm,
    required Map<String, Paddock> bySimpleNorm,
  }) {
    final n1 = _normNameForMatch(importedName);
    if (n1.isNotEmpty) {
      final m = byMatchNorm[n1];
      if (m != null) return m.id;
    }
    final n2 = _normName(importedName);
    final m2 = bySimpleNorm[n2];
    return m2?.id;
  }

  Future<List<_MergeChoice>?> _reviewMergeChoices({
    required List<Paddock> existing,
  }) async {
    if (nameKey == null || areaKey == null) return null;
    if (features.isEmpty) return null;

    final byMatchNorm = <String, Paddock>{};
    final bySimpleNorm = <String, Paddock>{};
    for (final p in existing) {
      final k1 = _normNameForMatch(p.name);
      if (k1.isNotEmpty && !byMatchNorm.containsKey(k1)) byMatchNorm[k1] = p;
      final k2 = _normName(p.name);
      if (k2.isNotEmpty && !bySimpleNorm.containsKey(k2)) bySimpleNorm[k2] = p;
    }

    final initial = <_MergeChoice>[];
    for (int i = 0; i < features.length; i++) {
      final f = features[i];
      final props = (f['properties'] is Map)
          ? Map<String, dynamic>.from(f['properties'] as Map)
          : <String, dynamic>{};
      final geom = (f['geometry'] is Map)
          ? Map<String, dynamic>.from(f['geometry'] as Map)
          : null;
      if (geom == null) continue;
      final name = _asString(props[nameKey]);
      final area = _parseAreaHa(props[areaKey]);
      if (name.isEmpty) continue;
      if (area <= 0) continue;
      final polys = _extractOuterRings(geom);
      if (polys == null) continue;
      final suggested = _suggestExistingId(
        importedName: name,
        byMatchNorm: byMatchNorm,
        bySimpleNorm: bySimpleNorm,
      );
      initial.add(
        _MergeChoice(
          featureIndex: i,
          importedName: name,
          areaHa: area,
          selectedExistingId: suggested,
          overrideName: null,
        ),
      );
    }

    if (!mounted) return null;

    return await showDialog<List<_MergeChoice>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final items = initial.map((e) => e.copy()).toList();

        String? duplicateError() {
          final seen = <String, int>{};
          for (final it in items) {
            final id = it.selectedExistingId;
            if (id == null || id.isEmpty) continue;
            seen[id] = (seen[id] ?? 0) + 1;
          }
          final dup = seen.entries.where((e) => e.value > 1).toList();
          if (dup.isEmpty) return null;
          return 'A paddock has been matched more than once. Each imported paddock must match at most one existing paddock.';
        }

        return StatefulBuilder(
          builder: (ctx, setD) {
            final err = duplicateError();
            return AlertDialog(
              title: const Text('Review merge matches'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Confirm how each imported paddock should merge. You can fix name differences like 01 vs 1 here.',
                    ),
                    const SizedBox(height: 12),
                    if (err != null) ...[
                      Text(err, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                    ],
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, idx) {
                          final it = items[idx];

                          final ddItems = <DropdownMenuItem<String>>[
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Create new paddock'),
                            ),
                            ...existing.map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name),
                              ),
                            ),
                          ];

                          final ddValue = it.selectedExistingId ?? '';
                          final nameCtrl = TextEditingController(
                            text: (it.overrideName ?? it.importedName),
                          );

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Imported: ${it.importedName}  (${it.areaHa.toStringAsFixed(2)} ha)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Merge into',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: ddValue,
                                    items: ddItems,
                                    onChanged: (v) {
                                      setD(() {
                                        items[idx] = it.copyWith(
                                          selectedExistingId:
                                              (v == null || v.isEmpty)
                                              ? null
                                              : v,
                                        );
                                      });
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Paddock name (imported)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  setD(() {
                                    final t = v.trim();
                                    items[idx] = it.copyWith(
                                      overrideName: t.isEmpty ? null : t,
                                    );
                                  });
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: err != null
                      ? null
                      : () => Navigator.pop(ctx, items),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _promptMergeReplace() async {
    final existing = await storage.loadPaddocks();
    if (existing.isEmpty) {
      setState(() {
        mergeMode = false;
        overwriteNamesOnMerge = false;
      });
      return;
    }

    if (!mounted) return;

    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import paddocks'),
        content: const Text(
          'You already have paddocks on this phone. Do you want to replace them or merge by name?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Text('Replace'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Text('Merge'),
          ),
        ],
      ),
    );

    if (choice == null || choice == 0) return;

    if (choice == 1) {
      setState(() {
        mergeMode = false;
        overwriteNamesOnMerge = false;
      });
      return;
    }

    if (!mounted) return;

    final nameChoice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merge names'),
        content: const Text(
          'For matched paddocks, do you want to keep existing names on the phone or overwrite with the imported name?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Text('Keep existing'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );

    if (nameChoice == null || nameChoice == 0) return;

    setState(() {
      mergeMode = true;
      overwriteNamesOnMerge = (nameChoice == 2);
    });
  }

  // Returns a list of polygons. Each polygon is an outer ring only (holes ignored in v1).
  // Polygon: [ [ [lon,lat], ... ] ]
  // MultiPolygon: [ outerRing1, outerRing2, ... ]
  List<List<List<double>>>? _extractOuterRings(Map<String, dynamic> geometry) {
    final type = geometry['type'];
    final coords = geometry['coordinates'];
    if (type is! String || coords == null) return null;

    if (type == 'Polygon') {
      if (coords is! List) return null;
      if (coords.isEmpty) return null;
      final outer = coords.first;
      if (outer is! List) return null;
      final pts = <List<double>>[];
      for (final p in outer) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          pts.add(<double>[(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
        }
      }
      if (pts.length < 3) return null;
      return <List<List<double>>>[pts];
    }

    if (type == 'MultiPolygon') {
      if (coords is! List) return null;
      final out = <List<List<double>>>[];
      for (final poly in coords) {
        if (poly is! List || poly.isEmpty) continue;
        final outer = poly.first;
        if (outer is! List) continue;
        final pts = <List<double>>[];
        for (final p in outer) {
          if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
            pts.add(<double>[
              (p[0] as num).toDouble(),
              (p[1] as num).toDouble(),
            ]);
          }
        }
        if (pts.length >= 3) out.add(pts);
      }
      if (out.isEmpty) return null;
      return out;
    }

    return null;
  }

  Map<String, double> _bboxForPolys(List<List<List<double>>> polys) {
    double? minX;
    double? minY;
    double? maxX;
    double? maxY;

    for (final ring in polys) {
      for (final p in ring) {
        final x = p[0];
        final y = p[1];
        minX = (minX == null || x < minX) ? x : minX;
        minY = (minY == null || y < minY) ? y : minY;
        maxX = (maxX == null || x > maxX) ? x : maxX;
        maxY = (maxY == null || y > maxY) ? y : maxY;
      }
    }

    return {
      'minLon': minX ?? 0,
      'minLat': minY ?? 0,
      'maxLon': maxX ?? 0,
      'maxLat': maxY ?? 0,
    };
  }

  Future<void> _import() async {
    if (nameKey == null || areaKey == null) return;
    if (features.isEmpty) return;

    await _promptMergeReplace();
    if (mergeMode == null) return;

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final existing = await storage.loadPaddocks();

      List<_MergeChoice>? mergeChoices;
      if (mergeMode == true) {
        mergeChoices = await _reviewMergeChoices(existing: existing);
        if (mergeChoices == null) {
          setState(() => busy = false);
          return;
        }
      }

      final existingMaxOrder = existing.isEmpty
          ? 0
          : existing.map((p) => p.recordOrder).reduce((a, b) => a > b ? a : b);
      int nextOrder = existingMaxOrder + 1;

      final newPaddocks = <Paddock>[];
      final polygonsOut = <Map<String, dynamic>>[];

      final updatedExisting = <String, Paddock>{
        for (final p in existing) p.id: p,
      };

      final choiceByFeature = <int, _MergeChoice>{
        for (final c in (mergeChoices ?? const <_MergeChoice>[]))
          c.featureIndex: c,
      };

      for (int i = 0; i < features.length; i++) {
        final f = features[i];
        final props = (f['properties'] is Map)
            ? Map<String, dynamic>.from(f['properties'] as Map)
            : <String, dynamic>{};

        final geom = (f['geometry'] is Map)
            ? Map<String, dynamic>.from(f['geometry'] as Map)
            : null;
        if (geom == null) continue;

        final name = _asString(props[nameKey]);
        final area = _parseAreaHa(props[areaKey]);
        if (name.isEmpty) continue;
        if (area <= 0) continue;

        final polys = _extractOuterRings(geom);
        if (polys == null) continue;

        String paddockId;
        if (mergeMode == true) {
          final choice = choiceByFeature[i];
          final chosenExistingId = choice?.selectedExistingId;
          final chosenName = (choice?.overrideName ?? name).trim();

          if (chosenExistingId != null && chosenExistingId.isNotEmpty) {
            final match = existing.firstWhere((p) => p.id == chosenExistingId);
            paddockId = match.id;
            final newName = (overwriteNamesOnMerge == true)
                ? chosenName
                : match.name;
            updatedExisting[paddockId] = Paddock(
              id: match.id,
              name: newName,
              areaHa: area,
              recordOrder: match.recordOrder,
              includeInRotation: match.includeInRotation,
            );
          } else {
            paddockId = uuid.v4();
            newPaddocks.add(
              Paddock(
                id: paddockId,
                name: chosenName.isEmpty ? name : chosenName,
                areaHa: area,
                recordOrder: nextOrder++,
                includeInRotation: true,
              ),
            );
          }
        } else {
          paddockId = uuid.v4();
          newPaddocks.add(
            Paddock(
              id: paddockId,
              name: name,
              areaHa: area,
              recordOrder: nextOrder++,
              includeInRotation: true,
            ),
          );
        }

        polygonsOut.add({
          'paddockId': paddockId,
          'polys': polys,
          'bbox': _bboxForPolys(polys),
        });
      }

      if (polygonsOut.isEmpty) {
        throw Exception(
          'No valid paddock polygons found (check name/area fields and geometry types).',
        );
      }

      if (mergeMode == false) {
        // Replace mode: wipe paddocks and map.
        await storage.savePaddocks(newPaddocks);
      } else {
        final combined = <Paddock>[];
        combined.addAll(updatedExisting.values);
        combined.addAll(newPaddocks);
        combined.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));
        await storage.savePaddocks(combined);
      }

      // Save map data
      final now = DateTime.now().toIso8601String();
      await storage.saveFarmMapPolygons(polygonsOut);
      await storage.saveFarmMapImportMeta({
        'importedAt': now,
        'filename': picked?.name ?? '',
        'sourceType': sourceType ?? '',
      });

      // Store raw source for debugging/audit if available.
      if (picked?.path != null) {
        if ((picked?.extension ?? '').toLowerCase() == 'zip') {
          await storage.saveFarmMapSourceRaw('zip:${picked!.name}');
        } else {
          final text = await File(picked!.path!).readAsString();
          await storage.saveFarmMapSourceRaw(text);
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        busy = false;
        error = 'Import failed: $e';
      });
      return;
    }

    if (mounted) {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = picked != null;
    final canMap = features.isNotEmpty && keys.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Import paddocks + map')),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                const Text(
                  'Import paddocks + map geometry',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Supports GeoJSON (.geojson/.json) and Shapefile zip (.zip containing .shp + .shx + .dbf).\n\nThis imports paddock name, area (ha) and geometry. Recording order is managed in-app.',
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
                    'Found ${features.length} features',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  _dropdown(
                    label: 'Field to use as paddock name/number',
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
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (nameKey == null || areaKey == null)
                          ? null
                          : _import,
                      child: const Text(
                        'Import',
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
}

class _MergeChoice {
  final int featureIndex;
  final String importedName;
  final double areaHa;
  final String? selectedExistingId;
  final String? overrideName;

  const _MergeChoice({
    required this.featureIndex,
    required this.importedName,
    required this.areaHa,
    required this.selectedExistingId,
    required this.overrideName,
  });

  _MergeChoice copyWith({String? selectedExistingId, String? overrideName}) {
    return _MergeChoice(
      featureIndex: featureIndex,
      importedName: importedName,
      areaHa: areaHa,
      selectedExistingId: selectedExistingId,
      overrideName: overrideName,
    );
  }

  _MergeChoice copy() => copyWith(
    selectedExistingId: selectedExistingId,
    overrideName: overrideName,
  );
}
