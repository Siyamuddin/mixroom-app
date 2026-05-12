const TOKENS_STORAGE_KEY = "mixroom.admin.site.tokens.v1";
const LOCALE_STORAGE_KEY = "mixroom.admin.site.locale.v1";
const SESSION_META_STORAGE_KEY = "mixroom.admin.site.session_meta.v1";
const PKCE_STATE_KEY = "mixroom.admin.site.pkce_state.v1";
const PKCE_VERIFIER_KEY = "mixroom.admin.site.pkce_verifier.v1";
const OVERVIEW_PATH = "/v1/internal/admin/overview";
const LIVE_PRESENCE_PATH = "/v1/internal/admin/live-presence";
const ADMIN_USERS_PATH = "/v1/internal/admin/users";
const ADMIN_USERS_DELETE_PATH = "/v1/internal/admin/users/delete";
const ADMIN_USERS_GRANT_PROMPTS_PATH = "/v1/internal/admin/users/grant-prompts";
const ADMIN_USERS_ENTITLEMENT_OVERRIDE_PATH =
  "/v1/internal/admin/users/entitlement-override";
const ADMIN_FEEDBACK_PATH = "/v1/internal/admin/feedback";
const ADMIN_AI_PROMPT_LIMITS_PATH = "/v1/internal/admin/settings/ai-prompt-limits";
const ADMIN_AI_RUNTIME_PATH = "/v1/internal/admin/settings/ai-runtime";
const ADMIN_BILLING_CATALOG_PATH = "/v1/internal/admin/settings/billing-catalog";
const ADMIN_BILLING_ORGANIZATIONS_PATH = "/v1/internal/admin/billing/organizations";
const ADMIN_BILLING_EDUCATION_PROVISIONING_PATH =
  "/v1/internal/admin/billing/education-provisioning";
const ADMIN_BILLING_MEMBERSHIPS_PATH = "/v1/internal/admin/billing/memberships";
const ADMIN_BILLING_WORKSPACES_PATH = "/v1/internal/admin/billing/workspaces";
const ADMIN_BILLING_CLOUD_PROJECTS_PATH = "/v1/internal/admin/billing/cloud-projects";
const ADMIN_PRODUCER_CAPTURE_WHITELIST_PATH =
  "/v1/internal/admin/settings/producer-capture-whitelist";
const DEFAULT_ADMIN_USERS_LIMIT = 8;
const DEFAULT_FEEDBACK_LIMIT = 8;
const DEFAULT_OVERVIEW_USERS_LIMIT = 5;
const DEFAULT_OVERVIEW_PROJECTS_LIMIT = 5;
const DEFAULT_OVERVIEW_TRACE_LIMIT = 5;
const OVERVIEW_RESULT_LIMIT_STEP = 5;
const RESULT_LIMIT_STEP = 8;
const RESULT_LIMIT_MAX = 40;
const DEFAULT_LOCALE = "en";
const SUPPORTED_LOCALES = new Set(["en", "ko"]);
const ADMIN_IDLE_TIMEOUT_MS = 60 * 60 * 1000;
const ADMIN_MAX_SESSION_MS = 8 * 60 * 60 * 1000;
const ACTIVITY_PERSIST_INTERVAL_MS = 30 * 1000;
const LIVE_PRESENCE_POLL_MS = 60 * 1000;
const DEFAULT_TAB = "home";
const TAB_KEYS = ["home", "users", "feedback", "dev"];
const ANDREW_ADMIN_EMAIL = "andrew@mixroom.ai";
const AI_PROMPT_LIMITS_CONFIRM_PHRASE = "APPLY PROMPT LIMITS";
const PRODUCER_CAPTURE_WHITELIST_CONFIRM_PHRASE = "APPLY PRODUCER WHITELIST";
const ENTITLEMENT_OVERRIDE_DURATION_OPTIONS = [
  { key: "1d", days: 1, labelKey: "override.duration.1d" },
  { key: "1w", days: 7, labelKey: "override.duration.1w" },
  { key: "1m", days: 30, labelKey: "override.duration.1m" },
  { key: "1y", days: 365, labelKey: "override.duration.1y" },
];
const ANALYTICS_RANGE_OPTIONS = [
  { key: "365d", days: 365, labelKey: "analytics.range.1y" },
  { key: "90d", days: 90, labelKey: "analytics.range.3m" },
  { key: "30d", days: 30, labelKey: "analytics.range.1m" },
  { key: "7d", days: 7, labelKey: "analytics.range.1w" },
];
const AI_TOOL_USAGE_RANGE_OPTIONS = [
  { key: "7d", label: "Week" },
  { key: "30d", label: "Month" },
  { key: "all", label: "All time" },
];
const AI_MODEL_OPTIONS = [
  "",
  "gpt-4.1",
  "gpt-4.1-mini",
  "gpt-5",
  "gpt-5-mini",
  "gpt-5-codex",
  "gpt-5.1",
  "gpt-5.1-codex",
  "gpt-5.1-codex-mini",
  "gpt-5.1-chat-latest",
  "gpt-5.2",
  "gpt-5.4",
  "gpt-5.4-mini",
  "gpt-5.4-nano",
];
const AI_REASONING_EFFORT_OPTIONS = ["", "none", "minimal", "low", "medium", "high", "xhigh"];
const AI_PROMPT_CACHE_RETENTION_OPTIONS = ["", "in_memory", "24h"];

function buildOverviewIncludes() {
  return {
    aiUsage: false,
    productAnalytics: false,
    aiObservability: false,
    users: false,
    projects: false,
  };
}

function buildHomeSectionLoading() {
  return {
    analytics: false,
    usage: false,
    observability: false,
    users: false,
    projects: false,
  };
}

const MESSAGES = {
  en: {
    "language.label": "Language",
    "hero.subtitle": "Internal tools",
    "action.refresh": "Refresh",
    "action.signOut": "Sign Out",
    "action.signIn": "Sign In",
    "action.search": "Search",
    "action.clear": "Clear",
    "action.openPosthog": "Open PostHog",
    "action.showMore": "Show more",
    "action.showLess": "Show less",
    "action.saving": "Saving...",
    "action.savePromptLimits": "Save prompt limits",
    "action.saveProducerCaptureWhitelist": "Save producer whitelist",
    "action.saveAiOverride": "Save AI override",
    "auth.kicker": "Employee access",
    "auth.title": "Sign in",
    "auth.copy": "Use your work email.",
    "welcome.kicker": "Mixroom control surface",
    "welcome.subtitle": "Live user operations, AI controls, and product monitoring.",
    "welcome.session": "Session",
    "welcome.mode": "Mode",
    "welcome.fallbackName": "Operator",
    "presence.liveNow": "Live now",
    "presence.userCount": "{count} users",
    "presence.userCountOne": "{count} user",
    "presence.idle": "No users in last {minutes}m",
    "presence.offline": "Live users unavailable",
    "tab.home": "Home",
    "tab.users": "Users",
    "tab.feedback": "Feedback",
    "tab.dev": "Dev",
    "panel.kpi.label": "KPI Overview",
    "panel.kpi.title": "Product metrics",
    "panel.kpi.meta.default":
      "Native PostHog metrics appear here when the admin backend has read access configured.",
    "panel.kpi.meta.live":
      "Native product analytics from PostHog identified screen activity.",
    "panel.kpi.meta.empty":
      "PostHog native metrics are not configured yet.",
    "panel.kpi.meta.error":
      "PostHog metrics could not be loaded. The rest of the admin dashboard is still available.",
    "panel.kpi.activityTitle": "Daily active users",
    "panel.kpi.activityMeta": "Distinct identified people with a screen view each day.",
    "panel.kpi.hoursTitle": "Daily hours used",
    "panel.kpi.hoursMeta": "Total app hours from completed sessions each day.",
    "panel.kpi.countriesTitle": "Top countries",
    "panel.kpi.countriesMeta": "30-day active identified people by country.",
    "panel.kpi.loading": "Sign in to load product metrics.",
    "panel.kpi.unconfigured":
      "PostHog read access is not configured yet. Add the admin read token to enable native metrics.",
    "panel.kpi.unavailable":
      "PostHog metrics are temporarily unavailable.",
    "panel.userAdmin.label": "User Admin",
    "panel.userAdmin.title": "Find user",
    "panel.userAdmin.meta.default": "Email, username, or user ID.",
    "search.label": "User lookup",
    "search.placeholder": "email, username, display name, or user ID",
    "analytics.label": "Product Analytics",
    "analytics.copy": "Retention, MAU, funnels, and session KPIs live in PostHog.",
    "analytics.range.1y": "1Y",
    "analytics.range.3m": "3M",
    "analytics.range.1m": "1M",
    "analytics.range.1w": "1W",
    "panel.accounts.label": "Accounts",
    "panel.accounts.title": "Search results",
    "panel.accounts.meta": "Recent accounts show when blank.",
    "panel.selectedUser.label": "Selected User",
    "panel.selectedUser.title": "User details",
    "panel.selectedUser.meta": "Review actions here.",
    "panel.aiUsage.label": "AI Usage",
    "panel.aiUsage.title": "Daily and weekly AI snapshot",
    "panel.aiPromptLimits.label": "AI Prompt Limits",
    "panel.aiPromptLimits.title": "Free plan defaults",
    "panel.aiPromptLimits.meta": "Server-enforced prompt limits for free users.",
    "panel.aiRuntime.label": "AI Runtime",
    "panel.aiRuntime.title": "Server prompt and model config",
    "panel.aiRuntime.meta": "Prompt and runtime overrides for server-owned AI features.",
    "panel.producerCaptureWhitelist.label": "Producer Capture Whitelist",
    "panel.producerCaptureWhitelist.title": "Producer capture usernames",
    "panel.producerCaptureWhitelist.meta":
      "Usernames allowlisted to see the Producer Capture UI toggle.",
    "panel.features.title": "Most used AI tools this week",
    "panel.tiers.label": "Subscription Plan",
    "panel.tiers.title": "Plans",
    "panel.accountActivity.label": "Account Activity",
    "panel.accountActivity.title": "Accounts with app data",
    "panel.accountActivity.meta": "Users with subscription or AI usage records.",
    "panel.projectActivity.label": "Project Activity",
    "panel.projectActivity.title": "Projects with AI usage",
    "panel.projectActivity.meta": "Project IDs seen in AI usage events.",
    "panel.feedback.label": "User Feedback / Bugs",
    "panel.feedback.title": "Feedback & bug inbox",
    "panel.feedback.meta": "Latest user feedback and bug reports.",
    "panel.selectedFeedback.label": "Selected Submission",
    "panel.selectedFeedback.title": "Submission detail",
    "panel.selectedFeedback.meta": "Review message, DAW context, and screenshots here.",
    "table.user": "User",
    "table.auth": "Auth",
    "table.subscription": "Subscription",
    "table.state": "State",
    "table.lastSeen": "Last Seen",
    "table.type": "Type",
    "table.message": "Message",
    "table.attachments": "Attachments",
    "table.submitted": "Submitted",
    "table.tier": "Plan",
    "table.status": "Status",
    "table.aiRequests": "AI Requests",
    "table.creditsToday": "Credits Today",
    "table.tokensMonth": "Tokens Month",
    "table.project": "Project",
    "table.requests": "Requests",
    "table.users": "Users",
    "table.credits": "Credits",
    "table.tokens": "Tokens",
    "table.lastActivity": "Last Activity",
    "empty.signInSearchUsers": "Sign in to search users.",
    "empty.selectUser": "Select a user to review details and actions.",
    "empty.signInFeatureUsage": "Sign in to load feature usage.",
    "empty.signInTierDistribution": "Sign in to load plan distribution.",
    "empty.signInUserData": "Sign in to load user data.",
    "empty.signInProjectData": "Sign in to load project data.",
    "empty.signInFeedback": "Sign in to load user feedback and bug reports.",
    "empty.signInAiPromptLimits": "Sign in to load AI prompt limit settings.",
    "empty.signInAiRuntime": "Sign in to load AI runtime settings.",
    "empty.signInProducerCaptureWhitelist":
      "Sign in to load producer capture whitelist settings.",
    "empty.selectFeedback": "Select a feedback item or bug report to review the full submission.",
    "empty.feedbackLoading": "Loading feedback detail...",
    "status.configIncomplete":
      "Admin site config is incomplete. Update admin_site/config.js before deploy.",
    "status.signInToContinue": "Sign in to continue.",
    "status.initializeFailed": "Could not initialize admin session.",
    "status.signedOut": "Signed out.",
    "status.loadingAdminOverview": "Loading admin overview...",
    "status.adminOverviewLoaded": "Admin overview loaded.",
    "status.loadAdminOverviewFailed": "Could not load admin overview.",
    "status.searchingUsers": "Searching users...",
    "status.loadingRecentUsers": "Loading recent users...",
    "status.loadingFeedback": "Loading feedback and bug inbox...",
    "status.loadingAiPromptLimits": "Loading AI prompt limit settings...",
    "status.loadingAiRuntime": "Loading AI runtime settings...",
    "status.loadingProducerCaptureWhitelist":
      "Loading producer capture whitelist settings...",
    "status.aiPromptLimitsLoaded": "AI prompt limit settings loaded.",
    "status.aiRuntimeLoaded": "AI runtime settings loaded.",
    "status.producerCaptureWhitelistLoaded":
      "Producer capture whitelist settings loaded.",
    "status.noUsersFound": "No users found.",
    "status.searchUsersFailed": "Could not search users.",
    "status.loadFeedbackFailed": "Could not load user feedback or bug reports.",
    "status.loadAiPromptLimitsFailed": "Could not load AI prompt limit settings.",
    "status.loadAiRuntimeFailed": "Could not load AI runtime settings.",
    "status.loadProducerCaptureWhitelistFailed":
      "Could not load producer capture whitelist settings.",
    "status.grantingPrompts": "Granting extra AI prompts to {target}...",
    "status.promptsGranted": "Extra AI prompts granted.",
    "status.grantPromptsFailed": "Could not grant extra AI prompts.",
    "status.applyingEntitlementOverride": "Applying entitlement override to {target}...",
    "status.entitlementOverrideApplied": "Entitlement override applied.",
    "status.entitlementOverrideFailed": "Could not apply entitlement override.",
    "status.savingAiPromptLimits": "Saving AI prompt limit settings...",
    "status.aiPromptLimitsSaved": "AI prompt limit settings saved.",
    "status.saveAiPromptLimitsFailed": "Could not save AI prompt limit settings.",
    "status.savingProducerCaptureWhitelist":
      "Saving producer capture whitelist settings...",
    "status.producerCaptureWhitelistSaved":
      "Producer capture whitelist settings saved.",
    "status.saveProducerCaptureWhitelistFailed":
      "Could not save producer capture whitelist settings.",
    "status.savingAiRuntime": "Saving AI runtime settings...",
    "status.aiRuntimeSaved": "AI runtime settings saved.",
    "status.saveAiRuntimeFailed": "Could not save AI runtime settings.",
    "status.deletingUser": "Deleting {target}...",
    "status.userDeleted": "User deleted and tombstoned.",
    "status.deleteRequiresForce": "Delete requires force confirmation.",
    "status.deleteUserFailed": "Could not delete user.",
    "status.employeeSignInRequired": "Employee sign-in required.",
    "status.requestFailed": "Request failed with status {status}.",
    "status.hostedStateFailed": "Hosted sign-in state validation failed.",
    "status.hostedSignInFailed": "Hosted sign-in failed.",
    "status.sessionRefreshFailed": "Session refresh failed.",
    "status.sessionMissingEmail": "Session is missing an email claim.",
    "status.signInConfigIncomplete": "Admin site config is incomplete.",
    "status.sessionExpiredIdle":
      "Admin session expired after {minutes} minutes of inactivity. Sign in again.",
    "status.sessionExpiredAbsolute": "Admin session expired. Sign in again.",
    "summary.users": "Users",
    "summary.usersDetail": "{count} with AI or billing data",
    "summary.aiPromptsToday": "AI prompts today",
    "summary.aiPromptsTodayDetail": "{count} AI-active users today",
    "summary.aiPromptsWeek": "AI prompts 7d",
    "summary.aiPromptsWeekDetail": "{count} AI-active users this week",
    "summary.paidUsers": "Paid Users",
    "summary.paidUsersDetail": "{count} active subs",
    "generated.at": "Generated {date}",
    "generated.unavailable": "Generated time unavailable",
    "identity.signedInAs": "Signed in as {email}",
    "identity.employeeAccess": "Allowlisted employee access",
    "identity.employeeEmailsOnly": "Allowlisted employee emails only",
    "identity.employee": "Employee",
    "identity.notSignedIn": "Not signed in",
    "usage.promptsToday": "Prompts today",
    "usage.promptsWeek": "Prompts 7d",
    "usage.activeUsersToday": "AI users today",
    "usage.activeUsersWeek": "AI users 7d",
    "usage.avgPromptsPerUserToday": "Avg prompts / user today",
    "usage.avgPromptsPerUserWeek": "Avg prompts / user 7d",
    "usage.avgLatencyToday": "Avg latency today",
    "usage.avgLatencyWeek": "Avg latency 7d",
    "usage.na": "n/a",
    "usage.noFeatures": "No AI feature events recorded yet.",
    "overview.loading": "Loading…",
    "overview.loadingSection": "Loading this section…",
    "analytics.metric.dau": "DAU",
    "analytics.metric.wau": "WAU",
    "analytics.metric.mau": "MAU",
    "analytics.metric.hours24h": "Hours / 24h",
    "analytics.emptyTrend": "No trend data yet.",
    "analytics.emptyCountries": "No country data yet.",
    "analytics.chartUnavailable": "Chart view is temporarily unavailable.",
    "analytics.countryUsers": "{count} active people",
    "analytics.countryShare": "{share} of shown countries",
    "analytics.countryFeatured": "Strongest current region",
    "analytics.countryListLabel": "Country spread",
    "tiers.noData": "No plan data available.",
    "tiers.usersActive": "{users} users • {active} active",
    "trackedUsers.none": "No users with billing or AI usage data yet.",
    "projects.none": "No project IDs have shown AI activity yet.",
    "projects.lastUser": "Last user: {user}",
    "search.meta": "Search: {query}",
    "search.recentAccounts": "Recent accounts",
    "adminUsers.none": "No users matched that search.",
    "feedback.none": "No feedback or bug report submissions yet.",
    "feedback.detail.user": "User",
    "feedback.detail.source": "Source",
    "feedback.detail.client": "Client",
    "feedback.detail.attachments": "Attachments",
    "feedback.detail.emailConsent": "Email follow-up",
    "feedback.detail.submitted": "Submitted",
    "feedback.detail.message": "Message",
    "feedback.detail.context": "DAW context",
    "feedback.detail.screenshot": "Screenshot",
    "feedback.attachments.context": "context",
    "feedback.attachments.screenshot": "screenshot",
    "feedback.attachments.none": "none",
    "feedback.contact.allowed": "allowed",
    "feedback.contact.notAllowed": "not allowed",
    "feedback.category.feedback": "Feedback",
    "feedback.category.bug_report": "Bug report",
    "feedback.source.home": "Home",
    "feedback.source.account": "Account",
    "feedback.source.daw_chat": "DAW chat",
    "user.usernameLine": "Username: {value}",
    "user.musicProfileLine": "Music profile: {value}",
    "user.birthdateLine": "Birthday: {value}",
    "user.userIdLine": "User ID: {value}",
    "inspector.selectedUser": "Selected user",
    "inspector.noEmail": "No email available",
    "detail.userId": "User ID",
    "detail.name": "Name",
    "detail.username": "Username",
    "detail.birthdate": "Birthday",
    "detail.age": "Age",
    "detail.musicProfile": "Music Profile",
    "detail.appAuth": "App Auth",
    "detail.emailVerification": "Email Verification",
    "detail.nativeSessions": "Native Sessions",
    "detail.legacyCognito": "Legacy Cognito",
    "detail.subscription": "Subscription",
    "detail.onboarding": "Onboarding",
    "detail.aiPrompts": "AI Prompts",
    "detail.extraPromptBank": "Extra Prompt Bank",
    "detail.lastSeen": "Last Seen",
    "detail.created": "Created",
    "detail.updated": "Updated",
    "settings.currentLimits": "Current effective limits",
    "settings.currentAiRuntime": "Current AI runtime override",
    "settings.currentProducerCaptureWhitelist": "Current producer capture whitelist",
    "settings.producerCaptureWhitelistUsernames": "Usernames (comma or line separated)",
    "settings.producerCaptureWhitelistNone": "No usernames are currently allowlisted.",
    "settings.editableByAnyAdmin": "Any admin can edit this list.",
    "settings.confirmProducerCaptureWhitelist":
      "Type APPLY PRODUCER WHITELIST to confirm",
    "settings.freeDailyPromptLimit": "Free daily prompt limit",
    "settings.freeWeeklyPromptLimit": "Free weekly prompt limit",
    "settings.feature.ai_chat": "DAW chat",
    "settings.feature.video_editor_chat": "Video editor chat",
    "settings.modelOverride": "Model override",
    "settings.systemPromptOverride": "System prompt override",
    "settings.maxOutputTokensOverride": "Max output tokens override",
    "settings.temperatureOverride": "Temperature override",
    "settings.reasoningEffortOverride": "Reasoning effort override",
    "settings.promptCacheRetentionOverride": "Prompt cache retention override",
    "settings.currentSavedOverride": "Current saved override",
    "settings.emptyUsesDefault": "Leave a field empty to keep the current backend default.",
    "settings.readOnly": "Visible to admins. Edit access is restricted to andrew@mixroom.ai.",
    "settings.andrewOnlyControl": "Dev surface. Edit access is restricted to andrew@mixroom.ai.",
    "settings.usingBackendDefault": "(default) {value}",
    "settings.noPromptOverride": "No prompt override saved",
    "settings.confirmPromptLimits": "Type APPLY PROMPT LIMITS to confirm",
    "settings.confirmAiRuntime": "Type APPLY {feature} OVERRIDE to confirm",
    "settings.source.default": "Deployed default",
    "settings.source.remote": "Remote override",
    "settings.updatedAt": "Updated {date}",
    "settings.updatedBy": "by {email}",
    "support.label": "AI Support",
    "support.title": "Grant extra prompts",
    "support.copy":
      "Adds a one-time extra prompt bank for support cases. These prompts are consumed before daily and weekly limits.",
    "support.readOnly": "Visible to admins, editable only by andrew@mixroom.ai.",
    "support.inputLabel": "Extra prompts to add",
    "support.granting": "Granting...",
    "support.button": "Grant Extra Prompts",
    "override.label": "Entitlement Support",
    "override.title": "Temporary plan override",
    "override.copy":
      "Grants temporary access without changing payment-provider subscriptions. Every use is written to the audit log.",
    "override.readOnly": "Visible to admins, editable only by andrew@mixroom.ai.",
    "override.plan": "Plan to grant",
    "override.seats": "Seat limit",
    "override.seatsHelp":
      "Studio minimum is 5. Education supports 10, 20, or 30 student seats; teacher/admin access is separate.",
    "override.organizationName": "Team or school name",
    "override.organizationNamePlaceholder": "Optional",
    "override.expiry": "Expiry",
    "override.duration.1d": "1 day",
    "override.duration.1w": "1 week",
    "override.duration.1m": "1 month",
    "override.duration.1y": "1 year",
    "override.reason": "Reason",
    "override.reasonPlaceholder": "Support ticket, local test, or emergency context",
    "override.confirmIdentifier": "Type the user's email, username, or user ID",
    "override.confirmAdminName": "Type your admin first name: {value}",
    "override.applying": "Applying...",
    "override.button": "Apply Override",
    "override.applied": "Granted {plan} until {date}.",
    "override.typeExactIdentifier": "Type a matching user email, username, or user ID to confirm.",
    "override.typeExactAdminName": "Type your admin first name exactly.",
    "delete.label": "Delete User",
    "delete.title": "Delete account",
    "delete.copy":
      "Deletes the auth account, profile, subscription records, linked providers, and frees the username.",
    "delete.activeSubscriptionWarning":
      "This user still has an active paid subscription.",
    "delete.reason": "Reason",
    "delete.reasonPlaceholder": "Why are you deleting this account?",
    "delete.confirm": "Type {value} to confirm",
    "delete.confirmEmail": "Type the user's login email exactly",
    "delete.confirmEmailPlaceholder": "{value}",
    "delete.force":
      "Force deletion even if the user still has an active paid subscription.",
    "delete.deleting": "Deleting...",
    "delete.button": "Delete User",
    "delete.typeExact": "Type {value} exactly to confirm deletion.",
    "delete.typeExactEmail": "Type the login email {value} exactly to confirm deletion.",
    "delete.forceRequired": "This delete requires force confirmation.",
    "detail.na": "n/a",
    "authSource.native": "native",
    "authSource.nativeLegacyBridge": "native + legacy",
    "authSource.legacyOnly": "legacy cognito",
    "authSource.unknown": "unknown",
    "provider.email": "email",
    "provider.google": "google",
    "provider.apple": "apple",
    "provider.kakao": "kakao",
    "provider.unknown": "unknown",
    "value.verified": "verified",
    "value.unverified": "unverified",
    "value.noNativeAuthAccount": "no native auth account",
    "value.zeroSessions": "0 sessions",
    "value.nativeSessionsSummary": "{active}/{total} active • latest expiry {expiry}",
    "value.notLinked": "not linked",
    "value.musicProfile.producer": "Producer",
    "value.musicProfile.artist": "Artist",
    "value.musicProfile.songwriter": "Songwriter",
    "value.musicProfile.audio_engineer": "Audio engineer",
    "value.musicProfile.student": "Student",
    "value.musicProfile.music_enthusiast": "Music enthusiast",
    "value.musicProfile.beginner": "Beginner",
    "value.musicProfile.music_for_work": "Make music for work",
    "value.migrated": "migrated {date}",
    "value.todayWeek": "{today} today • {week} this week",
    "value.remainingGranted": "{remaining} remaining • {granted} granted total",
    "value.extraPromptsAdded": "Added {count} extra prompt{suffix}.",
    "value.dailyWeeklyLimits": "{daily} daily • {weekly} weekly",
    "value.showingCount": "Showing {shown}",
    "value.showingOfTotal": "Showing {shown} of {total}",
    "value.userLoaded": "{count} user loaded.",
    "value.usersLoaded": "{count} users loaded.",
    "value.free": "free",
    "value.starter": "starter",
    "value.pro": "producer",
    "value.producer": "producer",
    "value.studio": "studio",
    "value.enterprise": "enterprise",
    "value.education": "education",
    "value.active": "active",
    "value.trialing": "trialing",
    "value.grace_period": "grace period",
    "value.past_due": "past due",
    "value.paused": "paused",
    "value.canceled": "canceled",
    "value.expired": "expired",
    "value.refunded": "refunded",
    "value.revoked": "revoked",
    "value.unknown": "unknown",
    "value.signup_complete": "signup complete",
    "value.bootstrap_only": "bootstrap only",
    "value.profile_ready": "profile ready",
    "value.complete": "complete",
    "value.pending": "pending",
    "value.deleted": "deleted",
    "value.disabled": "disabled",
    "value.locked": "locked",
    "value.suspended": "suspended",
  },
  ko: {
    "language.label": "언어",
    "hero.subtitle": "내부 도구",
    "action.refresh": "새로고침",
    "action.signOut": "로그아웃",
    "action.signIn": "로그인",
    "action.search": "검색",
    "action.clear": "지우기",
    "action.openPosthog": "PostHog 열기",
    "action.showMore": "더 보기",
    "action.showLess": "줄여 보기",
    "action.saveLimits": "제한 저장",
    "action.saving": "저장 중...",
    "action.savePromptLimits": "프롬프트 제한 저장",
    "action.saveProducerCaptureWhitelist": "프로듀서 화이트리스트 저장",
    "action.saveAiOverride": "AI 재정의 저장",
    "auth.kicker": "직원 접근",
    "auth.title": "로그인",
    "auth.copy": "업무용 이메일로 로그인하세요.",
    "welcome.kicker": "Mixroom 컨트롤 서피스",
    "welcome.subtitle": "실시간 사용자 운영, AI 제어, 제품 모니터링.",
    "welcome.session": "세션",
    "welcome.mode": "모드",
    "welcome.fallbackName": "Operator",
    "presence.liveNow": "실시간",
    "presence.userCount": "사용자 {count}명",
    "presence.userCountOne": "사용자 {count}명",
    "presence.idle": "최근 {minutes}분 사용자 없음",
    "presence.offline": "실시간 사용자 불러오기 불가",
    "tab.home": "홈",
    "tab.users": "사용자",
    "tab.feedback": "피드백",
    "tab.dev": "개발",
    "panel.kpi.label": "KPI 개요",
    "panel.kpi.title": "제품 지표",
    "panel.kpi.meta.default":
      "관리자 백엔드에 읽기 권한이 설정되면 여기에 PostHog 네이티브 지표가 표시됩니다.",
    "panel.kpi.meta.live":
      "PostHog 식별 화면 활동 기반의 네이티브 제품 분석입니다.",
    "panel.kpi.meta.empty":
      "PostHog 네이티브 지표가 아직 설정되지 않았습니다.",
    "panel.kpi.meta.error":
      "PostHog 지표를 불러오지 못했습니다. 나머지 관리자 대시보드는 계속 사용할 수 있습니다.",
    "panel.kpi.activityTitle": "일간 활성 사용자",
    "panel.kpi.activityMeta": "하루 동안 화면을 본 식별 사용자 수입니다.",
    "panel.kpi.hoursTitle": "일간 사용 시간",
    "panel.kpi.hoursMeta": "완료된 세션 기준 일별 총 사용 시간입니다.",
    "panel.kpi.countriesTitle": "상위 국가",
    "panel.kpi.countriesMeta": "최근 30일 활성 식별 사용자 기준 국가 분포입니다.",
    "panel.kpi.loading": "로그인하면 제품 지표를 불러옵니다.",
    "panel.kpi.unconfigured":
      "아직 PostHog 읽기 권한이 설정되지 않았습니다. 관리자 읽기 토큰을 추가하면 네이티브 지표가 표시됩니다.",
    "panel.kpi.unavailable":
      "PostHog 지표를 일시적으로 사용할 수 없습니다.",
    "panel.userAdmin.label": "사용자 관리",
    "panel.userAdmin.title": "사용자 찾기",
    "panel.userAdmin.meta.default": "이메일, 사용자명 또는 사용자 ID.",
    "search.label": "사용자 조회",
    "search.placeholder": "이메일, 사용자명, 표시 이름 또는 사용자 ID",
    "analytics.label": "제품 분석",
    "analytics.copy": "리텐션, MAU, 퍼널, 세션 KPI는 PostHog에서 확인합니다.",
    "analytics.range.1y": "1년",
    "analytics.range.3m": "3개월",
    "analytics.range.1m": "1개월",
    "analytics.range.1w": "1주",
    "panel.accounts.label": "계정",
    "panel.accounts.title": "검색 결과",
    "panel.accounts.meta": "검색어가 없으면 최근 계정을 보여줍니다.",
    "panel.selectedUser.label": "선택된 사용자",
    "panel.selectedUser.title": "사용자 상세",
    "panel.selectedUser.meta": "여기서 작업 내용을 검토하세요.",
    "panel.aiUsage.label": "AI 사용량",
    "panel.aiUsage.title": "일간 및 주간 AI 스냅샷",
    "panel.aiPromptLimits.label": "AI 프롬프트 제한",
    "panel.aiPromptLimits.title": "무료 플랜 기본값",
    "panel.aiPromptLimits.meta": "무료 사용자에게 서버에서 강제되는 프롬프트 제한입니다.",
    "panel.aiRuntime.label": "AI 런타임",
    "panel.aiRuntime.title": "서버 프롬프트 및 모델 설정",
    "panel.aiRuntime.meta": "서버가 소유하는 AI 기능의 프롬프트와 런타임 재정의입니다.",
    "panel.producerCaptureWhitelist.label": "프로듀서 캡처 화이트리스트",
    "panel.producerCaptureWhitelist.title": "프로듀서 캡처 사용자명",
    "panel.producerCaptureWhitelist.meta":
      "프로듀서 캡처 UI 토글을 볼 수 있는 사용자명 허용 목록입니다.",
    "panel.features.title": "이번 주 가장 많이 쓴 AI 도구",
    "panel.tiers.label": "구독 플랜",
    "panel.tiers.title": "플랜",
    "panel.accountActivity.label": "계정 활동",
    "panel.accountActivity.title": "앱 데이터가 있는 계정",
    "panel.accountActivity.meta": "구독 또는 AI 사용 기록이 있는 사용자입니다.",
    "panel.projectActivity.label": "프로젝트 활동",
    "panel.projectActivity.title": "AI 사용이 있는 프로젝트",
    "panel.projectActivity.meta": "AI 사용 이벤트에서 확인된 프로젝트 ID입니다.",
    "panel.feedback.label": "사용자 피드백 / 버그",
    "panel.feedback.title": "피드백 및 버그 받은 편지함",
    "panel.feedback.meta": "최신 사용자 피드백과 버그 제보입니다.",
    "panel.selectedFeedback.label": "선택된 제출",
    "panel.selectedFeedback.title": "제출 상세",
    "panel.selectedFeedback.meta": "메시지, DAW 문맥, 스크린샷을 여기서 검토하세요.",
    "table.user": "사용자",
    "table.auth": "인증",
    "table.subscription": "구독",
    "table.state": "상태",
    "table.lastSeen": "마지막 활동",
    "table.type": "유형",
    "table.message": "메시지",
    "table.attachments": "첨부",
    "table.submitted": "제출 시각",
    "table.tier": "플랜",
    "table.status": "상태",
    "table.aiRequests": "AI 요청",
    "table.creditsToday": "오늘 크레딧",
    "table.tokensMonth": "이번 달 토큰",
    "table.project": "프로젝트",
    "table.requests": "요청",
    "table.users": "사용자 수",
    "table.credits": "크레딧",
    "table.tokens": "토큰",
    "table.lastActivity": "최근 활동",
    "empty.signInSearchUsers": "사용자를 검색하려면 로그인하세요.",
    "empty.selectUser": "상세와 작업을 보려면 사용자를 선택하세요.",
    "empty.signInFeatureUsage": "기능 사용량을 불러오려면 로그인하세요.",
    "empty.signInTierDistribution": "플랜 분포를 불러오려면 로그인하세요.",
    "empty.signInUserData": "사용자 데이터를 불러오려면 로그인하세요.",
    "empty.signInProjectData": "프로젝트 데이터를 불러오려면 로그인하세요.",
    "empty.signInFeedback": "사용자 피드백과 버그 제보를 불러오려면 로그인하세요.",
    "empty.signInAiPromptLimits": "AI 프롬프트 제한 설정을 불러오려면 로그인하세요.",
    "empty.signInAiRuntime": "AI 런타임 설정을 불러오려면 로그인하세요.",
    "empty.signInProducerCaptureWhitelist":
      "프로듀서 캡처 화이트리스트 설정을 불러오려면 로그인하세요.",
    "empty.selectFeedback": "전체 제출 내용을 보려면 피드백 항목 또는 버그 제보를 선택하세요.",
    "empty.feedbackLoading": "피드백 상세를 불러오는 중...",
    "status.configIncomplete":
      "관리자 사이트 설정이 완전하지 않습니다. 배포 전에 admin_site/config.js를 업데이트하세요.",
    "status.signInToContinue": "계속하려면 로그인하세요.",
    "status.initializeFailed": "관리자 세션을 초기화할 수 없습니다.",
    "status.signedOut": "로그아웃되었습니다.",
    "status.loadingAdminOverview": "관리자 개요를 불러오는 중...",
    "status.adminOverviewLoaded": "관리자 개요를 불러왔습니다.",
    "status.loadAdminOverviewFailed": "관리자 개요를 불러올 수 없습니다.",
    "status.searchingUsers": "사용자를 검색하는 중...",
    "status.loadingRecentUsers": "최근 사용자를 불러오는 중...",
    "status.loadingFeedback": "피드백 및 버그 받은 편지함을 불러오는 중...",
    "status.loadingAiPromptLimits": "AI 프롬프트 제한 설정을 불러오는 중...",
    "status.loadingAiRuntime": "AI 런타임 설정을 불러오는 중...",
    "status.loadingProducerCaptureWhitelist":
      "프로듀서 캡처 화이트리스트 설정을 불러오는 중...",
    "status.aiPromptLimitsLoaded": "AI 프롬프트 제한 설정을 불러왔습니다.",
    "status.aiRuntimeLoaded": "AI 런타임 설정을 불러왔습니다.",
    "status.producerCaptureWhitelistLoaded":
      "프로듀서 캡처 화이트리스트 설정을 불러왔습니다.",
    "status.noUsersFound": "일치하는 사용자가 없습니다.",
    "status.searchUsersFailed": "사용자 검색에 실패했습니다.",
    "status.loadFeedbackFailed": "사용자 피드백 또는 버그 제보를 불러오지 못했습니다.",
    "status.loadAiPromptLimitsFailed": "AI 프롬프트 제한 설정을 불러오지 못했습니다.",
    "status.loadAiRuntimeFailed": "AI 런타임 설정을 불러오지 못했습니다.",
    "status.loadProducerCaptureWhitelistFailed":
      "프로듀서 캡처 화이트리스트 설정을 불러오지 못했습니다.",
    "status.grantingPrompts": "{target}에 추가 AI 프롬프트를 부여하는 중...",
    "status.promptsGranted": "추가 AI 프롬프트를 부여했습니다.",
    "status.grantPromptsFailed": "추가 AI 프롬프트 부여에 실패했습니다.",
    "status.applyingEntitlementOverride": "{target}에 플랜 재정의를 적용하는 중...",
    "status.entitlementOverrideApplied": "플랜 재정의를 적용했습니다.",
    "status.entitlementOverrideFailed": "플랜 재정의를 적용하지 못했습니다.",
    "status.savingAiPromptLimits": "AI 프롬프트 제한 설정을 저장하는 중...",
    "status.aiPromptLimitsSaved": "AI 프롬프트 제한 설정을 저장했습니다.",
    "status.saveAiPromptLimitsFailed": "AI 프롬프트 제한 설정 저장에 실패했습니다.",
    "status.savingProducerCaptureWhitelist":
      "프로듀서 캡처 화이트리스트 설정을 저장하는 중...",
    "status.producerCaptureWhitelistSaved":
      "프로듀서 캡처 화이트리스트 설정을 저장했습니다.",
    "status.saveProducerCaptureWhitelistFailed":
      "프로듀서 캡처 화이트리스트 설정 저장에 실패했습니다.",
    "status.savingAiRuntime": "AI 런타임 설정을 저장하는 중...",
    "status.aiRuntimeSaved": "AI 런타임 설정을 저장했습니다.",
    "status.saveAiRuntimeFailed": "AI 런타임 설정 저장에 실패했습니다.",
    "status.deletingUser": "{target} 삭제 중...",
    "status.userDeleted": "사용자를 삭제하고 tombstone 처리했습니다.",
    "status.deleteRequiresForce": "삭제하려면 강제 확인이 필요합니다.",
    "status.deleteUserFailed": "사용자 삭제에 실패했습니다.",
    "status.employeeSignInRequired": "직원 로그인이 필요합니다.",
    "status.requestFailed": "요청이 상태 코드 {status}(으)로 실패했습니다.",
    "status.hostedStateFailed": "Hosted 로그인 상태 검증에 실패했습니다.",
    "status.hostedSignInFailed": "Hosted 로그인에 실패했습니다.",
    "status.sessionRefreshFailed": "세션 갱신에 실패했습니다.",
    "status.sessionMissingEmail": "세션에 이메일 클레임이 없습니다.",
    "status.signInConfigIncomplete": "관리자 사이트 설정이 완전하지 않습니다.",
    "status.sessionExpiredIdle":
      "{minutes}분 동안 활동이 없어 관리자 세션이 만료되었습니다. 다시 로그인하세요.",
    "status.sessionExpiredAbsolute": "관리자 세션이 만료되었습니다. 다시 로그인하세요.",
    "summary.users": "사용자",
    "summary.usersDetail": "AI 또는 결제 데이터가 있는 사용자 {count}명",
    "summary.aiPromptsToday": "오늘 AI 프롬프트",
    "summary.aiPromptsTodayDetail": "오늘 AI 활성 사용자 {count}명",
    "summary.aiPromptsWeek": "최근 7일 AI 프롬프트",
    "summary.aiPromptsWeekDetail": "이번 주 AI 활성 사용자 {count}명",
    "summary.paidUsers": "유료 사용자",
    "summary.paidUsersDetail": "활성 구독 {count}",
    "generated.at": "{date} 생성",
    "generated.unavailable": "생성 시각 없음",
    "identity.signedInAs": "{email}(으)로 로그인됨",
    "identity.employeeAccess": "허용 목록에 있는 직원 접근",
    "identity.employeeEmailsOnly": "허용 목록의 직원 이메일만 허용",
    "identity.employee": "직원",
    "identity.notSignedIn": "로그인되지 않음",
    "usage.promptsToday": "오늘 프롬프트",
    "usage.promptsWeek": "최근 7일 프롬프트",
    "usage.activeUsersToday": "오늘 AI 사용자",
    "usage.activeUsersWeek": "최근 7일 AI 사용자",
    "usage.avgPromptsPerUserToday": "오늘 사용자당 평균 프롬프트",
    "usage.avgPromptsPerUserWeek": "최근 7일 사용자당 평균 프롬프트",
    "usage.avgLatencyToday": "오늘 평균 지연 시간",
    "usage.avgLatencyWeek": "최근 7일 평균 지연 시간",
    "usage.na": "해당 없음",
    "usage.noFeatures": "기록된 AI 기능 이벤트가 아직 없습니다.",
    "overview.loading": "불러오는 중…",
    "overview.loadingSection": "이 섹션을 불러오는 중…",
    "analytics.metric.dau": "DAU",
    "analytics.metric.wau": "WAU",
    "analytics.metric.mau": "MAU",
    "analytics.metric.hours24h": "24시간 사용",
    "analytics.emptyTrend": "아직 추이 데이터가 없습니다.",
    "analytics.emptyCountries": "아직 국가 데이터가 없습니다.",
    "analytics.chartUnavailable": "차트 보기를 일시적으로 사용할 수 없습니다.",
    "analytics.countryUsers": "활성 사용자 {count}명",
    "analytics.countryShare": "표시된 국가 중 {share}",
    "analytics.countryFeatured": "현재 가장 강한 지역",
    "analytics.countryListLabel": "국가 분포",
    "tiers.noData": "플랜 데이터가 없습니다.",
    "tiers.usersActive": "사용자 {users}명 • 활성 {active}명",
    "trackedUsers.none": "결제 또는 AI 사용 데이터가 있는 사용자가 아직 없습니다.",
    "projects.none": "AI 활동이 확인된 프로젝트 ID가 아직 없습니다.",
    "projects.lastUser": "최근 사용자: {user}",
    "search.meta": "검색: {query}",
    "search.recentAccounts": "최근 계정",
    "adminUsers.none": "검색 조건에 맞는 사용자가 없습니다.",
    "feedback.none": "아직 제출된 피드백이나 버그 제보가 없습니다.",
    "feedback.detail.user": "사용자",
    "feedback.detail.source": "출처",
    "feedback.detail.client": "클라이언트",
    "feedback.detail.attachments": "첨부",
    "feedback.detail.emailConsent": "이메일 후속 연락",
    "feedback.detail.submitted": "제출 시각",
    "feedback.detail.message": "메시지",
    "feedback.detail.context": "DAW 문맥",
    "feedback.detail.screenshot": "스크린샷",
    "feedback.attachments.context": "문맥",
    "feedback.attachments.screenshot": "스크린샷",
    "feedback.attachments.none": "없음",
    "feedback.contact.allowed": "허용",
    "feedback.contact.notAllowed": "허용 안 함",
    "feedback.category.feedback": "피드백",
    "feedback.category.bug_report": "버그 제보",
    "feedback.source.home": "홈",
    "feedback.source.account": "계정",
    "feedback.source.daw_chat": "DAW 채팅",
    "user.usernameLine": "사용자명: {value}",
    "user.musicProfileLine": "음악 프로필: {value}",
    "user.birthdateLine": "생년월일: {value}",
    "user.userIdLine": "사용자 ID: {value}",
    "inspector.selectedUser": "선택된 사용자",
    "inspector.noEmail": "이메일 없음",
    "detail.userId": "사용자 ID",
    "detail.name": "이름",
    "detail.username": "사용자명",
    "detail.birthdate": "생년월일",
    "detail.age": "나이",
    "detail.musicProfile": "음악 프로필",
    "detail.appAuth": "앱 인증",
    "detail.emailVerification": "이메일 인증",
    "detail.nativeSessions": "네이티브 세션",
    "detail.legacyCognito": "레거시 Cognito",
    "detail.subscription": "구독",
    "detail.onboarding": "온보딩",
    "detail.aiPrompts": "AI 프롬프트",
    "detail.extraPromptBank": "추가 프롬프트 뱅크",
    "detail.lastSeen": "마지막 활동",
    "detail.created": "생성일",
    "detail.updated": "수정일",
    "settings.currentLimits": "현재 적용 중인 제한",
    "settings.currentAiRuntime": "현재 AI 런타임 재정의",
    "settings.currentProducerCaptureWhitelist": "현재 프로듀서 캡처 화이트리스트",
    "settings.producerCaptureWhitelistUsernames": "사용자명(쉼표 또는 줄바꿈 구분)",
    "settings.producerCaptureWhitelistNone": "현재 허용된 사용자명이 없습니다.",
    "settings.editableByAnyAdmin": "모든 관리자가 이 목록을 수정할 수 있습니다.",
    "settings.confirmProducerCaptureWhitelist":
      "확인을 위해 APPLY PRODUCER WHITELIST 를 입력하세요",
    "settings.freeDailyPromptLimit": "무료 일일 프롬프트 제한",
    "settings.freeWeeklyPromptLimit": "무료 주간 프롬프트 제한",
    "settings.feature.ai_chat": "DAW 채팅",
    "settings.feature.video_editor_chat": "비디오 편집 채팅",
    "settings.modelOverride": "모델 재정의",
    "settings.systemPromptOverride": "시스템 프롬프트 재정의",
    "settings.maxOutputTokensOverride": "최대 출력 토큰 재정의",
    "settings.temperatureOverride": "온도 재정의",
    "settings.reasoningEffortOverride": "추론 강도 재정의",
    "settings.promptCacheRetentionOverride": "프롬프트 캐시 유지 재정의",
    "settings.currentSavedOverride": "현재 저장된 재정의",
    "settings.emptyUsesDefault": "필드를 비워 두면 현재 백엔드 기본값을 유지합니다.",
    "settings.readOnly": "관리자에게는 보이지만 수정 권한은 andrew@mixroom.ai 계정으로 제한됩니다.",
    "settings.andrewOnlyControl": "개발용 설정 화면이며 수정 권한은 andrew@mixroom.ai 계정으로 제한됩니다.",
    "settings.usingBackendDefault": "(기본값) {value}",
    "settings.noPromptOverride": "저장된 프롬프트 재정의 없음",
    "settings.confirmPromptLimits": "확인을 위해 APPLY PROMPT LIMITS 를 입력하세요",
    "settings.confirmAiRuntime": "확인을 위해 APPLY {feature} OVERRIDE 를 입력하세요",
    "settings.source.default": "배포된 기본값",
    "settings.source.remote": "원격 재정의",
    "settings.updatedAt": "{date}에 수정",
    "settings.updatedBy": "{email}에 의해 수정",
    "support.label": "AI 지원",
    "support.title": "추가 프롬프트 부여",
    "support.copy":
      "지원 상황에서 사용할 일회성 추가 프롬프트 뱅크를 더합니다. 이 프롬프트는 일일/주간 한도보다 먼저 사용됩니다.",
    "support.readOnly": "관리자에게는 보이지만 andrew@mixroom.ai 계정만 수정할 수 있습니다.",
    "support.inputLabel": "추가할 프롬프트 수",
    "support.granting": "부여 중...",
    "support.button": "추가 프롬프트 부여",
    "override.label": "권한 지원",
    "override.title": "임시 플랜 재정의",
    "override.copy":
      "결제 제공업체의 구독을 변경하지 않고 임시 접근 권한을 부여합니다. 모든 사용 기록은 감사 로그에 저장됩니다.",
    "override.readOnly": "관리자에게는 보이지만 andrew@mixroom.ai 계정만 수정할 수 있습니다.",
    "override.plan": "부여할 플랜",
    "override.seats": "좌석 수",
    "override.seatsHelp":
      "Studio는 최소 5석입니다. Education은 학생 좌석 10, 20, 30개를 지원하며 교사/관리자 접근은 별도입니다.",
    "override.organizationName": "팀 또는 학교 이름",
    "override.organizationNamePlaceholder": "선택 사항",
    "override.expiry": "만료일",
    "override.duration.1d": "1일",
    "override.duration.1w": "1주",
    "override.duration.1m": "1개월",
    "override.duration.1y": "1년",
    "override.reason": "사유",
    "override.reasonPlaceholder": "지원 티켓, 로컬 테스트, 긴급 상황 등",
    "override.confirmIdentifier": "사용자의 이메일, 사용자명, 또는 사용자 ID 입력",
    "override.confirmAdminName": "관리자 본인 이름 입력: {value}",
    "override.applying": "적용 중...",
    "override.button": "재정의 적용",
    "override.applied": "{date}까지 {plan} 권한을 부여했습니다.",
    "override.typeExactIdentifier": "일치하는 사용자 이메일, 사용자명, 또는 사용자 ID를 입력하세요.",
    "override.typeExactAdminName": "관리자 본인 이름을 정확히 입력하세요.",
    "delete.label": "사용자 삭제",
    "delete.title": "계정 삭제",
    "delete.copy":
      "인증 계정, 프로필, 구독 기록, 연결된 제공업체를 삭제하고 사용자명을 다시 사용할 수 있게 합니다.",
    "delete.activeSubscriptionWarning": "이 사용자는 아직 활성 유료 구독이 있습니다.",
    "delete.reason": "사유",
    "delete.reasonPlaceholder": "이 계정을 삭제하는 이유는 무엇인가요?",
    "delete.confirm": "확인을 위해 {value} 입력",
    "delete.confirmEmail": "사용자의 로그인 이메일을 정확히 입력",
    "delete.confirmEmailPlaceholder": "{value}",
    "delete.force": "사용자에게 활성 유료 구독이 있어도 강제로 삭제합니다.",
    "delete.deleting": "삭제 중...",
    "delete.button": "사용자 삭제",
    "delete.typeExact": "삭제를 확인하려면 {value}를 정확히 입력하세요.",
    "delete.typeExactEmail": "삭제를 확인하려면 로그인 이메일 {value}를 정확히 입력하세요.",
    "delete.forceRequired": "이 삭제에는 강제 확인이 필요합니다.",
    "detail.na": "해당 없음",
    "authSource.native": "네이티브",
    "authSource.nativeLegacyBridge": "네이티브 + 레거시",
    "authSource.legacyOnly": "레거시 Cognito",
    "authSource.unknown": "알 수 없음",
    "provider.email": "이메일",
    "provider.google": "구글",
    "provider.apple": "애플",
    "provider.kakao": "카카오",
    "provider.unknown": "알 수 없음",
    "value.verified": "인증됨",
    "value.unverified": "미인증",
    "value.noNativeAuthAccount": "네이티브 인증 계정 없음",
    "value.zeroSessions": "세션 0개",
    "value.nativeSessionsSummary": "활성 {active}/{total} • 최근 만료 {expiry}",
    "value.notLinked": "연결되지 않음",
    "value.musicProfile.producer": "프로듀서",
    "value.musicProfile.artist": "아티스트",
    "value.musicProfile.songwriter": "송라이터",
    "value.musicProfile.audio_engineer": "오디오 엔지니어",
    "value.musicProfile.student": "학생",
    "value.musicProfile.music_enthusiast": "음악 애호가",
    "value.musicProfile.beginner": "입문자",
    "value.musicProfile.music_for_work": "업무로 음악 제작",
    "value.migrated": "{date}에 마이그레이션됨",
    "value.todayWeek": "오늘 {today} • 이번 주 {week}",
    "value.remainingGranted": "남음 {remaining} • 총 부여 {granted}",
    "value.extraPromptsAdded": "추가 프롬프트 {count}개를 부여했습니다.",
    "value.dailyWeeklyLimits": "일일 {daily} • 주간 {weekly}",
    "value.showingCount": "{shown}개 표시 중",
    "value.showingOfTotal": "{total}개 중 {shown}개 표시 중",
    "value.userLoaded": "사용자 {count}명을 불러왔습니다.",
    "value.usersLoaded": "사용자 {count}명을 불러왔습니다.",
    "value.free": "무료",
    "value.starter": "스타터",
    "value.pro": "프로듀서",
    "value.producer": "프로듀서",
    "value.studio": "스튜디오",
    "value.enterprise": "엔터프라이즈",
    "value.education": "교육",
    "value.active": "활성",
    "value.trialing": "체험 중",
    "value.grace_period": "유예 기간",
    "value.past_due": "연체",
    "value.paused": "일시중지",
    "value.canceled": "취소됨",
    "value.expired": "만료됨",
    "value.refunded": "환불됨",
    "value.revoked": "회수됨",
    "value.unknown": "알 수 없음",
    "value.signup_complete": "가입 완료",
    "value.bootstrap_only": "부트스트랩 전용",
    "value.profile_ready": "프로필 준비됨",
    "value.complete": "완료",
    "value.pending": "대기 중",
    "value.deleted": "삭제됨",
    "value.disabled": "비활성화",
    "value.locked": "잠김",
    "value.suspended": "정지됨",
  },
};

