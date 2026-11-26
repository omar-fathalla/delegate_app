import 'package:delegate_app/core/design/widgets/loading_indicator.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
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
            _onSubmitted(context);
          } else if (state is FeedbackError) {
            showTashilSnackBar(context, state.message);
          }
        },
        child: BlocBuilder<FeedbackBloc, FeedbackState>(
          builder: (context, state) {
            if (state is FeedbackSubmitting) {
              return const Center(child: LoadingIndicator());
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(TashilSpacing.page),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // TAS-358: intro on a filled card with the card-icon
                    // rule (primary + onPrimary).
                    Card.filled(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(TashilSpacing.lg),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(TashilSpacing.sm),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.lightbulb_outline,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                            const SizedBox(width: TashilSpacing.md),
                            Expanded(
                              child: Text(
                                AppLocalizations.of(context)!.feedbackIntro,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: TashilSpacing.xl),

                    // TAS-358 (C-11): one type, single-select FilterChips.
                    Text(
                      AppLocalizations.of(context)!.feedbackType,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: TashilSpacing.sm),
                    Wrap(
                      spacing: TashilSpacing.sm,
                      runSpacing: TashilSpacing.sm,
                      children: FeedbackType.values.map((type) {
                        return FilterChip(
                          key: ValueKey('feedback_type_${type.name}'),
                          avatar: Icon(_feedbackIcon(type)),
                          label: Text(_feedbackLabel(context, type)),
                          selected: _selectedType == type,
                          onSelected: (_) =>
                              setState(() => _selectedType = type),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: TashilSpacing.xl),

                    // TAS-358 (C-08): outlined from the theme, with a label.
                    TextFormField(
                      key: const Key('feedback_message'),
                      controller: _contentController,
                      maxLines: 8,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.yourMessage,
                        hintText: AppLocalizations.of(context)!.feedbackHint,
                        alignLabelWithHint: true,
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
                    const SizedBox(height: TashilSpacing.xl),

                    // إرفاق صورة
                    Text(
                      AppLocalizations.of(context)!.screenshotOptional,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: TashilSpacing.sm),
                    if (_selectedImage != null)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              TashilRadius.medium,
                            ),
                            child: Image.file(
                              _selectedImage!,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          PositionedDirectional(
                            top: TashilSpacing.sm,
                            end: TashilSpacing.sm,
                            child: IconButton.filledTonal(
                              tooltip: MaterialLocalizations.of(context)
                                  .deleteButtonTooltip,
                              onPressed: _removeImage,
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        ],
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: Text(AppLocalizations.of(context)!.chooseImage),
                      ),
                    const SizedBox(height: TashilSpacing.xxl),

                    // زر الإرسال
                    FilledButton.icon(
                      onPressed: _submitFeedback,
                      icon: const Icon(Icons.send),
                      label: Text(AppLocalizations.of(context)!.sendAction),
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

  /// TAS-358 (C-30): a short result is a snackbar (no dialog, no «!»),
  /// shown on the app's messenger so it stays after the page closes. The
  /// two ways back are unchanged: the router on mobile, the shell's inner
  /// navigator on the web.
  void _onSubmitted(BuildContext context) {
    showTashilSnackBar(
      context,
      AppLocalizations.of(context)!.feedbackReceived,
    );
    if (widget.showAppBar) {
      context.pop();
    } else {
      Navigator.of(this.context).pop();
    }
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
