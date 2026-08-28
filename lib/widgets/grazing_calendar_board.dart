import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../utils.dart';

/// Shared grazing calendar item — persisted grazing or unsaved draft.
class GrazingCalendarBlock {
  final String id;
  final String paddockId;
  final String paddockName;
  final double areaHa;
  final DateTime startDay;
  final int durationDays;
  final bool isDraft;
  final bool locked;
  final int? preCover;
  final int? residual;
  final int? harvestedKgDm;
  final DateTime? enteredAt;

  GrazingCalendarBlock({
    required this.id,
    required this.paddockId,
    required this.paddockName,
    required this.areaHa,
    required DateTime startDay,
    this.durationDays = 1,
    this.isDraft = false,
    this.locked = false,
    this.preCover,
    this.residual,
    this.harvestedKgDm,
    this.enteredAt,
  }) : startDay = calendarDay(startDay);

  int get safeDuration => durationDays < 1 ? 1 : durationDays;

  DateTime get endDay => startDay.add(Duration(days: safeDuration - 1));

  bool covers(DateTime day) {
    final d = calendarDay(day);
    return !d.isBefore(startDay) && !d.isAfter(endDay);
  }

  GrazingCalendarBlock copyWith({
    String? id,
    String? paddockId,
    String? paddockName,
    double? areaHa,
    DateTime? startDay,
    int? durationDays,
    bool? isDraft,
    bool? locked,
    int? preCover,
    int? residual,
    int? harvestedKgDm,
    DateTime? enteredAt,
  }) =>
      GrazingCalendarBlock(
        id: id ?? this.id,
        paddockId: paddockId ?? this.paddockId,
        paddockName: paddockName ?? this.paddockName,
        areaHa: areaHa ?? this.areaHa,
        startDay: startDay ?? this.startDay,
        durationDays: durationDays ?? this.durationDays,
        isDraft: isDraft ?? this.isDraft,
        locked: locked ?? this.locked,
        preCover: preCover ?? this.preCover,
        residual: residual ?? this.residual,
        harvestedKgDm: harvestedKgDm ?? this.harvestedKgDm,
        enteredAt: enteredAt ?? this.enteredAt,
      );
}

enum GrazingCalendarInteraction { view, edit }

int _retainedVisibleCols = 4;

class _GanttBar {
  final GrazingCalendarBlock block;
  final int startDayIndex;
  final int dayCount;
  final int lane;
  final Color color;

  const _GanttBar({
    required this.block,
    required this.startDayIndex,
    required this.dayCount,
    required this.lane,
    required this.color,
  });
}

enum _DragKind { move, resize }

class _DragSession {
  final _DragKind kind;
  final GrazingCalendarBlock block;
  final int originStart;
  final int lane;
  final Color color;
  int previewStart;
  int previewDur;

  _DragSession({
    required this.kind,
    required this.block,
    required this.originStart,
    required this.lane,
    required this.color,
    required this.previewStart,
    required this.previewDur,
  });

  _DragSession copyWith({int? previewStart, int? previewDur}) => _DragSession(
        kind: kind,
        block: block,
        originStart: originStart,
        lane: lane,
        color: color,
        previewStart: previewStart ?? this.previewStart,
        previewDur: previewDur ?? this.previewDur,
      );
}

/// Day rows + fixed-width paddock rectangles. Extra columns scroll sideways.
class GrazingCalendarBoard extends StatefulWidget {
  final List<GrazingCalendarBlock> blocks;
  final double targetHaDay;
  final GrazingCalendarInteraction interaction;
  final ValueChanged<List<GrazingCalendarBlock>>? onBlocksChanged;
  final ValueChanged<GrazingCalendarBlock>? onBlockLongPress;
  final DateTime? focusDay;
  final int daysBefore;
  final int daysAfter;
  final double visibleDayCount;

  const GrazingCalendarBoard({
    super.key,
    required this.blocks,
    required this.targetHaDay,
    this.interaction = GrazingCalendarInteraction.view,
    this.onBlocksChanged,
    this.onBlockLongPress,
    this.focusDay,
    this.daysBefore = 90,
    this.daysAfter = 90,
    this.visibleDayCount = 5,
  });

  @override
  State<GrazingCalendarBoard> createState() => _GrazingCalendarBoardState();
}

