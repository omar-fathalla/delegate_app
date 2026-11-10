import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';

class NotificationModel extends NotificationEntity {
  const NotificationModel({
    required super.id,
    required super.delegateUid,
    required super.organizationId,
    required super.companyId,
    required super.title,
    required super.body,
    required super.type,
    super.taskId,
    super.penaltyId,
    required super.isRead,
    required super.createdAt,
    super.deletedBy,
    super.senderName,
    super.senderRole,
  });

  /// Sanitizes text by completely removing raw unicode emojis, makeshift checkmarks, etc.
  static String sanitizeText(String text) {
    if (text.isEmpty) return text;
    return text
        .replaceAll(
          RegExp(
            r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE00}-\u{FE0F}\u{1F900}-\u{1F9FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{2B50}\u{2B55}\u{231A}-\u{23F3}\u{2934}-\u{2935}\u{25AA}-\u{25FE}]',
            unicode: true,
          ),
          '',
        )
        .replaceAll('✅', '')
        .replaceAll('❌', '')
        .replaceAll('✔️', '')
        .replaceAll('✓', '')
        .replaceAll('✔', '')
        .replaceAll('☑️', '')
        .replaceAll('☑', '')
        .replaceAll('✖️', '')
        .replaceAll('✖', '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// Maps internal user role strings to standard human-readable Arabic labels.
  static String formatSenderRoleArabic(String? role) {
    if (role == null || role.trim().isEmpty) return 'النظام';
    final r = role.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_').trim();
    if (r.contains('supervis')) return 'مشرف الشركة';
    if (r.contains('super')) return 'سوبر أدمن';
    if (r.contains('org') || r == 'organization_admin') return 'مسؤول المنظمة';
    if (r.contains('branch') || r == 'branches_marketing' || r == 'branches_marketing_manager') {
      return 'مسؤول تسويق الفروع';
    }
    if (r == 'marketing_promotion' || r == 'marketingpromotion' || r == 'promotion_marketing' || r == 'promotionmarketing') return 'مسؤول تسويق العروض';
    if (r.contains('market')) return 'مسؤول التسويق';
    if (r.contains('support') || r.contains('tech')) return 'الدعم الفني';
    if (r == 'company_admin' || r == 'admin') return 'مشرف الشركة';
    if (r.contains('promoter')) return 'مروج';
    if (r.contains('delegate')) return 'مندوب';
    if (r.contains('system')) return 'النظام';
    return role;
  }

  NotificationModel copyWith({
    String? id,
    String? delegateUid,
    String? organizationId,
    String? companyId,
    String? title,
    String? body,
    String? type,
    String? taskId,
    String? penaltyId,
    bool? isRead,
    DateTime? createdAt,
    List<String>? deletedBy,
    String? senderName,
    String? senderRole,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      delegateUid: delegateUid ?? this.delegateUid,
      organizationId: organizationId ?? this.organizationId,
      companyId: companyId ?? this.companyId,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      taskId: taskId ?? this.taskId,
      penaltyId: penaltyId ?? this.penaltyId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      deletedBy: deletedBy ?? this.deletedBy,
      senderName: senderName ?? this.senderName,
      senderRole: senderRole ?? this.senderRole,
    );
  }

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawDeletedBy = data['deletedBy'];
    final List<String> deletedBy = rawDeletedBy is List
        ? rawDeletedBy.map((e) => e.toString()).toList()
        : const [];

    final rawTitle = (data['title'] ?? '').toString();
    final rawBody = (data['body'] ?? '').toString();
    final cleanTitle = sanitizeText(rawTitle);
    final cleanBody = sanitizeText(rawBody);
    final notifType = (data['type'] ?? 'general').toString();

    // 1. Direct sender resolution from stored fields
    String? senderName = (data['senderName'] ??
            data['createdByName'] ??
            data['authorName'] ??
            data['reviewerName'] ??
            data['approvedByName'] ??
            data['supervisorName'] ??
            data['sender']) as String?;

    String? senderRole = (data['senderRole'] ??
            data['creatorRole'] ??
            data['createdByUserRole'] ??
            data['role'] ??
            data['senderType']) as String?;

    // 2. Backward compatibility & smart regex inference from raw body/title
    if (senderName == null || senderName.trim().isEmpty) {
      // Check if body begins with approval: e.g. "اعتمد Mohamed Fadl الغرامة"
      final matchApproved = RegExp(
        r'^(?:اعتمد|وافق|رفض|أصدر|سجل)\s+([^\s]+(?:\s+[^\s]+)?)\s+',
      ).firstMatch(rawBody);
      if (matchApproved != null) {
        senderName = matchApproved.group(1)?.trim();
      }

      // Check "من قبل (Mohamed Fadl)" or "من قبل Mohamed Fadl"
      if (senderName == null || senderName.isEmpty) {
        final matchBy = RegExp(r'من قبل\s+\(?([^\)\.\n]+)\)?').firstMatch(rawBody);
        if (matchBy != null) {
          senderName = matchBy.group(1)?.trim();
        }
      }

      // Check "قام المشرف فلان"
      if (senderName == null || senderName.isEmpty) {
        final matchSup = RegExp(r'قام المشرف\s+([^\(]+?)\s*(?:\(|\b)').firstMatch(rawBody);
        if (matchSup != null) {
          senderName = matchSup.group(1)?.trim();
          senderRole ??= 'supervisor';
        }
      }

      // Check "قام المندوب فلان"
      if (senderName == null || senderName.isEmpty) {
        final matchDel = RegExp(r'قام المندوب\s+([^\s]+(?:\s+[^\s]+)?)\s+').firstMatch(rawBody);
        if (matchDel != null) {
          senderName = matchDel.group(1)?.trim();
          senderRole ??= 'delegate';
        }
      }

      // Check "بواسطة فلان"
      if (senderName == null || senderName.isEmpty) {
        final matchBy2 = RegExp(r'بواسطة\s+([^\.\n]+)').firstMatch(rawBody);
        if (matchBy2 != null) {
          senderName = matchBy2.group(1)?.trim();
        }
      }

      // Attendance check-in / check-out: sender is the delegate
      if ((senderName == null || senderName.isEmpty) &&
          (notifType == 'attendance_check_in' ||
              notifType == 'attendance_check_out' ||
              data['attendanceType'] != null)) {
        senderName = (data['targetDelegateName'] ?? data['delegateName']) as String?;
        senderRole ??= 'delegate';
      }

      // Wallet transactions: sender is financial management
      if ((senderName == null || senderName.isEmpty) &&
          (notifType == 'wallet_allocation' || notifType == 'wallet_payout')) {
        senderName = 'الإدارة العامة';
        senderRole ??= 'superAdmin';
      }
    }

    // 3. Fallback role inference
    if (senderRole == null || senderRole.trim().isEmpty) {
      if (rawTitle.contains('اعتماد نهائي') ||
          rawBody.contains('المدير العام') ||
          rawTitle.contains('تسوية وصرف') ||
          rawTitle.contains('إيداع رصيد')) {
        senderRole = 'superAdmin';
      } else if (rawTitle.contains('تسويق الفروع') ||
          rawBody.contains('مدير تسويق الفروع') ||
          rawBody.contains('تسويق الفروع')) {
        senderRole = 'branchesMarketingManager';
      } else if (notifType == 'attendance_check_in' ||
          notifType == 'attendance_check_out' ||
          notifType == 'delegate_camera_capture') {
        senderRole = 'delegate';
      } else if (notifType == 'support_alert' ||
          notifType == 'support_direct' ||
          notifType == 'technical_support_broadcast') {
        senderRole = 'technicalSupport';
      } else if (rawTitle.contains('مخالفة') || rawTitle.contains('إضافة مندوب')) {
        senderRole = 'supervisor';
      } else {
        senderRole = 'system';
      }
    }

    // Default fallback sender name
    if (senderName == null || senderName.trim().isEmpty) {
      if (senderRole == 'superAdmin') {
        senderName = 'الإدارة العامة';
      } else if (senderRole == 'technicalSupport') {
        senderName = 'الدعم الفني';
      } else if (senderRole == 'branchesMarketingManager') {
        senderName = 'تسويق الفروع';
      } else {
        senderName = 'إدارة النظام';
      }
    }

    return NotificationModel(
      id: doc.id,
      delegateUid: data['delegateUid'] ?? '',
      organizationId: data['organizationId'] ?? '',
      companyId: data['companyId'] ?? '',
      title: cleanTitle,
      body: cleanBody,
      type: notifType,
      taskId: data['taskId'],
      penaltyId: data['penaltyId'] ?? data['penaltyID'],
      isRead: data['isRead'] ?? data['read'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deletedBy: deletedBy,
      senderName: senderName,
      senderRole: senderRole,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'delegateUid': delegateUid,
      'organizationId': organizationId,
      'companyId': companyId,
      'title': title,
      'body': body,
      'type': type,
      'taskId': taskId,
      'penaltyId': penaltyId,
      'isRead': isRead,
      'read': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedBy': deletedBy,
      if (senderName != null) 'senderName': senderName,
      if (senderRole != null) 'senderRole': senderRole,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'delegateUid': delegateUid,
      'organizationId': organizationId,
      'companyId': companyId,
      'title': title,
      'body': body,
      'type': type,
      'taskId': taskId,
      'penaltyId': penaltyId,
      'isRead': isRead,
      'createdAt': createdAt.toIso8601String(),
      'deletedBy': deletedBy,
      'senderName': senderName,
      'senderRole': senderRole,
    };
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final rawDeletedBy = json['deletedBy'];
    final List<String> deletedBy = rawDeletedBy is List
        ? rawDeletedBy.map((e) => e.toString()).toList()
        : const [];

    return NotificationModel(
      id: json['id'] ?? '',
      delegateUid: json['delegateUid'] ?? '',
      organizationId: json['organizationId'] ?? '',
      companyId: json['companyId'] ?? '',
      title: sanitizeText(json['title'] ?? ''),
      body: sanitizeText(json['body'] ?? ''),
      type: json['type'] ?? 'general',
      taskId: json['taskId'],
      penaltyId: json['penaltyId'],
      isRead: json['isRead'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      deletedBy: deletedBy,
      senderName: json['senderName'],
      senderRole: json['senderRole'],
    );
  }
}

