import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/pages/admin_create_penalty_page.dart';

/// شاشة رصد وتدقيق الأمان ومكافحة برامج الـ Fake Location وتزييف الموقع (Anti-Fraud & Mock Location Audit)
class AntiFraudAuditScreen extends StatefulWidget {
  final Delegate delegate;
  final bool showAppBar;

  const AntiFraudAuditScreen({
    super.key,
    required this.delegate,
    this.showAppBar = false,
  });

  @override
  State<AntiFraudAuditScreen> createState() => _AntiFraudAuditScreenState();
}

class _AntiFraudAuditScreenState extends State<AntiFraudAuditScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _timeFilter = 'all'; // all, today, week, month

  @override
  void dispose() {
    _searchController.dispose();
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

  Future<void> _deleteAuditLog(BuildContext context, String docId, String delegateName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('حذف السجل الأمني', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف سجل المخالفة الأمني للمندوب "$delegateName"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
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
            const SnackBar(
              content: Text('تم حذف السجل الأمني بنجاح'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ أثناء الحذف: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _createPenaltyForDelegate(BuildContext context, Map<String, dynamic> data) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => di.sl<PenaltyBloc>(),
          child: AdminCreatePenaltyPage(
            adminDelegate: widget.delegate,
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
      case 'week':
        final weekAgo = now.subtract(const Duration(days: 7));
        return timestamp.isAfter(weekAgo);
      case 'month':
        final monthAgo = now.subtract(const Duration(days: 30));
        return timestamp.isAfter(monthAgo);
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

    final body = StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('security_audit_logs')
          .orderBy('timestamp', descending: true)
          .snapshots(),
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

        // Calculate summary metrics
        final now = DateTime.now();
        int todayAttempts = 0;
        final Set<String> uniqueDelegates = {};
        final Set<String> uniqueDevices = {};

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
        }

        // Apply filters
        final filteredLogs = allLogs.where((item) {
          // 1. Time filter
          final ts = (item['timestamp'] as Timestamp?)?.toDate();
          if (!_matchesTimeFilter(ts)) return false;

          // 2. Search query filter
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            final name = (item['delegateName'] ?? '').toString().toLowerCase();
            final phone = (item['delegatePhone'] ?? '').toString().toLowerCase();
            final comp = (item['companyName'] ?? '').toString().toLowerCase();
            final branch = (item['branchName'] ?? '').toString().toLowerCase();
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

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 1. Header Metrics Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _buildHeaderMetrics(
                    colorScheme: colorScheme,
                    totalAttempts: allLogs.length,
                    todayAttempts: todayAttempts,
                    uniqueDelegatesCount: uniqueDelegates.length,
                    uniqueDevicesCount: uniqueDevices.length,
                    isArabic: isArabic,
                  ),
                ),
              ),

              // 2. Search & Time Filters
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      // Search bar
                      TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        decoration: InputDecoration(
                          hintText: isArabic
                              ? 'بحث بالمندوب، الشركة، الفرع، أو نوع الجهاز...'
                              : 'Search delegate, company, branch, or device...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Time Filters
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('all', isArabic ? 'الكل (${allLogs.length})' : 'All', colorScheme),
                            const SizedBox(width: 8),
                            _buildFilterChip('today', isArabic ? 'اليوم ($todayAttempts)' : 'Today', colorScheme),
                            const SizedBox(width: 8),
                            _buildFilterChip('week', isArabic ? 'آخر 7 أيام' : 'Last 7 Days', colorScheme),
                            const SizedBox(width: 8),
                            _buildFilterChip('month', isArabic ? 'آخر 30 يوم' : 'Last 30 Days', colorScheme),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Results Count
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        isArabic
                            ? 'سجلات محاولات التزييف المكتشفة (${filteredLogs.length})'
                            : 'Detected Violations (${filteredLogs.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
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
                            color: Colors.green.shade400,
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
              else
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
                        );
                      },
                      childCount: filteredLogs.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (widget.showAppBar) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            isArabic ? 'سجل الأمان وكشف التزييف' : 'Security & Anti-Fraud Logs',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: body,
      );
    }

    return body;
  }

  Widget _buildFilterChip(String key, String label, ColorScheme colorScheme) {
    final isSelected = _timeFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _timeFilter = key);
        }
      },
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
      ),
    );
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
        gradient: LinearGradient(
          colors: [
            Colors.red.shade900,
            Colors.red.shade800,
            Colors.deepOrange.shade900,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.security_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'منظومة كشف التزييف والأمان' : 'Anti-Fraud & Security Monitor',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isArabic
                          ? 'رصد محاولات الـ Fake GPS وبصمات الأجهزة المخالفة'
                          : 'Real-time mock GPS & device fingerprint tracking',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 14),

          // Stat row
          Row(
            children: [
              _buildStatBox(
                title: isArabic ? 'إجمالي المحاولات' : 'Total Attempts',
                value: '$totalAttempts',
                icon: Icons.gavel_rounded,
              ),
              const SizedBox(width: 8),
              _buildStatBox(
                title: isArabic ? 'اليوم' : 'Today',
                value: '$todayAttempts',
                icon: Icons.today_rounded,
                isHighlight: todayAttempts > 0,
              ),
              const SizedBox(width: 8),
              _buildStatBox(
                title: isArabic ? 'المناديب' : 'Delegates',
                value: '$uniqueDelegatesCount',
                icon: Icons.people_outline_rounded,
              ),
              const SizedBox(width: 8),
              _buildStatBox(
                title: isArabic ? 'الأجهزة' : 'Devices',
                value: '$uniqueDevicesCount',
                icon: Icons.phone_android_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required String title,
    required String value,
    required IconData icon,
    bool isHighlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isHighlight
              ? Colors.amber.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: isHighlight
              ? Border.all(color: Colors.amber.shade300, width: 1.2)
              : null,
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: isHighlight ? Colors.amber.shade200 : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViolationCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required Map<String, dynamic> data,
    required bool isArabic,
  }) {
    final docId = data['docId']?.toString() ?? '';
    final delegateName = data['delegateName']?.toString() ?? 'مندوب غير محدد';
    final delegatePhone = data['delegatePhone']?.toString() ?? '';
    final companyName = data['companyName']?.toString() ?? '';
    final branchName = data['branchName']?.toString() ?? '';
    final deviceModel = data['deviceModel']?.toString() ?? 'جهاز غير معروف';
    final violationTitle = data['violationTitle']?.toString() ?? 'تزييف موقع جغرافي';
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final dateStr = ts != null
        ? DateFormat('yyyy-MM-dd  hh:mm a').format(ts)
        : (data['createdAt']?.toString() ?? 'غير محدد');

    final isApple = deviceModel.toLowerCase().contains('iphone') ||
        deviceModel.toLowerCase().contains('ipad') ||
        deviceModel.toLowerCase().contains('ios');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.red.shade200.withValues(alpha: 0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Delegate Name & Violation Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade800,
                  radius: 20,
                  child: const Icon(Icons.person_off_rounded, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delegateName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (delegatePhone.isNotEmpty)
                        Text(
                          delegatePhone,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                // Violation Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red.shade900),
                      const SizedBox(width: 4),
                      Text(
                        violationTitle.isNotEmpty ? violationTitle : 'Fake GPS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
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
                    color: isApple ? Colors.black87 : Colors.teal.shade800,
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

            const SizedBox(height: 8),

            // Company & Branch & Date Row
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (companyName.isNotEmpty)
                  Chip(
                    label: Text(companyName),
                    avatar: const Icon(Icons.business_rounded, size: 14),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(fontSize: 11),
                  ),
                if (branchName.isNotEmpty)
                  Chip(
                    label: Text(branchName),
                    avatar: const Icon(Icons.storefront_rounded, size: 14),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(fontSize: 11),
                  ),
                Chip(
                  label: Text(dateStr),
                  avatar: const Icon(Icons.access_time_rounded, size: 14),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 11),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Action Buttons Bar
            Row(
              children: [
                if (delegatePhone.isNotEmpty) ...[
                  IconButton.filledTonal(
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    tooltip: 'اتصال هاتفي بالمندوب',
                    onPressed: () => _makePhoneCall(delegatePhone),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.shade50,
                      foregroundColor: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    tooltip: 'مراسلة عبر واتساب',
                    onPressed: () => _openWhatsApp(delegatePhone),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.teal.shade50,
                      foregroundColor: Colors.teal.shade800,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _createPenaltyForDelegate(context, data),
                    icon: const Icon(Icons.gavel_rounded, size: 16),
                    label: const Text('تطبيق غرامة', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade900,
                      side: BorderSide(color: Colors.red.shade300),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 20),
                  tooltip: 'حذف السجل',
                  onPressed: () => _deleteAuditLog(context, docId, delegateName),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
