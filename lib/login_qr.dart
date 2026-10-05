// Read the university QR challenge and explicitly finish its approved login.
// All requests stay in the WebView's SSO cookie context; MIREA handles MFA.
const mireaLoginQrScript = r"""
(() => {
  if (location.origin !== 'https://sso.mirea.ru') return null;
  const c = typeof kcContext !== 'undefined' ? kcContext : window.kcContext;
  if (!c || !['qr-login', 'qr-login.ftl'].includes(c.pageId)) return null;
  if (c.message && c.message.type === 'error') return null;
  if (c.qrStatus && !['waiting', 'success'].includes(c.qrStatus)) return null;
  const state = window.__antiattendanceQrState ||
      (window.__antiattendanceQrState = {pending: false, submitted: false});
  const tabId = c.tabId || new URLSearchParams(location.search).get('tab_id');
  if (c.sessionId && tabId && !state.pending && !state.submitted) {
    state.pending = true;
    const endpoint = new URL('/realms/mirea/qr-code-auth/check-status', location.origin);
    endpoint.searchParams.set('sessionId', c.sessionId);
    endpoint.searchParams.set('tabId', tabId);
    fetch(endpoint.href, {credentials: 'same-origin', cache: 'no-store'})
      .then(response => response.ok ? response.json() : null)
      .then(result => {
        if (!result) return;
        state.status = result.status;
        if (result.authenticated !== true || state.submitted) return;
        const action = new URL(c.url.loginAction, location.origin);
        if (action.origin !== location.origin ||
            action.pathname !== '/realms/mirea/login-actions/authenticate' ||
            !c.QRauthExecId) return;
        // Use the same POST and execution field as MIREA's QR login page.
        let form = document.getElementById('ru-mirea-sso-qrcode-' + c.QRauthExecId);
        if (!form) {
          form = document.createElement('form');
          form.method = 'post';
          form.action = action.href;
          form.style.display = 'none';
          const execution = document.createElement('input');
          execution.type = 'hidden';
          execution.name = 'authenticationExecution';
          execution.value = c.QRauthExecId;
          form.appendChild(execution);
          document.body.appendChild(form);
        }
        if (new URL(form.action, location.origin).href !== action.href ||
            form.method.toLowerCase() !== 'post') return;
        state.submitted = true;
        HTMLFormElement.prototype.submit.call(form);
      })
      .catch(() => { /* Retry on the next app poll without losing the QR. */ })
      .finally(() => { state.pending = false; });
  }
  if (['timeout', 'rejected', 'session_not_found'].includes(state.status)) return null;
  return JSON.stringify({qr: c.QRauthToken});
})()
""";

String? mireaLoginQr(Object? value) {
  if (value is! String || value.length > 8192) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'sso.mirea.ru' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort && uri.port != 443 ||
      uri.path != '/realms/mirea/qr-code-auth/scan' ||
      (uri.queryParameters['qrToken'] ?? '').isEmpty) {
    return null;
  }
  return value;
}
