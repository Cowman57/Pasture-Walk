import 'package:flutter/material.dart';

class InstructionsScreen extends StatelessWidget {
  const InstructionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How to use Pasture Walk')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _H1('Overview'),
          _P(
            'Pasture Walk helps you record pasture covers, estimate current covers for paddocks you haven’t measured today, '
                'and log grazing events. It also learns paddock growth differences over time (growth modifiers) to improve predictions.',
          ),

          _H1('Main screens'),
          _H2('Home screen'),
          _Bullets([
            'Shows paddocks with Area, last Recorded cover, and Predicted cover for today.',
            'Tap a paddock to open its History (Covers / Grazings / Notes).',
            'Long-press a paddock to enter selection mode (used to save grazing).',
          ]),

          _H2('Recording screen (Start / Resume Recording)'),
          _Bullets([
            'Walk paddocks in the set Recording Order.',
            'Enter today’s cover for each paddock. The big number is the value saved.',
            '“Last cover” shows the last recorded cover + how long ago it was.',
            '“Predicted” is the estimate for today based on the latest anchor and growth calculations.',
            'Use +/- buttons (step size is configurable in Settings) to adjust quickly.',
            'Use Skip to move on without saving a new value for that paddock.',
          ]),

          _H2('Paddock History'),
          _Bullets([
            'Covers tab: all recorded covers over time.',
            'Grazings tab: grazing events (pre, residual, harvested).',
            'Notes tab: quick notes you add during recording (e.g. weeds, leaks).',
          ]),

          _H1('Recording order & cropping exclusion'),
          _P(
            'In Recording order you can reorder paddocks and also exclude paddocks that are being cropped. '
                'Excluded paddocks will not appear in the Recording screen and are ignored in farm averages and KPI calculations.',
          ),

          _H1('Grazing logging'),
          _P(
            'From Home, long-press a paddock to enter selection mode. Tap multiple paddocks to select them, '
                'set the post-grazing residual, then Save grazing.',
          ),
          _Bullets([
            'Pre cover is the paddock’s predicted cover at the time you save the grazing.',
            'Residual is what you entered in the grazing bar.',
            'Harvested kgDM = (pre - residual) × area.',
            'Undo grazing removes grazings saved in the last 24 hours for selected paddocks.',
          ]),

          _H1('How predictions work (anchors + growth)'),
          _H2('Anchor'),
          _P('Each paddock has an anchor point used for predicting today’s cover. The anchor is the most recent of:'),
          _Bullets([
            'Last recorded measurement (cover), OR',
            'Last grazing residual (post-grazing cover).',
          ]),
          _P('Prediction starts from that anchor and adds growth since the anchor date.'),

          _H2('Farm growth rate'),
          _P(
            'Farm growth is calculated from your most recent cover measurements (included paddocks only). '
                'It is the change in cover divided by the number of days between those measurements.',
          ),

          _H2('Paddock growth modifiers'),
          _P(
            'Each paddock has a growth modifier. 1.00 means “average”. '
                'Above 1 grows faster than average; below 1 grows slower.',
          ),
          _P(
            'When you record a cover, the app compares the predicted cover at the time you entered the paddock '
                'to the cover you saved. If the paddock was not grazed between measurements, the modifier is nudged slightly '
                '(smoothed) to improve future predictions.',
          ),

          _H1('Notes buttons'),
          _P(
            'You can set two custom note button titles in Settings (e.g. “Weeds”, “Water leak”). '
                'During recording, tap a note button to add a dated note for that paddock.',
          ),

          _H1('Backup & restore'),
          _Bullets([
            'Backup saves everything (paddocks, order, settings, covers, grazings, notes, modifiers) to a .json file.',
            'Restore overwrites the current phone’s data with the backup file.',
            'Keep backups somewhere safe (Drive, USB, etc.).',
          ]),

          _H1('Tips'),
          _Bullets([
            'Record covers regularly (weekly is good) so the learning has decent data.',
            'Log grazings when you shift stock so predictions reset off residuals properly.',
            'Exclude cropped paddocks so they don’t skew averages.',
          ]),
        ],
      ),
    );
  }
}

// ---------- simple text widgets ----------
class _H1 extends StatelessWidget {
  final String text;
  const _H1(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _H2 extends StatelessWidget {
  final String text;
  const _H2(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _P extends StatelessWidget {
  final String text;
  const _P(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, height: 1.35),
      ),
    );
  }
}

class _Bullets extends StatelessWidget {
  final List<String> items;
  const _Bullets(this.items);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          for (final s in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(fontSize: 14, height: 1.35)),
                  Expanded(child: Text(s, style: const TextStyle(fontSize: 14, height: 1.35))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
