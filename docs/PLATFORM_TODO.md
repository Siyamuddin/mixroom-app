# Platform TODO

Planning document for Mixroom's future platform side: user uploads, verified
artists, moderation, payouts, and the later path to licensed/distributor
catalog support.

This is a product, engineering, and business checklist. It is not legal
advice. Anything touching copyright, music licensing, payouts, taxes, minors,
privacy, or platform terms should be reviewed by counsel before launch.

## Working Assumption

Recommended launch stance:

- start as a `UGC platform` with direct uploads
- support `verified artist / team accounts` later without changing the core
  model
- do not launch as a full `licensed DSP / distributor destination` in v1
- future-proof the architecture so licensed catalog can be added cleanly later

Why this matters:

- UGC hosting, verified creators, and licensed catalog are related but not the
  same business
- legal, payment, and reporting obligations expand significantly once official
  licensed music is accepted from labels/distributors
- the data model should support both worlds, even if only UGC ships first

## Core Principles

- keep `account`, `artist profile`, `organization`, and `rights ownership`
  separate
- keep `asset file`, `track/release metadata`, and `social post` separate
- route all playback through a `rights / policy check`
- assume `territory`, `date windows`, and `role-based permissions` will matter
  later
- keep immutable audit history for uploads, takedowns, disputes, and payouts
- avoid hardcoding product assumptions that make distributor support impossible
  later

## 0. Launch Decisions To Lock Early

- [ ] Confirm the v1 business model:
  - UGC only
  - UGC + verified artists
  - licensed DSP / catalog destination
- [ ] Keep v1 scoped to `UGC + verified artists`, unless there is already a
  real licensing budget and counsel in place.
- [ ] Choose initial territory:
  - US only is simpler
  - global launch means more privacy, payments, tax, and rights complexity
- [ ] Choose initial age policy:
  - `13+` is much simpler than supporting under-13 users
  - `18+` is even simpler if the product can accept that tradeoff
- [ ] Decide whether v1 allows:
  - original music only
  - DJ mixes
  - remixes
  - covers
  - sampled music
  - AI voice clones / likeness content
  - reuploads of already released label/distributor content
- [ ] Decide whether users can:
  - stream only
  - download
  - embed
  - repost
  - monetize
  - collaborate on the same track

## 1. Legal / Business Foundation

These are not optional if the platform becomes public.

### 1.1 Copyright / DMCA / Safe Harbor

- [ ] Register a DMCA agent with the U.S. Copyright Office if Mixroom serves
  the U.S. market.
- [ ] Publish a copyright policy with:
  - takedown notice process
  - counter-notice process
  - repeat infringer policy
  - account termination / strike rules
- [ ] Add a product-level upload attestation:
  - "I own this or have the rights to upload it"
  - "I understand false claims may result in removal or account termination"
- [ ] Create moderator/admin tooling for:
  - takedown intake
  - counter-notice intake
  - strike tracking
  - repeat infringer enforcement
  - evidence and decision logging
- [ ] Keep an audit trail of:
  - who uploaded
  - when it was published
  - takedown notices
  - counter-notices
  - account actions

Notes:

- DMCA safe harbor is mainly about policy and process, not strict identity
  verification of every uploader.
- Identity verification helps with fraud and impersonation, but it is not a
  substitute for takedown/counter-notice flows.

### 1.2 Terms, Privacy, and User Policies

- [ ] Review and expand:
  - [TERMS_OF_SERVICE.md](/Users/andrewhyungulee/Mixroom/mixroom-app/docs/TERMS_OF_SERVICE.md)
  - [EULA.md](/Users/andrewhyungulee/Mixroom/mixroom-app/docs/EULA.md)
- [ ] Add platform-specific terms covering:
  - user content rights warranties
  - prohibited content
  - repeat infringement
  - impersonation
  - unauthorized leaks
  - AI-generated deceptive content / voice clones
  - suspension and termination
- [ ] Publish a privacy policy that clearly covers:
  - uploads and media storage
  - moderation data
  - linked social accounts
  - verification documents
  - payout / tax information
  - retention and deletion
