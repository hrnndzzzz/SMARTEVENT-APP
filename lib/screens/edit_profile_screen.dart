import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/avatar.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import '../widgets/user_avatar.dart';

/// Your name and your picture.
///
/// The picture is built here rather than uploaded: initials, one of
/// eight marks drawn from your name, or a photo. All of it stays on this
/// phone — there is no avatar route on the backend — and the screen says
/// so rather than implying a sync that does not exist.
class EditProfileScreen extends StatefulWidget {
  final String name;
  final String role;

  const EditProfileScreen({super.key, required this.name, required this.role});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;

  late AvatarStyle _style;
  late int _color;
  late AvatarPattern _pattern;
  Uint8List? _photo;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final avatar = context.read<Avatar>();
    final account = app.currentAccount;
    final name = account?.name ?? widget.name;

    _nameController = TextEditingController(text: name);
    _emailController = TextEditingController(text: account?.email ?? '');
    _style = avatar.style;
    _color = avatar.colorFor(name);
    _pattern = avatar.patternFor(name);
    _photo = avatar.photo;

    // The initials and the generated mark both follow the name, so the
    // preview has to keep up with it as it is typed.
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String get _name => _nameController.text.trim();

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final square = await _toSquare(bytes);
      if (square == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('That file could not be opened as an image.'),
            ),
          );
        }
        return;
      }
      if (mounted) {
        setState(() {
          _photo = square;
          _style = AvatarStyle.photo;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That photo could not be opened.')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (_name.isEmpty) return;
    setState(() => _saving = true);
    final app = context.read<AppState>();
    await context.read<Avatar>().save(
      style: _style,
      color: _color,
      pattern: _pattern,
      photo: _style == AvatarStyle.photo ? _photo : null,
    );
    app.updateProfile(name: _name, email: _emailController.text.trim());
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved on this phone.')));
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AppState>().currentAccount;

    return BrutScreen(
      header: BrutHeader(
        eyebrow: 'Account',
        title: 'Edit profile',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      footer: BrutFooter(
        child: BrutButton(
          label: _name.isEmpty ? 'Enter your name' : 'Save profile',
          size: BrutSize.large,
          busy: _saving,
          busyLabel: 'Saving…',
          onPressed: _name.isEmpty || _saving ? null : _save,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PictureCard(
            name: _name.isEmpty ? widget.name : _name,
            style: _style,
            color: _color,
            pattern: _pattern,
            photo: _photo,
            onStyle: (style) async {
              if (style == AvatarStyle.photo && _photo == null) {
                await _pickPhoto();
                return;
              }
              setState(() => _style = style);
            },
            onColor: (color) => setState(() => _color = color),
            onPattern: (pattern) => setState(() => _pattern = pattern),
            onPickPhoto: _pickPhoto,
            onRemovePhoto: () => setState(() {
              _photo = null;
              _style = AvatarStyle.initials;
            }),
          ),
          const SizedBox(height: AppLayout.section),
          const BrutSectionTitle('Profile'),
          const SizedBox(height: AppLayout.between),
          BrutTextField(
            label: 'Full name',
            controller: _nameController,
            hint: 'e.g. Demo Admin',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppLayout.between),
          BrutTextField(
            label: 'Email',
            controller: _emailController,
            hint: 'you@lcup.edu.ph',
          ),
          const SizedBox(height: AppLayout.between),
          // Role and department are the backend's to say, not yours.
          BrutCard(
            radius: AppRadius.rowAll,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MonoLabel('Set by your administrator'),
                const SizedBox(height: 8),
                BrutDetailRow('Role', widget.role),
                if (account?.position?.isNotEmpty ?? false)
                  BrutDetailRow('Position', account!.position!),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.between),
          const BrutInlineMessage(
            icon: Icons.phone_android,
            tone: BrutTone.neutral,
            text:
                'Your picture is kept on this phone. Signing in elsewhere '
                'shows your initials until you set one there too.',
          ),
        ],
      ),
    );
  }
}

/// Crops to a centred square and shrinks to 256px.
///
/// Off the UI thread: a gallery photo is several megapixels and decoding
/// one on the main isolate drops the frame the preview is drawn in.
Future<Uint8List?> _toSquare(Uint8List bytes) async {
  return Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final side = math.min(decoded.width, decoded.height);
    final square = img.copyCrop(
      decoded,
      x: ((decoded.width - side) / 2).round(),
      y: ((decoded.height - side) / 2).round(),
      width: side,
      height: side,
    );
    return Uint8List.fromList(
      img.encodeJpg(img.copyResize(square, width: 256), quality: 85),
    );
  });
}

