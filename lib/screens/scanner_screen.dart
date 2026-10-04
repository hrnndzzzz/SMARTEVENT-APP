import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/scope_picker.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

/// Capture a receipt, read it, correct it, then save it.
///
/// The order matters and is the contract's, not a preference. Scanning
/// uploads the image and returns what OCR made of it — it creates nothing.
/// No expense exists until Save is pressed, and everything OCR returned is
/// editable first, because a receipt read is a suggestion rather than a
/// record.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final ImagePicker _picker = ImagePicker();

  File? _capturedImage;
  Uint8List? _capturedBytes;
  String? _capturedFilename;

  /// Set once a scan succeeds. Holds the stored image URL, so the photo
  /// survives even if the form is abandoned.
  ScannedReceipt? _scan;

  bool _scanning = false;
  bool _saving = false;
  String? _error;

  /// True when OCR was unavailable and the user is filling this in by hand.
  bool _manualEntry = false;

  String? _categoryId;
  String? _eventId;
  DateTime? _expenseDate;

  /// Only used by accounts without their own scope — in practice a Super
  /// Admin, which belongs to no department.
  String? _departmentId;
  String? _organizationId;

  final _vendorController = TextEditingController();
  final _totalController = TextEditingController();
  final _purposeController = TextEditingController();

  /// Reviewed line items. Starts from the scan and is editable.
  List<_EditableLine> _lines = [];

  /// The backend accepts JPEG/JPG, PNG, WebP and HEIC up to 10 MB. The
  /// accepted types come from `receiptImageTypes` rather than a second list
  /// here, so this and what gets sent cannot drift apart.
  static const int _maxBytes = 10 * 1024 * 1024;

  @override
  void dispose() {
    _vendorController.dispose();
    _totalController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  bool get _hasImage => _capturedBytes != null;

  /// Ready to save: an image that scanned (or was entered manually), a
  /// category, a description and an amount.
  bool get _canSave =>
      (_scan != null || _manualEntry) && _categoryId != null && !_saving;

  Future<void> _pick(ImageSource source) async {
    final XFile? photo = await _picker.pickImage(source: source);
    if (photo == null) return;

    final bytes = await photo.readAsBytes();

    // The backend matches on the multipart part's content type, which is
    // derived from this extension — so an unmappable one has to stop here.
    if (receiptContentTypeFor(photo.name) == null) {
      final extension = photo.name.contains('.')
          ? '.${photo.name.split('.').last.toLowerCase()}'
          : 'that file';
      setState(
        () => _error =
            'Receipts must be JPEG, PNG, WebP or HEIC — $extension is not supported.',
      );
      return;
    }
    if (bytes.length > _maxBytes) {
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      setState(() => _error = 'That image is ${mb}MB. The limit is 10MB.');
      return;
    }

    setState(() {
      _capturedImage = File(photo.path);
      _capturedBytes = bytes;
      _capturedFilename = photo.name;
      _scan = null;
      _manualEntry = false;
      _error = null;
    });

    await _runScan();
  }

  Future<void> _runScan() async {
    if (_capturedBytes == null) return;

    setState(() {
      _scanning = true;
      _error = null;
    });

    final outcome = await context.read<AppState>().scanReceipt(
      bytes: _capturedBytes!,
      filename: _capturedFilename ?? 'receipt.jpg',
    );

    if (!mounted) return;

    final scan = outcome.scan;
    if (scan == null) {
      // OCR or storage is unavailable. The photo is still in hand, so
      // offer to enter the details by hand rather than losing the capture.
      setState(() {
        _scanning = false;
        _error = outcome.error;
      });
      return;
    }

    setState(() {
      _scanning = false;
      _scan = scan;
      // Prefilled from the reading, all of it editable.
      _vendorController.text = scan.merchant ?? '';
      _totalController.text = scan.amount == null
          ? ''
          : MoneyInput.fromDouble(scan.amount!);
      _expenseDate = scan.date;
      _lines = [
        for (final item in scan.items)
          _EditableLine(
            name: item.name,
            amount: MoneyInput.fromDouble(item.amount),
            category: item.category ?? ItemCategory.consumable,
          ),
      ];
    });
  }

  void _startManualEntry() {
    setState(() {
      _manualEntry = true;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) setState(() => _expenseDate = picked);
  }

  String? _validate() {
    if (_categoryId == null) return 'Choose a category.';
    if (context.read<AppState>().mustChooseScope) {
      // Your account has no department of its own, so the backend cannot
      // infer one — it refuses the create rather than guessing.
      if (_departmentId == null) return 'Choose a department for this expense.';
      if (_organizationId == null) return 'Choose an organization.';
    }
    if (_vendorController.text.trim().isEmpty) {
      return 'Enter what this expense was for.';
    }

    final amountProblem = MoneyInput.validate(_totalController.text);
    if (amountProblem != null) return amountProblem;

    final total = double.parse(_totalController.text.trim());
    var lineSum = 0.0;
    for (final line in _lines) {
      final problem = MoneyInput.validate(line.amount);
      if (problem != null) return 'Line “${line.name}”: $problem';
      if (line.name.trim().isEmpty) return 'Every line needs a name.';
      lineSum += double.parse(line.amount.trim());
    }
    // The backend enforces this too; catching it here explains which way
    // round the problem is.
    if (lineSum - total > 0.001) {
      return 'The line items add up to ₱${lineSum.toStringAsFixed(2)}, more '
          'than the ₱${total.toStringAsFixed(2)} total.';
    }

    // A receipt's purpose is required and must not be blank.
    if (_scan != null && _purposeController.text.trim().isEmpty) {
      return 'Describe what this receipt was for.';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final amount = MoneyInput.normalize(_totalController.text)!;
    final scan = _scan;

    final error = await context.read<AppState>().createExpense(
      categoryId: _categoryId!,
      eventId: _eventId,
      description: _vendorController.text.trim(),
      amount: amount,
      expenseDate: _expenseDate,
      receipt: scan == null
          ? null
          : ReceiptDetailsInput(
              receiptUrl: scan.receiptUrl,
              purpose: _purposeController.text.trim(),
              merchant: scan.merchant,
              issuedOn: scan.date,
              amount: amount,
            ),
      items: [
        for (final line in _lines)
          ExpenseLineInput(
            name: line.name.trim(),
            amount: MoneyInput.normalize(line.amount)!,
            category: line.category,
          ),
      ],
      departmentId: _departmentId,
      organizationId: _organizationId,
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Expense saved: ${_vendorController.text.trim()}'),
        ),
      );
      _reset();
    }
  }

  void _reset() {
    setState(() {
      _capturedImage = null;
      _capturedBytes = null;
      _capturedFilename = null;
      _scan = null;
      _manualEntry = false;
      _lines = [];
      _expenseDate = null;
      _eventId = null;
      _vendorController.clear();
      _totalController.clear();
      _purposeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final showForm = _scan != null || _manualEntry;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Scan receipt', style: AppText.screenTitle),
              const SizedBox(height: 4),
              const Text(
                'Nothing is saved until you press Save.',
                style: AppText.caption,
              ),
              const SizedBox(height: 14),

              _CapturePreview(
                image: _capturedImage,
                busy: _scanning,
                onCamera: () => _pick(ImageSource.camera),
                onGallery: () => _pick(ImageSource.gallery),
              ),

              if (_scanning) ...[
                const SizedBox(height: 14),
                const _Busy(label: 'Reading the receipt…'),
              ],

              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorCard(
                  message: _error!,
                  // Losing the photo to a failed read would be the worst
                  // outcome, so both recoveries stay available.
                  onRetry: _hasImage && !_scanning ? _runScan : null,
                  onManual: _hasImage && !showForm ? _startManualEntry : null,
                ),
              ],

              if (showForm) ...[
                const SizedBox(height: 14),
                // Only an account without its own scope sees this; everyone
                // else has theirs applied server-side.
                if (app.mustChooseScope) ...[
                  ScopePicker(
                    departments: app.departments,
                    departmentId: _departmentId,
                    onDepartmentChanged: (id) => setState(() {
                      _departmentId = id;
                      // An organization only exists inside one department,
                      // so a department change invalidates the choice.
                      _organizationId = null;
                    }),
                    organizations: app.organizationsIn(_departmentId),
                    organizationId: _organizationId,
                    onOrganizationChanged: (id) =>
                        setState(() => _organizationId = id),
                  ),
                  const SizedBox(height: 14),
                ],
                _ReviewCard(
                  scan: _scan,
                  categories: app.categories,
                  categoryId: _categoryId,
                  onCategoryChanged: (id) => setState(() => _categoryId = id),
                  events: app.events,
                  eventId: _eventId,
                  onEventChanged: (id) => setState(() => _eventId = id),
                  vendorController: _vendorController,
                  totalController: _totalController,
                  purposeController: _purposeController,
                  expenseDate: _expenseDate,
                  onDateTap: _pickDate,
                  requiresPurpose: _scan != null,
                ),
                const SizedBox(height: 14),
                _LinesEditor(
                  lines: _lines,
                  onChanged: (lines) => setState(() => _lines = lines),
                ),
                const SizedBox(height: 20),
                BrutButton(
                  label: 'Save expense',
                  size: BrutSize.large,
                  busy: _saving,
                  busyLabel: 'Saving…',
                  onPressed: _canSave ? _save : null,
                ),
                const SizedBox(height: 10),
                BrutButton(
                  label: 'Discard',
                  tone: BrutTone.neutral,
                  onPressed: _saving ? null : _reset,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One editable line item before it is saved.
class _EditableLine {
  _EditableLine({
    required this.name,
    required this.amount,
    required this.category,
  });

  String name;
  String amount;
  ItemCategory category;
}

class _CapturePreview extends StatelessWidget {
  const _CapturePreview({
    required this.image,
    required this.busy,
    required this.onCamera,
    required this.onGallery,
  });

  final File? image;
  final bool busy;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: AppRadius.cardAll,
            border: context.borderAll,
            boxShadow: context.shadows(AppShadows.base),
          ),
          clipBehavior: Clip.antiAlias,
          child: image == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 40,
                        color: context.palette.muted,
                      ),
                      SizedBox(height: 10),
                      Text('No receipt captured yet', style: AppText.caption),
                    ],
                  ),
                )
              : Image.file(image!, fit: BoxFit.cover, width: double.infinity),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: BrutButton(
                label: 'Camera',
                icon: Icons.photo_camera_outlined,
                tone: BrutTone.neutral,
                onPressed: busy ? null : onCamera,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BrutButton(
                label: 'Gallery',
                icon: Icons.photo_library_outlined,
                tone: BrutTone.neutral,
                onPressed: busy ? null : onGallery,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, this.onRetry, this.onManual});

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: BrutTone.coral,
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrutInlineMessage(text: message, tone: BrutTone.coral),
          if (onRetry != null || onManual != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onRetry != null)
                  Expanded(
                    child: BrutButton(
                      label: 'Try again',
                      icon: Icons.refresh,
                      size: BrutSize.small,
                      tone: BrutTone.neutral,
                      onPressed: onRetry,
                    ),
                  ),
                if (onRetry != null && onManual != null)
                  const SizedBox(width: 8),
                if (onManual != null)
                  Expanded(
                    child: BrutButton(
                      label: 'Enter manually',
                      icon: Icons.edit_outlined,
                      size: BrutSize.small,
                      tone: BrutTone.neutral,
                      onPressed: onManual,
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

/// The reviewable fields. Everything OCR read is shown as a starting point,
/// never as a settled value.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.scan,
    required this.categories,
    required this.categoryId,
    required this.onCategoryChanged,
    required this.events,
    required this.eventId,
    required this.onEventChanged,
    required this.vendorController,
    required this.totalController,
    required this.purposeController,
    required this.expenseDate,
    required this.onDateTap,
    required this.requiresPurpose,
  });

  final ScannedReceipt? scan;
  final List<Category> categories;
  final String? categoryId;
  final ValueChanged<String?> onCategoryChanged;
  final List<EventItem> events;
  final String? eventId;
  final ValueChanged<String?> onEventChanged;
  final TextEditingController vendorController;
  final TextEditingController totalController;
  final TextEditingController purposeController;
  final DateTime? expenseDate;
  final VoidCallback onDateTap;
  final bool requiresPurpose;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrutSectionTitle(
            scan == null ? 'Expense details' : 'Check what we read',
          ),
          if (scan != null) ...[
            const SizedBox(height: 4),
            const Text(
              'These came from the receipt image. Correct anything that is '
              'wrong.',
              style: AppText.caption,
            ),
          ],
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Description',
            controller: vendorController,
            hint: 'What was bought',
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Total amount',
            controller: totalController,
            prefixIcon: Icons.payments_outlined,
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 14),
          BrutDateField(
            label: 'Date',
            value: expenseDate,
            hint: 'Select a date',
            onTap: onDateTap,
          ),
          const SizedBox(height: 14),
          BrutDropdown<String>(
            label: 'Category',
            value: categoryId,
            hint: 'Select a category',
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: onCategoryChanged,
          ),
          const SizedBox(height: 14),
          BrutDropdown<String>(
            label: 'Event',
            value: eventId,
            hint: 'No event',
            items: [
              for (final e in events.where((e) => e.remoteId != null))
                DropdownMenuItem(value: e.remoteId, child: Text(e.title)),
            ],
            onChanged: onEventChanged,
          ),
          const SizedBox(height: 4),
          const Text(
            'Optional in general, but required for anything that becomes '
            'stock.',
            style: AppText.caption,
          ),
          if (requiresPurpose) ...[
            const SizedBox(height: 14),
            BrutTextField(
              label: 'Receipt purpose',
              controller: purposeController,
              hint: 'e.g. Catering for the leadership summit',
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 4),
            const Text(
              'Required whenever a receipt is attached.',
              style: AppText.caption,
            ),
          ],
        ],
      ),
    );
  }
}

