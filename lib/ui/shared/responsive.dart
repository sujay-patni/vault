import 'package:flutter/material.dart';

import 'app_theme.dart';

const double _maxContentWidth = 720;

double responsiveHorizontalPadding(double width) {
  if (width >= 900) return VaultSpacing.xl + VaultSpacing.sm;
  if (width >= 600) return VaultSpacing.xl;
  return VaultSpacing.lg;
}

class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = _maxContentWidth,
    this.scrollable = true,
    this.centerVertically = false,
  });

  final Widget child;
  final double maxWidth;
  final bool scrollable;
  final bool centerVertically;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = responsiveHorizontalPadding(constraints.maxWidth);
        final content = ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Align(
            alignment: centerVertically
                ? Alignment.center
                : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  VaultSpacing.lg,
                  padding,
                  VaultSpacing.xl,
                ),
                child: child,
              ),
            ),
          ),
        );
        if (!scrollable) return content;
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: content,
        );
      },
    );
  }
}
