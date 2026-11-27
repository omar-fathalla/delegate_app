import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'dart:developer' as developer;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/button_group.dart';

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
  _SearchMode _mode = _SearchMode.company;

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

    developer.log(
      '🔍 [Marketing Search] البحث عن مندوب: name="$name", phone="$phoneNumber"',
    );

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
    showTashilSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show error if no organization UID
    if (_actualOrganizationUID == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('البحث')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 64,
                color: colorScheme.error,
              ),
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

    // TAS-392: one search at a time. A connected ButtonGroup picks company or
    // delegate, so the screen keeps a single FilledButton.
    return Scaffold(
      appBar: AppBar(
        title: const Text('البحث'),
        actions: [
          BlocBuilder<MarketingSearchBloc, MarketingSearchState>(
            builder: (context, state) {
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
      body: ListView(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        children: [
          ButtonGroup<_SearchMode>(
            key: const Key('marketing_search_mode'),
            expand: true,
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
            items: const [
              ButtonGroupItem(
                key: Key('marketing_search_mode_company'),
                value: _SearchMode.company,
                label: 'شركة',
                icon: Icons.business_rounded,
              ),
              ButtonGroupItem(
                key: Key('marketing_search_mode_delegate'),
                value: _SearchMode.delegate,
                label: 'مندوب',
                icon: Icons.person_rounded,
              ),
            ],
          ),
          const SizedBox(height: TashilSpacing.lg),
          AnimatedSwitcher(
            duration: AppMotionDurations.short4,
            child: _mode == _SearchMode.company
                ? CompanySearchSection(
                    key: const ValueKey('company'),
                    controller: _companyNameController,
                    onSearch: _onSearchCompany,
                  )
                : DelegateSearchSection(
                    key: const ValueKey('delegate'),
                    nameController: _delegateNameController,
                    phoneController: _phoneNumberController,
                    onSearch: _onSearchDelegate,
                  ),
          ),
          const SizedBox(height: TashilSpacing.xl),
          BlocBuilder<MarketingSearchBloc, MarketingSearchState>(
            builder: (context, state) => SearchResultsSection(state: state),
          ),
        ],
      ),
    );
  }
}

enum _SearchMode { company, delegate }
