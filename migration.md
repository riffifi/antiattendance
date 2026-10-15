# Migration Plan: Move Sensitive Operations from the App to the Server

> **Review status:** Revised against the publicly visible repositories as of 15 October 2026:
> [`riffifi/antiattendance`](https://github.com/riffifi/antiattendance) and
> [`riffifi/aa-server`](https://github.com/riffifi/aa-server).
>
> This revision includes source inspection of `aa-server/app/main.py`, `app/vault.py`, `app/pulse.py`, `app/protocol.py`, `tests/test_server.py`, and the Flutter app's `lib/main.dart`, alongside the current public READMEs. It is a focused code review, not a full audit of every Dart file, deployment setting, or live production configuration.

## Executive summary

The original direction is sound: keep Pulse credentials and sensitive operations on the server wherever possible, make access revocable, and leave device-specific NFC diagnostics on the phone.

However, several parts of the original plan are already implemented, while the device-token proposal no longer matches the server's documented architecture. The current server README describes a **URL-only protocol (protocol v2)**: device keys and device-management endpoints have been removed, and the server explicitly treats API access as public to anyone who can reach it. The app README also documents local secure storage and session-transfer functionality. Therefore, the most important issue is not simply to add the planned device-token tables; it is to decide and implement a coherent authentication model across the app, server, and self-service web pages.

### Recommended priorities

1. **Immediately decide how the API will authenticate phone clients.** A server URL is not an authentication secret. If the service is reachable from the public internet, the documented URL-only model allows anyone who can reach it to access shared accounts and passes. Network restrictions can reduce exposure, but they are not a substitute for per-user authorization on an internet-facing API.
2. **Audit all sensitive endpoints and close unauthenticated access where appropriate.** Include account reads, imports, session uploads, pass operations, attendance/profile data, group mutations, and enrollment/login flows. Do not assume that hiding an endpoint in the UI protects it.
3. **Keep and test the existing session-ending feature.** The server README already documents `end-session`, including clearing saved Pulse browser state, marking the account expired, and publishing a sync event. This is implemented functionality, not a future migration stage.
4. **Choose a deliberate policy for local credentials and session transfer.** The app README says Pulse cookies are stored in `flutter_secure_storage` and documents Nearby/QR session transfer. The server README describes server-side encrypted storage and synchronization, but also documents phone uploads and local secure-storage copies. Confirm the current behavior in code and decide whether the target is server-only credentials or encrypted local copies with a defined purpose.
5. **Add auditability, recovery, and operational safeguards.** Audit sensitive actions, back up the database and `master.key` together, test restoration, and constrain browser/container resource usage.
6. **Defer PostgreSQL and broad observability work until there is a concrete need**, unless current operational evidence already shows SQLite or monitoring limitations.

## 1. Goal and security model

The goal is to reduce the amount of reusable Pulse credential material stored on phones and to make access revocable centrally.

The intended benefits are:

- Fewer long-lived credential copies.
- Centralized session revocation and device/access revocation.
- Consistent authorization, rate limits, and audit records.
- No transfer of raw Pulse cookies between phones.
- A clear distinction between account ownership, server access, and permission to use a digital pass.

A key distinction: **encrypting credentials at rest does not authenticate API callers**. HTTPS protects traffic in transit, but does not establish which user or device is making a request. A difficult-to-guess URL is not a reliable access-control mechanism.

## 2. Current state found in the repositories

The repositories' public documentation describes the following:

### Server: [`riffifi/aa-server`](https://github.com/riffifi/aa-server)

- Encrypted storage for Pulse cookies, browser state, and pass identifiers, using Fernet and `master.key`.
- Server-side MIREA QR sign-in and automatic session renewal.
- Proxying supported Pulse profile, attendance, and pass RPCs.
- A password-protected administration panel with CSRF protection.
- Per-account self-service pages protected by account passwords and page sessions.
- Session-ending behavior that clears saved session material and emits a sync event.
- Group discovery/assignment, attendance timeline data, and Telegram notifications.
- SQLite-backed storage and a documented single-process requirement.
- A **URL-only sync protocol v2**. The README says device keys and device-management endpoints were removed. It also warns that anyone able to reach the API can read/use shared accounts and passes and can upload sessions and passes; the URL is not authentication.

### App: [`riffifi/antiattendance`](https://github.com/riffifi/antiattendance)

- Flutter app for Android and iOS.
- Multiple Pulse sessions, QR attendance submission, and MIREA sign-in.
- Local session-cookie storage in `flutter_secure_storage`.
- Nearby and QR-based session transfer.
- Synchronization with the server, including account/group updates and pass-related state.
- Schedule UI and locally stored attendance confirmations.
- NFC/pass functionality and device-specific NFC diagnostics that necessarily remain on the phone.
- GitHub release checking and Android update installation.

### Important consistency check

The documentation describes both server-side encrypted storage and local app storage/synchronization. Do not assume that “the server stores the credentials” means “the phone never stores or uploads them.” Trace the actual current code paths for login, session upload, session refresh, sync, pass enrollment, and transfer before defining the final security guarantee.

## 3. Source-code findings confirmed

This section is based on the current `main` branch source inspected for this review. The relevant implementation is in `aa-server/app/main.py`, `app/vault.py`, `app/pulse.py`, `app/protocol.py`, and `tests/test_server.py`; the Flutter app's `lib/main.dart` was also inspected for local account/session flows.

### Finding A — The URL-only trust model is enforced by code and tests

`create_app()` exposes protocol v2. The tests explicitly assert that:

- `GET /api/accounts` succeeds without credentials.
- Supplying an old `Authorization: Bearer ...` key does not change that behavior.
- Device-management endpoints are absent.
- The public account snapshot includes stored pass numbers, while omitting Pulse cookies and the encrypted `secret` field.
- `/api/events` returns account events without authentication.

This is an intentional design, not an accidental missing header. The important exposure is that the API returns/usefully operates on shared accounts and passes for any caller who can reach it.

### Finding B — Several sensitive mutations and proxy calls are also public

The current handlers confirm the following route behavior:

| Route | Current code behavior | Recommended action |
|---|---|---|
| `GET /api/accounts` | Unauthenticated shared account snapshot and pass identifiers | Require authentication or restrict the entire API to a trusted private network |
| `GET /api/events` | Unauthenticated sync/event feed | Scope events to the authenticated principal; avoid global feed access |
| `POST /api/accounts/import` | Unauthenticated; validates the cookie against Pulse and checks identity/revisions | Require an authenticated enrollment/import capability; keep identity validation as an additional check |
| `PUT /api/accounts/{id}/group` | Public route does not call `page_authed()` or `panel()` | Require owner authorization; retain revision/CAS checks |
| `PUT /api/accounts/{id}/pass` | Public route updates the stored pass identifier using a revision check | Require owner/client authorization; revision checks are not authentication |
| `POST /api/accounts/{id}/rpc/{method}` | Proxies allowlisted Pulse RPCs without caller authentication | Require account-scoped authorization before proxying |
| `GET /api/groups` and `/api/groups/search` | Public group metadata/search | Decide whether this data is intentionally public; it is lower priority than account/pass operations |
| `PUT /api/accounts/{id}/pass-allowed` | Owner page session or authenticated panel required | Keep this protection and add authorization regression tests |
| `POST /api/accounts/{id}/end-session` | Owner page session or authenticated panel required | Keep this protection and test failure/concurrency cases |
| `PUT /api/accounts/{id}/label` | Owner page session or authenticated panel required | Keep this protection |
| `GET /api/accounts/{id}/attendance` | Owner page session or authenticated panel required | Keep this protection |

The RPC proxy does have meaningful safeguards: a method allowlist, bounded request/response sizes, checks for a live stored session, pass permission checks, short-lived Pulse token tracking bound to the account, and limits on pass-code/pass-issue attempts. These are useful defenses, but they do not replace authentication of the caller.

### Finding C — Group updates are a specific authorization gap

The `/api/accounts/{id}/group` route calls `vault.update_group()` without requiring an owner page session or panel session. The test suite deliberately verifies that an unauthenticated request can change a group's assignment. `expected_version` prevents stale writes, but does not prove the caller owns the account.

Fix this early, even before the full client-authentication redesign: at minimum, make group mutation available only through an authenticated owner/panel route or a deliberately scoped, short-lived enrollment capability. Coordinate this with the app's sync protocol so legitimate group edits continue to work.

### Finding D — Credential handling is not yet server-only

The Flutter README and `lib/main.dart` confirm that the app saves Pulse cookies locally, supports Nearby/QR transfer, and uses the saved cookie in attendance submission. It also schedules background sync after local account changes. The server import endpoint receives the cookie and validates the Pulse identity before storing/updating it.

The server's sync snapshot does not return Pulse cookies, but the phone still retains its local cookie and can upload it. Therefore, the current implementation is **server-backed synchronization, not a server-only credential architecture**. Do not claim that a stolen phone contains no reusable Pulse credential material.

The app's transfer implementation encrypts the transfer payload and requires receiver confirmation, which is useful in transit. Nevertheless, a successful transfer deliberately gives the receiving device the saved session. Encryption does not make the exported credential revocable from the server under the current model.

### Finding E — HTTPS must be treated as a deployment requirement

The server README documents HTTP as the default and says the installer does not issue a TLS certificate by default. In `app/main.py`, the `Secure` attribute on page/panel session cookies is enabled only when `PUBLIC_URL` starts with `https://`.

If the service is reachable over an untrusted network using HTTP, session cookies, account metadata, pass identifiers, and session uploads may be exposed in transit. This is separate from the lack of API authentication.

**Immediate deployment action:** put the service behind correctly configured HTTPS and ensure the public URL matches the HTTPS origin. For a production/public deployment, fail closed or refuse insecure configuration rather than silently accepting HTTP. Network restrictions remain useful but do not encrypt traffic.

### Finding F — Some important protections already exist

The source contains several good foundations that should be preserved:

- Pulse cookies, browser state, and pass identifiers are stored in a Fernet-encrypted account secret.
- `master.key` and the SQLite database are created with restrictive file permissions.
- The panel password is scrypt-hashed; panel sessions are stored as token hashes and panel writes require CSRF validation.
- Page passwords are scrypt-hashed; page sessions are stored as token hashes.
- The first page session is obtained through the university sign-in/claim flow, and setting/changing the page password requires an active page session.
- Login enrollment uses a random capability whose hash is stored server-side, with a short validity window.
- Import checks the Pulse identity and account binding, and the sync protocol uses revision/session-version checks to prevent stale overwrites.
- The RPC proxy is allowlisted and validates framing/body sizes.
- Browser login navigation is restricted to expected Pulse/MIREA-related hosts.
- Session termination clears `cookie`, `storage_state`, and renewal metadata, marks the account expired, increments the session revision, and emits a sync event.

These controls reduce specific risks; they do not close the public API authorization gap.

### Finding G — Tests currently codify the trust model rather than challenging it

`tests/test_server.py` uses a fake Pulse transport, which is appropriate for deterministic tests, but its URL-only tests explicitly assert public access to account snapshots, events, session import, group updates, pass updates, and RPC proxy routes.

Before changing the protocol, add negative tests for each sensitive route that verify:
- requests without authentication are rejected;
- a credential for account A cannot read or mutate account B;
- a revoked/expired client credential is rejected immediately;
- unauthenticated imports cannot create or replace sessions;
- old protocol clients cannot bypass the new authorization model;
- the owner page and admin panel still work, including CSRF and session termination.

The current tests cover valuable revision, identity-binding, size-limit, and pass-token behaviors; retain those tests while adding authorization tests.

## 4. Feature-by-feature decision

| Area | Current understanding | Recommendation | Priority |
|---|---|---|---|
| Pulse session storage | Server has encrypted storage; app README says cookies are also stored locally and synchronized | Decide whether local copies are still required. Prefer server-held Pulse credentials if the product can work without local copies | Critical |
| Attendance QR submission | Server supports a proxy for supported Pulse operations; app submits attendance | Route through the server consistently if the target is a thin client; enforce authorization per account | High |
| Digital-pass RPCs | Server proxies pass operations and has a `pass_allowed` flag | Keep the permission check server-side and test every pass-related endpoint, including token/code/issue flows | Critical |
| Session transfer | App documents Nearby and QR transfer of saved sessions | Remove if credentials become server-only. If retained temporarily, treat it as a deliberate credential-export feature with clear warnings and tests | High |
| Account/session sync | Current server documents URL-only protocol v2 and synchronization | Define exactly which data may be uploaded, downloaded, or cached; validate ownership and revisions on every mutation | Critical |
| Schedule/group data | Group assignment and server group APIs already exist; schedule UI is in the app | Keep schedule display client-side if useful, but use server APIs for account-linked data and avoid unnecessary duplication | Medium |
| Attendance history | Server exposes today's turnstile timeline; app also keeps local attendance confirmations | Keep the distinction explicit: turnstile events and locally confirmed lecture attendance are different data sources | Medium |
| Release checking | App checks GitHub releases | Leave on the client; this is not a credential-bearing operation | Low |
| NFC diagnostics | Depends on phone hardware/OS behavior | Leave on the client. It cannot be moved to the server | Not applicable |
| Database migration | SQLite is documented as single-process | Stay on SQLite while the single-instance workload is adequate; plan PostgreSQL only when measured requirements justify it | Later |

## 5. Target architecture

The long-term target should be a thin client for account credentials and server-supported Pulse operations:

```text
Phone app / Web account page / Telegram bot
                 |
                 | HTTPS + authenticated, account-scoped requests
                 v
             aa-server
       authorization + audit
       encrypted credential store
                 |
                 | Pulse session credentials stay server-side
                 v
             Pulse / MIREA
```

The diagram is the desired security model, not a claim that the current URL-only API already provides it.

The phone may still need local state for offline UX, device preferences, schedule presentation, and hardware-specific NFC operations. Avoid storing reusable Pulse cookies locally if the server can perform the operation instead. Any local pass identifiers or other credentials should have a documented reason, explicit lifecycle, and revocation behavior.

## 6. Recommended implementation phases

### Phase 0 — Verify the actual baseline

Before changing the protocol, trace and test the existing behavior:

- Identify every endpoint that reads or mutates account data.
- Identify every path that uploads, downloads, refreshes, or transfers Pulse cookies, browser state, pass identifiers, and tokens.
- Confirm which endpoints require a page session, panel session, bot linkage, or no authentication.
- Confirm what the current app stores locally and what remains available offline.
- Write integration tests for the existing sync/revision behavior before changing it.

**Deliverable:** an endpoint/authentication matrix and a data-flow inventory. This phase prevents implementing a design that has already been superseded or breaking synchronization assumptions.

### Phase 1 — Close the API authorization gap

This is the highest-priority work.

- Define the threat model: public server, private network, or VPN-only deployment.
- If public clients must access the service, require authenticated, account-scoped access on every sensitive endpoint.
- Do not treat the server URL, an account ID, or an unguessable enrollment path as a substitute for authorization.
- Check authorization on reads as well as writes. Include account snapshots, profile data, attendance, group changes, pass permissions, pass RPCs, imports, and session uploads.
- Make login/enrollment capabilities short-lived, single-use where possible, and bound to the intended account and operation.
- Keep administrator actions behind the admin authentication and CSRF protections already documented.
- Add negative tests that verify unauthenticated and cross-account requests are rejected.

**Design choice required:** the current README says device keys were removed in URL-only protocol v2. Decide whether to introduce a different authenticated client model (for example, revocable per-installation credentials) or to make the service reachable only through a tightly controlled private network. Do not reintroduce a `device_tokens` table mechanically without first specifying token issuance, storage, rotation, expiration, revocation, and recovery.

### Phase 2 — Make account ownership and revocation explicit

- Preserve and test the existing `end-session` behavior.
- Separate the concepts of ending a Pulse login, revoking a phone's server access, removing an account, and disabling pass use.
- Provide an owner-visible list of active client authorizations only if the selected authentication model has identifiable client installations.
- Add “revoke this client” and “revoke all clients” operations if applicable.
- Ensure revocation invalidates server-side authorization promptly and emits the appropriate sync event.
- Never delete the account as a side effect of ending a Pulse session.

### Phase 3 — Decide the credential-storage policy and retire unsafe legacy paths

- If the server is to be the sole holder of Pulse sessions, remove local Pulse-cookie persistence and the session-transfer UI only after the replacement login/renewal flow works.
- If local credentials must temporarily remain, document why, encrypt them using platform-secure storage, and treat transfer as exporting a credential—not as harmless data sharing.
- Do not remove Nearby/QR transfer until the app can reliably sign in, recover expired sessions, and use supported features through the server.
- Version the protocol and coordinate app/server rollout. Keep compatibility only for a defined migration window; avoid indefinite support for insecure legacy endpoints.

### Phase 4 — Consolidate server-backed account data

- Use the server for account-linked group data and attendance events where server data is authoritative.
- Keep local lecture-confirmation records clearly labeled as client-side records; do not present them as an authoritative university attendance roster.
- Minimize duplicate caches and define behavior while offline.
- Preserve revision checks and conflict handling. Test stale uploads, account deletion, group moves, and reconnect/resume behavior.

### Phase 5 — Harden operations

- Add structured audit events for sign-in/enrollment, session renewal and termination, access revocation, pass permission changes, pass issuance, group changes, account removal, and failed authorization.
- Avoid logging cookies, bearer tokens, passwords, enrollment capabilities, or sensitive request payloads.
- Set and test container memory/CPU limits and browser concurrency limits.
- Back up SQLite data and `master.key` together; test restoration, not just backup creation.
- Add basic health checks and alerts for renewal failures, repeated authorization failures, and unusual spikes in expired sessions.
- Keep the single-worker/single-instance constraint until the storage and job/event architecture is deliberately changed.
- Add admin 2FA or network/VPN restriction based on the actual deployment threat model.

### Phase 6 — Reassess scaling only when justified

PostgreSQL is not automatically necessary just because the project has a server. The current documented SQLite design is constrained by its single-process ownership model. Migrate when you need multiple application instances, higher write concurrency, or operational features that justify the extra complexity. If a migration becomes necessary, plan schema migration, backup/restore, rollback, and concurrency testing separately.

## 7. API and data design

Do not implement the original `device_tokens` schema until the authentication model is settled. If revocable client credentials are selected, define at least:

- A random, high-entropy secret shown to the client only once.
- A server-side token hash rather than the raw token.
- A stable internal client ID, account/owner binding, label, creation time, last-used time, expiration, and revocation timestamp.
- Rotation and recovery behavior.
- Scopes or permissions if clients should not all have identical access.
- Rate limits per authenticated account/client, not only per IP.
- Audit events for issuance, use where appropriate, rotation, and revocation.

For authorization, prefer one shared dependency/helper that resolves the authenticated principal and checks access to the requested account. Avoid a generic `require(account_id, who=...)` helper if callers can supply `who` themselves; the principal must come from verified server-side authentication, not from a caller-controlled string.

Use optimistic concurrency/version checks for account mutations where the existing sync protocol relies on them. Keep session and pass revisions separate if they have independent lifecycles.

## 8. Security checklist

- [ ] Sensitive API routes have an explicit authentication and authorization policy.
- [ ] Cross-account reads and writes are rejected.
- [ ] Session upload/import endpoints verify identity and account ownership before replacing credentials.
- [ ] Pass permission is enforced server-side for every token, code, and issuance path.
- [ ] Enrollment/login capabilities expire, are scoped, and cannot be reused improperly.
- [ ] Ending a Pulse session clears the intended credential material and prevents auto-renewal until a fresh login.
- [ ] Client-access revocation is separate from Pulse-session termination and account deletion.
- [ ] Audit logs contain useful actor/action/time metadata but no secrets.
- [ ] Rate limits work correctly behind Nginx, where client IPs may be shared.
- [ ] Database and `master.key` backups are paired and restoration is tested.
- [ ] Container/browser resource limits are configured and load-tested.
- [ ] Admin access has an appropriate network boundary and strong authentication.
- [ ] Key rotation and recovery after `master.key` compromise are documented.
- [ ] Retention rules are defined for attendance and ACS timeline data.
- [ ] App/server protocol compatibility and rollback behavior are tested.

## 9. Existing “End session” behavior

The server README already documents `POST /api/accounts/{id}/end-session`, accessible through the owner's page session or the admin-panel variant.

The documented behavior is to:

1. Best-effort call the Pulse/MIREA logout endpoint with the stored cookie.
2. Clear the saved cookie and browser state from the encrypted account secret, along with relevant expiry/renewal metadata.
3. Mark the account `expired` and emit a synchronization event.
4. Preserve the account label, group, page password, and pass permission.
5. Prevent automatic renewal until the owner signs in again.

Treat this as existing behavior to verify with tests, not as a new feature to build from scratch. Test failure cases too: logout unavailable, missing session material, duplicate requests, concurrent renewal, and clients that are offline when the event is emitted.

## 10. Risks, rollout, and rollback

- **App/server compatibility:** the client and server have coupled sync and revision behavior. Introduce protocol changes deliberately and test old-client behavior before deployment.
- **Credential exposure:** the current README explicitly warns that the URL-only API is accessible to anyone who can reach it. Resolve this before adding more account capabilities to the API.
- **Pulse/MIREA dependency:** the server cannot guarantee permanent sessions; SSO may require a fresh interactive login.
- **Single point of failure:** server-side credential handling makes backups, restore drills, resource limits, and monitoring important.
- **Local/offline behavior:** removing local sessions or transfer can affect recovery and offline use. Replace those flows before deleting them.
- **Rollback:** keep database migrations backward-compatible where practical, retain backups, and define how the previous app and server versions behave. Do not roll back to an API mode that re-exposes sensitive operations.

Feature flags are useful only when both code paths are safe and data-compatible. A flag does not make an insecure endpoint safe while it remains publicly reachable.

## 11. What to do next

1. **Immediately require HTTPS for public deployments and restrict API reachability** while the current URL-only protocol remains in place. Then audit/document the endpoint access model in `aa-server`, including every route that handles accounts, sessions, passes, groups, attendance, imports, and enrollment.
2. **Choose the deployment/authentication model**: authenticated public API, or private-network/VPN-only API. Record the threat model and expected user experience. HTTPS is required either way when traffic crosses an untrusted network.
3. **Fix the unauthenticated group-mutation route and add regression/negative authorization tests** before changing the sync protocol.
4. **Confirm the intended credential policy**: server-only Pulse credentials versus temporary/local encrypted copies. Trace login, sync, pass enrollment, and transfer in the current app.
5. **Harden and test the existing session-ending flow**, then add audit logging, paired backups, restore testing, and resource limits.
6. **Only then implement client authorization/revocation and remove session transfer**, if those are still the chosen product decisions.
7. **Defer PostgreSQL** until deployment requirements justify a multi-process database architecture.

## Scope: what to keep, change, or remove from the original plan

### Keep

- The principle of minimizing reusable Pulse credentials on devices.
- Server-side authorization for account-sensitive operations.
- Centralized session termination and revocation.
- Audit logs, account-aware rate limits, paired backups, restore testing, resource limits, and a key-compromise procedure.
- Client-side NFC diagnostics and GitHub release checks.
- Explicit rollout/compatibility testing.

### Change

- Replace the proposed immediate `device_tokens` implementation with an explicit authentication-model decision. The server README says the old device-key protocol was removed in favor of URL-only protocol v2.
- Treat `end-session` as existing functionality to test and harden.
- Treat server-side session storage and phone-side credential storage/sync as separate questions; the repositories' documentation describes both.
- Prioritize authorization of existing endpoints over a broad rewrite of schedule/history features.
- Use one verified-principal authorization layer, rather than trusting caller-supplied identity fields.

### Remove or defer

- Do not build the exact original `device_tokens(token_hash, account_id, label, created, last_seen, expires)` design before deciding how tokens are issued, scoped, rotated, and revoked.
- Do not migrate SQLite to PostgreSQL merely for theoretical scale.
- Do not move NFC diagnostics to the server; the required hardware access is local.
- Do not remove session transfer until the replacement sign-in and recovery paths are proven and the credential-storage policy is finalized.
- Do not treat every schedule/history feature as a security migration. Only move the parts that need authoritative server data or reduce sensitive local storage.



## Local implementation status · 16 October 2026

- The UI audit and polish are documented in `docs/ui-audit.md`.
- Before server changes, the working server source was backed up and force-synced
  to `origin/main` (`c9ffbca`). Phase 0's endpoint and credential-flow inventory is
  in `server/docs/migration-baseline.md`.
- The user chose to retain local sessions, local recovery and session transfer
  in a Legacy view under Settings. The normal root view now uses server-backed
  account references and opens the server's sign-in flow.
- A separate daily admin password, shown only in the authenticated server panel,
  unlocks pass testing without changing saved agreement flags. It rotates at
  Moscow midnight, is retained in app secure storage per server until invalid,
  and is removed on expiry/rejection or when testing is disabled. This implements
  the user's explicit testing exception to the normal pass-permission rule.
- Normal snapshots now withhold disabled pass numbers. Pass testing retains Pulse
  session checks, account-bound tokens, verification and rate limits, and is audited.
- Session termination is serialized with renewal; failed upstream logout cannot
  prevent local revocation. Issued tokens and renewal attempts are cleared.
- These changes do not complete Phase 1's general client-authentication redesign.
  The daily testing capability is deliberately scoped to pass testing. Existing
  URL-only compatibility remains; normal client authorization and coordinated
  rollout still require a separate explicit design decision.

Developer access: five downward swipes on the left rail at Attendance (01) reveal the in-memory Developer (00) destination until app close. This is the only menu entry; pass testing still requires the server-validated daily password.

Telegram agreements · 16 October 2026: the user chose per-person requests. Pass access now uses a private per-server app credential linked through an expiring Telegram handoff. Only MIREA-verified Telegram owners may approve, deny, or revoke each Telegram person for their own pass. This scopes authorization to pass snapshots, publishing and RPCs; the wider metadata/attendance access-model decision remains separate. Existing alert subscriptions are not ownership proof. Native activation is capped at a five-minute online-refreshed lease; normal approval pass numbers are not persisted. Legacy local pass activation cannot bypass the flow. Daily admin testing remains the explicit exception.
