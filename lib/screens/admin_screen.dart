import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import 'notifications_screen.dart';
import '../widgets/scope_picker.dart';

/// Roster, accounts and audit.
///
/// The roster and the account list are kept visibly separate because they
/// are different things: a roster entry is permission to create an account,
/// and an account is what exists afterwards. Conflating them is how you end
/// up "deleting a user" by removing a roster row that no longer governs
/// anything.
///
/// There is no Delete User anywhere here. The backend has no such endpoint
/// — access is revoked by suspending, which keeps the account's history
/// intact.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppState>();
      app.loadRoster();
      app.loadManagedUsers();
    });
  }

  void _select(int index) {
    setState(() => _tab = index);
    final app = context.read<AppState>();
    if (index == 2 && app.auditLog.isEmpty) app.loadAuditLog();
  }

  @override
  Widget build(BuildContext context) {
    return BrutScreen(
      topBar: AppHeader(
        onBack: () => Navigator.of(context).maybePop(),
        onBellTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      ),
      scrollable: false,
      bottomPadding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.contentPadding),
          const Text('Administration', style: AppText.titleBig),
          const SizedBox(height: AppLayout.between),
          Row(
            children: [
              for (final (i, label) in const [
                (0, 'Roster'),
                (1, 'Accounts'),
                (2, 'Audit'),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppLayout.tight),
                    child: BrutChip(
                      label: label,
                      selected: _tab == i,
                      onTap: () => _select(i),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppLayout.between),
          Expanded(
            child: switch (_tab) {
              0 => const _RosterTab(),
              1 => const _AccountsTab(),
              _ => const _AuditTab(),
            },
          ),
        ],
      ),
    );
  }
}

class _RosterTab extends StatelessWidget {
  const _RosterTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.rosterLoad;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const Text(
              'People approved to create an account. Adding someone here '
              'does not create one — it lets that email register, and their '
              'name and role come from the entry.',
              style: AppText.caption,
            ),
            const SizedBox(height: 14),
            if (load.isLoading && app.roster.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (load.hasFailed && app.roster.isEmpty)
              BrutInlineMessage(text: load.error!, tone: BrutTone.coral)
            else if (app.roster.isEmpty)
              const BrutEmptyState(title: 'Nobody on the roster yet')
            else
              for (final entry in app.roster) ...[
                _RosterCard(entry: entry),
                const SizedBox(height: 10),
              ],
          ],
        ),
        // The screen already supplies the side gutter, so this only needs
        // to clear the bottom.
        Positioned(
          right: 0,
          bottom: AppLayout.gutter,
          child: FloatingActionButton.extended(
            onPressed: () => BrutSheet.show<void>(
              context,
              builder: (_) => const _AddRosterSheet(),
            ),
            icon: const Icon(Icons.person_add_alt),
            label: Text('Add to roster', style: AppText.buttonLabel),
          ),
        ),
      ],
    );
  }
}

class _RosterCard extends StatelessWidget {
  const _RosterCard({required this.entry});

