import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';
import '../utils.dart';
import 'paddock_history_screen.dart';

class SilageSummaryScreen extends StatefulWidget {
  const SilageSummaryScreen({super.key});

  @override
  State<SilageSummaryScreen> createState() => _SilageSummaryScreenState();
}

class _SilageSummaryScreenState extends State<SilageSummaryScreen> {
  late final Storage storage = Storage();
  late final Future<List<Paddock>> _paddocksFuture;
  late final Future<List<SilageCut>> _silageCutsFuture;
  late final Future<Map<String, int>> _annualHarvestFuture;
  
  final Set<String> _selectedPaddockIds = {};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _paddocksFuture = storage.loadPaddocks();
    _silageCutsFuture = storage.loadAllSilageCuts();
    _annualHarvestFuture = storage.annualSilageHarvestAllPaddocksKgDm();
  }

  void _toggleSelection(String paddockId) {
    setState(() {
      if (_selectedPaddockIds.contains(paddockId)) {
        _selectedPaddockIds.remove(paddockId);
      } else {
        _selectedPaddockIds.add(paddockId);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedPaddockIds.clear();
    });
  }

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
    });
  }

  Future<void> _recordSilageCut() async {
    if (_selectedPaddockIds.isEmpty) return;

    // Show dialog to record silage cut details
    final residualCtrl = TextEditingController(text: '1200'); // Default residual
    var cutDate = DateTime.now();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Record silage cut'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('This will record a silage cut for selected paddocks.'),
                const SizedBox(height: 12),
                Text('Cut date: ${DateFormat('d MMM yyyy').format(cutDate)}'),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: cutDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => cutDate = picked);
                    }
                  },
                  child: const Text('Change date'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: residualCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Residual after cut (kgDM/ha)',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pre-cut cover will be taken from predicted cover. Harvest will be calculated from predicted cover minus residual.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
              ),
              child: const Text('Record cut'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final residual = int.tryParse(residualCtrl.text.trim()) ?? 1200;
    final clampedResidual = clampCover(residual);

    final List<dynamic> results = await Future.wait([
      storage.loadPaddocks(),
      storage.loadAllMeasurements(),
      storage.loadAllGrazings(),
    ]);

    final paddocks = results[0] as List<Paddock>;
    final measurements = results[1] as List<Measurement>;

    // Get selected paddocks
    final selectedPaddocks = paddocks.where((p) => _selectedPaddockIds.contains(p.id)).toList();

    // Simple predicted cover calculation
    int calculatePredictedCover(Paddock paddock) {
      // Get last measurement for this paddock
      final paddockMeasurements = measurements.where((m) => m.paddockId == paddock.id).toList();
      paddockMeasurements.sort((a, b) => b.at.compareTo(a.at));
      
      if (paddockMeasurements.isEmpty) {
        // No measurements, use default
        return 2000;
      }
      
      final lastMeasurement = paddockMeasurements.first;
      final daysSince = DateTime.now().difference(lastMeasurement.at).inDays;
      
      // Simple growth calculation: 20 kgDM/ha/day as default
      // This matches the home screen's fallback logic
      return clampCover(lastMeasurement.cover + (daysSince * 20));
    }

    // Record silage cut for each selected paddock
    for (final paddock in selectedPaddocks) {
      final preCover = calculatePredictedCover(paddock);
      final area = paddock.areaHa;
      final harvested = area > 0 
          ? ((preCover - clampedResidual) * area).round().clamp(0, 999999999)
          : 0;

      // Create silage cut record
      final silageCutId = const Uuid().v4();
      await storage.appendSilageCut(SilageCut(
        id: silageCutId,
        paddockId: paddock.id,
        at: cutDate,
        preCover: preCover,
        residual: clampedResidual,
        harvestedKgDm: harvested,
      ));

      // Reopen paddock for grazing (automatically reincluded)
      final updated = paddocks.map((p) {
        if (p.id == paddock.id) {
          return Paddock(
            id: p.id,
            name: p.name,
            areaHa: p.areaHa,
            recordOrder: p.recordOrder,
            includeInRotation: true, // Reincluded in rotation
            isSilage: p.isSilage,
            shutForSilage: false, // No longer shut for silage
          );
        }
        return p;
      }).toList();
      
      await storage.savePaddocks(updated);
    }

    // Add to activity log with summary
    final totalArea = selectedPaddocks.fold(0.0, (sum, p) => sum + p.areaHa);
    final totalHarvest = selectedPaddocks.fold(0, (sum, p) {
      final predicted = calculatePredictedCover(p);
      final area = p.areaHa;
      return sum + ((predicted - clampedResidual) * area).round();
    });
    final avgYield = totalArea > 0 ? totalHarvest / totalArea : 0;
    final avgYieldRounded = avgYield.round();
    final note = 'Silage cut: ${_selectedPaddockIds.length} paddock${_selectedPaddockIds.length == 1 ? '' : 's'}, ${totalArea.toStringAsFixed(1)} ha, $totalHarvest kgDM, $avgYieldRounded kgDM/ha avg';
    await storage.appendNote(NoteEntry(
      id: const Uuid().v4(),
      paddockId: '', // Farm-wide note
      at: DateTime.now(),
      title: note,
    ));

    _clearSelection();
    
    // Refresh data
    setState(() {
      _paddocksFuture = storage.loadPaddocks();
      _silageCutsFuture = storage.loadAllSilageCuts();
      _annualHarvestFuture = storage.annualSilageHarvestAllPaddocksKgDm();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Silage cut recorded for ${_selectedPaddockIds.length} paddock${_selectedPaddockIds.length == 1 ? '' : 's'}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Silage Summary'),
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                  tooltip: 'Cancel selection',
                ),
                if (_selectedPaddockIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.cut),
                    onPressed: _recordSilageCut,
                    tooltip: 'Record silage cut for selected paddocks',
                  ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.check_box_outlined),
                  onPressed: _enterSelectionMode,
                  tooltip: 'Select paddocks',
                ),
              ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: Future.wait([_paddocksFuture, _silageCutsFuture, _annualHarvestFuture]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }
          
          final List<dynamic> data = snapshot.data!;
          final paddocks = data[0] as List<Paddock>;
          final silageCuts = data[1] as List<SilageCut>;
          final annualHarvest = data[2] as Map<String, int>;
          
          final silagePaddocks = paddocks.where((p) => p.isSilage).toList();
          
          return _buildContent(silagePaddocks, silageCuts, annualHarvest);
        },
      ),
    );
  }

  Widget _buildContent(List<Paddock> silagePaddocks, List<SilageCut> silageCuts, Map<String, int> annualHarvest) {
    final totalArea = silagePaddocks.fold(0.0, (sum, p) => sum + p.areaHa);
    
    // Calculate total annual harvest
    final totalAnnualHarvest = annualHarvest.values.fold(0, (sum, harvest) => sum + harvest);
    
    // Group silage cuts by paddock
    final cutsByPaddock = <String, List<SilageCut>>{};
    for (final cut in silageCuts) {
      (cutsByPaddock[cut.paddockId] ??= []).add(cut);
    }
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!_selectionMode)
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Silage Summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.agriculture, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        '${silagePaddocks.length} paddock${silagePaddocks.length != 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.square_foot, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        '${totalArea.toStringAsFixed(1)} ha total',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  if (totalAnnualHarvest > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.grass, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          '${(totalAnnualHarvest / 1000).toStringAsFixed(1)} tDM harvested this year',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _enterSelectionMode,
                    icon: const Icon(Icons.cut),
                    label: const Text('Record Silage Cut'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
        
        const SizedBox(height: 16),
        
        if (silagePaddocks.isNotEmpty)
          _buildPaddockList(silagePaddocks, cutsByPaddock, annualHarvest)
        else
          const Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.agriculture, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No paddocks set aside for silage',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Go to Settings > Add/edit paddocks to mark paddocks as silage',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPaddockList(List<Paddock> silagePaddocks, Map<String, List<SilageCut>> cutsByPaddock, Map<String, int> annualHarvest) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_selectionMode)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Silage Paddocks',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ...silagePaddocks.map((paddock) {
          final paddockCuts = cutsByPaddock[paddock.id] ?? [];
          final lastCut = paddockCuts.isNotEmpty 
              ? paddockCuts.reduce((a, b) => a.at.isAfter(b.at) ? a : b)
              : null;
          final annualPaddockHarvest = annualHarvest[paddock.id] ?? 0;
          final isSelected = _selectedPaddockIds.contains(paddock.id);
          
          return GestureDetector(
            onLongPress: () {
              if (!_selectionMode) {
                _enterSelectionMode();
                _toggleSelection(paddock.id);
              }
            },
            onTap: () {
              if (_selectionMode) {
                _toggleSelection(paddock.id);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => PaddockHistoryScreen(paddock: paddock),
                  ),
                );
              }
            },
            child: Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: isSelected ? Colors.green.shade50 : null,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSelected ? Colors.green.shade300 : Colors.green.shade100,
                  child: Icon(
                    Icons.agriculture,
                    color: isSelected ? Colors.white : Colors.green,
                  ),
                ),
                title: Text(paddock.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${paddock.areaHa.toStringAsFixed(1)} ha'),
                    if (paddock.shutForSilage)
                      const Chip(
                        label: Text('Shut for silage'),
                        backgroundColor: Colors.orange,
                        labelStyle: TextStyle(fontSize: 12),
                      ),
                    if (lastCut != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last cut: ${lastCut.at.day}/${lastCut.at.month}/${lastCut.at.year}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        'Yield: ${(lastCut.harvestedKgDm / 1000).toStringAsFixed(1)} tDM (${lastCut.harvestedKgDm} kgDM)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                    if (annualPaddockHarvest > 0)
                      Text(
                        'Annual harvest: ${(annualPaddockHarvest / 1000).toStringAsFixed(1)} tDM',
                        style: const TextStyle(fontSize: 12, color: Colors.green),
                      ),
                  ],
                ),
                trailing: _selectionMode
                    ? Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelection(paddock.id),
                      )
                    : IconButton(
                        icon: const Icon(Icons.visibility),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => PaddockHistoryScreen(paddock: paddock),
                            ),
                          );
                        },
                      ),
              ),
            ),
          );
        }),
      ],
    );
  }
}