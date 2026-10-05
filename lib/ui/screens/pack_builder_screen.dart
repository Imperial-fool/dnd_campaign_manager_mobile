import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/models/builtin_components.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';
import 'package:dnd_campaign_manager/models/sheet_template.dart';
import 'package:dnd_campaign_manager/ui/widgets/dialogs.dart';
import 'package:dnd_campaign_manager/ui/widgets/formula_field.dart';
import 'package:dnd_campaign_manager/ui/widgets/item_form.dart';

const _pretty = JsonEncoder.withIndent('  ');

/// Starter JSON shown when adding a new item of each content type.
const Map<String, Map<String, dynamic>> _starters = {
  'weapons': {
    'name': 'New Rifle',
    'damage': '{1d6}d8+{dex_mod}',
    'ammoType': '5.56',
    'ammoMax': 30,
    'attackAbility': 'dex',
    'properties': 'Damage is a template: a d6 decides how many d8 are rolled.',
  },
  'armor': {'name': 'New Armor', 'rating': 0, 'effects': []},
  'items': {'name': 'New Item', 'description': ''},
  'traits': {'name': 'New Trait', 'description': '', 'effects': []},
  'features': {'name': 'New Feature', 'description': '', 'effects': []},
  'feats': {'name': 'New Feat', 'description': '', 'effects': []},
};

/// DM tool: assemble a content pack (items + components) and add it to
/// the campaign catalog or export it as JSON.
class PackBuilderScreen extends StatefulWidget {
  const PackBuilderScreen({super.key});

  @override
  State<PackBuilderScreen> createState() => _PackBuilderScreenState();
}

class _PackBuilderScreenState extends State<PackBuilderScreen> {
  final _name = TextEditingController(text: 'My Homebrew Pack');
  final _author = TextEditingController();
  final Map<String, List<Map<String, dynamic>>> _sections = {};

