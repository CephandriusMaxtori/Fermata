/// An action a Bluetooth page-turn pedal can trigger.
enum PedalAction {
  nextPage,
  previousPage,
  firstPage,
  lastPage,
  playPause,
  toggleMetronome;

  static PedalAction fromName(String name) => PedalAction.values.firstWhere(
    (action) => action.name == name,
    orElse: () => PedalAction.nextPage,
  );
}

/// Maps one HID key event to one app action.
///
/// Page-turn pedals present as Bluetooth keyboards and emit arrow or media
/// keys, and the exact codes differ per brand, so the mapping is user
/// configurable rather than hardcoded.
class PedalMapping {
  const PedalMapping({
    required this.id,
    required this.keyLabel,
    required this.action,
    this.platformKeyCode,
    this.enabled = true,
  });

  final String id;

  /// Human-readable key name shown in settings, e.g. "Volume Up".
  final String keyLabel;

  /// Raw platform key code, when one is known for this pedal.
  final int? platformKeyCode;

  final PedalAction action;
  final bool enabled;

  PedalMapping copyWith({
    String? keyLabel,
    int? platformKeyCode,
    PedalAction? action,
    bool? enabled,
  }) => PedalMapping(
    id: id,
    keyLabel: keyLabel ?? this.keyLabel,
    platformKeyCode: platformKeyCode ?? this.platformKeyCode,
    action: action ?? this.action,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'keyLabel': keyLabel,
    'platformKeyCode': platformKeyCode,
    'action': action.name,
    'enabled': enabled,
  };

  factory PedalMapping.fromJson(Map<String, dynamic> json) => PedalMapping(
    id: json['id'] as String,
    keyLabel: json['keyLabel'] as String,
    platformKeyCode: (json['platformKeyCode'] as num?)?.toInt(),
    action: PedalAction.fromName(json['action'] as String),
    enabled: (json['enabled'] as bool?) ?? true,
  );

  @override
  bool operator ==(Object other) =>
      other is PedalMapping &&
      other.id == id &&
      other.keyLabel == keyLabel &&
      other.platformKeyCode == platformKeyCode &&
      other.action == action &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(id, keyLabel, platformKeyCode, action, enabled);
}

/// The default bindings, covering the two conventions pedals actually ship
/// with: arrow keys and media keys.
const List<PedalMapping> kDefaultPedalMappings = [
  PedalMapping(
    id: 'default-right-arrow',
    keyLabel: 'Right Arrow',
    action: PedalAction.nextPage,
  ),
  PedalMapping(
    id: 'default-left-arrow',
    keyLabel: 'Left Arrow',
    action: PedalAction.previousPage,
  ),
  PedalMapping(
    id: 'default-media-next',
    keyLabel: 'Media Next',
    action: PedalAction.playPause,
  ),
  PedalMapping(
    id: 'default-media-previous',
    keyLabel: 'Media Previous',
    action: PedalAction.toggleMetronome,
  ),
];