class _GrazingCalendarBoardState extends State<GrazingCalendarBoard>
    with SingleTickerProviderStateMixin {
  static const _dayColW = 96.0;
  static const _colGap = 10.0;
  static const _gridPad = 8.0;
  static const _rowGap = 4.0;
  static const _minColW = 40.0;
  static const _minVisibleCols = 1;
  static const _maxVisibleColsCap = 10;

  late List<DateTime> _days;
  late List<GrazingCalendarBlock> _blocks;
  final _vDate = ScrollController();
  final _vGrid = ScrollController();
  final _hScroll = ScrollController();
  _DragSession? _dragSession;
  int? _focusIndex;
  bool _didJump = false;
  bool _syncingV = false;

  int? _moveOriginStart;
  double _moveTotalDy = 0;
  int? _resizeOriginDuration;
  double _resizeTotalDy = 0;

  String? _selectedId;

  double _visibleColCount = 4.0;
  bool _pinching = false;
  final _pointerPos = <int, Offset>{};
  double? _pinchStartDist;
  double _pinchStartCols = 4.0;
  double _pinchStartHOffset = 0;
  double _pinchStartColW = 1.0;
  double _pinchFocalLocalX = 0;
  late final AnimationController _colSnapAnim;
  Animation<double>? _colSnapTween;
  double _snapStartHOffset = 0;
  double _snapStartColW = 1.0;

  double _cachedRowH = 64;
  double _cachedViewportH = 400;
  double _cachedColW = 124;

  List<_GanttBar> _cachedBars = const [];
  int _laneCount = 1;
  List<double> _cachedAreaByDay = const [];
  Map<String, int?> _daysSinceById = const {};
  double _cachedGridViewportW = 300;
  final _colorCache = <String, Color>{};
  final _barScrollTick = ValueNotifier(0.0);
  final _selectionTick = ValueNotifier(0);
  bool _barScrollFrameQueued = false;

  ScrollHoldController? _dateHold;
  ScrollHoldController? _gridHold;
  ScrollHoldController? _hHold;

  @override
  void initState() {
    super.initState();
    _colSnapAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onColSnapTick);
    _visibleColCount =
        _retainedVisibleCols.toDouble().clamp(
          _minVisibleCols.toDouble(),
          _maxVisibleColsCap.toDouble(),
        );
    _rebuildDays();
    _blocks = [...widget.blocks];
    _rebuildLayoutCache();
    _vDate.addListener(_syncFromDate);
    _vGrid.addListener(_syncFromGrid);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToFocus());
  }

  void _onGridScroll(ScrollNotification notification) {
    if (notification.depth != 0) return;
    if (notification is ScrollEndNotification ||
        notification is UserScrollNotification) {
      if (_vGrid.hasClients) {
        _barScrollTick.value = _vGrid.offset;
      }
    }
    if (_barScrollFrameQueued) return;
    _barScrollFrameQueued = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _barScrollFrameQueued = false;
      if (!mounted || !_vGrid.hasClients) return;
      final px = _vGrid.offset;
      if ((px - _barScrollTick.value).abs() >= 0.5) {
        _barScrollTick.value = px;
      }
    });
  }

  @override
  void didUpdateWidget(covariant GrazingCalendarBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragSession == null && oldWidget.blocks != widget.blocks) {
      _blocks = [...widget.blocks];
      _rebuildLayoutCache();
    }
    if (oldWidget.interaction != widget.interaction &&
        widget.interaction != GrazingCalendarInteraction.edit) {
      _selectedId = null;
    }
    if (oldWidget.focusDay != widget.focusDay ||
        oldWidget.daysBefore != widget.daysBefore ||
        oldWidget.daysAfter != widget.daysAfter) {
      _rebuildDays();
      _rebuildLayoutCache();
      _didJump = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToFocus());
    }
  }

  @override
  void dispose() {
    _colSnapAnim.removeListener(_onColSnapTick);
    _colSnapAnim.dispose();
    _unlockScroll();
    _vDate.removeListener(_syncFromDate);
    _vGrid.removeListener(_syncFromGrid);
    _barScrollTick.dispose();
    _selectionTick.dispose();
    _vDate.dispose();
    _vGrid.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  void _syncFromDate() {
    if (_syncingV || !_vGrid.hasClients || !_vDate.hasClients) return;
    _syncingV = true;
    final next = _vDate.offset.clamp(0.0, _vGrid.position.maxScrollExtent);
    if ((_vGrid.offset - next).abs() > 0.5) {
      _vGrid.jumpTo(next);
      _barScrollTick.value = next;
    }
    _syncingV = false;
  }

  void _syncFromGrid() {
    if (_syncingV || !_vDate.hasClients || !_vGrid.hasClients) return;
    _syncingV = true;
    final next = _vGrid.offset.clamp(0.0, _vDate.position.maxScrollExtent);
    if ((_vDate.offset - next).abs() > 0.5) _vDate.jumpTo(next);
    _syncingV = false;
  }

  void _lockScroll() {
    _dateHold?.cancel();
    _gridHold?.cancel();
    _hHold?.cancel();
    if (_vDate.hasClients) _dateHold = _vDate.position.hold(() {});
    if (_vGrid.hasClients) _gridHold = _vGrid.position.hold(() {});
    if (_hScroll.hasClients) _hHold = _hScroll.position.hold(() {});
  }

  void _unlockScroll() {
    _dateHold?.cancel();
    _gridHold?.cancel();
    _hHold?.cancel();
    _dateHold = null;
    _gridHold = null;
    _hHold = null;
  }

  void _cancelDragSession() {
    _moveOriginStart = null;
    _moveTotalDy = 0;
    _resizeOriginDuration = null;
    _resizeTotalDy = 0;
    if (_dragSession == null) return;
    _dragSession = null;
    _rebuildLayoutCache();
  }

  double _pointerDistance() {
    final pts = _pointerPos.values.toList();
    if (pts.length < 2) return 0;
    return (pts[0] - pts[1]).distance;
  }

  Offset _pointerMidpoint() {
    final pts = _pointerPos.values.toList();
    return Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
  }

  double _focalXInGrid() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    final local = box.globalToLocal(_pointerMidpoint());
    return (local.dx - _dayColW).clamp(0.0, _cachedGridViewportW);
  }

  void _beginPinch() {
    if (_dragSession != null) _cancelDragSession();
    _colSnapAnim.stop();
    _lockScroll();
    _pinchStartCols = _visibleColCount;
    _pinchStartDist = _pointerDistance();
    _pinchStartHOffset = _hScroll.hasClients ? _hScroll.offset : 0;
    _pinchStartColW = math.max(1.0, _cachedColW);
    _pinchFocalLocalX = _focalXInGrid();
    if (!_pinching) setState(() => _pinching = true);
  }

  int _maxVisibleCols() {
    final inner = math.max(0.0, _cachedGridViewportW - _gridPad * 2);
    final byWidth =
        ((inner + _colGap) / (_minColW + _colGap)).floor();
    return byWidth.clamp(_minVisibleCols, _maxVisibleColsCap);
  }

  void _keepHFocal({
    required double startOffset,
    required double startColW,
    required double focalX,
  }) {
    if (!_hScroll.hasClients || startColW <= 0) return;
    final ratio = _cachedColW / startColW;
    final next = (startOffset + focalX) * ratio - focalX;
    _hScroll.jumpTo(
      next.clamp(0.0, _hScroll.position.maxScrollExtent),
    );
  }

  void _updatePinch() {
    final startDist = _pinchStartDist;
    if (startDist == null || startDist < 12) return;
    final dist = math.max(12.0, _pointerDistance());
    final maxN = _maxVisibleCols().toDouble();
    final next = (_pinchStartCols * startDist / dist)
        .clamp(_minVisibleCols.toDouble(), maxN);
    if ((next - _visibleColCount).abs() < 0.01) return;
    _visibleColCount = next;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keepHFocal(
        startOffset: _pinchStartHOffset,
        startColW: _pinchStartColW,
        focalX: _pinchFocalLocalX,
      );
    });
  }

  void _onColSnapTick() {
    final tween = _colSnapTween;
    if (tween == null) return;
    _visibleColCount = tween.value;
    _updateColW(_cachedGridViewportW);
    setState(() {});
    _keepHFocal(
      startOffset: _snapStartHOffset,
      startColW: _snapStartColW,
      focalX: _pinchFocalLocalX,
    );
  }

  void _snapVisibleCols() {
    final maxN = _maxVisibleCols();
    final target =
        _visibleColCount.round().clamp(_minVisibleCols, maxN).toDouble();
    _retainedVisibleCols = target.round();
    if ((_visibleColCount - target).abs() < 0.02) {
      _visibleColCount = target;
      if (_dragSession == null) _unlockScroll();
      setState(() {});
      return;
    }
    _snapStartColW = math.max(1.0, _cachedColW);
    _snapStartHOffset = _hScroll.hasClients ? _hScroll.offset : 0;
    _colSnapTween = Tween<double>(begin: _visibleColCount, end: target).animate(
      CurvedAnimation(parent: _colSnapAnim, curve: Curves.easeOutCubic),
    );
    _colSnapAnim.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      _visibleColCount = target;
      _retainedVisibleCols = target.round();
      if (!_pinching && _dragSession == null) _unlockScroll();
      if (mounted) setState(() {});
    });
  }

  void _endPinchIfNeeded() {
    if (_pointerPos.length >= 2) return;
    _pinchStartDist = null;
    if (!_pinching) return;
    _pinching = false;
    _snapVisibleCols();
  }

  void _onBoardPointerDown(PointerDownEvent e) {
    _pointerPos[e.pointer] = e.position;
    if (_pointerPos.length == 2) _beginPinch();
  }

  void _onBoardPointerMove(PointerMoveEvent e) {
    if (!_pointerPos.containsKey(e.pointer)) return;
    _pointerPos[e.pointer] = e.position;
    if (_pointerPos.length == 2) _updatePinch();
  }

  void _onBoardPointerUp(PointerEvent e) {
    _pointerPos.remove(e.pointer);
    _endPinchIfNeeded();
  }

  bool get _isDragging => _dragSession != null;

  bool get _blockScroll =>
      _isDragging || _pinching || _colSnapAnim.isAnimating;

  double get _rowStride => _cachedRowH + _rowGap;

  double get _colW => _cachedColW;

  double _colWForVisibleCount(double count, double gridViewportW) {
    final inner = math.max(0.0, gridViewportW - _gridPad * 2);
    final n = count.clamp(
      _minVisibleCols.toDouble(),
      _maxVisibleCols().toDouble(),
    );
    final gaps = (n - 1) * _colGap;
    return math.max(_minColW, (inner - gaps) / n);
  }

  void _updateColW(double gridViewportW) {
    _cachedColW = _colWForVisibleCount(_visibleColCount, gridViewportW);
  }

  double _rowTop(int dayIndex) => dayIndex * _rowStride;

  double _barHeight(int dayCount) =>
      dayCount * _cachedRowH + (dayCount - 1) * _rowGap;

  double _colLeft(int lane) => _gridPad + lane * (_colW + _colGap);

  double _gridContentW(double viewportW) {
    final packed = _gridPad * 2 +
        _laneCount * _colW +
        math.max(0, _laneCount - 1) * _colGap;
    final id = _selectedId;
    final extra = (id != null && _isDetailsOpen(id))
        ? math.max(0.0, _barWidthFor(id) - _colW + _colGap)
        : 0.0;
    return math.max(viewportW, packed + extra);
  }

  void _rebuildDays() {
    final focus = calendarDay(widget.focusDay ?? DateTime.now());
    _days = [
      for (var i = -widget.daysBefore; i <= widget.daysAfter; i++)
        focus.add(Duration(days: i)),
    ];
    _focusIndex = widget.daysBefore;
  }

  void _jumpToFocus() {
    if (_didJump || _focusIndex == null) return;
    final target = (_focusIndex! * _rowStride);
    if (_vDate.hasClients) {
      _vDate.jumpTo(target.clamp(0.0, _vDate.position.maxScrollExtent));
    }
    if (_vGrid.hasClients) {
      final next = target.clamp(0.0, _vGrid.position.maxScrollExtent);
      _vGrid.jumpTo(next);
      _barScrollTick.value = next;
    }
    _didJump = true;
  }

  Color _colorFor(String paddockId) {
    return _colorCache.putIfAbsent(paddockId, () {
      final hue = (paddockId.hashCode % 360).abs().toDouble();
      return HSLColor.fromAHSL(1, hue, 0.46, 0.48).toColor();
    });
  }

  void _emit() => widget.onBlocksChanged?.call(List.unmodifiable(_blocks));

  int _indexOfDay(DateTime day) =>
      _days.indexWhere((x) => x == calendarDay(day));

  Map<String, int> _assignLanes(
    List<({GrazingCalendarBlock b, int start, int dur})> indexed,
  ) {
    final laneById = <String, int>{};
    final laneEnd = <int>[];

    for (final item in indexed) {
      var lane = 0;
      while (lane < laneEnd.length && laneEnd[lane] > item.start) {
        lane++;
      }
      if (lane == laneEnd.length) laneEnd.add(0);
      laneEnd[lane] = item.start + item.dur;
      laneById[item.b.id] = lane;
    }
    _laneCount = math.max(1, laneEnd.length);
    return laneById;
  }

  List<({GrazingCalendarBlock b, int start, int dur})> _indexedBlocks() {
    final session = _dragSession;
    final indexed = <({GrazingCalendarBlock b, int start, int dur})>[];

    for (final b in _blocks) {
      var start = _indexOfDay(b.startDay);
      if (start < 0 || start >= _days.length) continue;
      var dur = b.safeDuration;
      if (session != null && session.block.id == b.id) {
        start = session.previewStart;
        dur = session.previewDur;
      }
      indexed.add((b: b, start: start, dur: dur));
    }

    indexed.sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) return c;
      return b.dur.compareTo(a.dur);
    });
    return indexed;
  }

  void _rebuildLayoutCache() {
    final indexed = _indexedBlocks();
    final lanes = _assignLanes(indexed);
    _cachedBars = [
      for (final item in indexed)
        _GanttBar(
          block: item.b,
          startDayIndex: item.start,
          dayCount: item.dur,
          lane: lanes[item.b.id]!,
          color: _colorFor(item.b.paddockId),
        ),
    ];
    _cachedAreaByDay = _computeAreaByDay();
    _rebuildDaysSince();
  }

  void _rebuildDaysSince() {
    final byPdk = <String, List<GrazingCalendarBlock>>{};
    for (final b in _blocks) {
      (byPdk[b.paddockId] ??= []).add(b);
    }
    final map = <String, int?>{};
    for (final list in byPdk.values) {
      list.sort((a, b) => a.startDay.compareTo(b.startDay));
      for (var i = 0; i < list.length; i++) {
        map[list[i].id] = i == 0
            ? null
            : list[i].startDay.difference(list[i - 1].startDay).inDays;
      }
    }
    _daysSinceById = map;
  }

  _GanttBar? _barFor(String blockId) {
    for (final bar in _cachedBars) {
      if (bar.block.id == blockId) return bar;
    }
    return null;
  }

  List<double> _computeAreaByDay() {
    final session = _dragSession;
    final areas = List<double>.filled(_days.length, 0);
    for (final b in _blocks) {
      var start = _indexOfDay(b.startDay);
      if (start < 0) continue;
      var dur = b.safeDuration;
      if (session != null && session.block.id == b.id) {
        start = session.previewStart;
        dur = session.previewDur;
      }
      final haDay = b.areaHa / dur;
      for (var d = 0; d < dur; d++) {
        final di = start + d;
        if (di >= 0 && di < _days.length) areas[di] += haDay;
      }
    }
    return areas;
  }

  void _onBarTap(String id) {
    if (_dragSession != null) return;
    final opening = _selectedId != id;
    setState(() => _selectedId = opening ? id : null);
    _selectionTick.value++;
    if (opening &&
        widget.interaction != GrazingCalendarInteraction.edit) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollExpandedIntoView());
    }
  }

  void _onBarDragStart(_GanttBar bar, {required _DragKind kind}) {
    if (_pinching || _pointerPos.length >= 2) return;
    if (_dragSession != null) return;
    if (!_canEditBlock(bar.block.id)) return;
    _lockScroll();
    _selectedId = bar.block.id;
    if (kind == _DragKind.resize) {
      _startResizeDrag(bar.block.id);
    } else {
      _startMoveDrag(bar.block.id);
    }
    if (_dragSession == null) {
      _unlockScroll();
      return;
    }
    _rebuildLayoutCache();
    setState(() {});
  }

  void _deselect() {
    if (_selectedId == null) return;
    setState(() => _selectedId = null);
    _selectionTick.value++;
  }

  bool _isDetailsOpen(String id) =>
      widget.interaction != GrazingCalendarInteraction.edit &&
      _selectedId == id &&
      _dragSession == null;

  double _barWidthFor(String id) {
    if (!_isDetailsOpen(id)) return _colW;
    final bar = _barFor(id);
    return _colW +
        _GrazingDetailGrid.panelWidth(
          pre: bar?.block.preCover,
          post: bar?.block.residual,
          harvest: bar?.block.harvestedKgDm,
          daysSince: _daysSinceById[id],
          textScaler: MediaQuery.textScalerOf(context),
        );
  }

  double _barDisplayHeight(_GanttBar bar) => _barHeight(bar.dayCount);

  void _scrollHorizontal(double deltaDx) {
    if (_pinching || !_hScroll.hasClients) return;
    final next = (_hScroll.offset - deltaDx)
        .clamp(0.0, _hScroll.position.maxScrollExtent);
    _hScroll.jumpTo(next);
  }

  void _scrollVertical(double deltaDy) {
    if (_pinching || !_vGrid.hasClients) return;
    final next = (_vGrid.offset - deltaDy)
        .clamp(0.0, _vGrid.position.maxScrollExtent);
    _vGrid.jumpTo(next);
  }

  void _scrollExpandedIntoView() {
    final id = _selectedId;
    if (id == null || !_hScroll.hasClients) return;
    final bar = _barFor(id);
    if (bar == null) return;
    final left = _colLeft(bar.lane);
    final right = left + _barWidthFor(id) + _gridPad;
    final viewW = _cachedGridViewportW;
    var target = _hScroll.offset;
    if (right - target > viewW) target = right - viewW;
    if (left < target) target = left;
    target = target.clamp(0.0, _hScroll.position.maxScrollExtent);
    _hScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  bool _canEditBlock(String id) {
    if (widget.interaction != GrazingCalendarInteraction.edit) return false;
    for (final b in _blocks) {
      if (b.id == id) return !b.locked;
    }
    return false;
  }

  void _onBarDragUpdate(DragUpdateDetails details) {
    if (_dragSession == null) return;
    if (_dragSession!.kind == _DragKind.move) {
      _moveTotalDy += details.delta.dy;
      _applyMovePreview();
    } else {
      _resizeTotalDy += details.delta.dy;
      _applyResizePreview();
    }
  }

  void _onBarDragEnd() {
    _unlockScroll();
    if (_dragSession == null) return;
    if (_dragSession!.kind == _DragKind.move) {
      _commitMove();
    } else {
      _commitResize();
    }
  }

  void _startMoveDrag(String id) {
    final b = _blocks.firstWhere((x) => x.id == id);
    if (b.locked) return;
    final start = _indexOfDay(b.startDay);
    if (start < 0) return;
    final bar = _barFor(id);
    _moveOriginStart = start;
    _moveTotalDy = 0;
    _dragSession = _DragSession(
      kind: _DragKind.move,
      block: b,
      originStart: start,
      lane: bar?.lane ?? 0,
      color: _colorFor(b.paddockId),
      previewStart: start,
      previewDur: b.safeDuration,
    );
  }

  void _startResizeDrag(String id) {
    final b = _blocks.firstWhere((x) => x.id == id);
    if (b.locked) return;
    final start = _indexOfDay(b.startDay);
    if (start < 0) return;
    final bar = _barFor(id);
    _resizeOriginDuration = b.safeDuration;
    _resizeTotalDy = 0;
    _dragSession = _DragSession(
      kind: _DragKind.resize,
      block: b,
      originStart: start,
      lane: bar?.lane ?? 0,
      color: _colorFor(b.paddockId),
      previewStart: start,
      previewDur: b.safeDuration,
    );
  }

  void _applyMovePreview() {
    final session = _dragSession;
    final origin = _moveOriginStart;
    if (session == null || origin == null) return;
    final steps = (_moveTotalDy / _rowStride).round();
    var next = origin + steps;
    next = next.clamp(0, _days.length - session.previewDur);
    if (next == session.previewStart) return;
    _dragSession = session.copyWith(previewStart: next);
    _rebuildLayoutCache();
    setState(() {});
  }

  void _commitMove() {
    final session = _dragSession;
    _moveOriginStart = null;
    _moveTotalDy = 0;
    _dragSession = null;

    if (session != null) {
      final i = _blocks.indexWhere((b) => b.id == session.block.id);
      if (i >= 0) {
        final b = _blocks[i];
        final newStart = _days[session.previewStart];
        if (newStart != b.startDay) {
          _blocks[i] = b.copyWith(startDay: newStart);
          _emit();
        }
      }
    }
    _rebuildLayoutCache();
    setState(() {});
  }

  void _commitResize() {
    final session = _dragSession;
    final origin = _resizeOriginDuration;
    _resizeOriginDuration = null;
    _resizeTotalDy = 0;
    _dragSession = null;

    if (session != null && origin != null && session.previewDur != origin) {
      final i = _blocks.indexWhere((b) => b.id == session.block.id);
      if (i >= 0) {
        _blocks[i] = _blocks[i].copyWith(durationDays: session.previewDur);
        _emit();
      }
    }
    _rebuildLayoutCache();
    setState(() {});
  }

  void _applyResizePreview() {
    final session = _dragSession;
    final origin = _resizeOriginDuration;
    if (session == null || origin == null) return;
    final maxDur = (_days.length - session.previewStart).clamp(1, 365);
    final steps = (_resizeTotalDy / _rowStride).round();
    final dur = (origin + steps).clamp(1, maxDur);
    if (dur == session.previewDur) return;
    _dragSession = session.copyWith(previewDur: dur);
    _rebuildLayoutCache();
    setState(() {});
  }

  ScrollPhysics get _vPhysics => _blockScroll
      ? const NeverScrollableScrollPhysics()
      : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  bool _barCanDrag(_GanttBar bar) =>
      widget.interaction == GrazingCalendarInteraction.edit &&
      !bar.block.locked &&
      _selectedId == bar.block.id;

  Widget _wrapBarGestures(_GanttBar bar, {required Widget child}) {
    final canDrag = _barCanDrag(bar);
    if (!canDrag) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onBarTap(bar.block.id),
        onHorizontalDragUpdate: (d) => _scrollHorizontal(d.delta.dx),
        onVerticalDragUpdate: (d) => _scrollVertical(d.delta.dy),
        child: child,
      );
    }

    return Listener(
      onPointerDown: (_) => _lockScroll(),
      onPointerUp: (_) {
        if (_dragSession == null) _unlockScroll();
      },
      onPointerCancel: (_) {
        if (_dragSession == null) _unlockScroll();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onBarTap(bar.block.id),
            onVerticalDragStart: (_) =>
                _onBarDragStart(bar, kind: _DragKind.move),
            onVerticalDragUpdate: _onBarDragUpdate,
            onVerticalDragEnd: (_) => _onBarDragEnd(),
            onVerticalDragCancel: _onBarDragEnd,
            child: child,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 26,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onBarTap(bar.block.id),
              onVerticalDragStart: (_) =>
                  _onBarDragStart(bar, kind: _DragKind.resize),
              onVerticalDragUpdate: _onBarDragUpdate,
              onVerticalDragEnd: (_) => _onBarDragEnd(),
              onVerticalDragCancel: _onBarDragEnd,
              child: const _ExtendHandle(),
            ),
          ),
          if (_selectedId == bar.block.id &&
              widget.onBlockLongPress != null)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                icon: const Icon(Icons.close, size: 14, color: Colors.white),
                onPressed: () => widget.onBlockLongPress!(bar.block),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayRow(int i, {required bool inGrid}) {
    final previewStart = _dragSession?.previewStart;
    return SizedBox(
      height: _rowStride,
      child: Padding(
        padding: const EdgeInsets.only(bottom: _rowGap),
        child: inGrid
            ? GestureDetector(
                onTap: _deselect,
                behavior: HitTestBehavior.opaque,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: previewStart == i
                        ? const Color(0x102F66E3)
                        : i.isEven
                            ? const Color(0x05000000)
                            : Colors.transparent,
                    border: const Border(
                      bottom: BorderSide(color: Color(0x0D000000)),
                    ),
                  ),
                ),
              )
            : _DayProgressCell(
                day: _days[i],
                percent: widget.targetHaDay > 0
                    ? (_cachedAreaByDay[i] / widget.targetHaDay) * 100
                    : 0,
                hasTarget: widget.targetHaDay > 0,
                highlight: previewStart == i,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dragging = _isDragging;
    final blockScroll = _blockScroll;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onBoardPointerDown,
      onPointerMove: _onBoardPointerMove,
      onPointerUp: _onBoardPointerUp,
      onPointerCancel: (e) => _onBoardPointerUp(e),
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
          _cachedRowH =
              (constraints.maxHeight / widget.visibleDayCount).clamp(58.0, 112.0);
          _cachedViewportH = constraints.maxHeight;
          final rowStride = _rowStride;
          final gridViewportW = math.max(0.0, constraints.maxWidth - _dayColW);
          _cachedGridViewportW = gridViewportW;
          _updateColW(gridViewportW);
          final gridW = _gridContentW(gridViewportW);

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _dayColW,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (_) => blockScroll,
                      child: ListView.builder(
                        controller: _vDate,
                        physics: _vPhysics,
                        itemExtent: rowStride,
                        cacheExtent: rowStride * 4,
                        itemCount: _days.length,
                        itemBuilder: (context, i) =>
                            _dayRow(i, inGrid: false),
                      ),
                    ),
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (_) => blockScroll,
                      child: SingleChildScrollView(
                        controller: _hScroll,
                        scrollDirection: Axis.horizontal,
                        physics: blockScroll
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        child: SizedBox(
                          width: gridW,
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _ColumnGuidePainter(
                                      laneCount: _laneCount,
                                      colW: _colW,
                                      colGap: _colGap,
                                      pad: _gridPad,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: (n) {
                                    _onGridScroll(n);
                                    return blockScroll;
                                  },
                                  child: ListView.builder(
                                    controller: _vGrid,
                                    physics: _vPhysics,
                                    itemExtent: rowStride,
                                    cacheExtent: rowStride * 3,
                                    itemCount: _days.length,
                                    itemBuilder: (context, i) =>
                                        _dayRow(i, inGrid: true),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: GestureDetector(
                                  onTap: dragging ? null : _deselect,
                                  behavior: HitTestBehavior.translucent,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              Positioned.fill(
                                child: ListenableBuilder(
                                  listenable: Listenable.merge(
                                    [_vGrid, _selectionTick],
                                  ),
                                  builder: (context, _) {
                                    final v =
                                        _vGrid.hasClients ? _vGrid.offset : 0.0;
                                    if (_cachedBars.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    final firstRow = (v / rowStride)
                                        .floor()
                                        .clamp(0, _days.length - 1);
                                    final lastRow = (firstRow +
                                            (_cachedViewportH / rowStride)
                                                .ceil() +
                                            2)
                                        .clamp(0, _days.length - 1);
                                    final visible = <_GanttBar>[];
                                    for (final bar in _cachedBars) {
                                      if (bar.startDayIndex + bar.dayCount >=
                                              firstRow &&
                                          bar.startDayIndex <= lastRow) {
                                        visible.add(bar);
                                      }
                                    }
                                    if (_selectedId != null) {
                                      visible.sort((a, b) {
                                        if (a.block.id == _selectedId) return 1;
                                        if (b.block.id == _selectedId) return -1;
                                        return 0;
                                      });
                                    }
                                    return Stack(
                                      fit: StackFit.expand,
                                      clipBehavior: Clip.hardEdge,
                                      children: [
                                        for (final bar in visible)
                                          Positioned(
                                            key: ValueKey(bar.block.id),
                                            top: _rowTop(
                                                  bar.startDayIndex,
                                                ) -
                                                v,
                                            left: _colLeft(bar.lane),
                                            child: _BarShell(
                                              width: _barWidthFor(
                                                bar.block.id,
                                              ),
                                              height: _barDisplayHeight(
                                                bar,
                                              ),
                                              child: _wrapBarGestures(
                                                bar,
                                                child: _GanttBarTile(
                                                  bar: bar,
                                                  isSelected: _selectedId ==
                                                      bar.block.id,
                                                  isExpanded: _isDetailsOpen(
                                                    bar.block.id,
                                                  ),
                                                  compactWidth: _colW,
                                                  showExtendHandle:
                                                      _barCanDrag(bar),
                                                  isDragging: dragging &&
                                                      _dragSession?.block.id ==
                                                          bar.block.id,
                                                  previewDuration:
                                                      _dragSession?.block.id ==
                                                              bar.block.id
                                                          ? _dragSession!
                                                              .previewDur
                                                          : null,
                                                  daysSincePrev:
                                                      _daysSinceById[
                                                          bar.block.id],
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}

class _DayProgressCell extends StatelessWidget {
  final DateTime day;
  final double percent;
  final bool hasTarget;
  final bool highlight;

  const _DayProgressCell({
    required this.day,
    required this.percent,
    required this.hasTarget,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final today = calendarDay(DateTime.now());
    final isToday = day == today;
    final isPast = day.isBefore(today);
    final over = percent > 100.01;
    final fill = hasTarget ? (percent / 100.0).clamp(0.0, 1.0) : 0.0;

    return ColoredBox(
      color: highlight
          ? const Color(0x222F66E3)
          : isToday
              ? const Color(0x142F66E3)
              : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              Text(
                DateFormat('EEE d MMM').format(day),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isPast ? Colors.black54 : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Colors.black.withValues(alpha: 0.06)),
                      FractionallySizedBox(
                        widthFactor: fill,
                        alignment: Alignment.centerLeft,
                        child: ColoredBox(
                          color: (!hasTarget
                                  ? Colors.transparent
                                  : over
                                      ? const Color(0xFFE53935)
                                      : const Color(0xFF43A047))
                              .withValues(alpha: 0.85),
                        ),
                      ),
                      Center(
                        child: Text(
                          !hasTarget ? '—' : '${percent.round()}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: over ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

class _ColumnGuidePainter extends CustomPainter {
  final int laneCount;
  final double colW;
  final double colGap;
  final double pad;

  const _ColumnGuidePainter({
    required this.laneCount,
    required this.colW,
    required this.colGap,
    required this.pad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0A000000);
    for (var i = 0; i < laneCount; i++) {
      final x = pad + i * (colW + colGap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 2, colW, size.height - 4),
          const Radius.circular(8),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ColumnGuidePainter oldDelegate) =>
      oldDelegate.laneCount != laneCount ||
      oldDelegate.colW != colW ||
      oldDelegate.colGap != colGap;
}

class _BarShell extends StatelessWidget {
  final double width;
  final double height;
  final Widget child;

  const _BarShell({
    required this.width,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: child,
      ),
    );
  }
}

class _GanttBarTile extends StatelessWidget {
  final _GanttBar bar;
  final bool isSelected;
  final bool isExpanded;
  final double compactWidth;
  final bool showExtendHandle;
  final bool isDragging;
  final int? previewDuration;
  final int? daysSincePrev;

  const _GanttBarTile({
    required this.bar,
    required this.isSelected,
    required this.isExpanded,
    required this.compactWidth,
    required this.showExtendHandle,
    required this.isDragging,
    this.previewDuration,
    this.daysSincePrev,
  });

  @override
  Widget build(BuildContext context) {
    final b = bar.block;
    final dur = previewDuration ?? bar.dayCount;
    final haDay = b.areaHa / b.safeDuration;
    final fill = b.locked ? bar.color.withValues(alpha: 0.55) : bar.color;
    const labelStyle = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      fontSize: 12,
      height: 1.15,
      shadows: [
        Shadow(
          color: Color(0x55000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(fill, Colors.white, 0.12)!,
            fill,
          ],
        ),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF2F66E3)
              : b.isDraft
                  ? Colors.white.withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.08),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: isDragging || isExpanded ? 0.22 : 0.12,
            ),
            blurRadius: isDragging || isExpanded ? 10 : 5,
            offset: Offset(0, isDragging || isExpanded ? 4 : 1.5),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          if (isExpanded)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: compactWidth,
              child: _nameBlock(b, dur, haDay, labelStyle),
            )
          else
            Positioned.fill(
              child: _nameBlock(b, dur, haDay, labelStyle),
            ),
          if (isExpanded)
            Positioned(
              left: compactWidth,
              top: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                ),
                child: _GrazingDetailGrid(
                    pre: b.preCover,
                    post: b.residual,
                    harvest: b.harvestedKgDm,
                    daysSince: daysSincePrev,
                  ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _nameBlock(
    GrazingCalendarBlock b,
    int dur,
    double haDay,
    TextStyle labelStyle,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 7, 7, showExtendHandle ? 30 : 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            b.paddockName,
            maxLines: dur > 2 ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
          const Spacer(),
          Text(
            dur > 1
                ? '$dur d · ${haDay.toStringAsFixed(2)} ha/d'
                : '${b.areaHa.toStringAsFixed(1)} ha',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtendHandle extends StatelessWidget {
  const _ExtendHandle();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.32),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
          SizedBox(height: 1),
          Text(
            'extend',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _GrazingDetailGrid extends StatelessWidget {
  final int? pre;
  final int? post;
  final int? harvest;
  final int? daysSince;

  static const _padH = 10.0;
  static const _gap = 12.0;
  static const _labelStyle = TextStyle(
    color: Color(0xDDFFFFFF),
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: 0.2,
  );
  static const _valueStyle = TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontWeight: FontWeight.w800,
    height: 1.15,
  );

  const _GrazingDetailGrid({
    required this.pre,
    required this.post,
    required this.harvest,
    required this.daysSince,
  });

  static String _n(int? v) {
    if (v == null) return '—';
    return NumberFormat.decimalPattern().format(v);
  }

  static List<(String, String)> _items({
    required int? pre,
    required int? post,
    required int? harvest,
    required int? daysSince,
  }) =>
      [
        ('Pre', _n(pre)),
        ('Post', _n(post)),
        ('Harvest', harvest == null ? '—' : '${_n(harvest)} kg'),
        ('Round', daysSince == null ? '—' : '$daysSince d'),
      ];

  static double panelWidth({
    required int? pre,
    required int? post,
    required int? harvest,
    required int? daysSince,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    double measure(String text, TextStyle style) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        textScaler: textScaler,
      )..layout();
      return tp.width;
    }

    var w = _padH * 2;
    final items = _items(
      pre: pre,
      post: post,
      harvest: harvest,
      daysSince: daysSince,
    );
    for (var i = 0; i < items.length; i++) {
      if (i > 0) w += _gap;
      w += math.max(
        measure(items[i].$1, _labelStyle),
        measure(items[i].$2, _valueStyle),
      );
    }
    return w.ceilToDouble() + 4;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(
      pre: pre,
      post: post,
      harvest: harvest,
      daysSince: daysSince,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _padH),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  items[i].$1,
                  maxLines: 1,
                  style: _labelStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  items[i].$2,
                  maxLines: 1,
                  style: _valueStyle,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
