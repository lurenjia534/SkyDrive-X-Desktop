import 'package:flutter/material.dart';
import 'package:skydrivex/features/drive/settings/drive_settings_tiles.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_grid.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_section_title.dart';

class DownloadsSection extends StatelessWidget {
  const DownloadsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionTitle(
          title: 'Downloads',
          subtitle: 'Control where files land and how many tasks run.',
        ),
        const SizedBox(height: 16),
        const SettingsGrid(
          minTileWidth: 460,
          children: [
            DownloadDirectoryTile(),
            DownloadConcurrencyTile(),
          ],
        ),
      ],
    );
  }
}
