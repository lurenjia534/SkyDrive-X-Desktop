import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

void showToast(BuildContext context, String message) {
  if (context.findAncestorStateOfType<FToasterState>() != null) {
    showFToast(context: context, title: Text(message));
    return;
  }

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null && Scaffold.maybeOf(context) != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
