import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:url_launcher/url_launcher.dart';

/// ويدجت وخدمة عرض مستندات وإيصالات المخالفات داخل التطبيق دون الخروج منه
class PenaltyEvidenceViewer {
  /// عرض مستندات المخالفة (إيصال أو صورة أو مستند) داخل التطبيق
  static void showEvidence(
    BuildContext context, {
    required PenaltyEntity penalty,
  }) {
    if (penalty.evidenceFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستندات مرفقة لهذه المخالفة')),
      );
      return;
    }

    // إذا كان هناك ملف واحد فقط وهو صورة، افتح عارض الصور مباشرة لراحة المستخدم
    if (penalty.evidenceFiles.length == 1) {
      final file = penalty.evidenceFiles.first;
      if (_isImageFile(file)) {
        showImageLightbox(
          context,
          imageUrl: file.fileUrl,
          title: penalty.title,
          subtitle: penalty.companyName,
          fileName: file.fileName,
        );
        return;
      }
    }

    // إذا كانت هناك ملفات متعددة أو ملف PDF، أظهر نافذة اختيار واستعراض المستندات
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EvidenceListBottomSheet(penalty: penalty),
    );
  }

  /// عارض الصور التفاعلي المكبر داخل التطبيق (InteractiveViewer Lightbox)
  static void showImageLightbox(
    BuildContext context, {
    required String imageUrl,
    String? title,
    String? subtitle,
    String? fileName,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title ?? 'إيصال / مستند المخالفة',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null && subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Interactive Image Container
              Flexible(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Container(
                    color: Colors.black,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.7,
                      maxWidth: double.infinity,
                    ),
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 5.0,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                        errorWidget: (context, url, error) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.broken_image_rounded,
                                    color: Colors.white54, size: 48),
                                const SizedBox(height: 12),
                                const Text(
                                  'تعذّر عرض الصورة من الخادم',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () async {
                                    final uri = Uri.parse(imageUrl);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri,
                                          mode: LaunchMode.externalApplication);
                                    }
                                  },
                                  icon: const Icon(Icons.open_in_browser_rounded,
                                      size: 16),
                                  label: const Text('فتح في المتصفح'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// عارض الصور المحلية أثناء الرفع في شاشة تسجيل المخالفة
  static void showLocalImageLightbox(
    BuildContext context, {
    required File file,
  }) {
    final fileName = file.path.split('/').last.split('\\').last;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Container(
                    color: Colors.black,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.7,
                      maxWidth: double.infinity,
                    ),
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 5.0,
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static bool _isImageFile(EvidenceFile file) {
    if (file.fileType.toUpperCase() == 'IMAGE' || file.fileType.toUpperCase() == 'IMG') {
      return true;
    }
    final name = file.fileName.toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif') ||
        name.endsWith('.bmp');
  }
}

/// نافذة سفلية تعرض فقاعات وبطاقات المستندات المرفقة للمخالفة
class _EvidenceListBottomSheet extends StatelessWidget {
  final PenaltyEntity penalty;

  const _EvidenceListBottomSheet({required this.penalty});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: colorScheme.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المستندات والإيصالات المرفقة',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${penalty.companyName} - ${penalty.title}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // Evidence Grid / List
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.55,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: penalty.evidenceFiles.length,
              separatorBuilder: (c, i) => const SizedBox(height: 10),
              itemBuilder: (ctx, index) {
                final file = penalty.evidenceFiles[index];
                final isImage = PenaltyEvidenceViewer._isImageFile(file);

                return InkWell(
                  onTap: () {
                    if (isImage) {
                      PenaltyEvidenceViewer.showImageLightbox(
                        context,
                        imageUrl: file.fileUrl,
                        title: penalty.title,
                        subtitle: '${penalty.companyName} (${index + 1}/${penalty.evidenceFiles.length})',
                        fileName: file.fileName,
                      );
                    } else {
                      _openFile(file.fileUrl);
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Thumbnail Preview
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 60,
                            height: 60,
                            color: colorScheme.surfaceContainerHighest,
                            child: isImage
                                ? CachedNetworkImage(
                                    imageUrl: file.fileUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                    errorWidget: (context, url, err) => Icon(
                                      Icons.image_rounded,
                                      color: colorScheme.primary,
                                    ),
                                  )
                                : Icon(
                                    file.fileType == 'PDF'
                                        ? Icons.picture_as_pdf_rounded
                                        : Icons.insert_drive_file_rounded,
                                    color: colorScheme.primary,
                                    size: 30,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // File Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.fileName.isNotEmpty
                                    ? file.fileName
                                    : 'إيصال / مستند #${index + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isImage
                                          ? colorScheme.primaryContainer
                                          : colorScheme.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isImage ? 'صورة / إيصال' : file.fileType,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isImage
                                            ? colorScheme.onPrimaryContainer
                                            : colorScheme.onTertiaryContainer,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isImage ? 'اضغط للمعاينة والتكبير' : 'اضغط للفتح',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Action Icon
                        IconButton(
                          icon: Icon(
                            isImage
                                ? Icons.zoom_in_rounded
                                : Icons.open_in_new_rounded,
                            color: colorScheme.primary,
                          ),
                          onPressed: () {
                            if (isImage) {
                              PenaltyEvidenceViewer.showImageLightbox(
                                context,
                                imageUrl: file.fileUrl,
                                title: penalty.title,
                                subtitle: '${penalty.companyName} (${index + 1}/${penalty.evidenceFiles.length})',
                                fileName: file.fileName,
                              );
                            } else {
                              _openFile(file.fileUrl);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openFile(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
