import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dnd_campaign_manager/vtt/ui/vtt_map_tools.dart';
import 'package:dnd_campaign_manager/vtt/ui/vtt_measure.dart';
import 'package:dnd_campaign_manager/vtt/vtt_controller.dart';
import 'package:dnd_campaign_manager/vtt/vtt_geometry.dart';
import 'package:dnd_campaign_manager/vtt/vtt_models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class VttBoard extends StatefulWidget {
  const VttBoard({super.key, required this.uiState});

  final VttBoardUiState uiState;

  @override
  State<VttBoard> createState() => _VttBoardState();
}

class _VttBoardState extends State<VttBoard> {
  static const double _cellSize = 48;
  static const double _edgeSnapThreshold = 12;

  final TransformationController _transformationController =
      TransformationController();

  int _activePointers = 0;
  int? _activePointerId;
  String? _imageMapId;
  int? _imageVersion;
  Uint8List? _imageBytes;
  String? _mapId;
  VttGridPoint? _measureStart;
  VttGridPoint? _measureCurrent;
  VttGridPoint? _dragStartCorner;
  VttGridPoint? _dragCurrentCorner;
  final Set<String> _eraseKeys = <String>{};
  final Set<String> _terrainKeys = <String>{};
  List<VttEdge> _previewEdges = const <VttEdge>[];

  @override
  void initState() {
    super.initState();
    widget.uiState.addListener(_handleUiStateChanged);
  }

