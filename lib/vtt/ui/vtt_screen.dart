import 'package:dnd_campaign_manager/logic/firebase_campaign_service.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/vtt/ui/vtt_board.dart';
import 'package:dnd_campaign_manager/vtt/ui/vtt_map_tools.dart';
import 'package:dnd_campaign_manager/vtt/ui/vtt_panels.dart';
import 'package:dnd_campaign_manager/vtt/ui/vtt_windowing.dart';
import 'package:dnd_campaign_manager/vtt/vtt_controller.dart';
import 'package:dnd_campaign_manager/vtt/vtt_firestore_repository.dart';
import 'package:dnd_campaign_manager/vtt/vtt_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class VttScreen extends StatefulWidget {
  const VttScreen({
    super.key,
    this.characters = const [],
    this.controller,
    this.allowPopoutAction = true,
  });

  final List<Character> characters;
  final VttController? controller;
  final bool allowPopoutAction;

  @override
  State<VttScreen> createState() => _VttScreenState();
}

class _VttScreenState extends State<VttScreen> {
  VttController? _controller;
  final VttBoardUiState _uiState = VttBoardUiState();
  bool _ownsController = false;
  bool _inlineFullscreen = false;
  bool _panelCollapsed = false;
  String? _lastShownError;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    if (_controller != null) {
      _controller!.start();
      return;
    }

    final shared = context.read<FirebaseCampaignService?>();
    if (shared == null || shared.isConnected != true) return;

    final VttRepository? repository =
        VttFirestoreRepository.fromService(shared);
    if (repository == null) return;
    _controller = VttController(repository)..start();
    _ownsController = true;
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller?.dispose();
    }
    _uiState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final canPopOut = widget.allowPopoutAction && supportsBoardPopout;
    final canNativeFullscreen = supportsNativeFullscreen;
    return Scaffold(
      appBar: _inlineFullscreen
          ? null
          : AppBar(
              title: const Text('Campaign board'),
              actions: [
                if (canPopOut && controller != null)
                  IconButton(
                    tooltip: 'Open board in new window',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => _openPopoutWindow(controller),
                  ),
                IconButton(
                  tooltip: canNativeFullscreen
                      ? 'Toggle fullscreen'
                      : (_inlineFullscreen ? 'Exit fullscreen' : 'Fullscreen'),
                  icon: Icon(
                    _inlineFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                  ),
                  onPressed: () => _toggleFullscreen(),
                ),
              ],
            ),
      body: controller == null
          ? const _UnavailableBoardMessage()
          : ChangeNotifierProvider<VttController>.value(
              value: controller,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final error = controller.error;
                  if (error != null &&
                      error.isNotEmpty &&
                      error != _lastShownError) {
                    _lastShownError = error;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error)),
                      );
                    });
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (_inlineFullscreen) {
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    VttTurnBar(characters: widget.characters),
                                    const SizedBox(height: 8),
                                    VttMeasureToolbar(state: _uiState),
                                    const SizedBox(height: 8),
                                    VttMapEditToolbar(state: _uiState),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: VttBoard(uiState: _uiState),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Card(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (canPopOut)
                                      IconButton(
                                        tooltip: 'Open board in new window',
                                        icon: const Icon(Icons.open_in_new),
                                        onPressed: () =>
                                            _openPopoutWindow(controller),
                                      ),
                                    IconButton(
                                      tooltip: 'Exit fullscreen',
                                      icon: const Icon(Icons.fullscreen_exit),
                                      onPressed: () => _toggleFullscreen(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      final wide = constraints.maxWidth >= 1000;
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    VttTurnBar(characters: widget.characters),
                                    const SizedBox(height: 8),
                                    VttMeasureToolbar(state: _uiState),
                                    const SizedBox(height: 8),
                                    VttMapEditToolbar(state: _uiState),
                                    const SizedBox(height: 8),
                                    Expanded(
                                        child: VttBoard(uiState: _uiState)),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 380,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(0, 12, 12, 12),
                                child: VttWidePanels(
                                  characters: widget.characters,
                                  uiState: _uiState,
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      final panelHeight = _panelCollapsed
                          ? 0.0
                          : (constraints.maxHeight * 0.38).clamp(160.0, 300.0);
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                VttTurnBar(characters: widget.characters),
                                const SizedBox(height: 8),
                                VttMeasureToolbar(state: _uiState),
                                const SizedBox(height: 8),
                                VttMapEditToolbar(state: _uiState),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                              child: VttBoard(uiState: _uiState),
                            ),
                          ),
                          InkWell(
                            key: const ValueKey('vtt-panel-toggle'),
                            onTap: () => setState(
                                () => _panelCollapsed = !_panelCollapsed),
                            child: SizedBox(
                              height: 32,
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _panelCollapsed
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                    ),
                                    Text(_panelCollapsed
                                        ? 'Show turn order & tokens'
                                        : 'Hide panel'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (!_panelCollapsed)
                            SizedBox(
                              height: panelHeight,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                child: VttCompactPanels(
                                  characters: widget.characters,
                                  uiState: _uiState,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
    );
  }

  Future<void> _openPopoutWindow(VttController controller) async {
    final opened = await openBoardPopoutWindow(
      context: context,
      childBuilder: () => VttScreen(
        controller: controller,
        characters: widget.characters,
        allowPopoutAction: false,
      ),
      controller: controller,
      characters: widget.characters,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Board pop-out is not available here.')),
      );
    }
  }

  Future<void> _toggleFullscreen() async {
    final usedNative = await toggleBoardFullscreen(context);
    if (!mounted || usedNative) return;
    setState(() => _inlineFullscreen = !_inlineFullscreen);
  }
}

class _UnavailableBoardMessage extends StatelessWidget {
  const _UnavailableBoardMessage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Join or create a shared campaign in Campaign Settings to use the board.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
