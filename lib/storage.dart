import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class Storage {
  // -----------------------------
  // COLUMN CONSTANTS (UI expects these)
  // -----------------------------
  static const colPaddock = 'paddock';
  static const colArea = 'area';

  // -----------------------------
  // KEYS
  // -----------------------------
  static const _paddocksKey = 'paddocks';
  static const _measurementsKey = 'measurements';
  static const _grazingsKey = 'grazings';
  static const _modifiersKey = 'growth_modifiers';
  static const _notesKey = 'notes';

  // Settings keys
  static const _coverStepKey = 'cover_step';
  static const _noteBtn1Key = 'note_btn_1_title';
  static const _noteBtn2Key = 'note_btn_2_title';

  // -----------------------------
  // SETTINGS
  // -----------------------------
  Future<int> loadCoverStep() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getInt(_coverStepKey);
    if (v == null) return 50;
    return v.clamp(1, 500);
  }

  Future<void> saveCoverStep(int step) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_coverStepKey, step.clamp(1, 500));
  }

  Future<String> loadNoteButton1Title() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_noteBtn1Key) ?? 'Weeds';
  }

  Future<String> loadNoteButton2Title() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_noteBtn2Key) ?? 'Water leak';
  }

  Future<void> saveNoteButton1Title(String title) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_noteBtn1Key, title.trim().isEmpty ? 'Weeds' : title.trim());
  }

  Future<void> saveNoteButton2Title(String title) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_noteBtn2Key, title.trim().isEmpty ? 'Water leak' : title.trim());
  }

  // -----------------------------
  // PADDOCKS
  // -----------------------------
  Future<List<Paddock>> loadPaddocks() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_paddocksKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Paddock.fromMap(e)).toList();
  }

  Future<void> savePaddocks(List<Paddock> paddocks) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _paddocksKey,
      jsonEncode(paddocks.map((p) => p.toMap()).toList()),
    );
  }

  Future<bool> isPaddockIncludedInRotation(String paddockId) async {
    final paddocks = await loadPaddocks();
    final p = paddocks.where((x) => x.id == paddockId).toList();
    if (p.isEmpty) return true;
    return p.first.includeInRotation;
  }

  Future<Set<String>> _includedPaddockIds() async {
    final paddocks = await loadPaddocks();
    return paddocks.where((p) => p.includeInRotation).map((p) => p.id).toSet();
  }

  // -----------------------------
  // MEASUREMENTS
  // -----------------------------
  Future<List<Measurement>> _loadMeasurements() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_measurementsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Measurement.fromMap(e)).toList();
  }

  Future<void> _saveMeasurements(List<Measurement> ms) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _measurementsKey,
      jsonEncode(ms.map((m) => m.toMap()).toList()),
    );
  }

  /// KPIs helper: raw load all
  Future<List<Measurement>> loadAllMeasurements() async => _loadMeasurements();

  Future<List<Measurement>> measurementsForPaddock(String paddockId) async {
    final all = await _loadMeasurements();
    return all.where((m) => m.paddockId == paddockId).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  Future<Measurement?> lastMeasurementForPaddock(String paddockId) async {
    final list = await measurementsForPaddock(paddockId);
    return list.isEmpty ? null : list.first;
  }

  /// Implicit anchor = last measurement OR last grazing residual
  Future<_Anchor?> latestAnchorForPaddock(String paddockId) async {
    final m = await lastMeasurementForPaddock(paddockId);
    final g = await _lastGrazingForPaddock(paddockId);

    if (m == null && g == null) return null;
    if (m != null && g == null) return _Anchor(m.at, m.cover);
    if (g != null && m == null) return _Anchor(g.at, g.residual);

    return m!.at.isAfter(g!.at) ? _Anchor(m.at, m.cover) : _Anchor(g.at, g.residual);
  }

  /// Overwrites measurement for today if present
  Future<void> upsertMeasurementForToday(Measurement m) async {
    final all = await _loadMeasurements();
    final today = DateTime.now();

    all.removeWhere((x) => x.paddockId == m.paddockId && _sameDay(x.at, today));
    all.add(m);
    await _saveMeasurements(all);

    // Only learn modifiers for included paddocks
    final included = await isPaddockIncludedInRotation(m.paddockId);
    if (included) {
      await _updateGrowthModifierFromMeasurement(m);
    }
  }

  // -----------------------------
  // NOTES
  // -----------------------------
  Future<List<NoteEntry>> _loadNotes() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_notesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => NoteEntry.fromMap(e)).toList();
  }

  Future<void> _saveNotes(List<NoteEntry> ns) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_notesKey, jsonEncode(ns.map((n) => n.toMap()).toList()));
  }

  Future<void> appendNote(NoteEntry n) async {
    final all = await _loadNotes();
    all.add(n);
    await _saveNotes(all);
  }

  Future<List<NoteEntry>> notesForPaddock(String paddockId) async {
    final all = await _loadNotes();
    return all.where((n) => n.paddockId == paddockId).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  Future<NoteEntry?> lastNoteForPaddock(String paddockId) async {
    final list = await notesForPaddock(paddockId);
    return list.isEmpty ? null : list.first;
  }

  // -----------------------------
  // GRAZINGS
  // -----------------------------
  Future<List<Grazing>> _loadGrazings() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_grazingsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Grazing.fromMap(e)).toList();
  }

  /// KPIs helper: raw load all
  Future<List<Grazing>> loadAllGrazings() async => _loadGrazings();

  Future<void> appendGrazing(Grazing g) async {
    final all = await _loadGrazings();
    all.add(g);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _grazingsKey,
      jsonEncode(all.map((x) => x.toMap()).toList()),
    );
  }

  Future<Grazing?> _lastGrazingForPaddock(String paddockId) async {
    final g = await _loadGrazings();
    final list = g.where((x) => x.paddockId == paddockId).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return list.isEmpty ? null : list.first;
  }

  Future<bool> isCurrentlyGrazed(String paddockId) async {
    final g = await _lastGrazingForPaddock(paddockId);
    if (g == null) return false;
    return DateTime.now().difference(g.at).inDays < 3;
  }

  Future<int> undoLatestGrazingsForPaddocks(
      Set<String> paddockIds, {
        required int withinHours,
      }) async {
    final all = await _loadGrazings();
    final cutoff = DateTime.now().subtract(Duration(hours: withinHours));

    final before = all.length;

    all.removeWhere((g) => paddockIds.contains(g.paddockId) && g.at.isAfter(cutoff));

    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _grazingsKey,
      jsonEncode(all.map((x) => x.toMap()).toList()),
    );

    return before - all.length;
  }

  Future<List<Grazing>> grazingsForPaddock(String paddockId) async {
    final all = await _loadGrazings();
    return all.where((g) => g.paddockId == paddockId).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  // -----------------------------
  // FARM GROWTH (MEASURED)
  // Excludes paddocks not included in rotation.
  // -----------------------------
  Future<double> computeFarmGrowthKgDmPerHaPerDay() async {
    final msAll = await _loadMeasurements();
    if (msAll.length < 2) return 0;

    final includedIds = await _includedPaddockIds();
    final ms = msAll.where((m) => includedIds.contains(m.paddockId)).toList();
    if (ms.length < 2) return 0;

    ms.sort((a, b) => a.at.compareTo(b.at));

    final last = ms.last;
    final prev = ms[ms.length - 2];

    final days = last.at.difference(prev.at).inDays;
    if (days <= 0) return 0;

    return (last.cover - prev.cover) / days;
  }

  // -----------------------------
  // GROWTH MODIFIERS (AUTO)
  // -----------------------------
  Future<Map<String, double>> loadGrowthModifiers() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_modifiersKey);
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return m.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  Future<void> saveGrowthModifiers(Map<String, double> m) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_modifiersKey, jsonEncode(m));
  }

  Future<void> _updateGrowthModifierFromMeasurement(Measurement m) async {
    final farmGrowth = await computeFarmGrowthKgDmPerHaPerDay();
    if (farmGrowth.abs() < 1) return;

    final prev = await lastMeasurementForPaddock(m.paddockId);
    if (prev == null) return;

    final days = m.at.difference(prev.at).inDays;
    if (days < 2) return;

    if (await paddockGrazedBetween(m.paddockId, prev.at, m.at)) return;

    final error = m.cover - m.predictedCoverAtEntry;
    final deltaPerDay = error / days;
    final modifierDelta = deltaPerDay / farmGrowth;

    final mods = await loadGrowthModifiers();
    final old = mods[m.paddockId] ?? 1.0;

    // EMA smoothing
    final learned = 1 + modifierDelta;
    final updated = old * 0.9 + learned * 0.1;

    mods[m.paddockId] = updated.clamp(0.7, 1.3);
    await saveGrowthModifiers(mods);
  }

  // -----------------------------
  // HISTORY / RANKING HELPERS
  // -----------------------------
  Future<int> annualHarvestKgDmForPaddock(String paddockId) async {
    final g = await _loadGrazings();
    final year = DateTime.now().year;
    return g.where((x) => x.paddockId == paddockId && x.at.year == year).fold<int>(
      0,
          (a, b) => a + b.harvestedKgDm,
    );
  }

  Future<Map<String, int>> annualHarvestAllPaddocksKgDm() async {
    final g = await _loadGrazings();
    final year = DateTime.now().year;
    final out = <String, int>{};

    for (final x in g.where((e) => e.at.year == year)) {
      out[x.paddockId] = (out[x.paddockId] ?? 0) + x.harvestedKgDm;
    }
    return out;
  }

  // -----------------------------
  // BACKUP / RESTORE (ALL PREFS)
  // -----------------------------
  Future<String> exportBackupJson() async {
    final sp = await SharedPreferences.getInstance();
    final keys = sp.getKeys().toList()..sort();

    final items = <String, dynamic>{};
    for (final k in keys) {
      final v = sp.get(k);
      items[k] = _encodePrefValue(v);
    }

    final backup = <String, dynamic>{
      'schema': 1,
      'app': 'PastureWalk',
      'exportedAt': DateTime.now().toIso8601String(),
      'prefs': items,
    };

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  Future<void> restoreBackupJson(String jsonText) async {
    final decoded = jsonDecode(jsonText);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid backup file.');
    }
    final prefs = decoded['prefs'];
    if (prefs is! Map<String, dynamic>) {
      throw Exception('Invalid backup file (missing prefs).');
    }

    final sp = await SharedPreferences.getInstance();

    // Wipe current state first
    await sp.clear();

    // Restore all keys
    for (final entry in prefs.entries) {
      final key = entry.key;
      final encoded = entry.value;
      await _applyPrefValue(sp, key, encoded);
    }
  }

  dynamic _encodePrefValue(dynamic v) {
    if (v == null) return {'t': 'null'};
    if (v is bool) return {'t': 'bool', 'v': v};
    if (v is int) return {'t': 'int', 'v': v};
    if (v is double) return {'t': 'double', 'v': v};
    if (v is String) return {'t': 'string', 'v': v};
    if (v is List<String>) return {'t': 'stringList', 'v': v};
    return {'t': 'string', 'v': v.toString()};
  }

  Future<void> _applyPrefValue(SharedPreferences sp, String key, dynamic encoded) async {
    if (encoded is Map<String, dynamic>) {
      final t = encoded['t'];
      final v = encoded['v'];

      switch (t) {
        case 'null':
          return;
        case 'bool':
          await sp.setBool(key, (v as bool?) ?? false);
          return;
        case 'int':
          await sp.setInt(key, (v as num?)?.toInt() ?? 0);
          return;
        case 'double':
          await sp.setDouble(key, (v as num?)?.toDouble() ?? 0.0);
          return;
        case 'string':
          await sp.setString(key, (v as String?) ?? '');
          return;
        case 'stringList':
          final list = (v as List?)?.map((e) => e.toString()).toList() ?? <String>[];
          await sp.setStringList(key, list);
          return;
        default:
          await sp.setString(key, encoded.toString());
          return;
      }
    }

    // Fallback for old backups
    if (encoded is bool) {
      await sp.setBool(key, encoded);
    } else if (encoded is int) {
      await sp.setInt(key, encoded);
    } else if (encoded is double) {
      await sp.setDouble(key, encoded);
    } else if (encoded is String) {
      await sp.setString(key, encoded);
    } else if (encoded is List) {
      await sp.setStringList(key, encoded.map((e) => e.toString()).toList());
    } else {
      await sp.setString(key, encoded.toString());
    }
  }

  // -----------------------------
  // HELPERS
  // -----------------------------
  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<bool> paddockGrazedBetween(
      String paddockId,
      DateTime a,
      DateTime b,
      ) async {
    final g = await _loadGrazings();
    return g.any((x) => x.paddockId == paddockId && x.at.isAfter(a) && x.at.isBefore(b));
  }
}

class _Anchor {
  final DateTime at;
  final int coverKgDmHa;

  _Anchor(this.at, this.coverKgDmHa);
}
