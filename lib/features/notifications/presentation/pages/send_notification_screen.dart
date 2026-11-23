import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/core/widgets/keyed_stream_builder.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/core/org/org_scope.dart';
import 'package:delegate_app/core/constants/cloud_functions.dart';
import 'package:delegate_app/features/notifications/data/send_staff_notification_request.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// مركز بث وإرسال الإشعارات السحابية الشامل
/// يتيح للسوبر أدمن والدعم الفني إرسال إشعارات فورية لجميع الأجهزة (Android & iOS)
/// مع محاكي حي لشكل الإشعار وقوالب جاهزة للتحديثات والصيانة.
/// Sent-log time for newest-first sorting; pending server timestamps first.
@visibleForTesting
DateTime sentAtOf(QueryDocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>?;
  final t = data?['createdAt'];
  return t is Timestamp ? t.toDate() : DateTime(9999);
}

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

  String _targetAudience = 'all'; // 'all', 'org', 'role', 'user'
  String _selectedType = 'update'; // 'update', 'announcement', 'support_alert'
  String _selectedRole = 'delegate'; // 'delegate', 'supervisor', 'marketing'
  String? _selectedOrgUID;
  List<Map<String, dynamic>> _organizations = [];
  bool _isLoadingOrgs = true;
  bool _isSending = false;
  bool _isPreviewAndroid = true; // true for Android, false for iOS

  @override
  void initState() {
    super.initState();
    // App update notices are for global staff only (TAS-268).
    if (!_isGlobalSender) _selectedType = 'announcement';
    _tabController = TabController(length: 2, vsync: this);
    _titleController.addListener(_onTextChanged);
    _bodyController.addListener(_onTextChanged);
    _fetchOrganizations();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  /// TAS-268: null for global staff (super admin / technical support);
  /// otherwise the only organization this sender may target.
  late final String? _orgScope = orgScopeFor(widget.senderDelegate);

  // Decision 2026-11-23 (TAS-216): only super admin / technical support
  // broadcast to the whole app; "all" from anyone else is their own scope
  // (the callable resolves it to their company or organization).
  bool get _isGlobalSender => _orgScope == null;
  bool get _isCompanySender =>
      widget.senderDelegate.companyUID.trim().isNotEmpty;

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.removeListener(_onTextChanged);
    _bodyController.removeListener(_onTextChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrganizations() async {
    try {
      final List<Map<String, dynamic>> orgs;
      final scope = _orgScope;
      if (scope != null) {
        // TAS-268: non-global staff only see their own organization.
        if (scope.isEmpty) {
          orgs = [];
        } else {
          final doc = await FirebaseFirestore.instance
              .collection('organizations')
              .doc(scope)
              .get();
          final data = doc.data() ?? const <String, dynamic>{};
          orgs = [
            {
              'uid': scope,
              'name': data['name'] ??
                  data['organizationName'] ??
                  data['title'] ??
                  widget.senderDelegate.organizationName,
            },
          ];
        }
      } else {
        final snap =
            await FirebaseFirestore.instance.collection('organizations').get();
        orgs = snap.docs.map((doc) {
          final data = doc.data();
          return {
            'uid': doc.id,
            'name': data['name'] ?? data['title'] ?? doc.id,
          };
        }).toList();
      }

      if (mounted) {
        setState(() {
          _organizations = orgs;
          if (_organizations.isNotEmpty) {
            _selectedOrgUID = _organizations.first['uid'];
          }
          _isLoadingOrgs = false;
        });
      }
    } catch (e) {
      debugPrint('SendNotificationScreen: load organizations failed: $e');
      if (mounted) {
        setState(() {
          _isLoadingOrgs = false;
          final scope = _orgScope;
          if (scope != null && scope.isNotEmpty) {
            // Still let the sender target their own org by id.
            _organizations = [
              {
                'uid': scope,
                'name': widget.senderDelegate.organizationName.isNotEmpty
                    ? widget.senderDelegate.organizationName
                    : scope,
              },
            ];
            _selectedOrgUID = scope;
          }
        });
      }
    }
  }

  void _applyPreset({
    required String title,
    required String body,
    required String type,
    String audience = 'all',
  }) {
    setState(() {
      _titleController.text = title;
      _bodyController.text = body;
      _selectedType = (!_isGlobalSender && type == 'update') ? 'announcement' : type;
      _targetAudience = audience;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تطبيق قالب: $title'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);

    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    try {
      // TAS-216: targeting and writes run in the scoped callable. The
      // server reads the sender's role and scope from users/{uid}.
      final payload = buildSendStaffNotificationPayload(
        title: title,
        body: body,
        type: _selectedType,
        audience: _targetAudience,
        role: _selectedRole,
        organizationUid: _selectedOrgUID,
        phone: _phoneController.text,
      );
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
            CloudCallableNames.sendStaffNotification,
            // Up to 10000 recipients: the server may take minutes.
            options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
          )
          .call<dynamic>(payload);
      final data = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : const <String, dynamic>{};
      final sentCount = (data['sent'] as num?)?.toInt() ?? 0;
      final targetName = (data['targetName'] as String?) ?? '';

      if (sentCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لم يتم العثور على مستلمين لهذا الاختيار داخل نطاقك.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Optional local test chime on sender device
      try {
        final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
        const androidDetails = AndroidNotificationDetails(
          'task_notifications',
          'إشعارات المهام والتحديثات',
          importance: Importance.high,
          priority: Priority.high,
        );
        const notificationDetails = NotificationDetails(android: androidDetails);
        await flutterLocalNotificationsPlugin.show(
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title,
          body,
          notificationDetails,
        );
      } catch (_) {}

      if (mounted) {
        _titleController.clear();
        _bodyController.clear();
        _phoneController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('تم إرسال الإشعار السحابي بنجاح إلى $targetName 🚀'),
                ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        _tabController.animateTo(1);
      }
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final reason =
          details is Map ? details['reason']?.toString() : null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sendStaffNotificationErrorMessage(e.code, reason)),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('SendNotificationScreen: send failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sendNotificationErrorMessage(e)),
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
        Tab(icon: Icon(Icons.send_rounded), text: 'إنشاء وبث إشعار جديد'),
        Tab(
          icon: Icon(Icons.outbox_rounded),
          text: 'سجل الحملات الصادرة',
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
              children: [
                _buildComposeTab(theme, colorScheme),
                _buildSentHistoryTab(),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              'مركز بث الإشعارات السحابية',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'بث فوري لجميع الأجهزة (Android & iOS)',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        centerTitle: true,
        bottom: tabBar,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildComposeTab(theme, colorScheme),
          _buildSentHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildComposeTab(ThemeData theme, ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 920;

        if (isDesktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column (in RTL: inputs column)
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildComposerForm(theme, colorScheme),
                ),
              ),
              // Vertical Divider
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              // Right Column (in RTL: Device Live Mockup Preview)
              Expanded(
                flex: 4,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildDevicePreviewColumn(theme, colorScheme),
                ),
              ),
            ],
          );
        }

        // Mobile Layout: Stacked with Collapsible Mockup
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPresetsBar(colorScheme),
              const SizedBox(height: 16),
              // Mobile Mockup Preview Card
              _buildDevicePreviewCardMobile(theme, colorScheme),
              const SizedBox(height: 16),
              _buildComposerForm(theme, colorScheme, showPresets: false),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPresetsBar(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt_rounded, size: 18, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'قوالب إشعارات سريعة (بضغطة زر واحدة)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // TAS-268: app update templates are for global staff only.
              if (_isGlobalSender) ...[
              _buildPresetChip(
                label: '🚀 تحديث إلزامي فوري',
                colorScheme: colorScheme,
                onTap: () => _applyPreset(
                  title: 'تحديث إلزامي جديد متوفر للتطبيق 🚀',
                  body:
                      'يرجى تحديث التطبيق الآن فوراً من المتجر (Google Play أو App Store) لضمان استمرار الخدمة وتجنب أي انقطاع.',
                  type: 'update',
                ),
              ),
              const SizedBox(width: 8),
              _buildPresetChip(
                label: '✨ إصدار جديد ومميزات',
                colorScheme: colorScheme,
                onTap: () => _applyPreset(
                  title: 'إصدار جديد متاح الآن ✨',
                  body:
                      'تم إطلاق إصدار جديد يضم ميزات وتحسينات جديدة للأداء. حدّث تطبيقك الآن لتجربة أسرع وأسهل.',
                  type: 'update',
                ),
              ),
              const SizedBox(width: 8),
              ],
              _buildPresetChip(
                label: '⚙️ صيانة مجدولة',
                colorScheme: colorScheme,
                onTap: () => _applyPreset(
                  title: 'تنبيه: صيانة دورية مجدولة ⚙️',
                  body:
                      'نود إحاطتكم علماً بوجود أعمال صيانة دورية لتحسين كفاءة الخوادم، قد يحدث بطء طفيف لعدة دقائق.',
                  type: 'announcement',
                ),
              ),
              const SizedBox(width: 8),
              _buildPresetChip(
                label: '📢 تعميم إداري عام',
                colorScheme: colorScheme,
                onTap: () => _applyPreset(
                  title: 'تعميم إداري هام 📋',
                  body:
                      'تنبيه لجميع منسوبي العمل، يرجى الالتزام بالتعليمات والمهام الموكلة إليكم والتحقق من الحضور اليومي بدقة.',
                  type: 'announcement',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip({
    required String label,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      onPressed: onTap,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildComposerForm(ThemeData theme, ColorScheme colorScheme, {bool showPresets = true}) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showPresets) ...[
            _buildPresetsBar(colorScheme),
            const SizedBox(height: 20),
          ],

          // Notification Type Selector Chips
          Text(
            'نوع الإشعار',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_isGlobalSender) ...[
                Expanded(
                  child: _buildTypeSelectTile(
                    title: 'تحديث تطبيق',
                    subtitle: 'مع زر للمتجر',
                    value: 'update',
                    icon: Icons.system_update_rounded,
                    colorScheme: colorScheme,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _buildTypeSelectTile(
                  title: 'إعلان عام',
                  subtitle: 'تعميم إداري',
                  value: 'announcement',
                  icon: Icons.campaign_rounded,
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTypeSelectTile(
                  title: 'تنبيه نظام',
                  subtitle: 'دعم فني',
                  value: 'support_alert',
                  icon: Icons.notifications_active_rounded,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

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
              hintText: 'مثال: تحديث إلزامي جديد متوفر للتطبيق 🚀',
              prefixIcon: const Icon(Icons.title_rounded),
              filled: true,
              fillColor: colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
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
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'يرجى إدخال عنوان الإشعار' : null,
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
              hintText: 'اكتب نص الإشعار هنا بالتفصيل ليظهر على شاشات المستخدمين...',
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 55),
                child: Icon(Icons.notes_rounded),
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
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
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'يرجى إدخال نص الإشعار' : null,
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
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                _buildAudienceOptionTile(
                  title: _isGlobalSender
                      ? 'جميع مستخدمي التطبيق (بث شامل)'
                      : (_isCompanySender ? 'جميع مستخدمي شركتك' : 'جميع مستخدمي منظمتك'),
                  subtitle: _isGlobalSender
                      ? 'يصل فورياً لجميع هواتف Android و iOS عبر موضوع app_updates'
                      : 'الإرسال داخل نطاقك فقط',
                  value: 'all',
                  icon: Icons.public_rounded,
                  badge: 'الأشمل',
                ),
                const Divider(height: 1),
                _buildAudienceOptionTile(
                  title: 'حسب الدور الوظيفي (فئة محددة)',
                  subtitle: 'مناديب فقط، مشرفين، أو مسؤولي تسويق',
                  value: 'role',
                  icon: Icons.groups_rounded,
                ),
                const Divider(height: 1),
                _buildAudienceOptionTile(
                  title: 'قطاع / منظمة محددة',
                  subtitle: 'تخصيص الإشعار لمنظمة معينة',
                  value: 'org',
                  icon: Icons.corporate_fare_rounded,
                ),
                const Divider(height: 1),
                _buildAudienceOptionTile(
                  title: 'مستخدم فردي (برقم الهاتف)',
                  subtitle: 'إرسال الإشعار لشخص واحد بالهاتف',
                  value: 'user',
                  icon: Icons.person_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Conditional Target Sub-forms
          if (_targetAudience == 'role') ...[
            Text(
              'اختر الفئة الوظيفية المستهدفة',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: InputDecoration(
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'delegate', child: Text('جميع المناديب والمروجين')),
                DropdownMenuItem(value: 'supervisor', child: Text('جميع المشرفين')),
                DropdownMenuItem(value: 'marketing', child: Text('مسؤولو تسويق الفروع')),
                DropdownMenuItem(value: 'admin', child: Text('مشرفو ومسؤولو الشركات')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedRole = val);
              },
            ),
            const SizedBox(height: 18),
          ],

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
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<String>(
                    initialValue: _selectedOrgUID,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colorScheme.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    items: _organizations.map((org) {
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
                fillColor: colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              validator: (v) =>
                  _targetAudience == 'user' && (v == null || v.trim().isEmpty)
                      ? 'يرجى إدخال رقم هاتف المستخدم'
                      : null,
            ),
            const SizedBox(height: 18),
          ],

          const SizedBox(height: 12),

          // Broadcast Action Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _isSending ? null : _sendNotification,
              icon: _isSending
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: colorScheme.onPrimary,
                        strokeWidth: 2.2,
                      ),
                    )
                  : const Icon(Icons.campaign_rounded, size: 22),
              label: Text(
                _isSending
                    ? 'جاري البث والإرسال لجميع الأجهزة...'
                    : 'بث وإرسال الإشعار الآن 🚀',
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
    );
  }

  Widget _buildTypeSelectTile({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _selectedType == value;
    return InkWell(
      onTap: () => setState(() => _selectedType = value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.6)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
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
    String? badge,
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
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Icon(
              icon,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
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
  // Live Device Mockup Preview Column (Desktop/Web)
  // ----------------------------------------------------
  Widget _buildDevicePreviewColumn(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Preview Header + Toggle between Android and iOS
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.remove_red_eye_rounded, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'معاينة حية للموبايل',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Android', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.android_rounded, size: 14),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('iOS', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.apple_rounded, size: 14),
                  ),
                ],
                selected: {_isPreviewAndroid},
                onSelectionChanged: (set) {
                  setState(() => _isPreviewAndroid = set.first);
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Realistic Phone Mockup Frame
        _buildPhoneFrame(colorScheme),
      ],
    );
  }

  Widget _buildDevicePreviewCardMobile(ThemeData theme, ColorScheme colorScheme) {
    return ExpansionTile(
      initiallyExpanded: false,
      collapsedBackgroundColor: colorScheme.surfaceContainerLow,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      leading: Icon(Icons.phone_android_rounded, color: colorScheme.primary),
      title: const Text(
        'معاينة شكل الإشعار على الهاتف',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
      ),
      subtitle: Text(
        'اضغط لمشاهدة كيف سيظهر التنبيه للمستخدمين',
        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: _buildDevicePreviewColumn(theme, colorScheme),
        ),
      ],
    );
  }

  Widget _buildPhoneFrame(ColorScheme colorScheme) {
    final title = _titleController.text.trim().isEmpty
        ? 'عنوان الإشعار سيظهر هنا...'
        : _titleController.text.trim();
    final body = _bodyController.text.trim().isEmpty
        ? 'نص ومحتوى الرسالة سيظهر هنا بشكل واضح على شاشة قفل هاتف المستخدم...'
        : _bodyController.text.trim();

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF121316),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: const Color(0xFF2C2D32), width: 5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Speaker / Dynamic Island or Notch
          Container(
            width: _isPreviewAndroid ? 50 : 80,
            height: _isPreviewAndroid ? 4 : 14,
            decoration: BoxDecoration(
              color: const Color(0xFF28292E),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 12),

          // Status Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('hh:mm').format(DateTime.now()),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Row(
                children: [
                  Icon(Icons.wifi_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Icon(Icons.signal_cellular_alt_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Icon(Icons.battery_full_rounded, color: Colors.white, size: 14),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Notification Banner on Phone Screen
          if (_isPreviewAndroid)
            _buildAndroidNotificationCard(title, body, colorScheme)
          else
            _buildIosNotificationCard(title, body, colorScheme),

          const SizedBox(height: 50),

          // Bottom Home Indicator Bar
          Container(
            width: 100,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildAndroidNotificationCard(String title, String body, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2024),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App Header Row
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 11),
              ),
              const SizedBox(width: 6),
              const Text(
                'تساهيل',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '• الآن',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const Spacer(),
              const Icon(Icons.expand_more_rounded, color: Colors.white38, size: 16),
            ],
          ),
          const SizedBox(height: 8),

          // Title
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),

          // Body
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),

          // If Type is Update -> Action Button
          if (_selectedType == 'update') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.system_update_rounded, size: 13, color: colorScheme.primary),
                  const SizedBox(width: 5),
                  Text(
                    'تحديث التطبيق الآن',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIosNotificationCard(String title, String body, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF24262B).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 12),
              ),
              const SizedBox(width: 8),
              const Text(
                'تساهيل',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              const Text(
                'الآن',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (_selectedType == 'update') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'فتح المتجر للتحديث',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // Sent History / Outbox Tab with Realtime Read Status
  // ----------------------------------------------------
  /// The outbox lists the most recent sent notifications only (TAS-90).
  static const int _sentHistoryLimit = 50;

  Widget _buildSentHistoryTab() {
    // Subscribed once, not on every build: the compose form calls setState
    // on every keystroke (TAS-90).
    return KeyedStreamBuilder<QuerySnapshot>(
      streamKey: 'sent_notifications',
      // TAS-268: non-global senders see only what they sent (the rules allow
      // reading own entries only). Sorted on the client so no
      // senderUid+createdAt index is needed.
      create: () => _isGlobalSender
          ? FirebaseFirestore.instance
              .collection('sent_notifications')
              .orderBy('createdAt', descending: true)
              .limit(_sentHistoryLimit)
              .snapshots()
          : FirebaseFirestore.instance
              .collection('sent_notifications')
              .where('senderUid', isEqualTo: widget.senderDelegate.uid)
              .limit(_sentHistoryLimit)
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

        final docs = [...?snapshot.data?.docs]
          ..sort((a, b) => sentAtOf(b).compareTo(sentAtOf(a)));
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
                  'أي إشعار ستقوم ببثه سيظهر هنا في السجل مع إمكانية إعادة إرساله بنقرة واحدة.',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _SentNotificationCard(
              docId: doc.id,
              data: data,
              onResend: (t, b, type, aud, ph) {
                _titleController.text = t;
                _bodyController.text = b;
                _selectedType =
                    (!_isGlobalSender && type == 'update') ? 'announcement' : type;
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
    String type,
    String audience,
    String phone,
  ) onResend;

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
    final type = data['type'] as String? ?? 'update';
    final rawTargetName = data['targetName'] as String? ?? 'الجميع';
    final targetName = rawTargetName.replaceAll(RegExp(r'\s*\(\+?\d+\)\s*'), '').trim();
    final senderName = data['senderName'] as String? ?? 'الدعم الفني';
    final timestamp = data['createdAt'] as Timestamp?;
    final dateStr = timestamp != null
        ? DateFormat('dd/MM/yyyy • hh:mm a').format(timestamp.toDate())
        : 'الآن';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showNotificationDetails(context, dateStr),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // 1. Icon Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _getTypeBackgroundColor(type, colorScheme),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(
                    _getTypeIcon(type),
                    color: _getTypeColor(type, colorScheme),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // 2. Middle Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getTypeColor(type, colorScheme).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _getTypeLabel(type),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _getTypeColor(type, colorScheme),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    Text(
                      body.isNotEmpty ? '$title: $body' : title,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 12, color: colorScheme.outline),
                        const SizedBox(width: 4),
                        Text(
                          dateStr,
                          style: TextStyle(fontSize: 11, color: colorScheme.outline),
                        ),
                        if (senderName.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '• $senderName',
                              style: TextStyle(fontSize: 11, color: colorScheme.outline),
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
              const SizedBox(width: 8),

              // 3. Actions: Resend Button & Details Button
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(8),
                    ),
                    icon: const Icon(Icons.repeat_rounded, size: 18),
                    tooltip: 'إعادة إرسال نفس الإشعار',
                    onPressed: () {
                      final targetAudience = data['targetAudience'] as String? ?? 'all';
                      final targetName = data['targetName'] as String? ?? '';
                      String phone = '';
                      if (targetAudience == 'user') {
                        final match = RegExp(r'(\+?\d{10,14})').firstMatch(targetName);
                        if (match != null) phone = match.group(0) ?? '';
                      }
                      onResend(title, body, type, targetAudience, phone);
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(8),
                    ),
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    tooltip: 'عرض التفاصيل',
                    onPressed: () => _showNotificationDetails(context, dateStr),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'update':
        return Icons.system_update_rounded;
      case 'announcement':
        return Icons.campaign_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _getTypeColor(String type, ColorScheme colorScheme) {
    switch (type) {
      case 'update':
        return colorScheme.primary;
      case 'announcement':
        return colorScheme.tertiary;
      default:
        return colorScheme.secondary;
    }
  }

  Color _getTypeBackgroundColor(String type, ColorScheme colorScheme) {
    switch (type) {
      case 'update':
        return colorScheme.primaryContainer;
      case 'announcement':
        return colorScheme.tertiaryContainer;
      default:
        return colorScheme.secondaryContainer;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'update':
        return 'تحديث تطبيق';
      case 'announcement':
        return 'إعلان عام';
      default:
        return 'تنبيه نظام';
    }
  }

  void _showNotificationDetails(BuildContext context, String dateStr) {
    final title = data['title'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final targetDetails = data['targetDetails'] as String? ?? data['targetName'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.mark_email_read_rounded, color: Theme.of(ctx).colorScheme.primary),
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
                _buildDetailRow(ctx, 'العنوان', title),
                const Divider(),
                _buildDetailRow(ctx, 'المحتوى', body),
                const Divider(),
                _buildDetailRow(ctx, 'المستهدف', targetDetails),
                const Divider(),
                _buildDetailRow(ctx, 'المرسل', data['senderName'] ?? ''),
                const Divider(),
                _buildDetailRow(ctx, 'تاريخ الإرسال', dateStr),
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

/// TAS-268: a clear Arabic message for a failed send (never the raw error).
@visibleForTesting
String sendNotificationErrorMessage(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'ليس لديك صلاحية لإرسال هذا الإشعار لهذه الفئة. تواصل مع الإدارة.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'تعذّر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى.';
    }
  }
  return 'تعذّر إرسال الإشعار. حاول مرة أخرى.';
}
