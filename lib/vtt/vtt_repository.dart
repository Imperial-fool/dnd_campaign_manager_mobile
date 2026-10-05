import 'dart:typed_data';

import 'package:dnd_campaign_manager/vtt/vtt_models.dart';

/// Storage/transport boundary for the VTT. Implementations: Firestore (shared
/// campaigns) and in-memory (tests). The VTT never touches CampaignController.
abstract class VttRepository {
  /// True when the current user is the DM / campaign owner.
  bool get isOwner;

  /// Firebase uid (or any stable id) of the current user.
  String get userId;

  /// Players only receive non-hidden tokens.
  Stream<List<VttMap>> watchMaps();
  Stream<List<VttToken>> watchTokens();
  Stream<VttCombat> watchCombat();
  Stream<Map<String, Set<String>>> watchDoorStates();

  // DM-only writes.
  Future<void> saveMap(VttMap map);

  /// Also deletes the tokens, image, and door state that live on the map.
  Future<void> deleteMap(String mapId);
  Future<void> saveToken(VttToken token);
  Future<void> deleteToken(String tokenId);
  Future<void> saveCombat(VttCombat combat);
  Future<void> saveMapImage(String mapId, Uint8List jpegBytes);
  Future<Uint8List?> loadMapImage(String mapId);
  Future<void> deleteMapImage(String mapId);

  // Allowed for the token's owner (and the DM).
  Future<void> moveToken(String tokenId, String mapId, int col, int row);
  Future<void> setInitiative(String tokenId, int? initiative);
  Future<void> setDoorOpen(String mapId, String edgeKey, bool open);
}
