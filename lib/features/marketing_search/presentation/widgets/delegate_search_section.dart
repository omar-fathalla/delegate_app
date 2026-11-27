import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:delegate_app/core/design/tokens.dart';

/// قسم البحث عن المندوبين بالاسم ورقم الموبايل (TAS-392: theme text fields
/// and one FilledButton).
class DelegateSearchSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final VoidCallback onSearch;

  const DelegateSearchSection({
    super.key,
    required this.nameController,
    required this.phoneController,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: nameController,
          builder: (context, _) => Semantics(
            // TAS-393: stable id for Maestro (Android EditText bounds are
            // taller than the visible field, so text taps miss it).
            identifier: 'delegate_search_name',
            child: TextField(
              key: const Key('delegate_search_name'),
              controller: nameController,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'اسم المندوب',
                hintText: 'مثال: أحمد محمد',
                prefixIcon: const Icon(Icons.badge_rounded),
                suffixIcon: nameController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        tooltip: 'مسح',
                        onPressed: nameController.clear,
                      )
                    : null,
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
        ),
        const SizedBox(height: TashilSpacing.md),
        ListenableBuilder(
          listenable: phoneController,
          builder: (context, _) => Semantics(
            // TAS-393: stable id for Maestro (Android EditText bounds are
            // taller than the visible field, so text taps miss it).
            identifier: 'delegate_search_phone',
            child: TextField(
              key: const Key('delegate_search_phone'),
              controller: phoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
              ],
              decoration: InputDecoration(
                labelText: 'رقم الموبايل',
                hintText: 'اختياري',
                prefixIcon: const Icon(Icons.phone_android_rounded),
                suffixIcon: phoneController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        tooltip: 'مسح',
                        onPressed: phoneController.clear,
                      )
                    : null,
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
        ),
        const SizedBox(height: TashilSpacing.lg),
        FilledButton.icon(
          key: const Key('delegate_search_button'),
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
          label: const Text('بحث عن المندوب'),
        ),
      ],
    );
  }
}
