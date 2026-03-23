# Release Compliance Checklist

Last updated: 2026-03-08

This checklist covers the non-code release work that still has to be true for a
public beta, even after the security/privacy fixes in the app and backend.

## License and Commercial Rights

1. JUCE
   - Keep proof of an active JUCE commercial license for Mixroom, or do not
     ship unless you are intentionally complying with the AGPL for the full app.
   - Record who approved the release against that license and when.

2. FFmpeg / ffmpeg-kit
   - Inventory the exact packages shipped on iOS and Android.
   - Archive the upstream license bundle and notice text for those exact
     packages.
   - Verify your enabled codecs/encoders do not create GPL or patent exposure
     you are not prepared to accept.
   - The unused Android `ffmpeg-kit-full-gpl` local override was removed from
     this repo. Keep it out unless you explicitly want GPL obligations.

3. Bundled samples and creative assets
   - Every shipped asset needs a source URL, a license text, and any required
     attribution in-repo.
   - Do not ship the TicTokMen sample assets until redistribution rights are
     documented clearly enough for external review.

## Privacy and Minor Handling

1. Publish and link these documents before beta:
   - Privacy Policy
   - Terms of Service
   - Data retention / deletion policy
   - Security / privacy contact
   - Subprocessor list if third-party processors receive personal data

2. Store disclosure alignment
   - App Store privacy nutrition labels must match the actual SDKs, analytics,
     crash reporting, account data, purchase verification, and AI proxy usage.
   - Play Data Safety must match the same data flows.

3. Age gate policy
   - Decide and document the product rule. The current signup flow still
     collects birthday and enforces a minimum age, so your public policy,
     account UX, and store disclosures must match that behavior until the flow
     changes.
   - If you want to allow under-13 users later, that is a separate compliance
     project: child privacy handling, guardian consent, safer defaults,
     moderation policy, and updated store disclosures. Explicit-content filters
     alone are not enough.
   - Long term, prefer collecting the minimum age signal you actually need. A
     simple 13+ gate or age band is a better data-minimised design than full
     DOB if exact birth date is not otherwise needed.
   - Document what features, defaults, and moderation rules apply to minors.

4. Consent and policy versioning
   - Track accepted `terms_version` and `privacy_version` per user before
     enabling public social/content features.
   - Keep a dated change log of policy revisions.

## Operations and Security

1. Local secret storage
   - Auth tokens and queued purchase verification records now migrate into
     OS-protected secure storage (iPhone Keychain / Android Keystore-backed
     encrypted storage).
   - Do not move those values back into `SharedPreferences` or app logs.
   - Test one upgrade path from an older beta build on a real iPhone and a
     real Android device to confirm secure-storage migration works.

2. Environment separation
   - Separate staging and production AWS accounts or at least separate IAM,
     secrets, data stores, and billing alarms.

3. Access control
   - MFA on every admin account.
   - Least-privilege IAM for humans and Lambdas.
   - Secret rotation owners and dates.

4. Incident readiness
   - Backups plus at least one restore drill.
   - Abuse / takedown contact.
   - Incident response runbook and rollback owner.

5. Release sign-off
   - Record a named owner for security, privacy, licensing, and production
     deployment approval before public beta.
