import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../storage.dart';

/// Groups activity by day and type. **Past** grazings use the event date (`at`);
/// **future** (scheduled) grazings use **entered** calendar day (`enteredAt`).
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

enum _LogKind { cover, grazing, note }

/// How grazing rows are bucketed (past vs scheduled-by-entry-day).
enum _GrazingBucket { pastEventDay, futureEnteredDay }

class _LogGroup {
  _LogGroup({
    required this.kind,
    required this.day,
    this.grazingBucket,
  });

  final _LogKind kind;
  final DateTime day;
  final _GrazingBucket? grazingBucket;
  final List<String> ids = [];
  final Set<String> paddockIds = {};

  int get eventCount => ids.length;

  String get key {
    if (kind == _LogKind.grazing && grazingBucket != null) {
      return 'grazing_${grazingBucket!.name}_${day.year}_${day.month}_${day.day}';
    }
    return '${kind.name}_${day.year}_${day.month}_${day.day}';
  }
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final storage = Storage();
  int _refreshTick = 0;
  bool _selectionMode = false;
  final Set<String> _selectedKeys = {};

  static DateTime _dayLocal(DateTime d) => DateTime(d.year, d.month, d.day);

  static final _dateFmt = DateFormat('d/M/yy');
  static final _dateTimeFmt = DateFormat('d/M/yy HH:mm');

  String _kindTitle(_LogGroup g) {
    switch (g.kind) {
      case _LogKind.cover:
        return 'Pasture covers';
      case _LogKind.grazing:
        if (g.grazingBucket == _GrazingBucket.futureEnteredDay) {
          return 'Scheduled grazings (entered)';
        }
        return 'Grazings';
      case _LogKind.note:
        return 'Notes';
    }
  }

  IconData _kindIcon(_LogKind k) {
    switch (k) {
      case _LogKind.cover:
        return Icons.grass_outlined;
      case _LogKind.grazing:
        return Icons.agriculture_outlined;
      case _LogKind.note:
        return Icons.note_alt_outlined;
    }
  }

  int _groupSortOrder(_LogGroup g) {
    switch (g.kind) {
      case _LogKind.cover:
        return 0;
      case _LogKind.grazing:
        return g.grazingBucket == _GrazingBucket.futureEnteredDay ? 2 : 1;
      case _LogKind.note:
        return 3;
    }
  }

  List<_LogGroup> _buildGroups(
    List<Measurement> measurements,
    List<Grazing> grazings,
    List<NoteEntry> notes,
    DateTime now,
  ) {
    final map = <String, _LogGroup>{};

    for (final m in measurements) {
      final day = _dayLocal(m.at);
      final g = map.putIfAbsent(
        '${_LogKind.cover.name}_${day.year}_${day.month}_${day.day}',
        () => _LogGroup(kind: _LogKind.cover, day: day),
      );
      g.ids.add(m.id);
      g.paddockIds.add(m.paddockId);
    }

    for (final x in grazings) {
      final isFuture = x.at.isAfter(now);
      final _GrazingBucket bucket = isFuture
          ? _GrazingBucket.futureEnteredDay
          : _GrazingBucket.pastEventDay;
      final day = isFuture ? _dayLocal(x.enteredAt) : _dayLocal(x.at);
      final key =
          'grazing_${bucket.name}_${day.year}_${day.month}_${day.day}';
      final g = map.putIfAbsent(
        key,
        () => _LogGroup(
          kind: _LogKind.grazing,
          day: day,
          grazingBucket: bucket,
        ),
      );
      g.ids.add(x.id);
      g.paddockIds.add(x.paddockId);
    }

    for (final n in notes) {
      final day = _dayLocal(n.at);
      final g = map.putIfAbsent(
        '${_LogKind.note.name}_${day.year}_${day.month}_${day.day}',
        () => _LogGroup(kind: _LogKind.note, day: day),
      );
      g.ids.add(n.id);
      g.paddockIds.add(n.paddockId);
    }

    final list = map.values.toList();
    list.sort((a, b) {
      final c = b.day.compareTo(a.day);
      if (c != 0) return c;
      final o = _groupSortOrder(a).compareTo(_groupSortOrder(b));
      if (o != 0) return o;
      return a.kind.index.compareTo(b.kind.index);
    });
    return list;
  }

  Future<void> _deleteGroup(_LogGroup g) async {
    switch (g.kind) {
      case _LogKind.cover:
        for (final id in g.ids) {
          await storage.deleteMeasurementById(id);
        }
      case _LogKind.grazing:
        for (final id in g.ids) {
          await storage.deleteGrazingById(id);
        }
      case _LogKind.note:
        for (final id in g.ids) {
          await storage.deleteNoteById(id);
        }
    }
  }

  Future<void> _deleteOne({
    required _LogKind kind,
    required String id,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    switch (kind) {
      case _LogKind.cover:
        await storage.deleteMeasurementById(id);
      case _LogKind.grazing:
        await storage.deleteGrazingById(id);
      case _LogKind.note:
        await storage.deleteNoteById(id);
    }
    if (!mounted) return;
    setState(() => _refreshTick++);
  }

  void _onLongPressSelectGroup(String groupKey) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectionMode = true;
      _selectedKeys.add(groupKey);
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedKeys.isEmpty) return;

    final snap = await Future.wait([
      storage.loadAllMeasurements(),
      storage.loadAllGrazings(),
      storage.loadAllNotes(),
    ]);
    final measurements = snap[0] as List<Measurement>;
    final grazings = snap[1] as List<Grazing>;
    final notes = snap[2] as List<NoteEntry>;
    final now = DateTime.now();
    final groups = _buildGroups(measurements, grazings, notes, now);
    final toDelete = groups.where((g) => _selectedKeys.contains(g.key)).toList();

