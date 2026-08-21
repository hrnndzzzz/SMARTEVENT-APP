import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'signup_screen.dart';
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
    'Built for CITE student leaders.',
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

  void _goToSignUp() {
    Navigator.of(context).push(_fadeUpRoute(const SignUpScreen()));
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
              const Spacer(flex: 3),
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppColors.indigo,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.groups_outlined, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to\nSmartEvent',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 30,
                  height: 1.25,
                  color: AppColors.ink,
                ),
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
                    style: const TextStyle(
                      fontFamily: AppText.bodyFamily,
                      fontSize: 14,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 4),
              ElevatedButton(
                onPressed: _goToSignUp,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: const Text('Sign Up'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _goToSignIn,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: const Text('Sign In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}