const config = window.MIXROOM_ADMIN_CONFIG || {};
const elements = {
  signInButtonSecondary: document.querySelector("#sign-in-button-secondary"),
  refreshButton: document.querySelector("#refresh-button"),
  signOutButton: document.querySelector("#sign-out-button"),
  signedInHero: document.querySelector("#welcome-banner"),
  statusPanel: document.querySelector("#status-panel"),
  signedOutStatusPanel: document.querySelector("#signed-out-status-panel"),
  identityEmail: document.querySelector("#identity-email"),
  identityMeta: document.querySelector("#identity-meta"),
  signedOutPanel: document.querySelector("#signed-out-panel"),
  dashboard: document.querySelector("#dashboard"),
  welcomeBanner: document.querySelector("#welcome-banner"),
  welcomeName: document.querySelector("#welcome-name"),
  livePresenceBadge: document.querySelector("#live-presence-badge"),
  livePresenceLabel: document.querySelector("#live-presence-label"),
  livePresenceValue: document.querySelector("#live-presence-value"),
  tabButtons: Array.from(document.querySelectorAll("[data-tab-button]")),
  tabPanels: Array.from(document.querySelectorAll("[data-tab-panel]")),
  tabLoadingStates: Object.fromEntries(
    Array.from(document.querySelectorAll("[data-tab-loading]")).map((node) => [
      `${node.dataset.tabLoading || ""}`.trim(),
      node,
    ]),
  ),
  tabLoadingLabels: Object.fromEntries(
    Array.from(document.querySelectorAll("[data-tab-loading-label]")).map((node) => [
      `${node.dataset.tabLoadingLabel || ""}`.trim(),
      node,
    ]),
  ),
  homeSectionPanels: Object.fromEntries(
    Array.from(document.querySelectorAll("[data-home-section-panel]")).map((node) => [
      `${node.dataset.homeSectionPanel || ""}`.trim(),
      node,
    ]),
  ),
  homeSectionLoadingStates: Object.fromEntries(
    Array.from(document.querySelectorAll("[data-home-section-loading]")).map((node) => [
      `${node.dataset.homeSectionLoading || ""}`.trim(),
      node,
    ]),
  ),
  homeSectionLoadingLabels: Object.fromEntries(
    Array.from(document.querySelectorAll("[data-home-section-loading-label]")).map((node) => [
      `${node.dataset.homeSectionLoadingLabel || ""}`.trim(),
      node,
    ]),
  ),
  generatedAt: document.querySelector("#generated-at"),
  aiPromptLimitsMeta: document.querySelector("#ai-prompt-limits-meta"),
  aiPromptLimitsSummary: document.querySelector("#ai-prompt-limits-summary"),
  aiPromptLimitsForm: document.querySelector("#ai-prompt-limits-form"),
  freeDailyPromptLimitInput: document.querySelector("#free-daily-prompt-limit"),
  freeWeeklyPromptLimitInput: document.querySelector("#free-weekly-prompt-limit"),
  aiPromptLimitsEditorNote: document.querySelector("#ai-prompt-limits-editor-note"),
  aiPromptLimitsConfirmWrap: document.querySelector("#ai-prompt-limits-confirm-wrap"),
  aiPromptLimitsConfirmLabel: document.querySelector("#ai-prompt-limits-confirm-label"),
  aiPromptLimitsConfirmInput: document.querySelector("#ai-prompt-limits-confirm-input"),
  aiPromptLimitsSaveButton: document.querySelector("#ai-prompt-limits-save-button"),
  aiPromptLimitsFeedback: document.querySelector("#ai-prompt-limits-feedback"),
  producerCaptureWhitelistMeta: document.querySelector("#producer-capture-whitelist-meta"),
  producerCaptureWhitelistSummary: document.querySelector("#producer-capture-whitelist-summary"),
  producerCaptureWhitelistForm: document.querySelector("#producer-capture-whitelist-form"),
  producerCaptureWhitelistInput: document.querySelector("#producer-capture-whitelist-input"),
  producerCaptureWhitelistEditorNote: document.querySelector(
    "#producer-capture-whitelist-editor-note",
  ),
  producerCaptureWhitelistConfirmWrap: document.querySelector(
    "#producer-capture-whitelist-confirm-wrap",
  ),
  producerCaptureWhitelistConfirmLabel: document.querySelector(
    "#producer-capture-whitelist-confirm-label",
  ),
  producerCaptureWhitelistConfirmInput: document.querySelector(
    "#producer-capture-whitelist-confirm-input",
  ),
  producerCaptureWhitelistSaveButton: document.querySelector(
    "#producer-capture-whitelist-save-button",
  ),
  producerCaptureWhitelistFeedback: document.querySelector(
    "#producer-capture-whitelist-feedback",
  ),
  aiRuntimePanel: document.querySelector("#ai-runtime-panel"),
  aiRuntimeMeta: document.querySelector("#ai-runtime-meta"),
  aiRuntimeSettings: document.querySelector("#ai-runtime-settings"),
  billingCatalogMeta: document.querySelector("#billing-catalog-meta"),
  billingCatalogSummary: document.querySelector("#billing-catalog-summary"),
  billingCatalogPreview: document.querySelector("#billing-catalog-preview"),
  billingCatalogForm: document.querySelector("#billing-catalog-form"),
  billingCatalogSupportEmailInput: document.querySelector("#billing-catalog-support-email"),
  billingCatalogContactLabelInput: document.querySelector("#billing-catalog-contact-label"),
  billingCatalogSupportUrlInput: document.querySelector("#billing-catalog-support-url"),
  billingCatalogFaqUrlInput: document.querySelector("#billing-catalog-faq-url"),
  billingCatalogManageSubscriptionUrlInput: document.querySelector(
    "#billing-catalog-manage-subscription-url",
  ),
  billingCatalogRefundPolicyUrlInput: document.querySelector(
    "#billing-catalog-refund-policy-url",
  ),
  billingCatalogDefaultCheckoutUrlInput: document.querySelector(
    "#billing-catalog-default-checkout-url",
  ),
  billingCatalogPlansInput: document.querySelector("#billing-catalog-plans-input"),
  billingCatalogProductsInput: document.querySelector("#billing-catalog-products-input"),
  billingCatalogProviderProductsInput: document.querySelector(
    "#billing-catalog-provider-products-input",
  ),
  billingCatalogSaveButton: document.querySelector("#billing-catalog-save-button"),
  billingCatalogFeedback: document.querySelector("#billing-catalog-feedback"),
  billingOrganizationsMeta: document.querySelector("#billing-organizations-meta"),
  billingOrganizationsTableBody: document.querySelector("#billing-organizations-table-body"),
  billingOrganizationsPageMeta: document.querySelector("#billing-organizations-page-meta"),
  billingEducationSummary: document.querySelector("#billing-education-summary"),
  billingEducationCurrentPlan: document.querySelector("#billing-education-current-plan"),
  billingEducationSeats: document.querySelector("#billing-education-seats"),
  billingEducationProvisionForm: document.querySelector("#billing-education-provision-form"),
  billingEducationProvisionOrgIdInput: document.querySelector(
    "#billing-education-provision-org-id",
  ),
  billingEducationProvisionNameInput: document.querySelector("#billing-education-provision-name"),
  billingEducationProvisionSeatsInput: document.querySelector("#billing-education-provision-seats"),
  billingEducationProvisionTeacherUserIdInput: document.querySelector(
    "#billing-education-provision-teacher-user-id",
  ),
  billingEducationProvisionTeacherEmailInput: document.querySelector(
    "#billing-education-provision-teacher-email",
  ),
  billingEducationProvisionSelectedUserButton: document.querySelector(
    "#billing-education-provision-selected-user-button",
  ),
  billingEducationProvisionSaveButton: document.querySelector(
    "#billing-education-provision-save-button",
  ),
  billingEducationProvisionFeedback: document.querySelector(
    "#billing-education-provision-feedback",
  ),
  billingOrganizationForm: document.querySelector("#billing-organization-form"),
  billingOrganizationIdInput: document.querySelector("#billing-organization-id"),
  billingOrganizationNameInput: document.querySelector("#billing-organization-name"),
  billingOrganizationPlanCodeInput: document.querySelector("#billing-organization-plan-code"),
  billingOrganizationSeatLimitInput: document.querySelector("#billing-organization-seat-limit"),
  billingOrganizationStatusInput: document.querySelector("#billing-organization-status"),
  billingOrganizationSharedWorkspaceEnabledInput: document.querySelector(
    "#billing-organization-shared-workspace-enabled",
  ),
  billingOrganizationSupportNotesInput: document.querySelector(
    "#billing-organization-support-notes",
  ),
  billingOrganizationSaveButton: document.querySelector("#billing-organization-save-button"),
  billingOrganizationClearButton: document.querySelector("#billing-organization-clear-button"),
  billingOrganizationFeedback: document.querySelector("#billing-organization-feedback"),
  billingMembershipsMeta: document.querySelector("#billing-memberships-meta"),
  billingMembershipsTableBody: document.querySelector("#billing-memberships-table-body"),
  billingMembershipsPageMeta: document.querySelector("#billing-memberships-page-meta"),
  billingMembershipForm: document.querySelector("#billing-membership-form"),
  billingMembershipOrganizationIdInput: document.querySelector(
    "#billing-membership-organization-id",
  ),
  billingMembershipUserIdInput: document.querySelector("#billing-membership-user-id"),
  billingMembershipEmailInput: document.querySelector("#billing-membership-email"),
  billingMembershipRoleInput: document.querySelector("#billing-membership-role"),
  billingMembershipStatusInput: document.querySelector("#billing-membership-status"),
  billingMembershipSeatConsumedInput: document.querySelector("#billing-membership-seat-consumed"),
  billingMembershipSaveButton: document.querySelector("#billing-membership-save-button"),
  billingMembershipClearButton: document.querySelector("#billing-membership-clear-button"),
  billingMembershipFeedback: document.querySelector("#billing-membership-feedback"),
  billingWorkspacesMeta: document.querySelector("#billing-workspaces-meta"),
  billingWorkspacesTableBody: document.querySelector("#billing-workspaces-table-body"),
  billingWorkspacesPageMeta: document.querySelector("#billing-workspaces-page-meta"),
  billingWorkspaceForm: document.querySelector("#billing-workspace-form"),
  billingWorkspaceIdInput: document.querySelector("#billing-workspace-id"),
  billingWorkspaceNameInput: document.querySelector("#billing-workspace-name"),
  billingWorkspaceOrganizationIdInput: document.querySelector(
    "#billing-workspace-organization-id",
  ),
  billingWorkspaceOwnerUserIdInput: document.querySelector("#billing-workspace-owner-user-id"),
  billingWorkspaceVisibilityInput: document.querySelector("#billing-workspace-visibility"),
  billingWorkspaceDefaultProjectPrivacyInput: document.querySelector(
    "#billing-workspace-default-project-privacy",
  ),
  billingWorkspaceStatusInput: document.querySelector("#billing-workspace-status"),
  billingWorkspaceSaveButton: document.querySelector("#billing-workspace-save-button"),
  billingWorkspaceClearButton: document.querySelector("#billing-workspace-clear-button"),
  billingWorkspaceFeedback: document.querySelector("#billing-workspace-feedback"),
  billingCloudProjectsMeta: document.querySelector("#billing-cloud-projects-meta"),
  billingCloudProjectsTableBody: document.querySelector("#billing-cloud-projects-table-body"),
  billingCloudProjectsPageMeta: document.querySelector("#billing-cloud-projects-page-meta"),
  billingCloudProjectForm: document.querySelector("#billing-cloud-project-form"),
  billingCloudProjectIdInput: document.querySelector("#billing-cloud-project-id"),
  billingCloudProjectNameInput: document.querySelector("#billing-cloud-project-name"),
  billingCloudProjectWorkspaceIdInput: document.querySelector(
    "#billing-cloud-project-workspace-id",
  ),
  billingCloudProjectOrganizationIdInput: document.querySelector(
    "#billing-cloud-project-organization-id",
  ),
  billingCloudProjectOwnerUserIdInput: document.querySelector(
    "#billing-cloud-project-owner-user-id",
  ),
  billingCloudProjectStorageModeInput: document.querySelector(
    "#billing-cloud-project-storage-mode",
  ),
  billingCloudProjectDocumentRevisionInput: document.querySelector(
    "#billing-cloud-project-document-revision",
  ),
  billingCloudProjectStatusInput: document.querySelector("#billing-cloud-project-status"),
  billingCloudProjectDocumentInput: document.querySelector("#billing-cloud-project-document"),
  billingCloudProjectSaveButton: document.querySelector("#billing-cloud-project-save-button"),
  billingCloudProjectClearButton: document.querySelector("#billing-cloud-project-clear-button"),
  billingCloudProjectFeedback: document.querySelector("#billing-cloud-project-feedback"),
  summarySection: document.querySelector("#summary-section"),
  aiUsageMetrics: document.querySelector("#ai-usage-metrics"),
  topFeatures: document.querySelector("#top-features"),
  tierBreakdown: document.querySelector("#tier-breakdown"),
  trackedUsersTableBody: document.querySelector("#users-table-body"),
  trackedUsersPageMeta: document.querySelector("#tracked-users-page-meta"),
  trackedUsersShowLessButton: document.querySelector("#tracked-users-show-less-button"),
  trackedUsersShowMoreButton: document.querySelector("#tracked-users-show-more-button"),
  projectsTableBody: document.querySelector("#projects-table-body"),
  projectsPageMeta: document.querySelector("#projects-page-meta"),
  projectsShowLessButton: document.querySelector("#projects-show-less-button"),
  projectsShowMoreButton: document.querySelector("#projects-show-more-button"),
  userSearchForm: document.querySelector("#user-search-form"),
  userSearchInput: document.querySelector("#user-search-input"),
  userSearchButton: document.querySelector("#user-search-button"),
  userSearchClearButton: document.querySelector("#user-search-clear-button"),
  userSearchMeta: document.querySelector("#user-search-meta"),
  adminUsersTableBody: document.querySelector("#admin-users-table-body"),
  adminUsersPageMeta: document.querySelector("#admin-users-page-meta"),
  adminUsersShowLessButton: document.querySelector("#admin-users-show-less-button"),
  adminUsersShowMoreButton: document.querySelector("#admin-users-show-more-button"),
  userInspector: document.querySelector("#user-inspector"),
  feedbackTableBody: document.querySelector("#feedback-table-body"),
  feedbackPageMeta: document.querySelector("#feedback-page-meta"),
  feedbackShowLessButton: document.querySelector("#feedback-show-less-button"),
  feedbackShowMoreButton: document.querySelector("#feedback-show-more-button"),
  feedbackInspector: document.querySelector("#feedback-inspector"),
  analyticsCallout: document.querySelector("#analytics-callout"),
  posthogLink: document.querySelector("#posthog-link"),
  kpiPanel: document.querySelector("#kpi-panel"),
  kpiMeta: document.querySelector("#kpi-meta"),
  analyticsRangeControls: document.querySelector("#analytics-range-controls"),
  analyticsSummary: document.querySelector("#analytics-summary"),
  analyticsActivityTrend: document.querySelector("#analytics-activity-trend"),
  analyticsHoursTrend: document.querySelector("#analytics-hours-trend"),
  analyticsCountryList: document.querySelector("#analytics-country-list"),
  aiObservabilityMeta: document.querySelector("#ai-observability-meta"),
  aiObservabilitySummary: document.querySelector("#ai-observability-summary"),
  aiObservabilityCounts: document.querySelector("#ai-observability-counts"),
  aiObservabilityTracesBody: document.querySelector("#ai-observability-traces-body"),
  aiObservabilityTracePageMeta: document.querySelector("#ai-observability-traces-page-meta"),
  aiObservabilityTracesShowLessButton: document.querySelector("#ai-observability-traces-show-less-button"),
  aiObservabilityTracesShowMoreButton: document.querySelector("#ai-observability-traces-show-more-button"),
  languageSelector: document.querySelector("#language-selector"),
  signedOutLanguageSelector: document.querySelector("#signed-out-language-selector"),
};

const state = {
  locale: loadLocale(),
  overviewBusy: false,
  userSearchBusy: false,
  feedbackBusy: false,
  aiPromptLimitsBusy: false,
  producerCaptureWhitelistBusy: false,
  aiRuntimeBusy: false,
  billingCatalogBusy: false,
  billingOrganizationsBusy: false,
  billingMembershipsBusy: false,
  billingWorkspacesBusy: false,
  billingCloudProjectsBusy: false,
  deleteBusy: false,
  grantBusy: false,
  activeTab: DEFAULT_TAB,
  currentSearchQuery: "",
  overview: null,
  overviewIncludes: buildOverviewIncludes(),
  homeSectionLoading: buildHomeSectionLoading(),
  overviewUserLimit: DEFAULT_OVERVIEW_USERS_LIMIT,
  overviewProjectLimit: DEFAULT_OVERVIEW_PROJECTS_LIMIT,
  overviewTraceLimit: DEFAULT_OVERVIEW_TRACE_LIMIT,
  lastUserSearchPayload: null,
  userSearchLimit: DEFAULT_ADMIN_USERS_LIMIT,
  adminUsers: [],
  selectedUserId: "",
  lastFeedbackPayload: null,
  feedbackLimit: DEFAULT_FEEDBACK_LIMIT,
  feedbackList: [],
  selectedFeedbackId: "",
  selectedFeedback: null,
  aiPromptLimits: null,
  aiPromptLimitsFeedback: null,
  producerCaptureWhitelist: null,
  producerCaptureWhitelistFeedback: null,
  aiRuntimeSettings: null,
  aiRuntimeFeedbackByFeature: {},
  billingCatalog: null,
  billingCatalogConfigurable: true,
  billingCatalogFeedback: null,
  billingOrganizations: [],
  billingOrganizationsLoaded: false,
  billingMemberships: [],
  billingMembershipsLoaded: false,
  billingWorkspaces: [],
  billingWorkspacesLoaded: false,
  billingCloudProjects: [],
  billingCloudProjectsLoaded: false,
  collaborationConfigurable: true,
  selectedBillingOrganizationId: "",
  selectedBillingMembershipKey: "",
  selectedBillingWorkspaceId: "",
  selectedBillingCloudProjectId: "",
  billingEducationProvisionFeedback: null,
  billingOrganizationFeedback: null,
  billingMembershipFeedback: null,
  billingWorkspaceFeedback: null,
  billingCloudProjectFeedback: null,
  livePresence: null,
  livePresenceRequestId: 0,
  analyticsRange: "7d",
  aiToolUsageRange: "7d",
  feedbackRequestId: 0,
  deleteFeedback: null,
  grantFeedback: null,
  overrideFeedback: null,
  overrideBusy: false,
  searchRequestId: 0,
  overviewRequestId: 0,
  loadedTabs: buildLoadedTabs(),
};

let tokens = loadTokens();
let currentUser = decodeIdToken(tokens?.idToken);
let sessionMeta = loadSessionMeta();
let sessionExpiryTimer = null;
let livePresenceTimer = null;
let lastActivityPersistAt = 0;
let welcomeAnimationPlayed = false;
const analyticsCharts = {};

bindEvents();
applyLocale();
bootstrap();

