import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/settings/sections/account_section.dart';
import 'package:skydrivex/features/drive/settings/sections/downloads_section.dart';
import 'package:skydrivex/features/drive/settings/sections/experience_section.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_header.dart';
import 'package:skydrivex/theme/app_theme_provider.dart';

class DriveSettingsPage extends ConsumerStatefulWidget {
  const DriveSettingsPage({super.key});

  @override
  ConsumerState<DriveSettingsPage> createState() => _DriveSettingsPageState();
}

class _DriveSettingsPageState extends ConsumerState<DriveSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final themeAsync = ref.watch(appThemeProvider);
    final themeState = themeAsync.value ?? AppThemeState.defaults;
    final themeLoading = themeAsync.isLoading;
    final themeController = ref.read(appThemeProvider.notifier);
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth =
            constraints.maxWidth >= 1200 ? 1080.0 : constraints.maxWidth;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(24, 20, 24, 4),
                    child: SettingsHeader(),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AccountSection(),
                        const SizedBox(height: 28),
                        ExperienceSection(
                          followSystem: themeState.followSystem,
                          manualMode: themeState.manualMode,
                          enabled: !themeLoading,
                          onFollowSystemChanged: (value) =>
                              unawaited(themeController.setFollowSystem(value)),
                          onManualModeChanged: (mode) =>
                              unawaited(themeController.setManualMode(mode)),
                        ),
                        const SizedBox(height: 28),
                        const DownloadsSection(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
