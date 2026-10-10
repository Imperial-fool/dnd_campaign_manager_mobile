enum FireMode {
  semi,
  burst,
  fullAuto;

  String get label => switch (this) {
        FireMode.semi => 'Semi',
        FireMode.burst => 'Burst',
        FireMode.fullAuto => 'Full auto',
      };

  static FireMode fromJson(Object? value) {
    for (final mode in FireMode.values) {
      if (value == mode.name) return mode;
    }
    throw FormatException('Unsupported firing mode "$value".');
  }

  static List<FireMode> listFromJson(Object? value) {
    if (value is! List) return [FireMode.semi];
    final modes = value.map(FireMode.fromJson).toSet().toList();
    return modes.isEmpty ? [FireMode.semi] : modes;
  }
}