function bindEvents() {
  elements.signInButtonSecondary.addEventListener("click", beginSignIn);
  elements.refreshButton.addEventListener("click", refreshDashboard);
  elements.signOutButton.addEventListener("click", signOut);
  elements.tabButtons.forEach((button) => {
    button.addEventListener("click", handleTabClick);
  });
  elements.userSearchForm.addEventListener("submit", handleUserSearchSubmit);
  elements.userSearchClearButton.addEventListener("click", clearUserSearch);
  elements.adminUsersShowLessButton.addEventListener("click", handleAdminUsersShowLess);
  elements.adminUsersShowMoreButton.addEventListener("click", handleAdminUsersShowMore);
  elements.adminUsersTableBody.addEventListener("click", handleAdminUsersTableClick);
  elements.trackedUsersShowLessButton.addEventListener("click", handleTrackedUsersShowLess);
  elements.trackedUsersShowMoreButton.addEventListener("click", handleTrackedUsersShowMore);
  elements.projectsShowLessButton.addEventListener("click", handleProjectsShowLess);
  elements.projectsShowMoreButton.addEventListener("click", handleProjectsShowMore);
  elements.aiObservabilityTracesShowLessButton.addEventListener("click", handleAiObservabilityTracesShowLess);
  elements.aiObservabilityTracesShowMoreButton.addEventListener("click", handleAiObservabilityTracesShowMore);
  elements.aiObservabilityCounts.addEventListener("click", handleAiToolUsageRangeClick);
  elements.feedbackTableBody.addEventListener("click", handleFeedbackTableClick);
  elements.feedbackShowLessButton.addEventListener("click", handleFeedbackShowLess);
  elements.feedbackShowMoreButton.addEventListener("click", handleFeedbackShowMore);
  elements.analyticsRangeControls.addEventListener("click", handleAnalyticsRangeClick);
  elements.userInspector.addEventListener("submit", handleInspectorSubmit);
  elements.userInspector.addEventListener("click", handleInspectorClick);
  elements.userInspector.addEventListener("change", handleInspectorChange);
  elements.aiPromptLimitsForm.addEventListener("submit", handleAiPromptLimitsSubmit);
  elements.aiPromptLimitsConfirmInput.addEventListener("input", updateBusyState);
  elements.producerCaptureWhitelistForm.addEventListener(
    "submit",
    handleProducerCaptureWhitelistSubmit,
  );
  elements.producerCaptureWhitelistConfirmInput.addEventListener("input", updateBusyState);
  elements.aiRuntimeSettings.addEventListener("submit", handleAiRuntimeSubmit);
  elements.aiRuntimeSettings.addEventListener("input", handleAiRuntimeInputChange);
  elements.aiRuntimeSettings.addEventListener("change", handleAiRuntimeInputChange);
  elements.billingCatalogForm.addEventListener("submit", handleBillingCatalogSubmit);
  elements.billingEducationProvisionForm?.addEventListener(
    "submit",
    handleBillingEducationProvisionSubmit,
  );
  elements.billingEducationProvisionSelectedUserButton?.addEventListener(
    "click",
    fillEducationProvisionTeacherFromSelectedUser,
  );
  elements.billingOrganizationsTableBody.addEventListener("click", handleBillingOrganizationsTableClick);
  elements.billingEducationSummary?.addEventListener("click", handleEducationSeatPresetClick);
  elements.billingOrganizationForm.addEventListener("submit", handleBillingOrganizationSubmit);
  elements.billingOrganizationClearButton.addEventListener(
    "click",
    clearBillingOrganizationSelection,
  );
  elements.billingMembershipsTableBody.addEventListener("click", handleBillingMembershipsTableClick);
  elements.billingMembershipForm.addEventListener("submit", handleBillingMembershipSubmit);
  elements.billingMembershipClearButton.addEventListener("click", clearBillingMembershipSelection);
  elements.billingWorkspacesTableBody.addEventListener("click", handleBillingWorkspacesTableClick);
  elements.billingWorkspaceForm.addEventListener("submit", handleBillingWorkspaceSubmit);
  elements.billingWorkspaceClearButton.addEventListener("click", clearBillingWorkspaceSelection);
  elements.billingCloudProjectsTableBody.addEventListener(
    "click",
    handleBillingCloudProjectsTableClick,
  );
  elements.billingCloudProjectForm.addEventListener("submit", handleBillingCloudProjectSubmit);
  elements.billingCloudProjectClearButton.addEventListener(
    "click",
    clearBillingCloudProjectSelection,
  );
  elements.languageSelector.addEventListener("change", handleLocaleChange);
  elements.signedOutLanguageSelector.addEventListener("change", handleLocaleChange);
  ["pointerdown", "keydown", "scroll", "touchstart"].forEach((eventName) => {
    window.addEventListener(eventName, handleUserActivity, { passive: true });
  });
  window.addEventListener("focus", handleSessionCheckpoint);
  document.addEventListener("visibilitychange", handleSessionCheckpoint);
}

function handleLocaleChange(event) {
  setLocale(event.target.value);
}

function loadLocale() {
  const storedLocale = localStorage.getItem(LOCALE_STORAGE_KEY);
  if (SUPPORTED_LOCALES.has(storedLocale)) {
    return storedLocale;
  }

  const browserLocale = `${navigator.language || DEFAULT_LOCALE}`.toLowerCase();
  return browserLocale.startsWith("ko") ? "ko" : DEFAULT_LOCALE;
}

function setLocale(locale) {
  const nextLocale = SUPPORTED_LOCALES.has(locale) ? locale : DEFAULT_LOCALE;
  if (state.locale === nextLocale) {
    updateLanguageSelectors();
    return;
  }

  state.locale = nextLocale;
  localStorage.setItem(LOCALE_STORAGE_KEY, nextLocale);
  applyLocale();
}

function applyLocale() {
  document.documentElement.lang = state.locale;
  updateLanguageSelectors();
  applyStaticTranslations();
  configureAnalyticsCallout();
  rerenderForLocale();
}

function updateLanguageSelectors() {
  elements.languageSelector.value = state.locale;
  elements.signedOutLanguageSelector.value = state.locale;
}

function applyStaticTranslations() {
  document.querySelectorAll("[data-i18n]").forEach((node) => {
    const key = `${node.dataset.i18n || ""}`.trim();
    if (!key) {
      return;
    }
    node.textContent = tMaybe(key, node.textContent || "");
  });
  document.querySelectorAll("[data-i18n-placeholder]").forEach((node) => {
    const key = `${node.dataset.i18nPlaceholder || ""}`.trim();
    if (!key) {
      return;
    }
    node.setAttribute(
      "placeholder",
      tMaybe(key, node.getAttribute("placeholder") || ""),
    );
  });
  document.querySelectorAll("[data-i18n-aria-label]").forEach((node) => {
    const key = `${node.dataset.i18nAriaLabel || ""}`.trim();
    if (!key) {
      return;
    }
    node.setAttribute(
      "aria-label",
      tMaybe(key, node.getAttribute("aria-label") || ""),
    );
  });
}

function rerenderForLocale() {
  if (tokens?.idToken && currentUser?.email) {
    setSignedInState(currentUser);
  } else {
    setSignedOutState();
  }

  if (state.overview) {
    renderOverview(state.overview);
  } else {
    elements.generatedAt.textContent = t("generated.unavailable");
  }

  renderAdminUsers(state.adminUsers);
  renderInspector();
  renderFeedbackTable(state.feedbackList);
  renderFeedbackInspector();
  renderWelcomeBanner(currentUser);
  renderLivePresence();
  renderAiPromptLimitSettings();
  renderProducerCaptureWhitelistSettings();
  renderAiRuntimeSettings();
  renderBillingCatalogSettings();
  renderBillingOrganizations();
  renderBillingMemberships();
  renderBillingWorkspaces();
  renderBillingCloudProjects();
  renderUserSearchMeta(state.lastUserSearchPayload || {});
  updateTabView();
}

function buildLoadedTabs() {
  return {
    home: false,
    users: false,
    feedback: false,
    dev: false,
  };
}

function getOverviewSectionIncludes(overview = state.overview) {
  const includes = overview?.section_includes || {};
  return {
    aiUsage: state.overviewIncludes.aiUsage || includes.ai_usage === true,
    productAnalytics: state.overviewIncludes.productAnalytics || includes.product_analytics === true,
    aiObservability: state.overviewIncludes.aiObservability || includes.ai_observability === true,
    users: state.overviewIncludes.users || includes.users === true,
    projects: state.overviewIncludes.projects || includes.projects === true,
  };
}

function syncOverviewIncludesFromPayload(overview) {
  state.overviewIncludes = getOverviewSectionIncludes(overview);
}

function buildOverviewParams(includeOverrides = {}) {
  const includes = {
    ...buildOverviewIncludes(),
    ...state.overviewIncludes,
    ...includeOverrides,
  };
  return new URLSearchParams({
    user_limit: `${state.overviewUserLimit}`,
    project_limit: `${state.overviewProjectLimit}`,
    trace_limit: `${state.overviewTraceLimit}`,
    tool_usage_range: `${state.aiToolUsageRange}`,
    include_ai_usage: `${includes.aiUsage}`,
    include_product_analytics: `${includes.productAnalytics}`,
    include_ai_observability: `${includes.aiObservability}`,
    include_users: `${includes.users}`,
    include_projects: `${includes.projects}`,
  });
}

function mergeOverviewPayload(currentOverview, nextOverview) {
  const current = currentOverview || {};
  const next = nextOverview || {};
  const nextRawIncludes = next.section_includes || {};
  const includes = {
    ...getOverviewSectionIncludes(current),
    ...getOverviewSectionIncludes(next),
  };
  const mergedSummary = {
    ...(current.summary || {}),
  };
  Object.entries(next.summary || {}).forEach(([key, value]) => {
    if (value !== null && value !== undefined) {
      mergedSummary[key] = value;
    }
  });
  return {
    ...current,
    ...next,
    summary: mergedSummary,
    section_includes: {
      ai_usage: includes.aiUsage,
      product_analytics: includes.productAnalytics,
      ai_observability: includes.aiObservability,
      users: includes.users,
      projects: includes.projects,
    },
    data_sources: {
      ...(current.data_sources || {}),
      ...(next.data_sources || {}),
    },
    warnings: Array.isArray(next.warnings) ? next.warnings : (current.warnings || []),
    subscription_tiers: Array.isArray(next.subscription_tiers)
      ? next.subscription_tiers
      : (current.subscription_tiers || []),
    ai_usage: nextRawIncludes.ai_usage === true
      ? (next.ai_usage || current.ai_usage || {})
      : (current.ai_usage || next.ai_usage || {}),
    ai_observability: nextRawIncludes.ai_observability === true
      ? (next.ai_observability || current.ai_observability || {})
      : (current.ai_observability || next.ai_observability || {}),
    product_analytics: nextRawIncludes.product_analytics === true
      ? (next.product_analytics || current.product_analytics || {})
      : (current.product_analytics || next.product_analytics || {}),
    users: nextRawIncludes.users === true
      ? (Array.isArray(next.users) ? next.users : (current.users || []))
      : (current.users || next.users || []),
    projects: nextRawIncludes.projects === true
      ? (Array.isArray(next.projects) ? next.projects : (current.projects || []))
      : (current.projects || next.projects || []),
  };
}

function setHomeSectionLoading(keys, loading, message = "") {
  keys.forEach((key) => {
    state.homeSectionLoading[key] = loading;
    const panel = elements.homeSectionPanels[key];
    const overlay = elements.homeSectionLoadingStates[key];
    const label = elements.homeSectionLoadingLabels[key];
    if (panel) {
      panel.classList.toggle("is-section-loading", loading);
      panel.setAttribute("aria-busy", loading ? "true" : "false");
    }
    if (overlay) {
      overlay.classList.toggle("hidden", !loading);
    }
    if (label && message) {
      label.textContent = message;
    }
  });
}

function handleTabClick(event) {
  const button = event.currentTarget;
  const tab = `${button?.dataset?.tabButton || ""}`.trim();
  if (!tab || tab === state.activeTab) {
    return;
  }
  setActiveTab(tab, { load: true });
}

function handleAnalyticsRangeClick(event) {
  const button = event.target.closest("[data-analytics-range]");
  if (!button || !state.overview?.product_analytics) {
    return;
  }
  const nextRange = `${button.dataset.analyticsRange || ""}`.trim();
  if (!ANALYTICS_RANGE_OPTIONS.some((option) => option.key === nextRange)) {
    return;
  }
  if (nextRange === state.analyticsRange) {
    return;
  }
  state.analyticsRange = nextRange;
  renderProductAnalytics(state.overview.product_analytics || {});
}

function handleAiToolUsageRangeClick(event) {
  const button = event.target.closest("[data-ai-tool-usage-range]");
  if (!button || state.overviewBusy) {
    return;
  }
  const nextRange = `${button.dataset.aiToolUsageRange || ""}`.trim();
  if (!AI_TOOL_USAGE_RANGE_OPTIONS.some((option) => option.key === nextRange)) {
    return;
  }
  if (nextRange === state.aiToolUsageRange) {
    return;
  }
  state.aiToolUsageRange = nextRange;
  void refreshOverviewSections({
    include_ai_usage: true,
    loadingKeys: ["usage"],
    statusMessage: t("status.loadingAdminOverview"),
  });
}

function updateTabView() {
  elements.tabButtons.forEach((button) => {
    const tab = `${button.dataset.tabButton || ""}`.trim();
    const active = tab === state.activeTab;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-selected", active ? "true" : "false");
  });
  elements.tabPanels.forEach((panel) => {
    const tab = `${panel.dataset.tabPanel || ""}`.trim();
    panel.classList.toggle("hidden", tab !== state.activeTab);
  });
}

function setTabLoading(tab, loading, message = "") {
  const panel = elements.tabLoadingStates[tab];
  const label = elements.tabLoadingLabels[tab];
  const tabPanel = elements.tabPanels.find((node) => `${node.dataset.tabPanel || ""}`.trim() === tab);
  if (!panel || !tabPanel) {
    return;
  }
  panel.classList.toggle("hidden", !loading);
  tabPanel.classList.toggle("is-loading", loading);
  tabPanel.setAttribute("aria-busy", loading ? "true" : "false");
  if (label && message) {
    label.textContent = message;
  }
}

function clearTabLoading(tab) {
  setTabLoading(tab, false);
}

async function setActiveTab(tab, { load = false, force = false } = {}) {
  if (!TAB_KEYS.includes(tab)) {
    return;
  }
  state.activeTab = tab;
  updateTabView();
  if (load && tokens?.idToken) {
    await loadActiveTabData({ silent: false, force });
  }
}

function handleUserActivity() {
  if (!tokens?.idToken) {
    return;
  }
  if (!ensureActiveSession()) {
    return;
  }
  touchSessionActivity();
}

function handleSessionCheckpoint() {
  if (!tokens?.idToken) {
    return;
  }
  ensureActiveSession();
}

function t(key, vars = {}) {
  const dictionary = MESSAGES[state.locale] || MESSAGES[DEFAULT_LOCALE];
  const fallbackDictionary = MESSAGES[DEFAULT_LOCALE];
  let template = dictionary[key] || fallbackDictionary[key] || key;
  for (const [name, value] of Object.entries(vars)) {
    template = template.replaceAll(`{${name}}`, `${value ?? ""}`);
  }
  return template;
}

function getAnalyticsRangeOption(rangeKey) {
  return ANALYTICS_RANGE_OPTIONS.find((option) => option.key === rangeKey)
    || ANALYTICS_RANGE_OPTIONS[2];
}

function tMaybe(key, fallback, vars = {}) {
  const dictionary = MESSAGES[state.locale] || MESSAGES[DEFAULT_LOCALE];
  const fallbackDictionary = MESSAGES[DEFAULT_LOCALE];
  if (!dictionary[key] && !fallbackDictionary[key]) {
    return fallback;
  }
  return t(key, vars);
}

function getWelcomeName(email) {
  const normalized = normalizeEmail(email);
  if (!normalized || !normalized.includes("@")) {
    return t("welcome.fallbackName");
  }
  const localPart = normalized.split("@")[0] || "";
  const firstToken = localPart.split(/[._+-]+/).find(Boolean) || localPart;
  if (!firstToken) {
    return t("welcome.fallbackName");
  }
  return firstToken.charAt(0).toUpperCase() + firstToken.slice(1);
}

function renderWelcomeBanner(user) {
  const email = user?.email || state.overview?.requested_email || "";
  elements.welcomeName.textContent = getWelcomeName(email);
}

function renderLivePresence(presence = state.livePresence) {
  if (!elements.livePresenceBadge || !elements.livePresenceLabel || !elements.livePresenceValue) {
    return;
  }

  elements.livePresenceLabel.textContent = t("presence.liveNow");
  if (!presence) {
    elements.livePresenceBadge.classList.add("hidden");
    elements.livePresenceBadge.classList.remove("is-idle");
    return;
  }

  const count = Number(presence.active_users || 0);
  const minutes = Number(presence.window_minutes || 5);
  const isLive = presence.status === "live";
  const hasUsers = isLive && count > 0;
  elements.livePresenceBadge.classList.remove("hidden");
  elements.livePresenceBadge.classList.toggle("is-idle", !hasUsers);
  if (!isLive) {
    elements.livePresenceValue.textContent = t("presence.offline");
    return;
  }
  elements.livePresenceValue.textContent = hasUsers
    ? t(count === 1 ? "presence.userCountOne" : "presence.userCount", {
      count: formatWholeNumber(count),
    })
    : t("presence.idle", { minutes: formatWholeNumber(minutes) });
}

async function loadLivePresence({ silent = true } = {}) {
  if (!tokens?.idToken) {
    return;
  }

  const requestId = ++state.livePresenceRequestId;
  try {
    const payload = await fetchAdminJson(LIVE_PRESENCE_PATH);
    if (requestId !== state.livePresenceRequestId) {
      return;
    }
    state.livePresence = payload;
    renderLivePresence();
  } catch (error) {
    if (requestId !== state.livePresenceRequestId) {
      return;
    }
    state.livePresence = {
      status: "error",
      active_users: 0,
      window_minutes: 5,
    };
    renderLivePresence();
    if (!silent) {
      handleAdminRequestError(error, t("status.loadAdminOverviewFailed"));
    }
  }
}

function startLivePresencePolling() {
  if (livePresenceTimer) {
    window.clearInterval(livePresenceTimer);
    livePresenceTimer = null;
  }
  if (!tokens?.idToken) {
    return;
  }
  void loadLivePresence({ silent: true });
  livePresenceTimer = window.setInterval(() => {
    void loadLivePresence({ silent: true });
  }, LIVE_PRESENCE_POLL_MS);
}

function animateWelcomeBanner({ force = false } = {}) {
  const banner = elements.welcomeBanner;
  if (!banner || (!force && welcomeAnimationPlayed)) {
    return;
  }

  const nameNode = elements.welcomeName;
  const topbarNode = banner.querySelector(".welcome-topbar");
  const scanNode = banner.querySelector(".welcome-scan");
  const gsapApi = window.gsap;

  if (gsapApi && typeof gsapApi.timeline === "function") {
    gsapApi.set([topbarNode, nameNode], { opacity: 0, y: 14 });
    gsapApi.set(scanNode, { xPercent: -120, opacity: 0.9 });
    gsapApi.set(".welcome-grid", { backgroundPosition: "0px 0px" });
    const timeline = gsapApi.timeline({ defaults: { ease: "power3.out" } });
    timeline
      .fromTo(
        banner,
        { opacity: 0, y: 18, scale: 0.985 },
        { opacity: 1, y: 0, scale: 1, duration: 0.58 },
      )
      .to(topbarNode, { opacity: 1, y: 0, duration: 0.36 }, "-=0.22")
      .to(nameNode, { opacity: 1, y: 0, duration: 0.42 }, "-=0.16")
      .to(scanNode, { xPercent: 120, duration: 1.25, ease: "power2.out" }, 0.1)
      .to(scanNode, { opacity: 0, duration: 0.2 }, "-=0.18")
      .to(".welcome-grid", { backgroundPosition: "14px 8px", duration: 2.2, ease: "sine.out" }, 0);
  } else {
    banner.style.opacity = "1";
  }

  welcomeAnimationPlayed = true;
}

function canEditAiSettings() {
  return state.overview?.permissions?.can_edit_ai_settings === true;
}

function normalizeEmail(value) {
  return `${value || ""}`.trim().toLowerCase();
}

function isAndrewAdmin() {
  const email = normalizeEmail(currentUser?.email || state.overview?.requested_email || "");
  return email === ANDREW_ADMIN_EMAIL;
}

function canViewAiRuntimeSettings() {
  return canEditAiSettings() && isAndrewAdmin();
}

function canEditProducerCaptureWhitelist() {
  return !!tokens?.idToken;
}

function canEditBillingCatalog() {
  return canViewAiRuntimeSettings() && state.billingCatalogConfigurable !== false;
}

function canEditBillingControlPlane() {
  return canViewAiRuntimeSettings() && state.collaborationConfigurable !== false;
}

function canGrantAiPrompts() {
  return state.overview?.permissions?.can_grant_ai_prompts === true;
}

function canApplyEntitlementOverrides() {
  return canViewAiRuntimeSettings();
}

async function bootstrap() {
  if (!isConfigured()) {
    setSignedOutState();
    setStatus(t("status.configIncomplete"), "error");
    return;
  }

  configureAnalyticsCallout();

  try {
    await maybeHandleHostedUiRedirect();
    if (tokens && !ensureActiveSession()) {
      return;
    }
    await ensureFreshTokens();
    currentUser = decodeIdToken(tokens?.idToken);
    if (!currentUser?.email) {
      setSignedOutState();
      setStatus(t("status.signInToContinue"), "info");
      return;
    }
    setSignedInState(currentUser);
    await refreshDashboard();
  } catch (error) {
    setSignedOutState();
    setStatus(error.message || t("status.initializeFailed"), "error");
  }
}

function isConfigured() {
  return (
    typeof config.apiBaseUrl === "string" &&
    config.apiBaseUrl.includes("http") &&
    typeof config.cognitoDomainUrl === "string" &&
    config.cognitoDomainUrl.includes("http") &&
    typeof config.cognitoClientId === "string" &&
    config.cognitoClientId &&
    typeof config.redirectUri === "string" &&
    config.redirectUri &&
    typeof config.logoutUri === "string" &&
    config.logoutUri
  );
}

function configureAnalyticsCallout() {
  const posthogUrl = `${config.posthogDashboardUrl || ""}`.trim();
  const hasDashboardUrl = posthogUrl && posthogUrl.includes("http");

  if (!hasDashboardUrl) {
    elements.analyticsCallout.classList.add("hidden");
    elements.posthogLink.removeAttribute("href");
  } else {
    elements.analyticsCallout.classList.remove("hidden");
    elements.posthogLink.href = posthogUrl;
  }
}

async function maybeHandleHostedUiRedirect() {
  const url = new URL(window.location.href);
  const code = url.searchParams.get("code");
  const stateParam = url.searchParams.get("state");
  const error = url.searchParams.get("error");
  const errorDescription = url.searchParams.get("error_description");

  if (error) {
    clearPkceArtifacts();
    throw new Error(errorDescription || error);
  }

  if (!code) {
    return;
  }

  const expectedState = sessionStorage.getItem(PKCE_STATE_KEY);
  const verifier = sessionStorage.getItem(PKCE_VERIFIER_KEY);
  if (!stateParam || !expectedState || stateParam !== expectedState || !verifier) {
    clearPkceArtifacts();
    throw new Error(t("status.hostedStateFailed"));
  }

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: config.cognitoClientId,
    code,
    redirect_uri: config.redirectUri,
    code_verifier: verifier,
  });
  const response = await fetch(buildCognitoUrl("/oauth2/token"), {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });

  const payload = await response.json().catch(() => ({}));
  clearPkceArtifacts();
  url.searchParams.delete("code");
  url.searchParams.delete("state");
  window.history.replaceState({}, document.title, url.toString());

  if (!response.ok) {
    const message = payload.error_description || payload.error || t("status.hostedSignInFailed");
    throw new Error(message);
  }

  storeTokens(payload);
}

