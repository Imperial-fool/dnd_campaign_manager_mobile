import 'dart:async';
import 'package:dnd_campaign_manager/logic/firebase_campaign_service.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/vtt/ui/vtt_map_tools.dart';
import 'package:dnd_campaign_manager/vtt/vtt_controller.dart';
import 'package:dnd_campaign_manager/vtt/vtt_models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class VttWidePanels extends StatelessWidget {
  const VttWidePanels({
    super.key,
    this.characters = const [],
    required this.uiState,
  });

  final List<Character> characters;
  final VttBoardUiState uiState;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _MapSwitcherCard(),
              const SizedBox(height: 12),
              _InitiativeCard(characters: characters),
              const SizedBox(height: 12),
              _BoardManagementCard(characters: characters, uiState: uiState),
            ],
          ),
        ),
      ),
    );
  }
}

class VttCompactPanels extends StatelessWidget {
  const VttCompactPanels({
    super.key,
    this.characters = const [],
    required this.uiState,
  });

  final List<Character> characters;
  final VttBoardUiState uiState;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VttController>();
    final tabCount = controller.isDm ? 2 : 1;
    return DefaultTabController(
      length: tabCount,
      child: Card(
        child: Column(
          children: [
            TabBar(
              tabs: [
                const Tab(text: 'Initiative'),
                if (controller.isDm) const Tab(text: 'Manage'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: _InitiativeCard(characters: characters),
                    ),
                  ),
                  if (controller.isDm)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        child: _BoardManagementCard(
                          characters: characters,
                          uiState: uiState,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapSwitcherCard extends StatelessWidget {
  const _MapSwitcherCard();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VttController>();
    final currentMapId = controller.currentMapId;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Map', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (controller.maps.isEmpty)
              const Text('No maps yet.')
            else
              DropdownButtonFormField<String>(
                key: const ValueKey('vtt-map-switcher'),
                initialValue: currentMapId ?? controller.maps.first.id,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final map in controller.maps)
                    DropdownMenuItem<String>(
                      value: map.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            map.isOverworld
                                ? Icons.public_outlined
                                : Icons.grid_3x3_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              map.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) controller.selectMap(value);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _InitiativeCard extends StatelessWidget {
  const _InitiativeCard({required this.characters});

  final List<Character> characters;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VttController>();
    final combat = controller.combat;
    final order = controller.initiativeOrder;
    final currentTurnId = controller.currentTurnToken?.id;
    final ownTokens = controller.tokens
        .where((token) => token.ownerUid == controller.userId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Initiative',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Chip(label: Text('Round ${combat.round}')),
              ],
            ),
            const SizedBox(height: 8),
            if (controller.isDm) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _runAction(
                      context,
                      controller.startCombat,
                      prefix: 'Could not start combat',
                    ),
                    child: const Text('Start combat'),
                  ),
                  FilledButton.tonal(
                    onPressed: combat.active
                        ? () => _runAction(
                              context,
                              controller.nextTurn,
                              prefix: 'Could not advance turn',
                            )
                        : null,
                    child: const Text('Next turn'),
                  ),
                  FilledButton.tonal(
                    onPressed: combat.active
                        ? () => _runAction(
                              context,
                              controller.endCombat,
                              prefix: 'Could not end combat',
                            )
                        : null,
                    child: const Text('End combat'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ] else if (ownTokens.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final token in ownTokens)
                    OutlinedButton.icon(
                      onPressed: () => _rollInitiative(
                        context,
                        controller,
                        token,
                        _initiativeBonusFor(token, characters),
                      ),
                      icon: const Icon(Icons.casino_outlined),
                      label: Text('Roll: ${token.name}'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (order.isEmpty)
              Text(
                combat.active
                    ? 'No tokens have initiative yet.'
                    : 'Combat order appears here when tokens have initiative.',
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: order.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final token = order[index];
                  final isCurrent = token.id == currentTurnId;
                  final isMine = token.ownerUid == controller.userId;
                  return ListTile(
                    dense: true,
                    selected: isCurrent,
                    selectedTileColor: Colors.amber.withValues(alpha: 0.18),
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Color(token.color),
                      child: Text(
                        '${token.initiative ?? '—'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(token.name),
                    subtitle: Text(
                      isCurrent && isMine && !controller.isDm
                          ? 'YOUR TURN'
                          : token.kind.toUpperCase(),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isCurrent)
                          const Icon(
                            Icons.play_circle_fill,
                            color: Colors.amber,
                          ),
                        if (controller.isDm)
                          IconButton(
                            tooltip: 'Roll initiative',
                            icon: const Icon(Icons.casino_outlined),
                            onPressed: () => _rollInitiative(
                              context,
                              controller,
                              token,
                              _initiativeBonusFor(token, characters),
                            ),
                          ),
                        if (controller.isDm)
                          IconButton(
                            tooltip: 'Edit initiative',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                _editInitiative(context, controller, token),
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  int _initiativeBonusFor(VttToken token, List<Character> characters) =>
      _initiativeBonus(token, characters);
}

int _initiativeBonus(VttToken token, List<Character> characters) {
  for (final character in characters) {
    if (character.id == token.characterId) return character.initiativeBonus;
  }
  return 0;
}

/// Compact, always-visible turn summary shown above the board.
class VttTurnBar extends StatelessWidget {
  const VttTurnBar({super.key, this.characters = const []});

  final List<Character> characters;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VttController>();
    final combat = controller.combat;
    final order = controller.initiativeOrder;
    final current = controller.currentTurnToken;
    final scheme = Theme.of(context).colorScheme;
    final isMyTurn = combat.active &&
        !controller.isDm &&
        current != null &&
        current.ownerUid == controller.userId;
    final unrolled = controller.tokens
        .where((t) =>
            t.initiative == null &&
            (controller.isDm || t.ownerUid == controller.userId))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (!combat.active && order.isEmpty && unrolled.isEmpty) {
      return const SizedBox.shrink();
    }

    final background =
        isMyTurn ? Colors.amber.shade700 : scheme.surfaceContainerHighest;
    final foreground = isMyTurn ? Colors.black : scheme.onSurface;

    String status;
    if (!combat.active) {
      status = 'Combat not started';
    } else if (isMyTurn) {
      status = "YOUR TURN — ${current.name}";
    } else if (current != null) {
      status = "${current.name}'s turn";
    } else {
      status = 'Waiting for first turn';
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    isMyTurn ? Icons.notifications_active : Icons.flag_outlined,
                    size: 18,
                    color: foreground,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      status,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (combat.active) Text('Rd ${combat.round}'),
                  if (unrolled.isNotEmpty)
                    PopupMenuButton<VttToken>(
                      tooltip: 'Roll initiative',
                      icon: Icon(Icons.casino_outlined, color: foreground),
                      onSelected: (token) => _rollInitiative(
                        context,
                        controller,
                        token,
                        _initiativeBonus(token, characters),
                      ),
                      itemBuilder: (_) => [
                        for (final token in unrolled)
                          PopupMenuItem<VttToken>(
                            value: token,
                            child: Text('Roll: ${token.name}'),
                          ),
                      ],
                    ),
                  if (controller.isDm && combat.active)
                    IconButton(
                      tooltip: 'Next turn',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.skip_next, color: foreground),
                      onPressed: () => _runAction(
                        context,
                        controller.nextTurn,
                        prefix: 'Could not advance turn',
                      ),
                    ),
                ],
              ),
              if (order.isNotEmpty)
                SizedBox(
                  height: 30,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: order.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final token = order[index];
                      final isCurrent = token.id == current?.id;
                      return Chip(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        backgroundColor: Color(token.color),
                        side: isCurrent
                            ? const BorderSide(color: Colors.amber, width: 2)
                            : BorderSide.none,
                        label: Text(
                          '${token.initiative} ${token.name}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight:
                                isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardManagementCard extends StatelessWidget {
  const _BoardManagementCard({
    required this.characters,
    required this.uiState,
  });

  final List<Character> characters;
  final VttBoardUiState uiState;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VttController>();
    if (!controller.isDm) return const SizedBox.shrink();
    final currentMap = controller.currentMap;
    final shared = context.watch<FirebaseCampaignService?>();
    final membersStream = shared != null && shared.isConnected && shared.isOwner
        ? shared.watchMembers()
        : const Stream<List<CampaignMember>>.empty();

    return StreamBuilder<List<CampaignMember>>(
      stream: membersStream,
      builder: (context, snapshot) {
        final members = snapshot.data ?? const <CampaignMember>[];
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DM tools', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _createMap(context, controller),
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Create map'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: currentMap == null
                          ? null
                          : () => _showMapSettingsSheet(
                                context,
                                controller,
                                currentMap,
                              ),
                      icon: const Icon(Icons.tune),
                      label: const Text('Map settings'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _importMapFile(context, controller),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Import map file'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: currentMap == null
                          ? null
                          : () => _exportMaps(context, controller, currentMap),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Export'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: currentMap == null
                          ? null
                          : () => _addToken(
                                context,
                                controller,
                                currentMap,
                                characters,
                                members,
                              ),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add token'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: uiState,
                  builder: (context, _) => Text(
                    uiState.editMode
                        ? 'Edit mode is active above the board.'
                        : 'Turn on Edit map above the board to draw walls, doors, windows, terrain, or portals.',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tokens on current map',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                if (controller.tokensOnCurrentMap.isEmpty)
                  const Text('No tokens on this map.')
                else
                  ...controller.tokensOnCurrentMap.map(
                    (token) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(token.color),
                          child: Text(token.kind.substring(0, 1).toUpperCase()),
                        ),
                        title: Text(token.name),
                        subtitle: Text([
                          '${token.kind.toUpperCase()} @ ${token.col}, ${token.row}',
                          if (token.hidden) 'Hidden',
                          if (token.ownerUid != null &&
                              token.ownerUid!.isNotEmpty)
                            'Owner ${_memberName(token.ownerUid, members)}',
                        ].join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit token',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editToken(
                                context,
                                controller,
                                token,
                                characters,
                                members,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove token',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _removeToken(
                                context,
                                controller,
                                token,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _createMap(BuildContext context, VttController controller) async {
  final values = await _showMapDialog(context);
  if (values == null) return;
  try {
    final map = await controller.createMap(
      name: values.name,
      cols: values.cols,
      rows: values.rows,
      isOverworld: values.isOverworld,
    );
    controller.selectMap(map.id);
    if (!context.mounted) return;
    _showControllerError(context, controller);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not create map: $error')),
    );
  }
}

Future<void> _showMapSettingsSheet(
  BuildContext context,
  VttController controller,
  VttMap map,
) async {
  final name = TextEditingController(text: map.name);
  final cols = TextEditingController(text: map.cols.toString());
  final rows = TextEditingController(text: map.rows.toString());
  final feetPerCell = TextEditingController(text: map.feetPerCell.toString());
  var showGrid = map.showGrid;
  var isOverworld = map.isOverworld;
  var diagonalRule = map.diagonalRule;
  var busy = false;

  Future<void> withBusy(
    StateSetter setState,
    Future<void> Function() action,
  ) async {
    setState(() => busy = true);
    try {
      await action();
    } finally {
      if (context.mounted) {
        setState(() => busy = false);
      }
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Map settings',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (busy) const CircularProgressIndicator(),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: cols,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Columns',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: rows,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Rows',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: feetPerCell,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Feet per cell',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<VttDiagonalRule>(
                      initialValue: diagonalRule,
                      decoration: const InputDecoration(
                        labelText: 'Diagonal rule',
                        border: OutlineInputBorder(),
                      ),
                      items: VttDiagonalRule.values
                          .map(
                            (rule) => DropdownMenuItem<VttDiagonalRule>(
                              value: rule,
                              child: Text(rule.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => diagonalRule = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                value: showGrid,
                title: const Text('Show grid'),
                contentPadding: EdgeInsets.zero,
                onChanged:
                    busy ? null : (value) => setState(() => showGrid = value),
              ),
              SwitchListTile(
                value: isOverworld,
                title: const Text('Overworld map'),
                contentPadding: EdgeInsets.zero,
                onChanged: busy
                    ? null
                    : (value) => setState(() => isOverworld = value),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => withBusy(
                              setState,
                              () => _pickAndSetBackgroundImage(
                                context,
                                controller,
                                map,
                              ),
                            ),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(map.hasImage ? 'Replace image' : 'Set image'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy || !map.hasImage
                        ? null
                        : () => withBusy(
                              setState,
                              () => _runAction(
                                context,
                                () => controller.clearMapImage(map.id),
                                prefix: 'Could not remove image',
                                controller: controller,
                              ),
                            ),
                    icon: const Icon(Icons.hide_image_outlined),
                    label: const Text('Remove image'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => withBusy(
                              setState,
                              () async {
                                final duplicated =
                                    await controller.duplicateMap(map.id);
                                controller.selectMap(duplicated.id);
                              },
                            ),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Duplicate map'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => withBusy(
                              setState,
                              () async {
                                final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: Text('Delete ${map.name}?'),
                                        content: const Text(
                                          'This also removes tokens on that map.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(
                                                dialogContext, false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(
                                                dialogContext, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    ) ??
                                    false;
                                if (!confirmed) return;
                                await controller.deleteMap(map.id);
                                if (context.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                              },
                            ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete map'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final parsedCols = int.tryParse(cols.text.trim());
                          final parsedRows = int.tryParse(rows.text.trim());
                          final parsedFeet =
                              int.tryParse(feetPerCell.text.trim());
                          if (parsedCols == null ||
                              parsedRows == null ||
                              parsedFeet == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter valid map settings.'),
                              ),
                            );
                            return;
                          }
                          await withBusy(
                            setState,
                            () => _runAction(
                              context,
                              () => controller.setMapSettings(
                                map.id,
                                name: name.text.trim(),
                                cols: parsedCols,
                                rows: parsedRows,
                                feetPerCell: parsedFeet,
                                showGrid: showGrid,
                                diagonalRule: diagonalRule,
                                isOverworld: isOverworld,
                              ),
                              prefix: 'Could not save map settings',
                              controller: controller,
                            ),
                          );
                          if (context.mounted) Navigator.pop(sheetContext);
                        },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  disposeAfterRouteExit([name, cols, rows, feetPerCell]);
}

Future<void> _pickAndSetBackgroundImage(
  BuildContext context,
  VttController controller,
  VttMap map,
) async {
  final file = await FilePicker.pickFile(
    type: FileType.image,
  );
  final bytes = file == null ? null : await file.readAsBytes();
  if (!context.mounted) return;
  if (bytes == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Image selection canceled.')),
    );
    return;
  }
  var fitGridToImage = false;
  final pixelsPerGrid = TextEditingController(text: '70');
  final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Background image'),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: fitGridToImage,
                    title: const Text('Fit grid to image'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) =>
                        setState(() => fitGridToImage = value),
                  ),
                  TextField(
                    controller: pixelsPerGrid,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pixels per grid cell',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ) ??
      false;
  final parsedPpg = int.tryParse(pixelsPerGrid.text.trim()) ?? 70;
  disposeAfterRouteExit([pixelsPerGrid]);
  if (!context.mounted || !confirmed) return;
  await _runAction(
    context,
    () => controller.setMapImage(
      map.id,
      bytes,
      fitGridToImage: fitGridToImage,
      pixelsPerGrid: parsedPpg,
    ),
    prefix: 'Could not set background image',
    controller: controller,
  );
}

Future<void> _importMapFile(
    BuildContext context, VttController controller) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['json', 'vttmap', 'dd2vtt', 'uvtt'],
  );
  if (!context.mounted) return;
  if (file == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Import canceled.')),
    );
    return;
  }
  try {
    final imported = await controller.importFile(
      await file.readAsBytes(),
      fileName: file.name,
    );
    if (!context.mounted) return;
    if (imported.maps.isNotEmpty) {
      controller.selectMap(imported.maps.first.id);
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import complete'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Imported ${imported.maps.length} map(s) and ${imported.tokensImported} token(s).',
                ),
                if (imported.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Warnings'),
                  for (final warning in imported.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $warning'),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not import map file: $error')),
    );
  }
}

Future<void> _exportMaps(
  BuildContext context,
  VttController controller,
  VttMap currentMap,
) async {
  var scope = 'current';
  var includeTokens = true;
  var format = 'native';
  final linkedIds = controller.linkedMapIds(currentMap.id);

  final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Export board'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: scope,
                    decoration: const InputDecoration(
                      labelText: 'Scope',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'current',
                        child: Text('This map only'),
                      ),
                      DropdownMenuItem(
                        value: 'linked',
                        enabled: format != 'dd2vtt',
                        child: Text(
                            'This map + linked maps (${linkedIds.length})'),
                      ),
                      DropdownMenuItem(
                        value: 'all',
                        enabled: format != 'dd2vtt',
                        child: Text('All maps (${controller.maps.length})'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => scope = value);
                    },
                  ),
                  const Divider(),
                  DropdownButtonFormField<String>(
                    initialValue: format,
                    decoration: const InputDecoration(
                      labelText: 'Format',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'native',
                        child: Text('.vttmap.json'),
                      ),
                      DropdownMenuItem(
                        value: 'dd2vtt',
                        child: Text('Universal VTT .dd2vtt'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        format = value;
                        if (format == 'dd2vtt') scope = 'current';
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeTokens,
                    title: const Text('Include NPC tokens'),
                    onChanged: format == 'dd2vtt'
                        ? (value) => setState(
                            () => includeTokens = value ?? includeTokens)
                        : (value) => setState(
                            () => includeTokens = value ?? includeTokens),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Export'),
              ),
            ],
          ),
        ),
      ) ??
      false;
  if (!context.mounted || !confirmed) return;

  try {
    late Uint8List bytes;
    late String fileName;
    late String mimeType;
    if (format == 'dd2vtt') {
      bytes = await controller.exportDd2vtt(currentMap.id);
      fileName = '${_safeFileName(currentMap.name)}.dd2vtt';
      mimeType = 'application/json';
    } else {
      final mapIds = switch (scope) {
        'linked' => linkedIds,
        'all' => controller.maps.map((map) => map.id).toList(growable: false),
        _ => <String>[currentMap.id],
      };
      bytes = await controller.exportMaps(mapIds, includeTokens: includeTokens);
      fileName = '${_safeFileName(currentMap.name)}.vttmap.json';
      mimeType = 'application/json';
    }
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: 'Save board export',
    );
    if (!context.mounted) return;
    final success = kIsWeb || uri != null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Board export saved.' : 'Export canceled.'),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not export board: $error')),
    );
  }
}

Future<void> _addToken(
  BuildContext context,
  VttController controller,
  VttMap currentMap,
  List<Character> characters,
  List<CampaignMember> members,
) async {
  final values = await _showTokenDialog(
    context,
    currentMap: currentMap,
    maps: controller.maps,
    characters: characters,
    members: members,
  );
  if (values == null) return;
  try {
    await controller.addToken(
      mapId: values.mapId,
      name: values.name,
      col: values.col,
      row: values.row,
      kind: values.kind,
      color: values.color,
      characterId: values.characterId,
      ownerUid: values.ownerUid,
      hidden: values.hidden,
    );
    if (!context.mounted) return;
    _showControllerError(context, controller);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not add token: $error')),
    );
  }
}

Future<void> _editToken(
  BuildContext context,
  VttController controller,
  VttToken token,
  List<Character> characters,
  List<CampaignMember> members,
) async {
  final map = controller.maps.firstWhere((entry) => entry.id == token.mapId);
  final values = await _showTokenDialog(
    context,
    currentMap: map,
    maps: controller.maps,
    characters: characters,
    members: members,
    initial: token,
  );
  if (values == null || !context.mounted) return;
  token
    ..mapId = values.mapId
    ..name = values.name
    ..col = values.col
    ..row = values.row
    ..kind = values.kind
    ..color = values.color
    ..characterId = values.characterId
    ..ownerUid = values.ownerUid
    ..hidden = values.hidden;
  await _runAction(
    context,
    () => controller.updateToken(token),
    prefix: 'Could not update token',
  );
}

Future<void> _removeToken(
  BuildContext context,
  VttController controller,
  VttToken token,
) async {
  await _runAction(
    context,
    () => controller.removeToken(token.id),
    prefix: 'Could not remove token',
  );
}

Future<void> _rollInitiative(
  BuildContext context,
  VttController controller,
  VttToken token,
  int bonus,
) async {
  try {
    final result = await controller.rollInitiative(token.id, bonus);
    if (!context.mounted) return;
    _showControllerError(context, controller);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${token.name} rolled $result initiative.')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not roll initiative: $error')),
    );
  }
}

Future<void> _editInitiative(
  BuildContext context,
  VttController controller,
  VttToken token,
) async {
  final field = TextEditingController(text: token.initiative?.toString() ?? '');
  final result = await showDialog<int?>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Initiative: ${token.name}'),
      content: TextField(
        controller: field,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Initiative',
          hintText: 'Blank clears initiative',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, null),
          child: const Text('Clear'),
        ),
        FilledButton(
          onPressed: () {
            final text = field.text.trim();
            Navigator.pop(
                dialogContext, text.isEmpty ? null : int.tryParse(text));
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  disposeAfterRouteExit([field]);
  if (!context.mounted) return;
  await _runAction(
    context,
    () => controller.setInitiative(token.id, result),
    prefix: 'Could not update initiative',
  );
}

Future<void> _runAction(
  BuildContext context,
  FutureOr<void> Function() action, {
  required String prefix,
  VttController? controller,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (!context.mounted) return;
    _showControllerError(context, controller ?? context.read<VttController>());
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('$prefix: $error')));
  }
}

void _showControllerError(BuildContext context, VttController controller) {
  final error = controller.error;
  if (error == null || error.isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error)),
  );
}

String _memberName(String? uid, List<CampaignMember> members) {
  if (uid == null || uid.isEmpty) return 'DM';
  for (final member in members) {
    if (member.uid == uid) return member.playerName;
  }
  return uid;
}

String _safeFileName(String name) =>
    name.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

class _MapDialogValues {
  const _MapDialogValues({
    required this.name,
    required this.cols,
    required this.rows,
    required this.isOverworld,
  });

  final String name;
  final int cols;
  final int rows;
  final bool isOverworld;
}

Future<_MapDialogValues?> _showMapDialog(
  BuildContext context, {
  VttMap? initial,
}) {
  final nameController = TextEditingController(text: initial?.name ?? '');
  final colsController =
      TextEditingController(text: (initial?.cols ?? 20).toString());
  final rowsController =
      TextEditingController(text: (initial?.rows ?? 20).toString());
  var isOverworld = initial?.isOverworld ?? false;
  return showDialog<_MapDialogValues>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(initial == null ? 'Create map' : 'Edit map'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: colsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Columns',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: rowsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Rows',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isOverworld,
                title: const Text('Overworld map'),
                onChanged: (value) => setState(() => isOverworld = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final cols = int.tryParse(colsController.text.trim());
              final rows = int.tryParse(rowsController.text.trim());
              if (cols == null || rows == null || cols < 1 || rows < 1) {
                return;
              }
              Navigator.pop(
                dialogContext,
                _MapDialogValues(
                  name: nameController.text.trim().isEmpty
                      ? 'Map'
                      : nameController.text.trim(),
                  cols: cols.clamp(1, VttMap.maxDimension),
                  rows: rows.clamp(1, VttMap.maxDimension),
                  isOverworld: isOverworld,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  ).whenComplete(() {
    disposeAfterRouteExit([nameController, colsController, rowsController]);
  });
}

class _TokenDialogValues {
  const _TokenDialogValues({
    required this.mapId,
    required this.name,
    required this.col,
    required this.row,
    required this.kind,
    required this.color,
    required this.characterId,
    required this.ownerUid,
    required this.hidden,
  });

  final String mapId;
  final String name;
  final int col;
  final int row;
  final String kind;
  final int color;
  final String? characterId;
  final String? ownerUid;
  final bool hidden;
}

Future<_TokenDialogValues?> _showTokenDialog(
  BuildContext context, {
  required VttMap currentMap,
  required List<VttMap> maps,
  required List<Character> characters,
  required List<CampaignMember> members,
  VttToken? initial,
}) {
  final nameController = TextEditingController(text: initial?.name ?? '');
  final colController =
      TextEditingController(text: (initial?.col ?? 0).toString());
  final rowController =
      TextEditingController(text: (initial?.row ?? 0).toString());
  final colorController = TextEditingController(
    text: ((initial?.color ?? 0xFF8D6E63) & 0xFFFFFFFF)
        .toRadixString(16)
        .padLeft(8, '0')
        .toUpperCase(),
  );
  var mapId = initial?.mapId ?? currentMap.id;
  var selectedCharacterId = initial?.characterId ?? '';
  var ownerUid = initial?.ownerUid ?? '';
  var hidden = initial?.hidden ?? false;
  var kind = initial?.kind ?? 'npc';

  Character? selectedCharacter() {
    for (final character in characters) {
      if (character.id == selectedCharacterId) return character;
    }
    return null;
  }

  return showDialog<_TokenDialogValues>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final linkedCharacter = selectedCharacter();
        return AlertDialog(
          title: Text(initial == null ? 'Add token' : 'Edit token'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue:
                        selectedCharacterId.isEmpty ? '' : selectedCharacterId,
                    decoration: const InputDecoration(
                      labelText: 'Linked character',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Generic token'),
                      ),
                      for (final character in characters)
                        DropdownMenuItem<String>(
                          value: character.id,
                          child: Text(character.name),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedCharacterId = value ?? '';
                        final character = selectedCharacter();
                        if (character != null) {
                          nameController.text = character.name;
                          kind = 'pc';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: mapId,
                    decoration: const InputDecoration(
                      labelText: 'Map',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final map in maps)
                        DropdownMenuItem<String>(
                          value: map.id,
                          child: Text(map.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => mapId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Token name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(
                      labelText: 'Kind',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'pc', child: Text('PC')),
                      DropdownMenuItem(value: 'npc', child: Text('NPC')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => kind = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: ownerUid,
                    decoration: const InputDecoration(
                      labelText: 'Owner',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('DM only'),
                      ),
                      for (final member in members)
                        DropdownMenuItem<String>(
                          value: member.uid,
                          child: Text(member.playerName),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => ownerUid = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: colController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Col',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: rowController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Row',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: colorController,
                    decoration: const InputDecoration(
                      labelText: 'Color (ARGB hex)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: hidden,
                    title: const Text('Hidden from players'),
                    onChanged: (value) => setState(() => hidden = value),
                  ),
                  if (linkedCharacter != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Initiative bonus: ${linkedCharacter.initiativeBonus}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final col = int.tryParse(colController.text.trim());
                final row = int.tryParse(rowController.text.trim());
                final color =
                    int.tryParse(colorController.text.trim(), radix: 16);
                if (col == null || row == null || color == null) return;
                Navigator.pop(
                  dialogContext,
                  _TokenDialogValues(
                    mapId: mapId,
                    name: nameController.text.trim().isEmpty
                        ? 'Token'
                        : nameController.text.trim(),
                    col: col,
                    row: row,
                    kind: kind,
                    color: color,
                    characterId: selectedCharacterId.isEmpty
                        ? null
                        : selectedCharacterId,
                    ownerUid: ownerUid.isEmpty ? null : ownerUid,
                    hidden: hidden,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  ).whenComplete(() {
    disposeAfterRouteExit([
      nameController,
      colController,
      rowController,
      colorController,
    ]);
  });
}