- [ ] Define data retention rules for:
  - deleted accounts
  - deleted uploads
  - moderation records
  - payout/audit history

### 1.3 Age, Region, and Sanctions

- [ ] Decide whether Mixroom is `13+`, `16+`, or `18+`.
- [ ] Avoid supporting under-13 users unless there is a deliberate COPPA
  strategy.
- [ ] Define blocked territories and sanctions restrictions.
- [ ] Decide which countries are:
  - allowed to listen
  - allowed to upload
  - allowed to receive payouts
- [ ] Build territory restrictions into the data model and playback layer from
  day one.

### 1.4 Payments, Tax, and Business Ops

- [ ] Decide when Mixroom will actually pay creators or rightsholders.
- [ ] If payouts are enabled, plan for:
  - KYC / identity verification
  - tax forms
  - payout holds
  - fraud review
  - chargeback / clawback handling
- [ ] Distinguish:
  - customer payments into Mixroom
  - creator payouts out of Mixroom
  - royalty settlements to rightsholders
- [ ] If the mobile apps sell digital features, review Apple/Google billing
  rules before shipping monetization UI.

## 2. Rights Model To Build Now

If this model is wrong, the platform becomes expensive to fix later.

### 2.1 Rights Concepts

- [ ] Model `sound recording rights` separately from `musical work /
  composition` concepts.
- [ ] Do not assume `uploader == owner`.
- [ ] Do not assume `artist name on profile == legal rightsholder`.
- [ ] Support multiple parties:
  - uploader
  - artist profile
  - label
  - distributor
  - manager / team
  - claimed rightsholder

### 2.2 Minimum Rights Fields

Every track/release should have room for:

- [ ] source type:
  - `ugc_manual`
  - `verified_manual`
  - `partner_delivery`
- [ ] ownership / claim fields
- [ ] territories allowed
- [ ] start date / end date
- [ ] allowed use types:
  - stream
  - download
  - embed
  - short preview
  - offline
  - monetizable
- [ ] visibility / moderation status
- [ ] takedown / dispute status
- [ ] provenance / proof links
- [ ] future identifiers:
  - ISRC
  - UPC/EAN
  - partner delivery IDs

### 2.3 Rights Rules

- [ ] Every playback request should evaluate:
  - is the track published?
  - is the listener territory allowed?
  - is the current date within the rights window?
  - is the requested use allowed?
  - is the asset blocked due to moderation, dispute, or takedown?
- [ ] Avoid a simple `published = true` check as the only gate.
- [ ] Track rights changes historically instead of overwriting them with no
  audit trail.

## 3. Identity, Verification, and Account Ownership

### 3.1 Recommended Model

- [ ] Let the general public create accounts and upload with low friction.
- [ ] Create a separate `claim / verification` flow for artists and public
  figures.
- [ ] Treat linked social accounts as proof of control, not full proof of
  rights ownership.
- [ ] Do not require exact email or legal-name matches as the main check.
- [ ] Reserve stronger verification for:
  - badges
  - account recovery
  - team access
  - monetization
  - official artist claims

### 3.2 Verification Signals

Potential signals to support:

- [ ] linked Instagram / TikTok / YouTube / X / website
- [ ] official website domain verification
- [ ] links to Spotify / Apple / YouTube artist pages
- [ ] label / distributor confirmation
- [ ] government ID or business documents for high-risk cases
- [ ] manual review queue

### 3.3 Account Structure

- [ ] Separate:
  - `user`
  - `artist profile`
  - `organization`
  - `team role`
- [ ] Support roles such as:
  - owner
  - admin
  - manager
  - uploader
  - finance
  - legal
- [ ] Build stronger recovery and change-review flows for verified/high-profile
  accounts.
- [ ] Keep an account ownership conflict process for hacked or disputed
  profiles.

## 4. Technical Architecture To Future-Proof

### 4.1 Core Domain Objects

