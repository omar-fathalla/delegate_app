import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/material.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class AttendanceActionButton extends StatelessWidget {
  final bool isCheckedIn;
  final bool isLoading;
  final VoidCallback? onTap;

  const AttendanceActionButton({
    super.key,
    required this.isCheckedIn,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surface,
          border: Border.all(
            color: isCheckedIn
                ? theme.colorScheme.secondary
                : theme.colorScheme.primary,
            width: 4,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.1),
              blurRadius: 15,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isCheckedIn ? Symbols.exit_to_app_rounded : Symbols.touch_app_rounded,
                      size: 40,
                      color: isCheckedIn
                          ? theme.colorScheme.secondary
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isCheckedIn ? l10n.checkOut : l10n.checkIn,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isCheckedIn
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
