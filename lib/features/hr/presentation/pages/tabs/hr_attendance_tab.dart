import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/utils/file_download_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/core/widgets/tashil_icon_button.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;

/// Model representing a delegate's attendance record on a specific date for HR
class HRAttendanceRecord {
  final Delegate delegate;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String? branchName;
  final double? latitude;
  final double? longitude;
  final String? deviceInfo;
  final double? distanceMeters;
  final bool? isInsideGeofence;

  const HRAttendanceRecord({
    required this.delegate,
    this.checkInTime,
    this.checkOutTime,
    this.branchName,
    this.latitude,
    this.longitude,
    this.deviceInfo,
    this.distanceMeters,
    this.isInsideGeofence,
  });

  bool get isPresent => checkInTime != null && checkOutTime == null;
  bool get isDeparted => checkInTime != null && checkOutTime != null;
  bool get isAbsent => checkInTime == null;
}

class HRAttendanceTab extends StatefulWidget {
  final Delegate hrDelegate;

  const HRAttendanceTab({super.key, required this.hrDelegate});

  @override
  State<HRAttendanceTab> createState() => _HRAttendanceTabState();
}

class _HRAttendanceTabState extends State<HRAttendanceTab> {
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();

  String _statusFilter = 'all'; // 'all', 'present', 'departed', 'absent'
  String _selectedBranch = 'all';
  bool _isTableView = true; // Table view is the primary default per user specification

  bool _isLoading = true;
  String? _errorMessage;

  List<Delegate> _companyDelegates = [];
  Map<String, Branch> _branchesByName = {};
  List<HRAttendanceRecord> _records = [];
  Set<String> _availableBranches = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Load branches to calculate geofence distances accurately
      final branchesSnap =
          await FirebaseFirestore.instance.collection('branches').get();
      final Map<String, Branch> branchesMap = {};
      for (final doc in branchesSnap.docs) {
        final data = doc.data();
        final name = (data['branchName'] ?? data['name'] ?? '').toString();
        if (name.isNotEmpty) {
          final lat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
          final lng = (data['longitude'] as num?)?.toDouble() ?? 0.0;
          final radius = (data['geofenceRadius'] as num?)?.toDouble() ?? 100.0;
          branchesMap[name.toLowerCase().trim()] = Branch(
            id: doc.id,
            branchName: name,
            latitude: lat,
            longitude: lng,
            geofenceRadius: radius,
          );
        }
      }
      _branchesByName = branchesMap;

      // 2. Load company delegates
      final delegatesResult = await di.sl<GetCompanyDelegates>()(
        GetCompanyDelegatesParams(
          organizationUID: widget.hrDelegate.organizationUID,
          companyUID: widget.hrDelegate.companyUID,
        ),
      );

      delegatesResult.fold(
        (failure) {
          _errorMessage = failure.message;
        },
        (delegates) {
          _companyDelegates = delegates;
        },
      );

