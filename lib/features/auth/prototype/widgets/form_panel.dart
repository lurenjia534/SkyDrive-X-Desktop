import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

class AuthFormPanel extends StatelessWidget {
  const AuthFormPanel({
    super.key,
    required this.typography,
    required this.colors,
    required this.isAuthenticating,
    required this.error,
    required this.clientIdController,
    required this.onSignIn,
  });

  final FTypography typography;
  final FColors colors;
  final bool isAuthenticating;
  final String? error;
  final TextEditingController clientIdController;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    Future<void> pasteClientId() async {
      if (isAuthenticating) return;
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null) return;
      clientIdController.text = text.trim();
      clientIdController.selection = TextSelection.collapsed(
        offset: clientIdController.text.length,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isAuthenticating) ...[
            const FProgress(),
            const SizedBox(height: 20),
          ],
          // Client ID label and input
          FTextField(
            controller: clientIdController,
            label: Text(
              'CLIENT ID',
              style: typography.xs.copyWith(
                color: colors.mutedForeground,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            description: Text(
              'Azure App Registration → Application (client) ID',
              style: typography.xs.copyWith(
                color: colors.mutedForeground.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
            hint: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
            enabled: !isAuthenticating,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
            prefixBuilder: (_, __, ___) => Padding(
              padding: const EdgeInsets.only(left: 14, right: 10),
              child: Icon(
                Icons.badge_outlined,
                color: colors.mutedForeground,
                size: 20,
              ),
            ),
            suffixBuilder: (context, style, states) => Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: FButton.icon(
                style: style.clearButtonStyle.call,
                onPress: states.contains(WidgetState.disabled)
                    ? null
                    : pasteClientId,
                child: const Icon(Icons.content_paste_rounded),
              ),
            ),
            clearable: (value) => value.text.trim().isNotEmpty,
            style: (style) => style.copyWith(
              filled: true,
              fillColor: colors.secondary.withValues(alpha: 0.25),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: FWidgetStateMap({
                WidgetState.error: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.error, width: 1.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                WidgetState.disabled: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: colors.border.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                WidgetState.focused: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: colors.primary.withValues(alpha: 0.85),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                WidgetState.hovered: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: colors.border.withValues(alpha: 0.9),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                WidgetState.any: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: colors.border.withValues(alpha: 0.85),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
              }),
            ),
            onSubmit: (_) {
              if (isAuthenticating) return;
              onSignIn();
            },
          ),
          const SizedBox(height: 24),
          // Continue with Microsoft button
          SizedBox(
            height: 52,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: FButton(
                onPress: isAuthenticating ? null : onSignIn,
                prefix: isAuthenticating
                    ? const FCircularProgress(icon: FIcons.loader)
                    : Icon(
                        Icons.key_rounded,
                        color: colors.primaryForeground,
                        size: 18,
                      ),
                child: Text(
                  isAuthenticating
                      ? 'Connecting...'
                      : 'Continue with Microsoft',
                  style: typography.base.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.primaryForeground,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Sign up link
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Don't have an account? ",
                  style: typography.sm.copyWith(color: colors.mutedForeground),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      // Opens Azure portal app registration page
                      // In production, use url_launcher package
                    },
                    child: Text(
                      'Sign up now',
                      style: typography.sm.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 20),
            FAlert(
              style: (_) => context.theme.alertStyles.destructive,
              title: Text(error!),
              subtitle: const Text(
                'Please check your Client ID and try again.',
              ),
              icon: const Icon(FIcons.circleAlert),
            ),
          ],
        ],
      ),
    );
  }
}
