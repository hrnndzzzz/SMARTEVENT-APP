import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_config.dart';
import '../state/app_icon.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import '../state/user_role.dart';
import 'sap/sap_review_demo_screen.dart';
import '../state/sfx.dart';
import '../widgets/backend_address_card.dart';
import '../widgets/brand_mark.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';

/// Device settings.
///
/// Nothing here is stored on the account — there is no settings endpoint
/// — so the screen says so rather than implying a preference follows you
/// to another device. The theme and reduce-motion choices do persist on
/// this phone and survive signing out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricLogin = false;
  bool _biometricAvailable = false;
  bool _biometricBusy = false;

  @override
  void initState() {
    super.initState();
    _readBiometric();
  }

  Future<void> _readBiometric() async {
    final lock = context.read<AppState>().biometricLock;
    final available = await lock.isAvailable;
    final enabled = available && await lock.isEnabled;
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricLogin = enabled;
    });
  }

  /// The switch shows what the device agreed to, not what was asked:
  /// turning it on prompts first, and a refused prompt leaves it off.
  Future<void> _setBiometric(bool wanted) async {
    if (_biometricBusy) return;
    setState(() => _biometricBusy = true);
    final settled = await context.read<AppState>().biometricLock.setEnabled(
      wanted,
    );
    if (!mounted) return;
    setState(() {
      _biometricLogin = settled;
      _biometricBusy = false;
    });
    if (wanted && !settled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not turned on: that was not confirmed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return BrutScreen(
      header: BrutHeader(
        title: 'Settings',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrutInlineMessage(
            tone: BrutTone.sun,
            icon: Icons.info_outline,
            text:
                'These stay on this device. There is no settings '
                'endpoint yet, so they do not follow your account.',
          ),
          const SizedBox(height: 20),
          const BrutSectionTitle('Appearance'),
          const SizedBox(height: 10),
          const _ThemePicker(),
          const SizedBox(height: 16),
          const _AccentPicker(),
          // Only on Android: the swap is two manifest components being
          // enabled and disabled, and there is nothing behind it
          // anywhere else.
          if (AppIcons.isSupported) ...[
            const SizedBox(height: 18),
            const BrutSectionTitle('App icon'),
            const SizedBox(height: 10),
            const _IconPicker(),
          ],
          const SizedBox(height: 18),
          _SwitchTile(
            label: 'Sound and vibration',
            subtitle:
                'A short sound and a tap when something registers, is '
                'accepted, or is refused. Your phone\'s silent switch '
                'still wins.',
            value: context.watch<SfxPlayer>().enabled,
            onChanged: context.read<SfxPlayer>().setEnabled,
          ),
          const SizedBox(height: 10),
          _SwitchTile(
            label: 'Reduce motion',
            subtitle:
                'Turns off the press effect, screen '
                'transitions and every other movement. Your '
                'phone\'s own setting is honoured either way.',
            value: settings.reduceMotion,
            onChanged: settings.setReduceMotion,
          ),
          if (context.watch<AppState>().isDemoMode) ...[
            const SizedBox(height: 20),
            const BrutSectionTitle('Demo'),
            const SizedBox(height: 10),
            const _DemoRolePicker(),
            const SizedBox(height: 10),
            BrutListRow(
              title: 'Review a proposal',
              meta: 'The form with a reviewer\'s marks on it',
              marker: const BrutIconTile(
                size: 32,
                icon: Icons.edit_note,
                tone: BrutTone.mint,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SapReviewDemoScreen(),
                ),
              ),
            ),
          ],
          // Only a development build, with no address baked in, needs pointing at a laptop's backend.
          if (!ApiConfig.isConfigured) ...[
            const SizedBox(height: 20),
            const BrutSectionTitle('Backend'),
            const SizedBox(height: 10),
            const BackendAddressCard(),
          ],
          const SizedBox(height: 20),
          const BrutSectionTitle('This device'),
          const SizedBox(height: 10),
          // Only where the hardware is there and enrolled. A switch
          // that cannot work is worse than no switch, and this one
          // used to be offered on every phone while doing nothing at
          // all on any of them.
          if (_biometricAvailable)
            _SwitchTile(
              label: 'Biometric login',
              subtitle:
                  'Ask for your fingerprint or face before opening a '
                  'saved session on this phone.',
              value: _biometricLogin,
              onChanged: _biometricBusy ? null : _setBiometric,
            )
          else
            const BrutInlineMessage(
              tone: BrutTone.neutral,
              icon: Icons.fingerprint,
              text:
                  'Biometric login needs a fingerprint or face enrolled on '
                  'this phone. Add one in the system settings and it will '
                  'be offered here.',
            ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;

    return BrutCard(
      radius: AppRadius.rowAll,
      shadow: enabled ? AppShadows.sm : AppShadows.none,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Light, Dark or System, as three choices you can see at once rather
/// than a switch that only says one of them.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Light, Dark, System — the order the design states, which is
            // not the order the enum happens to declare.
            for (final mode in const [
              ThemeMode.light,
              ThemeMode.dark,
              ThemeMode.system,
            ]) ...[
              Expanded(
                child: BrutSurface(
                  onTap: () => settings.setThemeMode(mode),
                  semanticLabel: mode.label,
                  fill: settings.themeMode == mode
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  radius: AppRadius.controlAll,
                  shadow: settings.themeMode == mode
                      ? AppShadows.base
                      : AppShadows.none,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Icon(switch (mode) {
                        ThemeMode.light => Icons.light_mode_outlined,
                        ThemeMode.dark => Icons.dark_mode_outlined,
                        ThemeMode.system => Icons.brightness_auto_outlined,
                      }, size: 20),
                      const SizedBox(height: 6),
                      Text(
                        mode.label,
                        style: AppText.buttonLabel.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              if (mode != ThemeMode.system) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(settings.themeMode.explanation, style: AppText.caption),
      ],
    );
  }
}

/// Which role the demo is being explored as.
///
/// The seeded records stay the same; what changes is who is looking at
/// them. An event reads one way to the officer who proposed it and
/// another to the office reviewing it, and switching here is how you see
/// both without signing out.
class _DemoRolePicker extends StatelessWidget {
  const _DemoRolePicker();

  /// Every role the app models, in the order the paperwork moves through
  /// them. Signatory is left out: it reviews in a configured order and
  /// has nothing seeded to review.
  static const List<UserRole> _roles = [
    UserRole.officer,
    UserRole.treasurer,
    UserRole.adviser,
    UserRole.sdsStaff,
    UserRole.admin,
    UserRole.superAdmin,
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final current = app.currentRole;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The parent Column stretches its children, which would make
        // every chip full width and stack them one per row. Align lets
        // the Wrap size itself so they sit in rows of two or three.
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in _roles)
                // BrutChip paints into a Container with an alignment and
                // no width, and that fills whatever it is given — so in a
                // Wrap every chip would take the full row. IntrinsicWidth
                // holds each one to its own label.
                IntrinsicWidth(
                  child: BrutChip(
                    label: role.label,
                    selected: role == current,
                    onTap: () => context.read<AppState>().switchDemoRole(role),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        BrutInlineMessage(
          tone: BrutTone.neutral,
          icon: Icons.swap_horiz,
          text:
              'Looking at the same seeded records as '
              '${current?.label ?? 'nobody'}. Nothing is sent anywhere.',
        ),
      ],
    );
  }
}

/// Which colour the app wears.
///
/// The accent comes from the account's department, and for a CITE
/// account that is orange whether or not anyone likes orange. This
/// overrides it on this phone without touching the account: the
/// department is still what the records belong to, and still what the
/// brand pill says — this only changes the paint.
///
/// The swatches are the departments' own palette rather than a colour
/// wheel. Each one was chosen to carry ink on top in both themes, and
/// none of them is coral, which means "a problem" everywhere else in
/// the app. A free picker would be a way to make the app unreadable.
class _AccentPicker extends StatelessWidget {
  const _AccentPicker();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final own = context.watch<AppState>().themeDepartment;
    final chosen = settings.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in Department.values)
              BrutSurface(
                onTap: () => settings.setAccent(
                  // Picking the department's own colour is the same
                  // thing as not having picked, and storing it as a
                  // choice would freeze the app on today's department
                  // if the account ever moved.
                  option == own ? null : option,
                ),
                semanticLabel: option.label,
                radius: AppRadius.controlAll,
                shadow: chosen == option || (chosen == null && option == own)
                    ? AppShadows.base
                    : AppShadows.none,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: option.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.palette.ink,
                          width: AppBorders.width,
                        ),
                      ),
                      child:
                          chosen == option || (chosen == null && option == own)
                          ? Icon(Icons.check, size: 12, color: AppColors.ink)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      option == own ? '${option.label} · yours' : option.label,
                      style: AppText.buttonLabel.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          chosen == null
              ? 'Following ${own.label}, the department on your account.'
              : 'Chosen on this phone. ${own.label} is still the department '
                    'your records belong to.',
          style: AppText.caption,
        ),
        if (chosen != null) ...[
          const SizedBox(height: 10),
          BrutButton(
            label: 'Use my department\'s colour',
            icon: Icons.restart_alt,
            tone: BrutTone.neutral,
            onPressed: () => settings.setAccent(null),
          ),
        ],
      ],
    );
  }
}

