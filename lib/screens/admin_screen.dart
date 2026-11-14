import 'package:flutter/material.dart';
import '../api/models/roster_import.dart';
import '../api/api_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/scope_picker.dart';
import '../widgets/module_band.dart';

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
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      scrollable: false,
      bottomPadding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.contentPadding),
          const ModuleBand(
            icon: Icons.manage_accounts_outlined,
            title: 'Administration',
            tone: BrutTone.brand,
            subtitle: 'Roster, accounts and the audit log.',
          ),
          // Departments and organizations were SQL-only before this.
          if (context.watch<AppState>().currentRole == UserRole.superAdmin) ...[
            const SizedBox(height: AppLayout.tight),
            Wrap(
              spacing: AppLayout.tight,
              runSpacing: AppLayout.tight,
              children: [
                BrutButton(
                  label: 'Add organization',
                  icon: Icons.add_business_outlined,
                  size: BrutSize.small,
                  expand: false,
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final created = await _addOrganization(context);
                    if (created == null) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('${created.code} added.')),
                    );
                  },
                ),
                BrutButton(
                  label: 'Add department',
                  icon: Icons.account_balance_outlined,
                  size: BrutSize.small,
                  tone: BrutTone.neutral,
                  expand: false,
                  onPressed: () => BrutSheet.show<void>(
                    context,
                    builder: (_) => const _AddDepartmentSheet(),
                  ),
                ),
              ],
            ),
          ],
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
                  child: BrutSpinner(),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A roster arrives as a spreadsheet far more often than one
              // name at a time, and the route for it was already there
              // with nothing calling it.
              FloatingActionButton(
                heroTag: 'roster-import',
                onPressed: () => _importRoster(context),
                tooltip: 'Upload a roster',
                child: const Icon(Icons.upload_file),
              ),
              const SizedBox(width: 10),
              FloatingActionButton.extended(
                heroTag: 'roster-add',
                onPressed: () => BrutSheet.show<void>(
                  context,
                  builder: (_) => const _AddRosterSheet(),
                ),
                icon: const Icon(Icons.person_add_alt),
                label: Text('Add to roster', style: AppText.buttonLabel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Picks a workbook and sends it.
///
/// A refusal names every bad row rather than stopping at the first, so
/// it opens a sheet listing them instead of a one-line snackbar: a
/// roster of two hundred with four bad emails needs those four pointed
/// at, not a count of them.
Future<void> _importRoster(BuildContext context) async {
  final picked = await FilePicker.pickFiles(
    dialogTitle: 'Choose the roster workbook',
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
  );
  final file = picked.firstOrNull;
  if (file == null || !context.mounted) return;

  final bytes = await file.readAsBytes();
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await context.read<AppState>().importRoster(
      bytes: bytes,
      filename: file.name,
    );
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${result.insertedCount} '
          '${result.insertedCount == 1 ? 'person' : 'people'} added. '
          'They can create an account now.',
        ),
      ),
    );
  } on RosterImportRejected catch (rejected) {
    if (!context.mounted) return;
    await BrutSheet.show<void>(
      context,
      builder: (_) => _RosterErrorsSheet(errors: rejected.errors),
    );
  } on ArgumentError catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('${error.message}')));
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error is ApiException ? error.message : 'Could not read that file.',
        ),
      ),
    );
  }
}

/// Every row the workbook got wrong.
class _RosterErrorsSheet extends StatelessWidget {
  const _RosterErrorsSheet({required this.errors});

  final List<RosterRowError> errors;

  @override
  Widget build(BuildContext context) {
    return BrutSheet(
      title: 'Nothing was added',
      subtitle:
          'The whole workbook is checked before any of it goes on, so '
          'fix these and upload it again.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final error in errors) ...[
            BrutCard(
              tone: BrutTone.coral,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonoLabel('Row ${error.row} · ${error.column}', fontSize: 10),
                  const SizedBox(height: 4),
                  Text(error.message, style: AppText.body),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          BrutInlineMessage(
            tone: BrutTone.neutral,
            icon: Icons.table_chart_outlined,
            text:
                'The columns it looks for: '
                '${RosterWorkbook.headers.join(', ')}.',
          ),
        ],
      ),
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
    final school = app.currentRole?.canAdministerSchool ?? false;

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.only(
            bottom: school ? 96 : AppLayout.contentPadding,
          ),
          children: [
            const Text(
              'Accounts that exist. Access is revoked by suspending, which '
              'keeps everything the account did — there is no delete.',
              style: AppText.caption,
            ),
            const SizedBox(height: 14),
            if (load.isLoading && app.managedUsers.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: BrutSpinner(),
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
        ),
        // Admin, SDS and Signatory accounts never come from the roster.
        // Without a signatory, no Admin can approve a plain event.
        if (school)
          Positioned(
            right: 0,
            bottom: AppLayout.gutter,
            child: FloatingActionButton.extended(
              heroTag: 'school-account-add',
              onPressed: () => BrutSheet.show<void>(
                context,
                builder: (_) => const _AddSchoolAccountSheet(),
              ),
              icon: const Icon(Icons.badge_outlined),
              label: Text('Add school account', style: AppText.buttonLabel),
            ),
          ),
      ],
    );
  }
}