async function ensureFreshTokens() {
  if (!tokens) {
    return;
  }

  if (!ensureActiveSession()) {
    return;
  }

  const now = Math.floor(Date.now() / 1000);
  if (tokens.expiresAt && tokens.expiresAt - 60 > now) {
    return;
  }

  if (!tokens.refreshToken) {
    clearTokens();
    return;
  }

  const body = new URLSearchParams({
    grant_type: "refresh_token",
    client_id: config.cognitoClientId,
    refresh_token: tokens.refreshToken,
  });
  const response = await fetch(buildCognitoUrl("/oauth2/token"), {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    clearTokens();
    throw new Error(payload.error_description || payload.error || t("status.sessionRefreshFailed"));
  }

  storeTokens({
    ...payload,
    refresh_token: tokens.refreshToken,
  });
}

async function beginSignIn() {
  if (!isConfigured()) {
    setStatus(t("status.signInConfigIncomplete"), "error");
    return;
  }

  const verifier = generateRandomString(64);
  const stateParam = generateRandomString(32);
  const challenge = await createPkceChallenge(verifier);
  sessionStorage.setItem(PKCE_VERIFIER_KEY, verifier);
  sessionStorage.setItem(PKCE_STATE_KEY, stateParam);

  const authorizeUrl = new URL(buildCognitoUrl("/oauth2/authorize"));
  authorizeUrl.searchParams.set("response_type", "code");
  authorizeUrl.searchParams.set("client_id", config.cognitoClientId);
  authorizeUrl.searchParams.set("redirect_uri", config.redirectUri);
  authorizeUrl.searchParams.set("scope", (config.scopes || ["openid", "email"]).join(" "));
  authorizeUrl.searchParams.set("state", stateParam);
  authorizeUrl.searchParams.set("code_challenge_method", "S256");
  authorizeUrl.searchParams.set("code_challenge", challenge);
  window.location.assign(authorizeUrl.toString());
}

async function signOut() {
  clearTokens();
  resetAdminState();
  setSignedOutState();
  setStatus(t("status.signedOut"), "info");
  if (!isConfigured()) {
    return;
  }
  const logoutUrl = new URL(buildCognitoUrl("/logout"));
  logoutUrl.searchParams.set("client_id", config.cognitoClientId);
  logoutUrl.searchParams.set("logout_uri", config.logoutUri);
  window.location.assign(logoutUrl.toString());
}

async function refreshDashboard() {
  await refreshOverview();
  state.loadedTabs.home = true;
  await loadActiveTabData({ silent: true, force: true });
}

async function loadActiveTabData({ silent = false, force = false } = {}) {
  if (!tokens?.idToken) {
    return;
  }
  if (state.activeTab === "users") {
    await loadUsersTabData({ silent, force });
    return;
  }
  if (state.activeTab === "feedback") {
    await loadFeedbackTabData({ silent, force });
    return;
  }
  if (state.activeTab === "dev") {
    await loadDevTabData({ silent, force });
    return;
  }
  state.loadedTabs.home = true;
}

async function loadUsersTabData({ silent = false, force = false } = {}) {
  if (force || !state.loadedTabs.users) {
    setTabLoading(
      "users",
      true,
      state.currentSearchQuery ? t("status.searchingUsers") : t("status.loadingRecentUsers"),
    );
    try {
      await searchUsers({ query: state.currentSearchQuery, silent, autoSelect: true });
      state.loadedTabs.users = true;
    } finally {
      clearTabLoading("users");
    }
  }
}

async function loadFeedbackTabData({ silent = false, force = false } = {}) {
  if (force || !state.loadedTabs.feedback) {
    setTabLoading("feedback", true, t("status.loadingFeedback"));
    try {
      await loadFeedback({ silent, autoSelect: true });
      state.loadedTabs.feedback = true;
    } finally {
      clearTabLoading("feedback");
    }
  }
}

async function loadDevTabData({ silent = false, force = false } = {}) {
  const requests = [];
  if (force || !state.loadedTabs.dev || !state.aiPromptLimits) {
    requests.push(loadAiPromptLimitSettings({ silent }));
  }
  if (force || !state.loadedTabs.dev || !state.producerCaptureWhitelist) {
    requests.push(loadProducerCaptureWhitelistSettings({ silent }));
  }
  if (canViewAiRuntimeSettings() && (force || !state.loadedTabs.dev || !state.aiRuntimeSettings)) {
    requests.push(loadAiRuntimeSettings({ silent }));
  } else if (!canViewAiRuntimeSettings()) {
    state.aiRuntimeSettings = null;
    renderAiRuntimeSettings();
  }
  if (force || !state.loadedTabs.dev || !state.billingCatalog) {
    requests.push(loadBillingCatalogSettings({ silent }));
  }
  if (force || !state.loadedTabs.dev || !state.billingOrganizationsLoaded) {
    requests.push(loadBillingOrganizations({ silent }));
  }
  if (force || !state.loadedTabs.dev || !state.billingMembershipsLoaded) {
    requests.push(loadBillingMemberships({ silent }));
  }
  if (force || !state.loadedTabs.dev || !state.billingWorkspacesLoaded) {
    requests.push(loadBillingWorkspaces({ silent }));
  }
  if (force || !state.loadedTabs.dev || !state.billingCloudProjectsLoaded) {
    requests.push(loadBillingCloudProjects({ silent }));
  }
  if (!requests.length) {
    state.loadedTabs.dev = true;
    return;
  }
  setTabLoading("dev", true, tMaybe("status.loadingBillingControlPlane", "Loading dev settings..."));
  try {
    await Promise.all(requests);
    state.loadedTabs.dev = true;
  } finally {
    clearTabLoading("dev");
  }
}

async function refreshOverview() {
  if (!tokens?.idToken) {
    setSignedOutState();
    setStatus(t("status.signInToContinue"), "info");
    return;
  }

  const requestId = ++state.overviewRequestId;
  state.overviewBusy = true;
  updateBusyState();
  setStatus(t("status.loadingAdminOverview"), "info");
  setHomeSectionLoading(
    ["usage"],
    true,
    t("overview.loadingSection"),
  );
  setHomeSectionLoading(
    ["analytics"],
    true,
    t("overview.loadingSection"),
  );
  try {
    currentUser = decodeIdToken(tokens?.idToken);
    if (!currentUser?.email) {
      clearTokens();
      throw new Error(t("status.sessionMissingEmail"));
    }

    state.overviewIncludes = {
      ...buildOverviewIncludes(),
      aiUsage: true,
    };
    const params = buildOverviewParams({
      aiUsage: true,
      productAnalytics: false,
    });
    const payload = await fetchAdminJson(`${OVERVIEW_PATH}?${params.toString()}`);
    if (requestId !== state.overviewRequestId) {
      return;
    }
    state.overview = mergeOverviewPayload(state.overview, payload);
    syncOverviewIncludesFromPayload(state.overview);
    setSignedInState(currentUser);
    renderOverview(state.overview);
    setHomeSectionLoading(["usage"], false);
    state.loadedTabs.home = true;
    setStatus(t("status.adminOverviewLoaded"), "success");

    state.overviewBusy = false;
    updateBusyState();
    void refreshOverviewSections({
      requestId,
      include_product_analytics: true,
      loadingKeys: ["analytics"],
      statusMessage: "",
    });
  } catch (error) {
    setHomeSectionLoading(["usage", "analytics"], false);
    handleAdminRequestError(error, t("status.loadAdminOverviewFailed"));
  } finally {
    if (requestId === state.overviewRequestId && state.overviewBusy) {
      state.overviewBusy = false;
      updateBusyState();
    }
  }
}

async function refreshOverviewSections({
  requestId = state.overviewRequestId,
  include_ai_usage = false,
  include_product_analytics = false,
  include_ai_observability = false,
  include_users = false,
  include_projects = false,
  loadingKeys = [],
  statusMessage = "",
} = {}) {
  if (!tokens?.idToken) {
    return null;
  }

  const includeOverrides = {
    aiUsage: include_ai_usage,
    productAnalytics: include_product_analytics,
    aiObservability: include_ai_observability,
    users: include_users,
    projects: include_projects,
  };
  setHomeSectionLoading(loadingKeys, true, t("overview.loadingSection"));
  if (statusMessage) {
    setStatus(statusMessage, "info");
  }
  try {
    const payload = await fetchAdminJson(`${OVERVIEW_PATH}?${buildOverviewParams(includeOverrides).toString()}`);
    if (requestId !== state.overviewRequestId) {
      return null;
    }
    state.overview = mergeOverviewPayload(state.overview, payload);
    syncOverviewIncludesFromPayload(state.overview);
    renderOverview(state.overview);
    return payload;
  } catch (error) {
    if (requestId === state.overviewRequestId) {
      handleAdminRequestError(error, t("status.loadAdminOverviewFailed"));
    }
    return null;
  } finally {
    if (requestId === state.overviewRequestId) {
      setHomeSectionLoading(loadingKeys, false);
      updateBusyState();
    }
  }
}

async function searchUsers({
  query = state.currentSearchQuery,
  silent = false,
  autoSelect = true,
} = {}) {
  if (!tokens?.idToken) {
    return;
  }

  const requestId = ++state.searchRequestId;
  state.userSearchBusy = true;
  state.currentSearchQuery = `${query || ""}`.trim();
  updateBusyState();
  if (!silent) {
    setStatus(
      state.currentSearchQuery ? t("status.searchingUsers") : t("status.loadingRecentUsers"),
      "info",
    );
  }

  try {
    const params = new URLSearchParams({
      limit: `${state.userSearchLimit}`,
    });
    if (state.currentSearchQuery) {
      params.set("query", state.currentSearchQuery);
    }
    const payload = await fetchAdminJson(`${ADMIN_USERS_PATH}?${params.toString()}`);
    if (requestId !== state.searchRequestId) {
      return;
    }

    state.lastUserSearchPayload = payload;
    state.adminUsers = Array.isArray(payload.users) ? payload.users : [];
    syncSelectedUser(autoSelect);
    renderAdminUsers(state.adminUsers);
    renderInspector();
    renderUserSearchMeta(payload);

    if (!silent) {
      const count = Number(payload.total_matches || state.adminUsers.length || 0);
      const message = count
        ? t(count === 1 ? "value.userLoaded" : "value.usersLoaded", {
            count: formatWholeNumber(count),
          })
        : t("status.noUsersFound");
      setStatus(message, count ? "success" : "info");
    }
  } catch (error) {
    if (requestId !== state.searchRequestId) {
      return;
    }
    handleAdminRequestError(error, t("status.searchUsersFailed"));
  } finally {
    if (requestId === state.searchRequestId) {
      state.userSearchBusy = false;
      updateBusyState();
    }
  }
}

async function loadFeedback({
  silent = false,
  autoSelect = true,
} = {}) {
  if (!tokens?.idToken) {
    return;
  }

  const requestId = ++state.feedbackRequestId;
  state.feedbackBusy = true;
  updateBusyState();
  if (!silent) {
    setStatus(t("status.loadingFeedback"), "info");
  }

  try {
    const payload = await fetchAdminJson(
      `${ADMIN_FEEDBACK_PATH}?limit=${encodeURIComponent(`${state.feedbackLimit}`)}`,
    );
    if (requestId !== state.feedbackRequestId) {
      return;
    }
    state.lastFeedbackPayload = payload;
    state.feedbackList = Array.isArray(payload.submissions) ? payload.submissions : [];
    syncSelectedFeedback(autoSelect);
    renderFeedbackTable(state.feedbackList);
    await loadSelectedFeedbackDetail({ silent: true });
  } catch (error) {
    if (requestId !== state.feedbackRequestId) {
      return;
    }
    handleAdminRequestError(error, t("status.loadFeedbackFailed"));
  } finally {
    if (requestId === state.feedbackRequestId) {
      state.feedbackBusy = false;
      updateBusyState();
    }
  }
}

async function loadAiPromptLimitSettings({ silent = false } = {}) {
  if (!tokens?.idToken) {
    return;
  }

  state.aiPromptLimitsBusy = true;
  updateBusyState();
  if (!silent) {
    setStatus(t("status.loadingAiPromptLimits"), "info");
  }

  try {
    const payload = await fetchAdminJson(ADMIN_AI_PROMPT_LIMITS_PATH);
    state.aiPromptLimits = payload.settings || null;
    renderAiPromptLimitSettings();
    if (!silent) {
      setStatus(t("status.aiPromptLimitsLoaded"), "success");
    }
  } catch (error) {
    handleAdminRequestError(error, t("status.loadAiPromptLimitsFailed"));
  } finally {
    state.aiPromptLimitsBusy = false;
    updateBusyState();
  }
}

async function loadAiRuntimeSettings({ silent = false } = {}) {
  if (!tokens?.idToken) {
    return;
  }

  state.aiRuntimeBusy = true;
  updateBusyState();
  if (!silent) {
    setStatus(t("status.loadingAiRuntime"), "info");
  }

  try {
    const payload = await fetchAdminJson(ADMIN_AI_RUNTIME_PATH);
    state.aiRuntimeSettings = payload.settings || null;
    renderAiRuntimeSettings();
    if (!silent) {
      setStatus(t("status.aiRuntimeLoaded"), "success");
    }
  } catch (error) {
    handleAdminRequestError(error, t("status.loadAiRuntimeFailed"));
  } finally {
    state.aiRuntimeBusy = false;
    updateBusyState();
  }
}

async function loadProducerCaptureWhitelistSettings({ silent = false } = {}) {
  if (!tokens?.idToken) {
    return;
  }

  state.producerCaptureWhitelistBusy = true;
  updateBusyState();
  if (!silent) {
    setStatus(t("status.loadingProducerCaptureWhitelist"), "info");
  }

  try {
    const payload = await fetchAdminJson(ADMIN_PRODUCER_CAPTURE_WHITELIST_PATH);
    state.producerCaptureWhitelist = payload.settings || null;
    renderProducerCaptureWhitelistSettings();
    if (!silent) {
      setStatus(t("status.producerCaptureWhitelistLoaded"), "success");
    }
  } catch (error) {
    handleAdminRequestError(error, t("status.loadProducerCaptureWhitelistFailed"));
  } finally {
    state.producerCaptureWhitelistBusy = false;
    updateBusyState();
  }
}

async function loadBillingCatalogSettings({ silent = false } = {}) {
  if (!tokens?.idToken) {
    return;
  }

  state.billingCatalogBusy = true;
  updateBusyState();
  if (!silent) {
    setStatus(
      tMaybe("status.loadingBillingCatalog", "Loading billing catalog settings..."),
      "info",
    );
  }

  try {
    const payload = await fetchAdminJson(ADMIN_BILLING_CATALOG_PATH);
    state.billingCatalog = payload || null;
    state.billingCatalogConfigurable = payload?.configurable !== false;
    renderBillingCatalogSettings();
    if (!silent) {
      setStatus(
        tMaybe("status.billingCatalogLoaded", "Billing catalog settings loaded."),
        "success",
      );
    }
  } catch (error) {
    handleAdminRequestError(
      error,
      tMaybe("status.loadBillingCatalogFailed", "Could not load billing catalog settings."),
    );
  } finally {
    state.billingCatalogBusy = false;
    updateBusyState();
  }
}

async function loadBillingOrganizations({ silent = false } = {}) {
  if (!tokens?.idToken) {
    return;
  }

  state.billingOrganizationsBusy = true;
  updateBusyState();
  if (!silent) {
    setStatus(
      tMaybe("status.loadingBillingOrganizations", "Loading billing organizations..."),
      "info",
    );
  }

  try {
    const payload = await fetchAdminJson(ADMIN_BILLING_ORGANIZATIONS_PATH);
    state.billingOrganizations = Array.isArray(payload.organizations) ? payload.organizations : [];
    state.billingOrganizationsLoaded = true;
    state.collaborationConfigurable = payload?.configurable !== false;
    syncSelectedBillingOrganization();
    renderBillingOrganizations();
    if (!silent) {
      setStatus(
        tMaybe("status.billingOrganizationsLoaded", "Billing organizations loaded."),
        "success",
      );
    }
  } catch (error) {
    handleAdminRequestError(
      error,
      tMaybe("status.loadBillingOrganizationsFailed", "Could not load billing organizations."),
    );
  } finally {
    state.billingOrganizationsBusy = false;
    updateBusyState();
  }
}

async function loadBillingMemberships({ silent = false } = {}) {
  if (!tokens?.idToken) {
    return;
  }

  state.billingMembershipsBusy = true;
  updateBusyState();
  if (!silent) {
    setStatus(
      tMaybe("status.loadingBillingMemberships", "Loading billing memberships..."),
      "info",
    );
  }

  try {
    const payload = await fetchAdminJson(ADMIN_BILLING_MEMBERSHIPS_PATH);
    state.billingMemberships = Array.isArray(payload.memberships) ? payload.memberships : [];
    state.billingMembershipsLoaded = true;
    state.collaborationConfigurable = payload?.configurable !== false;
    syncSelectedBillingMembership();
    renderBillingMemberships();
    if (!silent) {
      setStatus(
        tMaybe("status.billingMembershipsLoaded", "Billing memberships loaded."),
        "success",
      );
    }
  } catch (error) {
    handleAdminRequestError(
      error,
      tMaybe("status.loadBillingMembershipsFailed", "Could not load billing memberships."),
    );
  } finally {
    state.billingMembershipsBusy = false;
    updateBusyState();
  }
}

async function loadBillingWorkspaces({ silent = false } = {}) {
  if (!tokens?.idToken) {
    return;
  }

  state.billingWorkspacesBusy = true;
  updateBusyState();
  if (!silent) {
    setStatus(
      tMaybe("status.loadingBillingWorkspaces", "Loading billing workspaces..."),
      "info",
    );
  }

  try {
    const payload = await fetchAdminJson(ADMIN_BILLING_WORKSPACES_PATH);
    state.billingWorkspaces = Array.isArray(payload.workspaces) ? payload.workspaces : [];
    state.billingWorkspacesLoaded = true;
    state.collaborationConfigurable = payload?.configurable !== false;
    syncSelectedBillingWorkspace();
    renderBillingWorkspaces();
    if (!silent) {
      setStatus(
        tMaybe("status.billingWorkspacesLoaded", "Billing workspaces loaded."),
        "success",
      );
    }
  } catch (error) {
    handleAdminRequestError(
      error,
      tMaybe("status.loadBillingWorkspacesFailed", "Could not load billing workspaces."),
    );
  } finally {
    state.billingWorkspacesBusy = false;
    updateBusyState();
  }
}

async function loadBillingCloudProjects({ silent = false } = {}) {
  if (!tokens?.idToken) {
    return;
  }

  state.billingCloudProjectsBusy = true;
  updateBusyState();
  if (!silent) {
    setStatus(
      tMaybe("status.loadingBillingCloudProjects", "Loading billing cloud projects..."),
      "info",
    );
  }

  try {
    const payload = await fetchAdminJson(ADMIN_BILLING_CLOUD_PROJECTS_PATH);
    state.billingCloudProjects = Array.isArray(payload.cloud_projects) ? payload.cloud_projects : [];
    state.billingCloudProjectsLoaded = true;
    state.collaborationConfigurable = payload?.configurable !== false;
    syncSelectedBillingCloudProject();
    renderBillingCloudProjects();
    if (!silent) {
      setStatus(
        tMaybe("status.billingCloudProjectsLoaded", "Billing cloud projects loaded."),
        "success",
      );
    }
  } catch (error) {
    handleAdminRequestError(
      error,
      tMaybe("status.loadBillingCloudProjectsFailed", "Could not load billing cloud projects."),
    );
  } finally {
    state.billingCloudProjectsBusy = false;
    updateBusyState();
  }
}

async function loadSelectedFeedbackDetail({ silent = false } = {}) {
  if (!state.selectedFeedbackId) {
    state.selectedFeedback = null;
    renderFeedbackInspector();
    return;
  }

  renderFeedbackInspector({ loading: true });
  try {
    const payload = await fetchAdminJson(
      `${ADMIN_FEEDBACK_PATH}?submission_id=${encodeURIComponent(state.selectedFeedbackId)}`,
    );
    if (payload.submission_id !== state.selectedFeedbackId) {
      return;
    }
    state.selectedFeedback = payload;
    renderFeedbackInspector();
  } catch (error) {
    state.selectedFeedback = null;
    renderFeedbackInspector();
    if (!silent) {
      handleAdminRequestError(error, t("status.loadFeedbackFailed"));
    }
  }
}

function renderOverview(overview) {
  syncOverviewIncludesFromPayload(overview);
  renderSummary(overview.summary || {});
  renderProductAnalytics(overview.product_analytics || {});
  renderUsage(overview);
  renderTiers(overview.subscription_tiers || []);

  const warnings = Array.isArray(overview.warnings) ? overview.warnings : [];
  const generatedAt = overview.generated_at
    ? t("generated.at", { date: formatDate(overview.generated_at) })
    : t("generated.unavailable");
  elements.generatedAt.textContent = warnings.length
    ? `${generatedAt} • ${warnings.join(" • ")}`
    : generatedAt;
  if (overview.requested_email) {
    elements.identityMeta.textContent = t("identity.signedInAs", {
      email: overview.requested_email,
    });
  }
  renderWelcomeBanner({ email: overview.requested_email || currentUser?.email || "" });
}

function formatOverviewMetricValue(value, formatter = formatNumber) {
  if (value == null) {
    return t("overview.loading");
  }
  return formatter(value);
}

function renderAiPromptLimitSettings() {
  const settings = state.aiPromptLimits;
  const canEdit = canViewAiRuntimeSettings();
  if (!settings) {
    elements.aiPromptLimitsMeta.textContent = t("panel.aiPromptLimits.meta");
    elements.aiPromptLimitsSummary.innerHTML = `
      <div class="detail-label">${escapeHtml(t("settings.currentLimits"))}</div>
      <div class="detail-value">${escapeHtml(t("empty.signInAiPromptLimits"))}</div>
    `;
    elements.freeDailyPromptLimitInput.value = "";
    elements.freeWeeklyPromptLimitInput.value = "";
    elements.aiPromptLimitsConfirmInput.value = "";
    elements.aiPromptLimitsForm.classList.add("hidden");
    elements.aiPromptLimitsEditorNote.classList.add("hidden");
    elements.aiPromptLimitsConfirmWrap.classList.add("hidden");
    elements.aiPromptLimitsFeedback.textContent = "";
    elements.aiPromptLimitsFeedback.className = "panel-meta";
    updateBusyState();
    return;
  }

  const sourceKey =
    settings.source === "remote" ? "settings.source.remote" : "settings.source.default";
  const metaParts = [t(sourceKey)];
  if (settings.updated_at) {
    metaParts.push(t("settings.updatedAt", { date: formatDate(settings.updated_at) }));
  }
  if (settings.updated_by_email) {
    metaParts.push(t("settings.updatedBy", { email: settings.updated_by_email }));
  }
  elements.aiPromptLimitsMeta.textContent = metaParts.join(" • ");
  elements.aiPromptLimitsSummary.innerHTML = `
    <div class="detail-label">${escapeHtml(t("settings.currentLimits"))}</div>
    <div class="detail-value">${escapeHtml(
      t("value.dailyWeeklyLimits", {
        daily: formatWholeNumber(settings.free_daily_prompt_limit || 0),
        weekly: formatWholeNumber(settings.free_weekly_prompt_limit || 0),
      }),
    )}</div>
  `;
  elements.freeDailyPromptLimitInput.value = `${Number(settings.free_daily_prompt_limit || 0)}`;
  elements.freeWeeklyPromptLimitInput.value = `${Number(settings.free_weekly_prompt_limit || 0)}`;
  elements.aiPromptLimitsForm.classList.toggle("hidden", !canEdit);
  elements.aiPromptLimitsEditorNote.classList.toggle("hidden", !canEdit);
  elements.aiPromptLimitsConfirmWrap.classList.toggle("hidden", !canEdit);
  elements.aiPromptLimitsConfirmLabel.textContent = t("settings.confirmPromptLimits");
  elements.aiPromptLimitsFeedback.textContent = state.aiPromptLimitsFeedback?.message || "";
  elements.aiPromptLimitsFeedback.className = state.aiPromptLimitsFeedback?.tone
    ? `panel-meta status-${state.aiPromptLimitsFeedback.tone}`
    : "panel-meta";
  updateBusyState();
}

function renderProducerCaptureWhitelistSettings() {
  const settings = state.producerCaptureWhitelist;
  const canEdit = canEditProducerCaptureWhitelist();
  if (!settings) {
    elements.producerCaptureWhitelistMeta.textContent = t("panel.producerCaptureWhitelist.meta");
    elements.producerCaptureWhitelistSummary.innerHTML = `
      <div class="detail-label">${escapeHtml(t("settings.currentProducerCaptureWhitelist"))}</div>
      <div class="detail-value">${escapeHtml(t("empty.signInProducerCaptureWhitelist"))}</div>
    `;
    elements.producerCaptureWhitelistInput.value = "";
    elements.producerCaptureWhitelistConfirmInput.value = "";
    elements.producerCaptureWhitelistForm.classList.add("hidden");
    elements.producerCaptureWhitelistEditorNote.classList.add("hidden");
    elements.producerCaptureWhitelistConfirmWrap.classList.add("hidden");
    elements.producerCaptureWhitelistFeedback.textContent = "";
    elements.producerCaptureWhitelistFeedback.className = "panel-meta";
    updateBusyState();
    return;
  }

  const sourceKey =
    settings.source === "remote" ? "settings.source.remote" : "settings.source.default";
  const metaParts = [t(sourceKey)];
  if (settings.updated_at) {
    metaParts.push(t("settings.updatedAt", { date: formatDate(settings.updated_at) }));
  }
  if (settings.updated_by_email) {
    metaParts.push(t("settings.updatedBy", { email: settings.updated_by_email }));
  }
  const usernames = Array.isArray(settings.usernames)
    ? settings.usernames.map((value) => `${value || ""}`.trim()).filter(Boolean)
    : [];
  elements.producerCaptureWhitelistMeta.textContent = metaParts.join(" • ");
  elements.producerCaptureWhitelistSummary.innerHTML = `
    <div class="detail-label">${escapeHtml(t("settings.currentProducerCaptureWhitelist"))}</div>
    <div class="detail-value">${escapeHtml(
      usernames.length ? usernames.join(", ") : t("settings.producerCaptureWhitelistNone"),
    )}</div>
  `;
  elements.producerCaptureWhitelistInput.value = usernames.join("\n");
  elements.producerCaptureWhitelistForm.classList.toggle("hidden", !canEdit);
  elements.producerCaptureWhitelistEditorNote.classList.toggle("hidden", !canEdit);
  elements.producerCaptureWhitelistConfirmWrap.classList.toggle("hidden", !canEdit);
  elements.producerCaptureWhitelistConfirmLabel.textContent = t(
    "settings.confirmProducerCaptureWhitelist",
  );
  elements.producerCaptureWhitelistFeedback.textContent =
    state.producerCaptureWhitelistFeedback?.message || "";
  elements.producerCaptureWhitelistFeedback.className = state.producerCaptureWhitelistFeedback?.tone
    ? `panel-meta status-${state.producerCaptureWhitelistFeedback.tone}`
    : "panel-meta";
  updateBusyState();
}

function renderAiRuntimeSettings() {
  const settings = state.aiRuntimeSettings;
  const canEdit = canViewAiRuntimeSettings();
  elements.aiRuntimePanel.classList.toggle("hidden", !canEdit);
  if (!canEdit) {
    return;
  }
  if (!settings || !Array.isArray(settings.features)) {
    elements.aiRuntimeMeta.textContent = t("panel.aiRuntime.meta");
    elements.aiRuntimeSettings.className = "inspector-empty";
    elements.aiRuntimeSettings.textContent = t("empty.signInAiRuntime");
    return;
  }

  const forms = settings.features
    .map((featureConfig) => {
      const feature = `${featureConfig.feature || ""}`.trim();
      if (!feature) {
        return "";
      }
      const defaultRuntime = featureConfig.default_runtime || {};
      const feedback = state.aiRuntimeFeedbackByFeature[feature];
      const sourceKey =
        featureConfig.source === "remote" ? "settings.source.remote" : "settings.source.default";
      const metaParts = [t(sourceKey)];
      if (featureConfig.updated_at) {
        metaParts.push(t("settings.updatedAt", { date: formatDate(featureConfig.updated_at) }));
      }
      if (featureConfig.updated_by_email) {
        metaParts.push(t("settings.updatedBy", { email: featureConfig.updated_by_email }));
      }
      const confirmPhrase = aiRuntimeConfirmPhrase(feature);
      return `
        <form class="delete-card support-card ai-runtime-form" data-feature="${escapeHtml(feature)}">
          <p class="panel-label">${escapeHtml(t(`settings.feature.${feature}`))}</p>
          <h3>${escapeHtml(t("settings.currentAiRuntime"))}</h3>
          <p class="delete-copy">${escapeHtml(metaParts.join(" • "))}</p>
          <p class="delete-copy">${escapeHtml(t("settings.emptyUsesDefault"))}</p>
          <div class="detail-grid">
            ${detailCardHtml(
              t("settings.modelOverride"),
              featureConfig.model_override
                || defaultValueLabel(formatDefaultRuntimeValue(defaultRuntime.model)),
              featureConfig.model_override ? { monospace: true } : {},
            )}
            ${detailCardHtml(
              t("settings.maxOutputTokensOverride"),
              featureConfig.max_output_tokens_override == null
                ? defaultValueLabel(formatDefaultRuntimeValue(defaultRuntime.max_output_tokens))
                : `${featureConfig.max_output_tokens_override}`,
            )}
            ${detailCardHtml(
              t("settings.temperatureOverride"),
              featureConfig.temperature_override == null
                ? defaultValueLabel(formatDefaultRuntimeValue(defaultRuntime.temperature))
                : `${featureConfig.temperature_override}`,
            )}
            ${detailCardHtml(
              t("settings.reasoningEffortOverride"),
              featureConfig.reasoning_effort_override
                || defaultValueLabel(formatDefaultRuntimeValue(defaultRuntime.reasoning_effort)),
            )}
            ${detailCardHtml(
              t("settings.promptCacheRetentionOverride"),
              featureConfig.prompt_cache_retention_override
                || defaultValueLabel(
                  formatDefaultRuntimeValue(defaultRuntime.prompt_cache_retention),
                ),
            )}
            ${detailCardHtml(
              t("settings.systemPromptOverride"),
              featureConfig.system_prompt_override || t("settings.noPromptOverride"),
              { monospace: true },
            )}
          </div>
          <div class="form-stack">
            <label class="search-input-wrap">
                <span class="search-label">${escapeHtml(t("settings.modelOverride"))}</span>
              <select class="select-input" name="model_override">
                ${buildSelectOptions(AI_MODEL_OPTIONS, featureConfig.model_override || "", {
                  emptyLabel: defaultValueLabel(formatDefaultRuntimeValue(defaultRuntime.model)),
                })}
              </select>
            </label>
            <div class="inspector-grid">
              <label class="search-input-wrap">
                <span class="search-label">${escapeHtml(t("settings.maxOutputTokensOverride"))}</span>
                <input class="text-input" type="number" min="1" step="1" name="max_output_tokens_override" value="${escapeHtml(
                  featureConfig.max_output_tokens_override == null
                    ? ""
                    : `${featureConfig.max_output_tokens_override}`,
                )}" />
              </label>
              <label class="search-input-wrap">
                <span class="search-label">${escapeHtml(t("settings.temperatureOverride"))}</span>
                <input class="text-input" type="number" min="0" max="2" step="0.1" name="temperature_override" value="${escapeHtml(
                  featureConfig.temperature_override == null
                    ? ""
                    : `${featureConfig.temperature_override}`,
                )}" />
              </label>
            </div>
            <div class="inspector-grid">
              <label class="search-input-wrap">
                <span class="search-label">${escapeHtml(t("settings.reasoningEffortOverride"))}</span>
                <select class="select-input" name="reasoning_effort_override">
                  ${buildSelectOptions(
                    AI_REASONING_EFFORT_OPTIONS,
                    featureConfig.reasoning_effort_override || "",
                    {
                      emptyLabel: defaultValueLabel(
                        formatDefaultRuntimeValue(defaultRuntime.reasoning_effort),
                      ),
                    },
                  )}
                </select>
              </label>
              <label class="search-input-wrap">
                <span class="search-label">${escapeHtml(t("settings.promptCacheRetentionOverride"))}</span>
                <select class="select-input" name="prompt_cache_retention_override">
                  ${buildSelectOptions(
                    AI_PROMPT_CACHE_RETENTION_OPTIONS,
                    featureConfig.prompt_cache_retention_override || "",
                    {
                      emptyLabel: defaultValueLabel(
                        formatDefaultRuntimeValue(defaultRuntime.prompt_cache_retention),
                      ),
                    },
                  )}
                </select>
              </label>
            </div>
            <label class="search-input-wrap">
              <span class="search-label">${escapeHtml(t("settings.systemPromptOverride"))}</span>
              <textarea class="text-area" name="system_prompt_override">${escapeHtml(
                featureConfig.system_prompt_override || "",
              )}</textarea>
            </label>
            <label class="search-input-wrap">
              <span class="search-label">${escapeHtml(
                t("settings.confirmAiRuntime", {
                  feature: t(`settings.feature.${feature}`).toUpperCase(),
                }),
              )}</span>
              <input
                class="text-input ai-runtime-confirm-input"
                type="text"
                name="confirm_phrase"
                data-confirm-phrase="${escapeHtml(confirmPhrase)}"
                autocomplete="off"
                spellcheck="false"
              />
            </label>
            <div class="search-actions">
              <button class="button button-secondary ai-runtime-save-button" type="submit" ${
                state.aiRuntimeBusy ? "disabled" : ""
              }>
                ${escapeHtml(state.aiRuntimeBusy ? t("action.saving") : t("action.saveAiOverride"))}
              </button>
            </div>
            ${feedback ? `<div class="status-panel status-${escapeHtml(feedback.tone || "info")}">${escapeHtml(feedback.message || "")}</div>` : ""}
          </div>
        </form>
      `;
    })
    .join("");

  elements.aiRuntimeMeta.textContent = t("panel.aiRuntime.meta");
  elements.aiRuntimeSettings.className = "inspector-stack";
  elements.aiRuntimeSettings.innerHTML = forms || escapeHtml(t("empty.signInAiRuntime"));
  updateAiRuntimeConfirmButtons();
}

function renderBillingCatalogSettings() {
  const catalog = state.billingCatalog;
  const defaultMeta = tMaybe(
    "panel.billingCatalog.meta",
    "Control the catalog the app reads for pricing, entitlements, and support links.",
  );
  if (!catalog) {
    elements.billingCatalogMeta.textContent = defaultMeta;
    elements.billingCatalogSummary.innerHTML = buildBillingCatalogSummaryHtml({
      plans: [],
      products: [],
      providerProducts: [],
      support: null,
    });
    elements.billingCatalogPreview.innerHTML = `
      <div class="inspector-empty">${escapeHtml(
        tMaybe("empty.signInBillingCatalog", "Sign in to load billing catalog settings."),
      )}</div>
    `;
    elements.billingCatalogForm.classList.add("hidden");
    elements.billingCatalogSupportEmailInput.value = "";
    elements.billingCatalogContactLabelInput.value = "";
    elements.billingCatalogSupportUrlInput.value = "";
    elements.billingCatalogFaqUrlInput.value = "";
    elements.billingCatalogManageSubscriptionUrlInput.value = "";
    elements.billingCatalogRefundPolicyUrlInput.value = "";
    elements.billingCatalogDefaultCheckoutUrlInput.value = "";
    elements.billingCatalogPlansInput.value = "";
    elements.billingCatalogProductsInput.value = "";
    elements.billingCatalogProviderProductsInput.value = "";
    renderBillingFeedback(elements.billingCatalogFeedback, state.billingCatalogFeedback);
    renderBillingOrganizations();
    updateBusyState();
    return;
  }

  const plans = Array.isArray(catalog.plans) ? catalog.plans : [];
  const products = Array.isArray(catalog.products) ? catalog.products : [];
  const providerProducts = Array.isArray(catalog.provider_products)
    ? catalog.provider_products
    : Array.isArray(catalog.offers)
      ? catalog.offers
      : [];
  const support = catalog.support && typeof catalog.support === "object" ? catalog.support : {};
  const metaParts = [
    catalog.configurable === false ? "Read-only defaults" : "Editable by admin",
  ];
  if (catalog.updated_at) {
    metaParts.push(`Updated ${formatDate(catalog.updated_at)}`);
  }
  elements.billingCatalogMeta.textContent = metaParts.join(" • ") || defaultMeta;
  elements.billingCatalogSummary.innerHTML = buildBillingCatalogSummaryHtml({
    plans,
    products,
    providerProducts,
    support,
  });
  elements.billingCatalogPreview.innerHTML = buildBillingCatalogPreviewHtml({
    plans,
    products,
    providerProducts,
    support,
  });
  elements.billingCatalogForm.classList.remove("hidden");
  elements.billingCatalogSupportEmailInput.value = `${support.support_email || ""}`;
  elements.billingCatalogContactLabelInput.value = `${support.contact_label || ""}`;
  elements.billingCatalogSupportUrlInput.value = `${support.support_url || ""}`;
  elements.billingCatalogFaqUrlInput.value = `${support.faq_url || ""}`;
  elements.billingCatalogManageSubscriptionUrlInput.value =
    `${support.manage_subscription_url || ""}`;
  elements.billingCatalogRefundPolicyUrlInput.value = `${support.refund_policy_url || ""}`;
  elements.billingCatalogDefaultCheckoutUrlInput.value = `${support.default_checkout_url || ""}`;
  elements.billingCatalogPlansInput.value = JSON.stringify(plans, null, 2);
  elements.billingCatalogProductsInput.value = JSON.stringify(products, null, 2);
  elements.billingCatalogProviderProductsInput.value = JSON.stringify(
    providerProducts,
    null,
    2,
  );
  renderBillingFeedback(elements.billingCatalogFeedback, state.billingCatalogFeedback);
  renderBillingOrganizations();
  updateBusyState();
}

function renderBillingOrganizations() {
  const records = Array.isArray(state.billingOrganizations) ? state.billingOrganizations : [];
  const configurable = state.collaborationConfigurable !== false;
  const baseMeta = tMaybe(
    "panel.billingOrganizations.meta",
    "Create or update team billing orgs, seat limits, and shared workspace access.",
  );
  elements.billingOrganizationsMeta.textContent = configurable
    ? baseMeta
    : `${baseMeta} • Collaboration table not configured.`;
  if (!records.length) {
    elements.billingOrganizationsTableBody.innerHTML = buildBillingEmptyTableRow(
      5,
      configurable
        ? tMaybe("empty.noOrganizations", "No organizations yet.")
        : tMaybe("empty.signInBillingControlPlane", "Billing control-plane records are unavailable."),
    );
  } else {
    elements.billingOrganizationsTableBody.innerHTML = records
      .map((record) => {
        const selected = record.organization_id === state.selectedBillingOrganizationId;
        const rowClass = selected ? ' class="is-selected"' : "";
        const seatsUsed = Number(record.seats_used || 0);
        const seatsLimit = Number(record.seat_limit || 0);
        const seatDetail = seatsLimit > 0
          ? `${formatWholeNumber(seatsUsed)} / ${formatWholeNumber(seatsLimit)}`
          : formatWholeNumber(seatsUsed);
        return `
          <tr${rowClass} data-billing-selectable="true" data-organization-id="${escapeHtml(
            record.organization_id || "",
          )}">
            <td>
              <div class="user-name">${escapeHtml(record.name || record.organization_id || "")}</div>
              <div class="user-subtext table-code">${escapeHtml(record.organization_id || "")}</div>
            </td>
            <td>${escapeHtml(record.plan_code || t("detail.na"))}</td>
            <td>
              <div>${escapeHtml(seatDetail)}</div>
              <div class="user-subtext">${escapeHtml(
                `${formatWholeNumber(record.seats_active || 0)} active • ${formatWholeNumber(
                  record.seats_invited || 0,
                )} invited`,
              )}</div>
            </td>
            <td>${escapeHtml(formatStatusLabel(record.status || ""))}</td>
            <td>${escapeHtml(formatDate(record.updated_at || record.created_at))}</td>
          </tr>
        `;
      })
      .join("");
  }
  elements.billingOrganizationsPageMeta.textContent = buildBillingRecordMeta(records.length, "orgs");
  renderBillingEducationSummary();
  renderBillingOrganizationForm();
  renderBillingFeedback(
    elements.billingEducationProvisionFeedback,
    state.billingEducationProvisionFeedback,
  );
  renderBillingFeedback(elements.billingOrganizationFeedback, state.billingOrganizationFeedback);
}

function renderBillingEducationSummary() {
  const record = getSelectedBillingOrganization();
  if (!elements.billingEducationSummary) return;
  const isEducation = `${record?.plan_code || ""}`.trim().toLowerCase() === "education";
  elements.billingEducationSummary.classList.toggle("hidden", !isEducation);
  if (!isEducation) return;
  const limit = Number(record?.seat_limit || 0);
  const used = Number(record?.seats_used || 0);
  const active = Number(record?.seats_active || 0);
  const invited = Number(record?.seats_invited || 0);
  elements.billingEducationCurrentPlan.textContent = `Current plan: Education ${formatWholeNumber(
    limit,
  )} student seats`;
  elements.billingEducationSeats.textContent = `Student seats used: ${formatWholeNumber(
    used,
  )} / ${formatWholeNumber(limit)} (${formatWholeNumber(active)} active, ${formatWholeNumber(
    invited,
  )} invited). Teacher/admin access is separate.`;
  elements.billingEducationSummary
    .querySelectorAll("[data-education-seat-preset]")
    .forEach((button) => {
      const preset = Number(button.dataset.educationSeatPreset || 0);
      button.disabled = preset > 0 && preset < used;
      button.textContent =
        preset === 30 && limit < 30
          ? "Upgrade to 30 student seats"
          : `${formatWholeNumber(preset)} student seats`;
    });
}

function renderBillingMemberships() {
  const records = Array.isArray(state.billingMemberships) ? state.billingMemberships : [];
  const configurable = state.collaborationConfigurable !== false;
  const baseMeta = tMaybe(
    "panel.billingMemberships.meta",
    "Track who belongs to each org, their role, and whether they consume a seat.",
  );
  elements.billingMembershipsMeta.textContent = configurable
    ? baseMeta
    : `${baseMeta} • Collaboration table not configured.`;
  if (!records.length) {
    elements.billingMembershipsTableBody.innerHTML = buildBillingEmptyTableRow(
      5,
      configurable
        ? tMaybe("empty.noMemberships", "No memberships yet.")
        : tMaybe("empty.signInBillingControlPlane", "Billing control-plane records are unavailable."),
    );
  } else {
    elements.billingMembershipsTableBody.innerHTML = records
      .map((record) => {
        const key = billingMembershipKey(record);
        const selected = key === state.selectedBillingMembershipKey;
        const rowClass = selected ? ' class="is-selected"' : "";
        const seat = record.seat_consumed ? "Seat consumed" : "No seat";
        const userLabel = record.email || record.user_id || "";
        const inviteLabel =
          record.status === "pending" && record.invite_url
            ? `Pending invite • ${record.invite_url}`
            : seat;
        return `
          <tr${rowClass} data-billing-selectable="true" data-membership-key="${escapeHtml(key)}">
            <td class="table-code">${escapeHtml(record.organization_id || "")}</td>
            <td>
              <div class="user-name table-code">${escapeHtml(userLabel)}</div>
              <div class="user-subtext">${escapeHtml(inviteLabel)}</div>
            </td>
            <td>${escapeHtml(record.role || t("detail.na"))}</td>
            <td>${escapeHtml(formatStatusLabel(record.status || ""))}</td>
            <td>${escapeHtml(formatDate(record.updated_at || record.created_at))}</td>
          </tr>
        `;
      })
      .join("");
  }
  elements.billingMembershipsPageMeta.textContent = buildBillingRecordMeta(records.length, "memberships");
  renderBillingMembershipForm();
  renderBillingFeedback(elements.billingMembershipFeedback, state.billingMembershipFeedback);
}

function renderBillingWorkspaces() {
  const records = Array.isArray(state.billingWorkspaces) ? state.billingWorkspaces : [];
  const configurable = state.collaborationConfigurable !== false;
  const baseMeta = tMaybe(
    "panel.billingWorkspaces.meta",
    "Control workspace ownership, visibility, and default project privacy.",
  );
  elements.billingWorkspacesMeta.textContent = configurable
    ? baseMeta
    : `${baseMeta} • Collaboration table not configured.`;
  if (!records.length) {
    elements.billingWorkspacesTableBody.innerHTML = buildBillingEmptyTableRow(
      5,
      configurable
        ? tMaybe("empty.noWorkspaces", "No workspaces yet.")
        : tMaybe("empty.signInBillingControlPlane", "Billing control-plane records are unavailable."),
    );
  } else {
    elements.billingWorkspacesTableBody.innerHTML = records
      .map((record) => {
        const selected = record.workspace_id === state.selectedBillingWorkspaceId;
        const rowClass = selected ? ' class="is-selected"' : "";
        const workspaceMeta = [record.visibility, record.default_project_privacy]
          .map((value) => `${value || ""}`.trim())
          .filter(Boolean)
          .join(" • ");
        return `
          <tr${rowClass} data-billing-selectable="true" data-workspace-id="${escapeHtml(
            record.workspace_id || "",
          )}">
            <td>
              <div class="user-name">${escapeHtml(record.name || record.workspace_id || "")}</div>
              <div class="user-subtext table-code">${escapeHtml(
                workspaceMeta || record.workspace_id || "",
              )}</div>
            </td>
            <td class="table-code">${escapeHtml(record.organization_id || "")}</td>
            <td class="table-code">${escapeHtml(record.user_id || t("detail.na"))}</td>
            <td>${escapeHtml(formatStatusLabel(record.status || ""))}</td>
            <td>${escapeHtml(formatDate(record.updated_at || record.created_at))}</td>
          </tr>
        `;
      })
      .join("");
  }
  elements.billingWorkspacesPageMeta.textContent = buildBillingRecordMeta(records.length, "workspaces");
  renderBillingWorkspaceForm();
  renderBillingFeedback(elements.billingWorkspaceFeedback, state.billingWorkspaceFeedback);
}

function renderBillingCloudProjects() {
  const records = Array.isArray(state.billingCloudProjects) ? state.billingCloudProjects : [];
  const configurable = state.collaborationConfigurable !== false;
  const baseMeta = tMaybe(
    "panel.billingCloudProjects.meta",
    "Manage workspace-linked cloud project metadata and optional document uploads.",
  );
  elements.billingCloudProjectsMeta.textContent = configurable
    ? baseMeta
    : `${baseMeta} • Collaboration table not configured.`;
  if (!records.length) {
    elements.billingCloudProjectsTableBody.innerHTML = buildBillingEmptyTableRow(
      5,
      configurable
        ? tMaybe("empty.noCloudProjects", "No cloud projects yet.")
        : tMaybe("empty.signInBillingControlPlane", "Billing control-plane records are unavailable."),
    );
  } else {
    elements.billingCloudProjectsTableBody.innerHTML = records
      .map((record) => {
        const selected = record.project_id === state.selectedBillingCloudProjectId;
        const rowClass = selected ? ' class="is-selected"' : "";
        const projectMeta = [record.storage_mode, record.document_revision ? `rev ${record.document_revision}` : ""]
          .filter(Boolean)
          .join(" • ");
        return `
          <tr${rowClass} data-billing-selectable="true" data-cloud-project-id="${escapeHtml(
            record.project_id || "",
          )}">
            <td>
              <div class="user-name">${escapeHtml(record.name || record.project_id || "")}</div>
              <div class="user-subtext table-code">${escapeHtml(
                projectMeta || record.project_id || "",
              )}</div>
            </td>
            <td class="table-code">${escapeHtml(record.workspace_id || "")}</td>
            <td class="table-code">${escapeHtml(record.user_id || t("detail.na"))}</td>
            <td>${escapeHtml(formatStatusLabel(record.status || ""))}</td>
            <td>${escapeHtml(formatDate(record.updated_at || record.created_at))}</td>
          </tr>
        `;
      })
      .join("");
  }
  elements.billingCloudProjectsPageMeta.textContent = buildBillingRecordMeta(
    records.length,
    "cloud projects",
  );
  renderBillingCloudProjectForm();
  renderBillingFeedback(elements.billingCloudProjectFeedback, state.billingCloudProjectFeedback);
}

function renderBillingOrganizationForm() {
  const record = getSelectedBillingOrganization();
  const defaultPlanCode = state.billingCatalog?.plans?.[0]?.code || "studio";
  const planCode = `${record?.plan_code || defaultPlanCode || ""}`.trim();
  elements.billingOrganizationPlanCodeInput.innerHTML = buildBillingPlanCodeOptions(planCode);
  elements.billingOrganizationIdInput.value = `${record?.organization_id || ""}`;
  elements.billingOrganizationNameInput.value = `${record?.name || ""}`;
  elements.billingOrganizationPlanCodeInput.value = planCode;
  elements.billingOrganizationSeatLimitInput.value =
    record?.seat_limit == null ? "" : `${record.seat_limit}`;
  elements.billingOrganizationStatusInput.value = `${record?.status || "active"}`;
  elements.billingOrganizationSharedWorkspaceEnabledInput.checked =
    record?.shared_workspace_enabled !== false;
  elements.billingOrganizationSupportNotesInput.value = `${record?.support_notes || ""}`;
}

function renderBillingMembershipForm() {
  const record = getSelectedBillingMembership();
  elements.billingMembershipOrganizationIdInput.value = `${record?.organization_id || ""}`;
  elements.billingMembershipUserIdInput.value = `${record?.user_id || ""}`;
  elements.billingMembershipEmailInput.value = `${record?.email || ""}`;
  elements.billingMembershipRoleInput.value = `${record?.role || "member"}`;
  elements.billingMembershipStatusInput.value = `${record?.status || "active"}`;
  elements.billingMembershipSeatConsumedInput.checked = record?.seat_consumed === true;
}

function renderBillingWorkspaceForm() {
  const record = getSelectedBillingWorkspace();
  elements.billingWorkspaceIdInput.value = `${record?.workspace_id || ""}`;
  elements.billingWorkspaceNameInput.value = `${record?.name || ""}`;
  elements.billingWorkspaceOrganizationIdInput.value = `${record?.organization_id || ""}`;
  elements.billingWorkspaceOwnerUserIdInput.value = `${record?.user_id || ""}`;
  elements.billingWorkspaceVisibilityInput.value = `${record?.visibility || "organization"}`;
  elements.billingWorkspaceDefaultProjectPrivacyInput.value =
    `${record?.default_project_privacy || "workspace"}`;
  elements.billingWorkspaceStatusInput.value = `${record?.status || "active"}`;
}

function renderBillingCloudProjectForm() {
  const record = getSelectedBillingCloudProject();
  elements.billingCloudProjectIdInput.value = `${record?.project_id || ""}`;
  elements.billingCloudProjectNameInput.value = `${record?.name || ""}`;
  elements.billingCloudProjectWorkspaceIdInput.value = `${record?.workspace_id || ""}`;
  elements.billingCloudProjectOrganizationIdInput.value = `${record?.organization_id || ""}`;
  elements.billingCloudProjectOwnerUserIdInput.value = `${record?.user_id || ""}`;
  elements.billingCloudProjectStorageModeInput.value =
    `${record?.storage_mode || "metadata_only"}`;
  elements.billingCloudProjectDocumentRevisionInput.value =
    record?.document_revision == null ? "" : `${record.document_revision}`;
  elements.billingCloudProjectStatusInput.value = `${record?.status || "active"}`;
  elements.billingCloudProjectDocumentInput.value = "";
}

function buildBillingCatalogSummaryHtml({ plans, products, providerProducts, support }) {
  return [
    buildBillingMiniMetricHtml("Plans", formatWholeNumber(plans.length || 0)),
    buildBillingMiniMetricHtml("Products", formatWholeNumber(products.length || 0)),
    buildBillingMiniMetricHtml(
      "Provider products",
      formatWholeNumber(providerProducts.length || 0),
    ),
    buildBillingMiniMetricHtml(
      "Support",
      support?.support_email || support?.contact_label || t("detail.na"),
    ),
  ].join("");
}

function buildBillingMiniMetricHtml(label, value) {
  return `
    <div class="mini-metric">
      <div class="mini-label">${escapeHtml(label)}</div>
      <div class="mini-value">${escapeHtml(value)}</div>
    </div>
  `;
}

function buildBillingCatalogPreviewHtml({ plans, products, providerProducts, support }) {
  const planRows = plans.map((plan) => [
    `<span class="table-code">${escapeHtml(plan.code || "")}</span>`,
    escapeHtml(plan.label || plan.code || ""),
    escapeHtml(plan.group || ""),
    escapeHtml(summarizeMap(plan.limits || {})),
  ]);
  const productRows = products.map((product) => [
    `<span class="table-code">${escapeHtml(product.code || "")}</span>`,
    escapeHtml(product.plan_code || ""),
    escapeHtml(`${product.type || ""} • ${product.billing_interval || ""}`.trim()),
    escapeHtml(product.price_display || product.management_channel || t("detail.na")),
  ]);
  const providerProductRows = providerProducts.map((providerProduct) => [
    `<span class="table-code">${escapeHtml(providerProduct.code || "")}</span>`,
    escapeHtml(providerProduct.provider || ""),
    escapeHtml(providerProduct.product_code || ""),
    escapeHtml(providerProduct.provider_product_id || t("detail.na")),
  ]);
  return `
    ${buildBillingPreviewTableSection("Plans", ["Code", "Label", "Group", "Limits"], planRows)}
    ${buildBillingPreviewTableSection(
      "Products",
      ["Code", "Plan", "Type", "Price / Channel"],
      productRows,
    )}
    ${buildBillingPreviewTableSection(
      "Provider products",
      ["Code", "Provider", "Product", "Provider Product ID"],
      providerProductRows,
    )}
    <section class="billing-preview-section">
      <div class="subsection-header">
        <div>
          <p class="panel-label">Support</p>
          <h3>Support links</h3>
        </div>
      </div>
      <div class="detail-grid">
        ${detailCardHtml("Support email", support?.support_email || t("detail.na"), { monospace: true })}
        ${detailCardHtml("Contact label", support?.contact_label || t("detail.na"))}
        ${detailCardHtml("Support URL", support?.support_url || t("detail.na"), { monospace: true })}
        ${detailCardHtml("FAQ URL", support?.faq_url || t("detail.na"), { monospace: true })}
        ${detailCardHtml(
          "Manage subscription URL",
          support?.manage_subscription_url || t("detail.na"),
          { monospace: true },
        )}
        ${detailCardHtml(
          "Default checkout URL",
          support?.default_checkout_url || t("detail.na"),
          { monospace: true },
        )}
      </div>
    </section>
  `;
}

function buildBillingPreviewTableSection(title, columns, rows) {
  return `
    <section class="billing-preview-section">
      <div class="subsection-header">
        <div>
          <p class="panel-label">${escapeHtml(title)}</p>
          <h3>${escapeHtml(title)}</h3>
        </div>
      </div>
      <div class="compact-table-wrap">
        <table class="billing-table billing-preview-table">
          <thead>
            <tr>${columns.map((column) => `<th>${escapeHtml(column)}</th>`).join("")}</tr>
          </thead>
          <tbody>
            ${rows.length
              ? rows
                .map(
                  (row) => `<tr>${row.map((value) => `<td>${value}</td>`).join("")}</tr>`,
                )
                .join("")
              : buildBillingEmptyTableRow(columns.length, "No records.")}
          </tbody>
        </table>
      </div>
    </section>
  `;
}

function buildBillingEmptyTableRow(colspan, message) {
  return `<tr><td colspan="${colspan}" class="table-empty">${escapeHtml(message)}</td></tr>`;
}

function buildBillingRecordMeta(count, label) {
  const parts = [`${formatWholeNumber(count)} ${label}`];
  if (state.collaborationConfigurable === false) {
    parts.push("not configured");
  }
  return parts.join(" • ");
}

function renderBillingFeedback(node, feedback) {
  node.textContent = feedback?.message || "";
  node.className = feedback?.tone ? `panel-meta status-${feedback.tone}` : "panel-meta";
}

function summarizeMap(value) {
  if (!value || typeof value !== "object") {
    return t("detail.na");
  }
  const entries = Object.entries(value)
    .filter(([, current]) => current !== null && current !== undefined && `${current}` !== "")
    .slice(0, 4);
  if (!entries.length) {
    return t("detail.na");
  }
  return entries.map(([key, current]) => `${key}: ${current}`).join(" • ");
}

function buildBillingPlanCodeOptions(selectedValue) {
  const options = Array.isArray(state.billingCatalog?.plans)
    ? state.billingCatalog.plans.map((plan) => ({
      value: `${plan.code || ""}`.trim(),
      label: `${plan.label || plan.code || ""}`.trim(),
    }))
    : [];
  if (selectedValue && !options.some((option) => option.value === selectedValue)) {
    options.unshift({ value: selectedValue, label: selectedValue });
  }
  if (!options.length) {
    options.push({ value: "studio", label: "Studio" });
  }
  return options
    .map((option) => {
      const selected = option.value === `${selectedValue || ""}` ? "selected" : "";
      return `<option value="${escapeHtml(option.value)}" ${selected}>${escapeHtml(option.label)}</option>`;
    })
    .join("");
}

function syncSelectedBillingOrganization() {
  if (!state.billingOrganizations.some((record) => record.organization_id === state.selectedBillingOrganizationId)) {
    state.selectedBillingOrganizationId = "";
  }
}

function syncSelectedBillingMembership() {
  if (!state.billingMemberships.some((record) => billingMembershipKey(record) === state.selectedBillingMembershipKey)) {
    state.selectedBillingMembershipKey = "";
  }
}

function syncSelectedBillingWorkspace() {
  if (!state.billingWorkspaces.some((record) => record.workspace_id === state.selectedBillingWorkspaceId)) {
    state.selectedBillingWorkspaceId = "";
  }
}

function syncSelectedBillingCloudProject() {
  if (!state.billingCloudProjects.some((record) => record.project_id === state.selectedBillingCloudProjectId)) {
    state.selectedBillingCloudProjectId = "";
  }
}

function getSelectedBillingOrganization() {
  return state.billingOrganizations.find(
    (record) => record.organization_id === state.selectedBillingOrganizationId,
  ) || null;
}

function getSelectedBillingMembership() {
  return state.billingMemberships.find(
    (record) => billingMembershipKey(record) === state.selectedBillingMembershipKey,
  ) || null;
}

function getSelectedBillingWorkspace() {
  return state.billingWorkspaces.find(
    (record) => record.workspace_id === state.selectedBillingWorkspaceId,
  ) || null;
}

function getSelectedBillingCloudProject() {
  return state.billingCloudProjects.find(
    (record) => record.project_id === state.selectedBillingCloudProjectId,
  ) || null;
}

function billingMembershipKey(record) {
  return `${record?.organization_id || ""}:${record?.user_id || ""}`;
}

function clearBillingOrganizationSelection() {
  state.selectedBillingOrganizationId = "";
  renderBillingOrganizations();
}

function clearBillingMembershipSelection() {
  state.selectedBillingMembershipKey = "";
  renderBillingMemberships();
}

function clearBillingWorkspaceSelection() {
  state.selectedBillingWorkspaceId = "";
  renderBillingWorkspaces();
}

function clearBillingCloudProjectSelection() {
  state.selectedBillingCloudProjectId = "";
  renderBillingCloudProjects();
}

function handleBillingOrganizationsTableClick(event) {
  const row = event.target.closest("tr[data-organization-id]");
  if (!row) {
    return;
  }
  state.selectedBillingOrganizationId = `${row.dataset.organizationId || ""}`;
  renderBillingOrganizations();
}

function handleEducationSeatPresetClick(event) {
  const button = event.target.closest("[data-education-seat-preset]");
  if (!button || button.disabled) {
    return;
  }
  const preset = Number(button.dataset.educationSeatPreset || 0);
  if (!Number.isFinite(preset) || preset <= 0) {
    return;
  }
  const selected = getSelectedBillingOrganization();
  if (!selected) {
    return;
  }
  elements.billingOrganizationPlanCodeInput.value = "education";
  elements.billingOrganizationSeatLimitInput.value = `${preset}`;
  elements.billingOrganizationFeedback.textContent = `Education student seat limit staged at ${formatWholeNumber(
    preset,
  )}. Save organization to apply.`;
}

function handleBillingMembershipsTableClick(event) {
  const row = event.target.closest("tr[data-membership-key]");
  if (!row) {
    return;
  }
  state.selectedBillingMembershipKey = `${row.dataset.membershipKey || ""}`;
  renderBillingMemberships();
}

function handleBillingWorkspacesTableClick(event) {
  const row = event.target.closest("tr[data-workspace-id]");
  if (!row) {
    return;
  }
  state.selectedBillingWorkspaceId = `${row.dataset.workspaceId || ""}`;
  renderBillingWorkspaces();
}

function handleBillingCloudProjectsTableClick(event) {
  const row = event.target.closest("tr[data-cloud-project-id]");
  if (!row) {
    return;
  }
  state.selectedBillingCloudProjectId = `${row.dataset.cloudProjectId || ""}`;
  renderBillingCloudProjects();
}

function fillEducationProvisionTeacherFromSelectedUser() {
  const user = getSelectedUser();
  if (!user) {
    state.billingEducationProvisionFeedback = {
      tone: "error",
      message: "Select a user first.",
    };
    renderBillingOrganizations();
    return;
  }
  elements.billingEducationProvisionTeacherUserIdInput.value = user.user_id || "";
  elements.billingEducationProvisionTeacherEmailInput.value = user.email || "";
  if (!elements.billingEducationProvisionNameInput.value.trim()) {
    const label = user.display_name || user.username || user.email || "Education";
    elements.billingEducationProvisionNameInput.value = `${label} Education`;
  }
  state.billingEducationProvisionFeedback = {
    tone: "info",
    message: "Selected user staged as teacher.",
  };
  renderBillingFeedback(
    elements.billingEducationProvisionFeedback,
    state.billingEducationProvisionFeedback,
  );
}

async function handleBillingCatalogSubmit(event) {
  event.preventDefault();
  if (!tokens?.idToken || !canEditBillingCatalog()) {
    return;
  }

  state.billingCatalogBusy = true;
  state.billingCatalogFeedback = null;
  updateBusyState();
  setStatus(tMaybe("status.savingBillingCatalog", "Saving billing catalog settings..."), "info");

  try {
    const plans = parseJsonArrayInput(
      elements.billingCatalogPlansInput.value,
      "Plans JSON",
    );
    const products = parseJsonArrayInput(
      elements.billingCatalogProductsInput.value,
      "Products JSON",
    );
    const providerProducts = parseJsonArrayInput(
      elements.billingCatalogProviderProductsInput.value,
      "Provider products JSON",
    );
    const payload = await fetchAdminJson(ADMIN_BILLING_CATALOG_PATH, {
      method: "PUT",
      body: JSON.stringify({
        plans,
        products,
        provider_products: providerProducts,
        support: {
          support_email: `${elements.billingCatalogSupportEmailInput.value || ""}`.trim(),
          support_url: `${elements.billingCatalogSupportUrlInput.value || ""}`.trim(),
          faq_url: `${elements.billingCatalogFaqUrlInput.value || ""}`.trim(),
          manage_subscription_url:
            `${elements.billingCatalogManageSubscriptionUrlInput.value || ""}`.trim(),
          refund_policy_url: `${elements.billingCatalogRefundPolicyUrlInput.value || ""}`.trim(),
          contact_label: `${elements.billingCatalogContactLabelInput.value || ""}`.trim(),
          default_checkout_url:
            `${elements.billingCatalogDefaultCheckoutUrlInput.value || ""}`.trim(),
        },
      }),
    });
    state.billingCatalog = payload || null;
    state.billingCatalogConfigurable = payload?.configurable !== false;
    state.billingCatalogFeedback = {
      tone: "success",
      message: tMaybe("status.billingCatalogSaved", "Billing catalog settings saved."),
    };
    renderBillingCatalogSettings();
    setStatus(tMaybe("status.billingCatalogSaved", "Billing catalog settings saved."), "success");
  } catch (error) {
    handleAdminRequestError(
      error,
      tMaybe("status.saveBillingCatalogFailed", "Could not save billing catalog settings."),
    );
    state.billingCatalogFeedback = {
      tone: "error",
      message: error.message || tMaybe("status.saveBillingCatalogFailed", "Could not save billing catalog settings."),
    };
    renderBillingCatalogSettings();
  } finally {
    state.billingCatalogBusy = false;
    updateBusyState();
  }
}

async function handleBillingEducationProvisionSubmit(event) {
  event.preventDefault();
  if (!tokens?.idToken || !canEditBillingControlPlane()) {
    return;
  }

  state.billingOrganizationsBusy = true;
  state.billingEducationProvisionFeedback = null;
  updateBusyState();
  setStatus("Provisioning Education organization...", "info");

  try {
    const payload = await fetchAdminJson(ADMIN_BILLING_EDUCATION_PROVISIONING_PATH, {
      method: "POST",
      body: JSON.stringify({
        organization_id: `${elements.billingEducationProvisionOrgIdInput.value || ""}`.trim(),
        name: `${elements.billingEducationProvisionNameInput.value || ""}`.trim(),
        seat_limit: Number(elements.billingEducationProvisionSeatsInput.value || 20),
        teacher_user_id:
          `${elements.billingEducationProvisionTeacherUserIdInput.value || ""}`.trim(),
        teacher_email:
          `${elements.billingEducationProvisionTeacherEmailInput.value || ""}`.trim(),
      }),
    });
    if (payload.organization) {
      state.selectedBillingOrganizationId = payload.organization.organization_id || "";
      state.billingOrganizations = upsertByKey(
        state.billingOrganizations,
        payload.organization,
        (record) => record.organization_id,
      );
    }
    if (payload.teacher_membership) {
      state.selectedBillingMembershipKey = billingMembershipKey(payload.teacher_membership);
      state.billingMemberships = upsertByKey(
        state.billingMemberships,
        payload.teacher_membership,
        billingMembershipKey,
      );
    }
    if (payload.workspace) {
      state.selectedBillingWorkspaceId = payload.workspace.workspace_id || "";
      state.billingWorkspaces = upsertByKey(
        state.billingWorkspaces,
        payload.workspace,
        (record) => record.workspace_id,
      );
    }
    state.billingEducationProvisionFeedback = {
      tone: "success",
      message: "Education org provisioned. Teacher can now invite students from the app.",
    };
    elements.billingEducationProvisionOrgIdInput.value = "";
    elements.billingEducationProvisionNameInput.value = "";
    elements.billingEducationProvisionTeacherUserIdInput.value = "";
    elements.billingEducationProvisionTeacherEmailInput.value = "";
    renderBillingOrganizations();
    renderBillingMemberships();
    renderBillingWorkspaces();
    setStatus("Education organization provisioned.", "success");
  } catch (error) {
    handleAdminRequestError(error, "Could not provision Education organization.");
    state.billingEducationProvisionFeedback = {
      tone: "error",
      message: error.message || "Could not provision Education organization.",
    };
    renderBillingOrganizations();
  } finally {
    state.billingOrganizationsBusy = false;
    updateBusyState();
  }
}

async function handleBillingOrganizationSubmit(event) {
  event.preventDefault();
  if (!tokens?.idToken || !canEditBillingControlPlane()) {
    return;
  }

  state.billingOrganizationsBusy = true;
  state.billingOrganizationFeedback = null;
  updateBusyState();
  setStatus(tMaybe("status.savingOrganization", "Saving organization..."), "info");

  try {
    const payload = await fetchAdminJson(ADMIN_BILLING_ORGANIZATIONS_PATH, {
      method: "POST",
      body: JSON.stringify({
        organization_id: `${elements.billingOrganizationIdInput.value || ""}`.trim(),
        name: `${elements.billingOrganizationNameInput.value || ""}`.trim(),
        plan_code: `${elements.billingOrganizationPlanCodeInput.value || ""}`.trim(),
        seat_limit: `${elements.billingOrganizationSeatLimitInput.value || ""}`.trim(),
        status: `${elements.billingOrganizationStatusInput.value || ""}`.trim(),
        shared_workspace_enabled: elements.billingOrganizationSharedWorkspaceEnabledInput.checked,
        support_notes: `${elements.billingOrganizationSupportNotesInput.value || ""}`.trim(),
      }),
    });
    if (payload.organization) {
      state.selectedBillingOrganizationId = payload.organization.organization_id || "";
      state.billingOrganizations = upsertByKey(
        state.billingOrganizations,
        payload.organization,
        (record) => record.organization_id,
      );
    }
    state.billingOrganizationFeedback = {
      tone: "success",
      message: tMaybe("status.organizationSaved", "Organization saved."),
    };
    renderBillingOrganizations();
    setStatus(tMaybe("status.organizationSaved", "Organization saved."), "success");
  } catch (error) {
    handleAdminRequestError(error, tMaybe("status.saveOrganizationFailed", "Could not save organization."));
    state.billingOrganizationFeedback = {
      tone: "error",
      message: error.message || tMaybe("status.saveOrganizationFailed", "Could not save organization."),
    };
    renderBillingOrganizations();
  } finally {
    state.billingOrganizationsBusy = false;
    updateBusyState();
  }
}

async function handleBillingMembershipSubmit(event) {
  event.preventDefault();
  if (!tokens?.idToken || !canEditBillingControlPlane()) {
    return;
  }

  state.billingMembershipsBusy = true;
  state.billingMembershipFeedback = null;
  updateBusyState();
  setStatus(tMaybe("status.savingMembership", "Saving membership..."), "info");

  try {
    const payload = await fetchAdminJson(ADMIN_BILLING_MEMBERSHIPS_PATH, {
      method: "POST",
      body: JSON.stringify({
        organization_id: `${elements.billingMembershipOrganizationIdInput.value || ""}`.trim(),
        user_id: `${elements.billingMembershipUserIdInput.value || ""}`.trim(),
        email: `${elements.billingMembershipEmailInput.value || ""}`.trim(),
        role: `${elements.billingMembershipRoleInput.value || ""}`.trim(),
        status: `${elements.billingMembershipStatusInput.value || ""}`.trim(),
        seat_consumed: elements.billingMembershipSeatConsumedInput.checked,
      }),
    });
    if (payload.membership) {
      state.selectedBillingMembershipKey = billingMembershipKey(payload.membership);
      state.billingMemberships = upsertByKey(
        state.billingMemberships,
        payload.membership,
        billingMembershipKey,
      );
    }
    state.billingMembershipFeedback = {
      tone: "success",
      message: tMaybe("status.membershipSaved", "Membership saved."),
    };
    renderBillingMemberships();
    setStatus(tMaybe("status.membershipSaved", "Membership saved."), "success");
  } catch (error) {
    handleAdminRequestError(error, tMaybe("status.saveMembershipFailed", "Could not save membership."));
    state.billingMembershipFeedback = {
      tone: "error",
      message: error.message || tMaybe("status.saveMembershipFailed", "Could not save membership."),
    };
    renderBillingMemberships();
  } finally {
    state.billingMembershipsBusy = false;
    updateBusyState();
  }
}

async function handleBillingWorkspaceSubmit(event) {
  event.preventDefault();
  if (!tokens?.idToken || !canEditBillingControlPlane()) {
    return;
  }

  state.billingWorkspacesBusy = true;
  state.billingWorkspaceFeedback = null;
  updateBusyState();
  setStatus(tMaybe("status.savingWorkspace", "Saving workspace..."), "info");

  try {
    const payload = await fetchAdminJson(ADMIN_BILLING_WORKSPACES_PATH, {
      method: "POST",
      body: JSON.stringify({
        workspace_id: `${elements.billingWorkspaceIdInput.value || ""}`.trim(),
        organization_id: `${elements.billingWorkspaceOrganizationIdInput.value || ""}`.trim(),
        owner_user_id: `${elements.billingWorkspaceOwnerUserIdInput.value || ""}`.trim(),
        name: `${elements.billingWorkspaceNameInput.value || ""}`.trim(),
        visibility: `${elements.billingWorkspaceVisibilityInput.value || ""}`.trim(),
        default_project_privacy:
          `${elements.billingWorkspaceDefaultProjectPrivacyInput.value || ""}`.trim(),
        status: `${elements.billingWorkspaceStatusInput.value || ""}`.trim(),
      }),
    });
    if (payload.workspace) {
      state.selectedBillingWorkspaceId = payload.workspace.workspace_id || "";
      state.billingWorkspaces = upsertByKey(
        state.billingWorkspaces,
        payload.workspace,
        (record) => record.workspace_id,
      );
    }
    state.billingWorkspaceFeedback = {
      tone: "success",
      message: tMaybe("status.workspaceSaved", "Workspace saved."),
    };
    renderBillingWorkspaces();
    setStatus(tMaybe("status.workspaceSaved", "Workspace saved."), "success");
  } catch (error) {
    handleAdminRequestError(error, tMaybe("status.saveWorkspaceFailed", "Could not save workspace."));
    state.billingWorkspaceFeedback = {
      tone: "error",
      message: error.message || tMaybe("status.saveWorkspaceFailed", "Could not save workspace."),
    };
    renderBillingWorkspaces();
  } finally {
    state.billingWorkspacesBusy = false;
    updateBusyState();
  }
}

async function handleBillingCloudProjectSubmit(event) {
  event.preventDefault();
  if (!tokens?.idToken || !canEditBillingControlPlane()) {
    return;
  }

  state.billingCloudProjectsBusy = true;
  state.billingCloudProjectFeedback = null;
  updateBusyState();
  setStatus(tMaybe("status.savingCloudProject", "Saving cloud project..."), "info");

  try {
    const documentValue = `${elements.billingCloudProjectDocumentInput.value || ""}`.trim();
    const documentPayload = documentValue ? parseJsonObjectInput(documentValue, "Document JSON") : null;
    const payload = await fetchAdminJson(ADMIN_BILLING_CLOUD_PROJECTS_PATH, {
      method: "POST",
      body: JSON.stringify({
        project_id: `${elements.billingCloudProjectIdInput.value || ""}`.trim(),
        workspace_id: `${elements.billingCloudProjectWorkspaceIdInput.value || ""}`.trim(),
        organization_id: `${elements.billingCloudProjectOrganizationIdInput.value || ""}`.trim(),
        owner_user_id: `${elements.billingCloudProjectOwnerUserIdInput.value || ""}`.trim(),
        name: `${elements.billingCloudProjectNameInput.value || ""}`.trim(),
        storage_mode: `${elements.billingCloudProjectStorageModeInput.value || ""}`.trim(),
        document_revision: `${elements.billingCloudProjectDocumentRevisionInput.value || ""}`.trim(),
        status: `${elements.billingCloudProjectStatusInput.value || ""}`.trim(),
        ...(documentPayload ? { document: documentPayload } : {}),
      }),
    });
    if (payload.cloud_project) {
      state.selectedBillingCloudProjectId = payload.cloud_project.project_id || "";
      state.billingCloudProjects = upsertByKey(
        state.billingCloudProjects,
        payload.cloud_project,
        (record) => record.project_id,
      );
    }
    state.billingCloudProjectFeedback = {
      tone: "success",
      message: tMaybe("status.cloudProjectSaved", "Cloud project saved."),
    };
    renderBillingCloudProjects();
    setStatus(tMaybe("status.cloudProjectSaved", "Cloud project saved."), "success");
  } catch (error) {
    handleAdminRequestError(
      error,
      tMaybe("status.saveCloudProjectFailed", "Could not save cloud project."),
    );
    state.billingCloudProjectFeedback = {
      tone: "error",
      message: error.message || tMaybe("status.saveCloudProjectFailed", "Could not save cloud project."),
    };
    renderBillingCloudProjects();
  } finally {
    state.billingCloudProjectsBusy = false;
    updateBusyState();
  }
}

function upsertByKey(list, record, getKey) {
  const key = getKey(record);
  const nextList = Array.isArray(list) ? [...list] : [];
  const index = nextList.findIndex((candidate) => getKey(candidate) === key);
  if (index >= 0) {
    nextList[index] = record;
  } else {
    nextList.push(record);
  }
  return nextList.sort((left, right) =>
    `${right.updated_at || right.created_at || ""}`.localeCompare(`${left.updated_at || left.created_at || ""}`),
  );
}

function parseJsonArrayInput(value, label) {
  let parsed;
  try {
    parsed = JSON.parse(value);
  } catch (_) {
    throw new Error(`${label} must be valid JSON.`);
  }
  if (!Array.isArray(parsed)) {
    throw new Error(`${label} must be a JSON array.`);
  }
  return parsed;
}

function parseJsonObjectInput(value, label) {
  let parsed;
  try {
    parsed = JSON.parse(value);
  } catch (_) {
    throw new Error(`${label} must be valid JSON.`);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`${label} must be a JSON object.`);
  }
  return parsed;
}