  @override
  void dispose() {
    _name.dispose();
    _author.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _pack => {
        'schemaVersion': 1,
        'pack': _name.text.trim(),
        if (_author.text.trim().isNotEmpty) 'author': _author.text.trim(),
        for (final e in _sections.entries)
          if (e.value.isNotEmpty) e.key: e.value,
      };

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  List<Map<String, dynamic>> _list(String key) =>
      _sections.putIfAbsent(key, () => []);

  Future<void> _edit(String key, {int? index}) async {
    final campaign = context.read<CampaignController>();
    final existing = index == null ? null : _list(key)[index];
    Map<String, dynamic>? result;
    if (key == 'sheetTemplates') {
      result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => SheetTemplateEditorScreen(initial: existing),
        ),
      );
    } else if (itemSchemas[key] != null) {
      result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => ItemFormScreen(
            schema: itemSchemas[key]!,
            initial: existing,
            validate: (data) => campaign.registry[key]!.parse(data),
          ),
        ),
      );
    } else {
      final text = await showJsonInputDialog(
        context,
        title: existing == null ? 'New item' : 'Edit item',
        sample: _pretty.convert(existing ?? _starters[key] ?? {'name': ''}),
      );
      if (text == null || text.trim().isEmpty) return;
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map) throw const FormatException('Expected an object.');
        final item = Map<String, dynamic>.from(decoded);
        campaign.registry[key]!.parse(item); // validates
        result = item;
      } catch (error) {
        if (mounted) _snack('Invalid item: $error');
        return;
      }
    }
    if (result == null) return;
    setState(() {
      final list = _list(key);
      if (index == null) {
        list.add(result!);
      } else {
        list[index] = result!;
      }
    });
  }

  void _loadFromCatalog() {
    final campaign = context.read<CampaignController>();
    setState(() {
      for (final b in campaign.registry.bindings) {
        final items = campaign.catalog.items(b.key);
        if (items.isEmpty) continue;
        _sections[b.key] = [for (final i in items) i.toJson()];
      }
    });
  }

  Future<void> _addBuiltins() async {
    final chosen = <BuiltinComponent>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Copy standard sheet sections'),
          content: SizedBox(
            width: 400,
            child: ListView(shrinkWrap: true, children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Adds editable copies to your pack. Weapons, '
                    'armor, inventory, actions and traits stay built in.'),
              ),
              for (final b in builtinComponents)
                CheckboxListTile(
                  title: Text(b.name),
                  subtitle: Text(b.description),
                  value: chosen.contains(b),
                  onChanged: (v) => setLocal(
                      () => v == true ? chosen.add(b) : chosen.remove(b)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || chosen.isEmpty) return;
    setState(() {
      final list = _list('sheetTemplates');
      for (final b in chosen) {
        final json = b.build().toJson();
        list.removeWhere((e) => e['id'] == json['id']);
        list.add(json);
      }
    });
    _snack('Added ${chosen.length} component(s) - open the Sheet components '
        'tab to edit them.');
  }

  Future<void> _loadJson() async {
    final text = await showJsonInputDialog(context,
        title: 'Load pack JSON', sample: _pretty.convert(_pack));
    if (text == null || text.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('Expected an object.');
      setState(() {
        _name.text = asStr(decoded['pack'], _name.text);
        _author.text = asStr(decoded['author']);
        _sections.clear();
        for (final e in decoded.entries) {
          if (e.value is List) _sections['${e.key}'] = asMapList(e.value);
        }
      });
    } catch (error) {
      if (mounted) _snack('Could not load pack: $error');
    }
  }

  Future<void> _addToCampaign() async {
    final campaign = context.read<CampaignController>();
    try {
      final result = await campaign.importContent(_pretty.convert(_pack));
      if (mounted) showImportResult(context, result);
    } catch (error) {
      if (mounted) _snack('Could not add pack: $error');
    }
  }

  Future<void> _saveFile() async {
    try {
      final path = await FilePicker.saveFile(
        fileName:
            '${slug(_name.text).isEmpty ? 'pack' : slug(_name.text)}.json',
        dialogTitle: 'Save content pack',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        mimeType: 'application/json',
        bytes: Uint8List.fromList(utf8.encode(_pretty.convert(_pack))),
      );
      if (path != null && mounted) _snack('Saved pack to $path');
    } on Exception catch (error) {
      if (mounted) _snack('Could not save pack: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bindings = context.watch<CampaignController>().registry.bindings;
    return DefaultTabController(
      length: bindings.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Content pack builder'),
          actions: [
            IconButton(
              tooltip: 'Start from current catalog',
              icon: const Icon(Icons.library_books_outlined),
              onPressed: _loadFromCatalog,
            ),
            IconButton(
              tooltip: 'Copy standard sheet sections as components',
              icon: const Icon(Icons.dashboard_customize_outlined),
              onPressed: _addBuiltins,
            ),
            IconButton(
              tooltip: 'Load pack JSON',
              icon: const Icon(Icons.content_paste),
              onPressed: _loadJson,
            ),
            IconButton(
              tooltip: 'View / copy JSON',
              icon: const Icon(Icons.data_object),
              onPressed: () => showJsonViewDialog(context,
                  title: '${_name.text}.json', json: _pretty.convert(_pack)),
            ),
            IconButton(
              tooltip: 'Save pack file',
              icon: const Icon(Icons.save_alt),
              onPressed: _saveFile,
            ),
            IconButton(
              tooltip: 'Add pack to this campaign',
              icon: const Icon(Icons.playlist_add_check),
              onPressed: _addToCampaign,
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final b in bindings) Tab(text: b.label)],
          ),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Pack name'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _author,
                  decoration: const InputDecoration(labelText: 'Author'),
                ),
              ),
            ]),
          ),
          Expanded(
            child: TabBarView(children: [
              for (final b in bindings) _sectionView(b.key, b.label),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _sectionView(String key, String label) {
    final items = _list(key);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (var i = 0; i < items.length; i++)
          Card(
            child: ListTile(
              title: Text(asStr(items[i]['name'], 'Unnamed')),
              subtitle: key == 'sheetTemplates'
                  ? Text('${asMapList(items[i]['fields']).length} field(s)')
                  : null,
              onTap: () => _edit(key, index: i),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => items.removeAt(i)),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.add),
            label: Text(itemSchemas[key] == null
                ? 'Add to $label'
                : 'New ${itemSchemas[key]!.singular}'),
            onPressed: () => _edit(key),
          ),
        ),
      ],
    );
  }
}

