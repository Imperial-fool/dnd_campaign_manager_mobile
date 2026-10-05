import 'dart:async';

import 'package:dnd_campaign_manager/vtt/ui/vtt_measure.dart';
import 'package:dnd_campaign_manager/vtt/vtt_controller.dart';
import 'package:dnd_campaign_manager/vtt/vtt_models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum VttEditTool { pan, move, wall, window, door, eraseEdge, terrain, portal }

abstract class _VttUndoBatch {
  Future<void> undo(VttController controller);
}

class _VttEdgeUndoBatch implements _VttUndoBatch {
  _VttEdgeUndoBatch(this.mapId, this.previousEdges);

  final String mapId;
  final Map<String, VttEdge?> previousEdges;

  @override
  Future<void> undo(VttController controller) {
    final add = <VttEdge>[];
    final removeKeys = <String>[];
    for (final entry in previousEdges.entries) {
      if (entry.value == null) {
        removeKeys.add(entry.key);
      } else {
        add.add(_cloneEdge(entry.value!));
      }
    }
    return controller.setEdges(mapId, add: add, removeKeys: removeKeys);
  }
}

class _VttTerrainUndoBatch implements _VttUndoBatch {
  _VttTerrainUndoBatch(this.mapId, this.previousTerrain);

  final String mapId;
  final Map<String, String> previousTerrain;

  @override
  Future<void> undo(VttController controller) async {
    final grouped = <String, List<({int col, int row})>>{};
    for (final entry in previousTerrain.entries) {
      final parts = entry.key.split(',');
      final col = int.parse(parts[0]);
      final row = int.parse(parts[1]);
      grouped.putIfAbsent(entry.value, () => <({int col, int row})>[]).add(
        (col: col, row: row),
      );
    }
    for (final entry in grouped.entries) {
      await controller.paintTerrain(
        mapId,
        entry.value,
        entry.key == '.' ? null : int.tryParse(entry.key),
      );
    }
  }
}

class VttBoardUiState extends ChangeNotifier {
  bool editMode = false;
  VttEditTool editTool = VttEditTool.move;
  bool lockedDoor = false;
  int? terrainPaletteIndex = 0;
  VttMeasureMode measureMode = VttMeasureMode.none;
  int lineWidth = 1;
  String? selectedTokenId;
  String? _mapId;
  _VttUndoBatch? _undoBatch;

  bool get hasUndo => _undoBatch != null;
  bool get isEditingOnBoard => editMode && editTool != VttEditTool.pan;
  bool get measureActive => measureMode != VttMeasureMode.none;

  void syncMap(String? mapId) {
    if (_mapId == mapId) return;
    _mapId = mapId;
    selectedTokenId = null;
  }

  void setEditMode(bool value) {
    if (editMode == value) return;
    editMode = value;
    if (value) {
      measureMode = VttMeasureMode.none;
    }
    notifyListeners();
  }

  void setEditTool(VttEditTool value) {
    if (editTool == value) return;
    editTool = value;
    notifyListeners();
  }

  void setMeasureMode(VttMeasureMode value) {
    if (measureMode == value) return;
    measureMode = value;
    if (value != VttMeasureMode.none) {
      editMode = false;
    }
    notifyListeners();
  }

  void setLineWidth(int value) {
    final clamped = value.clamp(1, 4);
    if (lineWidth == clamped) return;
    lineWidth = clamped;
    notifyListeners();
  }

  void setSelectedToken(String? tokenId) {
    if (selectedTokenId == tokenId) return;
    selectedTokenId = tokenId;
    notifyListeners();
  }

  void setLockedDoor(bool value) {
    if (lockedDoor == value) return;
    lockedDoor = value;
    notifyListeners();
  }

  void setTerrainPaletteIndex(int? value) {
    if (terrainPaletteIndex == value) return;
    terrainPaletteIndex = value;
    notifyListeners();
  }

  void rememberEdgeUndo(String mapId, Map<String, VttEdge?> previousEdges) {
    _undoBatch = _VttEdgeUndoBatch(mapId, previousEdges);
    notifyListeners();
  }

