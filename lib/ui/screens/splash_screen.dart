import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/paper_card.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'room_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final s = Services.of(context);
    setState(() => _error = null);
    try {
      await Future.wait([
        s.repo.signIn(),
        Future<void>.delayed(const Duration(milliseconds: 1200)),
      ]);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not connect. Chittilata needs the internet to play with friends.');
      }
      return;
    }
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (!s.prefs.onboarded) {
      nav.pushReplacement(gameRoute(const OnboardingScreen(firstRun: true)));
      return;
    }
    nav.pushReplacement(gameRoute(const HomeScreen()));
    final resume = s.prefs.activeRoomId;
    if (resume != null) nav.push(gameRoute(RoomScreen(roomId: resume)));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: GameBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _anim,
                  builder: (_, _) {
                    final t = Curves.easeOutBack.transform(_anim.value);
                    return SizedBox(
                      height: 170,
                      width: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          for (var i = -1; i <= 1; i++)
                            Transform.translate(
                              offset: Offset(i * 46.0 * t, (i.abs() * 8.0) * t),
                              child: Transform.rotate(
                                angle: i * 0.22 * t,
                                child: PaperSlip(
                                  label: '',
                                  width: 86,
                                  state: i == 0
                                      ? SlipState.normal
                                      : SlipState.faceDown,
                                ),
                              ),
                            ),
                          Opacity(
                            opacity: _anim.value,
                            child: Text('చి',
                                style: TextStyle(
                                    color: c.kumkum,
                                    fontSize: 46,
                                    fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: Space.xl),
                Text('Chittilata',
                    style: context.text.displaySmall?.copyWith(color: c.marigold)),
                Text('చిట్టిలాట',
                    style: context.text.headlineSmall?.copyWith(color: c.onSurface)),
                const SizedBox(height: Space.sm),
                Text('The paper-slip game, now on every phone',
                    style: TextStyle(color: c.muted)),
                const SizedBox(height: Space.xxl),
                if (_error == null)
                  SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(color: c.marigold))
                else ...[
                  Icon(Icons.wifi_off_rounded, color: c.kumkum, size: 36),
                  const SizedBox(height: Space.sm),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.onSurface)),
                  const SizedBox(height: Space.lg),
                  BigButton(
                      label: 'Try again',
                      icon: Icons.refresh_rounded,
                      onPressed: _boot),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