/// Visual designer for a character sheet: sections of fields (inputs,
/// formula-driven calculations, and dice-roll buttons).
class SheetTemplateEditorScreen extends StatefulWidget {
  const SheetTemplateEditorScreen({super.key, this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<SheetTemplateEditorScreen> createState() =>
      _SheetTemplateEditorScreenState();
}

class _SheetTemplateEditorScreenState extends State<SheetTemplateEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final List<SheetField> _fields;
  String? _id;

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initial == null ? null : SheetTemplate.fromJson(widget.initial!);
    _id = initial?.id;
    _name = TextEditingController(text: initial?.name ?? 'New Component');
    _description = TextEditingController(text: initial?.description ?? '');
    _fields = List.of(initial?.fields ?? <SheetField>[]);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  SheetTemplate get _template => SheetTemplate(
        id: _id ?? '',
        name: _name.text.trim(),
        description: _description.text.trim(),
        fields: _fields,
      );

  /// Evaluates against a blank sample character so previews and validation
  /// need no real character.
  SheetEvaluator get _sample =>
      SheetEvaluator(Character(id: 'sample'), _template);

  void _save() {
    final template = _template;
    if (template.name.isEmpty) return _error('Give the component a name.');
    final keys = <String>{};
    for (final f in _fields) {
      if (!keys.add(f.key)) return _error('Duplicate field key "${f.key}".');
    }
    final problem = _sample.validate();
    if (problem != null) return _error(problem);
    Navigator.pop(context, template.toJson());
  }

  void _error(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  static String _typeLabel(SheetFieldType t) => switch (t) {
        SheetFieldType.calc => 'Calculated value',
        SheetFieldType.roll => 'Roll button',
        SheetFieldType.number => 'Number input',
        _ => t.name,
      };

  Future<void> _editField({int? index, String? sectionDefault}) async {
    final existing = index == null ? null : _fields[index];
    final label = TextEditingController(text: existing?.label ?? '');
    final key = TextEditingController(text: existing?.key ?? '');
    final section = TextEditingController(
        text: existing?.section ?? sectionDefault ?? 'General');
    final formula = TextEditingController(text: existing?.formula ?? '');
    final defaultValue =
        TextEditingController(text: existing?.defaultValue ?? '');
    var type = existing?.type ?? SheetFieldType.number;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add field' : 'Edit field'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                TextField(
                  controller: key,
                  decoration: const InputDecoration(
                    labelText: 'Key (used in formulas; blank = from label)',
                  ),
                ),
                TextField(
                  controller: section,
                  decoration: const InputDecoration(labelText: 'Section'),
                ),
                DropdownButtonFormField<SheetFieldType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final t in SheetFieldType.values)
                      DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
                  ],
                  onChanged: (t) => setLocal(() => type = t ?? type),
                ),
                if (type == SheetFieldType.calc || type == SheetFieldType.roll)
                  FormulaTextField(
                    label:
                        type == SheetFieldType.calc ? 'Formula' : 'Dice roll',
                    dice: type == SheetFieldType.roll,
                    initialValue: formula.text,
                    extraNames: [
                      for (final o in _fields)
                        if (o.key != existing?.key) o.key,
                    ],
                    onChanged: (v) => formula.text = v,
                  )
                else
                  TextField(
                    controller: defaultValue,
                    decoration: const InputDecoration(labelText: 'Default'),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    final result = saved == true
        ? {
            'label': label.text.trim(),
            'key': key.text.trim(),
            'section':
                section.text.trim().isEmpty ? 'General' : section.text.trim(),
            'type': type.name,
            'formula': formula.text.trim(),
            'default': defaultValue.text.trim(),
          }
        : null;
    label.dispose();
    key.dispose();
    section.dispose();
    formula.dispose();
    defaultValue.dispose();
    if (result == null) return;
    try {
      final field = SheetField.fromJson(result);
      setState(() {
        if (index == null) {
          _fields.add(field);
        } else {
          _fields[index] = field;
        }
      });
    } on FormatException catch (e) {
      _error(e.message);
    }
  }

  bool _showPreview = false;

  String _uniqueKey(String base) {
    final taken = _fields.map((f) => f.key).toSet();
    var k = base;
    for (var i = 2; taken.contains(k); i++) {
      k = '${base}_$i';
    }
    return k;
  }

  /// Ready-made blocks; each returns the fields to add for a chosen name.
  static final _blocks = <(
    String,
    IconData,
    String,
    List<SheetField> Function(String name, String key, String section)
  )>[
    (
      'Number',
      Icons.pin_outlined,
      'A value players type in',
      (n, k, s) => [
            SheetField(key: k, label: n, section: s),
          ]
    ),
    (
      'Text',
      Icons.notes,
      'Free text or notes',
      (n, k, s) => [
            SheetField(key: k, label: n, type: SheetFieldType.text, section: s),
          ]
    ),
    (
      'Checkbox',
      Icons.check_box_outlined,
      'On/off flag',
      (n, k, s) => [
            SheetField(
                key: k, label: n, type: SheetFieldType.toggle, section: s),
          ]
    ),
    (
      'Calculated',
      Icons.functions,
      'Value computed from a formula',
      (n, k, s) => [
            SheetField(
                key: k,
                label: n,
                type: SheetFieldType.calc,
                section: s,
                formula: '10 + dex_mod'),
          ]
    ),
    (
      'Roll button',
      Icons.casino_outlined,
      'Rolls dice when tapped',
      (n, k, s) => [
            SheetField(
                key: k,
                label: n,
                type: SheetFieldType.roll,
                section: s,
                formula: '1d20+{dex_mod}+{prof}'),
          ]
    ),
    (
      'Resource tracker',
      Icons.battery_5_bar,
      'Current / max / remaining',
      (n, k, s) => [
            SheetField(key: '${k}_current', label: '$n (current)', section: s),
            SheetField(key: '${k}_max', label: '$n (max)', section: s),
            SheetField(
                key: '${k}_left',
                label: '$n remaining',
                type: SheetFieldType.calc,
                section: s,
                formula: 'max(0, ${k}_max - ${k}_current)'),
          ]
    ),
    (
      'Gun attack (bullet die)',
      Icons.gps_fixed,
      'Attack + variable-dice damage',
      (n, k, s) => [
            SheetField(
                key: '${k}_attack',
                label: '$n attack',
                type: SheetFieldType.roll,
                section: s,
                formula: '1d20+{dex_mod}+{prof}'),
            SheetField(
                key: '${k}_damage',
                label: '$n damage',
                type: SheetFieldType.roll,
                section: s,
                formula: '{1d6}d8+{dex_mod}'),
          ]
    ),
    (
      'Skill / save',
      Icons.fitness_center,
      'Bonus plus a check roll',
      (n, k, s) => [
            SheetField(
                key: '${k}_bonus',
                label: '$n bonus',
                type: SheetFieldType.calc,
                section: s,
                formula: 'dex_mod + prof'),
            SheetField(
                key: '${k}_check',
                label: '$n check',
                type: SheetFieldType.roll,
                section: s,
                formula: '1d20+{${k}_bonus}'),
          ]
    ),
  ];

  Future<void> _addBlock(int blockIndex) async {
    final block = _blocks[blockIndex];
    final name = TextEditingController(text: block.$1);
    final section = TextEditingController(
        text: _fields.isEmpty ? 'General' : _fields.last.section);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add ${block.$1}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: section,
            decoration: const InputDecoration(
              labelText: 'Section',
              helperText: 'Type an existing section name or a new one.',
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    final n = name.text.trim().isEmpty ? block.$1 : name.text.trim();
    final s = section.text.trim().isEmpty ? 'General' : section.text.trim();
    name.dispose();
    section.dispose();
    if (ok != true) return;
    final base = slug(n).replaceAll('-', '_');
    final key =
        _uniqueKey(RegExp(r'^[A-Za-z_]').hasMatch(base) ? base : 'f_$base');
    setState(() => _fields.addAll(block.$4(n, key, s)));
  }

  Future<void> _renameSection(String section) async {
    final c = TextEditingController(text: section);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename section'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    c.dispose();
    if (value == null || value.isEmpty) return;
    setState(() {
      for (final f in _fields) {
        if (f.section == section) f.section = value;
      }
    });
  }

  void _move(int i, int dir) {
    final section = _fields[i].section;
    var j = i + dir;
    while (j >= 0 && j < _fields.length && _fields[j].section != section) {
      j += dir;
    }
    if (j < 0 || j >= _fields.length) return;
    setState(() {
      final tmp = _fields[i];
      _fields[i] = _fields[j];
      _fields[j] = tmp;
    });
  }

  String _subtitle(SheetField f) {
    switch (f.type) {
      case SheetFieldType.calc:
        return '${f.key} = ${f.formula}  ?  ${_sample.calcText(f)} (sample)';
      case SheetFieldType.roll:
        return '${f.key}: ${f.formula}';
      default:
        return '${f.key} ? ${_typeLabel(f.type)}';
    }
  }

  Widget _designPane() {
    final template = _template;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        TextField(
          controller: _name,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Component name'),
        ),
        TextField(
          controller: _description,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 12),
        Text('Add a block', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (var b = 0; b < _blocks.length; b++)
            Tooltip(
              message: _blocks[b].$3,
              child: ActionChip(
                avatar: Icon(_blocks[b].$2, size: 18),
                label: Text(_blocks[b].$1),
                onPressed: () => _addBlock(b),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        if (_fields.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'This component is empty. Tap a block above to add it, then tap any '
              'field to customise it. The preview shows how it will look as a card on the character sheet. '
              'the sheet.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final section in template.sections) ...[
          Row(children: [
            Expanded(
              child:
                  Text(section, style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              tooltip: 'Rename section',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _renameSection(section),
            ),
            IconButton(
              tooltip: 'Add field to this section',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _editField(sectionDefault: section),
            ),
          ]),
          for (var i = 0; i < _fields.length; i++)
            if (_fields[i].section == section)
              Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(_iconFor(_fields[i].type)),
                  title: Text(_fields[i].label),
                  subtitle: Text(_subtitle(_fields[i])),
                  onTap: () => _editField(index: i),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Move up',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: () => _move(i, -1),
                    ),
                    IconButton(
                      tooltip: 'Move down',
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: () => _move(i, 1),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _fields.removeAt(i)),
                    ),
                  ]),
                ),
              ),
        ],
      ],
    );
  }

  static IconData _iconFor(SheetFieldType t) => switch (t) {
        SheetFieldType.number => Icons.pin_outlined,
        SheetFieldType.text => Icons.notes,
        SheetFieldType.toggle => Icons.check_box_outlined,
        SheetFieldType.calc => Icons.functions,
        SheetFieldType.roll => Icons.casino_outlined,
      };

  /// Mirrors CustomSheetPanel, but tapping a field edits it.
  Widget _previewPane() {
    final template = _template;
    final eval = _sample;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    template.name.isEmpty
                        ? 'Untitled component'
                        : template.name,
                    style: Theme.of(context).textTheme.titleLarge),
                Text(
                    'Live preview with a blank sample character. Tap a field '
                    'to edit it.',
                    style: Theme.of(context).textTheme.bodySmall),
                for (final section in template.sections) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(section,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (var i = 0; i < _fields.length; i++)
                    if (_fields[i].section == section) _previewField(i, eval),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewField(int i, SheetEvaluator eval) {
    final f = _fields[i];
    final Widget body;
    switch (f.type) {
      case SheetFieldType.calc:
        body = Row(children: [
          Expanded(child: Text(f.label)),
          Text(eval.calcText(f),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ]);
      case SheetFieldType.roll:
        body = Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.casino_outlined),
            label: Text(f.label),
            onPressed: () => _editField(index: i),
          ),
        );
      case SheetFieldType.toggle:
        body = Row(children: [
          const Icon(Icons.check_box_outline_blank),
          const SizedBox(width: 8),
          Text(f.label),
        ]);
      case SheetFieldType.number:
      case SheetFieldType.text:
        body = InputDecorator(
          decoration: InputDecoration(labelText: f.label, isDense: true),
          child: Text(f.defaultValue),
        );
    }
    return InkWell(
      onTap: () => _editField(index: i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Component designer'),
        actions: [
          if (!wide)
            IconButton(
              tooltip: _showPreview ? 'Back to editing' : 'Preview sheet',
              icon: Icon(_showPreview ? Icons.edit : Icons.visibility),
              onPressed: () => setState(() => _showPreview = !_showPreview),
            ),
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Done'),
          ),
        ],
      ),
      body: wide
          ? Row(children: [
              Expanded(child: _designPane()),
              const VerticalDivider(width: 1),
              Expanded(child: _previewPane()),
            ])
          : (_showPreview ? _previewPane() : _designPane()),
    );
  }
}
