import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';
import '../utils.dart';

class PaddockRankingScreen extends StatefulWidget {
  const PaddockRankingScreen({super.key});

  @override
  State<PaddockRankingScreen> createState() => _PaddockRankingScreenState();
}

class _RankRow {
  final Paddock paddock;
  final int annualKgDm;

  _RankRow({required this.paddock, required this.annualKgDm});
}

class _PaddockRankingScreenState extends State<PaddockRankingScreen> {
  final storage = Storage();

  bool loaded = false;
  List<_RankRow> rows = [];

  String sortCol = 'harvest';
  bool sortAsc = false; // default: biggest first

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final paddocks = await storage.loadPaddocks();
    final harvestMap = await storage.annualHarvestAllPaddocksKgDm();

    final r = <_RankRow>[];
    for (final p in paddocks) {
      r.add(_RankRow(
        paddock: p,
        annualKgDm: harvestMap[p.id] ?? 0,
      ));
    }

    rows = r;
    loaded = true;
    setState(() {});
  }

  void _toggleSort(String col) {
    setState(() {
      if (sortCol == col) {
        sortAsc = !sortAsc;
      } else {
        sortCol = col;
        sortAsc = (col == 'paddock'); // paddock default asc, harvest default desc
        if (col == 'harvest') sortAsc = false;
      }
    });
  }

  List<_RankRow> _sorted() {
    final list = [...rows];
    list.sort((a, b) {
      int cmp;
      if (sortCol == 'paddock') {
        cmp = a.paddock.name.toLowerCase().compareTo(b.paddock.name.toLowerCase());
      } else {
        cmp = a.annualKgDm.compareTo(b.annualKgDm);
      }
      return sortAsc ? cmp : -cmp;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rankings')),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
          ? const Center(child: Text('No paddocks found.'))
          : Column(
        children: [
          _header(),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _sorted().length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final list = _sorted();
                final row = list[i];
                final rank = i + 1;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          '$rank',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.paddock.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          formatIntWithCommas(row.annualKgDm),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final isPdk = sortCol == 'paddock';
    final isHarv = sortCol == 'harvest';

    final pdkArrow = isPdk ? (sortAsc ? ' ▲' : ' ▼') : '';
    final harvArrow = isHarv ? (sortAsc ? ' ▲' : ' ▼') : '';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 44),
          Expanded(
            child: InkWell(
              onTap: () => _toggleSort('paddock'),
              child: Text(
                'Paddock$pdkArrow',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black87),
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: InkWell(
              onTap: () => _toggleSort('harvest'),
              child: Text(
                'Annual harvest$harvArrow',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
