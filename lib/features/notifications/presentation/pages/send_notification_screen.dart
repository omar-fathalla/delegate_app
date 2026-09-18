import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class SendNotificationScreen extends StatefulWidget {
  final Delegate senderDelegate;
  final bool showAppBar;

  const SendNotificationScreen({
    super.key,
    required this.senderDelegate,
    this.showAppBar = true,
  });

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
          'senderRole': widget.senderDelegate.role.name,
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
              'senderRole': widget.senderDelegate.role.name,
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
              'senderRole': widget.senderDelegate.role.name,
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
          final uName = matchedUser['name'] ?? 'مستخدم';
          final uPhone = matchedUser['phone'] ?? phoneInput;
          targetName = uName;
          targetDetails = 'مستخدم محدد: $uName';

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
            'senderRole': widget.senderDelegate.role.name,
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
            'senderRole': widget.senderDelegate.role.name,
            'senderUid': widget.senderDelegate.uid,
            'broadcastId': broadcastId,
          });
          sentCount = 1;
        }
      }

      // Record Sent Log Entry in sent_notifications
      await sentLogRef.set({
        'broadcastId': broadcastId,
        'title': title,
        'body': body,
        'senderUid': widget.senderDelegate.uid,
        'senderName': widget.senderDelegate.fullName,
        'senderRole': widget.senderDelegate.role.name,
        'targetAudience': _targetAudience,
        'targetName': targetName,
        'targetDetails': targetDetails,
        'targetUid': targetUid,
        'targetPhone': _targetAudience == 'user' ? _phoneController.text.trim() : null,
        'targetOrgId': _targetAudience == 'org' ? _selectedOrgUID : null,
        'sentCount': sentCount,
        'sentAt': FieldValue.serverTimestamp(),
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
            content: Text('تم إرسال الإشعار بنجاح إلى $targetName'),
            backgroundColor: Theme.of(context).colorScheme.primary,
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
            content: Text('حدث خطأ أثناء إرسال الإشعار: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
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

    final tabBar = TabBar(
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
    );

    if (!widget.showAppBar) {
      return Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
            ),
            child: tabBar,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildComposeTab(theme, colorScheme), _buildSentHistoryTab()],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'نظام إشعارات الدعم الفني',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        bottom: tabBar,
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
                  prefixIcon: const Icon(Icons.phone_rounded),
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
                        ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: colorScheme.onPrimary,
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
        final colorScheme = Theme.of(context).colorScheme;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'حدث خطأ في تحميل السجل: ${snapshot.error}',
              style: TextStyle(color: colorScheme.error),
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
                  color: colorScheme.outlineVariant,
                ),
                const SizedBox(height: 16),
                const Text(
                  'لا توجد إشعارات مرسلة حتى الآن',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'أي إشعار ستقوم بإرساله سيظهر هنا مع إحصائيات القراءة والتسليم.',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _SentNotificationCard(
              docId: doc.id,
              data: data,
              onResend: (t, b, aud, ph) {
                _titleController.text = t;
                _bodyController.text = b;
                _targetAudience = aud;
                _phoneController.text = ph;
                _tabController.animateTo(0);
                setState(() {});
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
    final rawTargetName = data['targetName'] as String? ?? 'الجميع';
    final targetName = rawTargetName.replaceAll(RegExp(r'\s*\(\+?\d+\)\s*'), '').trim();
    final targetAudience = data['targetAudience'] as String? ?? 'all';
    final senderName = data['senderName'] as String? ?? 'الدعم الفني';
    final totalSent = (data['sentCount'] as num?)?.toInt() ?? 1;
    final timestamp = data['createdAt'] as Timestamp?;
    final dateStr =
        timestamp != null
            ? DateFormat('dd/MM/yyyy • hh:mm a').format(timestamp.toDate())
            : 'الآن';

    return StreamBuilder<QuerySnapshot>(
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
                  (latestReadTime == null || rTime.isAfter(latestReadTime))) {
                latestReadTime = rTime;
              }
            }
          }
        }

        final bool isAllRead = actualCount > 0 && readCount == actualCount;
        final bool isSingleUser = targetAudience == 'user';
        final bool isUserRead = isSingleUser && readCount > 0;

        return Card(
          elevation: 0.5,
          margin: const EdgeInsets.only(bottom: 8),
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isUserRead || isAllRead
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showNotificationDetails(
              context,
              dateStr,
              readCount: readCount,
              actualCount: actualCount,
              latestReadTime: latestReadTime,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // 1. Audience / User Avatar
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isUserRead || isAllRead
                          ? colorScheme.primaryContainer
                          : colorScheme.primaryContainer.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        _getAudienceIcon(targetAudience),
                        color: isUserRead || isAllRead
                            ? colorScheme.primary
                            : colorScheme.primary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 2. Middle Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: Target Name + Compact Read Status Chip
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                targetName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildCompactReadBadge(
                              colorScheme: colorScheme,
                              isSingleUser: isSingleUser,
                              isUserRead: isUserRead,
                              readCount: readCount,
                              actualCount: actualCount,
                              isAllRead: isAllRead,
                              latestReadTime: latestReadTime,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),

                        // Row 2: Title and preview of message
                        Text(
                          body.isNotEmpty ? '$title: $body' : title,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),

                        // Row 3: Timestamp & Sender
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 11,
                              color: colorScheme.outline,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: colorScheme.outline,
                              ),
                            ),
                            if (senderName.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '• $senderName',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: colorScheme.outline,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 3. Trailing Action Icons Only
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Resend Icon Button
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
                          foregroundColor: colorScheme.primary,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                        ),
                        icon: const Icon(Icons.repeat_rounded, size: 17),
                        tooltip: 'إعادة إرسال',
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
                      ),
                      const SizedBox(width: 4),

                      // Details Icon Button
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                          foregroundColor: colorScheme.onSurfaceVariant,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                        ),
                        icon: const Icon(Icons.visibility_rounded, size: 17),
                        tooltip: 'عرض التفاصيل',
                        onPressed: () => _showNotificationDetails(
                          context,
                          dateStr,
                          readCount: readCount,
                          actualCount: actualCount,
                          latestReadTime: latestReadTime,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactReadBadge({
    required ColorScheme colorScheme,
    required bool isSingleUser,
    required bool isUserRead,
    required int readCount,
    required int actualCount,
    required bool isAllRead,
    required DateTime? latestReadTime,
  }) {
    if (isSingleUser) {
      if (isUserRead) {
        final timeStr =
            latestReadTime != null
                ? DateFormat('hh:mm a').format(latestReadTime)
                : '';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3), width: 0.7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.done_all_rounded, size: 12, color: colorScheme.primary),
              if (timeStr.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.3), width: 0.7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty_rounded, size: 11, color: colorScheme.secondary),
              const SizedBox(width: 2),
              Text(
                'في الانتظار',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.secondary,
                ),
              ),
            ],
          ),
        );
      }
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: isAllRead
              ? colorScheme.primaryContainer.withValues(alpha: 0.6)
              : colorScheme.secondaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isAllRead
                ? colorScheme.primary.withValues(alpha: 0.3)
                : colorScheme.secondary.withValues(alpha: 0.3),
            width: 0.7,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAllRead ? Icons.done_all_rounded : Icons.people_rounded,
              size: 11,
              color: isAllRead ? colorScheme.primary : colorScheme.secondary,
            ),
            const SizedBox(width: 2),
            Text(
              '$readCount / $actualCount',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: isAllRead ? colorScheme.primary : colorScheme.secondary,
              ),
            ),
          ],
        ),
      );
    }
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

  void _showNotificationDetails(
    BuildContext context,
    String dateStr, {
    int readCount = 0,
    int actualCount = 1,
    DateTime? latestReadTime,
  }) {
    final targetAudience = data['targetAudience'] as String? ?? 'all';
    final isSingleUser = targetAudience == 'user';
    final readStatusText =
        isSingleUser
            ? (readCount > 0
                ? 'تمت القراءة بنجاح ${latestReadTime != null ? "(${DateFormat('hh:mm a').format(latestReadTime)})" : ""}'
                : 'لم تتم القراءة بعد (في الانتظار)')
            : '$readCount من أصل $actualCount مستخدم قاموا بالقراءة';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.mark_email_read_rounded,
                color: Theme.of(ctx).colorScheme.primary,
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
                _buildDetailRow(ctx, 'العنوان', data['title'] ?? ''),
                const Divider(),
                _buildDetailRow(ctx, 'المحتوى', data['body'] ?? ''),
                const Divider(),
                _buildDetailRow(
                  ctx,
                  'المستهدف',
                  (data['targetDetails'] as String? ??
                          data['targetName'] as String? ??
                          '')
                      .replaceAll(RegExp(r'\s*•?\s*رقم الهاتف:?\s*\+?\d+'), '')
                      .replaceAll(RegExp(r'\s*\(\+?\d+\)\s*'), '')
                      .trim(),
                ),
                const Divider(),
                _buildDetailRow(ctx, 'حالة القراءة', readStatusText),
                const Divider(),
                _buildDetailRow(ctx, 'المرسل', data['senderName'] ?? ''),
                const Divider(),
                _buildDetailRow(ctx, 'تاريخ الإرسال', dateStr),
                const Divider(),
                _buildDetailRow(
                  ctx,
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

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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

