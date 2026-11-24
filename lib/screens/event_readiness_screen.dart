import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/compliance_service.dart';
import '../api/models/compliance.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import '../widgets/app_header.dart';

/// Why an event cannot be approved yet, and the two things you can do
/// about it from here.
///
/// The October backend will not let an Admin hand an event on until it
/// has been classified and has an institutional route. Both refusals
/// arrive as a 409 with a list of sentences, which is useless on its own
/// — this screen asks for the same list up front and makes each item
/// something you can act on.
class EventReadinessScreen extends StatefulWidget {
  const EventReadinessScreen({super.key, required this.event});

  final EventItem event;

  @override
  State<EventReadinessScreen> createState() => _EventReadinessScreenState();
}

class _EventReadinessScreenState extends State<EventReadinessScreen> {
  bool _loading = true;

  /// True when this deployment has no institutional-approval routes at
  /// all, which is a different thing from an event that is not ready.
  bool _unavailable = false;

  String? _error;
  EventLogistics? _logistics;
  EventReadiness? _readiness;

  String? get _eventId => widget.event.remoteId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = _eventId;
    if (id == null) {
      setState(() {
        _loading = false;
        _error = 'This proposal has not reached the server yet.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final app = context.read<AppState>();
      final results = await Future.wait([
        // Officers may not read logistics; that is no reason to fail the
        // readiness they may read.
        app
            .eventLogistics(id)
            .catchError(
              (_) => null,
              test: (e) => e is ApiException && e.isForbidden,
            ),
        app.eventReadiness(id),
      ]);
      if (!mounted) return;
      setState(() {
        _logistics = results[0] as EventLogistics?;
        _readiness = results[1] as EventReadiness;
        _loading = false;
      });
    } on FeatureUnavailable {
      if (mounted) {
        setState(() {
          _unavailable = true;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrutScreen(
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MonoLabel('Before approval'),
          const SizedBox(height: 4),
          Text(widget.event.title, style: AppText.display),
          const SizedBox(height: AppLayout.section),
          if (_loading)
            const Center(
              child: Padding(padding: EdgeInsets.all(32), child: BrutSpinner()),
            )
          else if (_unavailable)
            const BrutInlineMessage(
              icon: Icons.cloud_off_outlined,
              text:
                  'This server does not have institutional approval yet. '
                  'Classification and readiness appear once the backend '
                  'carrying them is deployed.',
            )
          else if (_error != null)
            BrutRetry(
              title: 'Could not load readiness',
              message: _error,
              onRetry: _load,
            )
          else ...[
            _ReadinessCard(readiness: _readiness!),
            const SizedBox(height: AppLayout.section),
            _LogisticsCard(
              logistics: _logistics,
              // The server refuses logistics writes from officers.
              onEdit: context.read<AppState>().currentRole == UserRole.officer
                  ? null
                  : _editLogistics,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editLogistics() async {
    final saved = await BrutSheet.show<bool>(
      context,
      builder: (_) => _LogisticsSheet(eventId: _eventId!, existing: _logistics),
    );
    if (saved == true) await _load();
  }
}

/// Ready, or the list of reasons it is not.
class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.readiness});

  final EventReadiness readiness;

  @override
  Widget build(BuildContext context) {
    if (readiness.ready) {
      return BrutCard(
        tone: BrutTone.mint,
        radius: AppRadius.rowAll,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 20),
            const SizedBox(width: AppLayout.between),
            Expanded(
              child: Text(
                'Ready for approval.',
                style: AppText.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    return BrutFoldable(
      title: 'Still in the way',
      count: readiness.blockers.length,
      children: [
        for (final blocker in readiness.blockers) ...[
          BrutListRow(
            // The backend's own wording. Rephrasing it here would mean
            // the refusal at approval time and the list here read as two
            // different rules.
            title: blocker,
            marker: const BrutIconTile(
              icon: Icons.priority_high,
              tone: BrutTone.coral,
              size: 32,
            ),
          ),
          const SizedBox(height: AppLayout.tight),
        ],
      ],
    );
  }
}

class _LogisticsCard extends StatelessWidget {
  const _LogisticsCard({required this.logistics, required this.onEdit});

  final EventLogistics? logistics;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final value = logistics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BrutSectionTitle('Where it happens'),
        const SizedBox(height: AppLayout.between),
        BrutCard(
          radius: AppRadius.rowAll,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (value == null)
                Text(
                  'Not classified yet. Every event needs this before it '
                  'can be approved.',
                  style: AppText.caption.copyWith(
                    color: context.palette.subtle,
                  ),
                )
              else ...[
                BrutDetailRow('Location', value.activityLocation.label),
                BrutDetailRow('Destination', value.destination),
                BrutDetailRow('Transport', value.transportMode.label),
                if (value.transportNotes?.isNotEmpty == true)
                  BrutDetailRow('Notes', value.transportNotes!),
              ],
              const SizedBox(height: AppLayout.between),
              BrutButton(
                label: value == null ? 'Classify this activity' : 'Change',
                icon: Icons.place_outlined,
                tone: value == null ? BrutTone.brand : BrutTone.neutral,
                size: BrutSize.small,
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Classify the activity.
///
/// On-campus forces transport to "no vehicles" — the backend refuses any
/// other combination with a 422, so the form will not offer one.
class _LogisticsSheet extends StatefulWidget {
  const _LogisticsSheet({required this.eventId, required this.existing});

  final String eventId;
  final EventLogistics? existing;

  @override
  State<_LogisticsSheet> createState() => _LogisticsSheetState();
}

class _LogisticsSheetState extends State<_LogisticsSheet> {
  late ActivityLocation _location =
      widget.existing?.activityLocation ?? ActivityLocation.onCampus;
  late TransportMode _transport =
      widget.existing?.transportMode ?? TransportMode.none;
  late final _destination = TextEditingController(
    text: widget.existing?.destination ?? '',
  );
  late final _notes = TextEditingController(
    text: widget.existing?.transportNotes ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _destination.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _changesClearance {
    final was = widget.existing;
    if (was == null) return false;
    return was.activityLocation != _location ||
        was.destination != _destination.text.trim() ||
        was.transportMode != _transport;
  }

  Future<void> _save() async {
    if (_destination.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter where the activity happens.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppState>().saveEventLogistics(
        widget.eventId,
        EventLogistics(
          activityLocation: _location,
          destination: _destination.text.trim(),
          transportMode: _transport,
          transportNotes: _notes.text.trim().isEmpty
              ? null
              : _notes.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrutSheet(
      title: 'Where it happens',
      subtitle: 'On campus asks for far less than off campus.',
      footer: BrutButton(
        label: 'Save',
        size: BrutSize.large,
        busy: _saving,
        busyLabel: 'Saving…',
        onPressed: _saving ? null : _save,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MonoLabel('Location'),
          const SizedBox(height: 6),
          BrutChipBar(
            children: [
              for (final option in ActivityLocation.values)
                BrutChip(
                  label: option.label,
                  selected: option == _location,
                  onTap: () => setState(() {
                    _location = option;
                    // On campus means no vehicles, by the backend's rule.
                    if (option == ActivityLocation.onCampus) {
                      _transport = TransportMode.none;
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppLayout.between),
          BrutTextField(
            label: 'Destination',
            controller: _destination,
            hint: _location == ActivityLocation.onCampus
                ? 'e.g. Gymnasium, AVR'
                : 'e.g. Museum of Natural History, Manila',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppLayout.between),
          const MonoLabel('Transport'),
          const SizedBox(height: 6),
          if (_location == ActivityLocation.onCampus)
            Text(
              'On-campus activities use no vehicles.',
              style: AppText.caption.copyWith(color: context.palette.subtle),
            )
          else
            BrutChipBar(
              children: [
                for (final option in TransportMode.values)
                  BrutChip(
                    label: option.label,
                    selected: option == _transport,
                    onTap: () => setState(() => _transport = option),
                  ),
              ],
            ),
          if (_location == ActivityLocation.offCampus) ...[
            const SizedBox(height: AppLayout.between),
            BrutTextField(
              label: _transport == TransportMode.none
                  ? 'Why no vehicles are needed'
                  : 'Transport notes',
              controller: _notes,
              maxLines: 2,
              hint: _transport == TransportMode.none
                  ? 'Required when no vehicle transport is used'
                  : 'Anything the reviewers should know',
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
          if (_changesClearance) ...[
            const SizedBox(height: AppLayout.between),
            const BrutInlineMessage(
              icon: Icons.warning_amber_outlined,
              text:
                  'Changing the location, destination or transport clears '
                  'verification already done. The uploaded files are kept '
                  'and have to be reviewed again.',
            ),
          ],
        ],
      ),
    );
  }
}
