import 'package:material_ui/material_ui.dart';

import 'package:delegate_app/core/design/tokens.dart';

/// قسم البحث عن الشركات (TAS-392: theme text field + one FilledButton).
/// Company search section widget.
class CompanySearchSection extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSearch;

  const CompanySearchSection({
    super.key,
    required this.controller,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => TextField(
            key: const Key('company_search_code'),
            controller: controller,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr, // Codes are LTR.
            decoration: InputDecoration(
              labelText: 'كود الشركة',
              hintText: 'مثال: 4818',
              prefixIcon: const Icon(Icons.business_rounded),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      tooltip: 'مسح',
                      onPressed: controller.clear,
                    )
                  : null,
            ),
            onSubmitted: (_) => onSearch(),
          ),
        ),
        const SizedBox(height: TashilSpacing.lg),
        FilledButton.icon(
          key: const Key('company_search_button'),
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
          label: const Text('بحث عن الشركة'),
        ),
      ],
    );
  }
}