  void rememberTerrainUndo(String mapId, Map<String, String> previousTerrain) {
    _undoBatch = _VttTerrainUndoBatch(mapId, previousTerrain);
    notifyListeners();
  }

  Future<void> undo(VttController controller) async {
    final batch = _undoBatch;
    if (batch == null) return;
    _undoBatch = null;
    notifyListeners();
    await batch.undo(controller);
  }
}

class VttMeasureToolbar extends StatelessWidget {
  const VttMeasureToolbar({super.key, required this.state});

  final VttBoardUiState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Measure'),
                ),
                for (final entry in const <(VttMeasureMode, String)>[
                  (VttMeasureMode.none, 'Off'),
                  (VttMeasureMode.ruler, 'Ruler'),
                  (VttMeasureMode.circle, 'Circle'),
                  (VttMeasureMode.cone, 'Cone'),
                  (VttMeasureMode.line, 'Line'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(entry.$2),
                      selected: state.measureMode == entry.$1,
                      onSelected: (_) => state.setMeasureMode(entry.$1),
                    ),
                  ),
                if (state.measureMode == VttMeasureMode.line) ...[
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: state.lineWidth,
                    items: [
                      for (var width = 1; width <= 4; width++)
                        DropdownMenuItem<int>(
                          value: width,
                          child: Text('Line width $width'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) state.setLineWidth(value);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VttMapEditToolbar extends StatelessWidget {
  const VttMapEditToolbar({super.key, required this.state});

  final VttBoardUiState state;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VttController>();
    if (!controller.isDm) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Edit map'),
                  selected: state.editMode,
                  onSelected: state.setEditMode,
                ),
                if (state.editMode) ...[
                  const SizedBox(width: 8),
                  for (final entry in const <(VttEditTool, String)>[
                    (VttEditTool.pan, 'Pan'),
                    (VttEditTool.move, 'Move'),
                    (VttEditTool.wall, 'Wall'),
                    (VttEditTool.window, 'Window'),
                    (VttEditTool.door, 'Door'),
                    (VttEditTool.eraseEdge, 'Erase'),
                    (VttEditTool.terrain, 'Terrain'),
                    (VttEditTool.portal, 'Portal'),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(entry.$2),
                        selected: state.editTool == entry.$1,
                        onSelected: (_) => state.setEditTool(entry.$1),
                      ),
                    ),
                  if (state.editTool == VttEditTool.door)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: const Text('Locked door'),
                        selected: state.lockedDoor,
                        onSelected: state.setLockedDoor,
                      ),
                    ),
                  if (state.editTool == VttEditTool.terrain)
                    ...List.generate(VttMap.terrainPalette.length + 1, (index) {
                      final paletteIndex = index == 0 ? null : index - 1;
                      final selected =
                          state.terrainPaletteIndex == paletteIndex;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: paletteIndex == null
                              ? const Text('Erase terrain')
                              : const Text(''),
                          avatar: paletteIndex == null
                              ? null
                              : CircleAvatar(
                                  backgroundColor: Color(
                                      VttMap.terrainPalette[paletteIndex]),
                                ),
                          selected: selected,
                          onSelected: (_) =>
                              state.setTerrainPaletteIndex(paletteIndex),
                        ),
                      );
                    }),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: state.hasUndo
                        ? () => _runAction(
                              context,
                              () => state.undo(controller),
                              prefix: 'Could not undo edit',
                            )
                        : null,
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _runAction(
  BuildContext context,
  FutureOr<void> Function() action, {
  required String prefix,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (!context.mounted) return;
    final controller = context.read<VttController>();
    final error = controller.error;
    if (error != null && error.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('$prefix: $error')));
  }
}

VttEdge _cloneEdge(VttEdge edge) => VttEdge(
      col: edge.col,
      row: edge.row,
      horizontal: edge.horizontal,
      type: edge.type,
      locked: edge.locked,
    );

/// Controllers must outlive the route's exit animation, which still rebuilds its fields.
void disposeAfterRouteExit(List<ChangeNotifier> notifiers) {
  Future<void>.delayed(const Duration(milliseconds: 500), () {
    for (final notifier in notifiers) {
      notifier.dispose();
    }
  });
}
