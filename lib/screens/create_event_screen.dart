import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

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

  bool get _isEditing => widget.existingEvent != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existingEvent;
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
        _dateController.text = '${months[picked.month - 1]} ${picked.day}, ${picked.year}';
      });
    }
  }

  void _submit() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an event name.')),
      );
      return;
    }

    final title = _nameController.text.trim();
    final date = _dateController.text.trim().isEmpty ? 'TBD' : _dateController.text.trim();
    final venue = _venueController.text.trim().isEmpty ? 'TBD' : _venueController.text.trim();
    final budget = _budgetController.text.trim().isEmpty ? '₱0.00' : '₱${_budgetController.text.trim()}';
    final attendees = _attendeesController.text.trim().isEmpty
        ? 'TBD'
        : '${_attendeesController.text.trim()} (expected)';

    if (_isEditing) {
      final e = widget.existingEvent!;
      e.title = title;
      e.date = date;
      e.venue = venue;
      e.budget = budget;
      e.attendees = attendees;
      context.read<AppState>().updateEvent();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title updated.')),
      );
    } else {
      final event = EventItem(
        title: title,
        org: 'CITE Student Council',
        date: date,
        venue: venue,
        budget: budget,
        attendees: attendees,
        approvalStep: 0,
      );
      context.read<AppState>().addEvent(event);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title submitted for review.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: Text(_isEditing ? 'Save Changes' : 'Submit for Review'),
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

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppText.caption);
  }
}