- [ ] `User`
- [ ] `ArtistProfile`
- [ ] `Organization`
- [ ] `TeamMembership`
- [ ] `Asset`
- [ ] `Track`
- [ ] `Release`
- [ ] `Post`
- [ ] `RightsGrant` or `Deal`
- [ ] `Fingerprint`
- [ ] `Claim`
- [ ] `ModerationCase`
- [ ] `TakedownNotice`
- [ ] `CounterNotice`
- [ ] `PlaybackEvent`
- [ ] `PayoutLedgerEntry`

### 4.2 Important Separation Rules

- [ ] Do not collapse audio uploads into social posts.
- [ ] Do not collapse artist pages into login accounts.
- [ ] Do not collapse metadata rows into file storage rows.
- [ ] Do not make ownership a single string field on the track table.
- [ ] Do not make payout logic depend on profile names or display metadata.

### 4.3 Upload / Ingestion Lanes

Design for multiple ingestion paths from the start:

- [ ] `Self-serve upload`
  - general public
  - verified artists
- [ ] `Trusted manual upload`
  - allowlisted labels / managers / approved teams
- [ ] `Partner delivery`
  - future distributor / label bulk ingest

The first two may share most of the same pipeline. The third should be an
additional adapter later, not a rewrite of the core system.

### 4.4 Asset Processing Pipeline

- [ ] upload original source file
- [ ] validate format, duration, size, and corruption
- [ ] store immutable original asset
- [ ] transcode streaming derivatives
- [ ] generate waveform / loudness metadata
- [ ] generate fingerprint / duplicate-detection data
- [ ] run moderation and trust checks
- [ ] publish only after policy checks pass

### 4.5 Policy Engine

- [ ] Centralize playback and publication rules in one service/module.
- [ ] Feed it:
  - rights data
  - moderation state
  - account state
  - territory
  - dates
  - subscription or product entitlements if relevant
- [ ] Use the same policy engine for:
  - stream playback
  - download
  - embed
  - monetization eligibility
  - editorial/algorithmic distribution

### 4.6 Auditability and Reporting

- [ ] Keep immutable logs for:
  - upload creation
  - metadata changes
  - rights changes
  - team-role changes
  - moderation actions
  - takedowns and disputes
  - playback usage
  - payouts
- [ ] Build an append-only usage ledger that can later support royalty
  reporting.

## 5. Trust, Safety, and Moderation

This needs product and tooling support, not only written policy.

- [ ] Add user reporting for:
  - copyright infringement
  - impersonation
  - stolen or leaked unreleased music
  - harassment
  - spam/scams
  - deepfake / AI voice clone abuse
- [ ] Create moderator actions for:
  - hide
  - geo-block
  - takedown
  - strike
  - freeze profile
  - suspend account
- [ ] Plan how to handle:
  - duplicate uploads
  - official upload vs fan reupload conflicts
  - hacked artist accounts
  - abusive metadata / links / comments
- [ ] Add rate limits and abuse detection for:
  - uploads
  - account creation
  - comments / follows / DMs if those exist later

## 6. Monetization, Payouts, and Revenue Share

### 6.1 Separate the Money Flows

- [ ] Customer billing is one system.
- [ ] Creator payouts are a different system.
- [ ] Licensed catalog royalty settlement is another system.

These should not be treated as one generic "payments" feature.

### 6.2 If Mixroom Pays Uploaders

- [ ] Gate payouts behind stronger verification.
- [ ] Track payable usage in a ledger, not just analytics dashboards.
- [ ] Support payout holds for disputes, fraud, or missing tax/KYC documents.
- [ ] Make split logic explicit if collaborators share revenue.
- [ ] Decide whether payments are:
  - ad revenue share
  - subscription pool share
  - direct fan payments
  - fixed creator program payouts

### 6.3 Mobile Store Constraints

- [ ] Review Apple and Google rules before adding:
  - boosts
  - paid badges
  - creator subscriptions consumed inside the app
  - digital unlocks
- [ ] Do not assume every revenue feature can use Stripe inside mobile apps.

## 7. Product Features That Create Extra Rights Complexity

These should be explicitly accepted or deferred.

