import 'package:google_sign_in/google_sign_in.dart';

class AccountableGoogleAccount {
  const AccountableGoogleAccount({
    required this.email,
    this.nativeAccount,
  });

  final String email;
  final GoogleSignInAccount? nativeAccount;
}
