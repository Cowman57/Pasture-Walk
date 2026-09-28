import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';

/// Setup for the grazing plan: herds and their grazing breaks (slots).
///
/// Each herd has one or more slots, e.g. Milkers -> "AM" (12h, 1.5 ha),
/// "PM" (12h, 1.5 ha). Slots are what the planner calendar allocates paddocks to.
class GrazingPlanSetupScreen extends StatefulWidget {
  const GrazingPlanSetupScreen({super.key});

  @override
  State<GrazingPlanSetupScreen> createState() => _GrazingPlanSetupScreenState();
}

class _GrazingPlanSetupScreenState extends State<GrazingPlanSetupScreen> {
  final Storage storage = Storage();
  final Uuid uuid = const Uuid();

  List<Herd> _herds = [];
  List<GrazingSlot> _slots = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      storage.loadHerds(),
      storage.loadGrazingSlots(),
    ]);
    if (!mounted) return;
    setState(() {
      _herds = results[0] as List<Herd>;
      _slots = results[1] as List<GrazingSlot>;
      _loading = false;
    });
  }

  Future<void> _persistHerds() async {
    await storage.saveHerds(_herds);
  }

  Future<void> _persistSlots() async {
    await storage.saveGrazingSlots(_slots);
  }

  /// Area (ha) for a herd expressed per cow per day. 1 ha = 10,000 m².
  static double? _haToM2PerCow(double ha, int cows) =>
      cows <= 0 ? null : ha * 10000.0 / cows;

  static double? _m2PerCowToHa(double m2, int cows) =>
      cows <= 0 ? null : m2 * cows / 10000.0;

  Future<void> _addOrEditHerd({Herd? herd}) async {
    final nameCtrl = TextEditingController(text: herd?.name ?? '');
    final cowsCtrl = TextEditingController(
      text: herd == null || herd.cowCount <= 0 ? '' : '${herd.cowCount}',
    );
    final areaCtrl = TextEditingController(
      text: herd == null || herd.areaGrazedPerDayHa <= 0
          ? ''
          : herd.areaGrazedPerDayHa.toStringAsFixed(2),
    );
    final m2Ctrl = TextEditingController(
      text: herd == null
          ? ''
          : (_haToM2PerCow(herd.areaGrazedPerDayHa, herd.cowCount)
                    ?.toStringAsFixed(1) ??
                ''),
    );
    final suppCtrl = TextEditingController(
      text: herd == null || herd.supplementKgDmPerCowPerDay <= 0
          ? ''
          : herd.supplementKgDmPerCowPerDay.toStringAsFixed(1),
    );
    var syncing = false;

    int cowsNow() => int.tryParse(cowsCtrl.text.trim()) ?? 0;

    void fromArea() {
      if (syncing) return;
      final cows = cowsNow();
      final ha = double.tryParse(areaCtrl.text.trim());
      if (cows <= 0 || ha == null) return;
      syncing = true;
      m2Ctrl.text = (_haToM2PerCow(ha, cows) ?? 0).toStringAsFixed(1);
      syncing = false;
    }

    void fromM2() {
      if (syncing) return;
      final cows = cowsNow();
      final m2 = double.tryParse(m2Ctrl.text.trim());
      if (cows <= 0 || m2 == null) return;
      syncing = true;
      areaCtrl.text = (_m2PerCowToHa(m2, cows) ?? 0).toStringAsFixed(2);
      syncing = false;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(herd == null ? 'Add herd' : 'Edit herd'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: cowsCtrl,
                  decoration: const InputDecoration(labelText: 'Cows'),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setLocal(fromArea),
                ),
                TextField(
                  controller: areaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Target area (ha/day)',
                    helperText: 'Total for the herd · blank = sum of its breaks',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setLocal(fromArea),
                ),
                TextField(
                  controller: m2Ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Target per cow (m²/cow/day)',
                    helperText: 'Linked to the total above via cow count',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setLocal(fromM2),
                ),
                TextField(
                  controller: suppCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Supplement (kgDM/cow/day)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final name = nameCtrl.text.trim().isEmpty ? 'Herd' : nameCtrl.text.trim();
    final cows = int.tryParse(cowsCtrl.text.trim()) ?? 0;
    final area = double.tryParse(areaCtrl.text.trim()) ?? 0.0;
    final supp = double.tryParse(suppCtrl.text.trim()) ?? 0.0;

    setState(() {
      if (herd == null) {
        _herds = [
          ..._herds,
          Herd(
            id: 'herd_${uuid.v4()}',
            name: name,
            cowCount: cows.clamp(0, 999999999),
            areaGrazedPerDayHa: area.clamp(0.0, 999999999.0),
            supplementKgDmPerCowPerDay: supp.clamp(0.0, 999999999.0),
          ),
        ];
      } else {
        _herds = [
          for (final h in _herds)
            if (h.id == herd.id)
              h.copyWith(
                name: name,
                cowCount: cows.clamp(0, 999999999),
                areaGrazedPerDayHa: area.clamp(0.0, 999999999.0),
                supplementKgDmPerCowPerDay: supp.clamp(0.0, 999999999.0),
              )
            else
              h,
        ];
      }
    });
    await _persistHerds();
  }

  Future<void> _deleteHerd(Herd herd) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete herd?'),
        content: Text(
          'Remove "${herd.name}" and its ${_slotsFor(herd.id).length} break(s)? '
          'Recorded grazings keep their history but lose this herd link.',
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
    final slotIds = _slotsFor(herd.id).map((s) => s.id).toSet();
    await storage.clearGrazingSlotReferences(slotIds);
    setState(() {
      _herds = _herds.where((h) => h.id != herd.id).toList();
      _slots = _slots.where((s) => s.herdId != herd.id).toList();
    });
    await _persistHerds();
    await _persistSlots();
  }

  List<GrazingSlot> _slotsFor(String herdId) =>
      _slots.where((s) => s.herdId == herdId).toList();

  Future<void> _addOrEditSlot(String herdId, {GrazingSlot? slot}) async {
    final labelCtrl = TextEditingController(text: slot?.label ?? '');
    final hoursCtrl = TextEditingController(
      text: slot == null ? '12' : _trimNum(slot.hours),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(slot == null ? 'Add break' : 'Edit break'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'e.g. AM, PM, Night',
                ),
              ),
              TextField(
                controller: hoursCtrl,
                decoration: const InputDecoration(
                  labelText: 'Hours in this break',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final label = labelCtrl.text.trim().isEmpty
        ? 'Break'
        : labelCtrl.text.trim();
    final hours = hoursCtrl.text.trim().isEmpty
        ? 12.0
        : (double.tryParse(hoursCtrl.text.trim()) ?? 12.0);

    setState(() {
      if (slot == null) {
        final order = _slotsFor(herdId).length;
        _slots = [
          ..._slots,
          GrazingSlot(
            id: 'slot_${uuid.v4()}',
            herdId: herdId,
            label: label,
            hours: hours.clamp(0.0, 168.0),
            sortOrder: order,
          ),
        ];
      } else {
        _slots = [
          for (final s in _slots)
            if (s.id == slot.id)
              s.copyWith(label: label, hours: hours.clamp(0.0, 168.0))
            else
              s,
        ];
      }
    });
    await _persistSlots();
  }

  Future<void> _deleteSlot(GrazingSlot slot) async {
    setState(() {
      _slots = _slots.where((s) => s.id != slot.id).toList();
    });
    await _persistSlots();
  }

  String _trimNum(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grazing Plan Setup'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'Define each herd and the breaks it takes. The planner '
                  'calendar allocates paddocks to these breaks so you can hit '
                  'your daily area target.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (final herd in _herds) _herdCard(herd),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _addOrEditHerd(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add herd'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _herdCard(Herd herd) {
    final slots = _slotsFor(herd.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    herd.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (herd.cowCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '${herd.cowCount} cows',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit herd',
                  onPressed: () => _addOrEditHerd(herd: herd),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete herd',
                  onPressed: () => _deleteHerd(herd),
                ),
              ],
            ),
            Text(
              'Daily target: ${herd.areaGrazedPerDayHa.toStringAsFixed(2)} ha/day'
              '${_haToM2PerCow(herd.areaGrazedPerDayHa, herd.cowCount) == null ? '' : '  ·  ${_haToM2PerCow(herd.areaGrazedPerDayHa, herd.cowCount)!.toStringAsFixed(1)} m²/cow'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (slots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No breaks yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final slot in slots)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule, size: 18),
                  title: Text(slot.label),
                  subtitle: Text('${_trimNum(slot.hours)} h'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () =>
                            _addOrEditSlot(herd.id, slot: slot),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Remove break',
                        onPressed: () => _deleteSlot(slot),
                      ),
                    ],
                  ),
                ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addOrEditSlot(herd.id),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add break'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