- [ ] downloads
- [ ] offline mode
- [ ] embeddable players
- [ ] reposts
- [ ] stems
- [ ] remix / derivative upload tools
- [ ] video support
- [ ] comments and messaging around unreleased content
- [ ] AI-generated voice / likeness tools
- [ ] automatic cross-posting to other services

Each one can change rights exposure, moderation requirements, or platform
policy obligations.

## 8. Future Licensed / Distributor Support

This is a later phase, not a free extension of UGC hosting.

### 8.1 What Needs To Exist Before Approaching Distributors

- [ ] stable rights model
- [ ] territory/date/use-type enforcement
- [ ] verified organization/team roles
- [ ] trusted ingest path
- [ ] usage reporting
- [ ] payout / settlement operations
- [ ] takedown and dispute handling
- [ ] partner support process and SLAs

### 8.2 Business Implications

- [ ] Expect separate commercial deals with labels, distributors, or
  aggregators.
- [ ] Expect to provide usage reports and royalty statements.
- [ ] Expect revenue share, royalty obligations, and possibly minimum
  guarantees in some deals.
- [ ] Expect a larger compliance burden once Mixroom is a licensed destination.
- [ ] If interactive streaming of official catalog exists in the U.S., review
  the publishing/mechanical rights implications as well, not only sound
  recording deals.

### 8.3 Technical Implications

- [ ] Build catalog delivery/reporting adapters at the edge of the system.
- [ ] Do not bake a specific DDEX version directly into the core product data
  model.
- [ ] Keep room for:
  - partner catalog IDs
  - release windows
  - redelivery / takedown updates
  - territory-by-territory changes
  - usage exports
- [ ] Treat `partner delivery` as another ingestion source with stricter
  entitlements, not as a different app.

## 9. Recommended Phase Plan

### Phase 1: UGC Launch

- [ ] direct uploads
- [ ] basic profiles
- [ ] terms/privacy/copyright policy
- [ ] moderation/reporting
- [ ] DMCA/takedown tooling
- [ ] rights-aware playback checks
- [ ] no official distributor ingest

### Phase 2: Verified Artists

- [ ] artist claim flow
- [ ] team roles
- [ ] stronger account recovery
- [ ] allowlisted trusted uploads
- [ ] better duplicate / impersonation handling

### Phase 3: Creator Monetization

- [ ] payout onboarding
- [ ] KYC/tax checks
- [ ] usage ledger
- [ ] payout statements
- [ ] dispute holds and fraud controls

### Phase 4: Partner / Distributor Support

- [ ] partner portal or API
- [ ] bulk ingest
- [ ] monthly reporting
- [ ] territory/deal operations
- [ ] contract-backed licensed catalog workflows

## 10. Open Questions To Keep Revisiting

- [ ] Are we a social audio platform, a creator tool with public sharing, or a
  music service with licensed catalog?
- [ ] Is Mixroom primarily for creators, listeners, or both?
- [ ] Will tracks exist independently from posts, or only inside posts?
- [ ] Can one recording be tied to multiple posts, releases, and rights deals?
- [ ] Will there be private uploads, drafts, invite-only listening, or
  unreleased promo links?
- [ ] Who can control an artist page: the artist, manager, label, distributor,
  or all of them?
- [ ] What happens when a user upload conflicts with an official rightsholder
  upload later?
- [ ] What is the policy for covers, remixes, samples, DJ sets, mashups, and
  AI-generated vocals?
- [ ] Which countries can upload, listen, subscribe, and receive payouts?
- [ ] When should Mixroom move from "platform for uploads" to "licensed
  destination for catalog"?

## 11. Short Developer Summary

If engineering only remembers a few things, remember these:

- [ ] Start UGC-first, but do not model the platform as `post + mp3`.
- [ ] Separate users, artist profiles, organizations, assets, tracks, releases,
  and rights grants.
- [ ] Put all playback behind a policy engine that understands territory, date,
  rights, moderation, and entitlement state.
- [ ] Keep immutable audit history and a usage ledger from the start.
- [ ] Treat verification, payout identity checks, and copyright compliance as
  separate systems.
- [ ] Make `partner delivery` a future adapter, not the foundation of v1.
