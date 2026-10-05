import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dnd_campaign_manager/logic/firebase_campaign_service.dart';
import 'package:dnd_campaign_manager/vtt/vtt_models.dart';
import 'package:dnd_campaign_manager/vtt/vtt_repository.dart';

class VttFirestoreRepository implements VttRepository {
  VttFirestoreRepository(
    FirebaseFirestore firestore,
    this._code,
    this.userId,
    this.isOwner,
  ) : _firestore = firestore;

  final FirebaseFirestore _firestore;
  final String _code;

  static VttRepository? fromService(FirebaseCampaignService service) {
    final firestore = service.firestore;
    final userId = service.userId;
    final code = service.joinCode;
    if (!service.isConnected ||
        firestore == null ||
        userId == null ||
        code == null) {
      return null;
    }
    return VttFirestoreRepository(
      firestore,
      code,
      userId,
      service.isOwner,
    );
  }

  @override
  final String userId;

  @override
  final bool isOwner;

  CollectionReference<Map<String, dynamic>> get _maps =>
      _campaign.doc(_code).collection('vttMaps');

  CollectionReference<Map<String, dynamic>> get _tokens =>
      _campaign.doc(_code).collection('vttTokens');

  CollectionReference<Map<String, dynamic>> get _mapImages =>
      _campaign.doc(_code).collection('vttMapImages');

  CollectionReference<Map<String, dynamic>> get _doorStates =>
      _campaign.doc(_code).collection('vttDoorStates');

  DocumentReference<Map<String, dynamic>> get _combat =>
      _campaign.doc(_code).collection('vtt').doc('combat');

  CollectionReference<Map<String, dynamic>> get _campaign =>
      _firestore.collection('campaigns');

  @override
  Stream<List<VttMap>> watchMaps() => _guardStream(
        _maps.snapshots().map(
              (snapshot) => snapshot.docs
                  .map(
                    (doc) => VttMap.fromJson(
                      <String, dynamic>{...doc.data(), 'id': doc.id},
                    ),
                  )
                  .toList(growable: false),
            ),
      );

  @override
  Stream<List<VttToken>> watchTokens() {
    final query = isOwner ? _tokens : _tokens.where('hidden', isEqualTo: false);
    return _guardStream(
      query.snapshots().map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) => VttToken.fromJson(
                    <String, dynamic>{...doc.data(), 'id': doc.id},
                  ),
                )
                .toList(growable: false),
          ),
    );
  }

  @override
  Stream<VttCombat> watchCombat() => _guardStream(
        _combat.snapshots().map((snapshot) {
          final data = snapshot.data();
          if (!snapshot.exists || data == null) {
            return const VttCombat();
          }
          return VttCombat.fromJson(data);
        }),
      );

  @override
  Stream<Map<String, Set<String>>> watchDoorStates() => _guardStream(
        _doorStates.snapshots().map((snapshot) {
          return <String, Set<String>>{
            for (final doc in snapshot.docs)
              doc.id: <String>{
                if (doc.data()['open'] is List)
                  for (final value in doc.data()['open'] as List)
                    if (value is String) value,
              },
          };
        }),
      );

  @override
  Future<void> saveMap(VttMap map) {
    _requireDm();
    return _maps.doc(map.id).set(<String, dynamic>{
      ...map.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteMap(String mapId) async {
    _requireDm();
    final tokenSnapshot = await _tokens.where('mapId', isEqualTo: mapId).get();
    final batch = _firestore.batch();
    batch.delete(_maps.doc(mapId));
    batch.delete(_mapImages.doc(mapId));
    batch.delete(_doorStates.doc(mapId));
    for (final doc in tokenSnapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  @override
  Future<void> saveToken(VttToken token) {
    _requireDm();
    return _tokens.doc(token.id).set(<String, dynamic>{
      ...token.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteToken(String tokenId) {
    _requireDm();
    return _tokens.doc(tokenId).delete();
  }

  @override
  Future<void> saveCombat(VttCombat combat) {
    _requireDm();
    return _combat.set(<String, dynamic>{
      ...combat.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> saveMapImage(String mapId, Uint8List jpegBytes) {
    _requireDm();
    return _mapImages.doc(mapId).set(<String, dynamic>{
      'data': base64Encode(jpegBytes),
      'mime': 'image/jpeg',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<Uint8List?> loadMapImage(String mapId) async {
    final snapshot = await _mapImages.doc(mapId).get();
    final data = snapshot.data();
    if (data == null || data['data'] is! String) return null;
    return Uint8List.fromList(base64Decode(data['data'] as String));
  }

  @override
  Future<void> deleteMapImage(String mapId) {
    _requireDm();
    return _mapImages.doc(mapId).delete();
  }

  @override
  Future<void> moveToken(String tokenId, String mapId, int col, int row) {
    return _tokens.doc(tokenId).update(<String, dynamic>{
      'mapId': mapId,
      'col': col,
      'row': row,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setInitiative(String tokenId, int? initiative) {
    return _tokens.doc(tokenId).update(<String, dynamic>{
      'initiative': initiative,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setDoorOpen(String mapId, String edgeKey, bool open) async {
    final ref = _doorStates.doc(mapId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final current = <String>{
        if (snapshot.data()?['open'] is List)
          for (final value in snapshot.data()!['open'] as List)
            if (value is String) value,
      };
      if (open) {
        current.add(edgeKey);
      } else {
        current.remove(edgeKey);
      }
      transaction.set(ref, <String, dynamic>{
        'open': current.toList()..sort(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<T> _guardStream<T>(Stream<T> source) async* {
    try {
      await for (final value in source) {
        yield value;
      }
    } catch (error, stackTrace) {
      yield* Stream<T>.error(error, stackTrace);
    }
  }

  void _requireDm() {
    if (!isOwner) {
      throw StateError('Only the DM can perform this action.');
    }
  }
}
