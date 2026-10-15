import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as google_sign_in_web;

Widget buildGoogleSignInButton({required VoidCallback onPressed}) {
  return google_sign_in_web.renderButton();
}
