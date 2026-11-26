import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/text_fields.dart';

/// Text field examples from Tashil's "new item" form: required fields
/// with the asterisk note, a counter, live barcode validation with valid
/// and error icons, clear icon, prefix and suffix text, multi-line notes,
/// a text area, a read-only field, and an opt-in dense layout.
class TextFieldsDemo extends StatefulWidget {
  const TextFieldsDemo({super.key});

  @override
  State<TextFieldsDemo> createState() => _TextFieldsDemoState();
}

class _TextFieldsDemoState extends State<TextFieldsDemo> {
  final _name = TextEditingController(text: 'سكر أبيض 1 كجم');
  final _barcode = TextEditingController(text: '622123');
  final _invoice = TextEditingController(text: 'INV-2026-00431');
  bool _dense = false;

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _invoice.dispose();
    super.dispose();
  }

  String? get _barcodeError {
    final b = _barcode.text;
    if (b.isEmpty || b.length == 13) return null;
    return 'الباركود 13 رقم، انت كاتب ${b.length}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final form = FormColumn(
      children: [
        TashilTextField(
          label: 'اسم الصنف',
          controller: _name,
          isRequired: true,
          leadingIcon: Icons.inventory_2_outlined,
          clearable: true,
          maxLength: 40,
          supportingText: 'زي ما هيتطبع على الفاتورة',
        ),
        TashilTextField(
          label: 'الباركود',
          controller: _barcode,
          isRequired: true,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          supportingText: 'امسحه بالكاميرا أو اكتبه',
          errorText: _barcodeError,
          valid: _barcode.text.length == 13,
          onChanged: (_) => setState(() {}),
          trailing: IconButton(
            tooltip: 'مسح الباركود بالكاميرا',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => setState(() => _barcode.text = '6221234567890'),
          ),
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TashilTextField(
                label: 'سعر البيع',
                isRequired: true,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                suffixText: 'ج.م',
              ),
            ),
            SizedBox(width: TashilSpacing.md),
            Expanded(
              child: TashilTextField(
                label: 'الوزن',
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                suffixText: 'كجم',
              ),
            ),
          ],
        ),
        const TashilTextField(
          label: 'موبايل المورد',
          prefixText: '+20 ',
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          leadingIcon: Icons.phone_outlined,
        ),
        const TashilTextField(
          label: 'ملاحظات',
          lines: TextFieldLines.multi,
          supportingText: 'بيكبر مع الكتابة لحد 4 سطور',
        ),
        const TashilTextField(
          label: 'سبب المرتجع',
          lines: TextFieldLines.area,
          maxLength: 200,
        ),
        TashilTextField(
          label: 'رقم الفاتورة',
          controller: _invoice,
          readOnly: true,
          textDirection: TextDirection.ltr,
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('عرض مضغوط'),
          subtitle: const Text('اختيار المستخدم، مش الافتراضي'),
          value: _dense,
          onChanged: (v) => setState(() => _dense = v),
        ),
        const RequiredFieldsNote(),
        if (_dense)
          Theme(
            data: theme.copyWith(
              visualDensity: VisualDensity.compact,
              inputDecorationTheme: theme.inputDecorationTheme.copyWith(
                isDense: true,
              ),
            ),
            child: form,
          )
        else
          form,
      ],
    );
  }
}
