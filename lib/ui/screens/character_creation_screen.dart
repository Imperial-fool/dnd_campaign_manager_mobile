import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/dice.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/class_definition.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';

class CharacterCreationScreen extends StatefulWidget {
  const CharacterCreationScreen({super.key});

  @override
  State<CharacterCreationScreen> createState() =>
      _CharacterCreationScreenState();
}

class _AbilityScoreRoll {
  const _AbilityScoreRoll({
    required this.rolls,
    required this.droppedRolls,
    required this.score,
  });

  final List<int> rolls;
  final List<int> droppedRolls;
  final int score;
}

class _CharacterCreationScreenState extends State<CharacterCreationScreen> {
  final _nameController = TextEditingController(text: 'New Character');
  final _playerController = TextEditingController();
  final _raceController = TextEditingController();
  final _backgroundController = TextEditingController();
  final _alignmentController = TextEditingController();
  final Map<String, Set<String>> _selections = {};
  final Map<Ability, int> _assignedScores = {};
  final DiceRoller _dice = DiceRoller();
  List<_AbilityScoreRoll> _rolledScores = [];
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
    setState(() => _saving = true);
    try {
      final character = Character(id: newId())
        ..name = _nameController.text.trim().isEmpty
            ? 'New Character'
            : _nameController.text.trim()
        ..player = _playerController.text.trim()
        ..race = _raceController.text.trim()
        ..background = _backgroundController.text.trim()
        ..alignment = _alignmentController.text.trim();
      for (final entry in _assignedScores.entries) {
        character.abilityScores[entry.key] = _rolledScores[entry.value].score;
      }

      if (definition != null) {
        final editor = CharacterController(
          character: character,
          repository: _DraftRepository(),
        );
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
          if (error != null) throw StateError(error);
        } finally {
          editor.dispose();
        }
      }
      await campaign.createCharacterFromSheet(character);
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

  void _rollAbilityScores(Map<String, dynamic> rules) {
    final diceCount = asInt(rules['diceCount'], 4);
    final dieSides = asInt(rules['dieSides'], 6);
    final dropLowest = asInt(rules['dropLowest'], 1);
    final scoreCount = asInt(rules['scoreCount'], Ability.values.length);
    if (diceCount < 1 ||
        diceCount > 20 ||
        dieSides < 2 ||
        dieSides > 1000 ||
        dropLowest < 0 ||
        dropLowest >= diceCount ||
        scoreCount != Ability.values.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid ability score roll settings.')),
      );
      return;
    }
    setState(() {
      _rolledScores = List.generate(scoreCount, (_) {
        final rolls = List.generate(diceCount, (_) => _dice.die(dieSides));
        final sorted = [...rolls]..sort();
        final score = sorted.skip(dropLowest).fold<int>(0, (a, b) => a + b);
        return _AbilityScoreRoll(
          rolls: rolls,
          droppedRolls: sorted.take(dropLowest).toList(),
          score: score,
        );
      });
      _assignedScores.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final campaign = context.watch<CampaignController>();
    final playerMode = campaign.sharedCampaign?.isConnected == true &&
        campaign.sharedCampaign?.isOwner == false;
    final rawAbilityRules = campaign.creationRules['abilityScoreGeneration'];
    final abilityRules = rawAbilityRules is Map
        ? Map<String, dynamic>.from(rawAbilityRules)
        : const <String, dynamic>{};
    final classes =
        campaign.catalog.items('classes').whereType<ClassDefinition>().toList();
    final definition = _selectedClass;
    final subclasses = definition?.subclasses.map(ClassSubclass.new).toList() ??
        <ClassSubclass>[];
    final requiresSubclass = definition != null &&
        definition.subclasses.isNotEmpty &&
        definition.subclassLevel <= 1;
    final choices = _levelOneChoices(definition);
    final allScoresAssigned = _rolledScores.isEmpty ||
        Ability.values.every(_assignedScores.containsKey);
    final canCreate = (classes.isEmpty ||
            (definition != null &&
                (!requiresSubclass || _selectedSubclassId.isNotEmpty) &&
                _choicesComplete(choices))) &&
        allScoresAssigned &&
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
              if (!playerMode) ...[
                TextField(
                  controller: _playerController,
                  decoration: const InputDecoration(labelText: 'Player'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 8),
              ],
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
              Text('Ability scores',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed:
                    _saving ? null : () => _rollAbilityScores(abilityRules),
                icon: const Icon(Icons.casino_outlined),
                label: Text(
                  'Roll ${asInt(abilityRules['diceCount'], 4)}d'
                  '${asInt(abilityRules['dieSides'], 6)}'
                  ' · drop lowest ${asInt(abilityRules['dropLowest'], 1)}',
                ),
              ),
              if (_rolledScores.isNotEmpty) ...[
                for (var index = 0; index < _rolledScores.length; index++)
                  Text(
                    'Roll ${index + 1}: '
                    '${_rolledScores[index].rolls.join(', ')}'
                    ' · dropped [${_rolledScores[index].droppedRolls.join(', ')}]'
                    ' · score ${_rolledScores[index].score}',
                  ),
                const SizedBox(height: 8),
                for (final ability in Ability.values)
                  Row(
                    children: [
                      SizedBox(width: 56, child: Text(ability.label)),
                      Expanded(
                        child: DropdownButton<int>(
                          value: _assignedScores[ability],
                          hint: const Text('Choose a roll'),
                          isExpanded: true,
                          items: [
                            for (var index = 0;
                                index < _rolledScores.length;
                                index++)
                              if (!_assignedScores.entries.any((entry) =>
                                  entry.key != ability && entry.value == index))
                                DropdownMenuItem(
                                  value: index,
                                  child: Text(
                                    'Roll ${index + 1}: '
                                    '${_rolledScores[index].score}',
                                  ),
                                ),
                          ],
                          onChanged: _saving
                              ? null
                              : (index) => setState(() {
                                    if (index == null) {
                                      _assignedScores.remove(ability);
                                    } else {
                                      _assignedScores[ability] = index;
                                    }
                                  }),
                        ),
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: 24),
              if (classes.isEmpty)
                const Text(
                  'No class definitions are loaded. The character will start '
                  'without a class; the DM can add one later.',
                )
              else ...[
                Text('Class', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey(definition?.id),
                  initialValue: definition?.id,
                  decoration:
                      const InputDecoration(labelText: 'Choose a class'),
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
              ],
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

class _DraftRepository implements CampaignRepository {
  @override
  Future<List<Character>> loadCharacters() async => [];

  @override
  Future<void> saveCharacter(Character character) async {}

  @override
  Future<void> deleteCharacter(String id) async {}

  @override
  Future<Map<String, dynamic>> loadCatalogJson() async => {};

  @override
  Future<void> saveCatalogJson(Map<String, dynamic> json) async {}

  @override
  Future<bool> loadRequireXpForLevelUp() async => false;

  @override
  Future<void> saveRequireXpForLevelUp(bool requireXp) async {}
}