  final RosterEntry entry;

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from roster?', style: AppText.cardTitle),
        content: Text(
          '${entry.fullName} will no longer be able to register. Nothing '
          'else is affected — no account exists for this entry yet.',
          style: AppText.caption,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          BrutButton(
            label: 'Remove',
            tone: BrutTone.coral,
            size: BrutSize.small,
            expand: false,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<AppState>().removeRosterEntry(entry);
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'Removed from the roster.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(entry.fullName, style: AppText.cardTitle)),
              // A claimed entry is spent: its account carries on from here,
              // so removal and free editing are both gone.
              if (entry.isClaimed)
                const BrutBadge(label: 'Claimed', tone: BrutTone.mint)
              else
                BrutIconButton(
                  icon: Icons.delete_outline,
                  label: 'Remove ${entry.fullName} from the roster',
                  size: 32,
                  onPressed: () => _confirmRemove(context),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(entry.email, style: AppText.caption),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BrutBadge(label: entry.role.label, tone: BrutTone.brand),
              if (entry.position?.isNotEmpty == true)
                BrutBadge(label: entry.position!, mono: true),
            ],
          ),
          if (entry.isClaimed) ...[
            const SizedBox(height: 10),
            const Text(
              'An account was created from this entry. Manage it under '
              'Accounts.',
              style: AppText.caption,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountsTab extends StatelessWidget {
  const _AccountsTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.usersLoad;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppLayout.contentPadding),
      children: [
        const Text(
          'Accounts that exist. Access is revoked by suspending, which keeps '
          'everything the account did — there is no delete.',
          style: AppText.caption,
        ),
        const SizedBox(height: 14),
        if (load.isLoading && app.managedUsers.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (load.hasFailed && app.managedUsers.isEmpty)
          BrutInlineMessage(text: load.error!, tone: BrutTone.coral)
        else if (app.managedUsers.isEmpty)
          const BrutEmptyState(title: 'No accounts in your scope')
        else
          for (final user in app.managedUsers) ...[
            _UserCard(user: user),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final ManagedUser user;

  Future<void> _confirmSuspension(BuildContext context, bool suspend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          suspend ? 'Suspend this account?' : 'Restore access?',
          style: AppText.cardTitle,
        ),
        content: Text(
          suspend
              // Spelling out what suspension actually does, rather than a
              // bare "are you sure".
              ? '${user.fullName} will lose access immediately, including on '
                    'any device already signed in. Their records stay exactly '
                    'as they are, and you can restore access later.'
              : '${user.fullName} will be able to sign in again. If they '
                    'never finished setting a password, they still have to.',
          style: AppText.caption,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          BrutButton(
            label: suspend ? 'Suspend' : 'Restore',
            tone: suspend ? BrutTone.coral : BrutTone.mint,
            size: BrutSize.small,
            expand: false,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<AppState>().setUserSuspended(
      user,
      suspend,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ?? (suspend ? 'Access suspended.' : 'Access restored.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSelf = context.watch<AppState>().currentAccount?.id == user.id;

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(user.fullName, style: AppText.cardTitle)),
              const SizedBox(width: 8),
              BrutBadge(
                label: user.statusLabel,
                tone: user.isSuspended
                    ? BrutTone.coral
                    : user.isUsable
                    ? BrutTone.mint
                    : BrutTone.sun,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(user.email, style: AppText.caption),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BrutBadge(
                label: user.role?.label ?? 'Unknown role',
                tone: BrutTone.brand,
              ),
              if (user.position?.isNotEmpty == true)
                BrutBadge(label: user.position!, mono: true),
            ],
          ),
          const SizedBox(height: 14),
          if (isSelf)
            const BrutInlineMessage(
              tone: BrutTone.neutral,
              icon: Icons.person_outline,
              text:
                  'This is your own account — you cannot change your own '
                  'access.',
            )
          else
            BrutButton(
              label: user.isSuspended ? 'Restore access' : 'Suspend access',
              tone: user.isSuspended ? BrutTone.mint : BrutTone.coral,
              size: BrutSize.small,
              onPressed: () => _confirmSuspension(context, !user.isSuspended),
            ),
        ],
      ),
    );
  }
}

class _AuditTab extends StatelessWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.auditLoad;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppLayout.contentPadding),
      children: [
        const Text(
          'A read-only record of administrative changes. Entries cannot be '
          'edited or removed.',
          style: AppText.caption,
        ),
        const SizedBox(height: 14),
        if (load.isLoading && app.auditLog.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (load.hasFailed && app.auditLog.isEmpty)
          BrutInlineMessage(text: load.error!, tone: BrutTone.coral)
        else if (app.auditLog.isEmpty)
          const BrutEmptyState(title: 'Nothing recorded yet')
        else
          for (final entry in app.auditLog) ...[
            _AuditRow(entry: entry),
            const Divider(height: 18),
          ],
      ],
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final at = entry.createdAt.toLocal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.readableAction,
          style: AppText.body.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        MonoLabel(
          '${at.year}-${at.month.toString().padLeft(2, '0')}'
          '-${at.day.toString().padLeft(2, '0')} '
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}'
          '${entry.entityType == null ? '' : ' · ${entry.entityType}'}',
        ),
        if (entry.userId != null) ...[
          const SizedBox(height: 4),
          // An id, not a name — the backend does not resolve them.
          Text(
            'By ${entry.userId}',
            style: AppText.caption.copyWith(fontSize: 10),
          ),
        ],
      ],
    );
  }
}

/// Adding someone to the approved roster.
class _AddRosterSheet extends StatefulWidget {
  const _AddRosterSheet();

  @override
  State<_AddRosterSheet> createState() => _AddRosterSheetState();
}

class _AddRosterSheetState extends State<_AddRosterSheet> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _positionController = TextEditingController();

  UserRole _role = UserRole.officer;
  String? _departmentId;
  String? _organizationId;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final app = context.read<AppState>();

    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter their full name.');
      return;
    }
    if (_emailController.text.trim().isEmpty) {
      setState(() => _error = 'Enter the email they will register with.');
      return;
    }
    if (app.mustChooseScope &&
        (_departmentId == null || _organizationId == null)) {
      setState(() => _error = 'Choose a department and organization.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await app.addRosterEntry(
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      role: _role,
      position: _positionController.text.trim().isEmpty
          ? null
          : _positionController.text.trim(),
      departmentId: _departmentId,
      organizationId: _organizationId,
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });

    if (error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added. They can now register with that email.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return BrutSheet(
      title: 'Add to the approved roster',
      subtitle:
          'This creates no account. It lets that email register, and '
          'their name and role come from this entry.',
      footer: BrutButton(
        label: 'Add to roster',
        size: BrutSize.large,
        busy: _submitting,
        busyLabel: 'Adding…',
        onPressed: _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (app.mustChooseScope) ...[
            ScopePicker(
              departments: app.departments,
              departmentId: _departmentId,
              onDepartmentChanged: (id) => setState(() {
                _departmentId = id;
                _organizationId = null;
              }),
              organizations: app.organizationsIn(_departmentId),
              organizationId: _organizationId,
              onOrganizationChanged: (id) =>
                  setState(() => _organizationId = id),
              explanation:
                  'Your account is not tied to a department, so choose '
                  'where this member belongs.',
            ),
            const SizedBox(height: 14),
          ],
          BrutTextField(
            label: 'Full name',
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Email',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 6),
          const Text(
            'Must match exactly what they register with.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          BrutDropdown<UserRole>(
            label: 'Role',
            value: _role,
            hint: 'Select a role',
            items: [
              for (final role in memberRoles)
                DropdownMenuItem(value: role, child: Text(role.label)),
            ],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: 6),
          const Text(
            'Admin and SDS accounts are created separately by a Super '
            'Admin, not through the roster.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Position (optional)',
            controller: _positionController,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 6),
          const Text(
            'A title like President. It never affects permissions.',
            style: AppText.caption,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            BrutInlineMessage(text: _error!, tone: BrutTone.coral),
          ],
        ],
      ),
    );
  }
}