      await _fetchAttendanceForSelectedDate();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'حدث خطأ أثناء تحميل البيانات: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchAttendanceForSelectedDate() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        0,
        0,
        0,
      );
      final endOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      );

      // Query attendance logs for this company
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection(kAttendanceCollection)
          .where('companyId', isEqualTo: widget.hrDelegate.companyUID);

      final snapshot = await query.get();

      // Group logs by delegate ID
      final Map<String, List<Map<String, dynamic>>> logsByDelegate = {};
      final Set<String> branchNames = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final ts = data['timestamp'];
        if (ts is Timestamp) {
          final date = ts.toDate();
          if (date.isBefore(startOfDay) || date.isAfter(endOfDay)) {
            continue;
          }
        }

        final delegateId =
            (data['delegateId'] ?? data['userId'] ?? '').toString();
        if (delegateId.isNotEmpty) {
          logsByDelegate.putIfAbsent(delegateId, () => []).add(data);
        }

        final bName = (data['branchName'] ?? '').toString().trim();
        if (bName.isNotEmpty) {
          branchNames.add(bName);
        }
      }

      // Build attendance records for each delegate
      final List<HRAttendanceRecord> list = [];

      for (final d in _companyDelegates) {
        final logs = logsByDelegate[d.uid] ?? [];
        DateTime? checkIn;
        DateTime? checkOut;
        String? branch;
        double? lat;
        double? lng;
        String? device;

        for (final log in logs) {
          final type = (log['type'] ?? '').toString();
          final ts = log['timestamp'];
          DateTime? logTime;
          if (ts is Timestamp) logTime = ts.toDate();

          if (type == 'check_in') {
            if (checkIn == null ||
                (logTime != null && logTime.isBefore(checkIn))) {
              checkIn = logTime;
              branch = log['branchName']?.toString();
              device = log['deviceInfo']?.toString();
              final loc = log['location'];
              if (loc is Map) {
                lat = (loc['latitude'] as num?)?.toDouble();
                lng = (loc['longitude'] as num?)?.toDouble();
              }
            }
          } else if (type == 'check_out') {
            if (checkOut == null ||
                (logTime != null && logTime.isAfter(checkOut))) {
              checkOut = logTime;
            }
          }
        }

        // Calculate anti-fraud geofence status
        double? distance;
        bool? isInside;

        if (lat != null && lng != null && branch != null) {
          final matchedBranch = _branchesByName[branch.toLowerCase().trim()];
          if (matchedBranch != null &&
              matchedBranch.latitude != 0.0 &&
              matchedBranch.longitude != 0.0) {
            distance = Geolocator.distanceBetween(
              lat,
              lng,
              matchedBranch.latitude,
              matchedBranch.longitude,
            );
            isInside = distance <= matchedBranch.geofenceRadius;
          }
        }

        list.add(
          HRAttendanceRecord(
            delegate: d,
            checkInTime: checkIn,
            checkOutTime: checkOut,
            branchName: branch,
            latitude: lat,
            longitude: lng,
            deviceInfo: device,
            distanceMeters: distance,
            isInsideGeofence: isInside,
          ),
        );
      }

      // Sort: Present first, then Departed, then Absent
      list.sort((a, b) {
        if (a.isPresent && !b.isPresent) return -1;
        if (!a.isPresent && b.isPresent) return 1;
        if (a.isDeparted && !b.isDeparted) return -1;
        if (!a.isDeparted && b.isDeparted) return 1;
        return a.delegate.fullName.compareTo(b.delegate.fullName);
      });

      if (mounted) {
        setState(() {
          _records = list;
          _availableBranches = branchNames;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'فشل تحديث بيانات الحضور: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<HRAttendanceRecord> get _filteredRecords {
    final query = _searchController.text.trim().toLowerCase();
    return _records.where((record) {
      // 1. Search Query
      if (query.isNotEmpty) {
        final matchesName =
            record.delegate.fullName.toLowerCase().contains(query);
        final matchesPhone = record.delegate.phoneNumber.contains(query);
        final matchesBranch =
            record.branchName?.toLowerCase().contains(query) ?? false;
        if (!matchesName && !matchesPhone && !matchesBranch) return false;
      }

      // 2. Status Filter
      if (_statusFilter == 'present' && !record.isPresent) return false;
      if (_statusFilter == 'departed' && !record.isDeparted) return false;
      if (_statusFilter == 'absent' && !record.isAbsent) return false;

      // 3. Branch Filter
      if (_selectedBranch != 'all' && record.branchName != _selectedBranch) {
        return false;
      }

      return true;
    }).toList();
  }

  // --- Export Attendance to CSV ---
  Future<void> _exportToCSV() async {
    final filtered = _filteredRecords;
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سجلات لتصديرها.')),
      );
      return;
    }

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final csvHeader =
          '\uFEFFاسم المندوب,رقم الهاتف,التاريخ,وقت الحضور,وقت الانصراف,الفرع,حالة النطاق الجغرافي,المسافة المقدرة بالمتر,حالة الحضور,بيانات الجهاز\n';

      final csvRows = filtered.map((r) {
        final name = r.delegate.fullName.replaceAll(',', ' ');
        final phone = r.delegate.phoneNumber;
        final checkIn = r.checkInTime != null
            ? DateFormat('HH:mm:ss').format(r.checkInTime!)
            : 'لم يسجل';
        final checkOut = r.checkOutTime != null
            ? DateFormat('HH:mm:ss').format(r.checkOutTime!)
            : 'لم ينصرف';
        final branch = (r.branchName ?? 'غير محدد').replaceAll(',', ' ');

        String geofence = 'غير متوفر';
        if (r.isInsideGeofence == true) {
          geofence = 'داخل النطاق';
        } else if (r.isInsideGeofence == false) {
          geofence = 'خارج النطاق';
        }

        final distance = r.distanceMeters != null
            ? '${r.distanceMeters!.toStringAsFixed(1)}م'
            : '-';

        String status = 'غائب';
        if (r.isPresent) {
          status = 'حاضر الآن';
        } else if (r.isDeparted) {
          status = 'انصرف';
        }

        final device = (r.deviceInfo ?? '-').replaceAll(',', ' ');

        return '$name,$phone,$dateStr,$checkIn,$checkOut,$branch,$geofence,$distance,$status,$device';
      }).join('\n');

      final csvContent = '$csvHeader$csvRows';
      final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'hr_attendance_${dateStr}_$nowStr.csv';

      await FileDownloadHelper.downloadString(
        content: csvContent,
        fileName: fileName,
        mimeType: 'text/csv;charset=utf-8',
        shareText: 'تقرير حضور وانصراف شركة ${widget.hrDelegate.companyName} ($dateStr)',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تصدير ملف الحضور بنجاح'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في تصدير التقرير: $e')),
        );
      }
    }
  }

  void _openGoogleMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _callPhone(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openWhatsApp(String phone) async {
    if (phone.isEmpty) return;
    var cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '20${cleanPhone.substring(1)}';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 900;
    final isDesktop = screenWidth >= 1050;

    final totalCount = _records.length;
    final presentCount = _records.where((r) => r.isPresent).length;
    final departedCount = _records.where((r) => r.isDeparted).length;
    final absentCount = _records.where((r) => r.isAbsent).length;

    final isToday = _isSameDay(_selectedDate, DateTime.now());
    final filtered = _filteredRecords;

    return RefreshIndicator(
      onRefresh: _fetchAttendanceForSelectedDate,
      child: Column(
        children: [
          // ── Top Header Section (KPI Cards + Date Selector) ──
          if (isWideScreen) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 4 KPI Metrics Cards on the Right (Primary content)
                  Expanded(
                    child: Row(
                      children: [
                        _buildKpiCard(
                          title: 'إجمالي',
                          count: totalCount,
                          icon: Icons.people_alt_rounded,
                          color: colorScheme.primary,
                          theme: theme,
                          isWide: true,
                        ),
                        const SizedBox(width: 8),
                        _buildKpiCard(
                          title: 'حاضر الآن',
                          count: presentCount,
                          icon: Icons.check_circle_rounded,
                          color: const Color(0xFF2E7D32),
                          theme: theme,
                          isWide: true,
                        ),
                        const SizedBox(width: 8),
                        _buildKpiCard(
                          title: 'انصرف',
                          count: departedCount,
                          icon: Icons.timelapse_rounded,
                          color: const Color(0xFFE65100),
                          theme: theme,
                          isWide: true,
                        ),
                        const SizedBox(width: 8),
                        _buildKpiCard(
                          title: 'لم يحضر',
                          count: absentCount,
                          icon: Icons.cancel_outlined,
                          color: colorScheme.outline,
                          theme: theme,
                          isWide: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Compact Date Controller on the Left
                  _buildDateSelector(theme, colorScheme, isToday),
                ],
              ),
            ),
          ] else ...[
            // Mobile: Date Selector on top, KPI Cards below
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _buildDateSelector(theme, colorScheme, isToday, isFullWidth: true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Row(
                children: [
                  _buildKpiCard(
                    title: 'إجمالي',
                    count: totalCount,
                    icon: Icons.people_alt_rounded,
                    color: colorScheme.primary,
                    theme: theme,
                    isWide: false,
                  ),
                  const SizedBox(width: 6),
                  _buildKpiCard(
                    title: 'حاضر الآن',
                    count: presentCount,
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF2E7D32),
                    theme: theme,
                    isWide: false,
                  ),
                  const SizedBox(width: 6),
                  _buildKpiCard(
                    title: 'انصرف',
                    count: departedCount,
                    icon: Icons.timelapse_rounded,
                    color: const Color(0xFFE65100),
                    theme: theme,
                    isWide: false,
                  ),
                  const SizedBox(width: 6),
                  _buildKpiCard(
                    title: 'لم يحضر',
                    count: absentCount,
                    icon: Icons.cancel_outlined,
                    color: colorScheme.outline,
                    theme: theme,
                    isWide: false,
                  ),
                ],
              ),
            ),
          ],

          // ── Search, Branch, Status M3 Button Group & Controls ──
          if (isDesktop) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 270,
                    child: _buildSearchBar(colorScheme),
                  ),
                  if (_availableBranches.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    _buildBranchSelector(theme, colorScheme),
                  ],
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildStatusButtonGroup(
                        totalCount,
                        presentCount,
                        departedCount,
                        absentCount,
                        theme,
                        colorScheme,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildCsvExportButton(),
                  const SizedBox(width: 8),
                  _buildViewModeToggle(colorScheme),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSearchBar(colorScheme),
                  ),
                  const SizedBox(width: 8),
                  _buildCsvExportButton(),
                  const SizedBox(width: 8),
                  _buildViewModeToggle(colorScheme),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  if (_availableBranches.isNotEmpty) ...[
                    _buildBranchSelector(theme, colorScheme),
                    const SizedBox(width: 10),
                  ],
                  _buildStatusButtonGroup(
                    totalCount,
                    presentCount,
                    departedCount,
                    absentCount,
                    theme,
                    colorScheme,
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 1),

          // ── Attendance List ──
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 48, color: colorScheme.error),
                            const SizedBox(height: 12),
                            Text(_errorMessage!,
                                style: TextStyle(color: colorScheme.error)),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: _loadInitialData,
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_busy_rounded,
                                    size: 56,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text(
                                  'لا توجد سجلات حضور تطابق البحث في هذا اليوم',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _isTableView
                            ? _buildTableView(filtered, theme, colorScheme)
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  if (constraints.maxWidth > 750) {
                                    return GridView.builder(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      gridDelegate:
                                          const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 600,
                                        mainAxisExtent: 235,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                      ),
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) {
                                        return _buildAttendanceCard(
                                          filtered[index],
                                          theme,
                                          colorScheme,
                                        );
                                      },
                                    );
                                  }

                                  return ListView.separated(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    itemCount: filtered.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      return _buildAttendanceCard(
                                        filtered[index],
                                        theme,
                                        colorScheme,
                                      );
                                    },
                                  );
                                },
                              ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableView(
    List<HRAttendanceRecord> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    const double tableMinWidth = 1100.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final contentWidth =
                availableWidth > tableMinWidth ? availableWidth : tableMinWidth;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  children: [
                    // ── Table Header ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        border: Border(
                          bottom: BorderSide(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          _buildHeaderCell('المندوب / المروج', flex: 22, theme: theme, colorScheme: colorScheme),
                          _buildHeaderCell('الحالة', flex: 12, theme: theme, colorScheme: colorScheme),
                          _buildHeaderCell('الفرع', flex: 15, theme: theme, colorScheme: colorScheme),
                          _buildHeaderCell('الحضور', flex: 10, theme: theme, colorScheme: colorScheme),
                          _buildHeaderCell('الانصراف', flex: 10, theme: theme, colorScheme: colorScheme),
                          _buildHeaderCell('النطاق الجغرافي والمسافة', flex: 18, theme: theme, colorScheme: colorScheme),
                          _buildHeaderCell('الجهاز', flex: 13, theme: theme, colorScheme: colorScheme),
                          _buildHeaderCell('الإجراءات', flex: 14, theme: theme, colorScheme: colorScheme, isCenter: true),
                        ],
                      ),
                    ),

                    // ── Table Rows ──
                    Expanded(
                      child: ListView.separated(
                        itemCount: records.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          thickness: 1,
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.25),
                        ),
                        itemBuilder: (context, index) {
                          return _buildTableRow(
                            records[index],
                            index.isEven,
                            theme,
                            colorScheme,
                            isWide: availableWidth >= 1050,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderCell(
    String title, {
    required int flex,
    required ThemeData theme,
    required ColorScheme colorScheme,
    bool isCenter = false,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        title,
        textAlign: isCenter ? TextAlign.center : TextAlign.start,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildTableRow(
    HRAttendanceRecord record,
    bool isEven,
    ThemeData theme,
    ColorScheme colorScheme, {
    bool isWide = false,
  }) {
    final isPresent = record.isPresent;
    final isDeparted = record.isDeparted;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isPresent) {
      statusColor = const Color(0xFF2E7D32);
      statusText = 'حاضر الآن';
      statusIcon = Icons.check_circle_rounded;
    } else if (isDeparted) {
      statusColor = const Color(0xFFE65100);
      statusText = 'انصرف اليوم';
      statusIcon = Icons.timelapse_rounded;
    } else {
      statusColor = colorScheme.outline;
      statusText = 'لم يسجل حضور';
      statusIcon = Icons.schedule_rounded;
    }

    final posName = record.delegate.position == DelegatePosition.supervisor
        ? 'مشرف'
        : 'مندوب / مروج';

    final checkInStr = record.checkInTime != null
        ? DateFormat('hh:mm a', 'ar').format(record.checkInTime!)
        : '-';

    final checkOutStr = record.checkOutTime != null
        ? DateFormat('hh:mm a', 'ar').format(record.checkOutTime!)
        : '-';

    return Material(
      color: isEven
          ? colorScheme.surface
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
      child: InkWell(
        hoverColor: colorScheme.primary.withValues(alpha: 0.05),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AttendanceScreen(
                delegate: record.delegate,
                viewOnly: true,
              ),
            ),
          );
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: isWide ? 12 : 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Delegate (Avatar + Name + Phone)
              Expanded(
                flex: 22,
                child: Row(
                  children: [
                    AppAvatar(
                      imageUrl: record.delegate.personalPhotoUrl,
                      fallbackText: record.delegate.fullName,
                      radius: isWide ? 20 : 17,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            record.delegate.fullName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  record.delegate.phoneNumber,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Text(
                                ' • $posName',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Status Badge
              Expanded(
                flex: 12,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Branch
              Expanded(
                flex: 15,
                child: Row(
                  children: [
                    Icon(
                      Icons.storefront_rounded,
                      size: 15,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        record.branchName ?? 'غير محدد',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // 4. Check-in
              Expanded(
                flex: 10,
                child: record.checkInTime != null
                    ? Row(
                        children: [
                          const Icon(Icons.login_rounded,
                              size: 14, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 4),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              checkInStr,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2E7D32),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        '-',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
              ),

              // 5. Check-out
              Expanded(
                flex: 10,
                child: record.checkOutTime != null
                    ? Row(
                        children: [
                          const Icon(Icons.logout_rounded,
                              size: 14, color: Color(0xFFE65100)),
                          const SizedBox(width: 4),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              checkOutStr,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFE65100),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        '-',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
              ),

              // 6. Geofence
              Expanded(
                flex: 18,
                child: Row(
                  children: [
                    Icon(
                      record.isInsideGeofence == true
                          ? Icons.verified_user_rounded
                          : record.isInsideGeofence == false
                              ? Icons.warning_amber_rounded
                              : Icons.location_off_outlined,
                      size: 14,
                      color: record.isInsideGeofence == true
                          ? const Color(0xFF2E7D32)
                          : record.isInsideGeofence == false
                              ? const Color(0xFFC62828)
                              : colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        record.isInsideGeofence == true
                            ? 'داخل النطاق (${record.distanceMeters!.toStringAsFixed(0)}م)'
                            : record.isInsideGeofence == false
                                ? 'خارج (${record.distanceMeters!.toStringAsFixed(0)}م)'
                                : 'لم تسجل',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: record.isInsideGeofence == true
                              ? const Color(0xFF2E7D32)
                              : record.isInsideGeofence == false
                                  ? const Color(0xFFC62828)
                                  : colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (record.latitude != null && record.longitude != null)
                      TashilIconButton.standard(
                        icon: Icons.map_outlined,
                        tooltip: 'عرض على الخريطة',
                        size: 28,
                        iconSize: 15,
                        onPressed: () => _openGoogleMaps(
                          record.latitude!,
                          record.longitude!,
                        ),
                      ),
                  ],
                ),
              ),

              // 7. Device Info
              Expanded(
                flex: 13,
                child: (record.deviceInfo != null &&
                        record.deviceInfo!.trim().isNotEmpty)
                    ? Row(
                        children: [
                          Icon(
                            Icons.smartphone_rounded,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              record.deviceInfo!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        '-',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
              ),

              // 8. Actions (Official Google Material Icons in Circular M3 Icon Buttons)
              Expanded(
                flex: 14,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (record.delegate.phoneNumber.isNotEmpty) ...[
                      TashilIconButton.tonal(
                        icon: Icons.call_outlined,
                        tooltip: 'اتصال هاتفي',
                        size: 34,
                        iconSize: 17,
                        onPressed: () =>
                            _callPhone(record.delegate.phoneNumber),
                      ),
                      const SizedBox(width: 6),
                      TashilIconButton.tonal(
                        icon: Icons.chat_outlined,
                        tooltip: 'محادثة واتساب',
                        size: 34,
                        iconSize: 17,
                        onPressed: () =>
                            _openWhatsApp(record.delegate.phoneNumber),
                      ),
                      const SizedBox(width: 6),
                    ],
                    TashilIconButton.tonal(
                      icon: Icons.history_rounded,
                      tooltip: 'السجل الشهري',
                      size: 34,
                      iconSize: 17,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AttendanceScreen(
                              delegate: record.delegate,
                              viewOnly: true,
                            ),
                          ),
                        );
                      },
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

  Widget _buildKpiCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required ThemeData theme,
    bool isWide = false,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: isWide ? 12 : 8,
          horizontal: isWide ? 10 : 4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.22),
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: isWide ? 18 : 14, color: color),
                SizedBox(width: isWide ? 6 : 3),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: isWide ? 12 : 10,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isWide ? 4 : 2),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '$count',
                style: (isWide
                        ? theme.textTheme.headlineSmall
                        : theme.textTheme.titleMedium)
                    ?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isToday, {
    bool isFullWidth = false,
  }) {
    final dateStr = DateFormat('EEEE، d MMMM yyyy', 'ar').format(_selectedDate);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous Day Button
          TashilIconButton.standard(
            icon: Icons.chevron_right_rounded,
            tooltip: 'اليوم السابق',
            size: 32,
            iconSize: 20,
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
              _fetchAttendanceForSelectedDate();
            },
          ),
          const SizedBox(width: 2),

          // Date Display Button (Click to Pick)
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2023),
                  lastDate: DateTime.now().add(const Duration(days: 7)),
                );
                if (picked != null && !_isSameDay(picked, _selectedDate)) {
                  setState(() => _selectedDate = picked);
                  _fetchAttendanceForSelectedDate();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 17,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      dateStr,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),

          // Next Day Button
          TashilIconButton.standard(
            icon: Icons.chevron_left_rounded,
            tooltip: 'اليوم التالي',
            size: 32,
            iconSize: 20,
            onPressed: isToday
                ? null
                : () {
                    setState(() {
                      _selectedDate = _selectedDate.add(const Duration(days: 1));
                    });
                    _fetchAttendanceForSelectedDate();
                  },
          ),

          if (!isToday) ...[
            const SizedBox(width: 4),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                setState(() => _selectedDate = DateTime.now());
                _fetchAttendanceForSelectedDate();
              },
              child: const Text('اليوم',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return SizedBox(
      height: 44,
      child: SearchBar(
        controller: _searchController,
        hintText: 'بحث باسم المندوب أو الهاتف أو الفرع...',
        elevation: WidgetStateProperty.all(0),
        backgroundColor: WidgetStateProperty.all(
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        leading: Icon(
          Icons.search_rounded,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
        trailing: _searchController.text.isNotEmpty
            ? [
                TashilIconButton.close(
                  size: 26,
                  iconSize: 14,
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
              ]
            : null,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 12),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildBranchSelector(ThemeData theme, ColorScheme colorScheme) {
    final isSelectedAll = _selectedBranch == 'all';
    final displayText = isSelectedAll ? 'جميع الفروع' : _selectedBranch;

    return PopupMenuButton<String>(
      tooltip: 'تصفية حسب الفرع',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: colorScheme.surfaceContainerHigh,
      elevation: 3,
      onSelected: (val) {
        setState(() => _selectedBranch = val);
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem<String>(
            value: 'all',
            child: Row(
              children: [
                Icon(
                  isSelectedAll
                      ? Icons.check_circle_rounded
                      : Icons.storefront_outlined,
                  size: 18,
                  color: isSelectedAll
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  'جميع الفروع',
                  style: TextStyle(
                    fontWeight:
                        isSelectedAll ? FontWeight.bold : FontWeight.normal,
                    color: isSelectedAll
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          ..._availableBranches.map(
            (b) {
              final isSelected = _selectedBranch == b;
              return PopupMenuItem<String>(
                value: b,
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.storefront_rounded,
                      size: 18,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        b,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ];
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                displayText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusButtonGroup(
    int totalCount,
    int presentCount,
    int departedCount,
    int absentCount,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return TashilConnectedButtonGroup<String>(
      height: 44,
      selectedValue: _statusFilter,
      isScrollable: true,
      onSelected: (val) {
        setState(() => _statusFilter = val);
      },
      items: [
        TashilConnectedButtonItem<String>(
          value: 'all',
          label: 'الكل ($totalCount)',
          icon: Icons.people_alt_outlined,
          activeColor: colorScheme.primary,
          activeForegroundColor: colorScheme.onPrimary,
        ),
        TashilConnectedButtonItem<String>(
          value: 'present',
          label: 'حاضرون ($presentCount)',
          icon: Icons.check_circle_rounded,
          activeColor: const Color(0xFF2E7D32),
          activeForegroundColor: Colors.white,
        ),
        TashilConnectedButtonItem<String>(
          value: 'departed',
          label: 'انصرفوا ($departedCount)',
          icon: Icons.timelapse_rounded,
          activeColor: const Color(0xFFE65100),
          activeForegroundColor: Colors.white,
        ),
        TashilConnectedButtonItem<String>(
          value: 'absent',
          label: 'لم يسجلوا ($absentCount)',
          icon: Icons.cancel_outlined,
          activeColor: colorScheme.outline,
          activeForegroundColor: Colors.white,
        ),
      ],
    );
  }

  Widget _buildCsvExportButton() {
    return TashilIconButton.tonal(
      icon: Icons.download_rounded,
      size: 44,
      iconSize: 20,
      tooltip: 'تصدير كشف الحضور (CSV)',
      onPressed: _exportToCSV,
    );
  }

  Widget _buildViewModeToggle(ColorScheme colorScheme) {
    return TashilConnectedButtonGroup<bool>(
      height: 44,
      selectedValue: _isTableView,
      onSelected: (val) {
        setState(() => _isTableView = val);
      },
      items: const [
        TashilConnectedButtonItem<bool>(
          value: true,
          label: 'جدول',
          icon: Icons.table_chart_rounded,
        ),
        TashilConnectedButtonItem<bool>(
          value: false,
          label: 'كروت',
          icon: Icons.grid_view_rounded,
        ),
      ],
    );
  }

  Widget _buildAttendanceCard(
    HRAttendanceRecord record,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isPresent = record.isPresent;
    final isDeparted = record.isDeparted;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isPresent) {
      statusColor = const Color(0xFF2E7D32);
      statusText = 'حاضر الآن';
      statusIcon = Icons.check_circle_rounded;
    } else if (isDeparted) {
      statusColor = const Color(0xFFE65100);
      statusText = 'انصرف اليوم';
      statusIcon = Icons.timelapse_rounded;
    } else {
      statusColor = colorScheme.outline;
      statusText = 'لم يسجل حضور';
      statusIcon = Icons.schedule_rounded;
    }

    final posName = record.delegate.position == DelegatePosition.supervisor
        ? 'مشرف'
        : 'مندوب / مروج';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPresent
              ? statusColor.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isPresent ? 1.5 : 1.0,
        ),
      ),
      color: isPresent
          ? statusColor.withValues(alpha: 0.02)
          : colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Delegate Top Header & Status ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppAvatar(
                  imageUrl: record.delegate.personalPhotoUrl,
                  fallbackText: record.delegate.fullName,
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.delegate.fullName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              record.delegate.phoneNumber,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            ' • $posName',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // ── Attendance Times & Branch ──
            if (record.checkInTime != null || record.branchName != null) ...[
              Row(
                children: [
                  // Branch
                  if (record.branchName != null) ...[
                    Icon(Icons.storefront_rounded,
                        size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        record.branchName!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],

                  // Check-in Time
                  if (record.checkInTime != null) ...[
                    Icon(Icons.login_rounded,
                        size: 15, color: const Color(0xFF2E7D32)),
                    const SizedBox(width: 4),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        DateFormat('hh:mm a', 'ar').format(record.checkInTime!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],

                  // Check-out Time
                  if (record.checkOutTime != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.logout_rounded,
                        size: 15, color: const Color(0xFFE65100)),
                    const SizedBox(width: 4),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        DateFormat('hh:mm a', 'ar').format(record.checkOutTime!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],

            // ── Anti-Fraud Geofence & Device Details ──
            if (record.latitude != null && record.longitude != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (record.isInsideGeofence == true)
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.08)
                      : (record.isInsideGeofence == false)
                          ? const Color(0xFFC62828).withValues(alpha: 0.08)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      record.isInsideGeofence == true
                          ? Icons.verified_user_rounded
                          : record.isInsideGeofence == false
                              ? Icons.warning_amber_rounded
                              : Icons.location_off_outlined,
                      size: 16,
                      color: record.isInsideGeofence == true
                          ? const Color(0xFF2E7D32)
                          : record.isInsideGeofence == false
                              ? const Color(0xFFC62828)
                              : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        record.isInsideGeofence == true
                            ? 'نطاق جغرافي سليم (داخل حدود الفرع: ${record.distanceMeters!.toStringAsFixed(0)}م)'
                            : record.isInsideGeofence == false
                                ? 'تنبيه: خارج حدود الفرع بمسافة ${record.distanceMeters!.toStringAsFixed(0)}م'
                                : 'إحداثيات الحضور مسجلة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: record.isInsideGeofence == true
                              ? const Color(0xFF2E7D32)
                              : record.isInsideGeofence == false
                                  ? const Color(0xFFC62828)
                                  : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    // Map Icon Button
                    TashilIconButton.standard(
                      icon: Icons.map_outlined,
                      tooltip: 'عرض الإحداثيات على الخريطة',
                      size: 28,
                      iconSize: 16,
                      onPressed: () => _openGoogleMaps(
                        record.latitude!,
                        record.longitude!,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ── Device Info & Actions Row ──
            Row(
              children: [
                if (record.deviceInfo != null && record.deviceInfo!.trim().isNotEmpty) ...[
                  Icon(Icons.smartphone_rounded,
                      size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      record.deviceInfo!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),

                // Action: Phone Call
                if (record.delegate.phoneNumber.isNotEmpty) ...[
                  TashilIconButton.tonal(
                    icon: Icons.call_outlined,
                    tooltip: 'اتصال بالمندوب',
                    size: 34,
                    iconSize: 17,
                    onPressed: () => _callPhone(record.delegate.phoneNumber),
                  ),
                  const SizedBox(width: 6),
                  TashilIconButton.tonal(
                    icon: Icons.chat_outlined,
                    tooltip: 'مراسلة عبر واتساب',
                    size: 34,
                    iconSize: 17,
                    onPressed: () => _openWhatsApp(record.delegate.phoneNumber),
                  ),
                  const SizedBox(width: 6),
                ],

                // Action: View Monthly History
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.history_rounded, size: 16),
                  label: const Text('السجل الشهري'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttendanceScreen(
                          delegate: record.delegate,
                          viewOnly: true,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
