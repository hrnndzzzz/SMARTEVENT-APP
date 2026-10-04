import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import 'signin_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const List<String> _taglines = [
    'Student orgs, organized.',
    'Track budgets in real time.',
    'Manage inventory with ease.',
    'Approve events on the go.',
    'Scan receipts instantly.',
    'Spot overspending early.',
    'Search records in seconds.',
    'Built for LCUP student leaders.',
  ];

  int _taglineIndex = 0;
  Timer? _taglineTimer;

  @override
  void initState() {
    super.initState();
    _taglineTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() => _taglineIndex = (_taglineIndex + 1) % _taglines.length);
      }
    });
  }

  @override
  void dispose() {
    _taglineTimer?.cancel();
    super.dispose();
  }


  void _goToSignIn() {
    Navigator.of(context).push(_fadeUpRoute(const SignInScreen()));
  }

  Route<T> _fadeUpRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BrutSurface(
                        fill: AppColors.brand,
                        radius: AppRadius.cardAll,
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        child: Icon(Icons.groups_outlined,
                            color: context.palette.ink, size: 34),
                      ),
                      const SizedBox(height: 22),
                      const MonoLabel('LCUP · Student organisations'),
                      const SizedBox(height: 8),
                      const Text(
                        'Welcome to\nSmartEvent',
                        textAlign: TextAlign.center,
                        style: AppText.display,
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 20,
                        child: AnimatedSwitcher(
                          duration: const Duration(seconds: 1),
                          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                          child: Text(
                            _taglines[_taglineIndex],
                            key: ValueKey(_taglineIndex),
                            style: AppText.body.copyWith(color: context.palette.subtle),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              BrutButton(
                label: 'Sign in',
                trailingIcon: Icons.arrow_forward,
                size: BrutSize.large,
                onPressed: _goToSignIn,
              ),
            ],
          ),
        ),
      ),
    );
  }
}