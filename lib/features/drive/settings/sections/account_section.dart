import 'package:flutter/material.dart';
import 'package:skydrivex/features/drive/settings/drive_settings_tiles.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_section_title.dart';

class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionTitle(
          title: 'Account & storage',
          subtitle: 'Manage OneDrive quota and account details.',
        ),
        const SizedBox(height: 16),
        const AccountManagementTile(),
        const SizedBox(height: 16),
        const DriveInfoTile(),
      ],
    );
  }
}
