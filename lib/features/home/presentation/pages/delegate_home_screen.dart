import 'package:delegate_app/core/l10n/display_names.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/features/hr/presentation/hr_account_pages.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/photo_permission/presentation/widgets/sync_status_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/firestore_session_subscriptions.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart' hide Bidi, TextDirection;
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history_for_month.dart';
import 'package:delegate_app/features/attendance/domain/monthly_attendance_stats.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:delegate_app/features/home/data/supervisor_cards_api.dart';

class DelegateHomeScreen extends StatefulWidget {
  final Delegate delegate;
  final VoidCallback? onNavigateToAttendance;

  const DelegateHomeScreen({
    super.key,
    required this.delegate,
    this.onNavigateToAttendance,
  });

  @override
  State<DelegateHomeScreen> createState() => _DelegateHomeScreenState();
}

class _DelegateHomeScreenState extends State<DelegateHomeScreen>
    with AutomaticKeepAliveClientMixin {
  static final Map<String, List<Map<String, dynamic>>> _supervisorsCache = {};
  final SupervisorCardsApi _supervisorCardsApi = SupervisorCardsApi();
  static final Map<String, DateTime> _supervisorsCacheTime = {};

  List<Map<String, dynamic>> _supervisorsData = [];
  bool _loadingSupervisor = false;
  String? _supervisorError;

  int _attendedDays = 0;
  int _absentDays = 0;
  int _approvedLeavesThisMonth = 0;

  List<Attendance> _recentSessions = [];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  DocumentSnapshot<Map<String, dynamic>>? _userDoc;
  static final Map<String, String> _orgNamesCache = {
    'PiioBFgxaHAeuRdjlDgj': 'فتح الله ماركت',
    '5DE6702w6hFwycJfZyqM': 'جملة ماركت',
    'gOaRsmPocj2xV018m0hY': 'جملة ماركت',
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final cacheKey = '${widget.delegate.organizationUID}_${widget.delegate.companyUID}';
    if (_supervisorsCache.containsKey(cacheKey)) {
      _supervisorsData = List.from(_supervisorsCache[cacheKey]!);
    }
    _fetchSupervisors();
    _loadAttendanceData();
    _loadRecentActivity();
    _listenToUserDoc();
  }

  String get _userSubKey => 'home.users.${widget.delegate.uid}';

  void _listenToUserDoc() {
    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.delegate.uid)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(() => _userDoc = doc);
    });
    FirestoreSessionSubscriptions.instance.register(_userSubKey, _userSub!);
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DelegateHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delegate.organizationUID != widget.delegate.organizationUID ||
        oldWidget.delegate.companyUID != widget.delegate.companyUID) {
      final cacheKey = '${widget.delegate.organizationUID}_${widget.delegate.companyUID}';
      if (_supervisorsCache.containsKey(cacheKey)) {
        setState(() {
          _supervisorsData = List.from(_supervisorsCache[cacheKey]!);
        });
      }
      _fetchSupervisors();
      _loadAttendanceData();
      _loadRecentActivity();
    }
  }

  Future<void> _fetchSupervisors({bool forceRefresh = false}) async {
    final orgId = widget.delegate.organizationUID;
    final compId = widget.delegate.companyUID;

    if (orgId.isEmpty || compId.isEmpty) return;

    final cacheKey = '${orgId}_$compId';
    final hasCached = _supervisorsCache.containsKey(cacheKey);

    if (!hasCached && !forceRefresh) {
      setState(() {
        _loadingSupervisor = true;
        _supervisorError = null;
      });
    }

    try {
      final List<Map<String, dynamic>> fetchedSupervisors = [];
      String companyPhone = widget.delegate.supervisorPhone ?? '';
      String companyEmail = '';
      String companySupervisorName = widget.delegate.supervisorName ?? '';
      String companyName = widget.delegate.companyName;

      // TAS-72: a delegate may only read its own users doc and list users
      // with its own phone/email, so every users get/query below is denied
      // for it (and was swallowed). Delegates read the company's `admins`
      // subcollection instead, which the rules open to the same org.
      final isDelegateViewer = widget.delegate.role == UserRole.delegate;

      // 0. Direct lookup by delegate's assigned supervisor UID if present
      final directSupervisorUid = widget.delegate.supervisorUid;
      if (directSupervisorUid != null && directSupervisorUid.isNotEmpty) {
        try {
          final supRef = isDelegateViewer
              ? FirebaseFirestore.instance
                  .collection('organizations')
                  .doc(orgId)
                  .collection('companies')
                  .doc(compId)
                  .collection('admins')
                  .doc(directSupervisorUid)
              : FirebaseFirestore.instance
                  .collection('users')
                  .doc(directSupervisorUid);
          final supDoc = await supRef.getResilient(forceServer: forceRefresh);
          if (supDoc.exists) {
            final sData = supDoc.data()!;
            final name = _extractPersonName(sData, companyName);
            // `admins/{uid}` stores the number as `phone`.
            final phone = (sData['phoneNumber'] as String?)?.trim() ??
                (sData['phone'] as String?)?.trim() ??
                (widget.delegate.supervisorPhone ?? '');
            fetchedSupervisors.add({
              ...sData,
              'displayName': name.isNotEmpty
                  ? name
                  : (companySupervisorName.isNotEmpty
                      ? companySupervisorName
                      : 'مشرف الشركة'),
              'phoneNumber': phone,
              'email': (sData['email'] as String?)?.trim() ?? '',
              'companyName': companyName,
            });
          }
        } catch (_) {}
      }

      // Also check supervisor from delegate's supervisorPhone if UID lookup didn't yield a supervisor
      if (!isDelegateViewer &&
          fetchedSupervisors.isEmpty &&
          widget.delegate.supervisorPhone != null &&
          widget.delegate.supervisorPhone!.trim().isNotEmpty) {
        try {
          final cleanPhone = widget.delegate.supervisorPhone!.replaceAll(RegExp(r'[^\d+]'), '');
          final phoneSnap = await FirebaseFirestore.instance
              .collection('users')
              .where('phoneNumber', isEqualTo: cleanPhone)
              .getResilient(forceServer: forceRefresh);
          if (phoneSnap.docs.isNotEmpty) {
            final sData = phoneSnap.docs.first.data();
            final name = _extractPersonName(sData, companyName);
            fetchedSupervisors.add({
              ...sData,
              'displayName': name.isNotEmpty
                  ? name
                  : (companySupervisorName.isNotEmpty
                      ? companySupervisorName
                      : 'مشرف الشركة'),
              'phoneNumber': cleanPhone,
              'email': (sData['email'] as String?)?.trim() ?? '',
              'companyName': companyName,
            });
          }
        } catch (_) {}
      }

      // 1. First attempt: Get company info & contact phone
      try {
        final compDoc = await FirebaseFirestore.instance
            .collection('organizations')
            .doc(orgId)
            .collection('companies')
            .doc(compId)
            .getResilient(forceServer: forceRefresh);

        if (compDoc.exists) {
          final compData = compDoc.data();
          if (compData != null) {
            companyPhone =
                (compData['phone'] as String?)?.trim() ??
                (compData['phoneNumber'] as String?)?.trim() ??
                companyPhone;
            companyEmail =
                (compData['email'] as String?)?.trim() ??
                (compData['emailAddress'] as String?)?.trim() ??
                '';
            final cName =
                (compData['name'] as String?)?.trim() ??
                (compData['displayName'] as String?)?.trim() ??
                '';
            if (cName.isNotEmpty) {
              companyName = cName;
            }

            // Look for explicit person supervisor name (must not be company name)
            final rawSupervisor =
                (compData['supervisorName'] as String?)?.trim() ??
                (compData['supervisor_name'] as String?)?.trim() ??
                (compData['contactName'] as String?)?.trim() ??
                (compData['contact_name'] as String?)?.trim() ??
                (compData['adminName'] as String?)?.trim() ??
                (compData['managerName'] as String?)?.trim() ??
                '';

            if (rawSupervisor.isNotEmpty &&
                rawSupervisor.toLowerCase() != companyName.toLowerCase()) {
              companySupervisorName = rawSupervisor;
            }
          }
        }
      } catch (_) {}

      // 2. Query the users collection for company admins/supervisors.
      // Delegates must not list company users (rules deny it; M31 f7dbcf37).
      try {
        if (widget.delegate.role != UserRole.delegate) {
        final userRoles = [
          'company-admin',
          'company_admin',
          'supervisor',
          'company_supervisor',
          'company-supervisor',
          'admin',
        ];

        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('companyUID', isEqualTo: compId)
            .getResilient(forceServer: forceRefresh);

        if (snapshot.docs.isNotEmpty) {
          for (final doc in snapshot.docs) {
            final adminData = doc.data();
            final role = (adminData['role'] as String?)?.trim().toLowerCase() ?? '';
            if (userRoles.any((r) => r.toLowerCase() == role)) {
              final phone = (adminData['phoneNumber'] as String?)?.trim() ?? '';
              final name = _extractPersonName(adminData, companyName);

              final exists = fetchedSupervisors.any(
                (s) =>
                    (s['phoneNumber'] as String? ?? '') == phone &&
                    phone.isNotEmpty,
              );

              if (!exists) {
                fetchedSupervisors.add({
                  ...adminData,
                  'displayName':
                      name.isNotEmpty ? name : companySupervisorName,
                  'phoneNumber': phone.isNotEmpty ? phone : companyPhone,
                  'email':
                      (adminData['email'] as String?)?.trim() ?? companyEmail,
                  'companyName': companyName,
                });
              }
            }
          }
        }
        } // skip company-users list for delegates
      } catch (_) {}

      // 3. Query delegates subcollection for supervisors
      if (fetchedSupervisors.isEmpty ||
          fetchedSupervisors.every(
            (s) => (s['displayName'] as String? ?? '').isEmpty,
          )) {
        try {
          // TAS-55: a plain delegate cannot read other delegate documents;
          // it gets the supervisors' name / phone / email / photo from the
          // getMySupervisorCards callable. A supervisor and staff keep the
          // direct query (the rules allow them the whole company).
          final isPlainDelegate = isDelegateViewer &&
              widget.delegate.position != DelegatePosition.supervisor;
          if (isPlainDelegate) {
            final cards = await _supervisorCardsApi.fetch(
              organizationUID: orgId,
              companyUID: compId,
            );
            for (final card in cards) {
              final exists = fetchedSupervisors.any(
                (s) =>
                    (s['phoneNumber'] as String? ?? '') == card.phoneNumber &&
                    card.phoneNumber.isNotEmpty,
              );
              if (exists) continue;
              fetchedSupervisors.add({
                'uid': card.uid,
                'displayName': card.displayName.isNotEmpty
                    ? card.displayName
                    : companySupervisorName,
                'phoneNumber': card.phoneNumber.isNotEmpty
                    ? card.phoneNumber
                    : companyPhone,
                'email': card.email.isNotEmpty ? card.email : companyEmail,
                'profileImageUrl': card.photoUrl,
                'companyName': companyName,
              });
            }
          } else {
            final delSnapshot = await FirebaseFirestore.instance
                .collection('organizations')
                .doc(orgId)
                .collection('companies')
                .doc(compId)
                .collection('delegates')
                .where('position', whereIn: ['supervisor', 'Supervisor', 'مشرف'])
                .getResilient(forceServer: forceRefresh);

            for (final doc in delSnapshot.docs) {
              final delData = doc.data();
              final phone = (delData['phoneNumber'] as String?)?.trim() ?? '';
              final name = _extractPersonName(delData, companyName);

              final exists = fetchedSupervisors.any(
                (s) =>
                    (s['phoneNumber'] as String? ?? '') == phone &&
                    phone.isNotEmpty,
              );

              if (!exists) {
                fetchedSupervisors.add({
                  ...delData,
                  'displayName':
                      name.isNotEmpty ? name : companySupervisorName,
                  'phoneNumber': phone.isNotEmpty ? phone : companyPhone,
                  'email': (delData['email'] as String?)?.trim() ?? companyEmail,
                  'companyName': companyName,
                });
              }
            }
          }
        } catch (_) {}
      }

      // 4. If companyPhone exists, also try lookup in users collection by phoneNumber
      if (!isDelegateViewer &&
          companyPhone.isNotEmpty &&
          (fetchedSupervisors.isEmpty ||
              fetchedSupervisors.every(
                (s) => (s['displayName'] as String? ?? '').isEmpty,
              ))) {
        try {
          final cleanPhone = companyPhone.replaceAll(RegExp(r'[^\d+]'), '');
          var phoneSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where('phoneNumber', isEqualTo: cleanPhone)
              .getResilient(forceServer: forceRefresh);

          if (phoneSnapshot.docs.isEmpty && cleanPhone.startsWith('0')) {
            final altPhone = cleanPhone.substring(1);
            phoneSnapshot = await FirebaseFirestore.instance
                .collection('users')
                .where('phoneNumber', isEqualTo: altPhone)
                .getResilient(forceServer: forceRefresh);
          }

          if (phoneSnapshot.docs.isNotEmpty) {
            final uData = phoneSnapshot.docs.first.data();
            final name = _extractPersonName(uData, companyName);
            if (name.isNotEmpty) {
              fetchedSupervisors.removeWhere(
                (s) => (s['phoneNumber'] as String? ?? '') == companyPhone,
              );
              fetchedSupervisors.insert(0, {
                ...uData,
                'displayName': name,
                'phoneNumber': companyPhone,
                'email': (uData['email'] as String?)?.trim() ?? companyEmail,
                'companyName': companyName,
              });
            }
          }
        } catch (_) {}
      }

      // 5. Fallback from company document
      if (fetchedSupervisors.isEmpty &&
          (companyPhone.isNotEmpty || companySupervisorName.isNotEmpty)) {
        fetchedSupervisors.add({
          'displayName':
              companySupervisorName.isNotEmpty
                  ? companySupervisorName
                  : 'مشرف الشركة',
          'phoneNumber': companyPhone,
          'email': companyEmail,
          'companyName': companyName,
          'isCompanyDoc': true,
        });
      }

      _supervisorsCache[cacheKey] = fetchedSupervisors;
      _supervisorsCacheTime[cacheKey] = DateTime.now();

      if (mounted) {
        setState(() {
          _supervisorsData = fetchedSupervisors;
          _loadingSupervisor = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _supervisorError = e.toString();
          _loadingSupervisor = false;
        });
      }
    }
  }

  String _extractPersonName(Map<String, dynamic> data, [String companyName = '']) {
    final fullName = (data['fullName'] as String?)?.trim();
    if (fullName != null && fullName.isNotEmpty) {
      return fullName;
    }

    final displayName = (data['displayName'] as String?)?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final name = (data['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }

    final first = (data['firstName'] as String?)?.trim() ?? '';
    final last = (data['lastName'] as String?)?.trim() ?? '';
    final combined = '$first $last'.trim();
    if (combined.isNotEmpty) {
      return combined;
    }

    final userName = (data['userName'] as String?)?.trim() ??
        (data['username'] as String?)?.trim() ??
        '';
    if (userName.isNotEmpty) {
      return userName;
    }

    return '';
  }

  Future<void> _callNumber(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _openWhatsApp(String phone) async {
    var cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '2$cleanPhone';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: M3Refresh(
        onRefresh: () async {
          await Future.wait([
            _fetchSupervisors(forceRefresh: true),
            _loadAttendanceData(forceRefresh: true),
            _loadRecentActivity(forceRefresh: true),
          ]);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(TashilSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SyncStatusBanner(),
              M3StaggeredItem(index: 0, child: _buildWelcomeHeroCard(context)),
              const SizedBox(height: TashilSpacing.lg),
              M3StaggeredItem(
                  index: 1, child: _buildMonthlyAttendanceSummaryCard(context)),
              if (_recentSessions.isNotEmpty)
                const SizedBox(height: TashilSpacing.lg),
              M3StaggeredItem(
                  index: 2, child: _buildRecentActivityBriefCard(context)),
              const SizedBox(height: TashilSpacing.lg),
              M3StaggeredItem(
                  index: 3, child: _buildFeedbackCard(context)),
              const SizedBox(height: TashilSpacing.xl),
              M3StaggeredItem(
                index: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: TashilSpacing.xs,
                        bottom: TashilSpacing.sm,
                      ),
                      child: Text(AppLocalizations.of(context)!.homeSupervisorsTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                    ..._buildSupervisorsList(context),
                  ],
                ),
              ),
              const SizedBox(height: TashilSpacing.lg),
              M3StaggeredItem(index: 4, child: _buildPhotoCaptureCard(context)),
              const SizedBox(height: TashilSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  /// Foreground for the home hero. Uses the screen's [context] theme
  /// directly so it is correct in both modes: onPrimary on the light
  /// primary hero, onPrimaryContainer on the dark primaryContainer hero.
  Color _heroOn(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? cs.onPrimaryContainer : cs.onPrimary;
  }

  Widget _buildWelcomeHeroCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Container(
      padding: const EdgeInsets.all(TashilSpacing.xl),
      decoration: BoxDecoration(
        // Dark: primaryContainer (no glare); light unchanged.
        color: theme.brightness == Brightness.dark
            ? colorScheme.primaryContainer
            : colorScheme.primary,
        borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting & Role Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context)!.homeGreeting(firstNameForLocale(widget.delegate.fullName, widget.delegate.firstName, isArabic: Localizations.localeOf(context).languageCode == 'ar')),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _heroOn(context),
                      ),
                    ),
                    const SizedBox(height: TashilSpacing.sm),
                    Builder(
                      builder: (context) {
                        final userData = _userDoc?.data();
                        final positionLabel = widget.delegate.position ==
                                    DelegatePosition.promoter ||
                                widget.delegate.role ==
                                    UserRole.marketingPromotion
                            ? AppLocalizations.of(context)!.roleDelegate
                            : widget.delegate.position ==
                                    DelegatePosition.supervisor
                                ? AppLocalizations.of(context)!.roleFieldSupervisor
                                : AppLocalizations.of(context)!.roleDelegate;

                        final activeOrg = widget.delegate.organizationName.trim();
                        final affiliatedOrgs = <String>{};

                        if (activeOrg.isNotEmpty) {
                          affiliatedOrgs.add(activeOrg);
                        }

                        if (userData != null) {
                          final rawList = userData['organizationNames'] ??
                              userData['organizations'];
                          if (rawList is List) {
                            for (final item in rawList) {
                              if (item is String && item.trim().isNotEmpty) {
                                affiliatedOrgs.add(item.trim());
                              }
                            }
                          }
                        }

                        for (final name in widget.delegate.allOrganizationNames) {
                          if (name.trim().isNotEmpty) {
                            affiliatedOrgs.add(name.trim());
                          }
                        }

                        final orgsList = affiliatedOrgs.toList();

                        if (orgsList.length <= 1) {
                          return Wrap(
                            spacing: TashilSpacing.sm,
                            runSpacing: TashilSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildPositionChip(positionLabel),
                              if (orgsList.isNotEmpty)
                                _buildWelcomeOrgChip(
                                  orgName: orgsList.first,
                                  isActive: true,
                                  isArabic: isArabic,
                                ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPositionChip(positionLabel),
                            const SizedBox(height: TashilSpacing.xs),
                            Wrap(
                              spacing: TashilSpacing.sm,
                              runSpacing: TashilSpacing.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (final org in orgsList)
                                  _buildWelcomeOrgChip(
                                    orgName: org,
                                    isActive: org == activeOrg,
                                    isArabic: isArabic,
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (context) {
                  final photoUrl = widget.delegate.personalPhotoUrl ??
                      (widget.delegate.documents
                          .where((d) =>
                              d.documentKey == DocumentKey.personalPhoto &&
                              d.displayUrl.isNotEmpty)
                          .firstOrNull
                          ?.displayUrl) ??
                      FirebaseAuth.instance.currentUser?.photoURL;

                  return AppAvatar(
                    imageUrl: photoUrl,
                    fallbackText: widget.delegate.firstName,
                    radius: 26,
                    backgroundColor: colorScheme.secondaryContainer,
                    foregroundColor: colorScheme.onSecondaryContainer,
                    fallbackIcon: Symbols.person_pin_rounded,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: TashilSpacing.lg),
          Divider(color: colorScheme.outlineVariant, height: 1),
          const SizedBox(height: TashilSpacing.lg),

          // Core Duties Summary
          Text(AppLocalizations.of(context)!.homeCoreDuties,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: _heroOn(context),
            ),
          ),
          const SizedBox(height: TashilSpacing.sm),

          _buildDutyItem(
            icon: Symbols.location_on_rounded,
            text:
                AppLocalizations.of(context)!.homeDutyAttendance,
          ),
          const SizedBox(height: TashilSpacing.sm),
          _buildDutyItem(
            icon: Symbols.assignment_turned_in_rounded,
            text:
                AppLocalizations.of(context)!.homeDutyTasks,
          ),
          const SizedBox(height: TashilSpacing.sm),
          _buildDutyItem(
            icon: Symbols.camera_alt_rounded,
            text:
                AppLocalizations.of(context)!.homeDutyPhotos,
          ),
        ],
      ),
    );
  }

  Widget _buildDutyItem({required IconData icon, required String text}) {
    // TAS-384: every duty on one line, cut with an ellipsis.
    return Row(
      children: [
        Icon(icon, size: 18, color: _heroOn(context)),
        const SizedBox(width: TashilSpacing.sm),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _heroOn(context),
                ),
          ),
        ),
      ],
    );
  }

  /// Chip on the hero: secondaryContainer with its on colour, no border.
  Widget _buildHeroChip({
    required IconData icon,
    required String label,
    FontWeight? fontWeight,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TashilSpacing.sm,
        vertical: TashilSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(TashilRadius.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: TashilSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: fontWeight,
                  color: colorScheme.onSecondaryContainer,
                ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: TashilSpacing.xs),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildPositionChip(String label) {
    return _buildHeroChip(icon: Symbols.badge_rounded, label: label);
  }

  Widget _buildWelcomeOrgChip({
    required String orgName,
    required bool isActive,
    required bool isArabic,
  }) {
    final label = localizeChainName(orgName, AppLocalizations.of(context));
    if (isActive) {
      return _buildHeroChip(
        icon: Symbols.domain_rounded,
        label: label,
        fontWeight: FontWeight.w700,
        trailing: Container(
          width: 5.5,
          height: 5.5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      );
    }

    return _buildHeroChip(icon: Symbols.storefront_rounded, label: label);
  }

  List<Widget> _buildSupervisorsList(BuildContext context) {
    if (_loadingSupervisor) {
      // Layout is known → skeleton (never together with an indicator).
      return [
        M3Card(
          child: Row(
            children: const [
              M3Skeleton(height: 40, width: 40, radius: 20),
              SizedBox(width: TashilSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    M3Skeleton(height: 14, width: 140),
                    SizedBox(height: TashilSpacing.sm),
                    M3Skeleton(height: 12, width: 100),
                  ],
                ),
              ),
            ],
          ),
        ),
      ];
    }

    if (_supervisorsData.isEmpty) {
      return [_buildEmptySupervisorCard(context)];
    }

    return _supervisorsData
        .map((supervisor) => _buildSupervisorCard(context, supervisor))
        .toList();
  }

  Widget _buildEmptySupervisorCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final companyName = widget.delegate.companyName.trim();
    final supervisorTitle = companyName.isEmpty
        ? l10n.companySupervisor
        : l10n.companySupervisorWithName(companyName);

    return Card.filled(
      margin: const EdgeInsetsDirectional.only(bottom: TashilSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.surface,
              foregroundColor: colorScheme.onSurfaceVariant,
              child: const Icon(Symbols.person_off_rounded),
            ),
            const SizedBox(width: TashilSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    supervisorTitle,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: TashilSpacing.xs),
                  Text(
                    _supervisorError != null
                        ? AppLocalizations.of(context)!.errorWithMessage(_supervisorError ?? '')
                        : AppLocalizations.of(context)!.noSupervisorForCompany,
                    style: textTheme.bodySmall?.copyWith(
                      color:
                          _supervisorError != null
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupervisorCard(
    BuildContext context,
    Map<String, dynamic> supervisorData,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rawName = (supervisorData['displayName'] as String?)?.trim() ??
        (supervisorData['fullName'] as String?)?.trim() ??
        (supervisorData['name'] as String?)?.trim() ??
        '';
    final companyName =
        supervisorData['companyName'] as String? ?? widget.delegate.companyName;
    final phone = (supervisorData['phoneNumber'] as String?)?.trim() ?? '';

    final displayName = rawName.isNotEmpty
        ? rawName
        : AppLocalizations.of(context)!.companySupervisor;

    final subtitleText = companyName.isNotEmpty
        ? AppLocalizations.of(context)!.supervisorOfCompany(companyName)
        : AppLocalizations.of(context)!.assignedCompanySupervisor;

    return Card.filled(
      margin: const EdgeInsetsDirectional.only(bottom: TashilSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Row(
          children: [
            // TAS-384: primary fill, readable on the filled card.
            CircleAvatar(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              child: const Icon(Symbols.person_rounded),
            ),
            const SizedBox(width: TashilSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: TashilSpacing.xs),
                  Text(
                    subtitleText,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: TashilSpacing.xs),
                    Text(
                      phone,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                  ],
                ],
              ),
            ),
            if (phone.isNotEmpty) ...[
              // TAS-384: icons on cards are primary with onPrimary.
              IconButton.filled(
                onPressed: () => _callNumber(phone),
                icon: const Icon(Symbols.phone_rounded),
                tooltip: AppLocalizations.of(context)!.callAction,
              ),
              const SizedBox(width: TashilSpacing.sm),
              // TAS-384: icons on cards are primary with onPrimary.
              IconButton.filled(
                onPressed: () => _openWhatsApp(phone),
                icon: const Icon(Symbols.chat_rounded),
                tooltip: AppLocalizations.of(context)!.whatsapp,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoCaptureCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return M3PressScale(scale: 0.98, child: Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.push('/photo-permissions/delegate', extra: widget.delegate);
        },
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(TashilSpacing.md),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Symbols.photo_camera_rounded,
                      color: colorScheme.onPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: TashilSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppLocalizations.of(context)!.offerPhotosTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: TashilSpacing.xs),
                        Text(AppLocalizations.of(context)!.offerPhotosSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TashilSpacing.lg),
              // TAS-384: the screen's one main action, a real FilledButton.
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('home_start_photos_button'),
                  onPressed: () => context.push(
                    '/photo-permissions/delegate',
                    extra: widget.delegate,
                  ),
                  icon: const Icon(Symbols.photo_camera_rounded),
                  label: Text(
                    AppLocalizations.of(context)!.startPhotosCta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  // --- Monthly Attendance Summary Logic & UI ---

  DateTime _getTrustedNow() {
    try {
      if (sl.isRegistered<TrustedTimeService>()) {
        return sl<TrustedTimeService>().now;
      }
    } catch (_) {}
    return DateTime.now();
  }

  Future<void> _loadAttendanceData({bool forceRefresh = false}) async {
    // 1. Cache-first: read immediately from local persistent cache (0 ms)
    try {
      if (sl.isRegistered<AttendanceLocalDataSource>()) {
        final localDataSource = sl<AttendanceLocalDataSource>();
        final cached = await localDataSource.getLastAttendanceHistory(
          null,
          widget.delegate.uid,
        );
        if (cached.isNotEmpty) {
          _computeStats(cached);
        }
      }
    } catch (_) {}

    // 2. Load approved leaves this month from leave_requests
    int approvedLeaves = _approvedLeavesThisMonth;
    try {
      final leavesSnap = await FirebaseFirestore.instance
          .collection('leave_requests')
          .where('delegateUid', isEqualTo: widget.delegate.uid)
          .where('status', isEqualTo: 'approved')
          .getResilient(forceServer: forceRefresh);

      final now = _getTrustedNow();
      int count = 0;
      for (final doc in leavesSnap.docs) {
        final data = doc.data();
        if (data['isHourly'] == true) continue;
        final start = data['startDate'];
        if (start is Timestamp) {
          final date = start.toDate();
          if (date.year == now.year && date.month == now.month) {
            final days = (data['daysCount'] as num?)?.toInt() ?? 1;
            count += days;
          }
        }
      }
      approvedLeaves = count;
    } catch (_) {}

    // 3. Remote fetch: every session of the current month across all
    // affiliated organizations (not a paginated slice), shared with the
    // Attendance tab so both screens always show the same figures.
    try {
      if (sl.isRegistered<GetHistoryForMonth>()) {
        final result = await sl<GetHistoryForMonth>()(
          GetHistoryForMonthParams(
            userId: widget.delegate.uid,
            month: _getTrustedNow(),
            nationalityID: widget.delegate.nationalityID,
            phoneNumber: widget.delegate.phoneNumber,
          ),
        );
        result.fold(
          (_) {},
          (history) {
            _computeStats(history, approvedLeavesCount: approvedLeaves);
          },
        );
      }
    } catch (_) {}
  }

  void _computeStats(List<Attendance> history, {int? approvedLeavesCount}) {
    final trustedNow = _getTrustedNow();

    // Earliest registration date across all chains (new delegates).
    DateTime earliestCreatedAt = widget.delegate.createdAt;
    try {
      if (sl.isRegistered<AuthLocalDataSource>()) {
        final all = sl<AuthLocalDataSource>().getCachedAllDelegatesData();
        for (final d in all) {
          if (d.createdAt.isBefore(earliestCreatedAt)) {
            earliestCreatedAt = d.createdAt;
          }
        }
      }
    } catch (_) {}

    final leavesThisMonth = approvedLeavesCount ?? _approvedLeavesThisMonth;
    final stats = MonthlyAttendanceStats.compute(
      sessions: history,
      month: trustedNow,
      now: trustedNow,
      approvedLeaveDays: leavesThisMonth,
      createdAt: earliestCreatedAt,
    );
    final attended = stats.presentDays;
    final absent = stats.absentDays;

    if (mounted) {
      setState(() {
        _attendedDays = attended;
        _absentDays = absent;
        _approvedLeavesThisMonth = leavesThisMonth;
      });
    }
  }

  Widget _buildMonthlyAttendanceSummaryCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final trustedNow = _getTrustedNow();
    final monthName =
        DateFormat('MMMM yyyy', isArabic ? 'ar' : 'en').format(trustedNow);

    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onNavigateToAttendance,
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row: Title & Link to Attendance Tab
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Symbols.insights_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: TashilSpacing.sm),
                      Text(AppLocalizations.of(context)!.homeAttendanceSummary(monthName),
                        style: textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  if (widget.onNavigateToAttendance != null)
                    Row(
                      children: [
                        Text(AppLocalizations.of(context)!.detailsAction,
                          style: textTheme.labelMedium?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                        Icon(Symbols.chevron_right_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: TashilSpacing.lg),

              // 3 Stat Badges: Attendance, Absence, Off Days
              Row(
                children: [
                  // 1. أيام الحضور
                  Expanded(
                    child: _buildAttendanceStatPill(
                      context,
                      title: AppLocalizations.of(context)!.statAttended,
                      // TAS-384: number only, HR web icons.
                      value: '$_attendedDays',
                      icon: Symbols.how_to_reg_rounded,
                      containerColor: colorScheme.surface,
                      iconColor: colorScheme.onSurfaceVariant,
                      textColor: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: TashilSpacing.sm),

                  // 2. أيام الغياب: neutral, absence is not an error
                  // (F-04, TAS-174: "not recorded" is grey).
                  Expanded(
                    child: _buildAttendanceStatPill(
                      context,
                      title: AppLocalizations.of(context)!.statAbsent,
                      value: '$_absentDays',
                      icon: Symbols.person_off_rounded,
                      containerColor: colorScheme.surface,
                      iconColor: colorScheme.onSurfaceVariant,
                      textColor: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: TashilSpacing.sm),

                  // 3. أيام الإجازة
                  Expanded(
                    child: _buildAttendanceStatPill(
                      context,
                      title: AppLocalizations.of(context)!.statDaysOff,
                      value: Bidi.ltr('$_approvedLeavesThisMonth/4'),
                      icon: Symbols.event_available_rounded,
                      containerColor: colorScheme.surface,
                      iconColor: colorScheme.onSurfaceVariant,
                      textColor: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: TashilSpacing.md),

              // Clarification Note
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: TashilSpacing.md,
                  vertical: TashilSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(TashilRadius.small),
                ),
                child: Row(
                  children: [
                    Icon(
                      Symbols.info_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: TashilSpacing.sm),
                    Expanded(
                      child: Text(AppLocalizations.of(context)!.workPolicyNote,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadRecentActivity({bool forceRefresh = false}) async {
    try {
      if (sl.isRegistered<AttendanceRemoteDataSource>()) {
        final remoteDS = sl<AttendanceRemoteDataSource>();
        final sessions = await remoteDS.getRecentSessionsAcrossOrgs(
          widget.delegate.uid,
          nationalityID: widget.delegate.nationalityID,
          phoneNumber: widget.delegate.phoneNumber,
          limit: 4,
        );
        if (mounted) {
          setState(() {
            _recentSessions = sessions;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading recent activity: $e');
    }
  }

  String _resolveOrgLabel(
    String orgId, {
    String? branchName,
    bool isArabic = true,
  }) {
    final clean = orgId.trim();
    String raw = '';
    if (clean.isEmpty) {
      raw = widget.delegate.organizationName;
    } else if (_orgNamesCache.containsKey(clean)) {
      raw = _orgNamesCache[clean]!;
    } else if (clean == widget.delegate.organizationUID) {
      _orgNamesCache[clean] = widget.delegate.organizationName;
      raw = widget.delegate.organizationName;
    } else {
      raw = widget.delegate.organizationName;
    }

    final bLower = (branchName ?? '').trim().toLowerCase();
    if (bLower.startsWith('جملة ماركت') ||
        bLower.startsWith('جمله ماركت') ||
        bLower.startsWith('gomla market') ||
        bLower.startsWith('jomla market')) {
      return AppLocalizations.of(context)!.chainGomlaMarket;
    }
    if (bLower.startsWith('فتح الله') || bLower.startsWith('fathalla')) {
      return AppLocalizations.of(context)!.chainFathallaMarket;
    }
    if (bLower.startsWith('زهران') || bLower.startsWith('zahran')) {
      return AppLocalizations.of(context)!.chainZahranMarket;
    }

    return localizeChainName(raw, AppLocalizations.of(context));
  }

  String _cleanBranchName(String rawBranchName) {
    final trimmed = rawBranchName.trim();
    if (trimmed.isEmpty) return trimmed;
    final prefixRegex = RegExp(
      r'^(?:جملة\s*ماركت|جمله\s*ماركت|فتح\s*الله\s*ماركت|فتح\s*الله|زهران\s*ماركت|زهران|كارفور|بيت\s*الجملة|fathalla\s*market|fathallah\s*market|fathalla|gomla\s*market|jomla\s*market|zahran\s*market|carrefour)\s*[-–—:،/]\s*',
      caseSensitive: false,
    );
    final cleaned = trimmed.replaceFirst(prefixRegex, '').trim();
    return cleaned.isNotEmpty ? cleaned : trimmed;
  }

  Widget _buildRecentActivityBriefCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    if (_recentSessions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Symbols.history_toggle_off_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: TashilSpacing.sm),
                    Text(AppLocalizations.of(context)!.recentBranchActivity,
                      style: textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                if (widget.onNavigateToAttendance != null)
                  InkWell(
                    onTap: widget.onNavigateToAttendance,
                    borderRadius: BorderRadius.circular(TashilRadius.small),
                    child: Padding(
                      padding: const EdgeInsets.all(TashilSpacing.xs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(AppLocalizations.of(context)!.viewLog,
                            style: textTheme.labelMedium?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                          Icon(Symbols.chevron_right_rounded,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: TashilSpacing.md),

            // Session Items (latest 2-3 sessions)
            ..._recentSessions.take(3).map((session) {
              final rawBranchName = session.branchName ??
                  AppLocalizations.of(context)!.unknownBranch;
              final cleanBranchName = _cleanBranchName(rawBranchName);
              final orgName = _resolveOrgLabel(
                session.organizationId,
                branchName: session.branchName,
                isArabic: isArabic,
              );
              final checkInStr =
                  DateFormat('hh:mm a', isArabic ? 'ar' : 'en').format(session.checkInTime);
              final checkOutStr = session.checkOutTime != null
                  ? DateFormat('hh:mm a', isArabic ? 'ar' : 'en').format(session.checkOutTime!)
                  : AppLocalizations.of(context)!.onShift;

              // Format date relative (اليوم، أمس، أو التاريخ)
              final now = _getTrustedNow();
              final isToday = session.checkInTime.year == now.year &&
                  session.checkInTime.month == now.month &&
                  session.checkInTime.day == now.day;
              final isYesterday = session.checkInTime.year == now.year &&
                  session.checkInTime.month == now.month &&
                  session.checkInTime.day == now.day - 1;

              final dateLabel = isToday
                  ? AppLocalizations.of(context)!.today
                  : isYesterday
                      ? AppLocalizations.of(context)!.yesterday
                      : DateFormat('EEE، d MMM', isArabic ? 'ar' : 'en').format(session.checkInTime);

              // Compute Duration
              String durationLabel = '';
              if (session.checkOutTime != null) {
                final diff = session.checkOutTime!.difference(session.checkInTime);
                final hours = diff.inHours;
                final minutes = diff.inMinutes % 60;
                durationLabel = AppLocalizations.of(context)!.durationHm(hours, minutes);
              }

              return Container(
                margin: const EdgeInsetsDirectional.only(bottom: TashilSpacing.sm),
                padding: const EdgeInsets.all(TashilSpacing.md),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(TashilRadius.medium),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Chain Chip + Clean Branch Name
                    Row(
                      children: [
                        if (orgName.isNotEmpty) ...[
                          // F-01: one tonal pair for every chain, no
                          // per-chain hand-picked colours.
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: TashilSpacing.sm,
                              vertical: TashilSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(TashilRadius.small),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Symbols.storefront_rounded,
                                  size: 12,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                                const SizedBox(width: TashilSpacing.xs),
                                Text(
                                  orgName,
                                  style: textTheme.labelMedium?.copyWith(
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: TashilSpacing.sm),
                        ],
                        Icon(
                          Symbols.location_on_rounded,
                          size: 15,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: TashilSpacing.xs),
                        Expanded(
                          child: Text(AppLocalizations.of(context)!.branchLabel(cleanBranchName),
                            style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TashilSpacing.sm),

                    // Row 2: Date + In/Out Times + Duration
                    Wrap(
                      spacing: TashilSpacing.sm,
                      runSpacing: TashilSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Date pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: TashilSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(TashilRadius.extraSmall),
                          ),
                          child: Text(
                            dateLabel,
                            style: textTheme.labelMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        // Check-in
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Symbols.login_rounded,
                              size: 12,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: TashilSpacing.xs),
                            Text(
                              checkInStr,
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        // Check-out
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Symbols.logout_rounded,
                              size: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: TashilSpacing.xs),
                            Text(
                              checkOutStr,
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: session.checkOutTime == null
                                    ? FontWeight.bold
                                    : null,
                                color: session.checkOutTime != null
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        // Duration
                        if (durationLabel.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.timelapse_rounded,
                                size: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: TashilSpacing.xs),
                              Text(
                                durationLabel,
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceStatPill(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color containerColor,
    required Color iconColor,
    required Color textColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: TashilSpacing.md,
        horizontal: TashilSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(TashilRadius.medium),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: iconColor),
          const SizedBox(height: TashilSpacing.xs),
          Text(
            value,
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: TashilSpacing.xs),
          Text(
            title,
            style: tt.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// TAS-384: «طلباتي» is already in the navigation bar, so the home card
  /// sends feedback instead (the same page as in settings).
  Widget _buildFeedbackCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('home_send_feedback_card'),
        onTap: () => HrAccountPages.openSendFeedback(context, widget.delegate),
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.lg),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(TashilSpacing.md),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.feedback_rounded,
                  size: 24,
                  color: colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: TashilSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.sendFeedback,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: TashilSpacing.xs),
                    Text(
                      l10n.feedbackIntro,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TashilSpacing.sm),
              Icon(
                Symbols.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
