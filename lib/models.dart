class Paddock {
  final String id;
  final String name;
  final double areaHa;
  final int recordOrder;

  /// If false, paddock is excluded from the recording rotation (e.g. cropping).
  /// Defaults to true for backwards compatibility.
  final bool includeInRotation;

  /// If true, paddock is set aside for silage (excluded from round length & feed wedge).
  final bool isSilage;
  final bool shutForSilage;

  Paddock({
    required this.id,
    required this.name,
    required this.areaHa,
    required this.recordOrder,
    this.includeInRotation = true,
    this.isSilage = false,
    this.shutForSilage = false,
  });

Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'areaHa': areaHa,
    'recordOrder': recordOrder,
    'includeInRotation': includeInRotation,
    'isSilage': isSilage,
    'shutForSilage': shutForSilage,
  };

  static Paddock fromMap(Map<String, dynamic> m) => Paddock(
    id: m['id'],
    name: m['name'],
    areaHa: (m['areaHa'] as num).toDouble(),
    recordOrder: m['recordOrder'],
    includeInRotation: m['includeInRotation'] ?? true,
    isSilage: m['isSilage'] ?? false,
    shutForSilage: m['shutForSilage'] ?? false,
  );
}

class Herd {
  final String id;
  final String name;
  final int cowCount;
  final double areaGrazedPerDayHa;
  /// Manual supplement allocation (kgDM/cow/day).
  final double supplementKgDmPerCowPerDay;

  Herd({
    required this.id,
    required this.name,
    required this.cowCount,
    required this.areaGrazedPerDayHa,
    this.supplementKgDmPerCowPerDay = 0.0,
  });

  Herd copyWith({
    String? id,
    String? name,
    int? cowCount,
    double? areaGrazedPerDayHa,
    double? supplementKgDmPerCowPerDay,
  }) => Herd(
    id: id ?? this.id,
    name: name ?? this.name,
    cowCount: cowCount ?? this.cowCount,
    areaGrazedPerDayHa: areaGrazedPerDayHa ?? this.areaGrazedPerDayHa,
    supplementKgDmPerCowPerDay:
        supplementKgDmPerCowPerDay ?? this.supplementKgDmPerCowPerDay,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'cowCount': cowCount,
    'areaGrazedPerDayHa': areaGrazedPerDayHa,
    'supplementKgDmPerCowPerDay': supplementKgDmPerCowPerDay,
  };

  static Herd fromMap(Map<String, dynamic> m) => Herd(
    id: m['id'] as String,
    name: (m['name'] as String?)?.trim().isNotEmpty == true
        ? (m['name'] as String).trim()
        : 'Herd',
    cowCount: ((m['cowCount'] as num?)?.toInt() ?? 0).clamp(0, 999999999),
    areaGrazedPerDayHa: ((m['areaGrazedPerDayHa'] as num?)?.toDouble() ?? 0.0)
        .clamp(0.0, 999999999.0),
    supplementKgDmPerCowPerDay:
        ((m['supplementKgDmPerCowPerDay'] as num?)?.toDouble() ?? 0.0)
            .clamp(0.0, 999999999.0),
  );
}

/// Point-in-time total herd area grazed/day (target) for charts.
class HerdTargetSnapshot {
  final DateTime at;
  final double targetHaDay;

  HerdTargetSnapshot({required this.at, required this.targetHaDay});

  Map<String, dynamic> toMap() => {
    'at': at.toIso8601String(),
    'targetHaDay': targetHaDay,
  };

  static HerdTargetSnapshot fromMap(Map<String, dynamic> m) =>
      HerdTargetSnapshot(
        at: DateTime.parse(m['at'] as String),
        targetHaDay: ((m['targetHaDay'] as num?)?.toDouble() ?? 0.0)
            .clamp(0.0, 999999999.0),
      );
}

class Measurement {
  final String id;
  final String paddockId;
  final DateTime at;
  final int cover;
  final int predictedCoverAtEntry;

  Measurement({
    required this.id,
    required this.paddockId,
    required this.at,
    required this.cover,
    required this.predictedCoverAtEntry,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'paddockId': paddockId,
    'at': at.toIso8601String(),
    'cover': cover,
    'predictedCoverAtEntry': predictedCoverAtEntry,
  };

  static Measurement fromMap(Map<String, dynamic> m) => Measurement(
    id: m['id'],
    paddockId: m['paddockId'],
    at: DateTime.parse(m['at']),
    cover: m['cover'],
    predictedCoverAtEntry: m['predictedCoverAtEntry'],
  );
}

class Grazing {
  final String id;
  final String paddockId;
  final DateTime at;
  /// When this record was saved (used to group scheduled/future grazings by entry day).
  final DateTime enteredAt;
  final int preCover;
  final int residual;
  final int harvestedKgDm;
  /// How many calendar days this grazing occupies (for planning / ha/day spread).
  final int durationDays;

  Grazing({
    required this.id,
    required this.paddockId,
    required this.at,
    DateTime? enteredAt,
    required this.preCover,
    required this.residual,
    required this.harvestedKgDm,
    this.durationDays = 1,
  }) : enteredAt = enteredAt ?? at;

  Map<String, dynamic> toMap() => {
    'id': id,
    'paddockId': paddockId,
    'at': at.toIso8601String(),
    'enteredAt': enteredAt.toIso8601String(),
    'preCover': preCover,
    'residual': residual,
    'harvestedKgDm': harvestedKgDm,
    'durationDays': durationDays,
  };

  static Grazing fromMap(Map<String, dynamic> m) {
    final at = DateTime.parse(m['at']);
    final enteredRaw = m['enteredAt'];
    final enteredAt = enteredRaw != null
        ? DateTime.parse(enteredRaw as String)
        : at;
    final dur = ((m['durationDays'] as num?)?.toInt() ?? 1).clamp(1, 365);
    return Grazing(
      id: m['id'],
      paddockId: m['paddockId'],
      at: at,
      enteredAt: enteredAt,
      preCover: m['preCover'],
      residual: m['residual'],
      harvestedKgDm: m['harvestedKgDm'],
      durationDays: dur,
    );
  }
}

class NoteEntry {
  final String id;
  final String paddockId;
  final DateTime at;
  final String title;

  NoteEntry({
    required this.id,
    required this.paddockId,
    required this.at,
    required this.title,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'paddockId': paddockId,
    'at': at.toIso8601String(),
    'title': title,
  };

  static NoteEntry fromMap(Map<String, dynamic> m) => NoteEntry(
    id: m['id'],
    paddockId: m['paddockId'],
    at: DateTime.parse(m['at']),
    title: m['title'],
  );
}

class SilageCut {
  final String id;
  final String paddockId;
  final DateTime at;
  final int preCover;
  final int residual;
  final int harvestedKgDm;

  SilageCut({
    required this.id,
    required this.paddockId,
    required this.at,
    required this.preCover,
    required this.residual,
    required this.harvestedKgDm,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'paddockId': paddockId,
    'at': at.toIso8601String(),
    'preCover': preCover,
    'residual': residual,
    'harvestedKgDm': harvestedKgDm,
  };

  static SilageCut fromMap(Map<String, dynamic> m) => SilageCut(
    id: m['id'],
    paddockId: m['paddockId'],
    at: DateTime.parse(m['at']),
    preCover: m['preCover'],
    residual: m['residual'],
    harvestedKgDm: m['harvestedKgDm'],
  );
}
