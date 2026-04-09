class Paddock {
  final String id;
  final String name;
  final double areaHa;
  final int recordOrder;

  /// If false, paddock is excluded from the recording rotation (e.g. cropping).
  /// Defaults to true for backwards compatibility.
  final bool includeInRotation;

  Paddock({
    required this.id,
    required this.name,
    required this.areaHa,
    required this.recordOrder,
    this.includeInRotation = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'areaHa': areaHa,
    'recordOrder': recordOrder,
    'includeInRotation': includeInRotation,
  };

  static Paddock fromMap(Map<String, dynamic> m) => Paddock(
    id: m['id'],
    name: m['name'],
    areaHa: (m['areaHa'] as num).toDouble(),
    recordOrder: m['recordOrder'],
    includeInRotation: (m['includeInRotation'] as bool?) ?? true,
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
  final int preCover;
  final int residual;
  final int harvestedKgDm;

  Grazing({
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

  static Grazing fromMap(Map<String, dynamic> m) => Grazing(
    id: m['id'],
    paddockId: m['paddockId'],
    at: DateTime.parse(m['at']),
    preCover: m['preCover'],
    residual: m['residual'],
    harvestedKgDm: m['harvestedKgDm'],
  );
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