function buildSelectOptions(options, selectedValue, { emptyLabel = "" } = {}) {
  return options
    .map((option) => {
      const value = `${option || ""}`;
      const label = value || emptyLabel;
      const selected = value === `${selectedValue || ""}` ? "selected" : "";
      return `<option value="${escapeHtml(value)}" ${selected}>${escapeHtml(label)}</option>`;
    })
    .join("");
}

function detailCardHtml(label, value, { monospace = false } = {}) {
  const valueClass = monospace ? "detail-value is-monospace" : "detail-value";
  return `
    <div class="detail-card compact">
      <div class="detail-label">${escapeHtml(label)}</div>
      <div class="${valueClass}">${escapeHtml(value)}</div>
    </div>
  `;
}

function defaultValueLabel(value) {
  return t("settings.usingBackendDefault", { value: value || t("detail.na") });
}

function formatDefaultRuntimeValue(value) {
  if (value == null || value === "") {
    return t("detail.na");
  }
  return `${value}`;
}

function aiRuntimeConfirmPhrase(feature) {
  return `APPLY ${t(`settings.feature.${feature}`).toUpperCase()} OVERRIDE`;
}

function promptLimitsConfirmationMatches() {
  return `${elements.aiPromptLimitsConfirmInput.value || ""}`.trim() === AI_PROMPT_LIMITS_CONFIRM_PHRASE;
}

function producerCaptureWhitelistConfirmationMatches() {
  return (
    `${elements.producerCaptureWhitelistConfirmInput.value || ""}`.trim()
    === PRODUCER_CAPTURE_WHITELIST_CONFIRM_PHRASE
  );
}

function runtimeConfirmationMatches(form) {
  const input = form?.querySelector(".ai-runtime-confirm-input");
  const expected = `${input?.dataset?.confirmPhrase || ""}`.trim();
  const actual = `${input?.value || ""}`.trim();
  return !!expected && actual === expected;
}

function updateAiRuntimeConfirmButtons() {
  elements.aiRuntimeSettings.querySelectorAll(".ai-runtime-form").forEach((form) => {
    const button = form.querySelector(".ai-runtime-save-button");
    if (!button) {
      return;
    }
    button.textContent = state.aiRuntimeBusy ? t("action.saving") : t("action.saveAiOverride");
    button.disabled = state.aiRuntimeBusy || !runtimeConfirmationMatches(form);
  });
}

function handleAiRuntimeInputChange() {
  updateAiRuntimeConfirmButtons();
}

function renderSummary(summary) {
  const cards = [
    {
      title: t("summary.users"),
      value: formatOverviewMetricValue(summary.total_users),
      detail: t("summary.usersDetail", {
        count: formatOverviewMetricValue(summary.tracked_users),
      }),
      className: "summary-users",
    },
    {
      title: t("summary.aiPromptsToday"),
      value: formatOverviewMetricValue(summary.ai_prompts_today),
      detail: summary.ai_prompts_today == null
        ? t("overview.loading")
        : t("summary.aiPromptsTodayDetail", {
          count: formatOverviewMetricValue(summary.ai_active_users_today),
        }),
      className: "summary-projects",
    },
    {
      title: t("summary.aiPromptsWeek"),
      value: formatOverviewMetricValue(summary.ai_prompts_week),
      detail: summary.ai_prompts_week == null
        ? t("overview.loading")
        : t("summary.aiPromptsWeekDetail", {
          count: formatOverviewMetricValue(summary.ai_active_users_week),
        }),
      className: "summary-ai",
    },
    {
      title: t("summary.paidUsers"),
      value: formatOverviewMetricValue(summary.paid_users),
      detail: t("summary.paidUsersDetail", {
        count: formatOverviewMetricValue(summary.active_subscriptions),
      }),
      className: "summary-paid",
    },
  ];

  elements.summarySection.innerHTML = cards
    .map(
      (card) => `
        <article class="summary-card ${card.className}">
          <p class="panel-label">${escapeHtml(card.title)}</p>
          <div class="summary-value">${escapeHtml(card.value)}</div>
          <p class="summary-detail">${escapeHtml(card.detail)}</p>
        </article>
      `,
    )
    .join("");
}

function renderProductAnalytics(productAnalytics) {
  const status = `${productAnalytics?.status || ""}`.trim() || "unconfigured";
  const metrics = productAnalytics?.metrics || {};
  const range = getAnalyticsRangeOption(state.analyticsRange);
  const emptyLabel = status === "live"
    ? t("analytics.emptyTrend")
    : status === "deferred"
      ? t("overview.loading")
    : status === "error"
      ? t("panel.kpi.unavailable")
      : t("panel.kpi.unconfigured");
  const emptyCountryLabel = status === "live"
    ? t("analytics.emptyCountries")
    : status === "deferred"
      ? t("overview.loading")
    : status === "error"
      ? t("panel.kpi.unavailable")
      : t("panel.kpi.unconfigured");
  const cards = [
    { label: t("analytics.metric.dau"), value: formatOverviewMetricValue(metrics.dau) },
    { label: t("analytics.metric.wau"), value: formatOverviewMetricValue(metrics.wau) },
    { label: t("analytics.metric.mau"), value: formatOverviewMetricValue(metrics.mau) },
    {
      label: t("analytics.metric.hours24h"),
      value: formatOverviewMetricValue(metrics.hours_24h, formatDecimal),
    },
  ];

  elements.kpiPanel.classList.remove("hidden");
  renderAnalyticsRangeControls();
  elements.analyticsSummary.innerHTML = cards
    .map(
      (metric) => `
        <div class="mini-metric">
          <div class="mini-label">${escapeHtml(metric.label)}</div>
          <div class="mini-value">${escapeHtml(metric.value)}</div>
        </div>
      `,
    )
    .join("");

  if (status === "live") {
    const updatedAt = productAnalytics.updated_at
      ? formatDate(productAnalytics.updated_at)
      : "";
    elements.kpiMeta.textContent = updatedAt
      ? `${t("panel.kpi.meta.live")} • ${updatedAt}`
      : t("panel.kpi.meta.live");
  } else if (status === "deferred") {
    elements.kpiMeta.textContent = t("overview.loading");
  } else if (status === "error") {
    elements.kpiMeta.textContent = t("panel.kpi.meta.error");
  } else {
    elements.kpiMeta.textContent = productAnalytics.note || t("panel.kpi.unconfigured");
  }

  renderAnalyticsChart(
    "activity",
    elements.analyticsActivityTrend,
    filterAnalyticsPoints(
      Array.isArray(productAnalytics.daily_active_users)
        ? productAnalytics.daily_active_users
        : [],
      range.days,
    ),
    {
      valueKey: "active_users",
      valueFormatter: (value) => formatNumber(value),
      seriesLabel: t("panel.kpi.activityTitle"),
      tone: "cool",
      emptyLabel,
    },
  );
  renderAnalyticsChart(
    "hours",
    elements.analyticsHoursTrend,
    filterAnalyticsPoints(
      Array.isArray(productAnalytics.daily_hours_used)
        ? productAnalytics.daily_hours_used
        : [],
      range.days,
    ),
    {
      valueKey: "hours_used",
      valueFormatter: (value) => formatDecimal(value),
      seriesLabel: t("panel.kpi.hoursTitle"),
      tone: "mint",
      emptyLabel,
    },
  );
  renderCountryConstellation(
    elements.analyticsCountryList,
    Array.isArray(productAnalytics.top_countries) ? productAnalytics.top_countries : [],
    {
      emptyLabel: emptyCountryLabel,
    },
  );
}

function renderAnalyticsRangeControls() {
  elements.analyticsRangeControls.innerHTML = ANALYTICS_RANGE_OPTIONS
    .map((option) => {
      const activeClass = option.key === state.analyticsRange ? " is-active" : "";
      return `
        <button
          class="analytics-range-button${activeClass}"
          type="button"
          data-analytics-range="${escapeHtml(option.key)}"
        >
          ${escapeHtml(t(option.labelKey))}
        </button>
      `;
    })
    .join("");
}

