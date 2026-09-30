import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
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
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Administration',
                        style: TextStyle(
                          fontFamily: AppText.headerFamily,
                          fontWeight: FontWeight.w500,
                          fontSize: 18,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final (i, label) in const [
                        (0, 'Approved Roster'),
                        (1, 'Accounts'),
                        (2, 'Audit'),
                      ])
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _select(i),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _tab == i
                                    ? AppColors.indigo
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _tab == i
                                      ? AppColors.indigo
                                      : AppColors.border,
                                ),
                              ),
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: AppText.bodyFamily,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: _tab == i
                                      ? Colors.white
                                      : AppColors.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (_tab) {
                0 => const _RosterTab(),
                1 => const _AccountsTab(),
                _ => const _AuditTab(),
              },
            ),
          ],
        ),
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
          children: [
            const Text(
              'People approved to create an account. Adding someone here '
              'does not create one — it lets that email register, and their '
              'name and role come from the entry.',
              style: AppText.caption,
            ),
            const SizedBox(height: 14),
            if (load.isLoading && app.roster.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (load.hasFailed && app.roster.isEmpty)
              Text(load.error!,
                  style: AppText.caption.copyWith(color: AppColors.brick))
            else if (app.roster.isEmpty)
              const Text('Nobody on the roster yet.', style: AppText.caption)
            else
              for (final entry in app.roster) ...[
                _RosterCard(entry: entry),
                const SizedBox(height: 10),
              ],
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const _AddRosterSheet(),
            ),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add to Roster'),
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
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brick),
            child: const Text('Remove'),
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
            children: [
              Expanded(child: Text(entry.fullName, style: AppText.cardTitle)),
              // A claimed entry is spent: its account carries on from here,
              // so removal and free editing are both gone.
              if (entry.isClaimed)
                const _Tag(
                  label: 'Claimed',
                  fg: AppColors.sageTealText,
                  bg: AppColors.sageTealTint,
                )
              else
                IconButton(
                  onPressed: () => _confirmRemove(context),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(entry.email, style: AppText.caption),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _Tag(
                label: entry.role.label,
                fg: AppColors.indigo,
                bg: AppColors.indigoLightTint,
              ),
              if (entry.position?.isNotEmpty == true)
                _Tag(
                  label: entry.position!,
                  fg: AppColors.inkMuted,
                  bg: AppColors.trackBg,
                ),
            ],
          ),
          if (entry.isClaimed) ...[
            const SizedBox(height: 8),
            const Text(
              'An account was created from this entry. Manage it under '
              'Accounts.',
              style: TextStyle(
                fontFamily: AppText.bodyFamily,
                fontSize: 10,
                color: AppColors.inkFaint,
              ),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        const Text(
          'Accounts that exist. Access is revoked by suspending, which keeps '
          'everything the account did — there is no delete.',
          style: AppText.caption,
        ),
        const SizedBox(height: 14),
        if (load.isLoading && app.managedUsers.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
        else if (load.hasFailed && app.managedUsers.isEmpty)
          Text(load.error!,
              style: AppText.caption.copyWith(color: AppColors.brick))
        else if (app.managedUsers.isEmpty)
          const Text('No accounts in your scope.', style: AppText.caption)
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
        title: Text(suspend ? 'Suspend this account?' : 'Restore access?',
            style: AppText.cardTitle),
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
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: suspend
                ? FilledButton.styleFrom(backgroundColor: AppColors.brick)
                : null,
            child: Text(suspend ? 'Suspend' : 'Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final error =
        await context.read<AppState>().setUserSuspended(user, suspend);
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ??
            (suspend ? 'Access suspended.' : 'Access restored.')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSelf = context.watch<AppState>().currentAccount?.id == user.id;

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
            children: [
              Expanded(child: Text(user.fullName, style: AppText.cardTitle)),
              _Tag(
                label: user.statusLabel,
                fg: user.isSuspended
                    ? AppColors.brick
                    : user.isUsable
                        ? AppColors.sageTealText
                        : AppColors.marigoldText,
                bg: user.isSuspended
                    ? const Color(0xFFFBEAE7)
                    : user.isUsable
                        ? AppColors.sageTealTint
                        : AppColors.marigoldTint,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(user.email, style: AppText.caption),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _Tag(
                label: user.role?.label ?? 'Unknown role',
                fg: AppColors.indigo,
                bg: AppColors.indigoLightTint,
              ),
              if (user.position?.isNotEmpty == true)
                _Tag(
                  label: user.position!,
                  fg: AppColors.inkMuted,
                  bg: AppColors.trackBg,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isSelf)
            const Text(
              'This is your own account — you cannot change your own access.',
              style: TextStyle(
                fontFamily: AppText.bodyFamily,
                fontSize: 10,
                color: AppColors.inkFaint,
              ),
            )
          else
            OutlinedButton(
              onPressed: () => _confirmSuspension(context, !user.isSuspended),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                foregroundColor:
                    user.isSuspended ? AppColors.sageTealText : AppColors.brick,
              ),
              child: Text(user.isSuspended ? 'Restore access' : 'Suspend access'),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        const Text(
          'A read-only record of administrative changes. Entries cannot be '
          'edited or removed.',
          style: AppText.caption,
        ),
        const SizedBox(height: 14),
        if (load.isLoading && app.auditLog.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
        else if (load.hasFailed && app.auditLog.isEmpty)
          Text(load.error!,
              style: AppText.caption.copyWith(color: AppColors.brick))
        else if (app.auditLog.isEmpty)
          const Text('Nothing recorded yet.', style: AppText.caption)
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
        Text(entry.readableAction,
            style: AppText.caption.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(
          '${at.year}-${at.month.toString().padLeft(2, '0')}'
          '-${at.day.toString().padLeft(2, '0')} '
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}'
          '${entry.entityType == null ? '' : ' · ${entry.entityType}'}',
          style: AppText.caption,
        ),
        if (entry.userId != null) ...[
          const SizedBox(height: 2),
          // An id, not a name — the backend does not resolve them.
          Text(
            'By ${entry.userId}',
            style: const TextStyle(
              fontFamily: AppText.bodyFamily,
              fontSize: 10,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppText.bodyFamily,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
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
    if (app.mustChooseScope && (_departmentId == null || _organizationId == null)) {
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
              const Text('Add to the approved roster',
                  style: AppText.cardTitle),
              const SizedBox(height: 2),
              const Text(
                'This creates no account. It lets that email register, and '
                'their name and role come from this entry.',
                style: AppText.caption,
              ),
              const SizedBox(height: 16),

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

              const Text('Full name', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(controller: _nameController),
              const SizedBox(height: 14),

              const Text('Email', style: AppText.caption),
              const SizedBox(height: 2),
              const Text(
                'Must match exactly what they register with.',
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 10,
                  color: AppColors.inkFaint,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),

              const Text('Role', style: AppText.caption),
              const SizedBox(height: 2),
              const Text(
                'Admin and SDS accounts are created separately by a Super '
                'Admin, not through the roster.',
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 10,
                  color: AppColors.inkFaint,
                ),
              ),
              const SizedBox(height: 6),
              LabeledDropdown<UserRole>(
                value: _role,
                hint: 'Select a role',
                items: [
                  for (final role in memberRoles)
                    DropdownMenuItem(value: role, child: Text(role.label)),
                ],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 14),

              const Text('Position (optional)', style: AppText.caption),
              const SizedBox(height: 2),
              const Text(
                'A title like President. It never affects permissions.',
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 10,
                  color: AppColors.inkFaint,
                ),
              ),
              const SizedBox(height: 6),
              TextField(controller: _positionController),

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
                    : const Text('Add to roster'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