/// Which icon the phone shows on its home screen.
///
/// Offered only where it can work: the swap is two Android components
/// being enabled and disabled, and there is nothing behind it anywhere
/// else. A switch that cannot work is worse than no switch.
class _IconPicker extends StatefulWidget {
  const _IconPicker();

  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  static const AppIcons _icons = AppIcons();

  AppIcon? _current;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _icons.current().then((icon) {
      if (mounted) setState(() => _current = icon);
    });
  }

  Future<void> _choose(AppIcon icon) async {
    if (_busy || icon == _current) return;
    setState(() => _busy = true);
    final done = await _icons.set(icon);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (done) _current = icon;
    });
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The icon could not be changed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final icon in AppIcon.values) ...[
              Expanded(
                child: BrutSurface(
                  onTap: _busy ? null : () => _choose(icon),
                  semanticLabel: icon.label,
                  fill: _current == icon
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  radius: AppRadius.controlAll,
                  shadow: _current == icon ? AppShadows.base : AppShadows.none,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      // The icon as it will actually look, rather than a
                      // swatch standing in for it.
                      BrandMark(
                        size: 40,
                        ground: icon == AppIcon.navy
                            ? BrandMark.navy
                            : Colors.white,
                        asset: icon == AppIcon.navy
                            ? 'assets/brand/mark-on-dark.png'
                            : 'assets/brand/mark-on-light.png',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        icon.label,
                        style: AppText.buttonLabel.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              if (icon != AppIcon.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _current == null
              ? 'Reading the current icon…'
              : '${_current!.explanation} The launcher decides what to do '
                    'next: some redraw at once, some only when the home '
                    'screen is next opened, and some bring the home screen '
                    'forward. The app keeps running either way.',
          style: AppText.caption,
        ),
      ],
    );
  }
}