    var totalEvents = 0;
    for (final g in toDelete) {
      totalEvents += g.eventCount;
    }

    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text(
          'Remove ${toDelete.length} group${toDelete.length == 1 ? '' : 's'} '
          '($totalEvents event${totalEvents == 1 ? '' : 's'} total)? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    for (final g in toDelete) {
      await _deleteGroup(g);
    }
    if (!mounted) return;
    setState(() {
      _selectedKeys.clear();
      _selectionMode = false;
      _refreshTick++;
    });
  }

  Measurement? _mById(List<Measurement> all, String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  Grazing? _gById(List<Grazing> all, String id) {
    for (final g in all) {
      if (g.id == id) return g;
    }
    return null;
  }

  NoteEntry? _nById(List<NoteEntry> all, String id) {
    for (final n in all) {
      if (n.id == id) return n;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity log'),
        actions: [
          if (_selectionMode) ...[
            TextButton(
              onPressed: _selectedKeys.isEmpty ? null : _deleteSelected,
              child: Text(
                'Delete (${_selectedKeys.length})',
                style: TextStyle(
                  color: _selectedKeys.isEmpty
                      ? Theme.of(context).disabledColor
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedKeys.clear();
                });
              },
              child: const Text('Cancel'),
            ),
          ],
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        key: ValueKey(_refreshTick),
        future: Future.wait([
          storage.loadAllMeasurements(),
          storage.loadAllGrazings(),
          storage.loadAllNotes(),
          storage.loadPaddocks(),
        ]),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final measurements = snap.data![0] as List<Measurement>;
          final grazings = snap.data![1] as List<Grazing>;
          final notes = snap.data![2] as List<NoteEntry>;
          final paddocks = snap.data![3] as List<Paddock>;
          final nameById = {for (final p in paddocks) p.id: p.name};

          final now = DateTime.now();
          final groups = _buildGroups(measurements, grazings, notes, now);
          if (groups.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No cover, grazing, or note events yet.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _groupTile(
                  context,
                  groups[i],
                  measurements,
                  grazings,
                  notes,
                  nameById,
                  _onLongPressSelectGroup,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _groupTile(
    BuildContext context,
    _LogGroup g,
    List<Measurement> measurements,
    List<Grazing> grazings,
    List<NoteEntry> notes,
    Map<String, String> nameById,
    void Function(String groupKey) onLongPressSelectGroup,
  ) {
    final subtitle = StringBuffer()
      ..write('${g.eventCount} event${g.eventCount == 1 ? '' : 's'}')
      ..write(' · ')
      ..write(
        '${g.paddockIds.length} paddock${g.paddockIds.length == 1 ? '' : 's'}',
      );

    final selected = _selectedKeys.contains(g.key);
    final titleText =
        '${_dateFmt.format(g.day)} · ${_kindTitle(g)}';

    final children = <Widget>[
      for (final id in g.ids)
        _entryRow(
          context,
          g.kind,
          id,
          measurements,
          grazings,
          notes,
          nameById,
        ),
    ];

    return GestureDetector(
      onLongPress: () => onLongPressSelectGroup(g.key),
      behavior: HitTestBehavior.opaque,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey(g.key),
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
            initiallyExpanded: false,
            leading: _selectionMode
                ? Checkbox(
                    value: selected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedKeys.add(g.key);
                        } else {
                          _selectedKeys.remove(g.key);
                        }
                      });
                    },
                  )
                : Icon(_kindIcon(g.kind)),
            title: Text(titleText, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle.toString()),
            children: [
              const Divider(height: 1),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryRow(
    BuildContext context,
    _LogKind kind,
    String id,
    List<Measurement> measurements,
    List<Grazing> grazings,
    List<NoteEntry> notes,
    Map<String, String> nameById,
  ) {
    String pad(String pid) => nameById[pid] ?? pid;

    switch (kind) {
      case _LogKind.cover:
        final m = _mById(measurements, id);
        if (m == null) return const SizedBox.shrink();
        return ListTile(
          dense: true,
          title: Text('${m.cover} kgDM/ha · ${pad(m.paddockId)}'),
          subtitle: Text(_dateTimeFmt.format(m.at)),
          trailing: IconButton(
            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            onPressed: _selectionMode
                ? null
                : () => _deleteOne(kind: kind, id: id),
          ),
        );
      case _LogKind.grazing:
        final x = _gById(grazings, id);
        if (x == null) return const SizedBox.shrink();
        return ListTile(
          dense: true,
          title: Text(
            'Pre ${x.preCover} → ${x.residual} · ${pad(x.paddockId)}',
          ),
          subtitle: Text(
            'Event ${_dateTimeFmt.format(x.at)}'
            '${x.at.isAfter(DateTime.now()) ? ' · entered ${_dateTimeFmt.format(x.enteredAt)}' : ''}',
          ),
          trailing: IconButton(
            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            onPressed: _selectionMode
                ? null
                : () => _deleteOne(kind: kind, id: id),
          ),
        );
      case _LogKind.note:
        final n = _nById(notes, id);
        if (n == null) return const SizedBox.shrink();
        return ListTile(
          dense: true,
          title: Text('${n.title} · ${pad(n.paddockId)}'),
          subtitle: Text(_dateTimeFmt.format(n.at)),
          trailing: IconButton(
            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            onPressed: _selectionMode
                ? null
                : () => _deleteOne(kind: kind, id: id),
          ),
        );
    }
  }
}
