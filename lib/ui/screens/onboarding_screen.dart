import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../rules_content.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// First-run walkthrough; also opened later as "How to play".
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    this.firstRun = false,
    this.mode = GameMode.movie,
  });
  final bool firstRun;
  final GameMode mode;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  List<RuleSection> get _sections =>
      widget.mode == GameMode.kingQueen ? kqRuleSections : ruleSections;
  final _page = PageController();
  int _index = 0;

  void _finish() {
    final s = Services.of(context);
    s.prefs.onboarded = true;
    if (widget.firstRun) {
      Navigator.of(context).pushReplacement(gameRoute(const HomeScreen()));
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = _index == _sections.length - 1;
    return Scaffold(
      body: GameBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                child: Row(
                  children: [
                    if (!widget.firstRun)
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: _finish,
                      child: Text(
                        widget.firstRun ? 'Skip' : 'Done',
                        style: TextStyle(color: c.muted),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                widget.mode == GameMode.kingQueen
                    ? 'How to play King & Queen'
                    : 'How to play Movie Chits',
                style: context.text.titleLarge?.copyWith(color: c.marigold),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _sections.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) {
                    final r = _sections[i];
                    return Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: c.surfaceHigh,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.marigold, width: 3),
                            ),
                            child: Icon(r.icon, size: 56, color: c.marigold),
                          ),
                          const SizedBox(height: Space.xl),
                          Text(
                            '${i + 1}. ${r.title}',
                            textAlign: TextAlign.center,
                            style: context.text.headlineSmall,
                          ),
                          const SizedBox(height: Space.lg),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Text(
                                r.body,
                                textAlign: TextAlign.center,
                                style: context.text.bodyLarge?.copyWith(
                                  color: c.muted,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _sections.length; i++)
                    AnimatedContainer(
                      duration: Motion.fast,
                      margin: const EdgeInsets.all(3),
                      width: i == _index ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index ? c.marigold : c.outline,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: SizedBox(
                  width: double.infinity,
                  child: BigButton(
                    label: last ? "Let's play" : 'Next',
                    icon: last
                        ? Icons.play_arrow_rounded
                        : Icons.arrow_forward_rounded,
                    onPressed: last
                        ? _finish
                        : () => _page.nextPage(
                            duration: Motion.of(context, Motion.medium),
                            curve: Motion.curve,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