function renderAnalyticsChart(
  chartKey,
  container,
  points,
  { valueKey, valueFormatter, emptyLabel, seriesLabel, tone = "cool" } = {},
) {
  if (!Array.isArray(points) || !points.length) {
    destroyAnalyticsChart(chartKey);
    container.textContent = emptyLabel || t("analytics.emptyTrend");
    container.classList.add("empty-state");
    return;
  }

  const ChartApi = window.Chart;
  if (!ChartApi || typeof ChartApi !== "function") {
    destroyAnalyticsChart(chartKey);
    container.textContent = t("analytics.chartUnavailable");
    container.classList.add("empty-state");
    return;
  }

  const labels = points.map((point) => formatShortDate(point?.day || ""));
  const data = points.map((point) => Number(point?.[valueKey] || 0));
  const peakValue = Math.max(...data, 0);
  container.classList.remove("empty-state");
  container.innerHTML = `
    <div class="analytics-chart-wrap">
      <canvas class="analytics-chart-canvas" aria-label="${escapeHtml(seriesLabel || "")}"></canvas>
    </div>
    <div class="analytics-chart-footer">
      <span>${escapeHtml(labels[0] || "")}</span>
      <span>${escapeHtml(
        `${seriesLabel || ""} • ${valueFormatter(peakValue)}`,
      )}</span>
      <span>${escapeHtml(labels[labels.length - 1] || "")}</span>
    </div>
  `;

  destroyAnalyticsChart(chartKey);
  const canvas = container.querySelector("canvas");
  const context = canvas?.getContext("2d");
  if (!context) {
    container.textContent = t("analytics.chartUnavailable");
    container.classList.add("empty-state");
    return;
  }
  const gradient = context.createLinearGradient(0, 0, 0, 220);
  if (tone === "mint") {
    gradient.addColorStop(0, "rgba(150, 235, 206, 0.34)");
    gradient.addColorStop(1, "rgba(150, 235, 206, 0.02)");
  } else {
    gradient.addColorStop(0, "rgba(148, 216, 255, 0.34)");
    gradient.addColorStop(1, "rgba(148, 216, 255, 0.02)");
  }
  const strokeColor = tone === "mint" ? "#95eecf" : "#94d8ff";

  analyticsCharts[chartKey] = new ChartApi(context, {
    type: "line",
    data: {
      labels,
      datasets: [
        {
          label: seriesLabel,
          data,
          tension: 0.34,
          fill: true,
          borderColor: strokeColor,
          backgroundColor: gradient,
          borderWidth: 2,
          pointRadius: 0,
          pointHoverRadius: 4,
          pointHitRadius: 12,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: {
        duration: 420,
      },
      interaction: {
        mode: "index",
        intersect: false,
      },
      plugins: {
        legend: {
          display: false,
        },
        tooltip: {
          displayColors: false,
          backgroundColor: "rgba(12, 18, 26, 0.94)",
          borderColor: "rgba(255, 255, 255, 0.08)",
          borderWidth: 1,
          padding: 10,
          callbacks: {
            label: (tooltipItem) => valueFormatter(tooltipItem.parsed.y),
          },
        },
      },
      scales: {
        x: {
          grid: {
            display: false,
          },
          border: {
            display: false,
          },
          ticks: {
            color: "rgba(206, 214, 224, 0.58)",
            maxRotation: 0,
            autoSkip: true,
            maxTicksLimit: 6,
          },
        },
        y: {
          beginAtZero: true,
          border: {
            display: false,
          },
          grid: {
            color: "rgba(255, 255, 255, 0.06)",
            drawTicks: false,
          },
          ticks: {
            color: "rgba(206, 214, 224, 0.58)",
            padding: 8,
            callback: (tickValue) => valueFormatter(Number(tickValue || 0)),
          },
        },
      },
    },
  });
}

function filterAnalyticsPoints(points, days) {
  if (!Array.isArray(points) || !points.length || !days || points.length <= 1) {
    return Array.isArray(points) ? points : [];
  }
  const lastPoint = points[points.length - 1];
  const lastDate = new Date(`${lastPoint?.day || ""}T00:00:00Z`);
  if (Number.isNaN(lastDate.getTime())) {
    return points.slice(-days);
  }
  const cutoff = new Date(lastDate);
  cutoff.setUTCDate(cutoff.getUTCDate() - Math.max(days - 1, 0));
  return points.filter((point) => {
    const pointDate = new Date(`${point?.day || ""}T00:00:00Z`);
    return !Number.isNaN(pointDate.getTime()) && pointDate >= cutoff;
  });
}

function renderCountryConstellation(container, countries, { emptyLabel } = {}) {
  if (!Array.isArray(countries) || !countries.length) {
    container.textContent = emptyLabel || t("analytics.emptyCountries");
    container.classList.add("empty-state");
    return;
  }

  const normalizedCountries = countries.map((item) => ({
    country: item?.country || t("value.unknown"),
    users: Number(item?.users || 0),
  }));
  const [featuredCountry] = normalizedCountries;
  const shownTotal = normalizedCountries.reduce((sum, item) => sum + item.users, 0) || 1;
  const maxUsers = Math.max(...normalizedCountries.map((item) => item.users), 1);
  container.classList.remove("empty-state");
  container.innerHTML = `
    <div class="country-featured-card">
      <p class="panel-label">${escapeHtml(t("analytics.countryFeatured"))}</p>
      <div class="country-featured-grid">
        <div>
          <div class="country-featured-name">${escapeHtml(featuredCountry.country)}</div>
          <div class="country-featured-value">${escapeHtml(formatNumber(featuredCountry.users))}</div>
          <div class="country-featured-copy">${escapeHtml(
            t("analytics.countryUsers", { count: formatNumber(featuredCountry.users) }),
          )}</div>
        </div>
        <div class="country-featured-share">${escapeHtml(
          t("analytics.countryShare", {
            share: formatPercent(featuredCountry.users / shownTotal),
          }),
        )}</div>
      </div>
    </div>
    <div class="country-cluster">
      <p class="panel-label">${escapeHtml(t("analytics.countryListLabel"))}</p>
      ${normalizedCountries
        .map((item, index) => {
          const ratio = `${Math.max((item.users / maxUsers) * 100, 6)}%`;
          return `
            <div class="country-signal-row ${index === 0 ? "is-featured" : ""}">
              <div class="country-rank">${escapeHtml(`${index + 1}`)}</div>
              <div class="country-signal-copy">
                <div class="country-head">
                  <span class="country-name">${escapeHtml(item.country)}</span>
                  <span class="country-value">${escapeHtml(formatNumber(item.users))}</span>
                </div>
                <div class="country-meter"><span style="width:${ratio}"></span></div>
                <div class="country-foot">
                  <span>${escapeHtml(
                    t("analytics.countryUsers", { count: formatNumber(item.users) }),
                  )}</span>
                  <span>${escapeHtml(
                    t("analytics.countryShare", {
                      share: formatPercent(item.users / shownTotal),
                    }),
                  )}</span>
                </div>
              </div>
            </div>
          `;
        })
        .join("")}
    </div>
  `;
}

function renderUsage(overview) {
  const includes = getOverviewSectionIncludes(overview);
  const usage = overview.ai_usage || {};
  const usageLoaded = includes.aiUsage;
  const formatUsageDecimal = (value) => (
    value == null ? t("usage.na") : formatDecimal(value)
  );
  const formatUsageLatency = (value) => (
    value == null ? t("usage.na") : formatMilliseconds(value)
  );

  const metrics = [
    {
      label: t("usage.promptsToday"),
      value: usageLoaded ? formatNumber(usage.daily_request_count || 0) : t("overview.loading"),
    },
    {
      label: t("usage.promptsWeek"),
      value: usageLoaded ? formatNumber(usage.weekly_request_count || 0) : t("overview.loading"),
    },
    {
      label: t("usage.activeUsersToday"),
      value: usageLoaded ? formatNumber(usage.active_users_today || 0) : t("overview.loading"),
    },
    {
      label: t("usage.activeUsersWeek"),
      value: usageLoaded ? formatNumber(usage.active_users_week || 0) : t("overview.loading"),
    },
    {
      label: t("usage.avgPromptsPerUserToday"),
      value: usageLoaded ? formatUsageDecimal(usage.avg_prompts_per_user_today) : t("overview.loading"),
    },
    {
      label: t("usage.avgPromptsPerUserWeek"),
      value: usageLoaded ? formatUsageDecimal(usage.avg_prompts_per_user_week) : t("overview.loading"),
    },
    {
      label: t("usage.avgLatencyToday"),
      value: usageLoaded ? formatUsageLatency(usage.avg_latency_ms_today) : t("overview.loading"),
    },
    {
      label: t("usage.avgLatencyWeek"),
      value: usageLoaded ? formatUsageLatency(usage.avg_latency_ms_week) : t("overview.loading"),
    },
  ];

  elements.aiUsageMetrics.innerHTML = metrics
    .map(
      (metric) => `
        <div class="mini-metric">
          <div class="mini-label">${escapeHtml(metric.label)}</div>
          <div class="mini-value">${escapeHtml(metric.value)}</div>
        </div>
      `,
    )
    .join("");

  const features = Array.isArray(usage.top_features) ? usage.top_features : [];
  if (!usageLoaded) {
    elements.topFeatures.textContent = t("overview.loading");
    elements.topFeatures.classList.add("empty-state");
    return;
  }
  if (!features.length) {
    elements.topFeatures.textContent = t("usage.noFeatures");
    elements.topFeatures.classList.add("empty-state");
    return;
  }

  elements.topFeatures.classList.remove("empty-state");
  const maxCount = Math.max(...features.map((item) => Number(item.request_count || 0)), 1);
  elements.topFeatures.innerHTML = features
    .map((feature) => {
      const count = Number(feature.request_count || 0);
      const ratio = `${Math.max((count / maxCount) * 100, 2)}%`;
      return `
        <div class="feature-row">
          <div class="feature-head">
            <strong>${escapeHtml(feature.feature || t("value.unknown"))}</strong>
            <span>${escapeHtml(formatNumber(count))}</span>
          </div>
          <div class="meter"><span style="width:${ratio}"></span></div>
        </div>
      `;
    })
    .join("");
}

function renderAiObservability(aiObservability) {
  const observabilityLoaded = getOverviewSectionIncludes().aiObservability;
  const toolUsageRangeControlsHtml = AI_TOOL_USAGE_RANGE_OPTIONS
    .map((option) => {
      const activeClass = option.key === state.aiToolUsageRange ? " is-active" : "";
      return `
        <button
          type="button"
          class="range-chip${activeClass}"
          data-ai-tool-usage-range="${escapeHtml(option.key)}"
        >
          ${escapeHtml(option.label)}
        </button>
      `;
    })
    .join("");
  const backendTimings = aiObservability?.backend_timings || {};
  const dashboardMetrics = aiObservability?.dashboard_metrics || {};
  const dashboardTimings = dashboardMetrics?.timings || {};
  const exportUsage = dashboardMetrics?.export_usage || {};
  const exportTotals = exportUsage?.totals || {};
  const aiUsageMetrics = dashboardMetrics?.ai_usage || {};
  const aiUsageTotals = aiUsageMetrics?.totals || {};
  const formatUsd = (value) =>
    `$${new Intl.NumberFormat(state.locale, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 4,
    }).format(Number(value || 0))}`;
  const summaryCards = [
    {
      label: "Median full prompt time",
      value: observabilityLoaded
        ? formatMilliseconds(dashboardTimings?.prompt_cycle_total_ms?.p50 || 0)
        : t("overview.loading"),
    },
    {
      label: "Slow full prompt time (p95)",
      value: observabilityLoaded
        ? formatMilliseconds(dashboardTimings?.prompt_cycle_total_ms?.p95 || 0)
        : t("overview.loading"),
    },
    {
      label: "Median backend proxy time",
      value: observabilityLoaded
        ? formatMilliseconds(backendTimings?.proxy_handler_ms_total?.p50 || 0)
        : t("overview.loading"),
    },
    {
      label: "Slow backend proxy time (p95)",
      value: observabilityLoaded
        ? formatMilliseconds(backendTimings?.proxy_handler_ms_total?.p95 || 0)
        : t("overview.loading"),
    },
    {
      label: "Exports (wav/mp3)",
      value: observabilityLoaded
        ? `${formatWholeNumber(exportTotals?.exports_total || 0)} (${formatWholeNumber(
            exportTotals?.exports_wav || 0,
          )}/${formatWholeNumber(exportTotals?.exports_mp3 || 0)})`
        : t("overview.loading"),
    },
    {
      label: "Avg exports per user",
      value: observabilityLoaded
        ? formatDecimal(exportTotals?.avg_exports_per_user || 0)
        : t("overview.loading"),
    },
    {
      label: "AI prompts / user",
      value: observabilityLoaded
        ? formatDecimal(aiUsageTotals?.avg_prompts_per_user || 0)
        : t("overview.loading"),
    },
    {
      label: "AI tokens / user",
      value: observabilityLoaded
        ? formatWholeNumber(aiUsageTotals?.avg_tokens_per_user || 0)
        : t("overview.loading"),
    },
    {
      label: "Estimated AI $ / user",
      value: observabilityLoaded
        ? Number(aiUsageTotals?.avg_cost_usd_per_user || 0) > 0
          ? formatUsd(aiUsageTotals?.avg_cost_usd_per_user || 0)
          : t("usage.na")
        : t("overview.loading"),
    },
  ];

  elements.aiObservabilitySummary.innerHTML = summaryCards
    .map(
      (metric) => `
        <div class="mini-metric">
          <div class="mini-label">${escapeHtml(metric.label)}</div>
          <div class="mini-value">${escapeHtml(metric.value)}</div>
        </div>
      `,
    )
    .join("");

  const dashboardStatus = `${aiObservability?.dashboard_status || ""}`.trim();
  const runtimeSuccess = Array.isArray(dashboardMetrics?.runtime_success)
    ? dashboardMetrics.runtime_success
    : [];
  const promptToolUsage = Array.isArray(dashboardMetrics?.prompt_tool_usage)
    ? dashboardMetrics.prompt_tool_usage
    : [];
  const promptToolUsageRange = dashboardMetrics?.prompt_tool_usage_range || {};
  const magnitudeModelUsage = Array.isArray(dashboardMetrics?.magnitude_model_usage)
    ? dashboardMetrics.magnitude_model_usage
    : [];
  const magnitudeModelUpdates = Array.isArray(dashboardMetrics?.magnitude_model_updates)
    ? dashboardMetrics.magnitude_model_updates
    : [];
  const exportByUserType = Array.isArray(exportUsage?.by_user_type)
    ? exportUsage.by_user_type
    : [];
  const aiUsageByUserType = Array.isArray(aiUsageMetrics?.by_user_type)
    ? aiUsageMetrics.by_user_type
    : [];
  const recentTracesMeta = aiObservability?.recent_traces_meta || {};
  const countGroups = aiObservability?.counts || {};
  const countSections = [
    {
      title: "AI setups",
      items: Array.isArray(countGroups.runtime_config_fingerprint)
        ? countGroups.runtime_config_fingerprint
        : [],
      valueKey: "value",
      formatter: (value) => shortenIdentifier(value, 10, 4),
    },
    {
      title: "LLM models",
      items: Array.isArray(countGroups.effective_model) ? countGroups.effective_model : [],
      valueKey: "value",
      formatter: (value) => `${value || "unknown"}`,
    },
  ];

  const runtimeSuccessHtml = runtimeSuccess.length
    ? `
      <div class="subsection compact-subsection">
        <div class="subsection-header">
          <div>
            <h3>AI setup success</h3>
            <p class="subsection-meta">30-day success and failure rate for each backend AI setup.</p>
          </div>
        </div>
        <div class="feature-list">
          ${runtimeSuccess
            .map(
              (row) => `
                <div class="feature-row">
                  <div class="feature-head">
                    <strong>${escapeHtml(shortenIdentifier(row.runtime_config_fingerprint || "unknown", 10, 4))}</strong>
                    <span>${escapeHtml(`${formatDecimal(row.success_rate || 0)}%`)}</span>
                  </div>
                  <div class="meter"><span style="width:${Math.max(Number(row.success_rate || 0), 2)}%"></span></div>
                </div>
              `,
            )
            .join("")}
        </div>
      </div>
    `
    : "";

  const promptToolUsageHtml = `
      <div class="subsection compact-subsection">
        <div class="subsection-header">
          <div>
            <h3>Prompt tools used</h3>
            <p class="subsection-meta">Server-side counts from PostHog. Monthly is the default to keep this cheap; all time only loads when selected.</p>
          </div>
          <div class="range-controls">${toolUsageRangeControlsHtml}</div>
        </div>
        ${
          promptToolUsage.length
            ? `<div class="feature-list">
                ${promptToolUsage
                  .map((row) => {
                    const count = Number(row.count || 0);
                    const maxCount = Math.max(...promptToolUsage.map((item) => Number(item.count || 0)), 1);
                    const ratio = `${Math.max((count / maxCount) * 100, 2)}%`;
                    return `
                      <div class="feature-row">
                        <div class="feature-head">
                          <strong>${escapeHtml(row.tool_name || "unknown")}</strong>
                          <span>${escapeHtml(formatNumber(count))}</span>
                        </div>
                        <div class="meter"><span style="width:${ratio}"></span></div>
                      </div>
                    `;
                  })
                  .join("")}
              </div>`
            : `<div class="empty-state">No tool usage found for ${escapeHtml(promptToolUsageRange?.label || "this range")}.</div>`
        }
      </div>
    `;

  const exportUsageHtml = `
      <div class="subsection compact-subsection">
        <div class="subsection-header">
          <div>
            <h3>Export usage by user type</h3>
            <p class="subsection-meta">Completed wav/mp3 exports and average exports per user segment.</p>
          </div>
        </div>
        ${
          exportByUserType.length
            ? `<div class="feature-list">
                ${exportByUserType
                  .map((row) => {
                    const count = Number(row.exports_total || 0);
                    const maxCount = Math.max(...exportByUserType.map((item) => Number(item.exports_total || 0)), 1);
                    const ratio = `${Math.max((count / maxCount) * 100, 2)}%`;
                    return `
                      <div class="feature-row">
                        <div class="feature-head">
                          <strong>${escapeHtml(formatMusicProfileLabel(row.user_type || "unknown"))}</strong>
                          <span>${escapeHtml(
                            `${formatWholeNumber(count)} exports • ${formatDecimal(row.avg_exports_per_user || 0)}/user`,
                          )}</span>
                        </div>
                        <div class="meter"><span style="width:${ratio}"></span></div>
                        <div class="user-subtext">${escapeHtml(
                          `${formatWholeNumber(row.exports_wav || 0)} wav • ${formatWholeNumber(row.exports_mp3 || 0)} mp3`,
                        )}</div>
                      </div>
                    `;
                  })
                  .join("")}
              </div>`
            : `<div class="empty-state">No export data found for ${escapeHtml(promptToolUsageRange?.label || "this range")}.</div>`
        }
      </div>
    `;

  const aiUsageByTypeHtml = `
      <div class="subsection compact-subsection">
        <div class="subsection-header">
          <div>
            <h3>AI usage by user type</h3>
            <p class="subsection-meta">Prompts, tokens, and estimated AI cost segmented by profile type.</p>
          </div>
        </div>
        ${
          aiUsageByUserType.length
            ? `<div class="feature-list">
                ${aiUsageByUserType
                  .map((row) => {
                    const prompts = Number(row.prompts_total || 0);
                    const maxPrompts = Math.max(...aiUsageByUserType.map((item) => Number(item.prompts_total || 0)), 1);
                    const ratio = `${Math.max((prompts / maxPrompts) * 100, 2)}%`;
                    const avgCostPerUser = Number(row.avg_cost_usd_per_user || 0);
                    const costLabel = avgCostPerUser > 0 ? formatUsd(avgCostPerUser) : t("usage.na");
                    return `
                      <div class="feature-row">
                        <div class="feature-head">
                          <strong>${escapeHtml(formatMusicProfileLabel(row.user_type || "unknown"))}</strong>
                          <span>${escapeHtml(
                            `${formatWholeNumber(prompts)} prompts • ${formatWholeNumber(row.tokens_total || 0)} tokens`,
                          )}</span>
                        </div>
                        <div class="meter"><span style="width:${ratio}"></span></div>
                        <div class="user-subtext">${escapeHtml(
                          `${formatDecimal(row.avg_prompts_per_user || 0)} prompts/user • ${formatWholeNumber(
                            row.avg_tokens_per_user || 0,
                          )} tokens/user • ${costLabel}/user`,
                        )}</div>
                      </div>
                    `;
                  })
                  .join("")}
              </div>`
            : `<div class="empty-state">No AI usage data found for ${escapeHtml(promptToolUsageRange?.label || "this range")}.</div>`
        }
      </div>
    `;

  const magnitudeUsageHtml = magnitudeModelUsage.length
    ? `
      <div class="subsection compact-subsection">
        <div class="subsection-header">
          <div>
            <h3>Magnitude model usage</h3>
            <p class="subsection-meta">30-day prompt completions grouped by active bundle version and source.</p>
          </div>
        </div>
        <div class="feature-list">
          ${magnitudeModelUsage
            .map((row) => {
              const label = `${row.bundle_version || "unknown"} • ${row.source || "unknown"}`;
              return `
                <div class="feature-row">
                  <div class="feature-head">
                    <strong>${escapeHtml(label)}</strong>
                    <span>${escapeHtml(formatNumber(row.count || 0))}</span>
                  </div>
                </div>
              `;
            })
            .join("")}
        </div>
      </div>
    `
    : "";

  const magnitudeUpdateHtml = magnitudeModelUpdates.length
    ? `
      <div class="subsection compact-subsection">
        <div class="subsection-header">
          <div>
            <h3>Magnitude model updates</h3>
            <p class="subsection-meta">Background manifest/download results from clients.</p>
          </div>
        </div>
        <div class="feature-list">
          ${magnitudeModelUpdates
            .map((row) => {
              const label = `${row.status || "unknown"} • ${row.bundle_version || "unknown"}`;
              return `
                <div class="feature-row">
                  <div class="feature-head">
                    <strong>${escapeHtml(label)}</strong>
                    <span>${escapeHtml(formatNumber(row.count || 0))}</span>
                  </div>
                </div>
              `;
            })
            .join("")}
        </div>
      </div>
    `
    : "";

  const countsHtml = countSections
    .map((section) => {
      if (!Array.isArray(section.items) || !section.items.length) {
        return `
          <div class="subsection compact-subsection">
            <div class="subsection-header">
              <div>
                <h3>${escapeHtml(section.title)}</h3>
              </div>
            </div>
            <div class="empty-state">${escapeHtml("No data yet.")}</div>
          </div>
        `;
      }
      const maxCount = Math.max(...section.items.map((item) => Number(item.count || 0)), 1);
      return `
        <div class="subsection compact-subsection">
          <div class="subsection-header">
            <div>
              <h3>${escapeHtml(section.title)}</h3>
            </div>
          </div>
          <div class="feature-list">
            ${section.items
              .map((item) => {
                const count = Number(item.count || 0);
                const ratio = `${Math.max((count / maxCount) * 100, 2)}%`;
                return `
                  <div class="feature-row">
                    <div class="feature-head">
                      <strong>${escapeHtml(section.formatter(item[section.valueKey]))}</strong>
                      <span>${escapeHtml(formatNumber(count))}</span>
                    </div>
                    <div class="meter"><span style="width:${ratio}"></span></div>
                  </div>
                `;
              })
              .join("")}
          </div>
        </div>
      `;
    })
    .join("");

  if (!observabilityLoaded) {
    elements.aiObservabilityCounts.classList.add("empty-state");
    elements.aiObservabilityCounts.textContent = t("overview.loading");
  } else {
    elements.aiObservabilityCounts.classList.remove("empty-state");
    elements.aiObservabilityCounts.innerHTML = `${runtimeSuccessHtml}${promptToolUsageHtml}${exportUsageHtml}${aiUsageByTypeHtml}${magnitudeUsageHtml}${magnitudeUpdateHtml}${countsHtml}`;
  }

  const traces = Array.isArray(aiObservability?.recent_traces)
    ? aiObservability.recent_traces
    : [];
  if (!observabilityLoaded) {
    elements.aiObservabilityTracesBody.innerHTML = `
      <tr>
        <td colspan="6" class="table-empty">${escapeHtml(t("overview.loading"))}</td>
      </tr>
    `;
  } else if (!traces.length) {
    elements.aiObservabilityTracesBody.innerHTML = `
      <tr>
        <td colspan="6" class="table-empty">${escapeHtml("No prompt traces yet.")}</td>
      </tr>
    `;
  } else {
    elements.aiObservabilityTracesBody.innerHTML = traces
      .map(
        (trace) => `
          <tr>
            <td>
              <div class="user-name">${escapeHtml(shortenIdentifier(trace.prompt_trace_id || trace.request_id || "unknown", 10, 4))}</div>
              <div class="user-subtext">${escapeHtml(shortenIdentifier(trace.request_id || "", 10, 4))}</div>
            </td>
            <td>${escapeHtml(trace.status || "unknown")}</td>
            <td>
              <div class="user-name">${escapeHtml(trace.effective_model || "unknown")}</div>
              <div class="user-subtext">${escapeHtml(shortenIdentifier(trace.runtime_config_fingerprint || "unknown", 10, 4))}</div>
            </td>
            <td>${escapeHtml(trace.resolved_tool || "unknown")}</td>
            <td>
              <div class="user-name">${escapeHtml(
                `proxy ${formatWholeNumber(trace.proxy_handler_ms_total || 0)}ms`,
              )}</div>
              <div class="user-subtext">${escapeHtml(
                `provider ${formatWholeNumber(trace.provider_roundtrip_ms || 0)}ms • normalize ${formatWholeNumber(trace.response_normalize_ms || 0)}ms`,
              )}</div>
            </td>
            <td>${escapeHtml(formatDate(trace.created_at))}</td>
          </tr>
        `,
      )
      .join("");
  }

  renderAiObservabilityTracePagination(
    observabilityLoaded ? Number(recentTracesMeta?.shown_count || traces.length || 0) : 0,
    observabilityLoaded ? Number(recentTracesMeta?.total_count || traces.length || 0) : 0,
    observabilityLoaded && recentTracesMeta?.has_more === true,
  );

  if (!observabilityLoaded) {
    elements.aiObservabilityMeta.textContent = t("overview.loading");
  } else if (dashboardStatus === "live") {
    elements.aiObservabilityMeta.textContent = `Full prompt time includes app work, network, backend, and apply. Backend proxy time is one slice inside it. Updated ${formatDate(
      aiObservability?.dashboard_updated_at || "",
    )}`;
  } else {
    elements.aiObservabilityMeta.textContent = "Full prompt time is the end-to-end user wait. Backend proxy time is only the server slice.";
  }
}

function renderTiers(tiers) {
  if (!Array.isArray(tiers) || !tiers.length) {
    elements.tierBreakdown.textContent = t("tiers.noData");
    elements.tierBreakdown.classList.add("empty-state");
    return;
  }

  const maxUsers = Math.max(...tiers.map((tier) => Number(tier.user_count || 0)), 1);
  elements.tierBreakdown.classList.remove("empty-state");
  elements.tierBreakdown.innerHTML = tiers
    .map((tier) => {
      const userCount = Number(tier.user_count || 0);
      const activeCount = Number(tier.active_user_count || 0);
      const ratio = `${Math.max((userCount / maxUsers) * 100, 2)}%`;
      return `
        <div class="tier-row">
          <div class="tier-head">
            <span class="tier-chip">${escapeHtml(formatTierLabel(tier.plan_code || tier.tier || "free"))}</span>
            <span>${escapeHtml(
              t("tiers.usersActive", {
                users: formatNumber(userCount),
                active: formatNumber(activeCount),
              }),
            )}</span>
          </div>
          <div class="meter"><span style="width:${ratio}"></span></div>
        </div>
      `;
    })
    .join("");
}

function renderTrackedUsers(users) {
  const includes = getOverviewSectionIncludes();
  if (!includes.users) {
    elements.trackedUsersTableBody.innerHTML = `
      <tr>
        <td colspan="7" class="table-empty">${escapeHtml(t("overview.loading"))}</td>
      </tr>
    `;
    renderTrackedUsersPagination(0);
    return;
  }
  if (!Array.isArray(users) || !users.length) {
    elements.trackedUsersTableBody.innerHTML = `
      <tr>
        <td colspan="7" class="table-empty">${escapeHtml(t("trackedUsers.none"))}</td>
      </tr>
    `;
    renderTrackedUsersPagination(0);
    return;
  }

  elements.trackedUsersTableBody.innerHTML = users
    .map((user) => {
      const displayName = user.display_name || user.email || user.user_id || t("value.unknown");
      const emailOrId = user.email || user.user_id || t("detail.na");
      const tierClass = badgeClass(user.subscription_tier || "free");
      const statusClass = badgeClass(user.subscription_status || "unknown", "status-");

      return `
        <tr>
          <td>
            <div class="user-name">${escapeHtml(displayName)}</div>
            <div class="user-subtext">${escapeHtml(emailOrId)}</div>
            <div class="user-badges">
              <span class="badge ${tierClass}">${escapeHtml(
                formatTierLabel(user.subscription_tier || "free"),
              )}</span>
              <span class="badge ${statusClass}">${escapeHtml(
                formatStatusLabel(user.subscription_status || "unknown"),
              )}</span>
            </div>
          </td>
          <td>${escapeHtml(formatTierLabel(user.subscription_tier || "free"))}</td>
          <td>${escapeHtml(formatStatusLabel(user.subscription_status || "unknown"))}</td>
          <td>${escapeHtml(formatNumber(user.ai_request_count || 0))}</td>
          <td>${escapeHtml(formatNumber(user.ai_credits_used_today || 0))}</td>
          <td>${escapeHtml(formatNumber(user.ai_tokens_used_month || 0))}</td>
          <td>${escapeHtml(formatDate(user.last_seen_at))}</td>
        </tr>
      `;
    })
    .join("");
  renderTrackedUsersPagination(users.length);
}

function renderProjects(projects) {
  const includes = getOverviewSectionIncludes();
  if (!includes.projects) {
    elements.projectsTableBody.innerHTML = `
      <tr>
        <td colspan="6" class="table-empty">${escapeHtml(t("overview.loading"))}</td>
      </tr>
    `;
    renderProjectsPagination(0);
    return;
  }
  if (!Array.isArray(projects) || !projects.length) {
    elements.projectsTableBody.innerHTML = `
      <tr>
        <td colspan="6" class="table-empty">${escapeHtml(t("projects.none"))}</td>
      </tr>
    `;
    renderProjectsPagination(0);
    return;
  }

  elements.projectsTableBody.innerHTML = projects
    .map(
      (project) => `
        <tr>
          <td>
            <div class="user-name">${escapeHtml(project.project_id || t("value.unknown"))}</div>
            <div class="user-subtext">${escapeHtml(
              t("projects.lastUser", { user: project.last_user_id || t("detail.na") }),
            )}</div>
          </td>
          <td>${escapeHtml(formatNumber(project.request_count || 0))}</td>
          <td>${escapeHtml(formatNumber(project.unique_user_count || 0))}</td>
          <td>${escapeHtml(formatNumber(project.credits_charged_total || 0))}</td>
          <td>${escapeHtml(formatNumber(project.tokens_total || 0))}</td>
          <td>${escapeHtml(formatDate(project.last_activity_at))}</td>
        </tr>
      `,
    )
    .join("");
  renderProjectsPagination(projects.length);
}

function renderUserSearchMeta(payload) {
  const warnings = Array.isArray(payload.warnings) ? payload.warnings : [];
  const detail = state.currentSearchQuery
    ? t("search.meta", { query: state.currentSearchQuery })
    : t("search.recentAccounts");
  elements.userSearchMeta.textContent = warnings.length
    ? `${detail} • ${warnings.join(" • ")}`
    : detail;
}

function renderAdminUsers(users) {
  if (!tokens?.idToken) {
    elements.adminUsersTableBody.innerHTML = `
      <tr>
        <td colspan="5" class="table-empty">${escapeHtml(t("empty.signInSearchUsers"))}</td>
      </tr>
    `;
    renderAdminUsersPagination(0, 0, false);
    return;
  }

  if (!Array.isArray(users) || !users.length) {
    elements.adminUsersTableBody.innerHTML = `
      <tr>
        <td colspan="5" class="table-empty">${escapeHtml(t("adminUsers.none"))}</td>
      </tr>
    `;
    renderAdminUsersPagination(0, Number(state.lastUserSearchPayload?.total_matches || 0), false);
    return;
  }

  elements.adminUsersTableBody.innerHTML = users
    .map((user) => {
      const selectedClass = user.user_id === state.selectedUserId ? "is-selected" : "";
      const name = user.display_name || user.email || user.user_id || t("value.unknown");
      const authClass = badgeClass(user.auth_provider || "email", "auth-");
      const authSourceClass = badgeClass(user.auth_source || "unknown", "status-");
      const subscriptionTierClass = badgeClass(user.subscription_tier || "free");
      const subscriptionStatusClass = badgeClass(user.subscription_status || "unknown", "status-");
      const onboardingClass = badgeClass(user.onboarding_state || "unknown", "state-");
      const usernameLine = user.username
        ? t("user.usernameLine", { value: user.username })
        : t("user.userIdLine", { value: user.user_id });
      const linkedProviders = Array.isArray(user.linked_providers) ? user.linked_providers : [];

      return `
        <tr class="${selectedClass}" data-user-id="${escapeHtml(user.user_id || "")}">
          <td>
            <div class="user-name">${escapeHtml(name)}</div>
            <div class="user-subtext">${escapeHtml(user.email || user.user_id || t("detail.na"))}</div>
            <div class="user-subtext">${escapeHtml(usernameLine)}</div>
          </td>
          <td>
            <div class="user-badges">
              <span class="badge ${authClass}">${escapeHtml(
                formatProviderLabel(user.auth_provider || "email"),
              )}</span>
              <span class="badge ${authSourceClass}">${escapeHtml(formatAuthSourceLabel(user.auth_source))}</span>
              ${linkedProviders
                .map((provider) => `<span class="badge">${escapeHtml(formatProviderLabel(provider))}</span>`)
                .join("")}
            </div>
          </td>
          <td>
            <div class="user-badges">
              <span class="badge ${subscriptionTierClass}">${escapeHtml(
                formatTierLabel(user.subscription_tier || "free"),
              )}</span>
              <span class="badge ${subscriptionStatusClass}">${escapeHtml(
                formatStatusLabel(user.subscription_status || "unknown"),
              )}</span>
            </div>
          </td>
          <td>
            <div class="user-badges">
              <span class="badge ${onboardingClass}">${escapeHtml(
                formatOnboardingLabel(user.onboarding_state || "unknown"),
              )}</span>
              <span class="badge">${escapeHtml(formatStatusLabel(user.profile_status || "active"))}</span>
            </div>
          </td>
          <td>${escapeHtml(formatDate(user.last_seen_at || user.updated_at || user.created_at))}</td>
        </tr>
      `;
    })
    .join("");
  renderAdminUsersPagination(
    users.length,
    Number(state.lastUserSearchPayload?.total_matches || users.length),
    state.lastUserSearchPayload?.has_more === true,
  );
}

function renderFeedbackTable(submissions) {
  if (!tokens?.idToken) {
    elements.feedbackTableBody.innerHTML = `
      <tr>
        <td colspan="5" class="table-empty">${escapeHtml(t("empty.signInFeedback"))}</td>
      </tr>
    `;
    renderFeedbackPagination(0, false);
    return;
  }

  if (!Array.isArray(submissions) || !submissions.length) {
    elements.feedbackTableBody.innerHTML = `
      <tr>
        <td colspan="5" class="table-empty">${escapeHtml(t("feedback.none"))}</td>
      </tr>
    `;
    renderFeedbackPagination(0, false);
    return;
  }

  elements.feedbackTableBody.innerHTML = submissions
    .map((submission) => {
      const selectedClass =
        submission.submission_id === state.selectedFeedbackId ? "is-selected" : "";
      const attachments = [];
      if (submission.has_context) {
        attachments.push(t("feedback.attachments.context"));
      }
      if (submission.has_screenshot) {
        attachments.push(t("feedback.attachments.screenshot"));
      }
      return `
        <tr class="${selectedClass}" data-submission-id="${escapeHtml(
          submission.submission_id || "",
        )}">
          <td>
            <span class="badge">${escapeHtml(formatFeedbackCategory(submission.category))}</span>
            <div class="user-subtext" style="margin-top:8px;">${escapeHtml(
              formatFeedbackSource(submission.source),
            )}</div>
          </td>
          <td>
            <div class="user-name">${escapeHtml(
              submission.display_name ||
                submission.user_email ||
                submission.user_id ||
                t("detail.na"),
            )}</div>
            <div class="user-subtext">${escapeHtml(
              submission.user_email || submission.user_id || t("detail.na"),
            )}</div>
          </td>
          <td><div class="feedback-preview">${escapeHtml(
            submission.message_preview || t("detail.na"),
          )}</div></td>
          <td>${escapeHtml(
            attachments.length
              ? attachments.join(" • ")
              : t("feedback.attachments.none"),
          )}</td>
          <td>${escapeHtml(formatDate(submission.created_at))}</td>
        </tr>
      `;
    })
    .join("");
  renderFeedbackPagination(
    submissions.length,
    state.lastFeedbackPayload?.has_more === true,
  );
}

function renderAdminUsersPagination(shownCount, totalCount, hasMore) {
  const signedIn = !!tokens?.idToken;
  elements.adminUsersPageMeta.textContent = shownCount
    ? t("value.showingOfTotal", {
        shown: formatWholeNumber(shownCount),
        total: formatWholeNumber(Math.max(totalCount || 0, shownCount)),
      })
    : "";
  elements.adminUsersShowLessButton.disabled =
    !signedIn || state.userSearchBusy || state.userSearchLimit <= DEFAULT_ADMIN_USERS_LIMIT;
  elements.adminUsersShowMoreButton.disabled =
    !signedIn || state.userSearchBusy || !hasMore || state.userSearchLimit >= RESULT_LIMIT_MAX;
}

function renderFeedbackPagination(shownCount, hasMore) {
  const signedIn = !!tokens?.idToken;
  elements.feedbackPageMeta.textContent = shownCount
    ? t("value.showingCount", {
        shown: formatWholeNumber(shownCount),
      })
    : "";
  elements.feedbackShowLessButton.disabled =
    !signedIn || state.feedbackBusy || state.feedbackLimit <= DEFAULT_FEEDBACK_LIMIT;
  elements.feedbackShowMoreButton.disabled =
    !signedIn || state.feedbackBusy || !hasMore || state.feedbackLimit >= RESULT_LIMIT_MAX;
}

function renderTrackedUsersPagination(shownCount) {
  const signedIn = !!tokens?.idToken;
  if (state.homeSectionLoading.users) {
    elements.trackedUsersPageMeta.textContent = t("overview.loading");
    elements.trackedUsersShowLessButton.disabled = true;
    elements.trackedUsersShowMoreButton.disabled = !signedIn || state.overviewBusy;
    return;
  }
  const canShowMore =
    Array.isArray(state.overview?.users)
    && state.overview.users.length >= state.overviewUserLimit
    && state.overviewUserLimit < RESULT_LIMIT_MAX;
  elements.trackedUsersPageMeta.textContent = shownCount
    ? t("value.showingCount", {
        shown: formatWholeNumber(shownCount),
      })
    : "";
  elements.trackedUsersShowLessButton.disabled =
    !signedIn || state.overviewBusy || state.overviewUserLimit <= DEFAULT_OVERVIEW_USERS_LIMIT;
  elements.trackedUsersShowMoreButton.disabled =
    !signedIn || state.overviewBusy || !canShowMore;
}

function renderProjectsPagination(shownCount) {
  const signedIn = !!tokens?.idToken;
  if (state.homeSectionLoading.projects) {
    elements.projectsPageMeta.textContent = t("overview.loading");
    elements.projectsShowLessButton.disabled = true;
    elements.projectsShowMoreButton.disabled = !signedIn || state.overviewBusy;
    return;
  }
  const canShowMore =
    Array.isArray(state.overview?.projects)
    && state.overview.projects.length >= state.overviewProjectLimit
    && state.overviewProjectLimit < RESULT_LIMIT_MAX;
  elements.projectsPageMeta.textContent = shownCount
    ? t("value.showingCount", {
        shown: formatWholeNumber(shownCount),
      })
    : "";
  elements.projectsShowLessButton.disabled =
    !signedIn || state.overviewBusy || state.overviewProjectLimit <= DEFAULT_OVERVIEW_PROJECTS_LIMIT;
  elements.projectsShowMoreButton.disabled =
    !signedIn || state.overviewBusy || !canShowMore;
}

function renderAiObservabilityTracePagination(shownCount, totalCount, hasMore) {
  const signedIn = !!tokens?.idToken;
  if (state.homeSectionLoading.observability) {
    elements.aiObservabilityTracePageMeta.textContent = t("overview.loading");
    elements.aiObservabilityTracesShowLessButton.disabled = true;
    elements.aiObservabilityTracesShowMoreButton.disabled = !signedIn || state.overviewBusy;
    return;
  }
  elements.aiObservabilityTracePageMeta.textContent = shownCount
    ? t("value.showingOfTotal", {
        shown: formatWholeNumber(shownCount),
        total: formatWholeNumber(Math.max(totalCount || 0, shownCount)),
      })
    : "";
  elements.aiObservabilityTracesShowLessButton.disabled =
    !signedIn || state.overviewBusy || state.overviewTraceLimit <= DEFAULT_OVERVIEW_TRACE_LIMIT;
  elements.aiObservabilityTracesShowMoreButton.disabled =
    !signedIn || state.overviewBusy || !hasMore || state.overviewTraceLimit >= 24;
}

function renderInspector() {
  const user = getSelectedUser();
  if (!user) {
    elements.userInspector.className = "inspector-empty";
    elements.userInspector.innerHTML = escapeHtml(t("empty.selectUser"));
    return;
  }

  const deleteFeedback =
    state.deleteFeedback && state.deleteFeedback.userId === user.user_id
      ? state.deleteFeedback
      : null;
  const grantFeedback =
    state.grantFeedback && state.grantFeedback.userId === user.user_id
      ? state.grantFeedback
      : null;
  const overrideFeedback =
    state.overrideFeedback && state.overrideFeedback.userId === user.user_id
      ? state.overrideFeedback
      : null;
  const readOnlyAiSupport = !canGrantAiPrompts();
  const readOnlyEntitlementOverride = !canApplyEntitlementOverrides();
  const confirmValue = inspectorConfirmValue(user);
  const adminFirstName = currentAdminFirstName();
  const defaultOverrideExpiry = toDateTimeLocalValue(addDays(new Date(), 7));
  const providerBadges = (Array.isArray(user.linked_providers) ? user.linked_providers : [])
    .map((provider) => `<span class="badge">${escapeHtml(formatProviderLabel(provider))}</span>`)
    .join("");
  const authSourceClass = badgeClass(user.auth_source || "unknown", "status-");

  elements.userInspector.className = "";
  elements.userInspector.innerHTML = `
    <div class="inspector-stack">
      <div class="inspector-heading">
        <div class="inspector-title">${escapeHtml(
          user.display_name || user.email || user.user_id || t("inspector.selectedUser"),
        )}</div>
        <div class="inspector-subtitle">
          ${escapeHtml(user.email || t("inspector.noEmail"))}
          ${user.username ? ` • ${escapeHtml(user.username)}` : ""}
        </div>
        <div class="provider-list">
          <span class="badge ${badgeClass(user.auth_provider || "email", "auth-")}">${escapeHtml(
            formatProviderLabel(user.auth_provider || "email"),
          )}</span>
          <span class="badge ${authSourceClass}">${escapeHtml(
            formatAuthSourceLabel(user.auth_source),
          )}</span>
          ${providerBadges}
        </div>
      </div>

      ${
        grantFeedback
          ? `<div class="status-panel status-${escapeHtml(grantFeedback.tone || "success")}">${escapeHtml(
              grantFeedback.message || "",
            )}</div>`
          : ""
      }

      <div class="inspector-grid">
        ${detailCard(t("detail.userId"), user.user_id)}
        ${detailCard(t("detail.name"), user.display_name || t("detail.na"))}
        ${detailCard(t("detail.username"), user.username || t("detail.na"))}
        ${detailCard(t("detail.birthdate"), formatBirthdateLabel(user.birthdate || ""))}
        ${detailCard(t("detail.age"), formatAgeLabel(user.birthdate || ""))}
        ${detailCard(
          t("detail.musicProfile"),
          formatMusicProfileLabel(user.music_profile || ""),
        )}
        ${detailCard(t("detail.appAuth"), formatAppAuthSummary(user))}
        ${detailCard(t("detail.emailVerification"), formatEmailVerification(user))}
        ${detailCard(t("detail.nativeSessions"), formatNativeSessionSummary(user))}
        ${detailCard(t("detail.legacyCognito"), formatLegacyCognitoSummary(user))}
        ${detailCard(
          t("detail.subscription"),
          `${formatTierLabel(user.subscription_tier || "free")} • ${formatStatusLabel(
            user.subscription_status || "unknown",
          )}`,
        )}
        ${detailCard(t("detail.onboarding"), formatOnboardingLabel(user.onboarding_state || "unknown"))}
        ${detailCard(
          t("detail.aiPrompts"),
          t("value.todayWeek", {
            today: formatWholeNumber(user.ai_prompts_used_today || 0),
            week: formatWholeNumber(user.ai_prompts_used_week || 0),
          }),
        )}
        ${detailCard(
          t("detail.extraPromptBank"),
          t("value.remainingGranted", {
            remaining: formatWholeNumber(user.admin_prompt_grants_remaining || 0),
            granted: formatWholeNumber(user.admin_prompt_grants_total || 0),
          }),
        )}
        ${detailCard(t("detail.lastSeen"), formatDate(user.last_seen_at || user.updated_at || user.created_at))}
        ${detailCard(t("detail.created"), formatDate(user.created_at))}
        ${detailCard(t("detail.updated"), formatDate(user.updated_at))}
      </div>

      ${
        overrideFeedback
          ? `<div class="status-panel status-${escapeHtml(overrideFeedback.tone || "success")}">${escapeHtml(
              overrideFeedback.message || "",
            )}</div>`
          : ""
      }

      <div class="delete-card support-card entitlement-override-card">
        <p class="panel-label">${escapeHtml(t("override.label"))}</p>
        <h3>${escapeHtml(t("override.title"))}</h3>
        <p class="delete-copy">${escapeHtml(t("override.copy"))}</p>
        ${
          readOnlyEntitlementOverride
            ? `<p class="delete-copy">${escapeHtml(t("override.readOnly"))}</p>`
            : ""
        }
        <form id="entitlement-override-form" class="form-stack" data-user-id="${escapeHtml(user.user_id || "")}">
          <div class="form-grid">
            <label class="search-input-wrap">
              <span class="search-label">${escapeHtml(t("override.plan"))}</span>
              <select class="select-input" name="planCode" ${readOnlyEntitlementOverride ? "disabled" : ""}>
                ${buildEntitlementOverridePlanOptions()}
              </select>
            </label>
            <label class="search-input-wrap">
              <span class="search-label">${escapeHtml(t("override.seats"))}</span>
              <input
                class="text-input"
                type="number"
                name="seatLimit"
                min="1"
                step="1"
                value="5"
                ${readOnlyEntitlementOverride ? "disabled" : ""}
              />
            </label>
          </div>
          <p class="field-help">${escapeHtml(t("override.seatsHelp"))}</p>
          <label class="search-input-wrap">
            <span class="search-label">${escapeHtml(t("override.organizationName"))}</span>
            <input
              class="text-input"
              type="text"
              name="organizationName"
              placeholder="${escapeHtml(t("override.organizationNamePlaceholder"))}"
              ${readOnlyEntitlementOverride ? "disabled" : ""}
            />
          </label>
          <label class="search-input-wrap">
            <span class="search-label">${escapeHtml(t("override.expiry"))}</span>
            <input
              class="text-input"
              type="datetime-local"
              name="expiresAt"
              value="${escapeHtml(defaultOverrideExpiry)}"
              ${readOnlyEntitlementOverride ? "disabled" : ""}
              required
            />
          </label>
          <div class="duration-row">
            ${ENTITLEMENT_OVERRIDE_DURATION_OPTIONS.map(
              (option) => `<button
                class="button button-secondary button-compact"
                type="button"
                data-override-duration-days="${option.days}"
                ${readOnlyEntitlementOverride ? "disabled" : ""}
              >${escapeHtml(t(option.labelKey))}</button>`,
            ).join("")}
          </div>
          <label class="search-input-wrap">
            <span class="search-label">${escapeHtml(t("override.reason"))}</span>
            <textarea
              class="text-area"
              name="reason"
              placeholder="${escapeHtml(t("override.reasonPlaceholder"))}"
              ${readOnlyEntitlementOverride ? "disabled" : ""}
              required
            ></textarea>
          </label>
          <label class="search-input-wrap">
            <span class="search-label">${escapeHtml(t("override.confirmIdentifier"))}</span>
            <input
              class="text-input"
              type="text"
              name="confirmIdentifier"
              autocomplete="off"
              ${readOnlyEntitlementOverride ? "disabled" : ""}
              required
            />
          </label>
          <label class="search-input-wrap">
            <span class="search-label">${escapeHtml(
              t("override.confirmAdminName", { value: adminFirstName || t("detail.na") }),
            )}</span>
            <input
              class="text-input"
              type="text"
              name="confirmAdminFirstName"
              autocomplete="off"
              ${readOnlyEntitlementOverride ? "disabled" : ""}
              required
            />
          </label>
          <div class="search-actions">
            <button
              class="button button-secondary"
              type="submit"
              ${state.overrideBusy || readOnlyEntitlementOverride ? "disabled" : ""}
            >
              ${escapeHtml(state.overrideBusy ? t("override.applying") : t("override.button"))}
            </button>
          </div>
        </form>
      </div>

      <div class="delete-card support-card">
        <p class="panel-label">${escapeHtml(t("support.label"))}</p>
        <h3>${escapeHtml(t("support.title"))}</h3>
        <p class="delete-copy">${escapeHtml(t("support.copy"))}</p>
        ${readOnlyAiSupport ? `<p class="delete-copy">${escapeHtml(t("support.readOnly"))}</p>` : ""}
        <form id="grant-prompts-form" class="form-stack" data-user-id="${escapeHtml(user.user_id || "")}">
          <label class="search-input-wrap">
            <span class="search-label">${escapeHtml(t("support.inputLabel"))}</span>
            <input
              class="text-input"
              type="number"
              name="promptCount"
              min="1"
              max="500"
              step="1"
              value="25"
              ${readOnlyAiSupport ? "disabled" : ""}
              required
            />
          </label>
          <div class="search-actions">
            <button
              class="button button-secondary"
              type="submit"
              ${state.grantBusy || readOnlyAiSupport ? "disabled" : ""}
            >
              ${escapeHtml(state.grantBusy ? t("support.granting") : t("support.button"))}
            </button>
          </div>
        </form>
      </div>

      ${
        deleteFeedback
          ? `<div class="status-panel status-${escapeHtml(deleteFeedback.tone || "error")}">${escapeHtml(
              deleteFeedback.message || "",
            )}</div>`
          : ""
      }

      <div class="delete-card">
        <p class="panel-label">${escapeHtml(t("delete.label"))}</p>
        <h3>${escapeHtml(t("delete.title"))}</h3>
        <p class="delete-copy">${escapeHtml(t("delete.copy"))}</p>
        ${
          user.has_active_subscription
            ? `<p class="delete-copy danger-note">${escapeHtml(
                t("delete.activeSubscriptionWarning"),
              )}</p>`
            : ""
        }
        <form id="delete-user-form" class="form-stack" data-user-id="${escapeHtml(user.user_id || "")}">
          <label class="search-input-wrap">
            <span class="search-label">${escapeHtml(t("delete.reason"))}</span>
            <textarea
              class="text-area"
              name="reason"
              placeholder="${escapeHtml(t("delete.reasonPlaceholder"))}"
              required
            ></textarea>
          </label>
          <label class="search-input-wrap">
            <span class="search-label">${escapeHtml(
              t("delete.confirm", { value: confirmValue }),
            )}</span>
            <input
              class="text-input"
              type="text"
              name="confirmText"
              autocomplete="off"
              required
            />
          </label>
          <label class="search-input-wrap">
            <span class="search-label">${escapeHtml(t("delete.confirmEmail"))}</span>
            <input
              class="text-input"
              type="text"
              name="confirmEmail"
              placeholder="${escapeHtml(
                t("delete.confirmEmailPlaceholder", {
                  value: user.email || user.user_id || "",
                }),
              )}"
              autocomplete="off"
              required
            />
          </label>
          <label class="checkbox-row">
            <input
              type="checkbox"
              name="force"
              ${deleteFeedback?.requiresForce ? "checked" : ""}
            />
            <span>${escapeHtml(t("delete.force"))}</span>
          </label>
          <div class="search-actions">
            <button
              class="button button-danger"
              type="submit"
              ${state.deleteBusy ? "disabled" : ""}
            >
              ${escapeHtml(state.deleteBusy ? t("delete.deleting") : t("delete.button"))}
            </button>
          </div>
        </form>
      </div>
    </div>
  `;
}

function renderFeedbackInspector({ loading = false } = {}) {
  if (!tokens?.idToken) {
    elements.feedbackInspector.className = "inspector-empty";
    elements.feedbackInspector.textContent = t("empty.signInFeedback");
    return;
  }

  if (loading) {
    elements.feedbackInspector.className = "inspector-empty";
    elements.feedbackInspector.textContent = t("empty.feedbackLoading");
    return;
  }

  const feedback = state.selectedFeedback;
  if (!feedback) {
    elements.feedbackInspector.className = "inspector-empty";
    elements.feedbackInspector.textContent = t("empty.selectFeedback");
    return;
  }

  const accountLabel = [
    feedback.display_name,
    feedback.user_email || feedback.user_id,
    feedback.username ? `@${feedback.username}` : "",
  ]
    .filter(Boolean)
    .join(" • ");
  const attachments = [];
  if (feedback.has_context) {
    attachments.push(t("feedback.attachments.context"));
  }
  if (feedback.has_screenshot) {
    attachments.push(t("feedback.attachments.screenshot"));
  }
  const clientLabel = formatFeedbackClient(feedback.client);
  const contextJson = feedback.context
    ? escapeHtml(JSON.stringify(feedback.context, null, 2))
    : "";
  const screenshotSrc = buildFeedbackScreenshotSrc(feedback.screenshot);

  elements.feedbackInspector.className = "";
  elements.feedbackInspector.innerHTML = `
    <div class="inspector-stack">
      <div class="inspector-heading">
        <div class="provider-list">
          <span class="badge">${escapeHtml(formatFeedbackCategory(feedback.category))}</span>
          <span class="badge">${escapeHtml(formatFeedbackSource(feedback.source))}</span>
        </div>
        <div class="inspector-title">${escapeHtml(
          feedback.message_preview || feedback.submission_id || t("detail.na"),
        )}</div>
      </div>

      <div class="inspector-grid">
        ${detailCard(t("feedback.detail.user"), accountLabel || t("detail.na"))}
        ${detailCard(t("feedback.detail.source"), formatFeedbackSource(feedback.source))}
        ${detailCard(t("feedback.detail.client"), clientLabel || t("detail.na"))}
        ${detailCard(
          t("feedback.detail.emailConsent"),
          feedback.allow_email_contact
            ? t("feedback.contact.allowed")
            : t("feedback.contact.notAllowed"),
        )}
        ${detailCard(
          t("feedback.detail.attachments"),
          attachments.length ? attachments.join(" • ") : t("feedback.attachments.none"),
        )}
        ${detailCard(t("feedback.detail.submitted"), formatDate(feedback.created_at))}
        ${detailCard(t("detail.userId"), feedback.submission_id || t("detail.na"))}
      </div>

      <div class="detail-card">
        <div class="detail-label">${escapeHtml(t("feedback.detail.message"))}</div>
        <pre class="feedback-json feedback-message">${escapeHtml(feedback.message || t("detail.na"))}</pre>
      </div>

      ${
        feedback.context
          ? `<div class="detail-card">
              <div class="detail-label">${escapeHtml(t("feedback.detail.context"))}</div>
              <pre class="feedback-json">${contextJson}</pre>
            </div>`
          : ""
      }

      ${
        screenshotSrc
          ? `<div class="detail-card">
              <div class="detail-label">${escapeHtml(t("feedback.detail.screenshot"))}</div>
              <img class="feedback-image" src="${screenshotSrc}" alt="Feedback screenshot" />
            </div>`
          : ""
      }
    </div>
  `;
}

function detailCard(label, value) {
  return `
    <div class="detail-card">
      <div class="detail-label">${escapeHtml(label)}</div>
      <div class="detail-value">${escapeHtml(value || t("detail.na"))}</div>
    </div>
  `;
}

function buildEntitlementOverridePlanOptions(selectedValue = "studio") {
  return ["starter", "producer", "studio", "enterprise", "education"]
    .map((planCode) => {
      const selected = planCode === selectedValue ? "selected" : "";
      return `<option value="${escapeHtml(planCode)}" ${selected}>${escapeHtml(
        formatTierLabel(planCode),
      )}</option>`;
    })
    .join("");
}

function currentAdminFirstName() {
  const email = `${currentUser?.email || ""}`.trim().toLowerCase();
  const local = email.split("@", 1)[0] || "";
  return local.replace(/[-_]/g, ".").split(".", 1)[0];
}

function addDays(date, days) {
  const next = new Date(date.getTime());
  next.setDate(next.getDate() + Number(days || 0));
  return next;
}

function toDateTimeLocalValue(date) {
  const pad = (value) => `${value}`.padStart(2, "0");
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
  ].join("-") + `T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function entitlementOverrideExpiryIso(localValue) {
  const date = new Date(`${localValue || ""}`);
  if (Number.isNaN(date.getTime())) {
    return "";
  }
  return date.toISOString();
}

function expectedOverrideIdentifiers(user) {
  return new Set(
    [user.email, user.username, user.user_id]
      .map((value) => `${value || ""}`.trim().toLowerCase())
      .filter(Boolean),
  );
}

function formatAuthSourceLabel(value) {
  switch (`${value || ""}`.trim()) {
    case "native":
      return t("authSource.native");
    case "native_legacy_bridge":
      return t("authSource.nativeLegacyBridge");
    case "legacy_cognito_only":
      return t("authSource.legacyOnly");
    default:
      return t("authSource.unknown");
  }
}

function formatAppAuthSummary(user) {
  const source = formatAuthSourceLabel(user.auth_source);
  const provider = formatProviderLabel(`${user.auth_provider || "email"}`.trim() || "email");
  const status = formatStatusLabel(`${user.auth_status || ""}`.trim());
  return status ? `${source} • ${provider} • ${status}` : `${source} • ${provider}`;
}

function formatEmailVerification(user) {
  const verified = user.native_auth_exists ? user.native_email_verified : user.email_verified;
  return verified ? t("value.verified") : t("value.unverified");
}

function formatNativeSessionSummary(user) {
  const total = Number(user.native_session_count || 0);
  const active = Number(user.native_active_session_count || 0);
  const expiresAt = formatDate(user.native_last_session_expires_at);
  if (!user.native_auth_exists) {
    return t("value.noNativeAuthAccount");
  }
  if (!total) {
    return t("value.zeroSessions");
  }
  return t("value.nativeSessionsSummary", {
    active: formatWholeNumber(active),
    total: formatWholeNumber(total),
    expiry: expiresAt,
  });
}

function formatLegacyCognitoSummary(user) {
  const username =
    `${user.legacy_cognito_username || user.cognito_username || ""}`.trim();
  const legacyStatus = `${user.legacy_auth_status || ""}`.trim();
  const migratedAt = `${user.legacy_cognito_migrated_at || ""}`.trim();
  if (!username && !legacyStatus && !migratedAt) {
    return t("value.notLinked");
  }
  const parts = [];
  if (username) {
    parts.push(username);
  }
  if (legacyStatus) {
    parts.push(formatStatusLabel(legacyStatus));
  }
  if (migratedAt) {
    parts.push(t("value.migrated", { date: formatDate(migratedAt) }));
  }
  return parts.join(" • ");
}

function formatMusicProfileLabel(value) {
  const normalized = `${value || ""}`.trim().toLowerCase();
  if (!normalized) {
    return t("detail.na");
  }
  return tMaybe(`value.musicProfile.${normalized}`, normalized.replace(/_/g, " "));
}

function parseBirthdate(value) {
  const normalized = `${value || ""}`.trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(normalized)) {
    return null;
  }
  const parsed = new Date(`${normalized}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }
  return parsed;
}