  @override
  void didUpdateWidget(covariant VttBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uiState != widget.uiState) {
      oldWidget.uiState.removeListener(_handleUiStateChanged);
      widget.uiState.addListener(_handleUiStateChanged);
    }
  }

  @override
  void dispose() {
    widget.uiState.removeListener(_handleUiStateChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _handleUiStateChanged() {
    setState(() {
      if (!widget.uiState.measureActive) {
        _measureStart = null;
        _measureCurrent = null;
      }
      if (!widget.uiState.editMode) {
        _dragStartCorner = null;
        _dragCurrentCorner = null;
        _eraseKeys.clear();
        _terrainKeys.clear();
        _previewEdges = const <VttEdge>[];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VttController>();
    final map = controller.currentMap;
    final tokens = controller.tokensOnCurrentMap;
    final selectedToken = _findToken(tokens, widget.uiState.selectedTokenId);
    final currentTurnTokenId = controller.currentTurnToken?.id;

    if (map == null) {
      return Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              controller.isDm
                  ? 'Create a map from the Tools panel to start the board.'
                  : 'The DM has not created a board map yet.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    _syncBoardState(controller, map);
    final boardSize = Size(map.cols * _cellSize, map.rows * _cellSize);
    final measureOverlay = buildMeasureOverlay(
      map,
      widget.uiState.measureMode,
      _measureStart,
      _measureCurrent,
      lineWidth: widget.uiState.lineWidth,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              spacing: 12,
              children: [
                Text(
                  map.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${map.cols} × ${map.rows} · ${map.feetPerCell} ft/cell',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (selectedToken != null)
                  Chip(
                    avatar: const Icon(Icons.adjust, size: 16),
                    label: Text(
                      controller.canMove(selectedToken)
                          ? 'Selected: ${selectedToken.name}'
                          : 'Selected: ${selectedToken.name} (read only)',
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: InteractiveViewer(
                transformationController: _transformationController,
                constrained: false,
                minScale: 0.35,
                maxScale: 3.5,
                panEnabled: !widget.uiState.measureActive &&
                    !widget.uiState.isEditingOnBoard,
                boundaryMargin: const EdgeInsets.all(200),
                child: RepaintBoundary(
                  child: Listener(
                    onPointerDown: _usesDragGestures
                        ? (event) => _handlePointerDown(
                              context,
                              controller,
                              map,
                              event,
                            )
                        : null,
                    onPointerMove: _usesDragGestures
                        ? (event) => _handlePointerMove(map, event)
                        : null,
                    onPointerUp: _usesDragGestures
                        ? (event) => _handlePointerUp(
                              context,
                              controller,
                              map,
                              event,
                            )
                        : null,
                    onPointerCancel: _usesDragGestures
                        ? (event) => _handlePointerCancel(
                              context,
                              controller,
                              map,
                              event,
                            )
                        : null,
                    child: GestureDetector(
                      key: const ValueKey('vtt-board-gesture'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) => _handleTap(
                        context,
                        controller,
                        map,
                        tokens,
                        details.localPosition,
                      ),
                      child: SizedBox(
                        key: const ValueKey('vtt-board-surface'),
                        width: boardSize.width,
                        height: boardSize.height,
                        child: Stack(
                          children: [
                            if (_imageBytes != null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Image.memory(
                                    _imageBytes!,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.low,
                                  ),
                                ),
                              ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _BoardPainter(
                                  map: map,
                                  tokens: tokens,
                                  selectedTokenId: selectedToken?.id,
                                  currentTurnTokenId: currentTurnTokenId,
                                  isDm: controller.isDm,
                                  cellSize: _cellSize,
                                  openDoorKeys: controller.openDoorsFor(map.id),
                                  previewEdges: _previewEdges,
                                  eraseKeys: _eraseKeys,
                                  measureOverlay: measureOverlay,
                                ),
                              ),
                            ),
                            if (measureOverlay != null)
                              Positioned(
                                left: ((_measureStart?.col ?? 0) + 0.5) *
                                    _cellSize,
                                top: ((_measureStart?.row ?? 0) * _cellSize) -
                                    28,
                                child: Material(
                                  color: Colors.transparent,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        measureOverlay.label,
                                        key: const ValueKey(
                                          'vtt-measure-label',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _usesDragGestures {
    if (widget.uiState.measureActive) return true;
    if (!widget.uiState.editMode) return false;
    return switch (widget.uiState.editTool) {
      VttEditTool.wall ||
      VttEditTool.window ||
      VttEditTool.door ||
      VttEditTool.eraseEdge ||
      VttEditTool.terrain =>
        true,
      _ => false,
    };
  }

  void _handlePointerDown(
    BuildContext context,
    VttController controller,
    VttMap map,
    PointerDownEvent event,
  ) {
    _activePointers += 1;
    if (_activePointers != 1 || _activePointerId != null) return;
    _activePointerId = event.pointer;
    _handlePanStart(context, controller, map, event.localPosition);
  }

  void _handlePointerMove(VttMap map, PointerMoveEvent event) {
    if (_activePointerId != event.pointer || _activePointers != 1) return;
    _handlePanUpdate(map, event.localPosition);
  }

  void _handlePointerUp(
    BuildContext context,
    VttController controller,
    VttMap map,
    PointerUpEvent event,
  ) {
    if (_activePointers > 0) _activePointers -= 1;
    if (_activePointerId != event.pointer) return;
    _activePointerId = null;
    unawaited(_handlePanEnd(context, controller, map));
  }

  void _handlePointerCancel(
    BuildContext context,
    VttController controller,
    VttMap map,
    PointerCancelEvent event,
  ) {
    if (_activePointers > 0) _activePointers -= 1;
    if (_activePointerId != event.pointer) return;
    _activePointerId = null;
    unawaited(_handlePanEnd(context, controller, map));
  }

  void _syncBoardState(VttController controller, VttMap map) {
    if (_mapId != map.id) {
      _mapId = map.id;
      widget.uiState.syncMap(map.id);
      _measureStart = null;
      _measureCurrent = null;
      _dragStartCorner = null;
      _dragCurrentCorner = null;
      _previewEdges = const <VttEdge>[];
      _eraseKeys.clear();
      _terrainKeys.clear();
    }
    if (!map.hasImage) {
      _imageMapId = null;
      _imageVersion = null;
      _imageBytes = null;
    } else if (_imageMapId != map.id || _imageVersion != map.imageVersion) {
      unawaited(_loadImage(controller, map));
    }
  }

  Future<void> _loadImage(VttController controller, VttMap map) async {
    final bytes = await controller.imageFor(map.id);
    if (!mounted) return;
    if (controller.currentMapId != map.id) return;
    setState(() {
      _imageMapId = map.id;
      _imageVersion = map.imageVersion;
      _imageBytes = bytes;
    });
  }

  void _handlePanStart(
    BuildContext context,
    VttController controller,
    VttMap map,
    Offset localPosition,
  ) {
    if (widget.uiState.measureActive) {
      _measureStart = _cellAt(localPosition);
      _measureCurrent = _measureStart;
      setState(() {});
      return;
    }
    switch (widget.uiState.editTool) {
      case VttEditTool.wall:
      case VttEditTool.window:
      case VttEditTool.door:
        _dragStartCorner = _cornerAt(localPosition, map);
        _dragCurrentCorner = _dragStartCorner;
        _previewEdges = const <VttEdge>[];
        setState(() {});
      case VttEditTool.eraseEdge:
        _eraseKeys.clear();
        final edge = _nearestEdge(localPosition, map);
        if (edge != null) {
          _eraseKeys.add(edge.key);
        }
        setState(() {});
      case VttEditTool.terrain:
        _terrainKeys.clear();
        final cell = _cellAt(localPosition);
        if (map.contains(cell.col, cell.row)) {
          _terrainKeys.add(cell.key);
        }
        setState(() {});
      default:
        break;
    }
  }

  void _handlePanUpdate(VttMap map, Offset localPosition) {
    if (widget.uiState.measureActive) {
      _measureCurrent = _cellAt(localPosition);
      setState(() {});
      return;
    }
    switch (widget.uiState.editTool) {
      case VttEditTool.wall:
      case VttEditTool.window:
      case VttEditTool.door:
        final start = _dragStartCorner;
        if (start == null) return;
        final current = _cornerAt(localPosition, map);
        _dragCurrentCorner = _snapAxis(start, current);
        _previewEdges = edgesOnLine(
          start.col,
          start.row,
          _dragCurrentCorner!.col,
          _dragCurrentCorner!.row,
          type: _edgeTypeForTool(widget.uiState.editTool),
        ).map((edge) {
          edge.locked = widget.uiState.lockedDoor;
          return edge;
        }).toList(growable: false);
        setState(() {});
      case VttEditTool.eraseEdge:
        final edge = _nearestEdge(localPosition, map);
        if (edge != null) {
          _eraseKeys.add(edge.key);
          setState(() {});
        }
      case VttEditTool.terrain:
        final cell = _cellAt(localPosition);
        if (map.contains(cell.col, cell.row)) {
          _terrainKeys.add(cell.key);
          setState(() {});
        }
      default:
        break;
    }
  }

  Future<void> _handlePanEnd(
    BuildContext context,
    VttController controller,
    VttMap map,
  ) async {
    if (widget.uiState.measureActive) {
      setState(() {});
      return;
    }
    switch (widget.uiState.editTool) {
      case VttEditTool.wall:
      case VttEditTool.window:
      case VttEditTool.door:
        if (_previewEdges.isNotEmpty) {
          final previous =
              _capturePreviousEdges(map, _previewEdges.map((e) => e.key));
          await _runBoardAction(
            context,
            () => controller.setEdges(map.id, add: _previewEdges),
            prefix: 'Could not update map edges',
          );
          widget.uiState.rememberEdgeUndo(map.id, previous);
        }
        setState(() {
          _dragStartCorner = null;
          _dragCurrentCorner = null;
          _previewEdges = const <VttEdge>[];
        });
      case VttEditTool.eraseEdge:
        if (_eraseKeys.isNotEmpty) {
          final previous = _capturePreviousEdges(map, _eraseKeys);
          await _runBoardAction(
            context,
            () => controller.setEdges(map.id, removeKeys: _eraseKeys.toList()),
            prefix: 'Could not erase edges',
          );
          widget.uiState.rememberEdgeUndo(map.id, previous);
        }
        setState(_eraseKeys.clear);
      case VttEditTool.terrain:
        if (_terrainKeys.isNotEmpty) {
          final cells = _terrainKeys
              .map((key) => _cellFromKey(key))
              .where((cell) => map.contains(cell.col, cell.row))
              .toList(growable: false);
          final previous = _capturePreviousTerrain(map, cells);
          await _runBoardAction(
            context,
            () => controller.paintTerrain(
              map.id,
              cells
                  .map((cell) => (col: cell.col, row: cell.row))
                  .toList(growable: false),
              widget.uiState.terrainPaletteIndex,
            ),
            prefix: 'Could not paint terrain',
          );
          widget.uiState.rememberTerrainUndo(map.id, previous);
        }
        setState(_terrainKeys.clear);
      default:
        break;
    }
  }

  Future<void> _handleTap(
    BuildContext context,
    VttController controller,
    VttMap map,
    List<VttToken> tokens,
    Offset position,
  ) async {
    if (widget.uiState.measureActive) {
      final cell = _cellAt(position);
      setState(() {
        _measureStart = cell;
        _measureCurrent = cell;
      });
      return;
    }

    if (widget.uiState.editMode) {
      await _handleEditTap(context, controller, map, position);
      return;
    }

    final cell = _cellAt(position);
    if (!map.contains(cell.col, cell.row)) return;

    final tappedToken = _tokenAt(tokens, cell.col, cell.row);
    if (tappedToken != null) {
      widget.uiState.setSelectedToken(tappedToken.id);
      return;
    }

    final doorEdge = _nearestDoorEdge(position, map);
    if (doorEdge != null) {
      await _runBoardAction(
        context,
        () => controller.toggleDoor(map.id, doorEdge.key),
        prefix: 'Could not toggle door',
      );
      return;
    }

    final selectedToken = _findToken(tokens, widget.uiState.selectedTokenId);
    if (selectedToken == null || !controller.canMove(selectedToken)) return;

    try {
      final result =
          await controller.moveToken(selectedToken.id, cell.col, cell.row);
      if (!context.mounted) return;
      _showControllerError(context, controller);
      if (result.reason != null && result.reason!.isNotEmpty && !result.moved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.reason!)),
        );
      }
      final portal = result.portal;
      if (portal == null) return;
      final targetName = controller.maps
          .where((entry) => entry.id == portal.targetMapId)
          .map((entry) => entry.name)
          .cast<String?>()
          .firstWhere((entry) => entry != null, orElse: () => null);
      final promptName = portal.label.trim().isNotEmpty
          ? portal.label
          : (targetName ?? 'portal');
      final usePortal = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Portal'),
              content: Text('Enter $promptName?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Stay'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Enter'),
                ),
              ],
            ),
          ) ??
          false;
      if (!usePortal) return;
      await controller.usePortal(selectedToken.id);
      if (!context.mounted) return;
      _showControllerError(context, controller);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not move token: $error')),
      );
    }
  }

  Future<void> _handleEditTap(
    BuildContext context,
    VttController controller,
    VttMap map,
    Offset position,
  ) async {
    switch (widget.uiState.editTool) {
      case VttEditTool.move:
        final cell = _cellAt(position);
        if (!map.contains(cell.col, cell.row)) return;
        final token =
            _tokenAt(controller.tokensOnCurrentMap, cell.col, cell.row);
        widget.uiState.setSelectedToken(token?.id);
      case VttEditTool.portal:
        final cell = _cellAt(position);
        if (!map.contains(cell.col, cell.row)) return;
        await _editPortalAtCell(context, controller, map, cell);
      case VttEditTool.door:
        final edge = _nearestEdge(position, map);
        if (edge == null) return;
        final existing = map.edgeAt(edge.key);
        final previous = _capturePreviousEdges(map, <String>[edge.key]);
        if (existing?.type == VttEdgeType.door) {
          await _runBoardAction(
            context,
            () => controller.setEdges(map.id, removeKeys: <String>[edge.key]),
            prefix: 'Could not remove door',
          );
        } else {
          edge
            ..type = VttEdgeType.door
            ..locked = widget.uiState.lockedDoor;
          await _runBoardAction(
            context,
            () => controller.setEdges(map.id, add: <VttEdge>[edge]),
            prefix: 'Could not place door',
          );
        }
        widget.uiState.rememberEdgeUndo(map.id, previous);
      case VttEditTool.eraseEdge:
        final edge = _nearestEdge(position, map);
        if (edge == null) return;
        final previous = _capturePreviousEdges(map, <String>[edge.key]);
        await _runBoardAction(
          context,
          () => controller.setEdges(map.id, removeKeys: <String>[edge.key]),
          prefix: 'Could not erase edge',
        );
        widget.uiState.rememberEdgeUndo(map.id, previous);
      case VttEditTool.terrain:
        final cell = _cellAt(position);
        if (!map.contains(cell.col, cell.row)) return;
        final previous = _capturePreviousTerrain(map, <VttGridPoint>[cell]);
        await _runBoardAction(
          context,
          () => controller.paintTerrain(
            map.id,
            <({int col, int row})>[(col: cell.col, row: cell.row)],
            widget.uiState.terrainPaletteIndex,
          ),
          prefix: 'Could not paint terrain',
        );
        widget.uiState.rememberTerrainUndo(map.id, previous);
      default:
        break;
    }
  }

  Future<void> _editPortalAtCell(
    BuildContext context,
    VttController controller,
    VttMap map,
    VttGridPoint cell,
  ) async {
    final existing = map.portalAt(cell.col, cell.row);
    final targetMaps =
        controller.maps.where((entry) => entry.id != map.id).toList();
    String targetMapId = existing?.targetMapId ??
        (targetMaps.isNotEmpty ? targetMaps.first.id : '');
    final targetCol = TextEditingController(
      text: (existing?.targetCol ?? 0).toString(),
    );
    final targetRow = TextEditingController(
      text: (existing?.targetRow ?? 0).toString(),
    );
    final label = TextEditingController(text: existing?.label ?? '');
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null
              ? 'Portal at ${cell.col}, ${cell.row}'
              : 'Edit portal'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: targetMapId.isEmpty ? null : targetMapId,
                    decoration: const InputDecoration(
                      labelText: 'Target map',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final target in targetMaps)
                        DropdownMenuItem<String>(
                          value: target.id,
                          child: Text(target.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => targetMapId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: targetCol,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Target col',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: targetRow,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Target row',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: label,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'remove'),
                child: const Text('Remove'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: targetMaps.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    targetCol.dispose();
    targetRow.dispose();
    label.dispose();
    if (!context.mounted || action == null) return;
    if (action == 'remove') {
      await _runBoardAction(
        context,
        () => controller.removePortal(map.id, cell.col, cell.row),
        prefix: 'Could not remove portal',
      );
      return;
    }
    final parsedTargetCol = int.tryParse(targetCol.text.trim());
    final parsedTargetRow = int.tryParse(targetRow.text.trim());
    if (parsedTargetCol == null ||
        parsedTargetRow == null ||
        targetMapId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid portal destination.')),
      );
      return;
    }
    await _runBoardAction(
      context,
      () => controller.addPortal(
        map.id,
        VttPortal(
          col: cell.col,
          row: cell.row,
          targetMapId: targetMapId,
          targetCol: parsedTargetCol,
          targetRow: parsedTargetRow,
          label: label.text.trim(),
        ),
      ),
      prefix: 'Could not save portal',
    );
  }

  Map<String, VttEdge?> _capturePreviousEdges(
    VttMap map,
    Iterable<String> keys,
  ) {
    return <String, VttEdge?>{
      for (final key in keys)
        key: map.edgeAt(key) == null ? null : _cloneEdge(map.edgeAt(key)!),
    };
  }

  Map<String, String> _capturePreviousTerrain(
    VttMap map,
    Iterable<VttGridPoint> cells,
  ) {
    final result = <String, String>{};
    for (final cell in cells) {
      if (!map.contains(cell.col, cell.row)) continue;
      result[cell.key] = map.terrain[cell.row][cell.col];
    }
    return result;
  }

  VttGridPoint _cellAt(Offset position) {
    return VttGridPoint(
      (position.dx / _cellSize).floor(),
      (position.dy / _cellSize).floor(),
    );
  }

  VttGridPoint _cornerAt(Offset position, VttMap map) {
    return VttGridPoint(
      (position.dx / _cellSize).round().clamp(0, map.cols),
      (position.dy / _cellSize).round().clamp(0, map.rows),
    );
  }

  VttGridPoint _snapAxis(VttGridPoint start, VttGridPoint current) {
    final dx = current.col - start.col;
    final dy = current.row - start.row;
    if (dx.abs() >= dy.abs()) {
      return VttGridPoint(current.col, start.row);
    }
    return VttGridPoint(start.col, current.row);
  }

  VttEdge? _nearestDoorEdge(Offset position, VttMap map) {
    final edge = _nearestEdge(position, map);
    if (edge == null) return null;
    final existing = map.edgeAt(edge.key);
    if (existing == null || existing.type != VttEdgeType.door) return null;
    return existing;
  }

  VttEdge? _nearestEdge(Offset position, VttMap map) {
    final x = position.dx / _cellSize;
    final y = position.dy / _cellSize;
    final col = x.floor();
    final row = y.floor();
    if (col < -1 || row < -1 || col > map.cols || row > map.rows) return null;

    VttEdge? best;
    double bestDistance = _edgeSnapThreshold + 1;

    void consider(VttEdge edge, double distance) {
      if (distance > _edgeSnapThreshold || distance >= bestDistance) return;
      if (edge.horizontal) {
        if (edge.col < 0 ||
            edge.col >= map.cols ||
            edge.row < 0 ||
            edge.row > map.rows) {
          return;
        }
      } else {
        if (edge.col < 0 ||
            edge.col > map.cols ||
            edge.row < 0 ||
            edge.row >= map.rows) {
          return;
        }
      }
      best = edge;
      bestDistance = distance;
    }

    final fracX = (x - col) * _cellSize;
    final fracY = (y - row) * _cellSize;

    consider(
      VttEdge(col: col, row: row, horizontal: false),
      fracX.abs(),
    );
    consider(
      VttEdge(col: col + 1, row: row, horizontal: false),
      (_cellSize - fracX).abs(),
    );
    consider(
      VttEdge(col: col, row: row, horizontal: true),
      fracY.abs(),
    );
    consider(
      VttEdge(col: col, row: row + 1, horizontal: true),
      (_cellSize - fracY).abs(),
    );
    return best;
  }

  VttToken? _findToken(List<VttToken> tokens, String? tokenId) {
    if (tokenId == null) return null;
    for (final token in tokens) {
      if (token.id == tokenId) return token;
    }
    return null;
  }

  VttToken? _tokenAt(List<VttToken> tokens, int col, int row) {
    for (final token in tokens.reversed) {
      if (token.col == col && token.row == row) return token;
    }
    return null;
  }

  VttGridPoint _cellFromKey(String key) {
    final parts = key.split(',');
    return VttGridPoint(int.parse(parts[0]), int.parse(parts[1]));
  }
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter({
    required this.map,
    required this.tokens,
    required this.selectedTokenId,
    required this.currentTurnTokenId,
    required this.isDm,
    required this.cellSize,
    required this.openDoorKeys,
    required this.previewEdges,
    required this.eraseKeys,
    required this.measureOverlay,
  });

  final VttMap map;
  final List<VttToken> tokens;
  final String? selectedTokenId;
  final String? currentTurnTokenId;
  final bool isDm;
  final double cellSize;
  final Set<String> openDoorKeys;
  final List<VttEdge> previewEdges;
  final Set<String> eraseKeys;
  final VttMeasureOverlay? measureOverlay;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1D2128),
    );

    _paintTerrain(canvas);
    if (measureOverlay != null) {
      final fill = Paint()..color = const Color(0x8842A5F5);
      for (final cell in measureOverlay!.affectedCells) {
        canvas.drawRect(
          Rect.fromLTWH(
            cell.col * cellSize,
            cell.row * cellSize,
            cellSize,
            cellSize,
          ),
          fill,
        );
      }
    }
    if (map.showGrid) {
      _paintGrid(canvas, size);
    }
    _paintPortals(canvas);
    _paintEdges(canvas, map.edges, eraseKeys);
    _paintEdges(canvas, previewEdges, const <String>{}, preview: true);
    _paintMeasureGuides(canvas);
    for (final token in tokens) {
      _paintToken(canvas, token);
    }
  }

  void _paintTerrain(Canvas canvas) {
    for (var row = 0; row < map.terrain.length; row++) {
      final terrainRow = map.terrain[row];
      for (var col = 0; col < terrainRow.length; col++) {
        final char = terrainRow[col];
        if (char == '.') continue;
        final index = int.tryParse(char);
        if (index == null ||
            index < 0 ||
            index >= VttMap.terrainPalette.length) {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize),
          Paint()
            ..color =
                Color(VttMap.terrainPalette[index]).withValues(alpha: 0.66),
        );
      }
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    final majorGridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1.2;
    for (var col = 0; col <= map.cols; col++) {
      final x = col * cellSize;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        col % 5 == 0 ? majorGridPaint : gridPaint,
      );
    }
    for (var row = 0; row <= map.rows; row++) {
      final y = row * cellSize;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        row % 5 == 0 ? majorGridPaint : gridPaint,
      );
    }
  }

  void _paintEdges(
    Canvas canvas,
    List<VttEdge> edges,
    Set<String> erasedKeys, {
    bool preview = false,
  }) {
    for (final edge in edges) {
      if (preview || !erasedKeys.contains(edge.key)) {
        _paintEdge(canvas, edge, preview: preview);
      }
    }
    if (!preview) {
      for (final key in erasedKeys) {
        final edge = map.edgeAt(key);
        if (edge == null) continue;
        final points = _edgePoints(edge);
        canvas.drawLine(
          points.$1,
          points.$2,
          Paint()
            ..color = Colors.redAccent
            ..strokeWidth = 4,
        );
      }
    }
  }

  void _paintEdge(Canvas canvas, VttEdge edge, {bool preview = false}) {
    final points = _edgePoints(edge);
    final isOpenDoor =
        edge.type == VttEdgeType.door && openDoorKeys.contains(edge.key);
    final color = switch (edge.type) {
      VttEdgeType.wall => preview ? Colors.orange : const Color(0xFFEEE2CC),
      VttEdgeType.window =>
        preview ? Colors.lightBlueAccent : const Color(0xFF8DD5FF),
      VttEdgeType.door =>
        preview ? Colors.greenAccent : const Color(0xFFB08968),
    };
    final strokeWidth = switch (edge.type) {
      VttEdgeType.wall => 4.2,
      VttEdgeType.window => 2.0,
      VttEdgeType.door => 3.0,
    };
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (edge.type == VttEdgeType.door && isOpenDoor) {
      final mid = Offset.lerp(points.$1, points.$2, 0.5)!;
      final delta = points.$2 - points.$1;
      final normal = Offset(-delta.dy, delta.dx);
      final scaled = normal / normal.distance * (cellSize * 0.3);
      canvas.drawLine(points.$1, mid, paint);
      canvas.drawLine(mid, mid + scaled, paint);
      canvas.drawLine(
          mid, points.$2, paint..color = color.withValues(alpha: 0.25));
    } else {
      canvas.drawLine(points.$1, points.$2, paint);
    }

    if (edge.type == VttEdgeType.door && edge.locked) {
      final mid = Offset.lerp(points.$1, points.$2, 0.5)!;
      final lockPaint = Paint()..color = Colors.amberAccent;
      canvas.drawCircle(mid, 3.5, lockPaint);
      canvas.drawRect(
        Rect.fromCenter(center: mid + const Offset(0, 5), width: 7, height: 5),
        lockPaint,
      );
    }
  }

  void _paintPortals(Canvas canvas) {
    for (final portal in map.portals) {
      final rect = Rect.fromLTWH(
        portal.col * cellSize + 4,
        portal.row * cellSize + 4,
        cellSize - 8,
        cellSize - 8,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        Paint()..color = const Color(0xFF26A69A).withValues(alpha: 0.85),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        Paint()
          ..color = Colors.white70
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _paintMeasureGuides(Canvas canvas) {
    final overlay = measureOverlay;
    if (overlay == null) return;
    final start = Offset(
      (overlay.start.col + 0.5) * cellSize,
      (overlay.start.row + 0.5) * cellSize,
    );
    final end = Offset(
      (overlay.end.col + 0.5) * cellSize,
      (overlay.end.row + 0.5) * cellSize,
    );
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 3,
    );
    canvas.drawCircle(start, 5, Paint()..color = Colors.white);
    canvas.drawCircle(end, 5, Paint()..color = Colors.cyanAccent);
  }

  void _paintToken(Canvas canvas, VttToken token) {
    final center = Offset(
      token.col * cellSize + cellSize / 2,
      token.row * cellSize + cellSize / 2,
    );
    final radius = cellSize * 0.34;
    final fillColor = Color(token.color);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = token.hidden && isDm
            ? fillColor.withValues(alpha: 0.45)
            : fillColor,
    );
    if (token.id == currentTurnTokenId) {
      canvas.drawCircle(
        center,
        radius + 5,
        Paint()
          ..color = const Color(0xFFFFD54F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    if (token.id == selectedTokenId) {
      canvas.drawCircle(
        center,
        radius + 9,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    if (token.hidden && isDm) {
      final dashPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      const dashCount = 12;
      for (var i = 0; i < dashCount; i++) {
        final start = (math.pi * 2 / dashCount) * i;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius + 1),
          start,
          0.18,
          false,
          dashPaint,
        );
      }
    } else {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    final initials = _initials(token.name);
    final textPainter = TextPainter(
      text: TextSpan(
        text: initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2),
    );
  }

  (Offset, Offset) _edgePoints(VttEdge edge) {
    if (edge.horizontal) {
      return (
        Offset(edge.col * cellSize, edge.row * cellSize),
        Offset((edge.col + 1) * cellSize, edge.row * cellSize),
      );
    }
    return (
      Offset(edge.col * cellSize, edge.row * cellSize),
      Offset(edge.col * cellSize, (edge.row + 1) * cellSize),
    );
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) {
    return oldDelegate.map != map ||
        oldDelegate.tokens != tokens ||
        oldDelegate.selectedTokenId != selectedTokenId ||
        oldDelegate.currentTurnTokenId != currentTurnTokenId ||
        oldDelegate.isDm != isDm ||
        oldDelegate.openDoorKeys != openDoorKeys ||
        oldDelegate.previewEdges != previewEdges ||
        oldDelegate.eraseKeys != eraseKeys ||
        oldDelegate.measureOverlay != measureOverlay;
  }
}

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    return words.first
        .substring(0, math.min(2, words.first.length))
        .toUpperCase();
  }
  return '${words.first[0]}${words.last[0]}'.toUpperCase();
}

VttEdgeType _edgeTypeForTool(VttEditTool tool) {
  return switch (tool) {
    VttEditTool.wall => VttEdgeType.wall,
    VttEditTool.window => VttEdgeType.window,
    VttEditTool.door => VttEdgeType.door,
    _ => VttEdgeType.wall,
  };
}

VttEdge _cloneEdge(VttEdge edge) => VttEdge(
      col: edge.col,
      row: edge.row,
      horizontal: edge.horizontal,
      type: edge.type,
      locked: edge.locked,
    );

Future<void> _runBoardAction(
  BuildContext context,
  Future<void> Function() action, {
  required String prefix,
}) async {
  try {
    await action();
    if (!context.mounted) return;
    final controller = context.read<VttController>();
    _showControllerError(context, controller);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$prefix: $error')),
    );
  }
}

void _showControllerError(BuildContext context, VttController controller) {
  final error = controller.error;
  if (error == null || error.isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error)),
  );
}
