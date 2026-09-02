import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// صفحة ومنظومة التحصيلات والفواتير الرسمية المعكوسة على الرصيد المتبقي مع الطباعة والمشاركة
class SuperAdminCollectionsScreen extends StatefulWidget {
  final Delegate delegate;

  const SuperAdminCollectionsScreen({super.key, required this.delegate});

  @override
  State<SuperAdminCollectionsScreen> createState() => _SuperAdminCollectionsScreenState();
}

class _SuperAdminCollectionsScreenState extends State<SuperAdminCollectionsScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();

  bool _isLoading = true;
  String? _errorMessage;

  // Selected Service Period (Month / Year)
  late DateTime _selectedPeriod;

  // Invoice Mode: 'remaining' (Default: صافي الرصيد المتبقي) or 'gross' (الإجمالي الكلي للشهر)
  bool _showRemainingInvoice = true;

  // Configurable Financial Rates (Default values matching official spec)
  double _receiptUnitPrice = 100.0;
  double _adCompanyUnitPrice = 20000.0;
  int _adCompanyCount = 7;
  double _tashilPercentage = 70.0;
  double _marketPercentage = 30.0;

  // Aggregated Billing Data from Delegates
  int _totalDueReceiptsCount = 0;

  // Recorded Collection Transactions for the selected period
  List<Map<String, dynamic>> _collectionTransactions = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedPeriod = DateTime(now.year, now.month, 1);
    _loadSettingsAndData();
  }

  String get _periodKey =>
      '${_selectedPeriod.year}_${_selectedPeriod.month.toString().padLeft(2, '0')}';

  Future<void> _loadSettingsAndData() async {
    await _loadSavedPreferences();
    await _fetchBillingAndCollectionsData();
  }

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _receiptUnitPrice = prefs.getDouble('billing_receipt_unit_price') ?? 100.0;
        _adCompanyUnitPrice = prefs.getDouble('billing_ad_company_unit_price') ?? 20000.0;
        _adCompanyCount = prefs.getInt('billing_ad_company_count') ?? 7;
        _tashilPercentage = prefs.getDouble('billing_tashil_percentage') ?? 70.0;
        _marketPercentage = prefs.getDouble('billing_market_percentage') ?? 30.0;
      });
    } catch (_) {}
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('billing_receipt_unit_price', _receiptUnitPrice);
      await prefs.setDouble('billing_ad_company_unit_price', _adCompanyUnitPrice);
      await prefs.setInt('billing_ad_company_count', _adCompanyCount);
      await prefs.setDouble('billing_tashil_percentage', _tashilPercentage);
      await prefs.setDouble('billing_market_percentage', _marketPercentage);
    } catch (_) {}
  }

  Future<void> _fetchBillingAndCollectionsData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final prefs = await SharedPreferences.getInstance();
    // Cache-First: instant load from persistent cache
    final cachedReceipts = prefs.getInt('cached_due_receipts_${widget.delegate.organizationUID}') ?? 0;
    if (cachedReceipts > 0 && mounted) {
      setState(() {
        _totalDueReceiptsCount = cachedReceipts;
        _isLoading = false;
      });
    }

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Fetch total due electronic receipts across delegates
      int totalElectronicReceipts = _totalDueReceiptsCount;
      try {
        final delegatesSnapshot = await firestore.collectionGroup('delegates').get();

        final filteredDelegates = delegatesSnapshot.docs.where((doc) {
          final pathParts = doc.reference.path.split('/');
          final orgUid = pathParts.length > 1 ? pathParts[1] : '';

          if (widget.delegate.organizationUID.isNotEmpty &&
              orgUid != widget.delegate.organizationUID) {
            return false;
          }
          return true;
        }).toList();

        int count = 0;
        for (var doc in filteredDelegates) {
          final data = doc.data();
          final documentsList = data['documents'] as List? ?? [];

          for (var docItem in documentsList) {
            if (docItem is Map<String, dynamic>) {
              final key = docItem['documentKey']?.toString().toLowerCase() ?? '';
              final url = docItem['documentURL']?.toString() ?? '';

              if ((key == 'electronicpaymentreceipt' ||
                      key == 'electronic_payment_receipt' ||
                      key == 'electronic_receipt' ||
                      key == 'electronicreceipt') &&
                  url.isNotEmpty) {
                count++;
              }
            }
          }
        }
        totalElectronicReceipts = count;
        await prefs.setInt('cached_due_receipts_${widget.delegate.organizationUID}', count);
      } catch (e) {
        debugPrint('Delegates fetch notice: $e');
      }

      // 2. Fetch recorded collection transactions for this specific month
      List<Map<String, dynamic>> transactions = [];
      try {
        final transactionsSnapshot = await firestore
            .collection('monthly_collections')
            .doc(_periodKey)
            .collection('transactions')
            .orderBy('createdAt', descending: true)
            .get();

        transactions = transactionsSnapshot.docs.map((doc) {
          final d = doc.data();
          return {
            'id': doc.id,
            ...d,
          };
        }).toList();
      } catch (e) {
        debugPrint('Transactions fetch notice: $e');
      }

      if (mounted) {
        setState(() {
          _totalDueReceiptsCount = totalElectronicReceipts;
          _collectionTransactions = transactions;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_totalDueReceiptsCount == 0) {
            _errorMessage = 'حدث خطأ أثناء تحميل بيانات التحصيلات: $e';
          }
        });
      }
    }
  }

  // --- Financial Calculations ---
  int get _totalCollectedReceiptsCount {
    int sum = 0;
    for (final t in _collectionTransactions) {
      sum += (t['receiptsCount'] as num? ?? 0).toInt();
    }
    return sum;
  }

  double get _totalCollectedAmount {
    double sum = 0.0;
    for (final t in _collectionTransactions) {
      sum += (t['collectedAmount'] as num? ?? 0.0).toDouble();
    }
    return sum;
  }

  // Gross Total Due (الإجمالي المستحق الكلي)
  double get _dueReceiptsTotalAmount => _totalDueReceiptsCount * _receiptUnitPrice;
  double get _adCompanyTotalAmount => _adCompanyCount * _adCompanyUnitPrice;
  double get _grandTotalDue => _dueReceiptsTotalAmount + _adCompanyTotalAmount;

  // Net Remaining (المتبقي الفعلي بعد الخصم)
  int get _remainingReceiptsCount =>
      (_totalDueReceiptsCount - _totalCollectedReceiptsCount).clamp(0, _totalDueReceiptsCount);

  double get _remainingReceiptsAmount => _remainingReceiptsCount * _receiptUnitPrice;

  double get _remainingBalanceAmount =>
      (_grandTotalDue - _totalCollectedAmount).clamp(0.0, _grandTotalDue);

  // Active Invoice Displayed Values (بناءً على اختيار المتبقي أو الإجمالي)
  int get _invoiceReceiptsQty => _showRemainingInvoice ? _remainingReceiptsCount : _totalDueReceiptsCount;
  double get _invoiceReceiptsTotal => _showRemainingInvoice ? _remainingReceiptsAmount : _dueReceiptsTotalAmount;
  double get _invoiceGrandTotal => _showRemainingInvoice ? _remainingBalanceAmount : _grandTotalDue;

  // Shares of Active Invoice
  double get _invoiceTashilAmount => (_invoiceGrandTotal * _tashilPercentage) / 100.0;
  double get _invoiceMarketAmount => (_invoiceGrandTotal * _marketPercentage) / 100.0;

  // Shares of Total Due
  double get _tashilDueAmount => (_grandTotalDue * _tashilPercentage) / 100.0;
  double get _marketDueAmount => (_grandTotalDue * _marketPercentage) / 100.0;

  // Shares of Collected Amount
  double get _tashilCollectedAmount => (_totalCollectedAmount * _tashilPercentage) / 100.0;
  double get _marketCollectedAmount => (_totalCollectedAmount * _marketPercentage) / 100.0;

  // Shares of Remaining Balance
  double get _tashilRemainingAmount => (_remainingBalanceAmount * _tashilPercentage) / 100.0;
  double get _marketRemainingAmount => (_remainingBalanceAmount * _marketPercentage) / 100.0;

  double get _collectionProgressPercentage =>
      _grandTotalDue > 0 ? ((_totalCollectedAmount / _grandTotalDue) * 100.0).clamp(0.0, 100.0) : 0.0;

  String _formatCurrency(num amount) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '${formatter.format(amount)} ج.م';
  }

  String _formatAmountOnly(num amount) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return formatter.format(amount);
  }

  String _numberToWordsArabic(num number) {
    if (number == 0) return 'صفر جنيه مصري فقط لا غير';
    final formatter = NumberFormat('#,##0', 'ar');
    return 'فقط ${formatter.format(number.toInt())} جنيهاً مصرياً لا غير.';
  }

  String _numberToWordsEnglish(num number) {
    final formatter = NumberFormat('#,##0', 'en_US');
    return '${formatter.format(number.toInt())} Egyptian pounds only.';
  }

  // --- Add New Collection Entry Dialog ---
  void _showAddCollectionDialog() {
    final receiptsCountController = TextEditingController();
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    String selectedPaymentMethod = 'نقداً (Cash)';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_card_rounded, color: Colors.green, size: 22),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'تسجيل تحصيل وخصم',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: Colors.blue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'المتبقي: $_remainingReceiptsCount إيصال (${_formatCurrency(_remainingBalanceAmount)})',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: receiptsCountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'عدد الإيصالات المحصلة (Qty)',
                      hintText: 'مثلاً: 385',
                      prefixIcon: const Icon(Icons.receipt_long_rounded, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) {
                      final count = int.tryParse(val) ?? 0;
                      if (count > 0) {
                        final computedAmount = count * _receiptUnitPrice;
                        amountController.text = computedAmount.toStringAsFixed(0);
                      }
                    },
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'المبلغ المحصل (ج.م)',
                      hintText: 'مثلاً: 38500',
                      prefixIcon: const Icon(Icons.payments_rounded, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  DropdownButtonFormField<String>(
                    initialValue: selectedPaymentMethod,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText: 'طريقة الدفع',
                      prefixIcon: const Icon(Icons.account_balance_wallet_rounded, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'نقداً (Cash)', child: Text('نقداً (Cash)')),
                      DropdownMenuItem(value: 'تحويل بنكي (Bank Transfer)', child: Text('تحويل بنكي')),
                      DropdownMenuItem(value: 'شيك مصرفي (Cheque)', child: Text('شيك مصرفي')),
                      DropdownMenuItem(value: 'إلكتروني (Online / Card)', child: Text('دفع إلكتروني')),
                      DropdownMenuItem(value: 'خصم من المستحقات (Deduction)', child: Text('خصم من المستحقات')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedPaymentMethod = val);
                      }
                    },
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'ملاحظات / رقم الشيك',
                      hintText: 'تفاصيل السداد أو رقم العملية...',
                      prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(fontSize: 12)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final qty = int.tryParse(receiptsCountController.text) ?? 0;
                  final amount = double.tryParse(amountController.text) ?? (qty * _receiptUnitPrice);

                  if (qty <= 0 && amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('يرجى إدخال عدد الإيصالات أو المبلغ المحصل.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  final messenger = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(ctx);

                  try {
                    final firestore = FirebaseFirestore.instance;
                    final docRef = firestore
                        .collection('monthly_collections')
                        .doc(_periodKey)
                        .collection('transactions')
                        .doc();

                    await docRef.set({
                      'id': docRef.id,
                      'receiptsCount': qty,
                      'unitPrice': _receiptUnitPrice,
                      'collectedAmount': amount,
                      'paymentMethod': selectedPaymentMethod,
                      'notes': notesController.text.trim(),
                      'createdAt': FieldValue.serverTimestamp(),
                      'createdBy': widget.delegate.fullName,
                      'periodKey': _periodKey,
                    });

                    if (mounted) {
                      nav.pop();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('تم تسجيل تحصيل $qty إيصال بمبلغ ${_formatCurrency(amount)} بنجاح.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _fetchBillingAndCollectionsData();
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('حدث خطأ أثناء حفظ التحصيل: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('تأكيد الخصم', style: TextStyle(fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteCollectionTransaction(String docId, int qty, double amount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text('تأكيد الحذف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        content: Text(
          'هل تريد حذف دفعة تحصيل $qty إيصال بمبلغ ${_formatCurrency(amount)} وإعادتها للمستحق؟',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('monthly_collections')
            .doc(_periodKey)
            .collection('transactions')
            .doc(docId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف عملية التحصيل وتحديث الأرصدة.'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchBillingAndCollectionsData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ أثناء الحذف: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // --- Print Invoice (طباعة الفاتورة عبر الطابعة أو PDF) ---
  Future<void> _printInvoice() async {
    try {
      final imageBytes = await _screenshotController.capture(
        delay: const Duration(milliseconds: 100),
        pixelRatio: 3.0,
      );

      if (imageBytes == null) return;

      final pdf = pw.Document();
      final image = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );

      final periodStr = DateFormat('yyyy-MM').format(_selectedPeriod);
      final docName = 'Invoice_${_showRemainingInvoice ? 'Remaining' : 'Total'}_$periodStr.pdf';

      await Printing.layoutPdf(
        name: docName,
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء طباعة الفاتورة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- Share Invoice (مشاركة الفاتورة كصورة عبر الواتساب) ---
  Future<void> _shareInvoiceImage() async {
    try {
      final image = await _screenshotController.capture(
        delay: const Duration(milliseconds: 100),
        pixelRatio: 2.5,
      );

      if (image == null) return;

      final directory = await getTemporaryDirectory();
      final periodStr = DateFormat('yyyy-MM').format(_selectedPeriod);
      final fileName = 'Official_Invoice_${_showRemainingInvoice ? 'Remaining' : 'Total'}_$periodStr.png';
      final imagePath = '${directory.path}/$fileName';
      final file = File(imagePath);
      await file.writeAsBytes(image);

      final invoiceNo = '${_selectedPeriod.year}${_selectedPeriod.month}000/46';
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: 'فاتورة التحصيلات الرسمية (${_showRemainingInvoice ? 'الرصيد المتبقي' : 'الإجمالي الكلي'}) - رقم: $invoiceNo للفترة: ${DateFormat('MMMM yyyy', 'ar').format(_selectedPeriod)} بمبلغ ${_formatCurrency(_invoiceGrandTotal)}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء مشاركة الفاتورة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSettingsDialog() {
    final receiptPriceController =
        TextEditingController(text: _receiptUnitPrice.toStringAsFixed(0));
    final adPriceController =
        TextEditingController(text: _adCompanyUnitPrice.toStringAsFixed(0));
    final adCountController =
        TextEditingController(text: _adCompanyCount.toString());
    final tashilPercController =
        TextEditingController(text: _tashilPercentage.toStringAsFixed(0));
    final marketPercController =
        TextEditingController(text: _marketPercentage.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: const Row(
            children: [
              Icon(Icons.tune_rounded, color: Colors.blue, size: 22),
              SizedBox(width: 8),
              Text(
                'إعدادات الأسعار والنسب',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: receiptPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'سعر الإيصال الإلكتروني (ج.م)',
                    prefixIcon: const Icon(Icons.receipt_long_rounded, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: adPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'سعر ترخيص شركة الدعاية (ج.م)',
                    prefixIcon: const Icon(Icons.campaign_rounded, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: adCountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'عدد شركات الدعاية (Qty)',
                    prefixIcon: const Icon(Icons.numbers_rounded, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 6),

                const Text(
                  'توزيع النسب المئوية (%):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tashilPercController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'تسهيل (%)',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (v) {
                          final val = double.tryParse(v) ?? 70.0;
                          if (val <= 100) {
                            marketPercController.text = (100.0 - val).toStringAsFixed(0);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: marketPercController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'فتح الله (%)',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final rPrice = double.tryParse(receiptPriceController.text) ?? 100.0;
                final aPrice = double.tryParse(adPriceController.text) ?? 20000.0;
                final aCount = int.tryParse(adCountController.text) ?? 7;
                final tPerc = double.tryParse(tashilPercController.text) ?? 70.0;
                final mPerc = double.tryParse(marketPercController.text) ?? 30.0;

                setState(() {
                  _receiptUnitPrice = rPrice;
                  _adCompanyUnitPrice = aPrice;
                  _adCompanyCount = aCount;
                  _tashilPercentage = tPerc;
                  _marketPercentage = mPerc;
                });

                _savePreferences();
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickServicePeriod() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedPeriod,
      firstDate: DateTime(2023),
      lastDate: DateTime(now.year + 2),
      helpText: 'اختر شهر وسنة التحصيل',
    );

    if (picked != null) {
      setState(() {
        _selectedPeriod = DateTime(picked.year, picked.month, 1);
      });
      _fetchBillingAndCollectionsData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text(
          'التحصيلات والفواتير',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: 'الإعدادات والنسب',
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded, size: 20),
            tooltip: 'طباعة الفاتورة',
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _printInvoice,
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, size: 20),
            tooltip: 'مشاركة الفاتورة',
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _shareInvoiceImage,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'تحديث البيانات',
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _fetchBillingAndCollectionsData,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCollectionDialog,
        icon: const Icon(Icons.add_card_rounded, size: 20),
        label: const Text('تسجيل تحصيل وخصم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 44),
                    const SizedBox(height: 10),
                    Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: _fetchBillingAndCollectionsData,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchBillingAndCollectionsData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. شريط اختيار الفترة الزمنية
                    _buildPeriodSelectorHeader(colorScheme),

                    const SizedBox(height: 12),

                    // 2. بطاقات النبض المالي المترابطة (المستحق | المحصل | المتبقي)
                    _buildTripleFinancialCards(colorScheme),

                    const SizedBox(height: 16),

                    // 3. الفاتورة الرسمية المعتمدة (مع خيار المتبقي/الإجمالي + الطباعة والمشاركة)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.description_rounded, color: Colors.indigo, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              _showRemainingInvoice ? 'فاتورة الرصيد المتبقي ⏳' : 'الفاتورة الشهرية الإجمالية 📑',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _printInvoice,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.print_rounded, size: 14),
                              label: const Text('طباعة', style: TextStyle(fontSize: 11)),
                            ),
                            const SizedBox(width: 6),
                            FilledButton.tonalIcon(
                              onPressed: _shareInvoiceImage,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.share_rounded, size: 14),
                              label: const Text('مشاركة', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Switcher: Remaining vs Gross Total
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('فاتورة المتبقي للتحصيل (صافي)'),
                          selected: _showRemainingInvoice,
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: _showRemainingInvoice ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (val) {
                            if (val) setState(() => _showRemainingInvoice = true);
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('الفاتورة الإجمالية للشهر'),
                          selected: !_showRemainingInvoice,
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: !_showRemainingInvoice ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (val) {
                            if (val) setState(() => _showRemainingInvoice = false);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Screenshot Wrapper for Invoice Table
                    Screenshot(
                      controller: _screenshotController,
                      child: _buildOfficialInvoiceDocument(colorScheme),
                    ),

                    const SizedBox(height: 20),

                    // 4. سجل عمليات التحصيل المعتمدة
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.history_edu_rounded, color: Colors.teal, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              'سجل دفعات التحصيل والخصم (${_collectionTransactions.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: _showAddCollectionDialog,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('إضافة دفعة', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    if (_collectionTransactions.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.pending_actions_rounded, size: 36, color: Colors.grey.shade400),
                            const SizedBox(height: 6),
                            const Text(
                              'لم يتم تسجيل أي عمليات تحصيل لهذا الشهر.',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'اضغط على زر "تسجيل تحصيل وخصم" بالأسفل لخصم عدد الإيصالات والمبالغ.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _collectionTransactions.length,
                        itemBuilder: (context, index) {
                          final item = _collectionTransactions[index];
                          return _buildTransactionCard(item, colorScheme, index + 1);
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPeriodSelectorHeader(ColorScheme colorScheme) {
    final periodName = DateFormat('MMMM yyyy', 'ar').format(_selectedPeriod);
    final periodCode = DateFormat('MMM-yy', 'en_US').format(_selectedPeriod);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.calendar_month_rounded, color: Colors.blue, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'فترة الخدمة والتحصيل:',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
                Text(
                  '$periodName ($periodCode)',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pickServicePeriod,
            icon: const Icon(Icons.edit_calendar_rounded, size: 14),
            label: const Text('تغيير الشهر', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  /// البطاقات المالية المنسقة والمدمجة (المستحق الكلي | تم تحصيله | المتبقي)
  Widget _buildTripleFinancialCards(ColorScheme colorScheme) {
    return Column(
      children: [
        // 1. الكارت الرئيسي: إجمالي المستحق الكلي
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D47A1).withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إجمالي التحصيل المستحق (Grand Total)',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatCurrency(_grandTotalDue),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_totalDueReceiptsCount إيصال',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'تسهيل (70%): ${_formatCurrency(_tashilDueAmount)}',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'فتح الله (30%): ${_formatCurrency(_marketDueAmount)}',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 2. بطاقتين متجاورتين: (المحصل الفعلي) و (المتبقي للتحصيل)
        Row(
          children: [
            // بطاقة تم تحصيله (Collected)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade800,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.shade800.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'المحصل ✅',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        Text(
                          '$_totalCollectedReceiptsCount إيصال',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 9.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCurrency(_totalCollectedAmount),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'تسهيل: ${_formatAmountOnly(_tashilCollectedAmount)} | فتح الله: ${_formatAmountOnly(_marketCollectedAmount)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 8.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // بطاقة المتبقي للتحصيل (Remaining)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.shade800,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepOrange.shade800.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'المتبقي ⏳',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        Text(
                          '$_remainingReceiptsCount إيصال',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 9.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCurrency(_remainingBalanceAmount),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'تسهيل: ${_formatAmountOnly(_tashilRemainingAmount)} | فتح الله: ${_formatAmountOnly(_marketRemainingAmount)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 8.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // شريط تقدم الإنجاز في التحصيل
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'نسبة إنجاز التحصيل الفعلي للشهر:',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_collectionProgressPercentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _collectionProgressPercentage >= 100
                          ? Colors.green.shade800
                          : Colors.blue.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _collectionProgressPercentage / 100.0,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _collectionProgressPercentage >= 100
                        ? Colors.green.shade700
                        : Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// الفاتورة الرسمية المعتمدة بتصميم منسق ومدمج 100% يعكس الرصيد المتبقي أو الإجمالي
  Widget _buildOfficialInvoiceDocument(ColorScheme colorScheme) {
    final invoiceDateStr = DateFormat('d/M/yyyy').format(_selectedPeriod);
    final servicePeriodStr = DateFormat('MMM-yy', 'en_US').format(_selectedPeriod);
    final invoiceNo = '${_selectedPeriod.year}${_selectedPeriod.month}000/46';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0D47A1), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Information Section
          Table(
            border: TableBorder.all(color: Colors.grey.shade300, width: 0.8),
            columnWidths: const {
              0: FlexColumnWidth(1.15),
              1: FlexColumnWidth(1.0),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Text(
                      'Bill To (الجهة المستلمة)',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1), fontSize: 11),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Text(
                      'Invoice Details (بيانات الفاتورة)',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1), fontSize: 11),
                    ),
                  ),
                ],
              ),
              TableRow(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text('Customer: Fathalla Market', style: TextStyle(fontSize: 10, color: Colors.black87)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text('Invoice No: $invoiceNo', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                ],
              ),
              TableRow(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text('Attn: Mr. Mohamed A. Hassan', style: TextStyle(fontSize: 10, color: Colors.black87)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text('Date: $invoiceDateStr', style: const TextStyle(fontSize: 10, color: Colors.black87)),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text(
                      _showRemainingInvoice ? 'Type: Net Remaining Balance' : 'Company: All Companies',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text('Period: $servicePeriodStr', style: const TextStyle(fontSize: 10, color: Colors.black87)),
                  ),
                ],
              ),
              const TableRow(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text('System: Tashil Business', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text('Payment: Official / Cash', style: TextStyle(fontSize: 10, color: Colors.black87)),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 2. Main Items Table
          Table(
            border: TableBorder.all(color: Colors.grey.shade300, width: 0.8),
            columnWidths: const {
              0: FlexColumnWidth(2.2),
              1: FlexColumnWidth(0.7),
              2: FlexColumnWidth(1.0),
              3: FlexColumnWidth(1.3),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(color: Color(0xFF0D47A1)),
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      'Description',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Text(
                      'Qty',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Text(
                      'Price',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Text(
                      'Total (EGP)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),

              // Item 1: Electronic Receipts (Shows Remaining Qty if _showRemainingInvoice is true)
              TableRow(
                decoration: const BoxDecoration(color: Colors.white),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      _showRemainingInvoice
                          ? 'Issuing official electronic payment receipts\n(إيصالات الدفع الإلكترونية المتبقية للتحصيل)'
                          : 'Issuing official electronic payment receipts\n(إصدار إيصالات الدفع الإلكترونية)',
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Text(
                      NumberFormat('#,##0').format(_invoiceReceiptsQty),
                      style: const TextStyle(fontSize: 10, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Text(
                      _formatAmountOnly(_receiptUnitPrice),
                      style: const TextStyle(fontSize: 10, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Text(
                      _formatAmountOnly(_invoiceReceiptsTotal),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),

              // Item 2: Advertising Company Subscription
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFFAFAFA)),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      'Advertising Company Subscription\n(اشتراك شركات الدعاية)',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Text(
                      '$_adCompanyCount',
                      style: const TextStyle(fontSize: 10, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Text(
                      _formatAmountOnly(_adCompanyUnitPrice),
                      style: const TextStyle(fontSize: 10, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Text(
                      _formatAmountOnly(_adCompanyTotalAmount),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),

              // Grand Total Row
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(''),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Text(''),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Text(
                      _showRemainingInvoice ? 'Net Total' : 'Grand Total',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Color(0xFF0D47A1)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Container(
                    color: const Color(0xFF0D47A1),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Text(
                      _formatAmountOnly(_invoiceGrandTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 10.5),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Written Amount Note
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _numberToWordsEnglish(_invoiceGrandTotal),
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 9.5,
                    color: Color(0xFF1E3A8A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _numberToWordsArabic(_invoiceGrandTotal),
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 9.5,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // 3. Payment Split Table
          Table(
            border: TableBorder.all(color: Colors.grey.shade300, width: 0.8),
            columnWidths: const {
              0: FlexColumnWidth(2.0),
              1: FlexColumnWidth(0.9),
              2: FlexColumnWidth(1.3),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(color: Color(0xFF0D47A1)),
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    child: Text(
                      'Payment Split (توزيع التحصيل)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                    child: Text(
                      'Ratio',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: Text(
                      'Amount (EGP)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              TableRow(
                decoration: const BoxDecoration(color: Colors.white),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    child: Text(
                      'Tashil Delegate Business (تطبيق تسهيل)',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                    child: Text(
                      '${_tashilPercentage.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 9.5, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: Text(
                      _formatAmountOnly(_invoiceTashilAmount),
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black87),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFFAFAFA)),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    child: Text(
                      'Fathalla Market (فتح الله ماركت)',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                    child: Text(
                      '${_marketPercentage.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 9.5, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: Text(
                      _formatAmountOnly(_invoiceMarketAmount),
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black87),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    child: Text(
                      'Total (الإجمالي)',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                    child: Text(
                      '100%',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: Text(
                      _formatAmountOnly(_invoiceGrandTotal),
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(
    Map<String, dynamic> item,
    ColorScheme colorScheme,
    int index,
  ) {
    final docId = item['id']?.toString() ?? '';
    final qty = (item['receiptsCount'] as num? ?? 0).toInt();
    final amount = (item['collectedAmount'] as num? ?? 0.0).toDouble();
    final paymentMethod = item['paymentMethod']?.toString() ?? 'نقداً (Cash)';
    final notes = item['notes']?.toString() ?? '';
    final createdBy = item['createdBy']?.toString() ?? '';
    final createdAt = (item['createdAt'] as Timestamp?)?.toDate();
    final dateStr = createdAt != null ? DateFormat('yyyy-MM-dd  hh:mm a').format(createdAt) : 'غير محدد';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.green.shade50,
                      foregroundColor: Colors.green.shade800,
                      child: Text('$index', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'دفعة تحصيل: $qty إيصال',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          dateStr,
                          style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  _formatCurrency(amount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 6),

            Row(
              children: [
                Chip(
                  label: Text(paymentMethod),
                  avatar: const Icon(Icons.payment_rounded, size: 12),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 10),
                ),
                if (createdBy.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Chip(
                    label: Text(createdBy),
                    avatar: const Icon(Icons.person_outline_rounded, size: 12),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(fontSize: 10),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 18),
                  tooltip: 'حذف عملية التحصيل',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _deleteCollectionTransaction(docId, qty, amount),
                ),
              ],
            ),

            if (notes.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'ملاحظات: $notes',
                style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
