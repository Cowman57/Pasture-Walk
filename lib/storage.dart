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
  static const _hiddenSummaryNoteIdsKey = 'hidden_summary_note_ids';

  // Manual override keys
  static const _manualFarmGrowthKey = 'manual_farm_growth_kgdm_ha_day';

  // Settings keys
  static const _coverStepKey = 'cover_step';
  static const _noteBtn1Key = 'note_btn_1_title';
  static const _noteBtn2Key = 'note_btn_2_title';
  static const _feedWedgePreTargetKey = 'feed_wedge_pre_target';
  static const _feedWedgePostResidualTargetKey =
      'feed_wedge_post_residual_target';
  static const _areaGrazedPerDayHaKey = 'area_grazed_per_day_ha';
  static const _coverTrendTimescaleKey = 'cover_trend_timescale';
  static const _cowCountKey = 'cow_count';

  // -----------------------------
  // SETTINGS
  // -----------------------------
  Future<int> loadCoverStep() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getInt(_coverStepKey);
    if (v == 100) return 100;
    return 50; // default
  }

  Future<void> saveCoverStep(int step) async {
    final sp = await SharedPreferences.getInstance();
    final safe = (step == 100) ? 100 : 50;
    await sp.setInt(_coverStepKey, safe);
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
    await sp.setString(
      _noteBtn1Key,
      title.trim().isEmpty ? 'Weeds' : title.trim(),
    );
  }

  Future<void> saveNoteButton2Title(String title) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _noteBtn2Key,
      title.trim().isEmpty ? 'Water leak' : title.trim(),
    );
  }

  Future<int> loadFeedWedgePreGrazingTarget() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_feedWedgePreTargetKey) ?? 2800;
  }

  Future<void> saveFeedWedgePreGrazingTarget(int v) async {
    final sp = await SharedPreferences.getInstance();
    final safe = v.clamp(0, 999999999);
    await sp.setInt(_feedWedgePreTargetKey, safe);
  }

  Future<int> loadFeedWedgePostGrazingResidualTarget() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_feedWedgePostResidualTargetKey) ?? 1500;
  }

  Future<void> saveFeedWedgePostGrazingResidualTarget(int v) async {
    final sp = await SharedPreferences.getInstance();
    final safe = v.clamp(0, 999999999);
    await sp.setInt(_feedWedgePostResidualTargetKey, safe);
  }

  Future<double> loadAreaGrazedPerDayHa() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getDouble(_areaGrazedPerDayHaKey) ?? 0.0;
  }

  Future<void> saveAreaGrazedPerDayHa(double v) async {
    final sp = await SharedPreferences.getInstance();
    final safe = v.isFinite ? v : 0.0;
    await sp.setDouble(_areaGrazedPerDayHaKey, safe.clamp(0.0, 999999999.0));
  }

  Future<String> loadCoverTrendTimescale() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_coverTrendTimescaleKey);
    if (v == 'week' || v == 'month') return v!;
    return 'day';
  }

  Future<void> saveCoverTrendTimescale(String v) async {
    final sp = await SharedPreferences.getInstance();
    final safe = (v == 'week' || v == 'month') ? v : 'day';
    await sp.setString(_coverTrendTimescaleKey, safe);
  }

  Future<int> loadCowCount() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getInt(_cowCountKey);
    return (v == null || v < 0) ? 0 : v;
  }

  Future<void> saveCowCount(int v) async {
    final sp = await SharedPreferences.getInstance();
    final safe = v.clamp(0, 999999999);
    await sp.setInt(_cowCountKey, safe);
  }

  Future<double?> loadManualFarmGrowthKgDmPerHaPerDay() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getDouble(_manualFarmGrowthKey);
    return v;
  }

  Future<void> saveManualFarmGrowthKgDmPerHaPerDay(double v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_manualFarmGrowthKey, v);
  }

  Future<void> clearManualFarmGrowthKgDmPerHaPerDay() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_manualFarmGrowthKey);
  }

  Future<double> effectiveFarmGrowthKgDmPerHaPerDay() async {
    final manual = await loadManualFarmGrowthKgDmPerHaPerDay();
    if (manual != null) return manual;
    return computeFarmGrowthKgDmPerHaPerDay();
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

  Future<Measurement?> _previousMeasurementBefore(
    String paddockId,
    DateTime at,
  ) async {
    final all = await _loadMeasurements();
    final list =
        all.where((m) => m.paddockId == paddockId && m.at.isBefore(at)).toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    return list.isEmpty ? null : list.first;
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

  /// Helper: raw load all notes
  Future<List<NoteEntry>> loadAllNotes() async => _loadNotes();

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
  Future<Anchor?> latestAnchorForPaddock(String paddockId) async {
    return latestAnchorForPaddockAsOf(paddockId, DateTime.now());
  }

  Future<Anchor?> latestAnchorForPaddockAsOf(
    String paddockId,
    DateTime asOf,
  ) async {
    final allM = await measurementsForPaddock(paddockId);
    final m = allM.where((x) => !x.at.isAfter(asOf)).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final m0 = m.isEmpty ? null : m.first;

    final g0 = await _lastGrazingForPaddockAsOf(paddockId, asOf);

    if (m0 == null && g0 == null) return null;
    if (m0 != null && g0 == null) return Anchor(m0.at, m0.cover);
    if (g0 != null && m0 == null) return Anchor(g0.at, g0.residual);

    return m0!.at.isAfter(g0!.at)
        ? Anchor(m0.at, m0.cover)
        : Anchor(g0.at, g0.residual);
  }

  /// Overwrites measurement for today if present
  Future<void> upsertMeasurementForToday(Measurement m) async {
    // ✅ capture previous measurement BEFORE we overwrite today
    final prev = await _previousMeasurementBefore(m.paddockId, m.at);

    final all = await _loadMeasurements();
    final today = DateTime.now();

    all.removeWhere((x) => x.paddockId == m.paddockId && _sameDay(x.at, today));
    all.add(m);
    await _saveMeasurements(all);

    // Growth modifiers are no longer used.
    // Kept `prev` capture for potential future features.
    // ignore: unused_local_variable
    final _ = prev;
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
    await sp.setString(
      _notesKey,
      jsonEncode(ns.map((n) => n.toMap()).toList()),
    );
  }

  Future<void> appendNote(NoteEntry n) async {
    final all = await _loadNotes();
    all.add(n);
    await _saveNotes(all);
  }

  Future<Set<String>> loadHiddenSummaryNoteIds() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_hiddenSummaryNoteIdsKey) ?? <String>[];
    return list.map((e) => e.toString()).toSet();
  }

  Future<void> hideSummaryNoteId(String noteId) async {
    final sp = await SharedPreferences.getInstance();
    final cur = sp.getStringList(_hiddenSummaryNoteIdsKey) ?? <String>[];
    if (cur.contains(noteId)) return;
    final next = [...cur, noteId];
    await sp.setStringList(_hiddenSummaryNoteIdsKey, next);
  }

  Future<void> unhideSummaryNoteId(String noteId) async {
    final sp = await SharedPreferences.getInstance();
    final cur = sp.getStringList(_hiddenSummaryNoteIdsKey) ?? <String>[];
    final next = cur.where((x) => x != noteId).toList();
    await sp.setStringList(_hiddenSummaryNoteIdsKey, next);
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

  Future<Grazing?> _lastGrazingForPaddockAsOf(
    String paddockId,
    DateTime asOf,
  ) async {
    final g = await _loadGrazings();
    final list =
        g.where((x) => x.paddockId == paddockId && !x.at.isAfter(asOf)).toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    return list.isEmpty ? null : list.first;
  }

  Future<bool> isCurrentlyGrazed(String paddockId) async {
    final g = await _lastGrazingForPaddockAsOf(paddockId, DateTime.now());
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

    all.removeWhere(
      (g) => paddockIds.contains(g.paddockId) && g.at.isAfter(cutoff),
    );

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

    // Only included paddocks
    final includedIds = await _includedPaddockIds();
    final ms = msAll.where((m) => includedIds.contains(m.paddockId)).toList();
    if (ms.length < 2) return 0;

    // Group measurements by paddock
    final byPdk = <String, List<Measurement>>{};
    for (final m in ms) {
      (byPdk[m.paddockId] ??= []).add(m);
    }

    final rates = <double>[];

    // For each paddock: find the most recent valid measurement-to-measurement segment
    // where NO grazing occurred between the two measurements.
    for (final entry in byPdk.entries) {
      final paddockId = entry.key;
      final list = entry.value..sort((a, b) => a.at.compareTo(b.at));
      if (list.length < 2) continue;

      // Start from the latest measurement and walk backwards until we find a valid "prev"
      final cur = list.last;

      for (int i = list.length - 2; i >= 0; i--) {
        final prev = list[i];

        final daysDiff = cur.at.difference(prev.at).inDays;
        if (daysDiff <= 0) continue;

        // Skip segments that include a grazing event (resets cover)
        final grazedBetween = await paddockGrazedBetween(
          paddockId,
          prev.at,
          cur.at,
        );
        if (grazedBetween) continue;

        final rate = (cur.cover - prev.cover) / daysDiff;

        // Ignore paddocks that have decreased in cover (often grazed / not representative).
        if (rate <= 0) continue;

        rates.add(rate);
        break; // only use most recent valid segment for this paddock
      }
    }

    if (rates.isEmpty) return 0;

    final avg = rates.reduce((a, b) => a + b) / rates.length;

    // If you never want negative farm growth in prediction, clamp it here:
    // return avg < 0 ? 0 : avg;
    return avg;
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

  // HISTORY / RANKING HELPERS
  // -----------------------------
  Future<int> annualHarvestKgDmForPaddock(String paddockId) async {
    final g = await _loadGrazings();
    final year = DateTime.now().year;
    return g
        .where((x) => x.paddockId == paddockId && x.at.year == year)
        .fold<int>(0, (a, b) => a + b.harvestedKgDm);
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

  Future<void> _applyPrefValue(
    SharedPreferences sp,
    String key,
    dynamic encoded,
  ) async {
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
          final list =
              (v as List?)?.map((e) => e.toString()).toList() ?? <String>[];
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
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<bool> paddockGrazedBetween(
    String paddockId,
    DateTime a,
    DateTime b,
  ) async {
    final g = await _loadGrazings();
    return g.any(
      (x) => x.paddockId == paddockId && x.at.isAfter(a) && x.at.isBefore(b),
    );
  }
}

class Anchor {
  final DateTime at;
  final int coverKgDmHa;

  Anchor(this.at, this.coverKgDmHa);
}
