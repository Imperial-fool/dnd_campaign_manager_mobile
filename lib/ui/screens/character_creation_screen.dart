import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/models/class_definition.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';

class CharacterCreationScreen extends StatefulWidget {
  const CharacterCreationScreen({super.key});

  @override
  State<CharacterCreationScreen> createState() =>
      _CharacterCreationScreenState();
}

class _CharacterCreationScreenState extends State<CharacterCreationScreen> {
  final _nameController = TextEditingController(text: 'New Character');
  final _playerController = TextEditingController();
  final _raceController = TextEditingController();
  final _backgroundController = TextEditingController();
  final _alignmentController = TextEditingController();
  final Map<String, Set<String>> _selections = {};
  ClassDefinition? _selectedClass;
  String _selectedSubclassId = '';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _playerController.dispose();
    _raceController.dispose();
    _backgroundController.dispose();
    _alignmentController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _levelOneChoices(ClassDefinition? definition) {
    if (definition == null) return [];
    final choices = definition.choicesAtLevel(1);
    if (_selectedSubclassId.isNotEmpty && definition.subclassLevel <= 1) {
      final subclass = subclassById(definition, _selectedSubclassId);
      if (subclass != null) {
        choices.addAll(subclass.choicesAtLevel(1, definition.id));
      }
    }
    return choices;
  }

  bool _choicesComplete(List<Map<String, dynamic>> choices) =>
      choices.every((choice) =>
          (_selections[asStr(choice['selectionKey'])]?.length ?? 0) ==
          asInt(choice['count'], 1));

  Future<void> _create(
    CampaignController campaign,
    List<Map<String, dynamic>> choices,
  ) async {
    final definition = _selectedClass;
    if (definition == null) return;
    setState(() => _saving = true);
    try {
      final character = await campaign.createCharacter(
        _nameController.text.trim().isEmpty
            ? 'New Character'
            : _nameController.text.trim(),
      );
      character
        ..player = _playerController.text.trim()
        ..race = _raceController.text.trim()
        ..background = _backgroundController.text.trim()
        ..alignment = _alignmentController.text.trim();

      final editor = campaign.editorFor(character);
      try {
        final subclass = _selectedSubclassId.isEmpty
            ? null
            : subclassById(definition, _selectedSubclassId);
        final error = editor.advanceLevel(
          definition,
          catalog: campaign.catalog,
          subclass: subclass,
          selections: {
            for (final entry in _selections.entries)
              entry.key: entry.value.toList(),
          },
        );
        if (error != null) {
          await campaign.deleteCharacter(character);
          throw StateError(error);
        }
        await editor.flush();
      } finally {
        editor.dispose();
      }
      if (mounted) Navigator.pop(context, character);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create character: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final campaign = context.watch<CampaignController>();
    final classes =
        campaign.catalog.items('classes').whereType<ClassDefinition>().toList();
    final definition = _selectedClass;
    final subclasses = definition?.subclasses.map(ClassSubclass.new).toList() ??
        <ClassSubclass>[];
    final requiresSubclass = definition != null &&
        definition.subclasses.isNotEmpty &&
        definition.subclassLevel <= 1;
    final choices = _levelOneChoices(definition);
    final canCreate = definition != null &&
        (!requiresSubclass || _selectedSubclassId.isNotEmpty) &&
        _choicesComplete(choices) &&
        !_saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Create character')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Character details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Character name'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _playerController,
                decoration: const InputDecoration(labelText: 'Player'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _raceController,
                decoration: const InputDecoration(labelText: 'Race'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _backgroundController,
                decoration: const InputDecoration(labelText: 'Background'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _alignmentController,
                decoration: const InputDecoration(labelText: 'Alignment'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 24),
              Text('Class', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(definition?.id),
                initialValue: definition?.id,
                decoration: const InputDecoration(labelText: 'Choose a class'),
                items: [
                  for (final classDefinition in classes)
                    DropdownMenuItem(
                      value: classDefinition.id,
                      child: Text(classDefinition.name),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (id) => setState(() {
                          _selectedClass = classes.firstWhere(
                            (classDefinition) => classDefinition.id == id,
                          );
                          _selectedSubclassId = '';
                          _selections.clear();
                        }),
              ),
              if (definition != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${definition.name} · ${definition.summary}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (requiresSubclass) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_selectedSubclassId),
                    initialValue: _selectedSubclassId.isEmpty
                        ? null
                        : _selectedSubclassId,
                    decoration:
                        const InputDecoration(labelText: 'Choose a subclass'),
                    items: [
                      for (final subclass in subclasses)
                        DropdownMenuItem(
                          value: subclass.id,
                          child: Text(subclass.name),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (id) => setState(() {
                              _selectedSubclassId = id ?? '';
                              _selections.clear();
                            }),
                  ),
                ],
                for (final choice in choices) ...[
                  const Divider(height: 28),
                  Text(
                    asStr(choice['prompt']),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  if (asInt(choice['count'], 1) == 1)
                    DropdownButtonFormField<String>(
                      key: ValueKey(asStr(choice['selectionKey'])),
                      initialValue: _selections[asStr(choice['selectionKey'])]
                          ?.firstOrNull,
                      decoration:
                          const InputDecoration(labelText: 'Choose one'),
                      items: [
                        for (final option in asMapList(choice['options']))
                          DropdownMenuItem(
                            value: asStr(option['id']),
                            child: Text(asStr(option['name'])),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (id) => setState(() {
                                if (id != null) {
                                  _selections[asStr(choice['selectionKey'])] = {
                                    id
                                  };
                                }
                              }),
                    )
                  else
                    for (final option in asMapList(choice['options']))
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(asStr(option['name'])),
                        subtitle: asStr(option['description']).isEmpty
                            ? null
                            : Text(asStr(option['description'])),
                        value: (_selections[asStr(choice['selectionKey'])] ??
                                const <String>{})
                            .contains(asStr(option['id'])),
                        onChanged: _saving
                            ? null
                            : (checked) => setState(() {
                                  final selected = _selections.putIfAbsent(
                                    asStr(choice['selectionKey']),
                                    () => {},
                                  );
                                  final id = asStr(option['id']);
                                  if (checked == true) {
                                    if (selected.length <
                                        asInt(choice['count'], 1)) {
                                      selected.add(id);
                                    }
                                  } else {
                                    selected.remove(id);
                                  }
                                }),
                      ),
                  if (asInt(choice['count'], 1) == 1)
                    Builder(builder: (context) {
                      final selectedId =
                          _selections[asStr(choice['selectionKey'])]
                              ?.firstOrNull;
                      final option = asMapList(choice['options'])
                          .where((item) => asStr(item['id']) == selectedId)
                          .firstOrNull;
                      final description = asStr(option?['description']);
                      return description.isEmpty
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(description),
                            );
                    }),
                ],
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: canCreate ? () => _create(campaign, choices) : null,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add),
                label: const Text('Create character'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
