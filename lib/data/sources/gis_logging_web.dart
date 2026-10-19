import 'package:google_identity_services_web/id.dart' as google_identity;

void suppressGisDebugLogs() {
  google_identity.id.setLogLevel('error');
}
