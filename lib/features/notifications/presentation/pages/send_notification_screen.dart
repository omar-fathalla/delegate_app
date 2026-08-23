import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class SendNotificationScreen extends StatefulWidget {
  final Delegate senderDelegate;

  const SendNotificationScreen({super.key, required this.senderDelegate});

  @override
  State<SendNotificationScreen> createState() => _SendNotificationScreenState();
}

class _SendNotificationScreenState extends State<SendNotificationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _phoneController = TextEditingController();

  String _targetAudience = 'all'; // 'all', 'org', 'user'
  String? _selectedOrgUID;
  List<Map<String, dynamic>> _organizations = [];
  bool _isLoadingOrgs = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchOrganizations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrganizations() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('organizations').get();
      final orgs = snap.docs.map((doc) {
        final data = doc.data();
        return {
          'uid': doc.id,
          'name': data['name'] ?? data['title'] ?? doc.id,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _organizations = orgs;
          if (_organizations.isNotEmpty) {
            _selectedOrgUID = _organizations.first['uid'];
          }
          _isLoadingOrgs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingOrgs = false);
    }
  }

  String _formatUserNameAndRole(Map<String, dynamic> data) {
    final role = (data['role'] ?? '').toString();
    final displayName = (data['displayName'] ?? '').toString().trim();
    final fullName = (data['fullName'] ?? data['name'] ?? '').toString().trim();

    if (role == 'super-admin' || role == 'superAdmin') {
      return 'Super Admin';
    }
    if (role == 'technicalSupport' || role == 'technical-support') {
      return 'Technical Support';
    }
    if (role == 'organization-admin' || role == 'organizationAdmin') {
      return fullName.isNotEmpty && fullName != 'admin' ? 'مدير عام ($fullName)' : 'مدير عام';
    }
    if (role == 'company-admin' || role == 'admin') {
      return fullName.isNotEmpty && fullName != 'admin' ? 'مشرف شركة ($fullName)' : 'مشرف شركة';
    }
    if (role == 'marketing') {
      return fullName.isNotEmpty ? 'تسويق الفروع ($fullName)' : 'تسويق الفروع';
    }
    if (role == 'marketing_promotion' || role == 'marketingPromotion') {
      return fullName.isNotEmpty ? 'تسويق العروض ($fullName)' : 'تسويق العروض';
    }

    if (displayName.isNotEmpty && displayName != 'admin' && displayName != 'user') {
      return displayName;
    }
    if (fullName.isNotEmpty && fullName != 'admin' && fullName != 'user') {
      return fullName;
    }
    return 'مستخدم';
  }

  /// Helper to search for a user by various phone number formats
  Future<Map<String, dynamic>?> _findUserByPhone(String rawPhone) async {
    final cleanPhone = rawPhone.replaceAll(RegExp(r'\s+'), '').trim();
    if (cleanPhone.isEmpty) return null;

    final variations = <String>{
      cleanPhone,
      cleanPhone.startsWith('0') ? cleanPhone.substring(1) : '0$cleanPhone',
      if (!cleanPhone.startsWith('+')) '+20$cleanPhone',
      if (!cleanPhone.startsWith('+') && cleanPhone.startsWith('0'))
        '+20${cleanPhone.substring(1)}',
      if (!cleanPhone.startsWith('+')) '+971$cleanPhone',
    };

    final firestore = FirebaseFirestore.instance;

    // 1. Search in users collection
    for (final phoneVar in variations) {
      for (final field in ['phoneNumber', 'phone', 'mobile', 'mobileNumber']) {
        final query =
            await firestore
                .collection('users')
                .where(field, isEqualTo: phoneVar)
                .limit(1)
                .get();
        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          final data = doc.data();
          return {
            'uid': data['uid'] ?? doc.id,
            'name': _formatUserNameAndRole(data),
            'phone': phoneVar,
            'organizationUID': data['organizationUID'] ?? '',
            'companyUID': data['companyUID'] ?? '',
            'role': data['role'] ?? 'user',
          };
        }
      }
    }

    // 2. Search in delegates collectionGroup
    for (final phoneVar in variations) {
      for (final field in ['phoneNumber', 'phone', 'mobile', 'mobileNumber']) {
        final query =
            await firestore
                .collectionGroup('delegates')
                .where(field, isEqualTo: phoneVar)
                .limit(1)
                .get();
        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          final data = doc.data();
          return {
            'uid': data['uid'] ?? doc.id,
            'name': _formatUserNameAndRole(data),
            'phone': phoneVar,
            'organizationUID': data['organizationUID'] ?? '',
            'companyUID': data['companyUID'] ?? '',
            'role': data['role'] ?? 'delegate',
          };
        }
      }
    }

    return null;
  }

  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);

    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    final firestore = FirebaseFirestore.instance;

    try {
      int sentCount = 0;
      String targetName = 'جميع مستخدمي التطبيق (الكل)';
      String targetDetails = '';
      String? targetUid;

      // 1. Create a tracking doc in sent_notifications collection
      final sentLogRef = firestore.collection('sent_notifications').doc();
      final String broadcastId = sentLogRef.id;

      if (_targetAudience == 'all') {
        targetName = 'جميع مستخدمي التطبيق (الكل)';
        targetDetails = 'إرسال لجميع الفروع والمناديب والمدراء';

        // Add global broadcast notification
        await firestore.collection('notifications').add({
          'delegateUid': 'all',
          'organizationId': '',
          'companyId': '',
          'title': title,
          'body': body,
          'type': 'technical_support_broadcast',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
          'senderName': widget.senderDelegate.fullName,
          'senderUid': widget.senderDelegate.uid,
          'broadcastId': broadcastId,
        });

        // Add individual user notifications
        final snap = await firestore.collectionGroup('delegates').get();
        final batch = firestore.batch();
        int count = 0;
        for (final doc in snap.docs) {
          final data = doc.data();
          final uid = data['uid'] ?? doc.id;
          final orgId = data['organizationUID'] ?? '';
          final compId = data['companyUID'] ?? '';
          if (uid != null && uid.toString().isNotEmpty) {
            final newRef = firestore.collection('notifications').doc();
            batch.set(newRef, {
              'delegateUid': uid,
              'organizationId': orgId,
              'companyId': compId,
              'title': title,
              'body': body,
              'type': 'support_alert',
              'isRead': false,
              'createdAt': FieldValue.serverTimestamp(),
              'senderName': widget.senderDelegate.fullName,
              'senderUid': widget.senderDelegate.uid,
              'broadcastId': broadcastId,
            });
            count++;
            if (count % 450 == 0) {
              await batch.commit();
            }
          }
        }
        await batch.commit();
        sentCount = count > 0 ? count : 1;
      } else if (_targetAudience == 'org' && _selectedOrgUID != null) {
        final org = _organizations.firstWhere(
          (o) => o['uid'] == _selectedOrgUID,
          orElse: () => {'name': _selectedOrgUID},
        );
        targetName = 'منظمة: ${org['name']}';
        targetDetails = 'جميع أعضاء ومناديب ${org['name']}';

        final snap = await firestore.collectionGroup('delegates').get();
        final batch = firestore.batch();
        int count = 0;

        for (final doc in snap.docs) {
          final data = doc.data();
          final pathParts = doc.reference.path.split('/');
          final docOrgUid =
              data['organizationUID'] ??
              (pathParts.length > 1 ? pathParts[1] : '');

          if (docOrgUid == _selectedOrgUID) {
            final uid = data['uid'] ?? doc.id;
            final compId = data['companyUID'] ?? '';
            final newRef = firestore.collection('notifications').doc();
            batch.set(newRef, {
              'delegateUid': uid,
              'organizationId': _selectedOrgUID,
              'companyId': compId,
              'title': title,
              'body': body,
              'type': 'support_alert',
              'isRead': false,
              'createdAt': FieldValue.serverTimestamp(),
              'senderName': widget.senderDelegate.fullName,
              'senderUid': widget.senderDelegate.uid,
              'broadcastId': broadcastId,
            });
            count++;
            if (count % 450 == 0) {
              await batch.commit();
            }
          }
        }
        await batch.commit();
        sentCount = count;
      } else if (_targetAudience == 'user') {
        final phoneInput = _phoneController.text.trim();
        final matchedUser = await _findUserByPhone(phoneInput);

        if (matchedUser != null) {
          targetUid = matchedUser['uid'];
          final uName = matchedUser['name'];
          final uPhone = matchedUser['phone'];
          targetName = '$uName ($uPhone)';
          targetDetails = 'مستخدم محدد: $uName • رقم الهاتف: $uPhone';

          await firestore.collection('notifications').add({
            'delegateUid': targetUid,
            'phoneNumber': uPhone,
            'organizationId': matchedUser['organizationUID'] ?? '',
            'companyId': matchedUser['companyUID'] ?? '',
            'title': title,
            'body': body,
            'type': 'support_direct',
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
            'senderName': widget.senderDelegate.fullName,
            'senderUid': widget.senderDelegate.uid,
            'broadcastId': broadcastId,
          });
          sentCount = 1;
        } else {
          // Send to phone identifier fallback
          targetUid = 'phone_$phoneInput';
          targetName = 'رقم الهاتف: $phoneInput';
          targetDetails = 'مستخدم غير مسجل بالاسم • رقم الهاتف: $phoneInput';

          await firestore.collection('notifications').add({
            'delegateUid': targetUid,
            'phoneNumber': phoneInput,
            'organizationId': '',
            'companyId': '',
            'title': title,
            'body': body,
            'type': 'support_direct',
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
            'senderName': widget.senderDelegate.fullName,
            'senderUid': widget.senderDelegate.uid,
            'broadcastId': broadcastId,
          });
          sentCount = 1;
        }
      }

      // Record Sent Log Entry in sent_notifications
      await sentLogRef.set({
        'id': broadcastId,
        'title': title,
        'body': body,
        'targetAudience': _targetAudience,
        'targetName': targetName,
        'targetDetails': targetDetails,
        'targetUid': targetUid,
        'senderName': widget.senderDelegate.fullName,
        'senderUid': widget.senderDelegate.uid,
        'sentCount': sentCount,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Trigger local test notification on device
      try {
        final flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();
        const androidDetails = AndroidNotificationDetails(
          'support_channel',
          'إشعارات الدعم الفني',
          channelDescription: 'إشعارات وبلاغات الدعم الفني',
          importance: Importance.high,
          priority: Priority.high,
        );
        const notificationDetails = NotificationDetails(
          android: androidDetails,
        );
        await flutterLocalNotificationsPlugin.show(
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title,
          body,
          notificationDetails,
        );
      } catch (e) {
        debugPrint('Local notification test trigger error: $e');
      }

      if (mounted) {
        _titleController.clear();
        _bodyController.clear();
        _phoneController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم إرسال الإشعار بنجاح إلى $targetName'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Switch to Sent History tab
        _tabController.animateTo(1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ حدث خطأ أثناء إرسال الإشعار: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'نظام إشعارات الدعم الفني',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 3,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.edit_note_rounded), text: 'إرسال إشعار جديد'),
            Tab(
              icon: Icon(Icons.outbox_rounded),
              text: 'صندوق الصادر والمقروء',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildComposeTab(theme, colorScheme), _buildSentHistoryTab()],
      ),
    );
  }

  Widget _buildComposeTab(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.campaign_rounded,
                    color: colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إرسال إشعار مباشر أو جماعي',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'يصل التنبيه لجميع الأجهزة وتظهر حالة الاستلام والقراءة في صندوق الصادر.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Title Field
            Text(
              'عنوان الإشعار',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'مثال: تنبيه هام من الدعم الفني',
                prefixIcon: const Icon(Icons.title_rounded),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
              validator:
                  (v) =>
                      v == null || v.trim().isEmpty
                          ? 'يرجى إدخال عنوان الإشعار'
                          : null,
            ),
            const SizedBox(height: 18),

            // Body Field
            Text(
              'نص ومحتوى الإشعار',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bodyController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'اكتب نص الإشعار هنا بالتفصيل...',
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 50),
                  child: Icon(Icons.notes_rounded),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
              validator:
                  (v) =>
                      v == null || v.trim().isEmpty
                          ? 'يرجى إدخال محتوى الإشعار'
                          : null,
            ),
            const SizedBox(height: 20),

            // Target Audience Selection
            Text(
              'الجمهور المستهدف بالإشعار',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  _buildAudienceOptionTile(
                    title: 'جميع مستخدمي التطبيق (الكل)',
                    subtitle: 'إرسال لجميع المناديب والمدراء في النظام',
                    value: 'all',
                    icon: Icons.public_rounded,
                  ),
                  const Divider(height: 1),
                  _buildAudienceOptionTile(
                    title: 'قطاع / منظمة محددة',
                    subtitle: 'تخصيص الإشعار لمنظمة معينة فقط',
                    value: 'org',
                    icon: Icons.corporate_fare_rounded,
                  ),
                  const Divider(height: 1),
                  _buildAudienceOptionTile(
                    title: 'مستخدم / مندوب محدد (رقم الهاتف)',
                    subtitle: 'إرسال الإشعار لمستخدم واحد برقم الهاتف',
                    value: 'user',
                    icon: Icons.person_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Sub-selection depending on Target Audience
            if (_targetAudience == 'org') ...[
              Text(
                'اختر المنظمة المستهدفة',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              _isLoadingOrgs
                  ? const CircularProgressIndicator()
                  : DropdownButtonFormField<String>(
                    initialValue: _selectedOrgUID,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    items:
                        _organizations.map((org) {
                          return DropdownMenuItem<String>(
                            value: org['uid'] as String,
                            child: Text(org['name'] as String),
                          );
                        }).toList(),
                    onChanged: (val) => setState(() => _selectedOrgUID = val),
                  ),
              const SizedBox(height: 18),
            ],

            if (_targetAudience == 'user') ...[
              Text(
                'رقم هاتف المستخدم المستهدف',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'مثال: 01012345678',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                validator:
                    (v) =>
                        _targetAudience == 'user' &&
                                (v == null || v.trim().isEmpty)
                            ? 'يرجى إدخال رقم هاتف المستخدم'
                            : null,
              ),
              const SizedBox(height: 18),
            ],

            const SizedBox(height: 16),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _isSending ? null : _sendNotification,
                icon:
                    _isSending
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : const Icon(Icons.send_rounded),
                label: Text(
                  _isSending ? 'جاري إرسال الإشعار...' : 'إرسال الإشعار الآن',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildAudienceOptionTile({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _targetAudience == value;

    return InkWell(
      onTap: () => setState(() => _targetAudience = value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color:
                  isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Icon(
              icon,
              color:
                  isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color:
                          isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
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

  // ----------------------------------------------------
  // Sent History / Outbox Tab with Realtime Read Status
  // ----------------------------------------------------
  Widget _buildSentHistoryTab() {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('sent_notifications')
              .orderBy('createdAt', descending: true)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'حدث خطأ في تحميل السجل: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.outbox_rounded,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                const Text(
                  'لا توجد إشعارات مرسلة حتى الآن',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'أي إشعار ستقوم بإرساله سيظهر هنا مع إحصائيات القراءة والتسليم.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final id = docs[index].id;
            return _SentNotificationCard(
              docId: id,
              data: data,
              onResend: (title, body, audience, phone) {
                _titleController.text = title;
                _bodyController.text = body;
                _phoneController.text = phone;
                setState(() {
                  _targetAudience = audience;
                });
                _tabController.animateTo(0);
              },
            );
          },
        );
      },
    );
  }
}

class _SentNotificationCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final void Function(
    String title,
    String body,
    String audience,
    String phone,
  )
  onResend;

  const _SentNotificationCard({
    required this.docId,
    required this.data,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final title = data['title'] as String? ?? 'بدون عنوان';
    final body = data['body'] as String? ?? '';
    final targetName = data['targetName'] as String? ?? 'الجميع';
    final targetAudience = data['targetAudience'] as String? ?? 'all';
    final senderName = data['senderName'] as String? ?? 'الدعم الفني';
    final totalSent = (data['sentCount'] as num?)?.toInt() ?? 1;
    final timestamp = data['createdAt'] as Timestamp?;
    final dateStr =
        timestamp != null
            ? DateFormat('dd/MM/yyyy - hh:mm a').format(timestamp.toDate())
            : 'الآن';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Sender, Target & Delivery Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getAudienceIcon(targetAudience),
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        targetName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'المرسل: $senderName • $dateStr',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.done_all_rounded,
                        color: Colors.green.shade700,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'تم التوصيل',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Message Title & Body
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),

            // Realtime Read Status Stream for this Notification / Broadcast
            StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('notifications')
                      .where('broadcastId', isEqualTo: docId)
                      .snapshots(),
              builder: (context, notifSnap) {
                int readCount = 0;
                int actualCount = totalSent;
                DateTime? latestReadTime;

                if (notifSnap.hasData && notifSnap.data!.docs.isNotEmpty) {
                  final docs = notifSnap.data!.docs;
                  actualCount = docs.length;
                  for (final d in docs) {
                    final m = d.data() as Map<String, dynamic>;
                    if (m['isRead'] == true) {
                      readCount++;
                      final rTime = (m['readAt'] as Timestamp?)?.toDate();
                      if (rTime != null &&
                          (latestReadTime == null ||
                              rTime.isAfter(latestReadTime))) {
                        latestReadTime = rTime;
                      }
                    }
                  }
                }

                final double readPercent =
                    actualCount > 0 ? (readCount / actualCount) : 0.0;
                final bool isAllRead =
                    actualCount > 0 && readCount == actualCount;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        isAllRead
                            ? Colors.blue.shade50
                            : colorScheme.surfaceContainerHighest.withValues(
                              alpha: 0.4,
                            ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          isAllRead
                              ? Colors.blue.shade200
                              : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isAllRead
                                    ? Icons.done_all_rounded
                                    : Icons.remove_red_eye_outlined,
                                size: 18,
                                color:
                                    isAllRead
                                        ? Colors.blue.shade700
                                        : colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                targetAudience == 'user'
                                    ? (readCount > 0
                                        ? 'تمت القراءة بنجاح ✅'
                                        : 'لم تتم القراءة بعد ⏳')
                                    : 'حالة القراءة: $readCount من $actualCount مستخدم',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      readCount > 0
                                          ? Colors.blue.shade800
                                          : colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            targetAudience == 'user'
                                ? (readCount > 0 && latestReadTime != null
                                    ? DateFormat(
                                      'hh:mm a',
                                    ).format(latestReadTime)
                                    : 'في الانتظار')
                                : '${(readPercent * 100).toStringAsFixed(0)}% تم الفتح',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  readPercent > 0
                                      ? Colors.blue.shade700
                                      : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      if (targetAudience != 'user') ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: readPercent,
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              readPercent >= 0.8
                                  ? Colors.green
                                  : Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Actions Row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    final targetAudience =
                        data['targetAudience'] as String? ?? 'all';
                    final targetName = data['targetName'] as String? ?? '';
                    String phone = '';
                    if (targetAudience == 'user') {
                      final match = RegExp(
                        r'(\+?\d{10,14})',
                      ).firstMatch(targetName);
                      if (match != null) phone = match.group(0) ?? '';
                    }
                    onResend(title, body, targetAudience, phone);
                  },
                  icon: const Icon(Icons.repeat_rounded, size: 18),
                  label: const Text('إعادة إرسال'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _showNotificationDetails(context, dateStr),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('عرض التفاصيل'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getAudienceIcon(String audience) {
    switch (audience) {
      case 'org':
        return Icons.corporate_fare_rounded;
      case 'user':
        return Icons.person_rounded;
      default:
        return Icons.public_rounded;
    }
  }

  void _showNotificationDetails(BuildContext context, String dateStr) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.mark_email_read_rounded,
                color: Colors.deepPurple,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'تفاصيل الإشعار المرسل',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('العنوان', data['title'] ?? ''),
                const Divider(),
                _buildDetailRow('المحتوى', data['body'] ?? ''),
                const Divider(),
                _buildDetailRow(
                  'المستهدف',
                  data['targetDetails'] ?? data['targetName'] ?? '',
                ),
                const Divider(),
                _buildDetailRow('المرسل', data['senderName'] ?? ''),
                const Divider(),
                _buildDetailRow('تاريخ الإرسال', dateStr),
                const Divider(),
                _buildDetailRow(
                  'إجمالي المستلمين',
                  '${data['sentCount'] ?? 1} مستخدم',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
