import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'utils.dart';

/// Effective pre-graze and post-graze (residual) targets, shared by every
/// figure that budgets feed — the feed wedge and the cover trend.
typedef PrePostTargets = ({int pre, int post, bool overridden});

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

  static const _silageCutsKey = 'silage_cuts';
  static const _grazingSlotsKey = 'grazing_slots_json';
  static const _calendarVisibleColsKey = 'calendar_visible_cols';

  // v2.0.0 Map/GPS keys
  static const _gpsMeasuringEnabledKey = 'gps_measuring_enabled';
  static const _farmMapSourceRawKey = 'farm_map_source_raw';
  static const _farmMapPolygonsKey = 'farm_map_polygons_v1';
  static const _farmMapImportMetaKey = 'farm_map_import_meta_v1';

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
  static const _herdsKey = 'herds_json';
  static const _herdTargetHistoryKey = 'herd_target_history_json';

  // -----------------------------
  // SETTINGS
  // -----------------------------
  Future<bool> loadGpsMeasuringEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_gpsMeasuringEnabledKey) ?? false;
  }

  Future<void> saveGpsMeasuringEnabled(bool enabled) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_gpsMeasuringEnabledKey, enabled);
  }

  Future<String?> loadFarmMapSourceRaw() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_farmMapSourceRawKey);
  }

  Future<void> saveFarmMapSourceRaw(String raw) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_farmMapSourceRawKey, raw);
  }

  Future<void> clearFarmMap() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_farmMapSourceRawKey);
    await sp.remove(_farmMapPolygonsKey);
    await sp.remove(_farmMapImportMetaKey);
  }

  Future<List<Map<String, dynamic>>> loadFarmMapPolygons() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_farmMapPolygonsKey);
    if (raw == null) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> saveFarmMapPolygons(List<Map<String, dynamic>> polys) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_farmMapPolygonsKey, jsonEncode(polys));
  }

  Future<Map<String, dynamic>?> loadFarmMapImportMeta() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_farmMapImportMetaKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> saveFarmMapImportMeta(Map<String, dynamic> meta) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_farmMapImportMetaKey, jsonEncode(meta));
  }

  Future<bool> hasFarmMap() async {
    final sp = await SharedPreferences.getInstance();
    return sp.containsKey(_farmMapPolygonsKey);
  }

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

  /// Manual feed-wedge override; null means use auto avg from recent grazings.
  Future<int?> loadFeedWedgePreGrazingOverride() async {
    final sp = await SharedPreferences.getInstance();
    if (!sp.containsKey(_feedWedgePreTargetKey)) return null;
    return sp.getInt(_feedWedgePreTargetKey);
  }

  Future<void> saveFeedWedgePreGrazingTarget(int v) async {
    final sp = await SharedPreferences.getInstance();
    final safe = v.clamp(0, 999999999);
    await sp.setInt(_feedWedgePreTargetKey, safe);
  }

  Future<void> clearFeedWedgePreGrazingOverride() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_feedWedgePreTargetKey);
  }

  /// Manual feed-wedge override; null means use auto avg from recent grazings.
  Future<int?> loadFeedWedgePostGrazingResidualOverride() async {
    final sp = await SharedPreferences.getInstance();
    if (!sp.containsKey(_feedWedgePostResidualTargetKey)) return null;
    return sp.getInt(_feedWedgePostResidualTargetKey);
  }

  Future<void> saveFeedWedgePostGrazingResidualTarget(int v) async {
    final sp = await SharedPreferences.getInstance();
    final safe = v.clamp(0, 999999999);
    await sp.setInt(_feedWedgePostResidualTargetKey, safe);
  }

  Future<void> clearFeedWedgePostGrazingResidualOverride() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_feedWedgePostResidualTargetKey);
  }

  /// Average preCover / residual from past grazings in the last [days] days
  /// for [includedPaddockIds]. Returns nulls when there are no matching events.
  Future<({int? avgPre, int? avgPost, int count})> avgGrazingPrePostLastDays({
    required int days,
    required Set<String> includedPaddockIds,
  }) async {
    final now = DateTime.now();
    final since = now.subtract(Duration(days: days));
    final gs = await loadAllGrazings();
    final recent = gs
        .where(
          (g) =>
              includedPaddockIds.contains(g.paddockId) &&
              !g.at.isAfter(now) &&
              !g.at.isBefore(since),
        )
        .toList();
    if (recent.isEmpty) {
      return (avgPre: null, avgPost: null, count: 0);
    }
    final avgPre =
        (recent.map((g) => g.preCover).reduce((a, b) => a + b) / recent.length)
            .round();
    final avgPost =
        (recent.map((g) => g.residual).reduce((a, b) => a + b) / recent.length)
            .round();
    return (avgPre: avgPre, avgPost: avgPost, count: recent.length);
  }

  Future<double> loadAreaGrazedPerDayHa() async {
    final herds = await loadHerds();
    return totalAreaGrazedPerDayHa(herds);
  }

  Future<void> saveAreaGrazedPerDayHa(double v) async {
    // Legacy single-value write: keep first herd (or create Milkers) in sync.
    final safe = (v.isFinite ? v : 0.0).clamp(0.0, 999999999.0);
    final herds = await loadHerds();
    if (herds.isEmpty) {
      await saveHerds([
        Herd(
          id: 'herd_milkers',
          name: 'Milkers',
          cowCount: await loadCowCount(),
          areaGrazedPerDayHa: safe,
        ),
      ]);
      return;
    }
    final updated = [...herds];
    updated[0] = updated[0].copyWith(areaGrazedPerDayHa: safe);
    await saveHerds(updated);
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
    final herds = await loadHerds();
    if (herds.isEmpty) {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getInt(_cowCountKey);
      return (v == null || v < 0) ? 0 : v;
    }
    return herds.fold<int>(0, (sum, h) => sum + h.cowCount);
  }

  Future<void> saveCowCount(int v) async {
    final safe = v.clamp(0, 999999999);
    final herds = await loadHerds();
    if (herds.isEmpty) {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_cowCountKey, safe);
      return;
    }
    final updated = [...herds];
    updated[0] = updated[0].copyWith(cowCount: safe);
    await saveHerds(updated);
  }

  /// Named herds with per-herd cow count and area grazed/day.
  /// Migrates once from legacy single cow_count + area_grazed_per_day_ha.
  Future<List<Herd>> loadHerds() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_herdsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        final herds = list
            .whereType<Map>()
            .map((e) => Herd.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        if (herds.isNotEmpty) return herds;
      } catch (_) {
        // fall through to migrate
      }
    }

    final legacyCows = sp.getInt(_cowCountKey) ?? 0;
    final legacyArea = sp.getDouble(_areaGrazedPerDayHaKey) ?? 0.0;
    final migrated = [
      Herd(
        id: 'herd_milkers',
        name: 'Milkers',
        cowCount: legacyCows < 0 ? 0 : legacyCows,
        areaGrazedPerDayHa: legacyArea.isFinite
            ? legacyArea.clamp(0.0, 999999999.0)
            : 0.0,
      ),
    ];
    await saveHerds(migrated);
    return migrated;
  }

  Future<void> saveHerds(List<Herd> herds) async {
    final sp = await SharedPreferences.getInstance();
    final cleaned = herds
        .map(
          (h) => Herd(
            id: h.id.trim().isEmpty
                ? 'herd_${DateTime.now().millisecondsSinceEpoch}'
                : h.id,
            name: h.name.trim().isEmpty ? 'Herd' : h.name.trim(),
            cowCount: h.cowCount.clamp(0, 999999999),
            areaGrazedPerDayHa: h.areaGrazedPerDayHa.isFinite
                ? h.areaGrazedPerDayHa.clamp(0.0, 999999999.0)
                : 0.0,
            supplementKgDmPerCowPerDay: h.supplementKgDmPerCowPerDay.isFinite
                ? h.supplementKgDmPerCowPerDay.clamp(0.0, 999999999.0)
                : 0.0,
          ),
        )
        .toList();
    await sp.setString(
      _herdsKey,
      jsonEncode(cleaned.map((h) => h.toMap()).toList()),
    );
    await _recordHerdTargetIfNeeded(totalAreaGrazedPerDayHa(cleaned));
  }

  static double totalAreaGrazedPerDayHa(List<Herd> herds) {
    return herds.fold<double>(0.0, (sum, h) => sum + h.areaGrazedPerDayHa);
  }

  // -----------------------------
  // GRAZING PLAN SLOTS
  // -----------------------------
  Future<List<GrazingSlot>> loadGrazingSlots() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_grazingSlotsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final out = list
          .whereType<Map>()
          .map((e) => GrazingSlot.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      out.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveGrazingSlots(List<GrazingSlot> slots) async {
    final sp = await SharedPreferences.getInstance();
    final cleaned = [
      for (var i = 0; i < slots.length; i++)
        slots[i].copyWith(sortOrder: i),
    ];
    await sp.setString(
      _grazingSlotsKey,
      jsonEncode(cleaned.map((s) => s.toMap()).toList()),
    );
  }

  Future<List<GrazingSlot>> slotsForHerd(String herdId) async {
    final all = await loadGrazingSlots();
    return all.where((s) => s.herdId == herdId).toList();
  }

  // Planner column-width zoom (number of visible break columns).
  Future<int?> loadCalendarVisibleCols() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_calendarVisibleColsKey);
  }

  Future<void> saveCalendarVisibleCols(int v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_calendarVisibleColsKey, v.clamp(1, 12));
  }

  Future<List<HerdTargetSnapshot>> loadHerdTargetHistory() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_herdTargetHistoryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final out = list
          .whereType<Map>()
          .map((e) => HerdTargetSnapshot.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      out.sort((a, b) => a.at.compareTo(b.at));
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveHerdTargetHistory(List<HerdTargetSnapshot> history) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _herdTargetHistoryKey,
      jsonEncode(history.map((e) => e.toMap()).toList()),
    );
  }

  /// Records target when total herd ha/day changes. Same-day edits replace the
  /// last snapshot for that calendar day so the chart has one step per day.
  Future<void> _recordHerdTargetIfNeeded(double targetHaDay) async {
    final safe = targetHaDay.isFinite
        ? targetHaDay.clamp(0.0, 999999999.0)
        : 0.0;
    final history = await loadHerdTargetHistory();
    final now = DateTime.now();
    if (history.isEmpty) {
      await _saveHerdTargetHistory([
        HerdTargetSnapshot(at: now, targetHaDay: safe),
      ]);
      return;
    }
    final last = history.last;
    if ((last.targetHaDay - safe).abs() < 1e-9) return;

    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(last.at.year, last.at.month, last.at.day);
    if (lastDay == today) {
      history[history.length - 1] =
          HerdTargetSnapshot(at: now, targetHaDay: safe);
    } else {
      history.add(HerdTargetSnapshot(at: now, targetHaDay: safe));
    }
    await _saveHerdTargetHistory(history);
  }

  /// Target in effect on [day]: latest snapshot at or before that day.
  /// Days before the first snapshot use the first known value.
  static double targetHaDayOn(
    List<HerdTargetSnapshot> history,
    DateTime day, {
    required double fallback,
  }) {
    if (history.isEmpty) return fallback;
    final d = DateTime(day.year, day.month, day.day);
    HerdTargetSnapshot? best;
    for (final s in history) {
      final sd = DateTime(s.at.year, s.at.month, s.at.day);
      if (sd.isAfter(d)) break;
      best = s;
    }
    return best?.targetHaDay ?? history.first.targetHaDay;
  }

  /// Ensures history exists (seeds current herds total if empty).
  Future<List<HerdTargetSnapshot>> ensureHerdTargetHistory() async {
    var history = await loadHerdTargetHistory();
    if (history.isNotEmpty) return history;
    final herds = await loadHerds();
    // loadHerds may migrate via saveHerds and seed history.
    history = await loadHerdTargetHistory();
    if (history.isNotEmpty) return history;
    final total = totalAreaGrazedPerDayHa(herds);
    history = [HerdTargetSnapshot(at: DateTime.now(), targetHaDay: total)];
    await _saveHerdTargetHistory(history);
    return history;
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
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Paddock.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
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
    return paddocks.where((p) => p.includeInRotation || p.isSilage).map((p) => p.id).toSet();
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
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Measurement.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
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

  /// Same result as [lastMeasurementForPaddock] but scans [all] in memory (batch use).
  static Measurement? latestMeasurementFromList(
    List<Measurement> all,
    String paddockId,
  ) {
    Measurement? best;
    for (final m in all) {
      if (m.paddockId != paddockId) continue;
      if (best == null || m.at.isAfter(best.at)) best = m;
    }
    return best;
  }

  /// Latest measurement strictly before [day]'s calendar date (excludes same-day).
  static Measurement? latestMeasurementBeforeDay(
    List<Measurement> all,
    String paddockId,
    DateTime day,
  ) {
    final dayStart = DateTime(day.year, day.month, day.day);
    Measurement? best;
    for (final m in all) {
      if (m.paddockId != paddockId) continue;
      if (!m.at.isBefore(dayStart)) continue;
      if (best == null || m.at.isAfter(best.at)) best = m;
    }
    return best;
  }

  // -----------------------------
  // FARMING DAY (05:00 ROLLOVER)
  // -----------------------------

  /// The hour at which the farm clicks over to a new day. A grazing planned for
  /// a day anchors the paddock at that day's residual, and one day of growth is
  /// added, all at this one point — so predictions change once per day instead
  /// of whenever a timestamp happens to land after a measurement.
  static const int dayRolloverHour = 5;

  /// The farming day [t] belongs to (times before [dayRolloverHour] belong to
  /// the previous day).
  static DateTime farmingDay(DateTime t) {
    final shifted = t.subtract(const Duration(hours: dayRolloverHour));
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  /// Whole farming days between [from] and [to] (UTC diff, so DST-safe).
  static int farmingDaysBetween(DateTime from, DateTime to) {
    final a = farmingDay(from);
    final b = farmingDay(to);
    return DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;
  }

  /// Same rules as [latestAnchorForPaddockAsOf] using pre-loaded lists (batch use).
  static Anchor? latestAnchorFromLists(
    List<Measurement> allMeasurements,
    List<Grazing> allGrazings,
    List<SilageCut> allSilageCuts,
    String paddockId,
    DateTime asOf,
  ) {
    Measurement? m0;
    for (final m in allMeasurements) {
      if (m.paddockId != paddockId || m.at.isAfter(asOf)) continue;
      if (m0 == null || m.at.isAfter(m0.at)) m0 = m;
    }
    
    Grazing? g0;
    Grazing? gDuring; // grazing that's currently ongoing at asOf
    
    for (final g in allGrazings) {
      if (g.paddockId != paddockId || g.at.isAfter(asOf)) continue;
      
      final grazingEnd = DateTime(
        g.at.year,
        g.at.month,
        g.at.day + (g.durationDays - 1),
      );
      final isDuring = !asOf.isBefore(g.at) && !asOf.isAfter(grazingEnd);
      
      if (isDuring) {
        // If this grazing is during the asOf date, it takes precedence
        if (gDuring == null || g.at.isAfter(gDuring.at)) {
          gDuring = g;
        }
      } else if (g0 == null || g.at.isAfter(g0.at)) {
        g0 = g;
      }
    }

    SilageCut? s0;
    for (final s in allSilageCuts) {
      if (s.paddockId != paddockId || s.at.isAfter(asOf)) continue;
      if (s0 == null || s.at.isAfter(s0.at)) s0 = s;
    }
    
    // If there's a grazing currently ongoing at asOf, use its residual
    if (gDuring != null) {
      return Anchor(gDuring.at, gDuring.residual);
    }
    
    // Find latest among measurements, grazings, and silage cuts
    final candidates = <Anchor>[];
    if (m0 != null) candidates.add(Anchor(m0.at, m0.cover));
    if (g0 != null) candidates.add(Anchor(g0.at, g0.residual));
    if (s0 != null) candidates.add(Anchor(s0.at, s0.residual));
    
    if (candidates.isEmpty) return null;
    
    // Return the latest anchor
    candidates.sort((a, b) => b.at.compareTo(a.at));
    return candidates.first;
  }

  /// Anchor used for predicting a paddock's cover at [asOf].
  ///
  /// Differs from [latestAnchorFromLists] in the two ways that matter once
  /// grazings are planned ahead of time:
  ///  * events are ordered by *farming day* ([farmingDay]), not clock time, so a
  ///    break planned for today cannot override a cover measured this morning;
  ///  * within one farming day a real measurement outranks a planned residual.
  static Anchor? predictionAnchorFromLists(
    List<Measurement> allMeasurements,
    List<Grazing> allGrazings,
    List<SilageCut> allSilageCuts,
    String paddockId,
    DateTime asOf,
  ) {
    final today = farmingDay(asOf);
    Anchor? best;
    DateTime? bestAt;
    var bestMeasured = false;

    void consider(DateTime at, int cover, bool measured) {
      final day = farmingDay(at);
      if (day.isAfter(today)) return; // not happened yet
      if (bestAt == null) {
        best = Anchor(at, cover);
        bestAt = at;
        bestMeasured = measured;
        return;
      }
      final cmp = day.compareTo(farmingDay(bestAt!));
      if (cmp < 0) return;
      final takesIt = cmp > 0 ||
          (measured && !bestMeasured) ||
          (measured == bestMeasured && at.isAfter(bestAt!));
      if (!takesIt) return;
      best = Anchor(at, cover);
      bestAt = at;
      bestMeasured = measured;
    }

    for (final m in allMeasurements) {
      if (m.paddockId == paddockId) consider(m.at, m.cover, true);
    }
    for (final g in allGrazings) {
      if (g.paddockId == paddockId) consider(g.at, g.residual, false);
    }
    for (final s in allSilageCuts) {
      if (s.paddockId == paddockId) consider(s.at, s.residual, false);
    }
    return best;
  }

  Future<List<Measurement>> measurementsForPaddock(String paddockId) async {
    final all = await _loadMeasurements();
    return all.where((m) => m.paddockId == paddockId).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  Future<Measurement?> lastMeasurementForPaddock(String paddockId) async {
    final all = await _loadMeasurements();
    return latestMeasurementFromList(all, paddockId);
  }

  /// Implicit anchor = last measurement OR last grazing residual
  Future<Anchor?> latestAnchorForPaddock(String paddockId) async {
    return latestAnchorForPaddockAsOf(paddockId, DateTime.now());
  }

  Future<Anchor?> latestAnchorForPaddockAsOf(
    String paddockId,
    DateTime asOf,
  ) async {
    final allM = await _loadMeasurements();
    final allG = await _loadGrazings();
    final allS = await _loadSilageCuts();
    return latestAnchorFromLists(allM, allG, allS, paddockId, asOf);
  }

  /// Predicted cover for [paddockId] **on [day]**: the latest anchor at or
  /// before that calendar day, grown at the farm growth rate up to it.
  ///
  /// Scheduling a grazing uses this so the break carries the cover the paddock
  /// is expected to have on the day it is scheduled for — not the cover it has
  /// on the day the grazing was entered.
  Future<int> predictedCoverForPaddockOnDay(
    String paddockId,
    DateTime day,
  ) async {
    final allM = await _loadMeasurements();
    final allG = await _loadGrazings();
    final allS = await _loadSilageCuts();
    final anchor = predictionAnchorFromLists(
      allM,
      allG,
      allS,
      paddockId,
      day,
    );
    final growth = await effectiveFarmGrowthKgDmPerHaPerDay();
    return predictCoverFromAnchor(anchor, day, growth);
  }

  /// Pure (no I/O) cover prediction: [anchor] grown per day up to [onDay].
  static int predictCoverFromAnchor(
    Anchor? anchor,
    DateTime onDay,
    double growthKgDmPerHaPerDay,
  ) {
    if (anchor == null) return clampCover(2500);
    final days = farmingDaysBetween(anchor.at, onDay);
    final grown =
        anchor.coverKgDmHa + (days * growthKgDmPerHaPerDay).round();
    return clampCover(grown);
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

  Future<void> deleteMeasurementById(String id) async {
    final all = await _loadMeasurements();
    final before = all.length;
    all.removeWhere((m) => m.id == id);
    if (all.length < before) await _saveMeasurements(all);
  }

  Future<void> updateMeasurement(Measurement m) async {
    final all = await _loadMeasurements();
    final i = all.indexWhere((x) => x.id == m.id);
    if (i < 0) return;
    all[i] = m;
    await _saveMeasurements(all);
  }

  // -----------------------------
  // NOTES
  // -----------------------------
  Future<List<NoteEntry>> _loadNotes() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_notesKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => NoteEntry.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
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

  Future<void> updateNote(NoteEntry n) async {
    final all = await _loadNotes();
    final i = all.indexWhere((x) => x.id == n.id);
    if (i < 0) return;
    all[i] = n;
    await _saveNotes(all);
  }

  Future<void> deleteNoteById(String id) async {
    final all = await _loadNotes();
    final before = all.length;
    all.removeWhere((x) => x.id == id);
    if (all.length >= before) return;
    await _saveNotes(all);
    await unhideSummaryNoteId(id);
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
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Grazing.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveGrazings(List<Grazing> all) async {
    final sp = await SharedPreferences.getInstance();
    try {
      await sp.setString(
        _grazingsKey,
        jsonEncode(all.map((x) => x.toMap()).toList()),
      );
    } catch (_) {
      // Log error silently - at least don't crash
    }
  }

  /// KPIs helper: raw load all
  Future<List<Grazing>> loadAllGrazings() async => _loadGrazings();

  Future<void> appendGrazing(Grazing g) async {
    try {
      final all = await _loadGrazings();
      all.add(g);
      await _saveGrazings(all);
    } catch (_) {
      // Log error silently
    }
  }

  Future<void> deleteGrazingById(String id) async {
    final all = await _loadGrazings();
    final before = all.length;
    all.removeWhere((g) => g.id == id);
    if (all.length < before) await _saveGrazings(all);
  }

  /// Removes every grazing whose event time is after [asOf] (scheduled / future).
  /// Returns how many records were removed.
  Future<int> deleteAllGrazingsAfter(DateTime asOf) async {
    final all = await _loadGrazings();
    final before = all.length;
    all.removeWhere((g) => g.at.isAfter(asOf));
    if (all.length < before) await _saveGrazings(all);
    return before - all.length;
  }

  Future<void> updateGrazing(Grazing g) async {
    final all = await _loadGrazings();
    final i = all.indexWhere((x) => x.id == g.id);
    if (i < 0) return;
    all[i] = g;
    await _saveGrazings(all);
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

    await _saveGrazings(all);

    return before - all.length;
  }

  Future<List<Grazing>> grazingsForPaddock(String paddockId) async {
    final all = await _loadGrazings();
    return all.where((g) => g.paddockId == paddockId).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  /// Clears the slot link on any grazing that references one of [slotIds].
  /// Used when a herd (and its breaks) is deleted so records become unassigned
  /// rather than orphaned. Returns how many records changed.
  Future<int> clearGrazingSlotReferences(Set<String> slotIds) async {
    if (slotIds.isEmpty) return 0;
    final all = await _loadGrazings();
    var changed = 0;
    for (var i = 0; i < all.length; i++) {
      final g = all[i];
      if (g.slotId != null && slotIds.contains(g.slotId)) {
        all[i] = Grazing(
          id: g.id,
          paddockId: g.paddockId,
          at: g.at,
          enteredAt: g.enteredAt,
          preCover: g.preCover,
          residual: g.residual,
          harvestedKgDm: g.harvestedKgDm,
          durationDays: g.durationDays,
          slotId: null,
          areaHa: g.areaHa,
          groupId: g.groupId,
        );
        changed++;
      }
    }
    if (changed > 0) await _saveGrazings(all);
    return changed;
  }

  // -----------------------------
  // FARM GROWTH (MEASURED)
  // Excludes paddocks not included in rotation.
  // -----------------------------

  /// Growth is only estimated over intervals of at least this length. A 1-day
  /// interval turns +/-50 kgDM/ha of measurement noise into +/-50 kgDM/ha/day.
  static const double _minGrowthIntervalDays = 3;

  /// Physically implausible daily growth — almost always a double-counted
  /// removal (a paddock split over two breaks) or a bad reading.
  static const double _maxGrowthRatePerDay = 200;

  /// Best estimate of the residual actually left by [grazing], from the first
  /// measurement taken after it and the farm growth rate:
  ///
  ///     residual = cover at that measurement - growth * days since grazing
  ///
  /// The planner writes a single default residual for every break, so the
  /// first measurement afterwards is what tells us whether this paddock was
  /// actually left at 1,450 or 1,700. Returns null when there is no measurement
  /// soon enough afterwards, because extrapolating further amplifies the error
  /// in the growth rate.
  static int? inferredResidualFor(
    Grazing grazing,
    List<Measurement> measurements,
    double growthKgDmPerHaPerDay, {
    int maxDays = 10,
    int minKgDmHa = 800,
    int maxKgDmHa = 2400,
  }) {
    return _inferredFrom(
      grazing,
      measurements,
      growthKgDmPerHaPerDay,
      maxDays: maxDays,
      minKgDmHa: minKgDmHa,
      maxKgDmHa: maxKgDmHa,
    )?.residual;
  }

  /// Internal: the inferred residual plus the measurement that resolved it.
  static ({int residual, DateTime measuredAt})? _inferredFrom(
    Grazing grazing,
    List<Measurement> measurements,
    double growthKgDmPerHaPerDay, {
    int maxDays = 10,
    int minKgDmHa = 800,
    int maxKgDmHa = 2400,
  }) {
    if (growthKgDmPerHaPerDay <= 0) return null;

    Measurement? after;
    for (final m in measurements) {
      if (m.paddockId != grazing.paddockId) continue;
      if (!m.at.isAfter(grazing.at)) continue;
      if (after == null || m.at.isBefore(after.at)) after = m;
    }
    if (after == null) return null;

    final days = after.at.difference(grazing.at).inHours / 24.0;
    if (days < 1 || days > maxDays) return null;

    final residual = (after.cover - growthKgDmPerHaPerDay * days).round();
    if (residual < minKgDmHa || residual > maxKgDmHa) return null;
    return (residual: residual, measuredAt: after.at);
  }

  /// The residual to apply automatically to a new break.
  ///
  /// This is the **average** of the residuals inferred from the most recent
  /// round of measurements — every grazing the latest walk resolved — so the
  /// value follows what the herd is actually being left with and refreshes
  /// itself each time covers are measured. Falls back to the 60-day median, then
  /// to [fallback], when the latest walk resolved no grazings.
  Future<int> typicalResidualKgDmHa({int fallback = 1600}) async {
    final growth = await effectiveFarmGrowthKgDmPerHaPerDay();
    if (growth <= 0) return fallback;

    final allM = await _loadMeasurements();
    final allG = await _loadGrazings();
    if (allM.isEmpty) return fallback;

    DateTime? walkAt;
    for (final m in allM) {
      if (walkAt == null || m.at.isAfter(walkAt)) walkAt = m.at;
    }

    final fromLatestWalk = <int>[];
    final recent = <int>[];
    final cutoff = DateTime.now().subtract(const Duration(days: 60));

    for (final g in allG) {
      final inf = _inferredFrom(g, allM, growth);
      if (inf == null) continue;
      if (farmingDaysBetween(inf.measuredAt, walkAt!) == 0) {
        fromLatestWalk.add(inf.residual);
      }
      if (!g.at.isBefore(cutoff)) recent.add(inf.residual);
    }

    if (fromLatestWalk.isNotEmpty) {
      final sum = fromLatestWalk.reduce((a, b) => a + b);
      return (sum / fromLatestWalk.length).round();
    }
    if (recent.isNotEmpty) {
      recent.sort();
      return recent[recent.length ~/ 2];
    }
    return fallback;
  }

  /// Fallback pre-graze target when there are no grazings to average.
  static const int defaultPreGrazingCover = 2800;

  /// Average **predicted pre-graze cover** of the grazings in the last
  /// [windowDays] days.
  ///
  /// The prediction is recomputed from the freshest cover known before each
  /// grazing rather than read off the stored `preCover` field, because older
  /// grazings stored the cover at the moment the break was planned instead of
  /// growing it forward to the grazing day — which made them 200–300 low and
  /// dragged any average of them down. Nothing is capped: a paddock that has
  /// been spelled long is supposed to read high, because that is the signal
  /// that it is heading for a rank residual.
  Future<int?> recentPreGrazingCover({int windowDays = 7}) async {
    final growth = await effectiveFarmGrowthKgDmPerHaPerDay();
    if (growth <= 0) return null;

    final allG = await _loadGrazings();
    final allM = await _loadMeasurements();
    if (allG.isEmpty || allM.isEmpty) return null;

    final paddocks = await loadPaddocks();
    final ids = paddocks
        .where((p) => p.includeInRotation || p.isSilage)
        .map((p) => p.id)
        .toSet();

    final now = DateTime.now();
    final from = now.subtract(Duration(days: windowDays));

    final values = <int>[];
    for (final g in allG) {
      if (!ids.contains(g.paddockId)) continue;
      if (g.at.isAfter(now) || g.at.isBefore(from)) continue;

      // Freshest cover known before this grazing: a measurement or a residual.
      DateTime? anchorAt;
      var anchorCover = 0;
      for (final m in allM) {
        if (m.paddockId != g.paddockId || m.at.isAfter(g.at)) continue;
        if (anchorAt == null || m.at.isAfter(anchorAt)) {
          anchorAt = m.at;
          anchorCover = m.cover;
        }
      }
      for (final other in allG) {
        if (other.paddockId != g.paddockId || !other.at.isBefore(g.at)) {
          continue;
        }
        if (anchorAt == null || other.at.isAfter(anchorAt)) {
          anchorAt = other.at;
          anchorCover = other.residual;
        }
      }
      if (anchorAt == null) continue;

      final days = farmingDaysBetween(anchorAt, g.at);
      if (days < 0) continue;
      values.add(clampCover(anchorCover + (days * growth).round()));
    }
    if (values.isEmpty) return null;
    return (values.reduce((a, b) => a + b) / values.length).round();
  }

  /// The **measured** cover trend: the area-weighted average cover on each of
  /// the last [walks] farm walks, and how far it moved per day.
  ///
  /// This is the APC graph as a number. No growth rate, no residuals, no model
  /// — just what the readings did between two walks.
  Future<
    ({
      double perDay,
      double perWeek,
      double fromCover,
      double toCover,
      DateTime from,
      DateTime to,
      int walks,
    })?
  >
  measuredCoverTrend({int walks = 4}) async {
    final allM = await _loadMeasurements();
    if (allM.isEmpty) return null;

    final paddocks = await loadPaddocks();
    final areaById = <String, double>{
      for (final p in paddocks)
        if (p.includeInRotation || p.isSilage || p.shutForSilage)
          p.id: p.areaHa,
    };
    if (areaById.isEmpty) return null;

    final byDay = <DateTime, List<Measurement>>{};
    for (final m in allM) {
      if (!areaById.containsKey(m.paddockId)) continue;
      (byDay[farmingDay(m.at)] ??= []).add(m);
    }

    // A farm walk is a day with readings on at least half the paddocks; that
    // filters out the odd single-paddock correction while keeping short walks.
    final walkDays = byDay.keys.where(
      (d) => (byDay[d]?.length ?? 0) * 2 >= areaById.length,
    ).toList()..sort();
    if (walkDays.length < 2) return null;

    double apcOn(DateTime day) {
      var area = 0.0;
      var sum = 0.0;
      for (final m in byDay[day] ?? const <Measurement>[]) {
        final a = areaById[m.paddockId] ?? 0;
        area += a;
        sum += m.cover * a;
      }
      return area <= 0 ? 0 : sum / area;
    }

    final take = walkDays.length <= walks
        ? walkDays
        : walkDays.sublist(walkDays.length - walks);
    final from = take.first;
    final to = take.last;
    final span = farmingDaysBetween(from, to);
    if (span < 1) return null;

    final fromCover = apcOn(from);
    final toCover = apcOn(to);
    final perDay = (toCover - fromCover) / span;
    return (
      perDay: perDay,
      perWeek: perDay * 7,
      fromCover: fromCover,
      toCover: toCover,
      from: from,
      to: to,
      walks: take.length,
    );
  }

  /// The pre-graze and residual figures used by the feed wedge and the cover
  /// trend, so the two widgets cannot disagree. A manual override wins;
  /// otherwise the pre-graze cover is the average predicted pre-graze cover of
  /// the current round, and the residual is the value inferred from the latest
  /// round of measurements.
  Future<PrePostTargets> prePostTargets({
    int defaultPre = defaultPreGrazingCover,
  }) async {
    final preOverride = await loadFeedWedgePreGrazingOverride();
    final postOverride = await loadFeedWedgePostGrazingResidualOverride();
    final measuredPre = await recentPreGrazingCover();
    final inferredPost = await typicalResidualKgDmHa();
    return (
      pre: preOverride ?? measuredPre ?? defaultPre,
      post: postOverride ?? inferredPost,
      overridden: preOverride != null || postOverride != null,
    );
  }

  Future<double> computeFarmGrowthKgDmPerHaPerDay() async {
    final msAll = await _loadMeasurements();
    final gsAll = await _loadGrazings();
    final allS = await _loadSilageCuts();
    final includedIds = await _includedPaddockIds();
    return computeFarmGrowthFromLoadedData(
      msAll,
      gsAll,
      includedIds,
      silageCuts: allS,
    );
  }

  /// Same rules as [computeFarmGrowthKgDmPerHaPerDay] but uses already-decoded lists
  /// so callers can avoid duplicate SharedPreferences + JSON work.
  double computeFarmGrowthFromLoadedData(
    List<Measurement> msAll,
    List<Grazing> gsAll,
    Set<String> includedIds, {
    List<SilageCut> silageCuts = const [],
  }) {
    if (msAll.length < 2) return 0;

    final ms = msAll.where((m) => includedIds.contains(m.paddockId)).toList();
    if (ms.length < 2) return 0;

    final byPdk = <String, List<Measurement>>{};
    for (final m in ms) {
      (byPdk[m.paddockId] ??= []).add(m);
    }

    // Farm growth = the mean of every paddock's current growth rate, counting
    // only the positive ones.
    //
    // Growth is measured from the last point at which the paddock's cover was
    // actually known: the previous measurement, or the residual of a grazing
    // or silage cut that happened since. Growing forward from that anchor to
    // today's measurement means the pre-graze cover — a plan value — cancels
    // out of the arithmetic and never has to be trusted. It also means a
    // planned break cannot inflate the figure, because only the residual is
    // used, not the difference between two guesses.
    final rates = <double>[];

    for (final entry in byPdk.entries) {
      final paddockId = entry.key;
      final list = entry.value..sort((a, b) => a.at.compareTo(b.at));
      if (list.length < 2) continue;

      final cur = list.last;

      // Latest known cover strictly before this measurement.
      DateTime? anchorAt;
      var anchorCover = 0;
      var haveAnchor = false;

      void consider(DateTime at, int cover) {
        if (!at.isBefore(cur.at)) return;
        if (haveAnchor && !at.isAfter(anchorAt!)) return;
        anchorAt = at;
        anchorCover = cover;
        haveAnchor = true;
      }

      for (final m in list) {
        consider(m.at, m.cover);
      }
      for (final g in gsAll) {
        if (g.paddockId == paddockId) consider(g.at, g.residual);
      }
      for (final s in silageCuts) {
        if (s.paddockId == paddockId) consider(s.at, s.residual);
      }
      if (!haveAnchor) continue;

      // Fractional days: truncating to whole days (inDays) inflated the rate
      // by up to a day's worth of growth per interval.
      final days = cur.at.difference(anchorAt!).inHours / 24.0;
      if (days < _minGrowthIntervalDays) continue;
      final rate = (cur.cover - anchorCover) / days;

      // Positive only: a cover that fell with nothing to explain it is an
      // unreported removal or a bad reading, not grass growing backwards.
      if (rate <= 0) continue;
      if (rate > _maxGrowthRatePerDay) continue;

      rates.add(rate);
    }

    if (rates.isEmpty) return 0;
    return rates.reduce((a, b) => a + b) / rates.length;
  }

  /// DM removed per hectare for [paddockId] between [from] and [to] by
  /// grazings and silage cuts, prorating multi-day events that only partly
  /// overlap the interval.
  static double removedKgDmHaBetween(
    List<Grazing> grazings,
    List<SilageCut> silageCuts,
    String paddockId,
    DateTime from,
    DateTime to,
  ) {
    final fromDay = calendarDay(from);
    final toDayExclusive = DateTime(to.year, to.month, to.day + 1);

    double overlapFraction(DateTime at, int durationDays) {
      final start = calendarDay(at);
      final days = durationDays < 1 ? 1 : durationDays;
      final end = DateTime(start.year, start.month, start.day + days);
      final lo = start.isAfter(fromDay) ? start : fromDay;
      final hi = end.isBefore(toDayExclusive) ? end : toDayExclusive;
      final overlap = hi.difference(lo).inDays;
      if (overlap <= 0) return 0.0;
      return overlap >= days ? 1.0 : overlap / days;
    }

    var removed = 0.0;

    // A paddock split across two breaks on the same day (AM/PM) is stored as
    // two grazing rows carrying the same pre/post, so count one removal per
    // paddock per start day instead of adding it twice.
    final grazingsByDay = <DateTime, List<Grazing>>{};
    for (final g in grazings) {
      if (g.paddockId != paddockId) continue;
      (grazingsByDay[calendarDay(g.at)] ??= []).add(g);
    }
    for (final group in grazingsByDay.values) {
      var bestDrop = 0;
      var dur = 1;
      for (final g in group) {
        final drop = g.preCover - g.residual;
        if (drop > bestDrop) bestDrop = drop;
        if (g.durationDays > dur) dur = g.durationDays;
      }
      if (bestDrop <= 0) continue;
      final share = overlapFraction(group.first.at, dur);
      if (share > 0) removed += bestDrop * share;
    }
    for (final s in silageCuts) {
      if (s.paddockId != paddockId) continue;
      final share = overlapFraction(s.at, 1);
      if (share > 0) removed += (s.preCover - s.residual) * share;
    }
    return removed;
  }

  static bool paddockGrazedBetweenFromList(
    List<Grazing> allG,
    String paddockId,
    DateTime a,
    DateTime b,
  ) {
    return allG.any(
      (x) {
        if (x.paddockId != paddockId) return false;
        final grazingEnd = DateTime(
          x.at.year,
          x.at.month,
          x.at.day + (x.durationDays - 1),
        );
        // Check if grazing overlaps with the interval (a, b)
        return x.at.isBefore(b) && grazingEnd.isAfter(a);
      },
    );
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

  Future<DuplicateGrazingCleanupSummary>
  cleanupDuplicateGrazingsAllPaddocks() async {
    const minDropKgDmHa = 200;

    final grazings = await _loadGrazings();
    if (grazings.isEmpty) {
      return const DuplicateGrazingCleanupSummary(
        deletedGrazings: 0,
        affectedPaddocks: 0,
      );
    }

    final msAll = await _loadMeasurements();
    if (msAll.isEmpty) {
      return const DuplicateGrazingCleanupSummary(
        deletedGrazings: 0,
        affectedPaddocks: 0,
      );
    }

    final msByPaddock = <String, List<Measurement>>{};
    for (final m in msAll) {
      (msByPaddock[m.paddockId] ??= []).add(m);
    }
    for (final e in msByPaddock.entries) {
      e.value.sort((a, b) => a.at.compareTo(b.at));
    }

    final toDelete = <String>{};
    final affectedPaddockIds = <String>{};

    final grazingsByPaddock = <String, List<Grazing>>{};
    for (final g in grazings) {
      (grazingsByPaddock[g.paddockId] ??= []).add(g);
    }

    for (final entry in grazingsByPaddock.entries) {
      final paddockId = entry.key;
      final gs = entry.value..sort((a, b) => a.at.compareTo(b.at));

      final ms = msByPaddock[paddockId];
      if (ms == null || ms.length < 2) continue;

      int mi = 0;
      for (final g in gs) {
        while (mi < ms.length && !ms[mi].at.isAfter(g.at)) {
          mi++;
        }

        final beforeIndex = mi - 1;
        if (beforeIndex < 0) continue;

        int afterIndex = mi;
        while (afterIndex < ms.length && !ms[afterIndex].at.isAfter(g.at)) {
          afterIndex++;
        }
        if (afterIndex >= ms.length) continue;

        final mBefore = ms[beforeIndex];
        final mAfter = ms[afterIndex];

        final drop = mBefore.cover - mAfter.cover;
        if (drop < minDropKgDmHa) {
          toDelete.add(g.id);
          affectedPaddockIds.add(paddockId);
        }
      }
    }

    if (toDelete.isEmpty) {
      return const DuplicateGrazingCleanupSummary(
        deletedGrazings: 0,
        affectedPaddocks: 0,
      );
    }

    final filtered = grazings.where((g) => !toDelete.contains(g.id)).toList();
    await _saveGrazings(filtered);

    return DuplicateGrazingCleanupSummary(
      deletedGrazings: toDelete.length,
      affectedPaddocks: affectedPaddockIds.length,
    );
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
    return paddockGrazedBetweenFromList(g, paddockId, a, b);
  }

  // -----------------------------
  // SILAGE CUTS
  // -----------------------------
  Future<List<SilageCut>> _loadSilageCuts() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_silageCutsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => SilageCut.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveSilageCuts(List<SilageCut> all) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _silageCutsKey,
      jsonEncode(all.map((x) => x.toMap()).toList()),
    );
  }

  Future<List<SilageCut>> loadAllSilageCuts() async => _loadSilageCuts();

  Future<void> appendSilageCut(SilageCut c) async {
    final all = await _loadSilageCuts();
    all.add(c);
    await _saveSilageCuts(all);
  }

  Future<void> deleteSilageCutById(String id) async {
    final all = await _loadSilageCuts();
    final before = all.length;
    all.removeWhere((c) => c.id == id);
    if (all.length < before) await _saveSilageCuts(all);
  }

  Future<void> updateSilageCut(SilageCut c) async {
    final all = await _loadSilageCuts();
    final i = all.indexWhere((x) => x.id == c.id);
    if (i < 0) return;
    all[i] = c;
    await _saveSilageCuts(all);
  }

  Future<List<SilageCut>> silageCutsForPaddock(String paddockId) async {
    final all = await _loadSilageCuts();
    return all.where((c) => c.paddockId == paddockId).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  Future<SilageCut?> lastSilageCutForPaddock(String paddockId) async {
    final list = await silageCutsForPaddock(paddockId);
    return list.isEmpty ? null : list.first;
  }

  Future<int> annualSilageHarvestKgDmForPaddock(String paddockId) async {
    final cuts = await _loadSilageCuts();
    final year = DateTime.now().year;
    return cuts
        .where((x) => x.paddockId == paddockId && x.at.year == year)
        .fold<int>(0, (a, b) => a + b.harvestedKgDm);
  }

  Future<Map<String, int>> annualSilageHarvestAllPaddocksKgDm() async {
    final cuts = await _loadSilageCuts();
    final year = DateTime.now().year;
    final out = <String, int>{};

    for (final x in cuts.where((e) => e.at.year == year)) {
      out[x.paddockId] = (out[x.paddockId] ?? 0) + x.harvestedKgDm;
    }
    return out;
  }

  /// Keeps `isSilage` and `shutForSilage` in sync. Older versions only cleared
  /// `shutForSilage` when reopening a paddock for grazing, leaving `isSilage`
  /// true — which made the paddock linger in the silage summary and kept it out
  /// of the grazing planner palette. A paddock is only ever a "silage paddock"
  /// while it is shut for silage, so any mismatch is repaired here.
  Future<void> migrateSilagePaddocks() async {
    final paddocks = await loadPaddocks();
    var changed = false;
    Paddock fix(Paddock p, {required bool isSilage, required bool shut}) {
      changed = true;
      return Paddock(
        id: p.id,
        name: p.name,
        areaHa: p.areaHa,
        recordOrder: p.recordOrder,
        includeInRotation: p.includeInRotation,
        isSilage: isSilage,
        shutForSilage: shut,
      );
    }

    final updated = paddocks.map((p) {
      if (p.shutForSilage && !p.isSilage) {
        // Legacy: shut but not flagged silage.
        return fix(p, isSilage: true, shut: true);
      }
      if (p.isSilage && !p.shutForSilage) {
        // Legacy: reopened for grazing but still flagged silage.
        return fix(p, isSilage: false, shut: false);
      }
      return p;
    }).toList();

    if (changed) {
      await savePaddocks(updated);
    }
  }
}

class DuplicateGrazingCleanupSummary {
  final int deletedGrazings;
  final int affectedPaddocks;

  const DuplicateGrazingCleanupSummary({
    required this.deletedGrazings,
    required this.affectedPaddocks,
  });
}

class Anchor {
  final DateTime at;
  final int coverKgDmHa;

  Anchor(this.at, this.coverKgDmHa);
}
