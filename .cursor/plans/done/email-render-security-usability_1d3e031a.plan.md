---
name: email-render-security-usability
overview: Make rendered-email sanitization "light" again so receipt content stays readable, while keeping the real security controls (JS disabled, locked-down CSP, external-only navigation) intact.
todos:
  - id: sanitizer
    content: "Rewrite lightlySanitizedEmailHTML to unwrap <form> (->div) instead of deleting its content; keep removing script/iframe/object/embed/base/meta-refresh/on*/javascript:"
    status: completed
  - id: csp
    content: "Loosen img-src in wrappedEmailHTML to data: https: http: cid: and add explicit script-src/object-src 'none'"
    status: completed
  - id: reqs-tests
    content: Update R078 wording + changelog and add/extend EmailAmountScrollSupportTests assertions (form content survives, img-src loosened)
    status: completed
  - id: verify
    content: Run t10 + t14 suites and manually verify a receipt email renders body and images
    status: completed
isProject: false
---

# Secure-yet-readable email rendering

## Root cause
Commit `6542b9e` added `lightlySanitizedEmailHTML` + a restrictive CSP in [src/macos-ui/Sources/TransactionClassifier/EmailAmountScrollSupport.swift](src/macos-ui/Sources/TransactionClassifier/EmailAmountScrollSupport.swift). Two regressions:

- `<form>...</form>` whole-element deletion removes legitimate, readable content (many receipts wrap their body in a form). Pattern: `#"(?is)<\s*(script|iframe|object|embed|form|base)\b[^>]*>.*?<\s*/\s*\1\s*>"#`.
- CSP `img-src data: https:` blocks `http:` and `cid:` images, so logos/image receipts break.

The actual security is already engine-level: `configuration.defaultWebpagePreferences.allowsContentJavaScript = false` and the R079 navigation policy in [MatchAndClassifyViews.swift](src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift). With JS off and `form-action 'none'`, forms are inert — so deleting their content is pure usability loss, contrary to the original "light sanitization, preserve typical receipt rendering" intent.

## Approach: keep the strong controls, stop destroying content
Security weight stays on: JS disabled, CSP (`default-src 'none'`, no scripts/frames/forms/base), and external-only link handoff. The string sanitizer is reduced to neutralizing genuinely-active/non-readable elements without nuking readable containers.

### 1. Fix the sanitizer (`lightlySanitizedEmailHTML`)
- Keep deleting whole elements that are active and not human-readable: `script`, `iframe`, `object`, `embed`. Keep removing `<base>`, `meta http-equiv=refresh`, `on*=` handlers, and `javascript:` URLs.
- Stop deleting `<form>` content. Instead unwrap it: rewrite `<form ...>` to `<div>` and `</form>` to `</div>` so inner receipt content survives. (Submission already blocked by `form-action 'none'` + JS off.)

### 2. Loosen CSP `img-src` for usability (`wrappedEmailHTML`)
- Change `img-src data: https:` to `img-src data: https: http: cid:` so logos and image-based receipts render.
- Keep everything else locked and add an explicit `script-src 'none'` and `object-src 'none'` for clarity:
  `default-src 'none'; script-src 'none'; object-src 'none'; img-src data: https: http: cid:; style-src 'unsafe-inline'; font-src data: https:; frame-src 'none'; form-action 'none'; base-uri 'none';`
- Tradeoff note: allowing remote/`http:` images permits tracking pixels (read receipts). Since the request prioritizes usability and JS is disabled, default to allowing images. If privacy is preferred over images, keep `img-src data: https:` only — call this out for the user.

### 3. Update requirement + tests (repo traceability discipline)
- [requirements/macos-ui/MatchAndClassifyViews-requirements.md](requirements/macos-ui/MatchAndClassifyViews-requirements.md) R078: reword to "strip/neutralize active content while preserving readable receipt content (including form-wrapped bodies)"; add R078-T02 and a changelog entry.
- [src/macos-ui/Tests/TransactionClassifierTests/EmailAmountScrollSupportTests.swift](src/macos-ui/Tests/TransactionClassifierTests/EmailAmountScrollSupportTests.swift): existing `testWrappedEmailHTMLSanitizesActiveContentAndAddsCSP` still passes (no literal `<form`, scripts/iframes gone). Add assertions that form-wrapped inner text survives and that `img-src` permits `http:`/`cid:`.
- The static/dynamic shell security tests (t03/t12) do not assert on the CSP string, so no shell-test changes needed.

## Verification
- `./tests/t10_run_swift_unit_tests.sh` (sanitizer/CSP unit tests)
- `./tests/t14_run_macos_ui_regression_tests.sh` (rendered email pane)
- Manual: open a receipt email (e.g. the DoorDash/Tacombi confirmation) in Rendered mode and confirm body + images now display.

## Outcome / follow-ups (post-implementation)
The form/CSP changes above were necessary but did NOT explain the fully blank body. The real root cause was the R079 navigation delegate added in the same commit: it called `decisionHandler(.cancel)` for every navigation, which also cancelled the initial `loadHTMLString` document render (navigation type `.other`, `about:blank` URL when `baseURL` is nil). Fixed `EmailBodyWebView.decidePolicyFor` to allow the initial in-memory document load (`about:` scheme), still open `.linkActivated` clicks externally, and cancel any other in-place navigation. Security is preserved (JS disabled at engine level + locked CSP + meta-refresh stripped).

Also removed the `id: <email_message_id>` line from `EmailHeaderView` to reclaim vertical space; no tests depended on it (header keeps `email-subject`, From/To, and date).

All checks green: 163 unit tests and 32-scenario t14 UI regression suite.