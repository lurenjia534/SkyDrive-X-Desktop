import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class DriveLoadingList extends StatelessWidget {
  const DriveLoadingList({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Center(
      child: FCircularProgress.loader(
        style: (style) => style.copyWith(
          iconStyle: IconThemeData(
            color: colors.primary,
            size: 22,
          ),
        ),
      ),
    );
  }
}
