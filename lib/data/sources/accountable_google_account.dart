import 'package:google_sign_in/google_sign_in.dart';

class AccountableGoogleAccount {
  const AccountableGoogleAccount({
    required this.email,
    required this.idToken,
    this.nativeAccount,
  });

  final String email;
  final String idToken;
  final GoogleSignInAccount? nativeAccount;
}