/// Line items, editable before saving.
///
/// Classification decides whether something can ever become stock, so it is
/// a visible choice rather than something inherited silently from OCR.
class _LinesEditor extends StatelessWidget {
  const _LinesEditor({required this.lines, required this.onChanged});

  final List<_EditableLine> lines;
  final ValueChanged<List<_EditableLine>> onChanged;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrutSectionTitle(
            'Line items',
            aside: BrutButton(
              label: 'Add',
              icon: Icons.add,
              size: BrutSize.small,
              expand: false,
              tone: BrutTone.neutral,
              onPressed: () => onChanged([
                ...lines,
                _EditableLine(
                  name: '',
                  amount: '',
                  category: ItemCategory.consumable,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          if (lines.isEmpty)
            const Text(
              'Optional. Add lines if you want this expense itemized — only '
              'asset lines can later become stock.',
              style: AppText.caption,
            ),
          for (var i = 0; i < lines.length; i++) ...[
            const Divider(height: 18),
            _LineEditorRow(
              line: lines[i],
              onChanged: (updated) {
                final next = [...lines];
                next[i] = updated;
                onChanged(next);
              },
              onRemove: () {
                final next = [...lines]..removeAt(i);
                onChanged(next);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _LineEditorRow extends StatelessWidget {
  const _LineEditorRow({
    required this.line,
    required this.onChanged,
    required this.onRemove,
  });

  final _EditableLine line;
  final ValueChanged<_EditableLine> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: line.name,
                decoration: const InputDecoration(labelText: 'Item'),
                onChanged: (v) => onChanged(
                  _EditableLine(
                    name: v,
                    amount: line.amount,
                    category: line.category,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: TextFormField(
                initialValue: line.amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount'),
                onChanged: (v) => onChanged(
                  _EditableLine(
                    name: line.name,
                    amount: v,
                    category: line.category,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in ItemCategory.values)
              BrutChip(
                label: category.label,
                selected: line.category == category,
                onTap: () => onChanged(
                  _EditableLine(
                    name: line.name,
                    amount: line.amount,
                    category: category,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Department and organization pickers.
///
