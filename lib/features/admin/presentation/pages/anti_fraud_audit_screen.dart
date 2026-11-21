import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/core/services/device_binding_service.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/hr/presentation/device_unbind_labels.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/pages/admin_create_penalty_page.dart';

class _CompanyContact {
  final String name;
  final String phone;
  final String role;
  final String? branch;

  _CompanyContact({
    required this.name,
    required this.phone,
    required this.role,
    this.branch,
  });
}

/// شاشة رصد وتدقيق الأمان ومكافحة برامج الـ Fake Location وتزييف الموقع (Anti-Fraud & Mock Location Audit)
class AntiFraudAuditScreen extends StatefulWidget {
  final Delegate delegate;
  final bool showAppBar;
  final String initialTab;

  /// HR web shell layout (TAS-153, TAS-154): the page shows the fraud log
  /// only, because device unbind requests live on the «فك الأجهزة» page,
  /// and the search filters as the user types without a separate button.
  /// Admin roles and mobile keep the default layout.
  final bool hrWebLayout;

  /// Firestore for the audit log stream. Null uses the default instance;
  /// tests pass a fake one.
  final FirebaseFirestore? firestore;

  const AntiFraudAuditScreen({
    super.key,
    required this.delegate,
    this.showAppBar = false,
    this.initialTab = 'violations',
    this.hrWebLayout = false,
    this.firestore,
  });

  @override
  State<AntiFraudAuditScreen> createState() => _AntiFraudAuditScreenState();
}

