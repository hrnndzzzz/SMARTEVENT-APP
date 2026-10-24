import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../api/export_saver.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import 'sds_proposals_screen.dart';
import '../widgets/app_header.dart';

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
    final canUpload =
        !app.isOfflineViewing &&
        role != null &&
        role.canAccessProposalLetters &&
        !role.isLetterOnly &&
        role.hasOperationalAccess;

    return BrutScreen(
      // A round button in the corner, the same as downloading a report
      // and scanning a receipt: the one action on the screen, where a
      // thumb already is, rather than a wide bar across the bottom.
      floatingActionButton: canUpload
          ? FloatingActionButton(
              onPressed: () => BrutSheet.show<void>(
                context,
                builder: (_) => const _UploadSheet(),
              ),
              tooltip: 'Upload letter',
              child: const Icon(Icons.upload_file),
            )
          : null,
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      scrollable: false,
      bottomPadding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Proposal letters', style: AppText.screenTitle),
          const SizedBox(height: 4),
          Text(switch (role) {
            null => 'Not signed in.',
            final r when r.isLetterOnly =>
              'Letters submitted across the school, for your review.',
            _ => 'Letters submitted for your organization’s events.',
          }, style: AppText.caption),
          const SizedBox(height: 14),

          // SDS owns Part 4, the checkpoints, the return, the final scan
          // and Part 6, all of them reached through an event — and the
          // role is otherwise held to this screen. Without a way across,
          // the office could be asked to sign what it could not open.
          if (role?.isLetterOnly ?? false) ...[
            BrutListRow(
              title: 'Proposals',
              meta: 'Part 4 onwards, and the signing',
              marker: const BrutIconTile(
                size: 32,
                icon: Icons.fact_check_outlined,
                tone: BrutTone.brand,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SdsProposalsScreen(),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: switch (load) {
              _ when load.isLoading && app.letters.isEmpty => const Center(
                child: BrutSpinner(),
              ),
              _ when load.hasFailed && app.letters.isEmpty => BrutRetry(
                title: 'Could not load letters',
                message: load.error,
                sessionExpired: load.sessionExpired,
                onRetry: app.loadLetters,
              ),
              _ when app.letters.isEmpty => _Empty(canUpload: canUpload),
              _ => RefreshIndicator(
                onRefresh: app.loadLetters,
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: app.letters.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _LetterCard(letter: app.letters[i]),
                ),
              ),
            },
          ),
        ],
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

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrutIconTile(
                icon: letter.looksLikePdf
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(letter.title, style: AppText.cardTitle)),
            ],
          ),
          const SizedBox(height: 14),
          BrutDetailRow('Event', eventTitle ?? letter.eventId),
          const SizedBox(height: 8),
          // An id rather than a name: the backend returns ids, and looking
          // one up would be refused for the role that most needs this list.
          BrutDetailRow('Submitted by', letter.submittedBy),
          const SizedBox(height: 8),
          BrutDetailRow(
            'Submitted',
            BrutDateField.format(letter.createdAt.toLocal()),
            mono: true,
          ),
          const SizedBox(height: 14),
          SelectableText(
            letter.documentUrl,
            style: AppText.caption.copyWith(fontSize: 10),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open document'),
            onPressed: () async {
              try {
                final file = await context.read<AppState>().downloadedFile(
                  letter.documentUrl,
                );
                await ExportSaver.share(file, subject: letter.title);
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$error')));
              }
            },
          ),
          if (context.watch<AppState>().currentRole == UserRole.sdsStaff)
            TextButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Open final signed scan'),
              onPressed: () async {
                try {
                  final file = await context
                      .read<AppState>()
                      .sapService
                      .finalScanFile(letter.eventId);
                  await ExportSaver.share(file, subject: letter.title);
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$error')));
                }
              },
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.canUpload});

  final bool canUpload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: BrutEmptyState(
        icon: Icons.description_outlined,
        title: 'No letters yet',
        hint: canUpload
            ? 'Upload a proposal letter against one of your events.'
            : 'Letters appear here once they are submitted.',
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
      setState(
        () => _error =
            'Letters must be PDF, JPEG or PNG. That file is not one of those.',
      );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Letter uploaded.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = context
        .watch<AppState>()
        .events
        .where((e) => e.remoteId != null)
        .toList();

    return BrutSheet(
      title: 'Upload a proposal letter',
      subtitle:
          'Separate from submitting the event — this does not '
          'advance its review.',
      footer: BrutButton(
        label: 'Upload letter',
        size: BrutSize.large,
        busy: _submitting,
        busyLabel: 'Uploading…',
        onPressed: _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutDropdown<String>(
            label: 'Event',
            value: _eventId,
            hint: events.isEmpty ? 'No events available' : 'Select an event',
            items: [
              for (final e in events)
                DropdownMenuItem(value: e.remoteId, child: Text(e.title)),
            ],
            onChanged: (v) => setState(() => _eventId = v),
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Title',
            controller: _titleController,
            maxLength: 200,
            hint: 'e.g. Leadership Summit proposal letter',
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 14),
          const MonoLabel('Document'),
          const SizedBox(height: 6),
          BrutButton(
            label: _filename ?? 'Choose a file',
            icon: Icons.attach_file,
            tone: BrutTone.neutral,
            onPressed: _submitting ? null : _pick,
          ),
          const SizedBox(height: 6),
          const Text('PDF, JPEG or PNG, up to 10MB.', style: AppText.caption),
          if (_error != null) ...[
            const SizedBox(height: 14),
            BrutInlineMessage(text: _error!, tone: BrutTone.coral),
          ],
        ],
      ),
    );
  }
}
