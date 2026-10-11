import 'dart:math';

import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';

/// Inventory operations (ammo bookkeeping, using items). Pure Dart.
class Inventory {
  Inventory._();

  static final _caliberPattern = RegExp(
    r'^\s*(\.?\d+(?:\.\d+)?(?:\s*x\s*\d+(?:\.\d+)?)?)(?:\s*(mm|ga|gauge|bmg))?',
    caseSensitive: false,
  );

  static String _typeKey(String type) {
    final match = _caliberPattern.firstMatch(type);
    if (match == null) {
      return type.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    }
    final caliber =
        match.group(1)!.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final unit = switch (match.group(2)?.toLowerCase()) {
      'gauge' => 'ga',
      'mm' => '',
      final value => value ?? '',
    };
    return unit == 'bmg'
        ? '${caliber.replaceFirst('.', '')}$unit'
        : '$caliber$unit';
  }

  static bool _matches(InventoryItem i, String type) =>
      i.isAmmo && _typeKey(i.ammoType) == _typeKey(type);

  /// Total rounds of [type] across all matching ammo stacks.
  static int available(Character c, String type) {
    if (type.trim().isEmpty) return 0;
    return c.items
        .where((i) => _matches(i, type))
        .fold(0, (s, i) => s + max(0, i.quantity));
  }

  /// Removes up to [amount] rounds from matching stacks (first stack first).
  /// Returns how many were actually removed.
  static int consumeAmmo(Character c, String type, int amount) {
    var left = amount;
    for (final i in c.items.where((i) => _matches(i, type))) {
      if (left <= 0) break;
      final take = min(max(0, i.quantity), left);
      i.quantity -= take;
      left -= take;
    }
    return amount - left;
  }

  /// Use one charge. Items with [InventoryItem.usesMax] lose a use; when the
  /// current unit runs out, one unit of quantity is consumed and uses reset.
  /// Items without uses simply lose one from the stack.
  static void useOne(InventoryItem i) {
    if (i.usesMax > 0) {
      if (i.uses <= 0) i.uses = i.usesMax;
      i.uses -= 1;
      if (i.uses <= 0) {
        i.quantity -= 1;
        i.uses = i.quantity > 0 ? i.usesMax : 0;
      }
    } else {
      i.quantity -= 1;
    }
  }
}