class _AntiFraudAuditScreenState extends State<AntiFraudAuditScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _deviceSearchController = TextEditingController();
  String _searchQuery = '';
  String _deviceSearchQuery = '';
  String _timeFilter = 'all'; // all, today
  String _selectedBranchFilter = 'all'; // all, or specific detected branch name
  late String _currentTab; // violations, devices
  String _deviceStatusFilter = 'requests'; // requests, locked, unbound, all
  int? _cachedTotalDelegatesCount;
  int? _cachedLockedCount;
  int? _cachedUnboundCount;
  List<Map<String, dynamic>>? _cachedDelegatesList;
  bool _isLoadingDelegates = false;
  List<Map<String, dynamic>> _branchesList = [];
  Map<String, String> _companiesMap = {};
  final Map<String, List<_CompanyContact>> _companyContactsCache = {};
  bool _isExporting = false;
  List<Map<String, dynamic>> _currentFilteredLogs = [];

  /// The audit log stream in the HR web layout, created once.
  Stream<QuerySnapshot>? _hrAuditStream;

  bool get _isCompanyScoped =>
      widget.delegate.companyUID.isNotEmpty &&
      widget.delegate.role != UserRole.superAdmin &&
      widget.delegate.role != UserRole.technicalSupport &&
      widget.delegate.role != UserRole.organizationAdmin;

  bool get _isOrgScoped =>
      widget.delegate.organizationUID.isNotEmpty &&
      widget.delegate.role != UserRole.superAdmin &&
      widget.delegate.role != UserRole.technicalSupport;

  String get _cachedDevicePrefix =>
      _isCompanyScoped ? 'cached_device_${widget.delegate.companyUID}_' : 'cached_device_';

  @override
  void initState() {
    super.initState();
    _currentTab = widget.hrWebLayout ? 'violations' : widget.initialTab;
    _loadBranches();
    _loadCompanies();
    // The device binding section is hidden in the HR web layout, so its
    // delegate list is not needed there.
    if (!widget.hrWebLayout) {
      _loadCachedDeviceCounts();
      _fetchDelegatesIfNeeded();
    }
  }

  Future<void> _loadCachedDeviceCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final total = prefs.getInt('${_cachedDevicePrefix}total_delegates');
      final locked = prefs.getInt('${_cachedDevicePrefix}locked_count');
      final unbound = prefs.getInt('${_cachedDevicePrefix}unbound_count');
      if (mounted && (total != null || locked != null || unbound != null)) {
        setState(() {
          _cachedTotalDelegatesCount = total;
          _cachedLockedCount = locked;
          _cachedUnboundCount = unbound;
        });
      }
    } catch (e) {
      debugPrint('Error loading cached device counts: $e');
    }
  }

  Future<void> _fetchDelegatesIfNeeded({bool forceRefresh = false}) async {
    if (!forceRefresh && (_cachedDelegatesList != null || _isLoadingDelegates)) return;
    if (mounted) setState(() => _isLoadingDelegates = true);

    try {
      final List<Map<String, dynamic>> rawList = [];

      if (_isCompanyScoped && widget.delegate.organizationUID.isNotEmpty) {
        // Query direct path for the company's delegates (instant & strictly scoped)
        final snap = await FirebaseFirestore.instance
            .collection('organizations')
            .doc(widget.delegate.organizationUID)
            .collection('companies')
            .doc(widget.delegate.companyUID)
            .collection('delegates')
            .get();

        for (final d in snap.docs) {
          rawList.add({
            'docId': d.id,
            'docPath': d.reference.path,
            ...d.data(),
          });
        }
      } else {
        Query query = FirebaseFirestore.instance.collectionGroup('delegates');
        if (_isCompanyScoped) {
          query = query.where('companyUID', isEqualTo: widget.delegate.companyUID);
        } else if (_isOrgScoped) {
          query = query.where('organizationUID', isEqualTo: widget.delegate.organizationUID);
        }

        final snapshot = await query.get();
        for (final d in snapshot.docs) {
          rawList.add({
            'docId': d.id,
            'docPath': d.reference.path,
            ...d.data() as Map<String, dynamic>,
          });
        }
      }

      final filteredRaw = rawList.where((d) {
        final role = d['role']?.toString().toLowerCase() ?? '';
        final isExcludedRole = role == 'admin' ||
            role == 'super-admin' ||
            role == 'superadmin' ||
            role == 'super_admin' ||
            role == 'technicalsupport' ||
            role == 'technical_support';
        if (isExcludedRole) return false;

        if (_isCompanyScoped) {
          final cId = (d['companyUID'] ?? '').toString().trim();
          if (cId.isNotEmpty && cId != widget.delegate.companyUID) {
            return false;
          }
        }
        return true;
      }).toList();

      // Deduplicate delegates across subcollections if same delegate appears in multiple records
      final Map<String, Map<String, dynamic>> uniqueMap = {};
      for (final d in filteredRaw) {
        final key = (d['uid'] != null && d['uid'].toString().isNotEmpty)
            ? d['uid'].toString()
            : (d['phoneNumber'] != null && d['phoneNumber'].toString().isNotEmpty)
                ? d['phoneNumber'].toString()
                : d['docId'].toString();
        if (!uniqueMap.containsKey(key)) {
          uniqueMap[key] = d;
        } else {
          final existingBound = uniqueMap[key]!['boundDeviceId']?.toString().trim() ?? '';
          final newBound = d['boundDeviceId']?.toString().trim() ?? '';
          if (existingBound.isEmpty && newBound.isNotEmpty) {
            uniqueMap[key] = d;
          }
        }
      }
      final delegatesList = uniqueMap.values.toList();

      int locked = 0;
      int unbound = 0;
      for (final item in delegatesList) {
        final boundId = item['boundDeviceId']?.toString().trim() ?? '';
        if (boundId.isNotEmpty) {
          locked++;
        } else {
          unbound++;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('${_cachedDevicePrefix}total_delegates', delegatesList.length);
      await prefs.setInt('${_cachedDevicePrefix}locked_count', locked);
      await prefs.setInt('${_cachedDevicePrefix}unbound_count', unbound);

      if (mounted) {
        setState(() {
          _cachedDelegatesList = delegatesList;
          _cachedTotalDelegatesCount = delegatesList.length;
          _cachedLockedCount = locked;
          _cachedUnboundCount = unbound;
          _isLoadingDelegates = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading delegates: $e');
      if (mounted) {
        setState(() => _isLoadingDelegates = false);
      }
    }
  }

  Future<void> _loadBranches() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('branches').get();
      final list = snap.docs.map((d) {
        final data = d.data();
        final name = (data['branchName'] as String?) ??
            (data['name'] as String?) ??
            (data['title'] as String?) ??
            d.id;
        double? lat;
        double? lng;
        if (data['location'] is Map) {
          lat = (data['location']['latitude'] as num?)?.toDouble();
          lng = (data['location']['longitude'] as num?)?.toDouble();
        } else if (data['latitude'] != null && data['longitude'] != null) {
          lat = (data['latitude'] as num?)?.toDouble();
          lng = (data['longitude'] as num?)?.toDouble();
        }
        return {
          'id': d.id,
          'name': name,
          'latitude': lat,
          'longitude': lng,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _branchesList = list;
        });
      }
    } catch (e, st) {
      debugPrint('AntiFraudAudit: failed to load branches: $e\n$st');
    }
  }

  String _resolveBranchName(Map<String, dynamic> item) {
    final directBranch = (item['branchName'] as String?)?.trim() ?? '';
    if (directBranch.isNotEmpty && directBranch != 'غير محدد') {
      return directBranch;
    }

    final branchUid = (item['branchUID'] as String?)?.trim() ?? '';
    if (branchUid.isNotEmpty) {
      final match = _branchesList.firstWhere(
        (b) => b['id'] == branchUid,
        orElse: () => {'name': ''},
      );
      if ((match['name'] as String?)?.isNotEmpty == true) {
        return match['name'] as String;
      }
    }

    // Match closest branch from mock coordinates
    final lat = (item['latitude'] as num?)?.toDouble();
    final lng = (item['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null && _branchesList.isNotEmpty) {
      double minDistance = double.infinity;
      String bestName = '';
      String bestId = '';

      for (final b in _branchesList) {
        final bLat = b['latitude'] as double?;
        final bLng = b['longitude'] as double?;
        if (bLat != null && bLng != null) {
          final dist = Geolocator.distanceBetween(lat, lng, bLat, bLng);
          if (dist < minDistance) {
            minDistance = dist;
            bestName = b['name'] as String;
            bestId = b['id'] as String;
          }
        }
      }

      if (bestName.isNotEmpty) {
        final docId = item['docId']?.toString();
        if (docId != null && docId.isNotEmpty && item['_isUpdated'] != true) {
          item['_isUpdated'] = true;
          FirebaseFirestore.instance
              .collection('security_audit_logs')
              .doc(docId)
              .update({
                'branchName': bestName,
                'branchUID': bestId,
              })
              .catchError((_) {});
        }
        return bestName;
      }
    }

    return 'غير محدد';
  }

  Future<void> _loadCompanies() async {
    try {
      final snap = await FirebaseFirestore.instance.collectionGroup('companies').get();
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim() ??
            (data['companyName'] as String?)?.trim() ??
            '';
        if (name.isNotEmpty) {
          map[doc.id] = name;
        }
      }
      if (mounted) {
        setState(() {
          _companiesMap = map;
        });
      }
    } catch (_) {}
  }

  String _resolveCompanyName(Map<String, dynamic> item) {
    final compUid = (item['companyUID'] as String?)?.trim() ?? '';
    if (compUid.isNotEmpty && _companiesMap.containsKey(compUid)) {
      final officialName = _companiesMap[compUid]!;
      final currentName = (item['companyName'] as String?)?.trim() ?? '';
      if (currentName != officialName && item['_isCompUpdated'] != true) {
        item['_isCompUpdated'] = true;
        final docId = item['docId']?.toString();
        if (docId != null && docId.isNotEmpty) {
          FirebaseFirestore.instance
              .collection('security_audit_logs')
              .doc(docId)
              .update({'companyName': officialName})
              .catchError((_) {});
        }
      }
      return officialName;
    }
    return (item['companyName'] as String?)?.trim() ?? '';
  }

  @override
  void dispose() {
    _searchController.dispose();
    _deviceSearchController.dispose();
    super.dispose();
  }

  Future<void> _makePhoneCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _openWhatsApp(String phone) async {
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '2$cleanPhone';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  int _getDistinctFraudDays(Map<String, dynamic> data, Map<String, Set<String>> daysMap) {
    final uid = (data['delegateUid'] ?? '').toString().trim();
    if (uid.isNotEmpty && daysMap.containsKey('uid:$uid')) {
      return daysMap['uid:$uid']!.length;
    }
    final phone = (data['delegatePhone'] ?? '').toString().trim();
    if (phone.isNotEmpty && daysMap.containsKey('phone:$phone')) {
      return daysMap['phone:$phone']!.length;
    }
    final name = (data['delegateName'] ?? '').toString().trim();
    if (name.isNotEmpty && daysMap.containsKey('name:$name')) {
      return daysMap['name:$name']!.length;
    }
    return 1;
  }

  Widget _buildFraudDaysChip({
    required ColorScheme colorScheme,
    required int daysCount,
    required bool isArabic,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: isArabic
          ? 'تم رصد محاولات تزييف في $daysCount ${daysCount == 1 ? "يوم واحد" : (daysCount == 2 ? "يومين مختلفين" : "أيام مختلفة")}'
          : 'Spoofing detected on $daysCount distinct day${daysCount > 1 ? "s" : ""}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: colorScheme.error,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.error.withValues(alpha: 0.35),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              '$daysCount',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onError,
                height: 1.0,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Future<List<_CompanyContact>> _fetchCompanyContacts(Map<String, dynamic> auditData) async {
    final compId = (auditData['companyUID'] ?? '').toString().trim();
    final compName = _resolveCompanyName(auditData).trim();
    final orgId = (auditData['organizationUID'] ?? '').toString().trim();
    final delegateUid = (auditData['delegateUid'] ?? '').toString().trim();

    final cacheKey = compId.isNotEmpty ? compId : compName;
    if (cacheKey.isNotEmpty && _companyContactsCache.containsKey(cacheKey)) {
      return _companyContactsCache[cacheKey]!;
    }

    final List<_CompanyContact> contacts = [];
    final Set<String> seenPhones = {};

    void addContact({
      required String name,
      required String phone,
      required String role,
      String? branch,
    }) {
      final clean = phone.replaceAll(RegExp(r'\s+'), '').trim();
      if (clean.isEmpty || clean.length < 7) return;

      final digits = clean.replaceAll(RegExp(r'[^0-9]'), '');
      final normalized = digits.startsWith('20')
          ? digits.substring(2)
          : (digits.startsWith('0') ? digits.substring(1) : digits);

      if (seenPhones.contains(normalized)) return;
      seenPhones.add(normalized);

      contacts.add(_CompanyContact(
        name: name.isNotEmpty ? name : (compName.isNotEmpty ? 'مسؤول $compName' : 'مشرف الشركة'),
        phone: clean,
        role: role,
        branch: branch,
      ));
    }

    final firestore = FirebaseFirestore.instance;

    // 1. Check direct supervisor from delegate's user document
    if (delegateUid.isNotEmpty) {
      try {
        final delDoc = await firestore.collection('users').doc(delegateUid).get();
        if (delDoc.exists) {
          final dData = delDoc.data()!;
          final supPhone = (dData['supervisorPhone'] ?? dData['supervisor_phone'])?.toString();
          final supName = (dData['supervisorName'] ?? dData['supervisor_name'])?.toString();
          final supUid = (dData['supervisorUid'] ?? dData['supervisor_uid'])?.toString();

          if (supPhone != null && supPhone.trim().isNotEmpty) {
            addContact(
              name: supName?.trim().isNotEmpty == true ? supName!.trim() : 'المشرف المباشر للمندوب',
              phone: supPhone,
              role: 'المشرف المباشر للمندوب',
            );
          }

          if (supUid != null && supUid.trim().isNotEmpty) {
            try {
              final supUserDoc = await firestore.collection('users').doc(supUid.trim()).get();
              if (supUserDoc.exists) {
                final suData = supUserDoc.data()!;
                final sPhone = (suData['phoneNumber'] ?? suData['phone'])?.toString();
                final sName = (suData['fullName'] ??
                    '${suData['firstName'] ?? ''} ${suData['lastName'] ?? ''}').toString().trim();
                if (sPhone != null && sPhone.isNotEmpty) {
                  addContact(
                    name: sName.isNotEmpty ? sName : 'المشرف المباشر',
                    phone: sPhone,
                    role: 'المشرف المباشر للمندوب',
                  );
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    // 2. Query users collection by companyUID or companyName for supervisors & company admins
    try {
      QuerySnapshot<Map<String, dynamic>>? usersSnap;
      if (compId.isNotEmpty) {
        usersSnap = await firestore
            .collection('users')
            .where('companyUID', isEqualTo: compId)
            .get();
      } else if (compName.isNotEmpty) {
        usersSnap = await firestore
            .collection('users')
            .where('companyName', isEqualTo: compName)
            .get();
      }

      if (usersSnap != null && usersSnap.docs.isNotEmpty) {
        for (final doc in usersSnap.docs) {
          final uData = doc.data();
          final role = (uData['role'] as String?)?.trim().toLowerCase() ?? '';
          final position = (uData['position'] as String?)?.trim().toLowerCase() ?? '';
          final phone = (uData['phoneNumber'] ?? uData['phone'] ?? '').toString();

          if (phone.isEmpty) continue;

          final isSupervisor = role.contains('supervisor') ||
              role == 'companysupervisor' ||
              role == 'company-supervisor' ||
              position.contains('مشرف') ||
              position.contains('supervisor');

          final isAdmin = role.contains('admin') ||
              role == 'company-admin' ||
              role == 'company_admin' ||
              position.contains('مدير') ||
              position.contains('مسؤول') ||
              position.contains('admin');

          if (isSupervisor || isAdmin) {
            final name = (uData['fullName'] ??
                '${uData['firstName'] ?? ''} ${uData['lastName'] ?? ''}').toString().trim();
            final branch = (uData['branchName'] ?? uData['branch'])?.toString();
            final roleTitle = isSupervisor ? 'مشرف الشركة' : 'مسؤول الشركة';

            addContact(
              name: name.isNotEmpty ? name : roleTitle,
              phone: phone,
              role: roleTitle,
              branch: branch,
            );
          }
        }
      }
    } catch (_) {}

    // 3. Check Company Document (both nested and root)
    try {
      Map<String, dynamic>? cData;
      if (orgId.isNotEmpty && compId.isNotEmpty) {
        final compDoc = await firestore
            .collection('organizations')
            .doc(orgId)
            .collection('companies')
            .doc(compId)
            .get();
        if (compDoc.exists) cData = compDoc.data();
      }

      if (cData == null && compId.isNotEmpty) {
        final rootDoc = await firestore.collection('companies').doc(compId).get();
        if (rootDoc.exists) cData = rootDoc.data();
      }

      if (cData != null) {
        final cPhone = (cData['supervisorPhone'] ??
            cData['phone'] ??
            cData['phoneNumber'] ??
            cData['telephone'] ??
            cData['mobile'])?.toString();
        final cContact = (cData['supervisorName'] ??
            cData['contactPerson'] ??
            cData['contactName'] ??
            cData['managerName'] ??
            cData['name'])?.toString();

        if (cPhone != null && cPhone.isNotEmpty) {
          addContact(
            name: cContact?.isNotEmpty == true ? cContact! : 'مشرف الشركة',
            phone: cPhone,
            role: 'مشرف الشركة',
          );
        }
      }
    } catch (_) {}

    // 4. Check nested delegates subcollection for supervisors
    if (orgId.isNotEmpty && compId.isNotEmpty) {
      try {
        final delegatesSnap = await firestore
            .collection('organizations')
            .doc(orgId)
            .collection('companies')
            .doc(compId)
            .collection('delegates')
            .where('role', isEqualTo: 'companySupervisor')
            .get();

        for (final doc in delegatesSnap.docs) {
          final dData = doc.data();
          final phone = (dData['phoneNumber'] ?? dData['phone'])?.toString() ?? '';
          final name = (dData['fullName'] ??
              '${dData['firstName'] ?? ''} ${dData['lastName'] ?? ''}').toString().trim();
          if (phone.isNotEmpty) {
            addContact(
              name: name.isNotEmpty ? name : 'مشرف الشركة',
              phone: phone,
              role: 'مشرف الشركة',
            );
          }
        }
      } catch (_) {}
    }

    if (cacheKey.isNotEmpty && contacts.isNotEmpty) {
      _companyContactsCache[cacheKey] = contacts;
    }

    return contacts;
  }

  void _showCompanySupervisorsSheet(
    BuildContext context,
    String companyName,
    List<_CompanyContact> contacts,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(bottomSheetContext).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Sheet Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.supervisor_account_rounded,
                          color: colorScheme.onPrimaryContainer,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isArabic ? 'مشرفو ومسؤولو الشركة' : 'Company Supervisors & Contacts',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              companyName.isNotEmpty
                                  ? (isArabic
                                      ? 'شركة: $companyName (${contacts.length} أرقام متاحة)'
                                      : 'Company: $companyName (${contacts.length} numbers)')
                                  : (isArabic
                                      ? 'قائمة الأرقام المتاحة (${contacts.length})'
                                      : 'Available numbers (${contacts.length})'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: isArabic ? 'إغلاق' : 'Close',
                        onPressed: () => Navigator.of(bottomSheetContext).pop(),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // List of Supervisors / Contacts
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: contacts.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (ctx, index) {
                      final contact = contacts[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            CircleAvatar(
                              backgroundColor: colorScheme.secondaryContainer,
                              foregroundColor: colorScheme.onSecondaryContainer,
                              radius: 20,
                              child: Text(
                                contact.name.trim().isNotEmpty
                                    ? contact.name.trim().characters.first
                                    : 'م',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    contact.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          contact.role,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      if (contact.branch != null && contact.branch!.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            contact.branch!,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    contact.phone,
                                    textDirection: ui.TextDirection.ltr,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Action buttons: Direct Call and WhatsApp
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.phone_rounded, size: 19),
                                  tooltip: isArabic ? 'اتصال هاتفي' : 'Call',
                                  onPressed: () {
                                    Navigator.of(bottomSheetContext).pop();
                                    _makePhoneCall(contact.phone);
                                  },
                                ),
                                const SizedBox(width: 6),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.chat_rounded, size: 19),
                                  tooltip: isArabic ? 'مراسلة عبر واتساب' : 'WhatsApp',
                                  onPressed: () {
                                    Navigator.of(bottomSheetContext).pop();
                                    _openWhatsApp(contact.phone);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleCompanyCall(BuildContext context, Map<String, dynamic> data) async {
    final companyName = _resolveCompanyName(data);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Text(
                  isArabic ? 'جاري جلب أرقام مشرفي الشركة...' : 'Fetching company contacts...',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    List<_CompanyContact> contacts = [];
    try {
      contacts = await _fetchCompanyContacts(data);
    } catch (_) {}

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!context.mounted) return;

    if (contacts.isEmpty) {
      final delegatePhone = (data['delegatePhone'] ?? '').toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            companyName.isNotEmpty
                ? (isArabic
                    ? 'لم يتم العثور على أرقام مسجلة لمشرفي شركة ($companyName).'
                    : 'No contact numbers found for supervisors of ($companyName).')
                : (isArabic
                    ? 'لم يتم العثور على أرقام مسجلة لمشرفي الشركة.'
                    : 'No supervisor contacts found for this company.'),
          ),
          action: delegatePhone.isNotEmpty
              ? SnackBarAction(
                  label: isArabic ? 'اتصال بالمندوب' : 'Call Delegate',
                  onPressed: () => _makePhoneCall(delegatePhone),
                )
              : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (contacts.length == 1) {
      final contact = contacts.first;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'الاتصال بمشرف الشركة (${contact.name}): ${contact.phone}'
                : 'Calling supervisor (${contact.name}): ${contact.phone}',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      _makePhoneCall(contact.phone);
      return;
    }

    _showCompanySupervisorsSheet(context, companyName, contacts);
  }

  Future<void> _openLocationOnMap(double lat, double lng) async {
    final googleMapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(googleMapsUri)) {
        await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(googleMapsUri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        await launchUrl(googleMapsUri);
      } catch (_) {}
    }
  }

  Future<void> _exportToCSV(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('لا توجد سجلات لتصديرها حالياً'),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isExporting = true);

    try {
      // Helper function to escape CSV cell contents
      String escapeCsv(dynamic value) {
        if (value == null) return '""';
        final str = value.toString().replaceAll('"', '""');
        return '"$str"';
      }

      // UTF-8 BOM (\uFEFF) ensures Excel properly displays Arabic characters
      final buffer = StringBuffer();
      buffer.write('\uFEFF');

      // CSV Header Row
      buffer.writeln([
        'م',
        'اسم المندوب',
        'رقم الهاتف',
        'الجهاز المستخدم',
        'اسم الشركة',
        'الفرع المرصود',
        'تاريخ وتوقيت المحاولة',
        'الإحداثيات المرصودة (Lat, Lng)',
        'خط العرض (Latitude)',
        'خط الطول (Longitude)',
        'رابط خرائط جوجل (Google Maps)',
        'موقع اتصال الإنترنت الفعلي (ISP & Location)',
        'عنوان الـ IP',
        'نوع العملية',
        'حالة الرصد',
      ].map(escapeCsv).join(','));

      // CSV Data Rows
      for (int i = 0; i < logs.length; i++) {
        final data = logs[i];
        final index = (i + 1).toString();
        final delegateName = data['delegateName']?.toString() ?? 'غير محدد';
        final delegatePhone = data['delegatePhone']?.toString() ?? '';
        final deviceModel = data['deviceModel']?.toString() ?? 'غير معروف';
        final companyName = _resolveCompanyName(data);
        final branchName = _resolveBranchName(data);

        // Attempt Timestamp
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        final realTs = data['realTimestamp'] != null
            ? DateTime.tryParse(data['realTimestamp'].toString())
            : (data['createdAt'] != null
                ? DateTime.tryParse(data['createdAt'].toString())
                : null);
        final effectiveDate = ts ?? realTs;
        final dateStr = effectiveDate != null
            ? DateFormat('yyyy-MM-dd  hh:mm a').format(effectiveDate)
            : 'غير محدد';

        // Coordinates & Map Link
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        final coordsStr = (lat != null && lng != null)
            ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
            : '';
        final latStr = lat != null ? lat.toStringAsFixed(6) : '';
        final lngStr = lng != null ? lng.toStringAsFixed(6) : '';
        final mapUrl = (lat != null && lng != null)
            ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
            : '';

        final networkLocation = data['networkLocation']?.toString() ?? '';
        final ipCity = data['ipCity']?.toString() ?? '';
        final ipIsp = data['ipIsp']?.toString() ?? '';
        final fullNetLoc = networkLocation.isNotEmpty
            ? networkLocation
            : (ipCity.isNotEmpty ? '$ipCity ($ipIsp)' : '');
        final ipAddress = data['ipAddress']?.toString() ?? '';
        final actionType = data['actionType']?.toString() ?? 'تسجيل حضور/انصراف';
        const status = 'محظورة (Fake GPS)';

        buffer.writeln([
          index,
          delegateName,
          delegatePhone,
          deviceModel,
          companyName,
          branchName,
          dateStr,
          coordsStr,
          latStr,
          lngStr,
          mapUrl,
          fullNetLoc,
          ipAddress,
          actionType,
          status,
        ].map(escapeCsv).join(','));
      }

      final directory = await getTemporaryDirectory();
      final nowStr = DateFormat('yyyy_MM_dd_HHmm').format(DateTime.now());
      final file = File('${directory.path}/تقرير_محاولات_تزييف_الموقع_$nowStr.csv');
      await file.writeAsString(buffer.toString());

      if (mounted) {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'تقرير سجلات كشف التزييف والأمان (Fake GPS Audit Report) - $nowStr',
        );
      }
    } catch (e) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تصدير الملف: $e'),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _resetDelegateDevice(
    BuildContext context,
    String delegateUid,
    String delegateName, {
    String? orgId,
    String? compId,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;
    if (delegateUid.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر تحديد معرف المندوب'),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.phonelink_erase_rounded, color: colorScheme.primary, size: 28),
            const SizedBox(width: 8),
            const Text('فك ربط الجهاز', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل أنت متأكد من فك ربط جهاز المندوب "$delegateName"؟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'سيتمكن المندوب من ربط جهازه الجديد تلقائياً بمجرد تسجيل دخوله القادم.',
                      style: TextStyle(fontSize: 12, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد فك الربط'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DeviceBindingService.resetDelegateDeviceBinding(
          delegateUid: delegateUid,
          organizationUID: orgId,
          companyUID: compId,
          adminUid: widget.delegate.uid,
        );

        if (_cachedDelegatesList != null) {
          final index = _cachedDelegatesList!.indexWhere(
            (d) => d['uid'] == delegateUid || d['docId'] == delegateUid,
          );
          if (index != -1) {
            final oldBound = _cachedDelegatesList![index]['boundDeviceId']?.toString().trim() ?? '';
            _cachedDelegatesList![index]['boundDeviceId'] = '';
            _cachedDelegatesList![index]['boundDeviceModel'] = '';
            _cachedDelegatesList![index]['boundDeviceBrand'] = '';
            _cachedDelegatesList![index]['boundDeviceLockedAt'] = null;
            if (oldBound.isNotEmpty) {
              final currentLocked = _cachedLockedCount ?? 0;
              final currentUnbound = _cachedUnboundCount ?? 0;
              final newLocked = (currentLocked - 1).clamp(0, 999999);
              final newUnbound = currentUnbound + 1;
              if (mounted) {
                setState(() {
                  _cachedLockedCount = newLocked;
                  _cachedUnboundCount = newUnbound;
                });
              }
              SharedPreferences.getInstance().then((prefs) {
                prefs.setInt('cached_device_locked_count', newLocked);
                prefs.setInt('cached_device_unbound_count', newUnbound);
              }).ignore();
            }
          }
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم فك ربط جهاز المندوب "$delegateName" بنجاح. يستطيع الآن الدخول من هاتفه الجديد.'),
              backgroundColor: colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ أثناء فك الربط: $e'),
              backgroundColor: colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteAuditLog(BuildContext context, String docId, String delegateName) async {
    final colorScheme = Theme.of(context).colorScheme;
    if (docId.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر تحديد معرف السجل الأمني'),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: colorScheme.error, size: 28),
            const SizedBox(width: 8),
            const Text('حذف السجل الأمني', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف سجل المخالفة الأمني للمندوب "$delegateName"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance.collection('security_audit_logs').doc(docId).delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تم حذف السجل الأمني بنجاح'),
              backgroundColor: colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ أثناء الحذف: $e'),
              backgroundColor: colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _createPenaltyForDelegate(
    BuildContext context,
    Map<String, dynamic> data, {
    int distinctDaysCount = 1,
  }) {
    final companyUid = data['companyUID']?.toString() ?? '';
    final companyName = _resolveCompanyName(data);
    final delegateUid = data['delegateUid']?.toString() ?? '';
    final delegateName = data['delegateName']?.toString() ?? '';
    final resolvedBranchName = _resolveBranchName(data);
    String resolvedBranchUid = data['branchUID']?.toString() ?? '';
    if (resolvedBranchUid.isEmpty && resolvedBranchName != 'غير محدد') {
      final match = _branchesList.firstWhere(
        (b) => b['name'] == resolvedBranchName,
        orElse: () => {'id': ''},
      );
      resolvedBranchUid = (match['id'] as String?) ?? '';
    }
    final deviceModel = data['deviceModel']?.toString() ?? 'جهاز غير محدد';
    final actionType = data['actionType']?.toString() ?? 'تسجيل الحضور/الانصراف';

    final networkLocation = data['networkLocation']?.toString() ?? '';

    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final realTs = data['realTimestamp'] != null
        ? DateTime.tryParse(data['realTimestamp'].toString())
        : (data['createdAt'] != null ? DateTime.tryParse(data['createdAt'].toString()) : null);
    final effectiveRealDate = ts ?? realTs;
    final realDateStr = effectiveRealDate != null
        ? DateFormat('yyyy-MM-dd  hh:mm a').format(effectiveRealDate)
        : '';

    final String daysSummary;
    if (distinctDaysCount == 1) {
      daysSummary = 'يوم واحد (1)';
    } else if (distinctDaysCount == 2) {
      daysSummary = 'يومان (2)';
    } else {
      daysSummary = '$distinctDaysCount أيام';
    }

    final incidentBuffer = StringBuffer();
    incidentBuffer.write('تم رصد محاولة تزييف موقع جغرافي (Fake GPS) بواسطة جهاز ($deviceModel)');
    if (actionType.isNotEmpty) {
      incidentBuffer.write(' أثناء $actionType');
    }
    if (resolvedBranchName.isNotEmpty && resolvedBranchName != 'غير محدد') {
      incidentBuffer.write(' بفرع $resolvedBranchName');
    }
    if (realDateStr.isNotEmpty) {
      incidentBuffer.write(' بتاريخ $realDateStr');
    }
    if (networkLocation.isNotEmpty) {
      incidentBuffer.write('، مع رصد اتصاله بالإنترنت من موقع ($networkLocation)');
    }
    incidentBuffer.write('، مع توثيق رصد تزييف الموقع للمندوب في ($daysSummary منفصلة)');
    incidentBuffer.write('، وتم اعتراض الإحداثيات وتوثيق الواقعة في سجل الأمان.');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => di.sl<PenaltyBloc>(),
          child: AdminCreatePenaltyPage(
            adminDelegate: widget.delegate,
            initialCompanyId: companyUid.isNotEmpty ? companyUid : null,
            initialCompanyName: companyName.isNotEmpty ? companyName : null,
            initialDelegateId: delegateUid.isNotEmpty ? delegateUid : null,
            initialDelegateName: delegateName.isNotEmpty ? delegateName : null,
            initialBranchId: resolvedBranchUid.isNotEmpty ? resolvedBranchUid : null,
            initialBranchName: resolvedBranchName != 'غير محدد' ? resolvedBranchName : null,
            initialViolationId: 28, // بند تزييف موقع الحضور والانصراف (Fake GPS) - 200 جنيه
            initialIncidentDetails: incidentBuffer.toString(),
          ),
        ),
      ),
    );
  }

  bool _matchesTimeFilter(DateTime? timestamp) {
    if (timestamp == null) return true;
    final now = DateTime.now();

    switch (_timeFilter) {
      case 'today':
        return timestamp.year == now.year &&
            timestamp.month == now.month &&
            timestamp.day == now.day;
      case 'all':
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    Query auditQuery = (widget.firestore ?? FirebaseFirestore.instance)
        .collection('security_audit_logs');
    if (_isCompanyScoped) {
      auditQuery = auditQuery.where('companyUID', isEqualTo: widget.delegate.companyUID);
    } else if (_isOrgScoped) {
      auditQuery = auditQuery.where('organizationUID', isEqualTo: widget.delegate.organizationUID);
    }

    // HR web searches as the user types, so every keystroke rebuilds the
    // page. Keep one stream there; a new one would drop back to the
    // spinner and take the focus from the search field.
    final Stream<QuerySnapshot> auditStream = widget.hrWebLayout
        ? (_hrAuditStream ??= auditQuery.snapshots())
        : auditQuery.snapshots();

    final body = StreamBuilder<QuerySnapshot>(
      stream: auditStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final allLogs = docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return {
            'docId': d.id,
            ...data,
          };
        }).toList();

        // 1. Strict double-enforcement of Company / Org isolation in memory
        if (_isCompanyScoped) {
          allLogs.removeWhere((item) {
            final compId = (item['companyUID'] ?? '').toString().trim();
            final compName = _resolveCompanyName(item).trim();
            if (compId.isNotEmpty && compId != widget.delegate.companyUID) {
              return true;
            }
            if (compId.isEmpty && compName.isNotEmpty && compName != widget.delegate.companyName.trim()) {
              return true;
            }
            return false;
          });
        } else if (_isOrgScoped) {
          allLogs.removeWhere((item) {
            final orgId = (item['organizationUID'] ?? '').toString().trim();
            return orgId.isNotEmpty && orgId != widget.delegate.organizationUID;
          });
        }

        // 2. Sort by timestamp descending in memory (0ms)
        allLogs.sort((a, b) {
          final aTs = (a['timestamp'] as Timestamp?)?.toDate() ??
              DateTime.tryParse(a['realTimestamp']?.toString() ?? '') ??
              (a['createdAt'] != null ? DateTime.tryParse(a['createdAt'].toString()) : null) ??
              DateTime(2000);
          final bTs = (b['timestamp'] as Timestamp?)?.toDate() ??
              DateTime.tryParse(b['realTimestamp']?.toString() ?? '') ??
              (b['createdAt'] != null ? DateTime.tryParse(b['createdAt'].toString()) : null) ??
              DateTime(2000);
          return bTs.compareTo(aTs);
        });

        // Calculate distinct calendar days of fraud attempts per delegate
        final Map<String, Set<String>> delegateDistinctDaysMap = {};
        for (final item in allLogs) {
          final ts = (item['timestamp'] as Timestamp?)?.toDate();
          final realTs = item['realTimestamp'] != null
              ? DateTime.tryParse(item['realTimestamp'].toString())
              : (item['createdAt'] != null ? DateTime.tryParse(item['createdAt'].toString()) : null);
          final effectiveDate = ts ?? realTs;
          if (effectiveDate == null) continue;

          final dayString = DateFormat('yyyy-MM-dd').format(effectiveDate);
          final uid = (item['delegateUid'] ?? '').toString().trim();
          final phone = (item['delegatePhone'] ?? '').toString().trim();
          final name = (item['delegateName'] ?? '').toString().trim();

          final keys = <String>{};
          if (uid.isNotEmpty) keys.add('uid:$uid');
          if (phone.isNotEmpty) keys.add('phone:$phone');
          if (name.isNotEmpty) keys.add('name:$name');
          if (keys.isEmpty) continue;

          Set<String>? sharedDaysSet;
          final connectedKeys = <String>{...keys};

          for (final k in keys) {
            if (delegateDistinctDaysMap.containsKey(k)) {
              if (sharedDaysSet == null) {
                sharedDaysSet = delegateDistinctDaysMap[k];
              } else {
                sharedDaysSet.addAll(delegateDistinctDaysMap[k]!);
              }
            }
          }

          sharedDaysSet ??= <String>{};
          sharedDaysSet.add(dayString);

          // Link all keys pointing to this delegate's set
          for (final entry in delegateDistinctDaysMap.entries) {
            if (identical(entry.value, sharedDaysSet)) {
              connectedKeys.add(entry.key);
            }
          }

          for (final k in connectedKeys) {
            delegateDistinctDaysMap[k] = sharedDaysSet;
          }
        }

        // Calculate summary metrics
        final now = DateTime.now();
        int todayAttempts = 0;
        final Set<String> uniqueDelegates = {};
        final Set<String> uniqueDevices = {};

        // Extract unique detected branch names from allLogs
        final Set<String> detectedBranchesSet = {};
        for (final item in allLogs) {
          final ts = (item['timestamp'] as Timestamp?)?.toDate();
          if (ts != null &&
              ts.year == now.year &&
              ts.month == now.month &&
              ts.day == now.day) {
            todayAttempts++;
          }
          final uid = item['delegateUid']?.toString() ?? '';
          if (uid.isNotEmpty) uniqueDelegates.add(uid);

          final dev = item['deviceModel']?.toString() ?? '';
          if (dev.isNotEmpty && dev != 'Unknown Device') uniqueDevices.add(dev);

          final bName = _resolveBranchName(item).trim();
          if (bName.isNotEmpty && bName != 'غير محدد') {
            detectedBranchesSet.add(bName);
          }
        }
        final detectedBranches = detectedBranchesSet.toList()..sort();

        // Apply filters
        final filteredLogs = allLogs.where((item) {
          // 1. Time filter (All or Today)
          final ts = (item['timestamp'] as Timestamp?)?.toDate();
          if (!_matchesTimeFilter(ts)) return false;

          // 2. Detected Branch filter
          if (_selectedBranchFilter != 'all') {
            final itemBranch = _resolveBranchName(item).trim();
            if (itemBranch != _selectedBranchFilter) {
              return false;
            }
          }

          // 3. Search query filter
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            final name = (item['delegateName'] ?? '').toString().toLowerCase();
            final phone = (item['delegatePhone'] ?? '').toString().toLowerCase();
            final comp = _resolveCompanyName(item).toLowerCase();
            final branch = _resolveBranchName(item).toLowerCase();
            final dev = (item['deviceModel'] ?? '').toString().toLowerCase();

            if (!name.contains(q) &&
                !phone.contains(q) &&
                !comp.contains(q) &&
                !branch.contains(q) &&
                !dev.contains(q)) {
              return false;
            }
          }

          return true;
        }).toList();

        _currentFilteredLogs = filteredLogs;

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {});
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (!widget.showAppBar)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isArabic ? 'سجل الأمان وكشف التزييف' : 'Security & Anti-Fraud Logs',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                                if (widget.delegate.companyName.isNotEmpty)
                                  Text(
                                    widget.delegate.companyName,
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: isArabic ? 'تحديث' : 'Refresh',
                            onPressed: () => setState(() {}),
                          ),
                          IconButton(
                            icon: _isExporting
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.primary,
                                    ),
                                  )
                                : const Icon(Icons.file_download_outlined),
                            tooltip: isArabic ? 'تصدير إكسيل' : 'Export Excel',
                            onPressed: (_isExporting || _currentFilteredLogs.isEmpty)
                                ? null
                                : () => _exportToCSV(_currentFilteredLogs),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_currentTab == 'devices') ...[
                  SliverToBoxAdapter(
                    child: _buildDeviceBindingSection(colorScheme, isArabic),
                  ),
                ] else ...[
                  // 1. Header Metrics (3/4) & Tab Switcher Card (1/4)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isDesktop = constraints.maxWidth >= 768;
                          final metricsWidget = _buildHeaderMetrics(
                            colorScheme: colorScheme,
                            totalAttempts: allLogs.length,
                            todayAttempts: todayAttempts,
                            uniqueDelegatesCount: uniqueDelegates.length,
                            uniqueDevicesCount: uniqueDevices.length,
                            isArabic: isArabic,
                          );

                          // HR web: no section switcher, the metrics take
                          // the full width.
                          if (widget.hrWebLayout) return metricsWidget;

                          if (isDesktop) {
                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: metricsWidget,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: _buildTabSwitcherCard(
                                      colorScheme,
                                      isArabic,
                                      violationsCount: allLogs.length,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            return Column(
                              children: [
                                _buildTabSwitcherCard(
                                  colorScheme,
                                  isArabic,
                                  violationsCount: allLogs.length,
                                  isHorizontal: true,
                                ),
                                const SizedBox(height: 10),
                                metricsWidget,
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  ),

                  // 2. Single-Row Filter Toolbar & Results Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Single-Row Filter Toolbar (Desktop: 1 row, Mobile: 2 rows)
                          _buildFilterToolbar(
                            colorScheme: colorScheme,
                            isArabic: isArabic,
                            allLogs: allLogs,
                            filteredLogs: filteredLogs,
                            detectedBranches: detectedBranches,
                            todayAttempts: todayAttempts,
                          ),

                          if (_searchQuery.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: colorScheme.outlineVariant),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.filter_alt_rounded, size: 16, color: colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      isArabic
                                          ? 'نتائج البحث عن: "$_searchQuery" (${filteredLogs.length} سجل)'
                                          : 'Results for "$_searchQuery" (${filteredLogs.length} items)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          isArabic ? 'إلغاء' : 'Clear',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.error,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Icon(Icons.close_rounded, size: 14, color: colorScheme.error),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 10),

                          // Section Title with Detected Violations Count
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.shield_outlined, size: 15, color: colorScheme.primary),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isArabic
                                      ? 'سجلات محاولات التزييف المكتشفة (${filteredLogs.length})'
                                      : 'Detected Violations (${filteredLogs.length})',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

              // 4. List of Violation Cards
              if (filteredLogs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_user_rounded,
                            size: 64,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isArabic ? 'سجل الأمان نظيف تماماً' : 'Security Log Clean',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isArabic
                                ? 'لم يتم تسجيل أي محاولات لاستخدام برامج Fake Location مطابقة للبحث المحدد.'
                                : 'No Fake Location / mock GPS attempts match your current filter.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                if (MediaQuery.sizeOf(context).width >= 850)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _buildTableHeader(colorScheme, isArabic),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = filteredLogs[index];
                        return _buildViolationCard(
                          context: context,
                          colorScheme: colorScheme,
                          data: item,
                          isArabic: isArabic,
                          distinctDaysCount: _getDistinctFraudDays(item, delegateDistinctDaysMap),
                        );
                      },
                      childCount: filteredLogs.length,
                    ),
                  ),
                ),
              ],
                ],
            ],
          ),
        );
      },
    );

    if (widget.showAppBar) {
      return Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          backgroundColor: colorScheme.surfaceContainer,
          elevation: 0,
          scrolledUnderElevation: 2.0,
          shape: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isArabic ? 'سجل الأمان وكشف التزييف' : 'Security & Anti-Fraud Logs',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.delegate.companyName.isNotEmpty)
                Text(
                  widget.delegate.companyName,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: isArabic ? 'تحديث' : 'Refresh',
              onPressed: () => setState(() {}),
            ),
            IconButton(
              icon: _isExporting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.file_download_outlined),
              tooltip: isArabic ? 'تصدير إكسيل' : 'Export Excel',
              onPressed: (_isExporting || _currentFilteredLogs.isEmpty)
                  ? null
                  : () => _exportToCSV(_currentFilteredLogs),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: body,
      );
    }

    return body;
  }


  Widget _buildHeaderMetrics({
    required ColorScheme colorScheme,
    required int totalAttempts,
    required int todayAttempts,
    required int uniqueDelegatesCount,
    required int uniqueDevicesCount,
    required bool isArabic,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.security_rounded,
                  color: colorScheme.onErrorContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'منظومة كشف التزييف والأمان' : 'Anti-Fraud & Security Monitor',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isArabic
                          ? 'رصد محاولات الـ Fake GPS وبصمات الأجهزة المخالفة'
                          : 'Real-time mock GPS & device fingerprint tracking',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.4), height: 1),
          const SizedBox(height: 12),

          // Stat row
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatBox(
                  colorScheme: colorScheme,
                  title: isArabic ? 'إجمالي المحاولات' : 'Total Attempts',
                  value: '$totalAttempts',
                  icon: Icons.gavel_rounded,
                ),
                const SizedBox(width: 8),
                _buildStatBox(
                  colorScheme: colorScheme,
                  title: isArabic ? 'اليوم' : 'Today',
                  value: '$todayAttempts',
                  icon: Icons.today_rounded,
                  isHighlight: todayAttempts > 0,
                ),
                const SizedBox(width: 8),
                _buildStatBox(
                  colorScheme: colorScheme,
                  title: isArabic ? 'المناديب' : 'Delegates',
                  value: '$uniqueDelegatesCount',
                  icon: Icons.people_outline_rounded,
                ),
                const SizedBox(width: 8),
                _buildStatBox(
                  colorScheme: colorScheme,
                  title: isArabic ? 'الأجهزة' : 'Devices',
                  value: '$uniqueDevicesCount',
                  icon: Icons.phone_android_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required ColorScheme colorScheme,
    required String title,
    required String value,
    required IconData icon,
    bool isHighlight = false,
    Color? highlightColor,
    Color? onHighlightColor,
    VoidCallback? onTap,
  }) {
    final bg = isHighlight
        ? (highlightColor ?? colorScheme.primaryContainer)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
    final fg = isHighlight
        ? (onHighlightColor ?? colorScheme.onPrimaryContainer)
        : colorScheme.onSurface;
    final border = isHighlight
        ? ((highlightColor ?? colorScheme.primary).withValues(alpha: 0.35))
        : colorScheme.outlineVariant.withValues(alpha: 0.4);

    Widget box = Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: fg,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              color: isHighlight
                  ? fg.withValues(alpha: 0.85)
                  : colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    if (onTap != null) {
      box = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: box,
      );
    }

    return Expanded(child: box);
  }

  Widget _buildTableHeader(ColorScheme colorScheme, bool isArabic) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 23,
            child: _buildHeaderCell(
              icon: Icons.person_off_rounded,
              label: isArabic ? 'المندوب / الموظف' : 'Delegate / User',
              colorScheme: colorScheme,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 18,
            child: _buildHeaderCell(
              icon: Icons.storefront_rounded,
              label: isArabic ? 'الفرع والشركة' : 'Branch & Company',
              colorScheme: colorScheme,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 19,
            child: _buildHeaderCell(
              icon: Icons.phone_android_rounded,
              label: isArabic ? 'الجهاز والشبكة' : 'Device & Network',
              colorScheme: colorScheme,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 22,
            child: _buildHeaderCell(
              icon: Icons.security_rounded,
              label: isArabic ? 'توقيت المحاولة والموقع' : 'Attempt & Location',
              colorScheme: colorScheme,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 18,
            child: _buildHeaderCell(
              icon: Icons.tune_rounded,
              label: isArabic ? 'الإجراءات والقرارات' : 'Actions',
              colorScheme: colorScheme,
              alignment: AlignmentDirectional.centerEnd,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
    AlignmentDirectional alignment = AlignmentDirectional.centerStart,
  }) {
    return Align(
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViolationCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required Map<String, dynamic> data,
    required bool isArabic,
    required int distinctDaysCount,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 850) {
      return _buildWideViolationRow(
        context: context,
        colorScheme: colorScheme,
        data: data,
        isArabic: isArabic,
        distinctDaysCount: distinctDaysCount,
      );
    }
    return _buildMobileViolationCard(
      context: context,
      colorScheme: colorScheme,
      data: data,
      isArabic: isArabic,
      distinctDaysCount: distinctDaysCount,
    );
  }

  Widget _buildWideViolationRow({
    required BuildContext context,
    required ColorScheme colorScheme,
    required Map<String, dynamic> data,
    required bool isArabic,
    required int distinctDaysCount,
  }) {
    final docId = (data['docId'] != null && data['docId'].toString().trim().isNotEmpty)
        ? data['docId'].toString().trim()
        : (data['id']?.toString().trim() ?? '');
    final delegateName = data['delegateName']?.toString() ?? 'مندوب غير محدد';
    final delegatePhone = data['delegatePhone']?.toString() ?? '';
    final companyName = _resolveCompanyName(data);
    final branchName = _resolveBranchName(data);
    final deviceModel = data['deviceModel']?.toString() ?? 'جهاز غير معروف';
    final actionType = data['actionType']?.toString() ?? '';
    final networkLocation = data['networkLocation']?.toString() ?? '';
    final ipAddress = data['ipAddress']?.toString() ?? '';
    final ipCity = data['ipCity']?.toString() ?? '';
    final ipIsp = data['ipIsp']?.toString() ?? '';

    // Coordinates
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();

    // Actual attempt timestamp
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final realTs = data['realTimestamp'] != null
        ? DateTime.tryParse(data['realTimestamp'].toString())
        : (data['createdAt'] != null ? DateTime.tryParse(data['createdAt'].toString()) : null);
    final effectiveRealDate = ts ?? realTs;
    final realDateStr = effectiveRealDate != null
        ? DateFormat('yyyy-MM-dd  hh:mm a').format(effectiveRealDate)
        : 'غير محدد';

    final isApple = deviceModel.toLowerCase().contains('iphone') ||
        deviceModel.toLowerCase().contains('ipad') ||
        deviceModel.toLowerCase().contains('ios');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Delegate & Days (flex: 23)
            Expanded(
              flex: 23,
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                    radius: 17,
                    child: const Icon(Icons.person_off_rounded, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                delegateName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildFraudDaysChip(
                              colorScheme: colorScheme,
                              daysCount: distinctDaysCount,
                              isArabic: isArabic,
                              onTap: () {
                                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isArabic
                                          ? 'سجل المندوب: رُصدت محاولات التزييف في $distinctDaysCount ${distinctDaysCount == 1 ? "يوم واحد" : (distinctDaysCount == 2 ? "يومين مختلفين" : "أيام مختلفة")}.'
                                          : 'Fraud record: Spoofing detected on $distinctDaysCount distinct day${distinctDaysCount > 1 ? "s" : ""}.',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        if (delegatePhone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            delegatePhone,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 2. Branch & Company (flex: 18)
            Expanded(
              flex: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_rounded, size: 14, color: colorScheme.primary),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          branchName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (companyName.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            companyName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 3. Device & Network (flex: 19)
            Expanded(
              flex: 19,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isApple ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          deviceModel,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_tethering_rounded, size: 13, color: colorScheme.outline),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          networkLocation.isNotEmpty
                              ? networkLocation
                              : (ipCity.isNotEmpty
                                  ? '$ipCity ($ipIsp)'
                                  : (ipAddress.isNotEmpty
                                      ? 'IP: $ipAddress'
                                      : (actionType.isNotEmpty ? actionType : '-'))),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 4. Incident & Coordinates (flex: 22)
            Expanded(
              flex: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 13, color: colorScheme.error),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          realDateStr,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'محظورة',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (lat != null && lng != null)
                    InkWell(
                      onTap: () => _openLocationOnMap(lat, lng),
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_rounded, size: 13, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                              decoration: TextDecoration.underline,
                              decorationColor: colorScheme.primary.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.open_in_new_rounded, size: 11, color: colorScheme.primary),
                        ],
                      ),
                    )
                  else if (actionType.isNotEmpty)
                    Text(
                      'العملية: $actionType',
                      style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 5. Actions (flex: 18)
            Expanded(
              flex: 18,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (lat != null && lng != null)
                        IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.map_rounded, size: 15),
                          tooltip: isArabic ? 'عرض الموقع على الخريطة' : 'View on Map',
                          onPressed: () => _openLocationOnMap(lat, lng),
                        ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.phone_rounded, size: 15),
                        tooltip: isArabic
                            ? 'اتصال بمشرف الشركة (${companyName.isNotEmpty ? companyName : "الشركة"})'
                            : 'Call Company Supervisor (${companyName.isNotEmpty ? companyName : "Company"})',
                        onPressed: () => _handleCompanyCall(context, data),
                      ),
                      if (delegatePhone.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.chat_rounded, size: 15),
                          tooltip: isArabic ? 'مراسلة المندوب عبر واتساب' : 'WhatsApp Delegate',
                          onPressed: () => _openWhatsApp(delegatePhone),
                        ),
                      ],
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.errorContainer,
                          foregroundColor: colorScheme.onErrorContainer,
                        ),
                        icon: const Icon(Icons.gavel_rounded, size: 15),
                        tooltip: isArabic ? 'تطبيق مخالفة وغرامة للمندوب' : 'Issue Penalty',
                        onPressed: () => _createPenaltyForDelegate(
                          context,
                          data,
                          distinctDaysCount: distinctDaysCount,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.phonelink_erase_rounded, size: 15),
                        tooltip: isArabic ? 'فك ربط جهاز المندوب' : 'Unbind Device',
                        onPressed: () => _resetDelegateDevice(
                          context,
                          data['delegateUid']?.toString() ?? '',
                          delegateName,
                          orgId: data['organizationUID']?.toString(),
                          compId: data['companyUID']?.toString(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: Icon(Icons.delete_outline_rounded, color: colorScheme.outline, size: 17),
                        tooltip: isArabic ? 'حذف السجل' : 'Delete Log',
                        onPressed: () => _deleteAuditLog(context, docId, delegateName),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileViolationCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required Map<String, dynamic> data,
    required bool isArabic,
    required int distinctDaysCount,
  }) {
    final docId = (data['docId'] != null && data['docId'].toString().trim().isNotEmpty)
        ? data['docId'].toString().trim()
        : (data['id']?.toString().trim() ?? '');
    final delegateName = data['delegateName']?.toString() ?? 'مندوب غير محدد';
    final delegatePhone = data['delegatePhone']?.toString() ?? '';
    final companyName = _resolveCompanyName(data);
    final branchName = _resolveBranchName(data);
    final deviceModel = data['deviceModel']?.toString() ?? 'جهاز غير معروف';
    final actionType = data['actionType']?.toString() ?? '';
    final networkLocation = data['networkLocation']?.toString() ?? '';
    final ipAddress = data['ipAddress']?.toString() ?? '';
    final ipCity = data['ipCity']?.toString() ?? '';
    final ipIsp = data['ipIsp']?.toString() ?? '';

    // Coordinates
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();

    // Actual attempt timestamp
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final realTs = data['realTimestamp'] != null
        ? DateTime.tryParse(data['realTimestamp'].toString())
        : (data['createdAt'] != null ? DateTime.tryParse(data['createdAt'].toString()) : null);
    final effectiveRealDate = ts ?? realTs;
    final realDateStr = effectiveRealDate != null
        ? DateFormat('yyyy-MM-dd  hh:mm a').format(effectiveRealDate)
        : 'غير محدد';

    final isApple = deviceModel.toLowerCase().contains('iphone') ||
        deviceModel.toLowerCase().contains('ipad') ||
        deviceModel.toLowerCase().contains('ios');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Delegate Name & Avatar with Distinct Days Counter Chip
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                  radius: 20,
                  child: const Icon(Icons.person_off_rounded, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              delegateName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildFraudDaysChip(
                            colorScheme: colorScheme,
                            daysCount: distinctDaysCount,
                            isArabic: isArabic,
                            onTap: () {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isArabic
                                        ? 'سجل المندوب: رُصدت محاولات التزييف في $distinctDaysCount ${distinctDaysCount == 1 ? "يوم واحد" : (distinctDaysCount == 2 ? "يومين مختلفين" : "أيام مختلفة")}.'
                                        : 'Fraud record: Spoofing detected on $distinctDaysCount distinct day${distinctDaysCount > 1 ? "s" : ""}.',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      if (delegatePhone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          delegatePhone,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 10),

            // Device Info Chip (Device Fingerprint)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(
                    isApple ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الجهاز المستخدم: $deviceModel',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Branch & Company Tags Row
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Branch Tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_rounded, size: 15, color: colorScheme.primary),
                      const SizedBox(width: 5),
                      Text(
                        'الفرع: $branchName',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),

                // Company Tag
                if (companyName.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business_rounded, size: 15, color: colorScheme.primary),
                        const SizedBox(width: 5),
                        Text(
                          'الشركة: $companyName',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Incident Details Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  // Attempt Timestamp Row
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'توقيت المحاولة: ',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          realDateStr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'محظورة',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (lat != null && lng != null) ...[
                    const SizedBox(height: 6),
                    Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 4),
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => _openLocationOnMap(lat, lng),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Row(
                            children: [
                              Icon(Icons.location_on_rounded, size: 16, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                'الإحداثيات المرصودة: ',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                    decorationColor: colorScheme.primary.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.map_rounded, size: 12, color: colorScheme.onPrimaryContainer),
                                    const SizedBox(width: 3),
                                    Text(
                                      'عرض بالخريطة',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (networkLocation.isNotEmpty || ipAddress.isNotEmpty || ipCity.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.wifi_tethering_rounded, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'اتصال الإنترنت الفعلي: ',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            networkLocation.isNotEmpty
                                ? networkLocation
                                : (ipCity.isNotEmpty ? '$ipCity ($ipIsp)' : 'IP: $ipAddress'),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (actionType.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.event_note_rounded, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'نوع العملية: ',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          actionType,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Action Buttons Bar (Responsive & Icon-First)
            Row(
              children: [
                if (lat != null && lng != null)
                  IconButton.filledTonal(
                    icon: const Icon(Icons.map_rounded, size: 18),
                    tooltip: isArabic ? 'عرض الموقع على الخريطة' : 'View on Map',
                    onPressed: () => _openLocationOnMap(lat, lng),
                  ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  tooltip: isArabic
                      ? 'اتصال بمشرف الشركة (${companyName.isNotEmpty ? companyName : "الشركة"})'
                      : 'Call Company Supervisor (${companyName.isNotEmpty ? companyName : "Company"})',
                  onPressed: () => _handleCompanyCall(context, data),
                ),
                if (delegatePhone.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    tooltip: isArabic ? 'مراسلة المندوب عبر واتساب' : 'WhatsApp Delegate',
                    onPressed: () => _openWhatsApp(delegatePhone),
                  ),
                ],
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                  ),
                  icon: const Icon(Icons.gavel_rounded, size: 18),
                  tooltip: isArabic ? 'تطبيق مخالفة وغرامة للمندوب' : 'Issue Penalty',
                  onPressed: () => _createPenaltyForDelegate(
                    context,
                    data,
                    distinctDaysCount: distinctDaysCount,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  icon: const Icon(Icons.phonelink_erase_rounded, size: 18),
                  tooltip: isArabic ? 'فك ربط جهاز المندوب' : 'Unbind Device',
                  onPressed: () => _resetDelegateDevice(
                    context,
                    data['delegateUid']?.toString() ?? '',
                    delegateName,
                    orgId: data['organizationUID']?.toString(),
                    compId: data['companyUID']?.toString(),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: colorScheme.outline, size: 19),
                  tooltip: isArabic ? 'حذف السجل' : 'Delete Log',
                  onPressed: () => _deleteAuditLog(context, docId, delegateName),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSwitcherCard(
    ColorScheme colorScheme,
    bool isArabic, {
    int? violationsCount,
    int? pendingRequestsCount,
    bool isHorizontal = false,
  }) {
    if (isHorizontal) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildTabCardItem(
                title: isArabic ? 'سجلات كشف التزييف' : 'Fraud Violations',
                icon: Icons.security_rounded,
                isSelected: _currentTab == 'violations',
                count: violationsCount,
                colorScheme: colorScheme,
                onTap: () {
                  if (_currentTab != 'violations') {
                    setState(() => _currentTab = 'violations');
                  }
                },
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _buildTabCardItem(
                title: isArabic ? 'ربط أجهزة المناديب' : 'Device Binding',
                icon: Icons.phonelink_lock_rounded,
                isSelected: _currentTab == 'devices',
                count: pendingRequestsCount,
                isWarningBadge: (pendingRequestsCount ?? 0) > 0,
                colorScheme: colorScheme,
                onTap: () {
                  if (_currentTab != 'devices') {
                    setState(() => _currentTab = 'devices');
                    _fetchDelegatesIfNeeded();
                  }
                },
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.layers_rounded,
                  color: colorScheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'أقسام الرقابة' : 'Audit Sections',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      isArabic ? 'سجلات الاحتيال والأجهزة' : 'Violations & Devices',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.35), height: 1),
          const Spacer(),
          // Tab 1: Fraud Violations
          _buildTabCardItem(
            title: isArabic ? 'سجلات كشف التزييف' : 'Fraud Violations',
            icon: Icons.security_rounded,
            isSelected: _currentTab == 'violations',
            count: violationsCount,
            colorScheme: colorScheme,
            onTap: () {
              if (_currentTab != 'violations') {
                setState(() => _currentTab = 'violations');
              }
            },
          ),
          const SizedBox(height: 6),
          // Tab 2: Device Binding
          _buildTabCardItem(
            title: isArabic ? 'ربط أجهزة المناديب' : 'Device Binding',
            icon: Icons.phonelink_lock_rounded,
            isSelected: _currentTab == 'devices',
            count: pendingRequestsCount,
            isWarningBadge: (pendingRequestsCount ?? 0) > 0,
            colorScheme: colorScheme,
            onTap: () {
              if (_currentTab != 'devices') {
                setState(() => _currentTab = 'devices');
                _fetchDelegatesIfNeeded();
              }
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildTabCardItem({
    required String title,
    required IconData icon,
    required bool isSelected,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
    int? count,
    bool isWarningBadge = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: colorScheme.primary.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: isSelected ? 1.2 : 0.8,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? colorScheme.onPrimary : colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isWarningBadge ? colorScheme.error : colorScheme.onPrimary.withValues(alpha: 0.25))
                        : (isWarningBadge ? colorScheme.errorContainer : colorScheme.primaryContainer),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : (isWarningBadge ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer),
                    ),
                  ),
                ),
              ],
              if (isSelected && (count == null || count == 0)) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: colorScheme.onPrimary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterToolbar({
    required ColorScheme colorScheme,
    required bool isArabic,
    required List<Map<String, dynamic>> allLogs,
    required List<Map<String, dynamic>> filteredLogs,
    required List<String> detectedBranches,
    required int todayAttempts,
  }) {
    // 1. Search text field
    final searchField = SizedBox(
      height: 44,
      child: TextField(
        controller: _searchController,
        style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
        textInputAction: TextInputAction.search,
        // HR web filters as the user types (TAS-154).
        onChanged: widget.hrWebLayout
            ? (val) => setState(() => _searchQuery = val.trim())
            : null,
        onSubmitted: (val) {
          setState(() => _searchQuery = val.trim());
        },
        decoration: InputDecoration(
          hintText: isArabic
              ? 'بحث بالمندوب، الشركة، الفرع، أو نوع الجهاز...'
              : 'Search delegate, company, branch, or device...',
          hintStyle: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w400,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 19,
            color: colorScheme.primary,
          ),
          suffixIcon: _searchController.text.isNotEmpty || _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  tooltip: isArabic ? 'مسح البحث' : 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: colorScheme.primary,
              width: 1.5,
            ),
          ),
        ),
      ),
    );

    // 2. Search action button
    final searchButton = SizedBox(
      width: 44,
      height: 44,
      child: IconButton.filled(
        onPressed: () {
          setState(() => _searchQuery = _searchController.text.trim());
          FocusScope.of(context).unfocus();
        },
        icon: const Icon(Icons.search_rounded, size: 19),
        tooltip: isArabic ? 'تنفيذ البحث' : 'Search',
        style: IconButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          padding: EdgeInsets.zero,
        ),
      ),
    );

    // 3. Branch Filter Dropdown (M3 via PopupMenuButton)
    final branchDropdown = PopupMenuButton<String>(
      tooltip: isArabic ? 'تصفية الفروع' : 'Filter branches',
      initialValue: (detectedBranches.contains(_selectedBranchFilter) || _selectedBranchFilter == 'all')
          ? _selectedBranchFilter
          : 'all',
      color: colorScheme.surfaceContainerHigh,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      onSelected: (val) {
        setState(() => _selectedBranchFilter = val);
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem<String>(
            value: 'all',
            child: Row(
              children: [
                Icon(
                  Icons.storefront_rounded,
                  size: 18,
                  color: _selectedBranchFilter == 'all'
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isArabic ? 'جميع الفروع المرصودة' : 'All Detected Branches',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: _selectedBranchFilter == 'all' ? FontWeight.bold : FontWeight.normal,
                      color: _selectedBranchFilter == 'all' ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${allLogs.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_selectedBranchFilter == 'all') ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check_rounded, size: 16, color: colorScheme.primary),
                ],
              ],
            ),
          ),
          ...detectedBranches.map((branchName) {
            final branchLogsCount = allLogs
                .where((l) => _resolveBranchName(l).trim() == branchName)
                .length;
            final isSelected = _selectedBranchFilter == branchName;
            return PopupMenuItem<String>(
              value: branchName,
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 18,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      branchName,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$branchLogsCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check_rounded, size: 16, color: colorScheme.primary),
                  ],
                ],
              ),
            );
          }),
        ];
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _selectedBranchFilter != 'all'
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: _selectedBranchFilter != 'all' ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(
              Icons.storefront_rounded,
              size: 18,
              color: _selectedBranchFilter != 'all'
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedBranchFilter == 'all'
                    ? (isArabic
                        ? 'جميع الفروع (${allLogs.length})'
                        : 'All Branches (${allLogs.length})')
                    : '$_selectedBranchFilter (${allLogs.where((l) => _resolveBranchName(l).trim() == _selectedBranchFilter).length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _selectedBranchFilter != 'all'
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );

    // 4. Time Filters (الكل / اليوم) M3 Segmented Control (Equal Width)
    final timeFilterSegment = Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegmentButton(
              label: isArabic ? 'الكل (${allLogs.length})' : 'All (${allLogs.length})',
              isSelected: _timeFilter == 'all',
              colorScheme: colorScheme,
              onTap: () => setState(() => _timeFilter = 'all'),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _buildSegmentButton(
              label: isArabic ? 'اليوم ($todayAttempts)' : 'Today ($todayAttempts)',
              isSelected: _timeFilter == 'today',
              colorScheme: colorScheme,
              onTap: () => setState(() => _timeFilter = 'today'),
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768;
        if (isDesktop) {
          return Row(
            children: [
              Expanded(child: searchField),
              if (!widget.hrWebLayout) ...[
                const SizedBox(width: 8),
                searchButton,
              ],
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
                child: branchDropdown,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
                child: timeFilterSegment,
              ),
            ],
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: searchField),
                  if (!widget.hrWebLayout) ...[
                    const SizedBox(width: 8),
                    searchButton,
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 11,
                    child: branchDropdown,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 10,
                    child: timeFilterSegment,
                  ),
                ],
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildSegmentButton({
    required String label,
    required bool isSelected,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(19),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceBindingSection(ColorScheme colorScheme, bool isArabic) {
    Query requestsQuery = FirebaseFirestore.instance.collection('device_unbind_requests');
    if (_isCompanyScoped) {
      requestsQuery = requestsQuery.where('companyUID', isEqualTo: widget.delegate.companyUID);
    } else if (_isOrgScoped) {
      requestsQuery = requestsQuery.where('organizationUID', isEqualTo: widget.delegate.organizationUID);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: requestsQuery.snapshots(),
      builder: (context, requestsSnapshot) {
        if (requestsSnapshot.connectionState == ConnectionState.waiting && !requestsSnapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Process unbind requests
        final reqDocs = requestsSnapshot.data?.docs ?? [];
        final allRequests = reqDocs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return {
            'docId': d.id,
            ...data,
          };
        }).toList();

        if (_isCompanyScoped) {
          allRequests.removeWhere((r) {
            final cId = (r['companyUID'] ?? '').toString().trim();
            return cId.isNotEmpty && cId != widget.delegate.companyUID;
          });
        } else if (_isOrgScoped) {
          allRequests.removeWhere((r) {
            final oId = (r['organizationUID'] ?? '').toString().trim();
            return oId.isNotEmpty && oId != widget.delegate.organizationUID;
          });
        }

        allRequests.sort((a, b) {
          final aTime = a['createdAt'];
          final bTime = b['createdAt'];
          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }
          return 0;
        });

        final pendingRequests = allRequests.where((r) => r['status'] == 'pending').toList();

        final isRequestsView = _deviceStatusFilter == 'requests';

        // Filter requests when on requests view
        final filteredRequests = pendingRequests.where((req) {
          if (_deviceSearchQuery.isNotEmpty) {
            final q = _deviceSearchQuery.toLowerCase();
            final name = (req['delegateName'] ?? '').toString().toLowerCase();
            final phone = (req['delegatePhone'] ?? '').toString().toLowerCase();
            final comp = (req['companyName'] ?? '').toString().toLowerCase();
            final bDev = (req['boundDeviceModel'] ?? '').toString().toLowerCase();
            final rDev = (req['requestedDeviceModel'] ?? '').toString().toLowerCase();

            if (!name.contains(q) && !phone.contains(q) && !comp.contains(q) && !bDev.contains(q) && !rDev.contains(q)) {
              return false;
            }
          }
          return true;
        }).toList();

        // Lazy load delegates if user switched to delegates view and not yet loaded
        if (!isRequestsView && _cachedDelegatesList == null && !_isLoadingDelegates) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _fetchDelegatesIfNeeded();
          });
        }

        // Filter delegates if loaded
        final delegatesList = _cachedDelegatesList ?? [];
        final filteredDelegates = delegatesList.where((d) {
          final boundId = d['boundDeviceId']?.toString().trim() ?? '';
          if (_deviceStatusFilter == 'locked' && boundId.isEmpty) return false;
          if (_deviceStatusFilter == 'unbound' && boundId.isNotEmpty) return false;

          if (_deviceSearchQuery.isNotEmpty) {
            final q = _deviceSearchQuery.toLowerCase();
            final name = (d['fullName'] ?? d['firstName'] ?? '').toString().toLowerCase();
            final phone = (d['phoneNumber'] ?? '').toString().toLowerCase();
            final comp = (d['companyName'] ?? '').toString().toLowerCase();
            final dev = (d['boundDeviceModel'] ?? '').toString().toLowerCase();

            if (!name.contains(q) && !phone.contains(q) && !comp.contains(q) && !dev.contains(q)) {
              return false;
            }
          }
          return true;
        }).toList();

        final currentCount = isRequestsView ? filteredRequests.length : filteredDelegates.length;

        final totalDelegatesStr = _cachedTotalDelegatesCount != null
            ? '$_cachedTotalDelegatesCount'
            : (_isLoadingDelegates ? '...' : '—');
        final lockedStr = _cachedLockedCount != null
            ? '$_cachedLockedCount'
            : (_isLoadingDelegates ? '...' : '—');
        final unboundStr = _cachedUnboundCount != null
            ? '$_cachedUnboundCount'
            : (_isLoadingDelegates ? '...' : '—');

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Device Binding Header Banner (3/4) & Tab Switcher Card (1/4)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 768;
                  final deviceBanner = Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.phonelink_lock_rounded, color: colorScheme.onPrimaryContainer, size: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'منظومة قفل وربط أجهزة المناديب',
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'حساب كل مندوب مقترن بهاتفه المعتمد لمنع تبادل الحسابات',
                                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildStatBox(
                                colorScheme: colorScheme,
                                title: 'المناديب',
                                value: totalDelegatesStr,
                                icon: Icons.people_outline_rounded,
                                isHighlight: _deviceStatusFilter == 'all',
                                onTap: () {
                                  setState(() {
                                    _deviceStatusFilter = 'all';
                                    _deviceSearchQuery = '';
                                    _deviceSearchController.clear();
                                  });
                                  if (_cachedDelegatesList == null) {
                                    _fetchDelegatesIfNeeded();
                                  }
                                },
                              ),
                              const SizedBox(width: 6),
                              _buildStatBox(
                                colorScheme: colorScheme,
                                title: 'مقترنة',
                                value: lockedStr,
                                icon: Icons.lock_rounded,
                                isHighlight: _deviceStatusFilter == 'locked',
                                onTap: () {
                                  setState(() {
                                    _deviceStatusFilter = 'locked';
                                    _deviceSearchQuery = '';
                                    _deviceSearchController.clear();
                                  });
                                  if (_cachedDelegatesList == null) {
                                    _fetchDelegatesIfNeeded();
                                  }
                                },
                              ),
                              const SizedBox(width: 6),
                              _buildStatBox(
                                colorScheme: colorScheme,
                                title: 'متاحة',
                                value: unboundStr,
                                icon: Icons.lock_open_rounded,
                                isHighlight: _deviceStatusFilter == 'unbound',
                                onTap: () {
                                  setState(() {
                                    _deviceStatusFilter = 'unbound';
                                    _deviceSearchQuery = '';
                                    _deviceSearchController.clear();
                                  });
                                  if (_cachedDelegatesList == null) {
                                    _fetchDelegatesIfNeeded();
                                  }
                                },
                              ),
                              const SizedBox(width: 6),
                              _buildStatBox(
                                colorScheme: colorScheme,
                                title: 'طلبات فك',
                                value: '${pendingRequests.length}',
                                icon: Icons.phonelink_erase_rounded,
                                isHighlight: isRequestsView,
                                highlightColor: pendingRequests.isNotEmpty ? colorScheme.errorContainer : colorScheme.primaryContainer,
                                onHighlightColor: pendingRequests.isNotEmpty ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer,
                                onTap: () => setState(() {
                                  _deviceStatusFilter = 'requests';
                                  _deviceSearchQuery = '';
                                  _deviceSearchController.clear();
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );

                  if (isDesktop) {
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child: deviceBanner,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: _buildTabSwitcherCard(
                              colorScheme,
                              isArabic,
                              pendingRequestsCount: pendingRequests.length,
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    return Column(
                      children: [
                        _buildTabSwitcherCard(
                          colorScheme,
                          isArabic,
                          pendingRequestsCount: pendingRequests.length,
                          isHorizontal: true,
                        ),
                        const SizedBox(height: 10),
                        deviceBanner,
                      ],
                    );
                  }
                },
              ),

              const SizedBox(height: 12),

              // 2. Search Bar with Light/Smaller Hint Style
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _deviceSearchController,
                        style: TextStyle(fontSize: 13.5, color: colorScheme.onSurface),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (val) {
                          setState(() => _deviceSearchQuery = val.trim());
                        },
                        decoration: InputDecoration(
                          hintText: isArabic
                              ? (isRequestsView
                                  ? 'بحث بالاسم، الهاتف، أو الجهاز...'
                                  : 'بحث بالاسم، الهاتف، الشركة، أو الجهاز...')
                              : 'Search delegate, phone, company, or device...',
                          hintStyle: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w300,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 19,
                            color: colorScheme.primary,
                          ),
                          suffixIcon: _deviceSearchController.text.isNotEmpty || _deviceSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  tooltip: isArabic ? 'مسح البحث' : 'Clear search',
                                  onPressed: () {
                                    _deviceSearchController.clear();
                                    setState(() => _deviceSearchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHigh,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton.filled(
                      onPressed: () {
                        setState(() => _deviceSearchQuery = _deviceSearchController.text.trim());
                        FocusScope.of(context).unfocus();
                      },
                      icon: const Icon(Icons.search_rounded, size: 19),
                      tooltip: isArabic ? 'بحث' : 'Search',
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
              if (_deviceSearchQuery.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.filter_alt_rounded, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isArabic
                              ? 'نتائج البحث عن: "$_deviceSearchQuery" ($currentCount ${isRequestsView ? 'طلب' : 'مندوب'})'
                              : 'Results for "$_deviceSearchQuery" ($currentCount items)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          _deviceSearchController.clear();
                          setState(() => _deviceSearchQuery = '');
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isArabic ? 'إلغاء' : 'Clear',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.error,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.close_rounded, size: 14, color: colorScheme.error),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // 3. Dropdown Menu Filter
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isRequestsView && pendingRequests.isNotEmpty
                        ? colorScheme.error.withValues(alpha: 0.5)
                        : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    width: isRequestsView && pendingRequests.isNotEmpty ? 1.5 : 1.0,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _deviceStatusFilter,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(14),
                    icon: Icon(
                      Icons.arrow_drop_down_rounded,
                      color: isRequestsView && pendingRequests.isNotEmpty
                          ? colorScheme.error
                          : colorScheme.primary,
                      size: 28,
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: 'requests',
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: pendingRequests.isNotEmpty
                                    ? colorScheme.errorContainer
                                    : colorScheme.primaryContainer.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.phonelink_erase_rounded,
                                size: 16,
                                color: pendingRequests.isNotEmpty
                                    ? colorScheme.onErrorContainer
                                    : colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'طلبات فك الارتباط (${pendingRequests.length})',
                                style: TextStyle(
                                  fontWeight: isRequestsView ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                  color: isRequestsView && pendingRequests.isNotEmpty
                                      ? colorScheme.error
                                      : colorScheme.onSurface,
                                ),
                              ),
                            ),
                            if (pendingRequests.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.error,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${pendingRequests.length} معلق',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      DropdownMenuItem<String>(
                        value: 'locked',
                        child: Row(
                          children: [
                            Icon(Icons.lock_rounded, size: 18, color: colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _cachedLockedCount != null
                                    ? 'الأجهزة المقترنة ($_cachedLockedCount)'
                                    : 'الأجهزة المقترنة',
                                style: TextStyle(
                                  fontWeight: _deviceStatusFilter == 'locked' ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      DropdownMenuItem<String>(
                        value: 'unbound',
                        child: Row(
                          children: [
                            Icon(Icons.lock_open_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _cachedUnboundCount != null
                                    ? 'الأجهزة المتاحة للربط ($_cachedUnboundCount)'
                                    : 'الأجهزة المتاحة للربط',
                                style: TextStyle(
                                  fontWeight: _deviceStatusFilter == 'unbound' ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      DropdownMenuItem<String>(
                        value: 'all',
                        child: Row(
                          children: [
                            Icon(Icons.people_outline_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _cachedTotalDelegatesCount != null
                                    ? 'كافة المناديب والأجهزة ($_cachedTotalDelegatesCount)'
                                    : 'كافة المناديب والأجهزة',
                                style: TextStyle(
                                  fontWeight: _deviceStatusFilter == 'all' ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _deviceStatusFilter = val;
                          _deviceSearchQuery = '';
                          _deviceSearchController.clear();
                        });
                        if (val != 'requests' && _cachedDelegatesList == null) {
                          _fetchDelegatesIfNeeded();
                        }
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 4. Section Content
              if (isRequestsView) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'طلبات فك الارتباط قيد المراجعة (${filteredRequests.length})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (pendingRequests.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'تتطلب اتخاذ إجراء',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (filteredRequests.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            pendingRequests.isEmpty
                                ? Icons.task_alt_rounded
                                : Icons.search_off_rounded,
                            size: 48,
                            color: pendingRequests.isEmpty ? colorScheme.primary : colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            pendingRequests.isEmpty
                                ? 'لا توجد طلبات فك ارتباط معلقة حالياً'
                                : 'لا توجد طلبات فك مطابقة للبحث',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (pendingRequests.isEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'كافة حسابات وأجهزة المناديب منتظمة، ويمكنك استعراض وإدارة قائمة الأجهزة بالكامل.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                setState(() {
                                  _deviceStatusFilter = 'all';
                                });
                                _fetchDelegatesIfNeeded();
                              },
                              icon: const Icon(Icons.people_outline_rounded, size: 18),
                              label: const Text('استعراض كافة المناديب والأجهزة'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredRequests.length,
                    itemBuilder: (context, index) {
                      final req = filteredRequests[index];
                      return _buildUnbindRequestCard(context, colorScheme, req, isArabic);
                    },
                  ),
              ] else ...[
                if (_isLoadingDelegates)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(36),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 14),
                          Text(
                            'جاري تحميل بيانات أجهزة المناديب...',
                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_cachedDelegatesList == null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.cloud_download_outlined, size: 48, color: colorScheme.primary),
                          const SizedBox(height: 12),
                          Text(
                            'اضغط لتحميل بيانات أجهزة المناديب',
                            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: () => _fetchDelegatesIfNeeded(forceRefresh: true),
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('تحميل البيانات الآن'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'قائمة المناديب وحالة الأجهزة (${filteredDelegates.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _fetchDelegatesIfNeeded(forceRefresh: true),
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: 'تحديث بيانات المناديب',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (filteredDelegates.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.person_search_rounded, size: 48, color: colorScheme.outlineVariant),
                            const SizedBox(height: 12),
                            Text(
                              'لا يوجد مناديب مطابقين للبحث',
                              style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredDelegates.length,
                      itemBuilder: (context, index) {
                        final item = filteredDelegates[index];
                        return _buildDelegateDeviceCard(context, colorScheme, item);
                      },
                    ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildUnbindRequestCard(
    BuildContext context,
    ColorScheme colorScheme,
    Map<String, dynamic> req,
    bool isArabic,
  ) {
    final name = (req['delegateName'] ?? 'مندوب').toString();
    final phone = (req['delegatePhone'] ?? '').toString();
    final company = (req['companyName'] ?? '').toString();
    final boundDevice = (req['boundDeviceModel'] ?? 'غير محدد').toString();
    final reqDevice = (req['requestedDeviceModel'] ?? 'غير محدد').toString();
    final reason = (req['reason'] ?? '').toString();

    DateTime? reqDate;
    if (req['createdAt'] is Timestamp) {
      reqDate = (req['createdAt'] as Timestamp).toDate();
    } else if (req['createdAt'] != null) {
      reqDate = DateTime.tryParse(req['createdAt'].toString());
    }
    final reqDateStr = reqDate != null ? DateFormat('yyyy-MM-dd hh:mm a').format(reqDate) : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.error.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Delegate Info Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                  radius: 20,
                  child: const Icon(Icons.phonelink_erase_rounded, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          phone,
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (company.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      company,
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 10),

            // Devices Comparison Box
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.phone_locked_rounded, size: 16, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Text(
                        'الجهاز المقترن حالياً: ',
                        style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                      ),
                      Expanded(
                        child: Text(
                          boundDevice,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.phone_android_rounded, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'الجهاز الجديد المطلوب: ',
                        style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                      ),
                      Expanded(
                        child: Text(
                          reqDevice,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'السبب: $reason',
                  style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],

            if (reqDateStr.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: isArabic ? Alignment.centerLeft : Alignment.centerRight,
                child: Text(
                  'تاريخ الطلب: $reqDateStr',
                  style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _rejectUnbindRequest(req),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text(DeviceUnbindLabels.reject, style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _approveUnbindRequest(req),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text(DeviceUnbindLabels.approve, style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveUnbindRequest(
    Map<String, dynamic> requestData,
  ) async {
    final requestId = requestData['docId']?.toString() ?? '';
    final delegateUid = requestData['delegateUid']?.toString() ?? '';
    final delegateName = requestData['delegateName']?.toString() ?? 'المندوب';
    final orgId = requestData['organizationUID']?.toString() ?? widget.delegate.organizationUID;
    final compId = requestData['companyUID']?.toString();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text(DeviceUnbindLabels.approveTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'هل تريد الموافقة على طلب فك ارتباط جهاز "$delegateName"؟\n\n'
          'سيتم إزالة قفل الجهاز القديم، وإرسال إشعار للمندوب ليتمكن من تسجيل الدخول من جهازه الجديد واعتماده تلقائياً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(DeviceUnbindLabels.approve),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await DeviceBindingService.approveUnbindRequest(
        requestId: requestId,
        delegateUid: delegateUid,
        organizationUID: orgId,
        companyUID: compId,
        adminUid: widget.delegate.uid,
        adminName: widget.delegate.fullName.isNotEmpty ? widget.delegate.fullName : widget.delegate.firstName,
      );

      if (_cachedDelegatesList != null) {
        final index = _cachedDelegatesList!.indexWhere(
          (d) => d['uid'] == delegateUid || d['docId'] == delegateUid,
        );
        if (index != -1) {
          final oldBound = _cachedDelegatesList![index]['boundDeviceId']?.toString().trim() ?? '';
          _cachedDelegatesList![index]['boundDeviceId'] = '';
          _cachedDelegatesList![index]['boundDeviceModel'] = '';
          _cachedDelegatesList![index]['boundDeviceBrand'] = '';
          _cachedDelegatesList![index]['boundDeviceLockedAt'] = null;
          if (oldBound.isNotEmpty) {
            final currentLocked = _cachedLockedCount ?? 0;
            final currentUnbound = _cachedUnboundCount ?? 0;
            final newLocked = (currentLocked - 1).clamp(0, 999999);
            final newUnbound = currentUnbound + 1;
            if (mounted) {
              setState(() {
                _cachedLockedCount = newLocked;
                _cachedUnboundCount = newUnbound;
              });
            }
            SharedPreferences.getInstance().then((prefs) {
              prefs.setInt('cached_device_locked_count', newLocked);
              prefs.setInt('cached_device_unbound_count', newUnbound);
            }).ignore();
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت الموافقة وفك ارتباط جهاز "$delegateName" بنجاح'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء فك الارتباط: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _rejectUnbindRequest(
    Map<String, dynamic> requestData,
  ) async {
    final requestId = requestData['docId']?.toString() ?? '';
    final delegateUid = requestData['delegateUid']?.toString() ?? '';
    final delegateName = requestData['delegateName']?.toString() ?? 'المندوب';
    final reasonController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.cancel_outlined, color: Theme.of(ctx).colorScheme.error),
            const SizedBox(width: 8),
            const Text(DeviceUnbindLabels.rejectTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل أنت متأكد من رفض طلب فك الارتباط للمندوب "$delegateName"؟'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'سبب الرفض (اختياري)',
                hintText: 'مثال: يلزم مراجعة الإدارة أولاً',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(DeviceUnbindLabels.confirmReject),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await DeviceBindingService.rejectUnbindRequest(
        requestId: requestId,
        delegateUid: delegateUid,
        adminUid: widget.delegate.uid,
        adminName: widget.delegate.fullName.isNotEmpty ? widget.delegate.fullName : widget.delegate.firstName,
        reason: reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم رفض طلب فك ارتباط "$delegateName"'),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء رفض الطلب: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildDelegateDeviceCard(
    BuildContext context,
    ColorScheme colorScheme,
    Map<String, dynamic> delegateData,
  ) {
    final name = (delegateData['fullName'] ?? delegateData['firstName'] ?? 'مندوب').toString();
    final phone = (delegateData['phoneNumber'] ?? '').toString();
    final company = (delegateData['companyName'] ?? '').toString();
    final boundDeviceModel = (delegateData['boundDeviceModel'] as String?)?.trim() ?? '';
    final boundDeviceId = (delegateData['boundDeviceId'] as String?)?.trim() ?? '';
    final isLocked = boundDeviceId.isNotEmpty;
    final delegateUid = delegateData['docId']?.toString() ?? delegateData['uid']?.toString() ?? '';
    final orgId = delegateData['organizationUID']?.toString();
    final compId = delegateData['companyUID']?.toString();

    DateTime? boundAt;
    if (delegateData['deviceBoundAt'] is Timestamp) {
      boundAt = (delegateData['deviceBoundAt'] as Timestamp).toDate();
    } else if (delegateData['deviceBoundAt'] != null) {
      boundAt = DateTime.tryParse(delegateData['deviceBoundAt'].toString());
    }

    final boundDateStr = boundAt != null ? DateFormat('yyyy-MM-dd hh:mm a').format(boundAt) : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isLocked ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                  foregroundColor: isLocked ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                  radius: 18,
                  child: Icon(
                    isLocked ? Icons.phonelink_lock_rounded : Icons.phonelink_setup_rounded,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          phone,
                          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (company.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      company,
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            if (isLocked) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone_android_rounded, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الجهاز المقترن: $boundDeviceModel',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (boundDateStr.isNotEmpty)
                            Text(
                              'تاريخ الاعتماد: $boundDateStr',
                              style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => _resetDelegateDevice(
                        context,
                        delegateUid,
                        name,
                        orgId: orgId,
                        compId: compId,
                      ),
                      icon: const Icon(Icons.phonelink_erase_rounded, size: 18),
                      tooltip: 'فك ربط الجهاز',
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_open_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'متاح للربط: سيتم اعتماد أول هاتف يسجل منه المندوب تلقائياً.',
                        style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
