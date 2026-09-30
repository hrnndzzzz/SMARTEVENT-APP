import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
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
  late final TextEditingController _venueController;
  late final TextEditingController _attendeesController;
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
    _venueController = TextEditingController(text: e?.venue ?? '');
    _attendeesController = TextEditingController(
      text: e?.attendees.replaceAll(' (expected)', '') ?? '',
    );
    _budgetController = TextEditingController(
      text: e?.budget.replaceAll('₱', '') ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dateController.dispose();
    _venueController.dispose();
    _attendeesController.dispose();
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
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      setState(() {
        _pickedDate = picked;
        _dateController.text = '${months[picked.month - 1]} ${picked.day}, ${picked.year}';
      });
    }
  }

  /// Client-side checks that mirror the backend's, so the user finds out
  /// before a round trip rather than from a 422.
  String? _validate() {
    if (_nameController.text.trim().isEmpty) return 'Please enter an event name.';
    if (_schoolYear == null) return 'Choose a school year.';
    if (!SchoolYear.isValid(_schoolYear!)) {
      return 'A school year must be two consecutive years, like 2026-2027.';
    }
    if (_semester == null) return 'Choose a semester.';
    if (_eventScope == null) return 'Choose whether this is departmental or organizational.';
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    final title = _nameController.text.trim();
    final date = _dateController.text.trim().isEmpty ? 'TBD' : _dateController.text.trim();
    final venue = _venueController.text.trim().isEmpty ? 'TBD' : _venueController.text.trim();
    final budgetValue = double.tryParse(_budgetController.text.trim()) ?? 0.0;
    final budget = '₱${budgetValue.toStringAsFixed(2)}';
    final attendees = _attendeesController.text.trim().isEmpty
        ? 'TBD'
        : '${_attendeesController.text.trim()} (expected)';

    if (_isEditing) {
      setState(() => _submitting = true);
      final e = widget.existingEvent!;
      final app = context.read<AppState>();
      final error = await app.resubmitEvent(
        e,
        title: title,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
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
        e.venue = venue;
        e.budget = budget;
        e.attendees = attendees;
        e.schoolYear = _schoolYear;
        e.semester = _semester;
        e.eventScope = _eventScope;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title revised and resubmitted for adviser review.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    } else {
      setState(() => _submitting = true);
      final app = context.read<AppState>();
      final error = await app.addEvent(
        title: title,
        categoryId: _selectedCategoryId,
        estimatedCost: budgetValue,
        eventDate: _pickedDate,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        venue: venue,
        attendees: attendees,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title submitted for review.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<AppState>().categories;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 16),
              Text(
                _isEditing ? 'Edit Event Proposal' : 'New Event Proposal',
                style: const TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 22,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isEditing ? 'Update the details of this proposal.' : 'Submit a new activity for adviser review.',
                style: AppText.caption,
              ),
              const SizedBox(height: 22),
              const _FieldLabel('Event Name'),
              const SizedBox(height: 6),
              _buildTextField(controller: _nameController, hint: 'e.g. Leadership Summit 2026'),
              const SizedBox(height: 14),
              if (!_isEditing) ...[
                const _FieldLabel('Category'),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border, width: 1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedCategoryId,
                      hint: const Text('Select a category', style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 13, color: AppColors.inkFaint)),
                      items: [
                        for (final c in categories)
                          DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontFamily: AppText.bodyFamily, fontSize: 13))),
                      ],
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (!_isEditing && context.watch<AppState>().mustChooseScope) ...[
                ScopePicker(
                  departments: context.watch<AppState>().departments,
                  departmentId: _departmentId,
                  onDepartmentChanged: (id) => setState(() {
                    _departmentId = id;
                    _organizationId = null;
                  }),
                  organizations:
                      context.watch<AppState>().organizationsIn(_departmentId),
                  organizationId: _organizationId,
                  onOrganizationChanged: (id) =>
                      setState(() => _organizationId = id),
                  explanation: 'Your account is not tied to a department, so '
                      'choose where this event belongs.',
                ),
                const SizedBox(height: 14),
              ],
              // Required: these are what make the event reportable by year,
              // semester and department, and the backend rejects a new
              // event without them.
              const _FieldLabel('School Year'),
              const SizedBox(height: 6),
              _PickerField<String>(
                value: _schoolYear,
                hint: 'Select a school year',
                options: [
                  for (final year in _schoolYearOptions)
                    DropdownMenuItem(value: year, child: Text(year, style: _optionStyle)),
                ],
                onChanged: (v) => setState(() => _schoolYear = v),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Semester'),
              const SizedBox(height: 6),
              _PickerField<Semester>(
                value: _semester,
                hint: 'Select a semester',
                options: [
                  for (final s in Semester.values)
                    DropdownMenuItem(value: s, child: Text(s.label, style: _optionStyle)),
                ],
                onChanged: (v) => setState(() => _semester = v),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Event Scope'),
              const SizedBox(height: 6),
              _PickerField<EventScope>(
                value: _eventScope,
                hint: 'Departmental or organizational',
                options: [
                  for (final scope in EventScope.values)
                    DropdownMenuItem(value: scope, child: Text(scope.label, style: _optionStyle)),
                ],
                onChanged: (v) => setState(() => _eventScope = v),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Date'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDate,
                child: AbsorbPointer(
                  child: _buildTextField(
                    controller: _dateController,
                    hint: 'Tap to select a date',
                    suffix: const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.inkMuted),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Venue'),
              const SizedBox(height: 6),
              _buildTextField(controller: _venueController, hint: 'e.g. CITE Auditorium'),
              const SizedBox(height: 14),
              const _FieldLabel('Expected Attendees'),
              const SizedBox(height: 6),
              _buildTextField(controller: _attendeesController, hint: 'e.g. 120', keyboardType: TextInputType.number),
              const SizedBox(height: 14),
              const _FieldLabel('Requested Budget'),
              const SizedBox(height: 6),
              _buildTextField(controller: _budgetController, hint: '0.00', keyboardType: TextInputType.number),
              const SizedBox(height: 14),
              const _FieldLabel('Description'),
              const SizedBox(height: 6),
              _buildTextField(controller: _descriptionController, hint: 'Briefly describe the event...', maxLines: 3),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: _submitting
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : Text(_isEditing ? 'Save Changes' : 'Submit for Review'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    Widget? suffix,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontFamily: AppText.bodyFamily, fontSize: 13, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontFamily: AppText.bodyFamily, fontSize: 13, color: AppColors.inkFaint),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

const TextStyle _optionStyle =
    TextStyle(fontFamily: AppText.bodyFamily, fontSize: 13);

/// A dropdown styled like the screen's other inputs.
class _PickerField<T> extends StatelessWidget {
  const _PickerField({
    required this.value,
    required this.hint,
    required this.options,
    required this.onChanged,
  });

  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(
              fontFamily: AppText.bodyFamily,
              fontSize: 13,
              color: AppColors.inkFaint,
            ),
          ),
          items: options,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppText.caption);
  }
}