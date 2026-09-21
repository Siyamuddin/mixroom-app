import 'package:flutter/material.dart';
import 'package:mixroom/l10n/l10n.dart';

class DawMobileRowGroupingActions extends StatelessWidget {
  const DawMobileRowGroupingActions({
    super.key,
    required this.selectedCount,
    required this.onCancel,
    required this.onGroup,
  });

  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback onGroup;

  Widget _buildActionButton({
    required Key key,
    required String label,
    required String semanticLabel,
    required VoidCallback? onTap,
    required Color accent,
    required double maxWidth,
    String? badgeLabel,
  }) {
    final enabled = onTap != null;
    final contentColor = enabled
        ? Colors.white.withValues(alpha: 0.96)
        : Colors.white.withValues(alpha: 0.42);
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 44, maxWidth: maxWidth),
      child: Semantics(
        key: key,
        button: true,
        enabled: enabled,
        label: semanticLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Ink(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: enabled ? 0.72 : 0.26),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: accent.withValues(alpha: enabled ? 0.58 : 0.22),
                ),
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            color: contentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (badgeLabel != null) ...[
                      const SizedBox(width: 7),
                      Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: enabled ? 0.20 : 0.10,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeLabel,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            color: contentColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeSelectedCount = selectedCount < 0 ? 0 : selectedCount;
    final canGroup = safeSelectedCount >= 2;
    return Row(
      key: const ValueKey('mobile_row_grouping_actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          key: const ValueKey('mobile_cancel_group_rows_button'),
          label: L10n.translate(context, 'Cancel'),
          semanticLabel: L10n.translate(
            context,
            'Cancel row grouping selection',
          ),
          accent: const Color(0xFF58636E),
          maxWidth: 88,
          onTap: onCancel,
        ),
        const SizedBox(width: 8),
        _buildActionButton(
          key: const ValueKey('mobile_group_rows_button'),
          label: L10n.translate(context, 'Group Rows'),
          semanticLabel: L10n.translate(
            context,
            canGroup ? 'Group selected rows' : 'Select rows to group',
          ),
          accent: const Color(0xFF347D87),
          maxWidth: 136,
          badgeLabel: '$safeSelectedCount',
          onTap: canGroup ? onGroup : null,
        ),
      ],
    );
  }
}
