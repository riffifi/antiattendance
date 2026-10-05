import 'package:nfc_pass_client/nfc_pass_client.dart';

import 'accounts.dart';
import 'nfc_pass.dart';

enum SessionCheckState {
  valid,
  expired,
  forbidden,
  unavailable,
  invalidResponse,
}

class SessionCheckResult {
  const SessionCheckResult(this.state, {this.tokenExpiresAt});
  final SessionCheckState state;
  // This is the digital-pass access token expiry, not the session cookie expiry.
  final DateTime? tokenExpiresAt;
}

Future<SessionCheckResult> checkSession(
  SavedAccount account, {
  NfcPassClient? client,
}) async {
  final ownedClient = client == null;
  final service = client ?? passClient(account);
  try {
    // A fresh authenticated token proves the server accepts this session.
    // No verification code is sent and no pass is issued by this check.
    final token = await service.getAccessTokenForDigitalPass();
    return SessionCheckResult(
      SessionCheckState.valid,
      tokenExpiresAt: passTokenExpiry(token),
    );
  } on NfcPassTransportException catch (error) {
    return SessionCheckResult(
      error.requiresAuthentication
          ? SessionCheckState.expired
          : error.httpStatusCode == 403 || error.grpcStatus == 7
          ? SessionCheckState.forbidden
          : SessionCheckState.unavailable,
    );
  } on NfcPassUnreachableException {
    return const SessionCheckResult(SessionCheckState.unavailable);
  } on FormatException {
    return const SessionCheckResult(SessionCheckState.invalidResponse);
  } finally {
    if (ownedClient) service.httpClient.close();
  }
}