function calculateAgeYears(value) {
  const birthdate = parseBirthdate(value);
  if (!birthdate) {
    return null;
  }
  const now = new Date();
  let age = now.getUTCFullYear() - birthdate.getUTCFullYear();
  const monthDelta = now.getUTCMonth() - birthdate.getUTCMonth();
  const dayDelta = now.getUTCDate() - birthdate.getUTCDate();
  if (monthDelta < 0 || (monthDelta === 0 && dayDelta < 0)) {
    age -= 1;
  }
  return age >= 0 ? age : null;
}

function formatBirthdateLabel(value) {
  const normalized = `${value || ""}`.trim();
  return normalized || t("detail.na");
}

function formatAgeLabel(value) {
  const age = calculateAgeYears(value);
  return age == null ? t("detail.na") : formatWholeNumber(age);
}

function formatBirthdateSummary(value) {
  const birthdate = formatBirthdateLabel(value);
  if (birthdate === t("detail.na")) {
    return birthdate;
  }
  const age = formatAgeLabel(value);
  return age === t("detail.na") ? birthdate : `${birthdate} • ${age}`;
}

function setSignedInState(user) {
  elements.signedInHero.classList.remove("hidden");
  elements.dashboard.classList.remove("hidden");
  elements.signedOutPanel.classList.add("hidden");
  elements.identityEmail.textContent = user.email || t("identity.employee");
  elements.identityMeta.textContent = t("identity.employeeAccess");
  renderWelcomeBanner(user);
  renderLivePresence();
  updateTabView();
  updateBusyState();
  animateWelcomeBanner();
  startLivePresencePolling();
}

function setSignedOutState() {
  welcomeAnimationPlayed = false;
  if (livePresenceTimer) {
    window.clearInterval(livePresenceTimer);
    livePresenceTimer = null;
  }
  elements.signedInHero.classList.add("hidden");
  elements.dashboard.classList.add("hidden");
  elements.signedOutPanel.classList.remove("hidden");
  elements.identityEmail.textContent = t("identity.notSignedIn");
  elements.identityMeta.textContent = t("identity.employeeEmailsOnly");
  renderWelcomeBanner(null);
  resetAdminState();
  renderLivePresence();
  updateTabView();
  updateBusyState();
}

function updateBusyState() {
  const signedIn = !!tokens?.idToken;
  const destructiveBusy = state.deleteBusy || state.grantBusy || state.overrideBusy;
  elements.refreshButton.disabled = !signedIn || state.overviewBusy;
  elements.signInButtonSecondary.disabled = signedIn;
  elements.signOutButton.disabled = !signedIn;
  elements.tabButtons.forEach((button) => {
    button.disabled = !signedIn;
  });
  elements.userSearchButton.disabled = !signedIn || state.userSearchBusy || destructiveBusy;
  elements.userSearchClearButton.disabled = !signedIn || state.userSearchBusy || destructiveBusy;
  elements.userSearchInput.disabled = !signedIn || destructiveBusy;
  elements.adminUsersShowLessButton.disabled =
    !signedIn || state.userSearchBusy || state.userSearchLimit <= DEFAULT_ADMIN_USERS_LIMIT;
  elements.adminUsersShowMoreButton.disabled =
    !signedIn
    || state.userSearchBusy
    || state.userSearchLimit >= RESULT_LIMIT_MAX
    || state.lastUserSearchPayload?.has_more !== true;
  elements.trackedUsersShowLessButton.disabled =
    !signedIn
    || state.homeSectionLoading.users
    || state.overviewUserLimit <= DEFAULT_OVERVIEW_USERS_LIMIT;
  elements.trackedUsersShowMoreButton.disabled =
    !signedIn
    || state.homeSectionLoading.users
    || !Array.isArray(state.overview?.users)
    || state.overview.users.length < state.overviewUserLimit
    || state.overviewUserLimit >= RESULT_LIMIT_MAX;
  elements.projectsShowLessButton.disabled =
    !signedIn
    || state.homeSectionLoading.projects
    || state.overviewProjectLimit <= DEFAULT_OVERVIEW_PROJECTS_LIMIT;
  elements.projectsShowMoreButton.disabled =
    !signedIn
    || state.homeSectionLoading.projects
    || !Array.isArray(state.overview?.projects)
    || state.overview.projects.length < state.overviewProjectLimit
    || state.overviewProjectLimit >= RESULT_LIMIT_MAX;
  elements.aiObservabilityTracesShowLessButton.disabled =
    !signedIn
    || state.homeSectionLoading.observability
    || state.overviewTraceLimit <= DEFAULT_OVERVIEW_TRACE_LIMIT;
  elements.aiObservabilityTracesShowMoreButton.disabled =
    !signedIn
    || state.homeSectionLoading.observability
    || state.overviewTraceLimit >= 24
    || state.overview?.ai_observability?.recent_traces_meta?.has_more !== true;
  elements.feedbackShowLessButton.disabled =
    !signedIn || state.feedbackBusy || state.feedbackLimit <= DEFAULT_FEEDBACK_LIMIT;
  elements.feedbackShowMoreButton.disabled =
    !signedIn
    || state.feedbackBusy
    || state.feedbackLimit >= RESULT_LIMIT_MAX
    || state.lastFeedbackPayload?.has_more !== true;
  elements.freeDailyPromptLimitInput.disabled =
    state.aiPromptLimitsBusy || !signedIn || !canViewAiRuntimeSettings();
  elements.freeWeeklyPromptLimitInput.disabled =
    state.aiPromptLimitsBusy || !signedIn || !canViewAiRuntimeSettings();
  elements.aiPromptLimitsConfirmInput.disabled =
    state.aiPromptLimitsBusy || !signedIn || !canViewAiRuntimeSettings();
  elements.aiPromptLimitsSaveButton.disabled =
    state.aiPromptLimitsBusy
    || !signedIn
    || !canViewAiRuntimeSettings()
    || !promptLimitsConfirmationMatches();
  elements.aiPromptLimitsSaveButton.textContent = state.aiPromptLimitsBusy
    ? t("action.saving")
    : t("action.savePromptLimits");
  elements.producerCaptureWhitelistInput.disabled =
    state.producerCaptureWhitelistBusy || !signedIn || !canEditProducerCaptureWhitelist();
  elements.producerCaptureWhitelistConfirmInput.disabled =
    state.producerCaptureWhitelistBusy || !signedIn || !canEditProducerCaptureWhitelist();
  elements.producerCaptureWhitelistSaveButton.disabled =
    state.producerCaptureWhitelistBusy
    || !signedIn
    || !canEditProducerCaptureWhitelist()
    || !producerCaptureWhitelistConfirmationMatches();
  elements.producerCaptureWhitelistSaveButton.textContent = state.producerCaptureWhitelistBusy
    ? t("action.saving")
    : t("action.saveProducerCaptureWhitelist");
  setFormControlsDisabled(
    elements.billingCatalogForm,
    state.billingCatalogBusy || !signedIn || !canEditBillingCatalog(),
  );
  elements.billingCatalogSaveButton.disabled =
    state.billingCatalogBusy || !signedIn || !canEditBillingCatalog();
  elements.billingCatalogSaveButton.textContent = state.billingCatalogBusy
    ? t("action.saving")
    : tMaybe("action.saveBillingCatalog", "Save billing catalog");
  setFormControlsDisabled(
    elements.billingOrganizationForm,
    state.billingOrganizationsBusy || !signedIn || !canEditBillingControlPlane(),
  );
  setFormControlsDisabled(
    elements.billingEducationProvisionForm,
    state.billingOrganizationsBusy || !signedIn || !canEditBillingControlPlane(),
  );
  elements.billingOrganizationSaveButton.textContent = state.billingOrganizationsBusy
    ? t("action.saving")
    : tMaybe("action.saveOrganization", "Save organization");
  if (elements.billingEducationProvisionSaveButton) {
    elements.billingEducationProvisionSaveButton.textContent = state.billingOrganizationsBusy
      ? t("action.saving")
      : "Provision Education";
  }
  setFormControlsDisabled(
    elements.billingMembershipForm,
    state.billingMembershipsBusy || !signedIn || !canEditBillingControlPlane(),
  );
  elements.billingMembershipSaveButton.textContent = state.billingMembershipsBusy
    ? t("action.saving")
    : tMaybe("action.saveMembership", "Save membership");
  setFormControlsDisabled(
    elements.billingWorkspaceForm,
    state.billingWorkspacesBusy || !signedIn || !canEditBillingControlPlane(),
  );
  elements.billingWorkspaceSaveButton.textContent = state.billingWorkspacesBusy
    ? t("action.saving")
    : tMaybe("action.saveWorkspace", "Save workspace");
  setFormControlsDisabled(
    elements.billingCloudProjectForm,
    state.billingCloudProjectsBusy || !signedIn || !canEditBillingControlPlane(),
  );
  elements.billingCloudProjectSaveButton.textContent = state.billingCloudProjectsBusy
    ? t("action.saving")
    : tMaybe("action.saveCloudProject", "Save cloud project");
  updateAiRuntimeConfirmButtons();
}

function setFormControlsDisabled(form, disabled) {
  if (!form) {
    return;
  }
  form.querySelectorAll("input, textarea, select, button").forEach((node) => {
    node.disabled = disabled;
  });
}

function setStatus(message, tone = "info") {
  const hasMessage = !!`${message || ""}`.trim();
  const signedIn = !elements.dashboard.classList.contains("hidden");
  const activePanel = signedIn ? elements.statusPanel : elements.signedOutStatusPanel;
  const inactivePanel = signedIn ? elements.signedOutStatusPanel : elements.statusPanel;
  inactivePanel.textContent = "";
  inactivePanel.className = signedIn ? "status-panel hidden" : "status-panel welcome-status-panel hidden";
  activePanel.textContent = hasMessage ? message : "";
  activePanel.className = signedIn ? "status-panel welcome-status-panel" : "status-panel";
  activePanel.classList.toggle("hidden", !hasMessage);
  if (hasMessage && tone) {
    activePanel.classList.add(`status-${tone}`);
  }
}

