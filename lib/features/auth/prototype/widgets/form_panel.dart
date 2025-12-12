import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class AuthFormPanel extends StatelessWidget {
  const AuthFormPanel({
    super.key,
    required this.typography,
    required this.colors,
    required this.isAuthenticating,
    required this.error,
    required this.userIdController,
    required this.onSignIn,
  });

  final FTypography typography;
  final FColors colors;
  final bool isAuthenticating;
  final String? error;
  final TextEditingController userIdController;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
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
          // USER ID label and input
          FTextField(
            controller: userIdController,
            label: Text(
              'USER ID',
              style: typography.xs.copyWith(
                color: colors.mutedForeground,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            hint: 'name@company.com',
            prefixBuilder: (_, __, ___) => Icon(
              Icons.person_outline_rounded,
              color: colors.mutedForeground,
              size: 20,
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
              subtitle: const Text('Please check your User ID and try again.'),
              icon: const Icon(FIcons.circleAlert),
            ),
          ],
        ],
      ),
    );
  }
}
