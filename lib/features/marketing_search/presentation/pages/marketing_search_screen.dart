import 'dart:developer' as developer;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../injection_container.dart' as di;
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../bloc/marketing_search_bloc.dart';
import '../bloc/marketing_search_event.dart';
import '../bloc/marketing_search_state.dart';
import '../widgets/company_search_section.dart';
import '../widgets/delegate_search_section.dart';
import '../widgets/search_results_section.dart';

/// صفحة البحث الموحدة للتسويق
/// Unified marketing search screen for companies and delegates
class MarketingSearchScreen extends StatelessWidget {
  final String? organizationUID;

  const MarketingSearchScreen({super.key, this.organizationUID});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<MarketingSearchBloc>(),
      child: _MarketingSearchView(organizationUID: organizationUID),
    );
  }
}

class _MarketingSearchView extends StatefulWidget {
  final String? organizationUID;

  const _MarketingSearchView({required this.organizationUID});

  @override
  State<_MarketingSearchView> createState() => _MarketingSearchViewState();
}

class _MarketingSearchViewState extends State<_MarketingSearchView> {
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _delegateNameController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  String? _actualOrganizationUID;

  @override
  void initState() {
    super.initState();
    _initializeOrganizationUID();
  }

  /// Initialize organization UID from parameter or cached user data
  void _initializeOrganizationUID() {
    if (widget.organizationUID != null) {
      _actualOrganizationUID = widget.organizationUID;
      developer.log(
        '🏢 [Marketing Search] استخدام organizationUID من المعامل: $_actualOrganizationUID',
      );
    } else {
      final authLocalDataSource = di.sl<AuthLocalDataSource>();
      final cachedDelegate = authLocalDataSource.getCachedDelegateData();
      if (cachedDelegate != null) {
        _actualOrganizationUID = cachedDelegate.organizationUID;
        developer.log(
          '🏢 [Marketing Search] استخدام organizationUID من البيانات المحفوظة: $_actualOrganizationUID',
        );
      } else {
        developer.log('❌ [Marketing Search] لم يتم العثور على organizationUID');
      }
    }
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _delegateNameController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }

  /// Handle company search
  void _onSearchCompany() {
    final companyName = _companyNameController.text.trim();

    if (companyName.isEmpty) {
      _showSnackBar('يرجى إدخال كود الشركة');
      return;
    }

    if (_actualOrganizationUID == null) {
      _showSnackBar('خطأ: لم يتم العثور على معرف المنظمة');
      return;
    }

    developer.log('🔍 [Marketing Search] البحث عن شركة: $companyName');

    context.read<MarketingSearchBloc>().add(
      SearchCompanyRequested(
        organizationUID: _actualOrganizationUID!,
        companyName: companyName,
      ),
    );

    // إخفاء لوحة المفاتيح
    FocusScope.of(context).unfocus();
  }

  /// Handle delegate search
  void _onSearchDelegate() {
    final name = _delegateNameController.text.trim();
    final phoneNumber = _phoneNumberController.text.trim();

    if (name.isEmpty && phoneNumber.isEmpty) {
      _showSnackBar('يرجى إدخال اسم المندوب أو رقم الموبايل');
      return;
    }

    if (_actualOrganizationUID == null) {
      _showSnackBar('خطأ: لم يتم العثور على معرف المنظمة');
      return;
    }

    developer.log('🔍 [Marketing Search] البحث عن مندوب: name="$name", phone="$phoneNumber"');

    context.read<MarketingSearchBloc>().add(
      SearchDelegateRequested(
        organizationUID: _actualOrganizationUID!,
        name: name.isNotEmpty ? name : null,
        phoneNumber: phoneNumber.isNotEmpty ? phoneNumber : null,
      ),
    );

    // إخفاء لوحة المفاتيح
    FocusScope.of(context).unfocus();
  }

  /// Handle clear search
  void _onClearSearch() {
    _companyNameController.clear();
    _delegateNameController.clear();
    _phoneNumberController.clear();
    context.read<MarketingSearchBloc>().add(const ClearSearchRequested());
  }

  /// Show snackbar message
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show error if no organization UID
    if (_actualOrganizationUID == null) {
      return Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          title: const Text('البحث'),
          backgroundColor: colorScheme.surfaceContainer,
          elevation: 0,
          shape: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'لم يتم العثور على معرف المنظمة',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'يرجى تسجيل الدخول مرة أخرى',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'البحث',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        actions: [
          // زر مسح البحث
          BlocBuilder<MarketingSearchBloc, MarketingSearchState>(
            builder: (context, state) {
              // إظهار الزر فقط إذا كان هناك نتائج
              if (state is CompanySearchSuccess ||
                  state is DelegateSearchSuccess ||
                  state is MarketingSearchEmpty) {
                return IconButton(
                  icon: const Icon(Icons.clear_all_rounded),
                  tooltip: 'مسح البحث',
                  onPressed: _onClearSearch,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // قسم البحث عن الشركات
            CompanySearchSection(
              controller: _companyNameController,
              onSearch: _onSearchCompany,
            ),

            const SizedBox(height: 24),

            // فاصل
            Divider(color: colorScheme.outlineVariant, thickness: 1),

            const SizedBox(height: 24),

            // قسم البحث عن المندوبين
            DelegateSearchSection(
              nameController: _delegateNameController,
              phoneController: _phoneNumberController,
              onSearch: _onSearchDelegate,
            ),

            const SizedBox(height: 32),

            // قسم النتائج
            BlocBuilder<MarketingSearchBloc, MarketingSearchState>(
              builder: (context, state) {
                return SearchResultsSection(state: state);
              },
            ),
          ],
        ),
      ),
    );
  }
}