/// The picture, and everything that makes it.
///
/// The preview updates as you change anything, including the name —
/// both the initials and the generated mark come from it, so a picture
/// that lagged a rename would be describing somebody else.
class _PictureCard extends StatelessWidget {
  const _PictureCard({
    required this.name,
    required this.style,
    required this.color,
    required this.pattern,
    required this.photo,
    required this.onStyle,
    required this.onColor,
    required this.onPattern,
    required this.onPickPhoto,
    required this.onRemovePhoto,
  });

  final String name;
  final AvatarStyle style;
  final int color;
  final AvatarPattern pattern;
  final Uint8List? photo;
  final ValueChanged<AvatarStyle> onStyle;
  final ValueChanged<int> onColor;
  final ValueChanged<AvatarPattern> onPattern;
  final VoidCallback onPickPhoto;
  final VoidCallback onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      padding: const EdgeInsets.all(AppLayout.contentPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: UserAvatar(
              name: name,
              size: 96,
              style: style,
              color: color,
              pattern: pattern,
              photo: photo,
            ),
          ),
          const SizedBox(height: AppLayout.section),
          Row(
            children: [
              for (final option in AvatarStyle.values) ...[
                Expanded(
                  child: Semantics(
                    inMutuallyExclusiveGroup: true,
                    selected: option == style,
                    child: BrutButton(
                      label: option.label,
                      size: BrutSize.small,
                      tone: option == style ? BrutTone.dark : BrutTone.neutral,
                      onPressed: () => onStyle(option),
                    ),
                  ),
                ),
                if (option != AvatarStyle.values.last) const SizedBox(width: 8),
              ],
            ],
          ),

          if (style == AvatarStyle.pattern) ...[
            const SizedBox(height: AppLayout.section),
            const MonoLabel('Pattern'),
            const SizedBox(height: AppLayout.between),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.78,
              children: [
                for (final option in AvatarPattern.values)
                  _PatternTile(
                    name: name,
                    pattern: option,
                    color: color,
                    selected: option == pattern,
                    onTap: () => onPattern(option),
                  ),
              ],
            ),
          ],

          if (style != AvatarStyle.photo) ...[
            const SizedBox(height: AppLayout.section),
            const MonoLabel('Background colour'),
            const SizedBox(height: AppLayout.between),
            Row(
              children: [
                for (final swatch in avatarColors) ...[
                  Expanded(
                    child: Semantics(
                      inMutuallyExclusiveGroup: true,
                      selected: swatch == color,
                      label:
                          '#${swatch.toRadixString(16).substring(2).toUpperCase()}',
                      child: GestureDetector(
                        onTap: () => onColor(swatch),
                        behavior: HitTestBehavior.opaque,
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Color(swatch),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.ink,
                                width: swatch == color ? 2.5 : 1,
                              ),
                            ),
                            child: swatch == color
                                ? const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: AppColors.ink,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppLayout.section),
            BrutButton(
              label: photo == null ? 'Upload a photo' : 'Use your photo',
              icon: Icons.photo_library_outlined,
              tone: BrutTone.neutral,
              size: BrutSize.small,
              onPressed: photo == null
                  ? onPickPhoto
                  : () => onStyle(AvatarStyle.photo),
            ),
          ] else ...[
            const SizedBox(height: AppLayout.section),
            Row(
              children: [
                Expanded(
                  child: BrutButton(
                    label: 'Change photo',
                    icon: Icons.photo_library_outlined,
                    tone: BrutTone.neutral,
                    size: BrutSize.small,
                    onPressed: onPickPhoto,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BrutButton(
                    label: 'Remove',
                    icon: Icons.close,
                    tone: BrutTone.coral,
                    size: BrutSize.small,
                    onPressed: onRemovePhoto,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One mark in the grid, drawn on the colour you have chosen.
class _PatternTile extends StatelessWidget {
  const _PatternTile({
    required this.name,
    required this.pattern,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final AvatarPattern pattern;
  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: pattern.label,
      child: BrutSurface(
        onTap: onTap,
        fill: selected ? context.palette.ink : context.palette.surface,
        radius: AppRadius.controlAll,
        shadow: AppShadows.sm,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(
              name: name,
              size: 32,
              style: AvatarStyle.pattern,
              color: color,
              pattern: pattern,
            ),
            const SizedBox(height: 4),
            Text(
              pattern.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.monoLabel.copyWith(fontSize: 8.5),
            ),
          ],
        ),
      ),
    );
  }
}
