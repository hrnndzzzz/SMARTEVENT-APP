import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/scope_picker.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

/// Proposal letters.
///
/// This is the whole of the SDS Staff role: it reads letters school-wide
/// and reaches nothing else. The screen is therefore careful to work
/// entirely from `/proposal-letters` — it never looks up an event or a user
/// name, because those calls would be refused for that role.
///
/// Uploading a letter is separate from submitting or approving its event.
/// Nothing here advances a review, and SDS cannot approve anything.
class ProposalLettersScreen extends StatefulWidget {
  const ProposalLettersScreen({super.key});

  @override
  State<ProposalLettersScreen> createState() => _ProposalLettersScreenState();
}

class _ProposalLettersScreenState extends State<ProposalLettersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadLetters();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final role = app.currentRole;
    final load = app.lettersLoad;

    // SDS reads school-wide but uploads nothing; Officers reach none of it.
    final canUpload = role != null &&
        role.canAccessProposalLetters &&
        !role.isLetterOnly &&
        role.hasOperationalAccess;

    return Scaffold(
      floatingActionButton: canUpload
          ? FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const _UploadSheet(),
              ),
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Letter'),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Proposal Letters',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                switch (role) {
                  null => 'Not signed in.',
                  final r when r.isLetterOnly =>
                    'Letters submitted across the school, for your review.',
                  _ => 'Letters submitted for your organization’s events.',
                },
                style: AppText.caption,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: switch (load) {
                  _ when load.isLoading && app.letters.isEmpty =>
                    const Center(child: CircularProgressIndicator()),
                  _ when load.hasFailed && app.letters.isEmpty => Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(load.error!,
                                style: AppText.caption,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: app.loadLetters,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _ when app.letters.isEmpty => _Empty(canUpload: canUpload),
                  _ => RefreshIndicator(
                      onRefresh: app.loadLetters,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: app.letters.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _LetterCard(letter: app.letters[i]),
                      ),
                    ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LetterCard extends StatelessWidget {
  const _LetterCard({required this.letter});

  final ProposalLetter letter;

  @override
  Widget build(BuildContext context) {
    // Null for SDS, which never loads events — the id is shown instead,
    // which is what the backend returns anyway.
    final eventTitle = context.watch<AppState>().eventTitleFor(letter.eventId);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                letter.looksLikePdf
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined,
                size: 18,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(letter.title, style: AppText.cardTitle)),
            ],
          ),
          const SizedBox(height: 8),
          _row('Event', eventTitle ?? letter.eventId),
          const SizedBox(height: 4),
          // An id rather than a name: the backend returns ids, and looking
          // one up would be refused for the role that most needs this list.
          _row('Submitted by', letter.submittedBy),
          const SizedBox(height: 4),
          _row(
            'Submitted',
            '${letter.createdAt.toLocal().year}-'
                '${letter.createdAt.toLocal().month.toString().padLeft(2, '0')}-'
                '${letter.createdAt.toLocal().day.toString().padLeft(2, '0')}',
          ),
          const SizedBox(height: 10),
          SelectableText(
            letter.documentUrl,
            style: const TextStyle(
              fontFamily: AppText.bodyFamily,
              fontSize: 10,
              color: AppColors.indigo,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Copy the link to open the document.',
            style: TextStyle(
              fontFamily: AppText.bodyFamily,
              fontSize: 10,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 92, child: Text(label, style: AppText.caption)),
        Expanded(
          child: Text(value, style: AppText.caption.copyWith(color: AppColors.ink)),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.canUpload});

  final bool canUpload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined,
              size: 44, color: AppColors.inkFaint),
          const SizedBox(height: 14),
          const Text('No letters yet', style: AppText.cardTitle),
          const SizedBox(height: 6),
          SizedBox(
            width: 280,
            child: Text(
              canUpload
                  ? 'Upload a proposal letter against one of your events.'
                  : 'Letters appear here once they are submitted.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Uploading a letter: pick an event, name it, attach the document.
class _UploadSheet extends StatefulWidget {
  const _UploadSheet();

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  final _picker = ImagePicker();
  final _titleController = TextEditingController();

  String? _eventId;
  List<int>? _bytes;
  String? _filename;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    if (proposalLetterContentTypeFor(file.name) == null) {
      setState(() => _error =
          'Letters must be PDF, JPEG or PNG. That file is not one of those.');
      return;
    }

    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _filename = file.name;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_eventId == null) {
      setState(() => _error = 'Choose the event this letter is for.');
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      setState(() => _error = 'Give the letter a title.');
      return;
    }
    if (_bytes == null) {
      setState(() => _error = 'Attach the document.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await context.read<AppState>().uploadLetter(
          eventId: _eventId!,
          title: _titleController.text.trim(),
          bytes: _bytes!,
          filename: _filename!,
        );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });

    if (error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Letter uploaded.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final events =
        context.watch<AppState>().events.where((e) => e.remoteId != null).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Upload a proposal letter', style: AppText.cardTitle),
              const SizedBox(height: 2),
              const Text(
                'Separate from submitting the event — this does not advance '
                'its review.',
                style: AppText.caption,
              ),
              const SizedBox(height: 16),

              const Text('Event', style: AppText.caption),
              const SizedBox(height: 6),
              LabeledDropdown<String>(
                value: _eventId,
                hint: events.isEmpty ? 'No events available' : 'Select an event',
                items: [
                  for (final e in events)
                    DropdownMenuItem(value: e.remoteId, child: Text(e.title)),
                ],
                onChanged: (v) => setState(() => _eventId = v),
              ),
              const SizedBox(height: 14),

              const Text('Title', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _titleController,
                maxLength: 200,
                decoration: const InputDecoration(
                  hintText: 'e.g. Leadership Summit proposal letter',
                ),
              ),

              const Text('Document', style: AppText.caption),
              const SizedBox(height: 2),
              const Text(
                'PDF, JPEG or PNG, up to 10MB.',
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 10,
                  color: AppColors.inkFaint,
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pick,
                icon: const Icon(Icons.attach_file, size: 16),
                label: Text(_filename ?? 'Choose a file'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brick.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppColors.brick.withValues(alpha: 0.3)),
                  ),
                  child: Text(_error!,
                      style: AppText.caption.copyWith(color: AppColors.brick)),
                ),
              ],

              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Upload letter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
