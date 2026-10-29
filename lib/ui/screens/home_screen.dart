import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../core/services/feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../data/game_repository.dart';
import '../widgets/common.dart';
import '../widgets/paper_card.dart';
import 'history_screen.dart';
import 'onboarding_screen.dart';
import 'room_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  bool _loadedName = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedName) return;
    _loadedName = true;
    _name.text = Services.of(context).prefs.playerName;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _validName() {
    final n = _name.text.trim();
    if (n.isEmpty) {
      showGameSnack(context, 'Enter your name first');
      return null;
    }
    if (n.length > 16) {
      showGameSnack(context, 'Names can be at most 16 characters');
      return null;
    }
    Services.of(context).prefs.playerName = n;
    return n;
  }

  Future<void> _create() async {
    final name = _validName();
    if (name == null) return;
    final s = Services.of(context);
    s.feedback.play(Sfx.tap);
    setState(() => _busy = true);
    try {
      final r = await s.repo.createRoom(name);
      _open(r.roomId);
    } on GameException catch (e) {
      if (mounted) showGameSnack(context, e.message);
    } catch (_) {
      if (mounted) showGameSnack(context, 'Could not reach the game server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final name = _validName();
    if (name == null) return;
    Services.of(context).feedback.play(Sfx.tap);
    final roomId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => JoinSheet(name: name),
    );
    if (roomId != null) _open(roomId);
  }

  void _open(String roomId) {
    if (!mounted) return;
    Services.of(context).prefs.activeRoomId = roomId;
    Navigator.of(context).push(gameRoute(RoomScreen(roomId: roomId)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: GameBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.all(Space.xl),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Match history',
                          icon: const Icon(Icons.history_rounded),
                          onPressed: () => Navigator.push(
                              context, gameRoute(const HistoryScreen())),
                        ),
                        IconButton(
                          tooltip: 'Settings',
                          icon: const Icon(Icons.tune_rounded),
                          onPressed: () => Navigator.push(
                              context, gameRoute(const SettingsScreen())),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.lg),
                    const _Hero(),
                    const SizedBox(height: Space.xl),
                    Text('Chittilata',
                        textAlign: TextAlign.center,
                        style: context.text.displaySmall
                            ?.copyWith(color: c.marigold)),
                    Text('చిట్టిలాట · collect four of a kind',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: Space.xxl),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 16,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        prefixIcon: Icon(Icons.person_rounded),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    BigButton(
                      label: 'Create a room',
                      icon: Icons.add_circle_rounded,
                      busy: _busy,
                      onPressed: _create,
                    ),
                    const SizedBox(height: Space.md),
                    BigButton(
                      label: 'Join with a code',
                      icon: Icons.login_rounded,
                      secondary: true,
                      onPressed: _busy ? null : _join,
                    ),
                    const SizedBox(height: Space.lg),
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                          context, gameRoute(const OnboardingScreen())),
                      icon: Icon(Icons.menu_book_rounded, color: c.teal),
                      label: Text('How to play',
                          style: TextStyle(color: c.teal, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    const names = ['RRR', 'RRR', 'RRR', 'RRR'];
    return SizedBox(
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < 4; i++)
            Transform.translate(
              offset: Offset((i - 1.5) * 52, (i - 1.5).abs() * 6),
              child: Transform.rotate(
                angle: (i - 1.5) * 0.14,
                child: PaperSlip(
                  label: names[i],
                  width: 78,
                  state: SlipState.winning,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class JoinSheet extends StatefulWidget {
  const JoinSheet({super.key, required this.name});
  final String name;

  @override
  State<JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<JoinSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Room codes have 6 letters and numbers');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await Services.of(context).repo.joinRoom(code, widget.name);
      if (mounted) Navigator.pop(context, r.roomId);
    } on GameException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the game server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          Space.xl, 0, Space.xl, MediaQuery.of(context).viewInsets.bottom + Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Join a room', style: context.text.titleLarge),
          const SizedBox(height: Space.sm),
          Text('Ask the host for the 6-character room code.',
              style: TextStyle(color: c.muted)),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _code,
            autofocus: true,
            maxLength: 6,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
              TextInputFormatter.withFunction(
                  (_, v) => v.copyWith(text: v.text.toUpperCase())),
            ],
            onSubmitted: (_) => _submit(),
            style: context.text.headlineMedium?.copyWith(letterSpacing: 10),
            decoration: InputDecoration(
              hintText: 'ABC234',
              counterText: '',
              errorText: _error,
            ),
          ),
          const SizedBox(height: Space.lg),
          BigButton(
              label: 'Join', icon: Icons.login_rounded, busy: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}
