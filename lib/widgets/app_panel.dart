import 'package:flutter/material.dart';
import 'package:radio_mac/theme/app_palette.dart';
import 'package:window_manager/window_manager.dart';

/// Shared frameless panel chrome inspired by the fso13 hero code panel.
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.title,
    this.actions = const [],
  });

  final Widget child;
  final String? title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(palette.glowAccent, palette.bg),
            palette.bg,
            palette.bgDeep,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          DragToMoveArea(
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: palette.codeBar.withValues(alpha: 0.95),
                border: Border(bottom: BorderSide(color: palette.line)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    title ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      fontFamily: 'Menlo',
                      color: palette.mutedBright,
                    ),
                  ),
                  Row(
                    children: [
                      const Spacer(),
                      ...actions,
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.onTap,
    this.footer,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onTap;
  final Widget? footer;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final card = Material(
      color: palette.bgElevated.withValues(alpha: 0.78),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.accent.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 17, color: palette.accent),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: palette.ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
            if (footer != null) ...[
              const SizedBox(height: 12),
              footer!,
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      ),
    );
  }
}

class ChoiceOption extends StatelessWidget {
  const ChoiceOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.description,
  });

  final String label;
  final String? description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? palette.accent.withValues(alpha: 0.75)
                  : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? palette.accent : palette.muted,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: palette.ink,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        description!,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: palette.mutedBright),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'Menlo',
            color: palette.accent,
          ),
        ),
      ],
    );
  }
}
