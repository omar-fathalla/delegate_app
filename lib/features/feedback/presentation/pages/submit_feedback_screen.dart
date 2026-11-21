import 'package:material_symbols_icons/symbols.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_event.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_state.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:go_router/go_router.dart';

class SubmitFeedbackScreen extends StatefulWidget {
  final Delegate delegate;

  /// False inside the web HR shell, where the inner page breadcrumb carries
  /// the title and the back button (TAS-157).
  final bool showAppBar;

  const SubmitFeedbackScreen({
    super.key,
    required this.delegate,
    this.showAppBar = true,
  });

  @override
  State<SubmitFeedbackScreen> createState() => _SubmitFeedbackScreenState();
}

class _SubmitFeedbackScreenState extends State<SubmitFeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  FeedbackType _selectedType = FeedbackType.featureRequest;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  void _submitFeedback() {
    if (_formKey.currentState!.validate()) {
      context.read<FeedbackBloc>().add(
        SubmitFeedbackEvent(
          userId: widget.delegate.uid,
          userName: widget.delegate.fullName,
          userEmail: 'support@sw-point.com', // يمكن تغييره حسب الحاجة
          type: _selectedType,
          content: _contentController.text.trim(),
          screenshot: _selectedImage,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(AppLocalizations.of(context)!.sendFeedback),
              centerTitle: true,
            )
          : null,
      body: BlocListener<FeedbackBloc, FeedbackState>(
        listener: (context, state) {
          if (state is FeedbackSubmitted) {
            _showSuccessDialog(context, isArabic);
          } else if (state is FeedbackError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        child: BlocBuilder<FeedbackBloc, FeedbackState>(
          builder: (context, state) {
            if (state is FeedbackSubmitting) {
              return const Center(child: CircularProgressIndicator());
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // رسالة ترحيبية
                    Card(
                      color: theme.colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              size: 32,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(AppLocalizations.of(context)!.feedbackIntro,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // نوع المقترح
                    Text(AppLocalizations.of(context)!.feedbackType,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: FeedbackType.values.map((type) {
                        final isSelected = _selectedType == type;
                        return ChoiceChip(
                          avatar: Icon(_feedbackIcon(type), size: 18),
                          label: Text(_feedbackLabel(context, type)),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedType = type;
                              });
                            }
                          },
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? theme.colorScheme.onSecondaryContainer
                                : theme.colorScheme.onSurface,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // محتوى الرسالة
                    Text(AppLocalizations.of(context)!.yourMessage,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _contentController,
                      maxLines: 8,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context)!.feedbackHint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return AppLocalizations.of(context)!.enterMessage;
                        }
                        if (value.trim().length < 10) {
                          return AppLocalizations.of(context)!.messageTooShort;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // إرفاق صورة
                    Text(AppLocalizations.of(context)!.screenshotOptional,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedImage != null)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _selectedImage!,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              onPressed: _removeImage,
                              icon: const Icon(Icons.close),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: Text(AppLocalizations.of(context)!.chooseImage),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    const SizedBox(height: 32),

                    // زر الإرسال
                    FilledButton.icon(
                      onPressed: _submitFeedback,
                      icon: const Icon(Icons.send),
                      label: Text(AppLocalizations.of(context)!.sendAction,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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

  void _showSuccessDialog(BuildContext context, bool isArabic) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.thankYou,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context)!.feedbackReceived,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // إغلاق الـ Dialog
              // Back to the previous page. In the web shell the page sits on
              // the shell's inner navigator, not on the router.
              if (widget.showAppBar) {
                context.pop();
              } else {
                Navigator.of(this.context).pop();
              }
            },
            child: Text(AppLocalizations.of(context)!.okAction),
          ),
        ],
      ),
    );
  }

  IconData _feedbackIcon(FeedbackType t) => switch (t) {
        FeedbackType.featureRequest => Symbols.lightbulb_rounded,
        FeedbackType.bugReport => Symbols.bug_report_rounded,
        FeedbackType.generalQuestion => Symbols.help_rounded,
        FeedbackType.improvement => Symbols.star_rounded,
        FeedbackType.other => Symbols.edit_note_rounded,
      };

  String _feedbackLabel(BuildContext context, FeedbackType t) {
    final l10n = AppLocalizations.of(context)!;
    return switch (t) {
      FeedbackType.featureRequest => l10n.feedbackTypeFeature,
      FeedbackType.bugReport => l10n.feedbackTypeBug,
      FeedbackType.generalQuestion => l10n.feedbackTypeQuestion,
      FeedbackType.improvement => l10n.feedbackTypeImprovement,
      FeedbackType.other => l10n.feedbackTypeOther,
    };
  }
}
