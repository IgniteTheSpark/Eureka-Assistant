import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/auth_store.dart';
import '../app_events.dart' show navigatorKey;
import '../data_revision.dart';
import '../widgets/toast.dart';
import 'pet_cosmetics.dart';
import 'reka_notifications.dart';

/// §9 球球 — the user's pet, as returned by `/api/pet`. Immutable snapshot; the
/// controller swaps it wholesale on every refresh/mutation.
@immutable
class Pet {
  final bool spawned;
  final String name;
  final String seed;
  final String skin;
  final String emblem;
  final String emblemColor;
  final Map<String, String> equipped; // head / leftItem / rightItem / carrier / aura
  final Map<String, List<String>> unlocked; // skin / emblem / head / item / carrier / aura
  final PetMilestones milestones;

  const Pet({
    required this.spawned,
    required this.name,
    required this.seed,
    required this.skin,
    required this.emblem,
    required this.emblemColor,
    required this.equipped,
    required this.unlocked,
    required this.milestones,
  });

  factory Pet.fromJson(Map<String, dynamic> j) {
    final eq = (j['equipped'] as Map?) ?? const {};
    final un = (j['unlocked'] as Map?) ?? const {};
    List<String> list(dynamic v) => (v as List?)?.map((e) => '$e').toList() ?? <String>[];
    return Pet(
      spawned: j['spawned'] == true,
      name: (j['name'] as String?)?.trim().isNotEmpty == true ? j['name'] as String : 'Reka',
      seed: (j['seed'] as String?) ?? '',
      skin: (j['skin'] as String?) ?? 'aurora',
      emblem: (j['emblem'] as String?) ?? 'star',
      emblemColor: (j['emblem_color'] as String?) ?? 'gold',
      equipped: {
        'head': (eq['head'] as String?) ?? 'none',
        'leftItem': (eq['leftItem'] as String?) ?? 'none',
        'rightItem': (eq['rightItem'] as String?) ?? 'none',
        'carrier': (eq['carrier'] as String?) ?? 'none',
        'aura': (eq['aura'] as String?) ?? 'soft',
      },
      unlocked: {
        'skin': list(un['skin']),
        'emblem': list(un['emblem']),
        'head': list(un['head']),
        'item': list(un['item']),
        'carrier': un['carrier'] != null ? list(un['carrier']) : <String>['none'],
        'aura': un['aura'] != null ? list(un['aura']) : <String>['none', 'soft'],
      },
      milestones: PetMilestones.fromJson((j['milestones'] as Map?)?.cast<String, dynamic>() ?? const {}),
    );
  }

  /// The genome map PetView/mascot.js consumes (camelCase keys, hands resolved).
  Map<String, dynamic> get genome => {
        'skin': skin,
        'emblem': emblem,
        'emblemColor': emblemColor,
        'head': equipped['head'] ?? 'none',
        'leftItem': equipped['leftItem'] ?? 'none',
        'rightItem': equipped['rightItem'] ?? 'none',
        'carrier': equipped['carrier'] ?? 'none',
        'aura': equipped['aura'] ?? 'soft',
      };

  /// Flattened "slot:key" set of everything unlocked — for drop diffing.
  Set<String> get ownedKeys => {
        for (final entry in unlocked.entries)
          for (final k in entry.value) '${entry.key}:$k',
      };
}

@immutable
class PetMilestones {
  final int captureCount;
  final int streakDays;
  final List<String> domains;
  const PetMilestones({required this.captureCount, required this.streakDays, required this.domains});

