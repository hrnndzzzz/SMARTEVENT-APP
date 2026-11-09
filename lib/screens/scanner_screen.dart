import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'categories_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/brut_date_picker.dart';
import '../widgets/event_picker_items.dart';
import 'capture_screen.dart';
import 'receipts_screen.dart';
import '../theme/peso.dart';

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

  Uint8List? _capturedBytes;
  String? _capturedFilename;

  /// Set once a scan succeeds. Holds the stored image URL, so the photo
  /// survives even if the form is abandoned.
  ScannedReceipt? _scan;

  bool _scanning = false;
  bool _saving = false;
  String? _error;

  /// True when the user skipped the scan, or OCR was unavailable, and is
  /// filling this in by hand. A photo already taken goes along as proof.
  bool _manualEntry = false;

  String? _categoryId;
  String? _eventId;
  DateTime? _expenseDate;

  final _merchantController = TextEditingController();
  final _vendorController = TextEditingController();
  final _totalController = TextEditingController();
  final _purposeController = TextEditingController();

  /// The OR or reference number printed on the paper.
  ///
  /// The backend hashes merchant + this into reference_key, which is
  /// one of the three keys that refuse an exact duplicate outright.
  /// Nothing ever filled it, so that key was always null and the same
  /// receipt photographed twice got through as merely "similar".
  final _referenceController = TextEditingController();

  /// Why there is no scanned receipt. Required for a manual entry, and
  /// shown to whoever reviews it.
  final _reasonController = TextEditingController();

  /// Reviewed line items. Starts from the scan and is editable.
  List<_EditableLine> _lines = [];

  /// The backend accepts JPEG/JPG, PNG, WebP and HEIC up to 10 MB. The
  /// accepted types come from `receiptImageTypes` rather than a second list
  /// here, so this and what gets sent cannot drift apart.
  static const int _maxBytes = 10 * 1024 * 1024;

  /// Guards the one automatic open, so backing out of the camera leaves
  /// you here rather than bouncing straight back into it.
  bool _offeredCamera = false;

  @override
  void initState() {
    super.initState();
    // Scanning starts with a photo, so the camera is the screen rather
    // than something to go and find once you have arrived.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_offeredCamera) {
        _offeredCamera = true;
        _shoot();
      }
    });
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _vendorController.dispose();
    _totalController.dispose();
    _purposeController.dispose();
    _referenceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  bool get _hasImage => _capturedBytes != null;

  /// Ready to save: an image that scanned (or was entered manually), a
  /// category, a description and an amount.
  bool get _canSave =>
      (_scan != null || _manualEntry) && _categoryId != null && !_saving;

  /// The in-app camera, which crops to the frame before anything is
  /// uploaded.
  ///
  /// It is also where the gallery lives now: offering both on this screen
  /// put a choice in front of someone who had already decided to scan a
  /// receipt. The camera opens, and an older photo is one tap inside it.
  Future<void> _shoot() async {
    final result = await Navigator.of(context).push<CaptureResult>(
      MaterialPageRoute(builder: (_) => const CaptureScreen()),
    );
    if (!mounted) return;
    switch (result) {
      case CapturedReceipt(:final bytes, :final filename):
        await _accept(bytes, filename);
      case GalleryRequested():
        await _pick(ImageSource.gallery);
      case null:
        break;
    }
  }

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

    _accept(bytes, photo.name);
  }

  /// One way in for both routes: check it, hold it, then read it.
  Future<void> _accept(Uint8List bytes, String filename) async {
    if (bytes.length > _maxBytes) {
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      setState(() => _error = 'That image is ${mb}MB. The limit is 10MB.');
      return;
    }
    setState(() {
      _capturedBytes = bytes;
      _capturedFilename = filename;
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
      _merchantController.text = scan.merchant ?? '';
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
    final picked = await BrutDatePicker.show(
      context,
      initial: _expenseDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      title: 'When was this spent?',
    );
    if (picked != null) setState(() => _expenseDate = picked);
  }

  String? _validate() {
    if (_categoryId == null) return 'Choose a category.';
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
      return 'The line items add up to ${peso(lineSum)}, more '
          'than the ${peso(total)} total.';
    }

    // A receipt's purpose is required and must not be blank.
    if (_scan != null && _purposeController.text.trim().isEmpty) {
      return 'Describe what this receipt was for.';
    }
    if (_scan == null && _reasonController.text.trim().length < 5) {
      return 'Say why there is no scanned receipt, so the reviewer knows.';
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
    final merchant = _merchantController.text.trim();
    final photo = _capturedBytes;

    final result = await context.read<AppState>().createExpense(
      categoryId: _categoryId!,
      eventId: _eventId,
      description: _vendorController.text.trim(),
      amount: amount,
      expenseDate: _expenseDate,
      merchant: merchant.isEmpty ? null : merchant,
      manualEntryReason: scan == null ? _reasonController.text.trim() : null,
      // The photo that could not be read is still proof of something.
      proof: scan == null && photo != null
          ? (bytes: photo, filename: _capturedFilename ?? 'proof.jpg')
          : null,
      receipt: scan == null
          ? null
          : ReceiptDetailsInput(
              receiptUrl: scan.receiptUrl,
              purpose: _purposeController.text.trim(),
              receiptNumber: _referenceController.text.trim().isEmpty
                  ? null
                  : _referenceController.text.trim(),
              merchant: merchant.isEmpty ? null : merchant,
              issuedOn: _expenseDate ?? scan.date,
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
      // Deliberately not sent. POST /expenses falls back to the
      // category's department and organization and then rejects anything
      // that differs, so the only values that can succeed are the ones
      // the category already carries. Asking for them gave a Super Admin
      // — who has no organization of their own — a required field whose
      // every wrong answer was a 400.
      departmentId: null,
      organizationId: null,
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = result.error;
    });

    if (result.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.warning ?? 'Expense saved: ${_vendorController.text.trim()}',
          ),
        ),
      );
      _reset();
    }
  }

  void _reset() {
    setState(() {
      _capturedBytes = null;
      _capturedFilename = null;
      _scan = null;
      _manualEntry = false;
      _lines = [];
      _expenseDate = null;
      _eventId = null;
      _merchantController.clear();
      _reasonController.clear();
      _vendorController.clear();
      _totalController.clear();
      _purposeController.clear();
      _referenceController.clear();
    });
  }

  String _duplicateWarning(List<DuplicateExpense> rows) {
    final first = rows.first;
    final when = first.expenseDate == null
        ? ''
        : ' · ${BrutDateField.format(first.expenseDate!)}';
    final status = first.status == 'approved'
        ? 'approved'
        : 'waiting for review';
    final more = rows.length > 1 ? ', and ${rows.length - 1} more' : '';
    return 'This looks like an expense already recorded: '
        '${first.description} · ${peso(first.amount)}$when · $status$more. '
        'Saving it flags it for review.';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final showForm = _scan != null || _manualEntry;

    return BrutScreen(
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      bottomPadding: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text('Scan receipt', style: AppText.display),
              ),
              // "Did I already record this one?" is asked at the counter,
              // before scanning, not afterwards from a different menu.
              // The history was only reachable from Money → Receipts.
              _HistoryButton(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReceiptsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Nothing is saved until you press Save.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),

          _CapturePreview(
            bytes: _capturedBytes,
            busy: _scanning,
            onCamera: _shoot,
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
              // outcome: it can be read again, or go along as proof below.
              onRetry: _hasImage && !_scanning ? _runScan : null,
            ),
          ],

          // The camera or the reader failing must not stop money being
          // recorded, so typing it in is always one tap away.
          if (!showForm && !_scanning) ...[
            const SizedBox(height: 14),
            BrutButton(
              label: 'Skip scan — enter manually',
              icon: Icons.edit_outlined,
              tone: BrutTone.neutral,
              onPressed: _startManualEntry,
            ),
          ],

          if (_scan?.possibleDuplicates case final duplicates?
              when duplicates.isNotEmpty) ...[
            const SizedBox(height: 14),
            BrutInlineMessage(
              tone: BrutTone.coral,
              icon: Icons.content_copy_outlined,
              text: _duplicateWarning(duplicates),
            ),
          ],

          if (_manualEntry) ...[
            const SizedBox(height: 14),
            BrutCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrutSectionTitle('No scanned receipt'),
                  const SizedBox(height: 10),
                  BrutTextField(
                    label: 'Why there is no scanned receipt',
                    controller: _reasonController,
                    hint: 'e.g. The vendor gave a handwritten note',
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hasImage
                        ? 'The photo above goes with it as proof. The '
                              'expense is flagged so the reviewer checks it.'
                        : 'Optional proof: take a photo above. If it cannot '
                              'be read as a receipt, it goes with this '
                              'expense. The expense is flagged so the '
                              'reviewer checks it.',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
          ],

          if (showForm) ...[
            const SizedBox(height: 14),
            _ReviewCard(
              scan: _scan,
              categories: app.categories,
              categoryId: _categoryId,
              onCategoryChanged: (id) => setState(() => _categoryId = id),
              events: app.events,
              eventId: _eventId,
              onEventChanged: (id) => setState(() => _eventId = id),
              merchantController: _merchantController,
              vendorController: _vendorController,
              totalController: _totalController,
              purposeController: _purposeController,
              referenceController: _referenceController,
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
    required this.bytes,
    required this.busy,
    required this.onCamera,
  });

  /// The photo in hand, held as bytes because that is what the in-app
  /// camera returns — it crops the frame and never writes a file. This
  /// used to be a `File`, which only the gallery route could supply, so
  /// a receipt shot with the camera was never shown back at all.
  final Uint8List? bytes;
  final bool busy;
  final VoidCallback onCamera;

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
          child: bytes == null
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
              : Image.memory(
                  bytes!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  // A retake replaces the image; without this the old one
                  // blanks out before the new one paints.
                  gaplessPlayback: true,
                ),
        ),
        const SizedBox(height: 12),
        // One way on. The gallery is inside the camera, a tap away, so
        // the only decision here is whether this photo is the one.
        BrutButton(
          label: bytes == null ? 'Open the camera' : 'Take another',
          icon: Icons.photo_camera_outlined,
          tone: bytes == null ? BrutTone.orange : BrutTone.neutral,
          onPressed: busy ? null : onCamera,
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
        const SizedBox(width: 14, height: 14, child: BrutSpinner(size: 14)),
        const SizedBox(width: 10),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: BrutTone.coral,
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrutInlineMessage(text: message, tone: BrutTone.coral),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            BrutButton(
              label: 'Try again',
              icon: Icons.refresh,
              size: BrutSize.small,
              tone: BrutTone.neutral,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// Picked in the category dropdown to make one rather than choose one.
const String newCategorySentinel = '__new_category__';

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
    required this.merchantController,
    required this.vendorController,
    required this.totalController,
    required this.purposeController,
    required this.referenceController,
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
  final TextEditingController merchantController;
  final TextEditingController vendorController;
  final TextEditingController totalController;
  final TextEditingController purposeController;
  final TextEditingController referenceController;
  final DateTime? expenseDate;
  final VoidCallback onDateTap;
  final bool requiresPurpose;

  @override
  Widget build(BuildContext context) {
    final canAddCategory =
        context.watch<AppState>().currentRole?.canManageCatalog ?? false;
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
            label: 'Merchant',
            controller: merchantController,
            hint: 'Who was paid',
            textCapitalization: TextCapitalization.words,
          ),
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
          // Making a category used to mean leaving this form, and losing
          // whatever had been typed into it. The last item opens the
          // same form the categories screen uses, and the new category
          // is selected when it comes back.
          BrutDropdown<String>(
            label: 'Category',
            value: categoryId,
            hint: 'Select a category',
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
              // Only those who manage categories can make one; anyone
              // else got a form whose save was refused.
              if (canAddCategory)
                const DropdownMenuItem(
                  value: newCategorySentinel,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16),
                      SizedBox(width: 6),
                      Text('New category'),
                    ],
                  ),
                ),
            ],
            onChanged: (value) async {
              if (value != newCategorySentinel) {
                onCategoryChanged(value);
                return;
              }

              final app = context.read<AppState>();
              final before = {for (final c in app.categories) c.id};
              await CategoriesScreen.openForm(context);
              if (!context.mounted) return;

              // Whatever is new is what they just made.
              final made = app.categories
                  .where((c) => !before.contains(c.id))
                  .toList();
              if (made.length == 1) onCategoryChanged(made.single.id);
            },
          ),
          const SizedBox(height: 14),
          BrutDropdown<String>(
            label: 'Event',
            value: eventId,
            hint: 'No event',
            items: eventPickerItems(events, keep: eventId),
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
            const SizedBox(height: 14),
            BrutTextField(
              label: 'Reference or OR number',
              controller: referenceController,
              hint: 'e.g. OR 2026-00417',
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 4),
            const Text(
              'Optional, but it is what lets the same receipt be '
              'refused if it is recorded twice.',
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

/// Opens the receipt history from the scanner.
///
/// Framed as "Recent" rather than "History" because what it answers is
/// "did I already record this one?", which is a question about the last
/// few, not about the archive.
class _HistoryButton extends StatelessWidget {
  const _HistoryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: p.line, width: 2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 16, color: p.ink),
            const SizedBox(width: 6),
            Text(
              'Recent',
              style: AppText.caption.copyWith(
                color: p.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
