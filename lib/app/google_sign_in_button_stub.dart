import 'package:flutter/material.dart';

Widget buildGoogleSignInButton({required VoidCallback onPressed}) {
  return FilledButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.login),
    label: const Text('Continue with Google'),
  );
}