/// Creates an Admin, SDS Staff or Signatory account. The server emails a
/// temporary password, so nothing here asks for one.
class _AddSchoolAccountSheet extends StatefulWidget {
  const _AddSchoolAccountSheet();

  @override
  State<_AddSchoolAccountSheet> createState() => _AddSchoolAccountSheetState();
}

class _AddSchoolAccountSheetState extends State<_AddSchoolAccountSheet> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _positionController = TextEditingController();

  UserRole _role = UserRole.signatory;
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
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter their full name.');
      return;
    }
    if (_emailController.text.trim().isEmpty) {
      setState(() => _error = 'Enter their email.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final position = _positionController.text.trim();
    final app = context.read<AppState>();
    final error = await app.createPrivilegedAccount(
      role: _role,
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      position: position.isEmpty ? null : position,
      departmentId: _organizationId == null
          ? null
          : app.departmentOfOrganization(_organizationId!),
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
          content: Text('Created. A temporary password was emailed to them.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return BrutSheet(
      title: 'Add a school account',
      subtitle:
          'The server emails a temporary password, which they change at '
          'first sign-in.',
      footer: BrutButton(
        label: 'Create account',
        size: BrutSize.large,
        busy: _submitting,
        busyLabel: 'Creating…',
        onPressed: _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutDropdown<UserRole>(
            label: 'Role',
            value: _role,
            hint: 'Select a role',
            items: [
              for (final role in const [
                UserRole.signatory,
                UserRole.sdsStaff,
                UserRole.admin,
              ])
                DropdownMenuItem(value: role, child: Text(role.label)),
            ],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: 6),
          Text(_role.responsibility, style: AppText.caption),
          const SizedBox(height: 14),
          if (_role == UserRole.admin) ...[
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
              explanation: 'An Admin manages one department.',
              allowNoDepartment: false,
            ),
            const SizedBox(height: 8),
            _NewOrganizationButton(
              departmentId: _departmentId,
              allowNoDepartment: false,
              onCreated: (org) => setState(() {
                _departmentId = org.departmentId ?? kNoDepartment;
                _organizationId = org.id;
              }),
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
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Position (optional)',
            controller: _positionController,
            textCapitalization: TextCapitalization.words,
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
    final app = context.watch<AppState>();
    final isSelf = app.currentAccount?.id == user.id;
    final canManage = manageableRolesFor(app.currentRole).contains(user.role);

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
                // mustChangePassword is tested before isUsable because
                // an invited account is both: active, not suspended,
                // and therefore green — which made "Awaiting password
                // setup" read as a finished state. It is a waiting one.
                tone: user.isSuspended
                    ? BrutTone.coral
                    : user.mustChangePassword || !user.isActive
                    ? BrutTone.sun
                    : BrutTone.mint,
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
          else if (!canManage)
            const BrutInlineMessage(
              tone: BrutTone.neutral,
              icon: Icons.lock_outline,
              text: 'Only the Dean or a Super Admin can change this account.',
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: BrutButton(
                    label: 'Change access',
                    icon: Icons.tune,
                    tone: BrutTone.neutral,
                    size: BrutSize.small,
                    onPressed: () => _AccessSheet.show(context, user),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BrutButton(
                    label: user.isSuspended ? 'Restore' : 'Suspend',
                    tone: user.isSuspended ? BrutTone.mint : BrutTone.coral,
                    size: BrutSize.small,
                    onPressed: () =>
                        _confirmSuspension(context, !user.isSuspended),
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
            child: Padding(padding: EdgeInsets.all(24), child: BrutSpinner()),
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
    final by = context
        .watch<AppState>()
        .managedUsers
        .where((u) => u.id == entry.userId)
        .map((u) => u.fullName)
        .firstOrNull;
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
          // The backend records who, as an id, and does not resolve it.
          // This screen has already loaded the accounts, so the name is
          // usually sitting right there — "By demo-user-2" told a
          // reader nothing. Anyone outside that list, which is anyone
          // outside the reader's own scope, still shows as the id
          // rather than as a guess.
          Text(
            'By ${by ?? entry.userId}',
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
    final schoolWide = _role.isSchoolWide;
    if (app.mustChooseScope && !schoolWide && _organizationId == null) {
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
      // The organization's own department, blank only where it has none.
      departmentId: schoolWide || _organizationId == null
          ? null
          : app.departmentOfOrganization(_organizationId!),
      organizationId: schoolWide ? null : _organizationId,
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
          if (app.mustChooseScope && !_role.isSchoolWide) ...[
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
            const SizedBox(height: 8),
            _NewOrganizationButton(
              departmentId: _departmentId,
              onCreated: (org) => setState(() {
                _departmentId = org.departmentId ?? kNoDepartment;
                _organizationId = org.id;
              }),
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
              for (final role in manageableRolesFor(app.currentRole))
                DropdownMenuItem(value: role, child: Text(role.label)),
            ],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: 6),
          Text(
            _role.isSchoolWide
                ? '${_role.label} accounts are school-wide, so they have no '
                      'department or organization.'
                : 'They get this role when they register.',
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

/// Change what an account may do: its organization, its role, its title.
///
/// The organization is the part that needed a screen. An account with
/// none cannot create anything the backend will accept, and there was no
/// way to give it one — `updateUserAccess` had carried an organizationId
/// since the roster work and nothing called it.
///
/// Moving an account between organizations is a Super Admin's job; an
/// Admin sees their own organization and can still change role and
/// position within it.
class _AccessSheet extends StatefulWidget {
  const _AccessSheet({required this.user});

  final ManagedUser user;

  static Future<void> show(BuildContext context, ManagedUser user) {
    return BrutSheet.show<void>(
      context,
      builder: (_) => _AccessSheet(user: user),
    );
  }

  @override
  State<_AccessSheet> createState() => _AccessSheetState();
}

class _AccessSheetState extends State<_AccessSheet> {
  late String? _organizationId = widget.user.organizationId;
  late UserRole? _role = widget.user.role;
  late final _position = TextEditingController(
    text: widget.user.position ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final app = context.read<AppState>();
    final canTransfer = app.currentRole?.canAdministerSchool ?? false;
    final error = await app.updateUserAccess(
      widget.user,
      role: _role,
      position: _position.text.trim().isEmpty ? null : _position.text.trim(),
      // Only a Super Admin may send an organization at all, and a
      // school-wide role must not carry one.
      organizationId:
          canTransfer &&
              !(_role?.isSchoolWide ?? false) &&
              _organizationId != widget.user.organizationId
          ? _organizationId
          : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Access updated.')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final canTransfer = app.currentRole?.canAdministerSchool ?? false;
    final organizations = app.organizations;

    return BrutSheet(
      title: 'Change access',
      subtitle: widget.user.fullName,
      footer: BrutButton(
        label: 'Save changes',
        size: BrutSize.large,
        busy: _saving,
        busyLabel: 'Saving…',
        onPressed: _saving ? null : _save,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_role?.isSchoolWide ?? false)
            BrutInlineMessage(
              icon: Icons.public,
              text:
                  '${_role!.label} accounts are school-wide, so they leave '
                  'their organization.',
            )
          else if (canTransfer)
            BrutDropdown<String>(
              label: 'Organization',
              value: _organizationId,
              hint: organizations.isEmpty
                  ? 'No organizations to choose from'
                  : 'Select an organization',
              items: [
                for (final organization in organizations)
                  DropdownMenuItem(
                    value: organization.id,
                    child: Text(organization.name),
                  ),
              ],
              onChanged: (id) => setState(() => _organizationId = id),
            )
          else
            const BrutInlineMessage(
              icon: Icons.lock_outline,
              text:
                  'Only a Super Admin can move an account to another '
                  'organization.',
            ),
          const SizedBox(height: AppLayout.between),
          BrutDropdown<UserRole>(
            label: 'Role',
            value: _role,
            hint: 'Select a role',
            items: [
              for (final role in manageableRolesFor(app.currentRole))
                DropdownMenuItem(value: role, child: Text(role.label)),
            ],
            onChanged: (role) => setState(() => _role = role),
          ),
          const SizedBox(height: AppLayout.between),
          BrutTextField(
            label: 'Position',
            controller: _position,
            hint: 'e.g. Treasurer, 3rd year',
            textCapitalization: TextCapitalization.words,
          ),
        ],
      ),
    );
  }
}

/// Opens [_AddOrganizationSheet]; the organization it made, or null.
Future<RemoteOrganization?> _addOrganization(
  BuildContext context, {
  String? departmentId,
  bool allowNoDepartment = true,
}) => BrutSheet.show<RemoteOrganization>(
  context,
  builder: (_) => _AddOrganizationSheet(
    departmentId: departmentId,
    allowNoDepartment: allowNoDepartment,
  ),
);

/// "New organization" under a scope picker, for the Super Admin, who
/// alone may make one — so a roster entry need not wait for SQL.
class _NewOrganizationButton extends StatelessWidget {
  const _NewOrganizationButton({
    required this.departmentId,
    required this.onCreated,
    this.allowNoDepartment = true,
  });

  final String? departmentId;
  final bool allowNoDepartment;
  final ValueChanged<RemoteOrganization> onCreated;

  @override
  Widget build(BuildContext context) {
    if (context.watch<AppState>().currentRole != UserRole.superAdmin) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: BrutButton(
        label: 'New organization',
        icon: Icons.add,
        size: BrutSize.small,
        tone: BrutTone.neutral,
        expand: false,
        onPressed: () async {
          final created = await _addOrganization(
            context,
            departmentId: departmentId,
            allowNoDepartment: allowNoDepartment,
          );
          if (created != null) onCreated(created);
        },
      ),
    );
  }
}

/// A new organization, in a department or in none.
///
/// "No department" is a choice, not a default left blank: a member of an
/// organization with a department must carry it, and the server refuses
/// one sent without it.
class _AddOrganizationSheet extends StatefulWidget {
  const _AddOrganizationSheet({
    this.departmentId,
    this.allowNoDepartment = true,
  });

  final String? departmentId;
  final bool allowNoDepartment;

  @override
  State<_AddOrganizationSheet> createState() => _AddOrganizationSheetState();
}

class _AddOrganizationSheetState extends State<_AddOrganizationSheet> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  late String? _departmentId = widget.departmentId;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim().toUpperCase();
    final name = _name.text.trim();
    final problem = _departmentId == null
        ? (widget.allowNoDepartment
              ? 'Choose its department, or No department.'
              : 'Choose its department.')
        : code.isEmpty
        ? 'Enter a short code, like JPSSITE.'
        : name.isEmpty
        ? 'Enter its full name.'
        : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final error = await app.createOrganization(
      code: code,
      name: name,
      departmentId: departmentOrNull(_departmentId),
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }
    // createOrganization appends what the server made.
    Navigator.of(context).pop(app.organizations.last);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return BrutSheet(
      title: 'Add an organization',
      subtitle:
          'It appears in every organization picker at once. Its members are '
          'added through the roster.',
      footer: BrutButton(
        label: 'Add organization',
        size: BrutSize.large,
        busy: _submitting,
        busyLabel: 'Adding…',
        onPressed: _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutDropdown<String>(
            label: 'Department',
            value: _departmentId,
            hint: 'Select a department',
            items: [
              for (final d in app.departments)
                DropdownMenuItem(value: d.id, child: Text(d.label)),
              if (widget.allowNoDepartment)
                const DropdownMenuItem(
                  value: kNoDepartment,
                  child: Text('No department'),
                ),
            ],
            onChanged: (id) => setState(() => _departmentId = id),
          ),
          const SizedBox(height: 6),
          Text(
            _departmentId == kNoDepartment
                ? 'Its members have no department, and its proposals go '
                      'from the Moderator straight to the SDS Office.'
                : 'Its members carry this department, and its proposals '
                      'go to that department\'s Dean.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Code',
            controller: _code,
            hint: 'JPSSITE',
            maxLength: 30,
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Full name',
            controller: _name,
            hint: 'Junior Philippine Student Society for IT',
            maxLength: 150,
            textCapitalization: TextCapitalization.words,
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

class _AddDepartmentSheet extends StatefulWidget {
  const _AddDepartmentSheet();

  @override
  State<_AddDepartmentSheet> createState() => _AddDepartmentSheetState();
}

class _AddDepartmentSheetState extends State<_AddDepartmentSheet> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim().toUpperCase();
    final name = _name.text.trim();
    if (code.isEmpty || name.isEmpty) {
      setState(() => _error = 'Enter a code and a full name.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final description = _description.text.trim();
    final error = await context.read<AppState>().createDepartment(
      code: code,
      name: name,
      description: description.isEmpty ? null : description,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$code added.')));
  }

  @override
  Widget build(BuildContext context) {
    return BrutSheet(
      title: 'Add a department',
      subtitle: 'Then add its organizations, and an Admin to act as its Dean.',
      footer: BrutButton(
        label: 'Add department',
        size: BrutSize.large,
        busy: _submitting,
        busyLabel: 'Adding…',
        onPressed: _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutTextField(
            label: 'Code',
            controller: _code,
            hint: 'CITE',
            maxLength: 20,
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Full name',
            controller: _name,
            hint: 'College of Information Technology and Engineering',
            maxLength: 150,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Description (optional)',
            controller: _description,
            maxLines: 3,
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