  factory PetMilestones.fromJson(Map<String, dynamic> j) => PetMilestones(
        captureCount: (j['capture_count'] as num?)?.toInt() ?? 0,
        streakDays: (j['streak_days'] as num?)?.toInt() ?? 0,
        domains: (j['domains'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
}

/// A cosmetic the pet just brought back (for the celebrate toast).
@immutable
class PetDrop {
  final String slot; // skin | emblem | head | item
  final String key;
  const PetDrop(this.slot, this.key);
}

/// App-wide pet state. Singleton so the header badge, detail page and the drop
/// toast all read one source. Refreshes opportunistically (login + after any
/// write via [dataRevision]) so completion-driven drops surface as toasts.
class PetController extends ChangeNotifier {
  PetController._() {
    // Any write (a route pop / create / completion) → re-sync so completion-
    // driven drops surface as a toast even when the pet UI isn't open.
    dataRevision.addListener(_onRevision);
  }
  static final PetController instance = PetController._();

  final _api = ApiClient();

  void _onRevision() {
    if (AuthStore.token != null && _everLoaded && !loading) refresh();
  }

  Pet? pet;
  bool loading = false;
  bool _everLoaded = false; // suppress drop toasts on the very first snapshot

  // §9.5 the 40-milestone ladder + this user's progress (GET /api/pet/milestones).
  List<Map<String, dynamic>> milestones = const [];
  int milestonesAchieved = 0;

  bool get spawned => pet?.spawned == true;

  /// True once the first /api/pet fetch has resolved (success or error). The
  /// root gate (§9.2.2 onboarding) waits on this before choosing 孵化 vs shell —
  /// deciding while the pet is still null would flash the onboarding takeover at
  /// already-spawned returning users.
  bool get loaded => _everLoaded;

  /// Load once (no-op if already loaded). Safe to call repeatedly.
  Future<void> ensureLoaded() async {
    if (_everLoaded || loading) return;
    await refresh();
  }

  /// Drop all per-user state on logout. Without this the singleton keeps the
  /// previous account's pet (spawned=true) → the global floating REKA lingers on
  /// the login screen AND the next account's `ensureLoaded()` no-ops on the stale
  /// snapshot, skipping its 孵化 onboarding. Resetting `_everLoaded` forces a
  /// fresh /api/pet fetch for whoever logs in next.
  void reset() {
    pet = null;
    loading = false;
    _everLoaded = false;
    milestones = const [];
    milestonesAchieved = 0;
    notifyListeners();
  }

  /// Fetch the pet; diff unlocked cosmetics vs the previous snapshot and toast
  /// any new drops (skips the first load + the spawn starter set).
  Future<void> refresh() async {
    if (AuthStore.token == null) return;
    loading = true;
    notifyListeners();
    try {
      final prevOwned = pet?.ownedKeys;
      final res = await _api.getJson('/api/pet');
      final j = (res is Map ? res['pet'] : null) as Map?;
      if (j != null) {
        final next = Pet.fromJson(j.cast<String, dynamic>());
        // Only diff once we had a prior snapshot AND the pet was already spawned
        // (so the hatch starter kit doesn't fire a drop storm).
        if (prevOwned != null && pet?.spawned == true && next.spawned) {
          final drops = next.ownedKeys.difference(prevOwned);
          for (final d in drops) {
            final i = d.indexOf(':');
            if (i > 0) _toastDrop(PetDrop(d.substring(0, i), d.substring(i + 1)));
          }
        }
        pet = next;
      }
      // §9.5 milestone ladder + progress (best-effort, independent of the pet body).
      try {
        final mr = await _api.getJson('/api/pet/milestones');
        if (mr is Map && mr['milestones'] is List) {
          milestones = (mr['milestones'] as List)
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
          milestonesAchieved = ((mr['summary'] as Map?)?['achieved'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {/* keep the last known milestones */}
    } catch (_) {
      // best-effort; the pet is non-critical chrome
    } finally {
      loading = false;
      _everLoaded = true;
      notifyListeners();
    }
  }

  /// Hatch the egg (server assigns the starter emblem + unlocked kit).
  Future<void> spawn({String name = ''}) async {
    final res = await _api.postJson('/api/pet/spawn', {'name': name});
    _applyResult(res);
  }

  /// Rename via PATCH.
  Future<void> rename(String name) async {
    final res = await _api.patchJson('/api/pet', {'name': name});
    _applyResult(res);
  }

  /// Equip a cosmetic into a slot. [slot] ∈ skin | emblem | emblem_color | head |
  /// leftItem | rightItem | carrier | aura; [value] must be unlocked (or 'none').
  Future<void> equip(String slot, String value) async {
    final res = await _api.patchJson('/api/pet', {
      'equip': {slot: value},
    });
    _applyResult(res);
  }

  /// Equip several slots in one PATCH — used by the emblem component (which sets
  /// `emblem` + `emblem_color` together, since color is baked into the component).
  Future<void> equipAll(Map<String, String> slots) async {
    final res = await _api.patchJson('/api/pet', {'equip': slots});
    _applyResult(res);
  }

  void _applyResult(dynamic res) {
    final j = (res is Map ? res['pet'] : null) as Map?;
    if (j != null) {
      pet = Pet.fromJson(j.cast<String, dynamic>());
      _everLoaded = true;
      notifyListeners();
    }
  }

  void _toastDrop(PetDrop d) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final emoji = cosmeticEmoji(d.slot, d.key);
    final label = cosmeticLabel(d.slot, d.key);
    showToast(ctx, '$emoji ${pet?.name ?? 'Reka'} 带回了新装饰 · $label');
    RekaNotifications.instance.add(icon: emoji, title: '新装饰', meta: label);
  }
}
