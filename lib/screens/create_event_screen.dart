import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import '../widgets/scope_picker.dart';

class CreateEventScreen extends StatefulWidget {
  final EventItem? existingEvent;

  const CreateEventScreen({super.key, this.existingEvent});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _dateController;
  late final TextEditingController _budgetController;
  final _descriptionController = TextEditingController();

  DateTime? _pickedDate;
  String? _selectedCategoryId;
  bool _submitting = false;

  /// Academic metadata — required on every event, and what makes the
  /// records reportable by year, semester and scope.
  String? _schoolYear;
  Semester? _semester;
  EventScope? _eventScope;

  /// Only for accounts with no scope of their own — a Super Admin.
  String? _departmentId;
  String? _organizationId;

  bool get _isEditing => widget.existingEvent != null;

  /// Which half of the form is showing. The budget gets a screen of its
  /// own because it is the number everyone argues about, and because a
  /// keypad you can hit without looking beats a text field on a phone
  /// held in one hand at a supplier's counter.
  int _step = 0;

  /// Known years merged with local suggestions, so the picker is never
  /// empty and a brand-new school year can still be started.
  List<String> get _schoolYearOptions => SchoolYear.mergeOptions(
    context.read<AppState>().knownSchoolYears,
    DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    final e = widget.existingEvent;
    _schoolYear = e?.schoolYear;
    _semester = e?.semester;
    _eventScope = e?.eventScope;
    // Refresh the year list in the background; the picker works without it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadSchoolYears();
    });
    _nameController = TextEditingController(text: e?.title ?? '');
    _dateController = TextEditingController(text: e?.date ?? '');
    _budgetController = TextEditingController(
      text: e?.budget.replaceAll('₱', '') ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dateController.dispose();
    _budgetController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      setState(() {
        _pickedDate = picked;
        _dateController.text =
            '${months[picked.month - 1]} ${picked.day}, ${picked.year}';
      });
    }
  }

  /// Client-side checks that mirror the backend's, so the user finds out
  /// before a round trip rather than from a 422.
  String? _validate() {
    if (_nameController.text.trim().isEmpty) {
      return 'Please enter an event name.';
    }
    if (_schoolYear == null) return 'Choose a school year.';
    if (!SchoolYear.isValid(_schoolYear!)) {
      return 'A school year must be two consecutive years, like 2026-2027.';
    }
    if (_semester == null) return 'Choose a semester.';
    if (_eventScope == null) {
      return 'Choose whether this is departmental or organizational.';
    }
    if (!_isEditing && context.read<AppState>().mustChooseScope) {
      // No department on the account means the backend cannot infer one.
      if (_departmentId == null) return 'Choose a department for this event.';
      if (_organizationId == null) return 'Choose an organization.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    final title = _nameController.text.trim();
    final date = _dateController.text.trim().isEmpty
        ? 'TBD'
        : _dateController.text.trim();
    final budgetValue = double.tryParse(_budgetController.text.trim()) ?? 0.0;
    final budget = '₱${budgetValue.toStringAsFixed(2)}';

    if (_isEditing) {
      setState(() => _submitting = true);
      final e = widget.existingEvent!;
      final app = context.read<AppState>();
      final error = await app.resubmitEvent(
        e,
        title: title,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        eventDate: _pickedDate,
        estimatedCost: budgetValue,
        allocatedBudget: budgetValue,
        schoolYear: _schoolYear == e.schoolYear ? null : _schoolYear,
        semester: _semester == e.semester ? null : _semester,
        eventScope: _eventScope == e.eventScope ? null : _eventScope,
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      if (error == null) {
        e.date = date;
        e.budget = budget;
        e.schoolYear = _schoolYear;
        e.semester = _semester;
        e.eventScope = _eventScope;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title revised and resubmitted for adviser review.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    } else {
      setState(() => _submitting = true);
      final app = context.read<AppState>();
      final error = await app.addEvent(
        title: title,
        categoryId: _selectedCategoryId,
        estimatedCost: budgetValue,
        eventDate: _pickedDate,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        schoolYear: _schoolYear!,
        semester: _semester!,
        eventScope: _eventScope!,
        departmentId: _departmentId,
        organizationId: _organizationId,
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      if (error == null) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$title submitted for review.')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  /// Appends a digit or a decimal point, the way a calculator would.
  void _press(String key) {
    final text = _budgetController.text;
    setState(() {
      if (key == '<') {
        if (text.isNotEmpty) {
          _budgetController.text = text.substring(0, text.length - 1);
        }
        return;
      }
      if (key == '.') {
        if (text.contains('.')) return;
        _budgetController.text = text.isEmpty ? '0.' : '$text.';
        return;
      }
      // Two decimal places is as fine as money gets here.
      final dot = text.indexOf('.');
      if (dot >= 0 && text.length - dot > 2) return;
      if (text == '0') {
        _budgetController.text = key;
        return;
      }
      _budgetController.text = '$text$key';
    });
  }

  String get _amountDisplay {
    final text = _budgetController.text;
    if (text.isEmpty) return '0';
    final value = double.tryParse(text);
    // While it is being typed, show exactly what was typed — formatting
    // a half-finished number fights the person entering it.
    if (text.endsWith('.') || text.contains('.') || value == null) return text;
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return BrutScreen(
      header: BrutFlowHeader(
        flowName: _isEditing ? 'Revise proposal' : 'New proposal',
        title: _step == 0 ? 'How much?' : 'The details',
        currentStep: _step,
        steps: [
          BrutStep(
            label: 'Budget',
            onJump: _step == 1 ? () => setState(() => _step = 0) : null,
          ),
          const BrutStep(label: 'Details'),
        ],
        onBack: () => _step == 0
            ? Navigator.of(context).maybePop()
            : setState(() => _step = 0),
      ),
      scrollable: _step == 1,
      bottomPadding: 0,
      footer: BrutFooter(
        child: _step == 0
            ? BrutButton(
                label: 'Next',
                trailingIcon: Icons.arrow_forward,
                size: BrutSize.large,
                onPressed: () => setState(() => _step = 1),
              )
            : BrutButton(
                label: _isEditing ? 'Save changes' : 'Submit for review',
                size: BrutSize.large,
                busy: _submitting,
                busyLabel: _isEditing ? 'Saving…' : 'Submitting…',
                onPressed: _submit,
              ),
      ),
      child: _step == 0 ? _budgetStep(context) : _detailsStep(context, app),
    );
  }

  Widget _budgetStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutTextField(
          label: 'Event name',
          controller: _nameController,
          hint: 'e.g. Leadership Summit 2026',
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        const Spacer(),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MonoLabel('Requested budget'),
              const SizedBox(height: AppLayout.between),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '₱',
                        style: AppText.heroNumber.copyWith(
                          fontSize: 34,
                          color: context.palette.subtle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(_amountDisplay, style: AppText.heroNumber),
                  ],
                ),
              ),
              const SizedBox(height: AppLayout.tight),
              Text(
                _nameController.text.trim().isEmpty
                    ? 'Name it above, then set the budget'
                    : 'for ${_nameController.text.trim()}',
                style: AppText.caption,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const Spacer(),
        _Keypad(onPress: _press),
        const SizedBox(height: AppLayout.between),
      ],
    );
  }

  Widget _detailsStep(BuildContext context, AppState app) {
    final categories = app.categories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutCard(
          tone: BrutTone.brand,
          tinted: true,
          radius: AppRadius.rowAll,
          padding: const EdgeInsets.all(12),
          onTap: () => setState(() => _step = 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _nameController.text.trim().isEmpty
                          ? 'Unnamed event'
                          : _nameController.text.trim(),
                      style: AppText.cardTitle.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    const MonoLabel('Tap to change the budget'),
                  ],
                ),
              ),
              Text('₱$_amountDisplay', style: AppText.number),
            ],
          ),
        ),
        const SizedBox(height: AppLayout.section),
        if (!_isEditing) ...[
          BrutDropdown<String>(
            label: 'Category',
            value: _selectedCategoryId,
            hint: 'Select a category',
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _selectedCategoryId = v),
          ),
          const SizedBox(height: AppLayout.between),
        ],
        if (!_isEditing && app.mustChooseScope) ...[
          ScopePicker(
            departments: app.departments,
            departmentId: _departmentId,
            onDepartmentChanged: (id) => setState(() {
              _departmentId = id;
              _organizationId = null;
            }),
            organizations: app.organizationsIn(_departmentId),
            organizationId: _organizationId,
            onOrganizationChanged: (id) => setState(() => _organizationId = id),
            explanation:
                'Your account is not tied to a department, so '
                'choose where this event belongs.',
          ),
          const SizedBox(height: AppLayout.between),
        ],
        // Required: these are what make the event reportable by year,
        // semester and department, and the backend rejects a new event
        // without them.
        BrutDropdown<String>(
          label: 'School year',
          value: _schoolYear,
          hint: 'Select a school year',
          items: [
            for (final year in _schoolYearOptions)
              DropdownMenuItem(value: year, child: Text(year)),
          ],
          onChanged: (v) => setState(() => _schoolYear = v),
        ),
        const SizedBox(height: AppLayout.between),
        BrutDropdown<Semester>(
          label: 'Semester',
          value: _semester,
          hint: 'Select a semester',
          items: [
            for (final s in Semester.values)
              DropdownMenuItem(value: s, child: Text(s.label)),
          ],
          onChanged: (v) => setState(() => _semester = v),
        ),
        const SizedBox(height: AppLayout.between),
        BrutDropdown<EventScope>(
          label: 'Event scope',
          value: _eventScope,
          hint: 'Departmental or organizational',
          items: [
            for (final scope in EventScope.values)
              DropdownMenuItem(value: scope, child: Text(scope.label)),
          ],
          onChanged: (v) => setState(() => _eventScope = v),
        ),
        const SizedBox(height: AppLayout.between),
        GestureDetector(
          onTap: _pickDate,
          child: AbsorbPointer(
            child: BrutTextField(
              label: 'Date',
              controller: _dateController,
              hint: 'Tap to select a date',
              suffix: const Icon(Icons.calendar_today_outlined, size: 16),
            ),
          ),
        ),
        const SizedBox(height: AppLayout.between),
        BrutTextField(
          label: 'Description',
          controller: _descriptionController,
          hint: 'Briefly describe the event…',
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }
}

/// The keypad from the amount screen: big targets, no shift, no cursor.
class _Keypad extends StatelessWidget {
  const _Keypad({required this.onPress});

  final void Function(String key) onPress;

  static const _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', '<'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _keys) ...[
          Row(
            children: [
              for (final key in row) ...[
                Expanded(
                  child: _Key(label: key, onTap: () => onPress(key)),
                ),
                if (key != row.last) const SizedBox(width: AppLayout.tight),
              ],
            ],
          ),
          if (row != _keys.last) const SizedBox(height: AppLayout.tight),
        ],
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBackspace = label == '<';
    return BrutSurface(
      onTap: onTap,
      semanticLabel: isBackspace ? 'Delete' : label,
      radius: AppRadius.rowAll,
      shadow: AppShadows.sm,
      height: 56,
      alignment: Alignment.center,
      child: isBackspace
          ? const Icon(Icons.backspace_outlined, size: 20)
          : Text(label, style: AppText.moneyLarge.copyWith(fontSize: 22)),
    );
  }
}
