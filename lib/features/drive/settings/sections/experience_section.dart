import 'package:flutter/material.dart';
import 'package:skydrivex/features/drive/settings/drive_settings_tiles.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_grid.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_section_title.dart';

class ExperienceSection extends StatelessWidget {
  const ExperienceSection({
    super.key,
    required this.followSystem,
    required this.manualMode,
    required this.enabled,
    required this.onFollowSystemChanged,
    required this.onManualModeChanged,
  });

  final bool followSystem;
  final ThemeMode manualMode;
  final bool enabled;
  final ValueChanged<bool> onFollowSystemChanged;
  final ValueChanged<ThemeMode> onManualModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionTitle(
          title: 'Experience',
          subtitle: 'Personalize visuals and monitor sync status.',
        ),
        const SizedBox(height: 16),
        SettingsGrid(
          minTileWidth: 460,
          children: [
            ThemeSettingsTile(
              followSystem: followSystem,
              manualMode: manualMode,
              enabled: enabled,
              onFollowSystemChanged: onFollowSystemChanged,
              onManualModeChanged: onManualModeChanged,
            ),
            const SettingsSyncTile(),
          ],
        ),
      ],
    );
  }
}
