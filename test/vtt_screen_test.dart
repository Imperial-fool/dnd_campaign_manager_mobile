import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/vtt/ui/vtt_screen.dart';
import 'package:dnd_campaign_manager/vtt/ui/vtt_windowing.dart';
import 'package:dnd_campaign_manager/vtt/vtt_controller.dart';
import 'package:dnd_campaign_manager/vtt/vtt_memory_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpBoard(
  WidgetTester tester,
  VttController controller, {
  List<Character> characters = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: VttScreen(
        controller: controller,
        characters: characters,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('DM view shows tools and initiative panel', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = MemoryVttStore();
    final dmController = VttController(
      MemoryVttRepository(
        isOwner: true,
        userId: 'dm',
        store: store,
      ),
    )..start();
    await tester.pump();

    final map = await dmController.createMap(
      name: 'Overworld',
      cols: 8,
      rows: 8,
      isOverworld: true,
    );
    await tester.pump();
    final hero = await dmController.addToken(
      mapId: map.id,
      name: 'Hero',
      kind: 'pc',
      ownerUid: 'player-1',
      characterId: 'hero-sheet',
    );
    final goblin = await dmController.addToken(
      mapId: map.id,
      name: 'Goblin',
      col: 1,
      row: 1,
    );
    await dmController.setInitiative(hero.id, 15);
    await dmController.setInitiative(goblin.id, 9);
    await tester.pump();
    await tester.pump();

    final heroSheet = Character(id: 'hero-sheet')
      ..name = 'Hero'
      ..initiativeBonus = 3;

    await _pumpBoard(
      tester,
      dmController,
      characters: [heroSheet],
    );

    expect(find.text('Initiative'), findsWidgets);
    expect(find.text('DM tools'), findsOneWidget);
    expect(find.text('Edit map'), findsOneWidget);
    expect(find.text('Import map file'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Start combat'), findsOneWidget);
    expect(find.byTooltip('Toggle fullscreen'), findsOneWidget);
    if (supportsBoardPopout) {
      expect(find.byTooltip('Open board in new window'), findsOneWidget);
    }
    expect(find.text('Hero'), findsWidgets);
    expect(find.text('Goblin'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    dmController.dispose();
    store.dispose();
  });

  testWidgets('player view hides tools and shows turn order', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = MemoryVttStore();
    final dmController = VttController(
      MemoryVttRepository(
        isOwner: true,
        userId: 'dm',
        store: store,
      ),
    )..start();
    await tester.pump();

    final playerController = VttController(
      MemoryVttRepository(
        isOwner: false,
        userId: 'player-1',
        store: store,
      ),
    );

    final map = await dmController.createMap(name: 'Arena', cols: 6, rows: 6);
    await tester.pump();
    final hero = await dmController.addToken(
      mapId: map.id,
      name: 'Hero',
      ownerUid: 'player-1',
      kind: 'pc',
      characterId: 'hero-sheet',
    );
    final goblin = await dmController.addToken(
      mapId: map.id,
      name: 'Goblin',
      col: 2,
      row: 2,
    );
    await dmController.setInitiative(hero.id, 14);
    await dmController.setInitiative(goblin.id, 11);
    await dmController.startCombat();
    await tester.pump();
    await tester.pump();

    final heroSheet = Character(id: 'hero-sheet')
      ..name = 'Hero'
      ..initiativeBonus = 2;

    await _pumpBoard(
      tester,
      playerController,
      characters: [heroSheet],
    );

    expect(find.text('DM tools'), findsNothing);
    expect(find.text('Start combat'), findsNothing);
    expect(find.text('Edit map'), findsNothing);
    expect(find.text('Import map file'), findsNothing);
    expect(find.text('Ruler'), findsOneWidget);
    expect(find.text('Line'), findsOneWidget);
    expect(find.text('Initiative'), findsWidgets);
    expect(find.text('Round 1'), findsOneWidget);
    expect(find.byTooltip('Toggle fullscreen'), findsOneWidget);
    expect(find.text('Hero'), findsWidgets);
    expect(find.text('Goblin'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    playerController.dispose();
    dmController.dispose();
    store.dispose();
  });

  testWidgets('ruler overlay shows measured feet and cells', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = MemoryVttStore();
    final dmController = VttController(
      MemoryVttRepository(
        isOwner: true,
        userId: 'dm',
        store: store,
      ),
    )..start();
    await tester.pump();

    final playerController = VttController(
      MemoryVttRepository(
        isOwner: false,
        userId: 'player-1',
        store: store,
      ),
    );

    final map = await dmController.createMap(name: 'Arena', cols: 6, rows: 6);
    await dmController.addToken(
      mapId: map.id,
      name: 'Hero',
      ownerUid: 'player-1',
      kind: 'pc',
    );
    await tester.pump();

    await _pumpBoard(tester, playerController);
    await tester.tap(find.text('Ruler'));
    await tester.pump();

    final board = find.byKey(const ValueKey('vtt-board-surface'));
    final topLeft = tester.getTopLeft(board);
    final gesture = await tester.startGesture(topLeft + const Offset(24, 24));
    await gesture.moveTo(topLeft + const Offset(168, 24));
    await gesture.up();
    await tester.pump();

    expect(find.byKey(const ValueKey('vtt-measure-label')), findsOneWidget);
    expect(find.text('15 ft · 3 cells'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    playerController.dispose();
    dmController.dispose();
    store.dispose();
  });

  testWidgets('wall drag adds expected edges', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = MemoryVttStore();
    final dmController = VttController(
      MemoryVttRepository(
        isOwner: true,
        userId: 'dm',
        store: store,
      ),
    )..start();
    await tester.pump();

    await dmController.createMap(name: 'Draft', cols: 8, rows: 8);
    await tester.pump();

    await _pumpBoard(tester, dmController);
    await tester.tap(find.text('Edit map'));
    await tester.pump();
    await tester.tap(find.text('Wall'));
    await tester.pump();

    final board = find.byKey(const ValueKey('vtt-board-surface'));
    final topLeft = tester.getTopLeft(board);
    final gesture = await tester.startGesture(topLeft + const Offset(48, 48));
    await gesture.moveTo(topLeft + const Offset(192, 48));
    await gesture.up();
    await tester.pump();

    final edges =
        dmController.currentMap!.edges.map((edge) => edge.key).toSet();
    expect(edges, containsAll(<String>['h:1:1', 'h:2:1', 'h:3:1']));

    await tester.pumpWidget(const SizedBox.shrink());
    dmController.dispose();
    store.dispose();
  });
}
