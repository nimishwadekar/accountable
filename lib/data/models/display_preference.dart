class DisplayPreference {
  const DisplayPreference({
    required this.entityType,
    required this.entityId,
    required this.displayOrder,
    required this.showInApp,
    required this.showInEntryForms,
  });

  final String entityType;
  final String entityId;
  final int displayOrder;
  final bool showInApp;
  final bool showInEntryForms;

  DisplayPreference copyWith({
    String? entityType,
    String? entityId,
    int? displayOrder,
    bool? showInApp,
    bool? showInEntryForms,
  }) {
    return DisplayPreference(
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      displayOrder: displayOrder ?? this.displayOrder,
      showInApp: showInApp ?? this.showInApp,
      showInEntryForms: showInEntryForms ?? this.showInEntryForms,
    );
  }
}