async function fetchAdminJson(path, options = {}) {
  await ensureFreshTokens();
  if (!tokens?.idToken || !ensureActiveSession()) {
    throw new Error(t("status.employeeSignInRequired"));
  }
  currentUser = decodeIdToken(tokens?.idToken);
  if (!currentUser?.email) {
    clearTokens();
    throw new Error(t("status.employeeSignInRequired"));
  }

  const headers = new Headers(options.headers || {});
  headers.set("Accept", "application/json");
  headers.set("Authorization", `Bearer ${tokens.idToken}`);
  if (options.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  const response = await fetch(buildApiUrl(path), {
    ...options,
    headers,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(
      normalizeError(payload.error) ||
        t("status.requestFailed", { status: `${response.status}` }),
    );
    error.status = response.status;
    error.payload = payload;
    throw error;
  }
  return payload;
}

function buildApiUrl(path) {
  const safeBase = `${config.apiBaseUrl || ""}`.trim().replace(/\/+$/, "");
  return `${safeBase}${path}`;
}

function buildCognitoUrl(path) {
  return `${`${config.cognitoDomainUrl || ""}`.trim().replace(/\/+$/, "")}${path}`;
}

function loadSessionMeta() {
  try {
    const parsed = JSON.parse(localStorage.getItem(SESSION_META_STORAGE_KEY) || "null");
    if (!parsed || typeof parsed !== "object") {
      return null;
    }
    const issuedAt = Number(parsed.issuedAt || 0);
    const lastActivityAt = Number(parsed.lastActivityAt || 0);
    if (!issuedAt || !lastActivityAt) {
      return null;
    }
    return { issuedAt, lastActivityAt };
  } catch (_) {
    return null;
  }
}

function persistSessionMeta() {
  if (!sessionMeta) {
    localStorage.removeItem(SESSION_META_STORAGE_KEY);
    return;
  }
  localStorage.setItem(SESSION_META_STORAGE_KEY, JSON.stringify(sessionMeta));
}

function ensureSessionMeta() {
  const now = Date.now();
  if (!sessionMeta) {
    sessionMeta = {
      issuedAt: now,
      lastActivityAt: now,
    };
    persistSessionMeta();
    lastActivityPersistAt = now;
    return sessionMeta;
  }

  if (!sessionMeta.issuedAt) {
    sessionMeta.issuedAt = now;
  }
  if (!sessionMeta.lastActivityAt) {
    sessionMeta.lastActivityAt = now;
  }
  persistSessionMeta();
  return sessionMeta;
}

function touchSessionActivity({ forcePersist = false } = {}) {
  if (!tokens?.idToken) {
    return;
  }
  const meta = ensureSessionMeta();
  const now = Date.now();
  meta.lastActivityAt = now;
  if (forcePersist || now - lastActivityPersistAt >= ACTIVITY_PERSIST_INTERVAL_MS) {
    persistSessionMeta();
    lastActivityPersistAt = now;
  }
  scheduleSessionExpiry();
}

function getSessionExpiryReason() {
  if (!tokens?.idToken) {
    return null;
  }
  const meta = ensureSessionMeta();
  const now = Date.now();
  if (now - meta.lastActivityAt >= ADMIN_IDLE_TIMEOUT_MS) {
    return "idle";
  }
  if (now - meta.issuedAt >= ADMIN_MAX_SESSION_MS) {
    return "absolute";
  }
  return null;
}

function ensureActiveSession() {
  const reason = getSessionExpiryReason();
  if (!reason) {
    scheduleSessionExpiry();
    return true;
  }
  expireAdminSession(reason);
  return false;
}

function scheduleSessionExpiry() {
  if (sessionExpiryTimer) {
    window.clearTimeout(sessionExpiryTimer);
    sessionExpiryTimer = null;
  }
  if (!tokens?.idToken) {
    return;
  }
  const meta = ensureSessionMeta();
  const now = Date.now();
  const idleRemaining = ADMIN_IDLE_TIMEOUT_MS - (now - meta.lastActivityAt);
  const absoluteRemaining = ADMIN_MAX_SESSION_MS - (now - meta.issuedAt);
  const nextExpiryMs = Math.min(idleRemaining, absoluteRemaining);
  if (nextExpiryMs <= 0) {
    ensureActiveSession();
    return;
  }
  sessionExpiryTimer = window.setTimeout(() => {
    ensureActiveSession();
  }, nextExpiryMs + 100);
}

function expireAdminSession(reason) {
  clearTokens();
  setSignedOutState();
  const messageKey = reason === "absolute" ? "status.sessionExpiredAbsolute" : "status.sessionExpiredIdle";
  setStatus(
    t(messageKey, { minutes: `${Math.round(ADMIN_IDLE_TIMEOUT_MS / 60000)}` }),
    "error",
  );
}

function loadTokens() {
  try {
    const parsed = JSON.parse(localStorage.getItem(TOKENS_STORAGE_KEY) || "null");
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch (_) {
    return null;
  }
}

function storeTokens(payload) {
  const previousRefreshToken = tokens?.refreshToken || "";
  const idToken = payload.id_token || payload.idToken || "";
  const accessToken = payload.access_token || payload.accessToken || "";
  const refreshToken = payload.refresh_token || payload.refreshToken || "";
  const expiresIn = Number(payload.expires_in || payload.expiresIn || 3600);
  tokens = {
    idToken,
    accessToken,
    refreshToken,
    expiresAt: Math.floor(Date.now() / 1000) + expiresIn,
  };
  localStorage.setItem(TOKENS_STORAGE_KEY, JSON.stringify(tokens));
  if (!sessionMeta || !previousRefreshToken || previousRefreshToken !== refreshToken) {
    sessionMeta = {
      issuedAt: Date.now(),
      lastActivityAt: Date.now(),
    };
    persistSessionMeta();
    lastActivityPersistAt = sessionMeta.lastActivityAt;
  } else {
    touchSessionActivity({ forcePersist: true });
  }
  scheduleSessionExpiry();
}

function clearTokens() {
  tokens = null;
  currentUser = null;
  sessionMeta = null;
  lastActivityPersistAt = 0;
  localStorage.removeItem(TOKENS_STORAGE_KEY);
  localStorage.removeItem(SESSION_META_STORAGE_KEY);
  clearPkceArtifacts();
  if (sessionExpiryTimer) {
    window.clearTimeout(sessionExpiryTimer);
    sessionExpiryTimer = null;
  }
}

function clearPkceArtifacts() {
  sessionStorage.removeItem(PKCE_STATE_KEY);
  sessionStorage.removeItem(PKCE_VERIFIER_KEY);
}

function decodeIdToken(idToken) {
  if (!idToken || typeof idToken !== "string") {
    return null;
  }
  const parts = idToken.split(".");
  if (parts.length < 2) {
    return null;
  }
  try {
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    return {
      sub: payload.sub || "",
      email: payload.email || "",
      exp: payload.exp || 0,
    };
  } catch (_) {
    return null;
  }
}

function handleUserSearchSubmit(event) {
  event.preventDefault();
  state.userSearchLimit = DEFAULT_ADMIN_USERS_LIMIT;
  searchUsers({ query: elements.userSearchInput.value.trim(), silent: false, autoSelect: true });
}

function clearUserSearch() {
  elements.userSearchInput.value = "";
  state.userSearchLimit = DEFAULT_ADMIN_USERS_LIMIT;
  searchUsers({ query: "", silent: false, autoSelect: true });
}

function handleAdminUsersShowLess() {
  if (state.userSearchBusy || state.userSearchLimit <= DEFAULT_ADMIN_USERS_LIMIT) {
    return;
  }
  state.userSearchLimit = DEFAULT_ADMIN_USERS_LIMIT;
  searchUsers({ query: state.currentSearchQuery, silent: true, autoSelect: true });
}

function handleAdminUsersShowMore() {
  if (state.userSearchBusy || state.userSearchLimit >= RESULT_LIMIT_MAX) {
    return;
  }
  state.userSearchLimit = Math.min(state.userSearchLimit + RESULT_LIMIT_STEP, RESULT_LIMIT_MAX);
  searchUsers({ query: state.currentSearchQuery, silent: true, autoSelect: false });
}

function handleTrackedUsersShowLess() {
  if (
    state.homeSectionLoading.users
    || state.overviewUserLimit <= DEFAULT_OVERVIEW_USERS_LIMIT
  ) {
    return;
  }
  state.overviewUserLimit = DEFAULT_OVERVIEW_USERS_LIMIT;
  void refreshOverviewSections({
    include_ai_usage: true,
    include_users: true,
    loadingKeys: ["users"],
  });
}

function handleTrackedUsersShowMore() {
  if (state.homeSectionLoading.users) {
    return;
  }
  if (state.overviewUserLimit >= RESULT_LIMIT_MAX) {
    return;
  }
  state.overviewUserLimit = Math.min(
    state.overviewUserLimit + OVERVIEW_RESULT_LIMIT_STEP,
    RESULT_LIMIT_MAX,
  );
  void refreshOverviewSections({
    include_ai_usage: true,
    include_users: true,
    loadingKeys: ["users"],
  });
}

function handleProjectsShowLess() {
  if (
    state.homeSectionLoading.projects
    || state.overviewProjectLimit <= DEFAULT_OVERVIEW_PROJECTS_LIMIT
  ) {
    return;
  }
  state.overviewProjectLimit = DEFAULT_OVERVIEW_PROJECTS_LIMIT;
  void refreshOverviewSections({
    include_projects: true,
    loadingKeys: ["projects"],
  });
}

function handleProjectsShowMore() {
  if (state.homeSectionLoading.projects) {
    return;
  }
  if (state.overviewProjectLimit >= RESULT_LIMIT_MAX) {
    return;
  }
  state.overviewProjectLimit = Math.min(
    state.overviewProjectLimit + OVERVIEW_RESULT_LIMIT_STEP,
    RESULT_LIMIT_MAX,
  );
  void refreshOverviewSections({
    include_projects: true,
    loadingKeys: ["projects"],
  });
}

function handleAiObservabilityTracesShowLess() {
  if (
    state.homeSectionLoading.observability
    || state.overviewTraceLimit <= DEFAULT_OVERVIEW_TRACE_LIMIT
  ) {
    return;
  }
  state.overviewTraceLimit = DEFAULT_OVERVIEW_TRACE_LIMIT;
  void refreshOverviewSections({
    include_ai_usage: true,
    include_ai_observability: true,
    loadingKeys: ["usage", "observability"],
  });
}

function handleAiObservabilityTracesShowMore() {
  if (state.homeSectionLoading.observability) {
    return;
  }
  if (state.overviewTraceLimit >= 24) {
    return;
  }
  state.overviewTraceLimit = Math.min(
    state.overviewTraceLimit + OVERVIEW_RESULT_LIMIT_STEP,
    24,
  );
  void refreshOverviewSections({
    include_ai_usage: true,
    include_ai_observability: true,
    loadingKeys: ["usage", "observability"],
  });
}

function handleFeedbackShowLess() {
  if (state.feedbackBusy || state.feedbackLimit <= DEFAULT_FEEDBACK_LIMIT) {
    return;
  }
  state.feedbackLimit = DEFAULT_FEEDBACK_LIMIT;
  loadFeedback({ silent: true, autoSelect: true });
}

function handleFeedbackShowMore() {
  if (state.feedbackBusy || state.feedbackLimit >= RESULT_LIMIT_MAX) {
    return;
  }
  state.feedbackLimit = Math.min(state.feedbackLimit + RESULT_LIMIT_STEP, RESULT_LIMIT_MAX);
  loadFeedback({ silent: true, autoSelect: false });
}

function handleAdminUsersTableClick(event) {
  const row = event.target.closest("tr[data-user-id]");
  if (!row) {
    return;
  }
  const userId = `${row.dataset.userId || ""}`.trim();
  if (!userId) {
    return;
  }
  state.selectedUserId = userId;
  state.deleteFeedback = null;
  state.grantFeedback = null;
  state.overrideFeedback = null;
  renderAdminUsers(state.adminUsers);
  renderInspector();
}

function handleFeedbackTableClick(event) {
  const row = event.target.closest("tr[data-submission-id]");
  if (!row) {
    return;
  }
  const submissionId = `${row.dataset.submissionId || ""}`.trim();
  if (!submissionId || submissionId === state.selectedFeedbackId) {
    return;
  }
  state.selectedFeedbackId = submissionId;
  state.selectedFeedback = null;
  renderFeedbackTable(state.feedbackList);
  void loadSelectedFeedbackDetail({ silent: true });
}

function handleInspectorClick(event) {
  const button = event.target.closest("[data-override-duration-days]");
  if (!button) {
    return;
  }
  const form = button.closest("#entitlement-override-form");
  const input = form?.querySelector("input[name='expiresAt']");
  if (!input) {
    return;
  }
  input.value = toDateTimeLocalValue(addDays(new Date(), Number(button.dataset.overrideDurationDays || 0)));
}

function handleInspectorChange(event) {
  const planSelect = event.target.closest("#entitlement-override-form select[name='planCode']");
  if (!planSelect) {
    return;
  }
  const form = planSelect.closest("#entitlement-override-form");
  const seatInput = form?.querySelector("input[name='seatLimit']");
  if (!seatInput) {
    return;
  }
  if (planSelect.value === "education") {
    seatInput.min = "10";
    seatInput.step = "10";
    seatInput.value = "20";
    return;
  }
  if (planSelect.value === "enterprise") {
    seatInput.min = "1";
    seatInput.step = "1";
    seatInput.value = "500";
    return;
  }
  if (planSelect.value === "studio") {
    seatInput.min = "5";
    seatInput.step = "1";
    seatInput.value = "5";
    return;
  }
  seatInput.min = "0";
  seatInput.step = "1";
  seatInput.value = "";
}

async function handleInspectorSubmit(event) {
  event.preventDefault();

  const user = getSelectedUser();
  if (!user) {
    return;
  }

  const overrideForm = event.target.closest("#entitlement-override-form");
  if (overrideForm) {
    const formData = new FormData(overrideForm);
    const planCode = `${formData.get("planCode") || ""}`.trim();
    const expiresAtLocal = `${formData.get("expiresAt") || ""}`.trim();
    const reason = `${formData.get("reason") || ""}`.trim();
    const confirmIdentifier = `${formData.get("confirmIdentifier") || ""}`.trim();
    const confirmAdminFirstName = `${formData.get("confirmAdminFirstName") || ""}`.trim();
    const expectedIdentifiers = expectedOverrideIdentifiers(user);
    const expectedAdminName = currentAdminFirstName();
    if (!expectedIdentifiers.has(confirmIdentifier.toLowerCase())) {
      state.overrideFeedback = {
        userId: user.user_id,
        tone: "error",
        message: t("override.typeExactIdentifier"),
      };
      renderInspector();
      return;
    }
    if (confirmAdminFirstName.toLowerCase() !== expectedAdminName) {
      state.overrideFeedback = {
        userId: user.user_id,
        tone: "error",
        message: t("override.typeExactAdminName"),
      };
      renderInspector();
      return;
    }

    state.overrideBusy = true;
    state.overrideFeedback = null;
    updateBusyState();
    renderInspector();
    setStatus(
      t("status.applyingEntitlementOverride", { target: user.email || user.user_id }),
      "info",
    );

    try {
      const payload = await fetchAdminJson(ADMIN_USERS_ENTITLEMENT_OVERRIDE_PATH, {
        method: "POST",
        body: JSON.stringify({
          user_id: user.user_id,
          plan_code: planCode,
          expires_at: entitlementOverrideExpiryIso(expiresAtLocal),
          seat_limit: Number(`${formData.get("seatLimit") || ""}`.trim() || 0),
          organization_name: `${formData.get("organizationName") || ""}`.trim(),
          reason,
          confirm_identifier: confirmIdentifier,
          confirm_admin_first_name: confirmAdminFirstName,
        }),
      });
      if (payload.user) {
        replaceAdminUser(payload.user);
      }
      state.overrideFeedback = {
        userId: user.user_id,
        tone: "success",
        message: t("override.applied", {
          plan: formatTierLabel(planCode),
          date: formatDate(payload.subscription?.expires_at || entitlementOverrideExpiryIso(expiresAtLocal)),
        }),
      };
      renderAdminUsers(state.adminUsers);
      renderInspector();
      setStatus(t("status.entitlementOverrideApplied"), "success");
    } catch (error) {
      handleAdminRequestError(error, t("status.entitlementOverrideFailed"));
      state.overrideFeedback = {
        userId: user.user_id,
        tone: "error",
        message: error.message || t("status.entitlementOverrideFailed"),
      };
      renderInspector();
    } finally {
      state.overrideBusy = false;
      updateBusyState();
    }
    return;
  }

  const grantForm = event.target.closest("#grant-prompts-form");
  if (grantForm) {
    const formData = new FormData(grantForm);
    const promptCount = Number(`${formData.get("promptCount") || ""}`.trim());
    state.grantBusy = true;
    state.grantFeedback = null;
    updateBusyState();
    renderInspector();
    setStatus(
      t("status.grantingPrompts", { target: user.email || user.user_id }),
      "info",
    );

    try {
      const payload = await fetchAdminJson(ADMIN_USERS_GRANT_PROMPTS_PATH, {
        method: "POST",
        body: JSON.stringify({
          user_id: user.user_id,
          prompt_count: promptCount,
        }),
      });
      if (payload.user) {
        replaceAdminUser(payload.user);
      }
      state.grantFeedback = {
        userId: user.user_id,
        tone: "success",
        message: t("value.extraPromptsAdded", {
          count: formatWholeNumber(payload.granted_prompts || promptCount),
          suffix: Number(payload.granted_prompts || promptCount) === 1 ? "" : "s",
        }),
      };
      renderAdminUsers(state.adminUsers);
      renderInspector();
      setStatus(t("status.promptsGranted"), "success");
    } catch (error) {
      handleAdminRequestError(error, t("status.grantPromptsFailed"));
      state.grantFeedback = {
        userId: user.user_id,
        tone: "error",
        message: error.message || t("status.grantPromptsFailed"),
      };
      renderInspector();
    } finally {
      state.grantBusy = false;
      updateBusyState();
    }
    return;
  }

  const form = event.target.closest("#delete-user-form");
  if (!form) {
    return;
  }

  const formData = new FormData(form);
  const reason = `${formData.get("reason") || ""}`.trim();
  const confirmText = `${formData.get("confirmText") || ""}`.trim();
  const confirmEmail = `${formData.get("confirmEmail") || ""}`.trim().toLowerCase();
  const force = formData.get("force") === "on";
  const confirmValue = inspectorConfirmValue(user);
  const expectedEmail = inspectorDeleteEmailValue(user);
  if (confirmText !== confirmValue) {
    state.deleteFeedback = {
      userId: user.user_id,
      tone: "error",
      message: t("delete.typeExact", { value: confirmValue }),
      requiresForce: force,
    };
    renderInspector();
    return;
  }
  if (confirmEmail !== expectedEmail) {
    state.deleteFeedback = {
      userId: user.user_id,
      tone: "error",
      message: t("delete.typeExactEmail", { value: expectedEmail }),
      requiresForce: force,
    };
    renderInspector();
    return;
  }

  state.deleteBusy = true;
  updateBusyState();
  state.deleteFeedback = null;
  renderInspector();
  setStatus(t("status.deletingUser", { target: user.email || user.user_id }), "info");

  try {
    await fetchAdminJson(ADMIN_USERS_DELETE_PATH, {
      method: "POST",
      body: JSON.stringify({
        user_id: user.user_id,
        reason,
        confirm_email: confirmEmail,
        force,
      }),
    });
    setStatus(t("status.userDeleted"), "success");
    state.deleteBusy = false;
    updateBusyState();
    await searchUsers({
      query: state.currentSearchQuery,
      silent: true,
      autoSelect: true,
    });
  } catch (error) {
    if (error.status === 409 && error.payload?.requires_force) {
      state.deleteFeedback = {
        userId: user.user_id,
        tone: "error",
        message: error.message || t("delete.forceRequired"),
        requiresForce: true,
      };
      if (error.payload?.user) {
        replaceAdminUser(error.payload.user);
      }
      renderAdminUsers(state.adminUsers);
      renderInspector();
      setStatus(error.message || t("status.deleteRequiresForce"), "error");
    } else {
      handleAdminRequestError(error, t("status.deleteUserFailed"));
      state.deleteFeedback = {
        userId: user.user_id,
        tone: "error",
        message: error.message || t("status.deleteUserFailed"),
        requiresForce: force,
      };
      renderInspector();
    }
  } finally {
    state.deleteBusy = false;
    updateBusyState();
  }
}

async function handleAiPromptLimitsSubmit(event) {
  event.preventDefault();
  if (!tokens?.idToken || !canViewAiRuntimeSettings() || !promptLimitsConfirmationMatches()) {
    return;
  }

  const freeDailyPromptLimit = Number(`${elements.freeDailyPromptLimitInput.value || ""}`.trim());
  const freeWeeklyPromptLimit = Number(`${elements.freeWeeklyPromptLimitInput.value || ""}`.trim());

  state.aiPromptLimitsBusy = true;
  state.aiPromptLimitsFeedback = null;
  updateBusyState();
  setStatus(t("status.savingAiPromptLimits"), "info");

  try {
    const payload = await fetchAdminJson(ADMIN_AI_PROMPT_LIMITS_PATH, {
      method: "PUT",
      body: JSON.stringify({
        free_daily_prompt_limit: freeDailyPromptLimit,
        free_weekly_prompt_limit: freeWeeklyPromptLimit,
      }),
    });
    state.aiPromptLimits = payload.settings || null;
    state.aiPromptLimitsFeedback = {
      tone: "success",
      message: t("status.aiPromptLimitsSaved"),
    };
    elements.aiPromptLimitsConfirmInput.value = "";
    renderAiPromptLimitSettings();
    setStatus(t("status.aiPromptLimitsSaved"), "success");
  } catch (error) {
    handleAdminRequestError(error, t("status.saveAiPromptLimitsFailed"));
    state.aiPromptLimitsFeedback = {
      tone: "error",
      message: error.message || t("status.saveAiPromptLimitsFailed"),
    };
    renderAiPromptLimitSettings();
  } finally {
    state.aiPromptLimitsBusy = false;
    updateBusyState();
  }
}

async function handleProducerCaptureWhitelistSubmit(event) {
  event.preventDefault();
  if (
    !tokens?.idToken
    || !canEditProducerCaptureWhitelist()
    || !producerCaptureWhitelistConfirmationMatches()
  ) {
    return;
  }

  const usernames = `${elements.producerCaptureWhitelistInput.value || ""}`
    .split(/[\s,]+/g)
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean);

  state.producerCaptureWhitelistBusy = true;
  state.producerCaptureWhitelistFeedback = null;
  updateBusyState();
  setStatus(t("status.savingProducerCaptureWhitelist"), "info");

  try {
    const payload = await fetchAdminJson(ADMIN_PRODUCER_CAPTURE_WHITELIST_PATH, {
      method: "PUT",
      body: JSON.stringify({
        usernames,
      }),
    });
    state.producerCaptureWhitelist = payload.settings || null;
    state.producerCaptureWhitelistFeedback = {
      tone: "success",
      message: t("status.producerCaptureWhitelistSaved"),
    };
    elements.producerCaptureWhitelistConfirmInput.value = "";
    renderProducerCaptureWhitelistSettings();
    setStatus(t("status.producerCaptureWhitelistSaved"), "success");
  } catch (error) {
    handleAdminRequestError(error, t("status.saveProducerCaptureWhitelistFailed"));
    state.producerCaptureWhitelistFeedback = {
      tone: "error",
      message: error.message || t("status.saveProducerCaptureWhitelistFailed"),
    };
    renderProducerCaptureWhitelistSettings();
  } finally {
    state.producerCaptureWhitelistBusy = false;
    updateBusyState();
  }
}

async function handleAiRuntimeSubmit(event) {
  event.preventDefault();
  const form = event.target.closest(".ai-runtime-form");
  if (!form || !tokens?.idToken || !canViewAiRuntimeSettings() || !runtimeConfirmationMatches(form)) {
    return;
  }

  const feature = `${form.dataset.feature || ""}`.trim();
  const formData = new FormData(form);

  state.aiRuntimeBusy = true;
  state.aiRuntimeFeedbackByFeature = {
    ...state.aiRuntimeFeedbackByFeature,
    [feature]: null,
  };
  updateBusyState();
  setStatus(t("status.savingAiRuntime"), "info");

  try {
    const payload = await fetchAdminJson(ADMIN_AI_RUNTIME_PATH, {
      method: "PUT",
      body: JSON.stringify({
        feature,
        model_override: `${formData.get("model_override") || ""}`,
        system_prompt_override: `${formData.get("system_prompt_override") || ""}`,
        max_output_tokens_override: `${formData.get("max_output_tokens_override") || ""}`.trim(),
        temperature_override: `${formData.get("temperature_override") || ""}`.trim(),
        reasoning_effort_override: `${formData.get("reasoning_effort_override") || ""}`,
        prompt_cache_retention_override: `${formData.get("prompt_cache_retention_override") || ""}`,
      }),
    });
    if (state.aiRuntimeSettings?.features) {
      state.aiRuntimeSettings.features = state.aiRuntimeSettings.features.map((candidate) =>
        candidate.feature === feature ? payload.feature : candidate,
      );
    }
    state.aiRuntimeFeedbackByFeature = {
      ...state.aiRuntimeFeedbackByFeature,
      [feature]: {
        tone: "success",
        message: t("status.aiRuntimeSaved"),
      },
    };
    const confirmInput = form.querySelector(".ai-runtime-confirm-input");
    if (confirmInput) {
      confirmInput.value = "";
    }
    renderAiRuntimeSettings();
    setStatus(t("status.aiRuntimeSaved"), "success");
  } catch (error) {
    handleAdminRequestError(error, t("status.saveAiRuntimeFailed"));
    state.aiRuntimeFeedbackByFeature = {
      ...state.aiRuntimeFeedbackByFeature,
      [feature]: {
        tone: "error",
        message: error.message || t("status.saveAiRuntimeFailed"),
      },
    };
    renderAiRuntimeSettings();
  } finally {
    state.aiRuntimeBusy = false;
    updateBusyState();
  }
}

function replaceAdminUser(user) {
  const nextUsers = state.adminUsers.map((candidate) =>
    candidate.user_id === user.user_id ? user : candidate,
  );
  state.adminUsers = nextUsers;
}

function syncSelectedFeedback(autoSelect) {
  const hasSelection = state.feedbackList.some(
    (submission) => submission.submission_id === state.selectedFeedbackId,
  );
  if (hasSelection) {
    return;
  }

  state.selectedFeedbackId =
    autoSelect && state.feedbackList.length ? state.feedbackList[0].submission_id || "" : "";
  state.selectedFeedback = null;
}

function syncSelectedUser(autoSelect) {
  const hasSelection = state.adminUsers.some((user) => user.user_id === state.selectedUserId);
  if (hasSelection) {
    return;
  }
  state.deleteFeedback = null;
  state.grantFeedback = null;
  state.selectedUserId = autoSelect && state.adminUsers.length ? state.adminUsers[0].user_id : "";
}

function getSelectedUser() {
  return state.adminUsers.find((user) => user.user_id === state.selectedUserId) || null;
}

function inspectorConfirmValue(user) {
  return user.username || user.email || user.user_id || "";
}

function inspectorDeleteEmailValue(user) {
  return `${user.email || user.user_id || ""}`.trim().toLowerCase();
}

function resetAdminState() {
  destroyAllAnalyticsCharts();
  state.overviewBusy = false;
  state.userSearchBusy = false;
  state.feedbackBusy = false;
  state.aiPromptLimitsBusy = false;
  state.producerCaptureWhitelistBusy = false;
  state.aiRuntimeBusy = false;
  state.billingCatalogBusy = false;
  state.billingOrganizationsBusy = false;
  state.billingMembershipsBusy = false;
  state.billingWorkspacesBusy = false;
  state.billingCloudProjectsBusy = false;
  state.deleteBusy = false;
  state.grantBusy = false;
  state.overrideBusy = false;
  state.currentSearchQuery = "";
  state.overview = null;
  state.overviewIncludes = buildOverviewIncludes();
  state.homeSectionLoading = buildHomeSectionLoading();
  state.overviewUserLimit = DEFAULT_OVERVIEW_USERS_LIMIT;
  state.overviewProjectLimit = DEFAULT_OVERVIEW_PROJECTS_LIMIT;
  state.overviewTraceLimit = DEFAULT_OVERVIEW_TRACE_LIMIT;
  state.lastUserSearchPayload = null;
  state.userSearchLimit = DEFAULT_ADMIN_USERS_LIMIT;
  state.adminUsers = [];
  state.selectedUserId = "";
  state.lastFeedbackPayload = null;
  state.feedbackLimit = DEFAULT_FEEDBACK_LIMIT;
  state.feedbackList = [];
  state.selectedFeedbackId = "";
  state.selectedFeedback = null;
  state.aiPromptLimits = null;
  state.aiPromptLimitsFeedback = null;
  state.producerCaptureWhitelist = null;
  state.producerCaptureWhitelistFeedback = null;
  state.aiRuntimeSettings = null;
  state.aiRuntimeFeedbackByFeature = {};
  state.billingCatalog = null;
  state.billingCatalogConfigurable = true;
  state.billingCatalogFeedback = null;
  state.billingOrganizations = [];
  state.billingOrganizationsLoaded = false;
  state.billingMemberships = [];
  state.billingMembershipsLoaded = false;
  state.billingWorkspaces = [];
  state.billingWorkspacesLoaded = false;
  state.billingCloudProjects = [];
  state.billingCloudProjectsLoaded = false;
  state.collaborationConfigurable = true;
  state.selectedBillingOrganizationId = "";
  state.selectedBillingMembershipKey = "";
  state.selectedBillingWorkspaceId = "";
  state.selectedBillingCloudProjectId = "";
  state.billingEducationProvisionFeedback = null;
  state.billingOrganizationFeedback = null;
  state.billingMembershipFeedback = null;
  state.billingWorkspaceFeedback = null;
  state.billingCloudProjectFeedback = null;
  state.livePresence = null;
  state.livePresenceRequestId = 0;
  state.analyticsRange = "7d";
  state.aiToolUsageRange = "7d";
  state.feedbackRequestId = 0;
  state.deleteFeedback = null;
  state.grantFeedback = null;
  state.searchRequestId = 0;
  state.overviewRequestId = 0;
  state.activeTab = DEFAULT_TAB;
  state.loadedTabs = buildLoadedTabs();

  setHomeSectionLoading(
    ["analytics", "usage", "observability", "users", "projects"],
    false,
  );

  elements.userSearchInput.value = "";
  elements.aiPromptLimitsConfirmInput.value = "";
  elements.producerCaptureWhitelistInput.value = "";
  elements.producerCaptureWhitelistConfirmInput.value = "";
  elements.billingCatalogSupportEmailInput.value = "";
  elements.billingCatalogContactLabelInput.value = "";
  elements.billingCatalogSupportUrlInput.value = "";
  elements.billingCatalogFaqUrlInput.value = "";
  elements.billingCatalogManageSubscriptionUrlInput.value = "";
  elements.billingCatalogRefundPolicyUrlInput.value = "";
  elements.billingCatalogDefaultCheckoutUrlInput.value = "";
  elements.billingCatalogPlansInput.value = "";
  elements.billingCatalogProductsInput.value = "";
  elements.billingCatalogProviderProductsInput.value = "";
  elements.adminUsersTableBody.innerHTML = `
    <tr>
      <td colspan="5" class="table-empty">${escapeHtml(t("empty.signInSearchUsers"))}</td>
    </tr>
  `;
  elements.userInspector.className = "inspector-empty";
  elements.userInspector.innerHTML = escapeHtml(t("empty.selectUser"));
  elements.feedbackTableBody.innerHTML = `
    <tr>
      <td colspan="5" class="table-empty">${escapeHtml(t("empty.signInFeedback"))}</td>
    </tr>
  `;
  elements.feedbackInspector.className = "inspector-empty";
  elements.feedbackInspector.innerHTML = escapeHtml(t("empty.signInFeedback"));
  elements.billingOrganizationsTableBody.innerHTML = buildBillingEmptyTableRow(
    5,
    tMaybe("empty.signInBillingControlPlane", "Sign in to load billing control-plane records."),
  );
  elements.billingMembershipsTableBody.innerHTML = buildBillingEmptyTableRow(
    5,
    tMaybe("empty.signInBillingControlPlane", "Sign in to load billing control-plane records."),
  );
  elements.billingWorkspacesTableBody.innerHTML = buildBillingEmptyTableRow(
    5,
    tMaybe("empty.signInBillingControlPlane", "Sign in to load billing control-plane records."),
  );
  elements.billingCloudProjectsTableBody.innerHTML = buildBillingEmptyTableRow(
    5,
    tMaybe("empty.signInBillingControlPlane", "Sign in to load billing control-plane records."),
  );
  elements.adminUsersPageMeta.textContent = "";
  elements.trackedUsersPageMeta.textContent = "";
  elements.projectsPageMeta.textContent = "";
  elements.aiObservabilityTracePageMeta.textContent = "";
  elements.feedbackPageMeta.textContent = "";
  elements.billingOrganizationsPageMeta.textContent = "";
  elements.billingMembershipsPageMeta.textContent = "";
  elements.billingWorkspacesPageMeta.textContent = "";
  elements.billingCloudProjectsPageMeta.textContent = "";
  updateTabView();
  renderAiPromptLimitSettings();
  renderProducerCaptureWhitelistSettings();
  renderAiRuntimeSettings();
  renderBillingCatalogSettings();
  renderBillingOrganizations();
  renderBillingMemberships();
  renderBillingWorkspaces();
  renderBillingCloudProjects();
}

function destroyAnalyticsChart(chartKey) {
  const chart = analyticsCharts[chartKey];
  if (chart && typeof chart.destroy === "function") {
    chart.destroy();
  }
  delete analyticsCharts[chartKey];
}

function destroyAllAnalyticsCharts() {
  Object.keys(analyticsCharts).forEach(destroyAnalyticsChart);
}

function handleAdminRequestError(error, fallbackMessage) {
  const message = error.message || fallbackMessage;
  if (/sign in|required|session/i.test(message)) {
    clearTokens();
    setSignedOutState();
  }
  setStatus(message, "error");
}

function normalizeError(value) {
  const safe = `${value || ""}`.trim();
  return safe ? safe.replaceAll("_", " ") : "";
}

function formatProviderLabel(value) {
  const normalized = `${value || ""}`.trim().toLowerCase();
  return tMaybe(`provider.${normalized || "unknown"}`, normalized || t("provider.unknown"));
}

function formatTierLabel(value) {
  const normalized = `${value || ""}`.trim().toLowerCase();
  return tMaybe(`value.${normalized || "unknown"}`, normalized || t("value.unknown"));
}

function formatStatusLabel(value) {
  const normalized = `${value || ""}`.trim().toLowerCase();
  return tMaybe(
    `value.${normalized || "unknown"}`,
    normalized ? normalized.replaceAll("_", " ") : t("value.unknown"),
  );
}

function formatFeedbackCategory(value) {
  const normalized = `${value || ""}`.trim().toLowerCase();
  return tMaybe(
    `feedback.category.${normalized || "feedback"}`,
    normalized || t("feedback.category.feedback"),
  );
}

function formatFeedbackSource(value) {
  const normalized = `${value || ""}`.trim().toLowerCase();
  return tMaybe(`feedback.source.${normalized || "home"}`, normalized || t("detail.na"));
}

function formatFeedbackClient(client) {
  if (!client || typeof client !== "object") {
    return "";
  }

  const parts = [];
  const platform = `${client.platform || ""}`.trim();
  const locale = `${client.locale || ""}`.trim();
  const appVersion = `${client.app_version || client.appVersion || ""}`.trim();
  if (platform) {
    parts.push(platform);
  }
  if (locale) {
    parts.push(locale);
  }
  if (appVersion) {
    parts.push(`v${appVersion}`);
  }
  return parts.join(" • ");
}

function buildFeedbackScreenshotSrc(screenshot) {
  if (!screenshot || typeof screenshot !== "object") {
    return "";
  }

  const mimeType = `${screenshot.mime_type || screenshot.mimeType || ""}`.trim();
  const base64Data = `${screenshot.data_base64 || screenshot.base64_data || screenshot.base64Data || ""}`.trim();
  if (!mimeType || !base64Data) {
    return "";
  }
  return `data:${mimeType};base64,${base64Data}`;
}

function formatOnboardingLabel(value) {
  const normalized = `${value || ""}`.trim().toLowerCase();
  return tMaybe(
    `value.${normalized || "unknown"}`,
    normalized ? normalized.replaceAll("_", " ") : t("value.unknown"),
  );
}

function formatNumber(value) {
  return new Intl.NumberFormat(state.locale, { notation: "compact" }).format(Number(value || 0));
}

function formatDecimal(value) {
  return new Intl.NumberFormat(state.locale, {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  }).format(Number(value || 0));
}

function formatMilliseconds(value) {
  return `${formatDecimal(value || 0)} ms`;
}

function formatWholeNumber(value) {
  return new Intl.NumberFormat(state.locale).format(Number(value || 0));
}

function formatPercent(value) {
  return new Intl.NumberFormat(state.locale, {
    style: "percent",
    maximumFractionDigits: 0,
  }).format(Number.isFinite(value) ? value : 0);
}

function formatShortDate(value) {
  if (!value) return t("detail.na");
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return t("detail.na");
  return new Intl.DateTimeFormat(state.locale, {
    month: "short",
    day: "numeric",
  }).format(parsed);
}

function formatDate(value) {
  if (!value) return t("detail.na");
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return t("detail.na");
  return new Intl.DateTimeFormat(state.locale, {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(parsed);
}

function shortenIdentifier(value, lead = 8, tail = 4) {
  const normalized = `${value || ""}`.trim();
  if (!normalized) {
    return "unknown";
  }
  if (normalized.length <= lead + tail + 3) {
    return normalized;
  }
  return `${normalized.slice(0, lead)}...${normalized.slice(-tail)}`;
}

function escapeHtml(value) {
  return `${value || ""}`
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function badgeClass(value, prefix = "") {
  const normalized = `${value || ""}`
    .trim()
    .toLowerCase()
    .replaceAll("_", "-")
    .replaceAll(/\s+/g, "-");
  return `${prefix}${normalized || "unknown"}`;
}

function generateRandomString(length) {
  const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (byte) => charset[byte % charset.length]).join("");
}

async function createPkceChallenge(verifier) {
  const data = new TextEncoder().encode(verifier);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return base64UrlEncode(new Uint8Array(digest));
}

function base64UrlEncode(bytes) {
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
