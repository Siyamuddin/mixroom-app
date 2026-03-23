const TOKENS_STORAGE_KEY = "mixroom.admin.site.tokens.v1";
const LOCALE_STORAGE_KEY = "mixroom.admin.site.locale.v1";
const SESSION_META_STORAGE_KEY = "mixroom.admin.site.session_meta.v1";
const PKCE_STATE_KEY = "mixroom.admin.site.pkce_state.v1";
const PKCE_VERIFIER_KEY = "mixroom.admin.site.pkce_verifier.v1";
const OVERVIEW_PATH = "/v1/internal/admin/overview";
const ADMIN_USERS_PATH = "/v1/internal/admin/users";
const ADMIN_USERS_DELETE_PATH = "/v1/internal/admin/users/delete";
const ADMIN_USERS_GRANT_PROMPTS_PATH = "/v1/internal/admin/users/grant-prompts";
const ADMIN_FEEDBACK_PATH = "/v1/internal/admin/feedback";
const DEFAULT_LOCALE = "en";
const SUPPORTED_LOCALES = new Set(["en", "ko"]);
const ADMIN_IDLE_TIMEOUT_MS = 60 * 60 * 1000;
const ADMIN_MAX_SESSION_MS = 8 * 60 * 60 * 1000;
const ACTIVITY_PERSIST_INTERVAL_MS = 30 * 1000;

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
    "auth.kicker": "Employee access",
    "auth.title": "Sign in",
    "auth.copy": "Use your work email.",
    "panel.kpi.label": "KPI Overview",
    "panel.kpi.title": "Product metrics",
    "panel.kpi.meta.default":
      "Connect a PostHog share or embed URL to surface MAU, retention, funnels, and session trends here.",
    "panel.kpi.meta.live":
      "Live PostHog metrics. Use a shared or embedded dashboard URL for this panel.",
    "panel.kpi.meta.empty":
      "Add a PostHog embed URL to show MAU, retention, funnels, and session trends here.",
    "panel.userAdmin.label": "User Admin",
    "panel.userAdmin.title": "Find user",
    "panel.userAdmin.meta.default": "Email, username, or user ID.",
    "search.label": "User lookup",
    "search.placeholder": "email, username, display name, or user ID",
    "analytics.label": "Product Analytics",
    "analytics.copy": "Retention, MAU, funnels, and session KPIs live in PostHog.",
    "panel.accounts.label": "Accounts",
    "panel.accounts.title": "Search results",
    "panel.accounts.meta": "Recent accounts show when blank.",
    "panel.selectedUser.label": "Selected User",
    "panel.selectedUser.title": "User details",
    "panel.selectedUser.meta": "Review actions here.",
    "panel.aiUsage.label": "AI Usage",
    "panel.aiUsage.title": "AI activity",
    "panel.features.title": "Features",
    "panel.tiers.label": "Subscription Tier",
    "panel.tiers.title": "Tiers",
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
    "table.tier": "Tier",
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
    "empty.signInTierDistribution": "Sign in to load tier distribution.",
    "empty.signInUserData": "Sign in to load user data.",
    "empty.signInProjectData": "Sign in to load project data.",
    "empty.signInFeedback": "Sign in to load user feedback and bug reports.",
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
    "status.noUsersFound": "No users found.",
    "status.searchUsersFailed": "Could not search users.",
    "status.loadFeedbackFailed": "Could not load user feedback or bug reports.",
    "status.grantingPrompts": "Granting extra AI prompts to {target}...",
    "status.promptsGranted": "Extra AI prompts granted.",
    "status.grantPromptsFailed": "Could not grant extra AI prompts.",
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
    "summary.projects": "Projects",
    "summary.projectsDetail": "Project IDs with AI activity",
    "summary.aiRequests": "AI Requests",
    "summary.aiRequestsDetail": "{count} lifetime credits",
    "summary.paidUsers": "Paid Users",
    "summary.paidUsersDetail": "{count} active subs",
    "generated.at": "Generated {date}",
    "generated.unavailable": "Generated time unavailable",
    "identity.signedInAs": "Signed in as {email}",
    "identity.employeeAccess": "Allowlisted employee access",
    "identity.employeeEmailsOnly": "Allowlisted employee emails only",
    "identity.employee": "Employee",
    "identity.notSignedIn": "Not signed in",
    "usage.creditsToday": "Credits today",
    "usage.tokensMonth": "Tokens this month",
    "usage.activeUsers": "AI-active users",
    "usage.successRate": "Success rate",
    "usage.na": "n/a",
    "usage.noFeatures": "No AI feature events recorded yet.",
    "tiers.noData": "No tier data available.",
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
    "user.userIdLine": "User ID: {value}",
    "inspector.selectedUser": "Selected user",
    "inspector.noEmail": "No email available",
    "detail.userId": "User ID",
    "detail.name": "Name",
    "detail.username": "Username",
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
    "support.label": "AI Support",
    "support.title": "Grant extra prompts",
    "support.copy": "Adds a one-time extra prompt bank for support cases.",
    "support.inputLabel": "Extra prompts to add",
    "support.granting": "Granting...",
    "support.button": "Grant Extra Prompts",
    "delete.label": "Delete User",
    "delete.title": "Delete account",
    "delete.copy":
      "Deletes the auth account, profile, subscription records, linked providers, and frees the username.",
    "delete.activeSubscriptionWarning":
      "This user still has an active paid subscription.",
    "delete.reason": "Reason",
    "delete.reasonPlaceholder": "Why are you deleting this account?",
    "delete.confirm": "Type {value} to confirm",
    "delete.force":
      "Force deletion even if the user still has an active paid subscription.",
    "delete.deleting": "Deleting...",
    "delete.button": "Delete User",
    "delete.typeExact": "Type {value} exactly to confirm deletion.",
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
    "value.migrated": "migrated {date}",
    "value.todayWeek": "{today} today • {week} this week",
    "value.remainingGranted": "{remaining} remaining • {granted} granted total",
    "value.extraPromptsAdded": "Added {count} extra prompt{suffix}.",
    "value.userLoaded": "{count} user loaded.",
    "value.usersLoaded": "{count} users loaded.",
    "value.free": "free",
    "value.pro": "pro",
    "value.studio": "studio",
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
    "auth.kicker": "직원 접근",
    "auth.title": "로그인",
    "auth.copy": "업무용 이메일로 로그인하세요.",
    "panel.kpi.label": "KPI 개요",
    "panel.kpi.title": "제품 지표",
    "panel.kpi.meta.default":
      "여기에 MAU, 리텐션, 퍼널, 세션 추이를 보려면 PostHog 공유 또는 임베드 URL을 연결하세요.",
    "panel.kpi.meta.live":
      "실시간 PostHog 지표입니다. 이 패널에는 공유 또는 임베드 대시보드 URL을 사용하세요.",
    "panel.kpi.meta.empty":
      "여기에 MAU, 리텐션, 퍼널, 세션 추이를 표시하려면 PostHog 임베드 URL을 추가하세요.",
    "panel.userAdmin.label": "사용자 관리",
    "panel.userAdmin.title": "사용자 찾기",
    "panel.userAdmin.meta.default": "이메일, 사용자명 또는 사용자 ID.",
    "search.label": "사용자 조회",
    "search.placeholder": "이메일, 사용자명, 표시 이름 또는 사용자 ID",
    "analytics.label": "제품 분석",
    "analytics.copy": "리텐션, MAU, 퍼널, 세션 KPI는 PostHog에서 확인합니다.",
    "panel.accounts.label": "계정",
    "panel.accounts.title": "검색 결과",
    "panel.accounts.meta": "검색어가 없으면 최근 계정을 보여줍니다.",
    "panel.selectedUser.label": "선택된 사용자",
    "panel.selectedUser.title": "사용자 상세",
    "panel.selectedUser.meta": "여기서 작업 내용을 검토하세요.",
    "panel.aiUsage.label": "AI 사용량",
    "panel.aiUsage.title": "AI 활동",
    "panel.features.title": "기능",
    "panel.tiers.label": "구독 티어",
    "panel.tiers.title": "티어",
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
    "table.tier": "티어",
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
    "empty.signInTierDistribution": "티어 분포를 불러오려면 로그인하세요.",
    "empty.signInUserData": "사용자 데이터를 불러오려면 로그인하세요.",
    "empty.signInProjectData": "프로젝트 데이터를 불러오려면 로그인하세요.",
    "empty.signInFeedback": "사용자 피드백과 버그 제보를 불러오려면 로그인하세요.",
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
    "status.noUsersFound": "일치하는 사용자가 없습니다.",
    "status.searchUsersFailed": "사용자 검색에 실패했습니다.",
    "status.loadFeedbackFailed": "사용자 피드백 또는 버그 제보를 불러오지 못했습니다.",
    "status.grantingPrompts": "{target}에 추가 AI 프롬프트를 부여하는 중...",
    "status.promptsGranted": "추가 AI 프롬프트를 부여했습니다.",
    "status.grantPromptsFailed": "추가 AI 프롬프트 부여에 실패했습니다.",
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
    "summary.projects": "프로젝트",
    "summary.projectsDetail": "AI 활동이 있는 프로젝트 ID",
    "summary.aiRequests": "AI 요청",
    "summary.aiRequestsDetail": "누적 크레딧 {count}",
    "summary.paidUsers": "유료 사용자",
    "summary.paidUsersDetail": "활성 구독 {count}",
    "generated.at": "{date} 생성",
    "generated.unavailable": "생성 시각 없음",
    "identity.signedInAs": "{email}(으)로 로그인됨",
    "identity.employeeAccess": "허용 목록에 있는 직원 접근",
    "identity.employeeEmailsOnly": "허용 목록의 직원 이메일만 허용",
    "identity.employee": "직원",
    "identity.notSignedIn": "로그인되지 않음",
    "usage.creditsToday": "오늘 크레딧",
    "usage.tokensMonth": "이번 달 토큰",
    "usage.activeUsers": "AI 활성 사용자",
    "usage.successRate": "성공률",
    "usage.na": "해당 없음",
    "usage.noFeatures": "기록된 AI 기능 이벤트가 아직 없습니다.",
    "tiers.noData": "티어 데이터가 없습니다.",
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
    "user.userIdLine": "사용자 ID: {value}",
    "inspector.selectedUser": "선택된 사용자",
    "inspector.noEmail": "이메일 없음",
    "detail.userId": "사용자 ID",
    "detail.name": "이름",
    "detail.username": "사용자명",
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
    "support.label": "AI 지원",
    "support.title": "추가 프롬프트 부여",
    "support.copy": "지원 상황에서 사용할 일회성 추가 프롬프트 뱅크를 더합니다.",
    "support.inputLabel": "추가할 프롬프트 수",
    "support.granting": "부여 중...",
    "support.button": "추가 프롬프트 부여",
    "delete.label": "사용자 삭제",
    "delete.title": "계정 삭제",
    "delete.copy":
      "인증 계정, 프로필, 구독 기록, 연결된 제공업체를 삭제하고 사용자명을 다시 사용할 수 있게 합니다.",
    "delete.activeSubscriptionWarning": "이 사용자는 아직 활성 유료 구독이 있습니다.",
    "delete.reason": "사유",
    "delete.reasonPlaceholder": "이 계정을 삭제하는 이유는 무엇인가요?",
    "delete.confirm": "확인을 위해 {value} 입력",
    "delete.force": "사용자에게 활성 유료 구독이 있어도 강제로 삭제합니다.",
    "delete.deleting": "삭제 중...",
    "delete.button": "사용자 삭제",
    "delete.typeExact": "삭제를 확인하려면 {value}를 정확히 입력하세요.",
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
    "value.migrated": "{date}에 마이그레이션됨",
    "value.todayWeek": "오늘 {today} • 이번 주 {week}",
    "value.remainingGranted": "남음 {remaining} • 총 부여 {granted}",
    "value.extraPromptsAdded": "추가 프롬프트 {count}개를 부여했습니다.",
    "value.userLoaded": "사용자 {count}명을 불러왔습니다.",
    "value.usersLoaded": "사용자 {count}명을 불러왔습니다.",
    "value.free": "무료",
    "value.pro": "프로",
    "value.studio": "스튜디오",
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
    "value.suspended": "정지됨",
  },
};

const config = window.MIXROOM_ADMIN_CONFIG || {};
const elements = {
  signInButtonSecondary: document.querySelector("#sign-in-button-secondary"),
  refreshButton: document.querySelector("#refresh-button"),
  signOutButton: document.querySelector("#sign-out-button"),
  signedInHero: document.querySelector("#signed-in-hero"),
  statusPanel: document.querySelector("#status-panel"),
  identityEmail: document.querySelector("#identity-email"),
  identityMeta: document.querySelector("#identity-meta"),
  signedOutPanel: document.querySelector("#signed-out-panel"),
  dashboard: document.querySelector("#dashboard"),
  generatedAt: document.querySelector("#generated-at"),
  summarySection: document.querySelector("#summary-section"),
  aiUsageMetrics: document.querySelector("#ai-usage-metrics"),
  topFeatures: document.querySelector("#top-features"),
  tierBreakdown: document.querySelector("#tier-breakdown"),
  trackedUsersTableBody: document.querySelector("#users-table-body"),
  projectsTableBody: document.querySelector("#projects-table-body"),
  userSearchForm: document.querySelector("#user-search-form"),
  userSearchInput: document.querySelector("#user-search-input"),
  userSearchButton: document.querySelector("#user-search-button"),
  userSearchClearButton: document.querySelector("#user-search-clear-button"),
  userSearchMeta: document.querySelector("#user-search-meta"),
  adminUsersTableBody: document.querySelector("#admin-users-table-body"),
  userInspector: document.querySelector("#user-inspector"),
  feedbackTableBody: document.querySelector("#feedback-table-body"),
  feedbackInspector: document.querySelector("#feedback-inspector"),
  analyticsCallout: document.querySelector("#analytics-callout"),
  posthogLink: document.querySelector("#posthog-link"),
  kpiPanel: document.querySelector("#kpi-panel"),
  kpiMeta: document.querySelector("#kpi-meta"),
  kpiEmbedShell: document.querySelector("#kpi-embed-shell"),
  posthogPanelLink: document.querySelector("#posthog-panel-link"),
  posthogEmbedFrame: document.querySelector("#posthog-embed-frame"),
  languageSelector: document.querySelector("#language-selector"),
  signedOutLanguageSelector: document.querySelector("#signed-out-language-selector"),
};

const state = {
  locale: loadLocale(),
  overviewBusy: false,
  userSearchBusy: false,
  feedbackBusy: false,
  deleteBusy: false,
  grantBusy: false,
  currentSearchQuery: "",
  overview: null,
  lastUserSearchPayload: null,
  adminUsers: [],
  selectedUserId: "",
  feedbackList: [],
  selectedFeedbackId: "",
  selectedFeedback: null,
  feedbackRequestId: 0,
  deleteFeedback: null,
  grantFeedback: null,
  searchRequestId: 0,
};

let tokens = loadTokens();
let currentUser = decodeIdToken(tokens?.idToken);
let sessionMeta = loadSessionMeta();
let sessionExpiryTimer = null;
let lastActivityPersistAt = 0;

bindEvents();
applyLocale();
bootstrap();

function bindEvents() {
  elements.signInButtonSecondary.addEventListener("click", beginSignIn);
  elements.refreshButton.addEventListener("click", refreshDashboard);
  elements.signOutButton.addEventListener("click", signOut);
  elements.userSearchForm.addEventListener("submit", handleUserSearchSubmit);
  elements.userSearchClearButton.addEventListener("click", clearUserSearch);
  elements.adminUsersTableBody.addEventListener("click", handleAdminUsersTableClick);
  elements.feedbackTableBody.addEventListener("click", handleFeedbackTableClick);
  elements.userInspector.addEventListener("submit", handleInspectorSubmit);
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
  renderUserSearchMeta(state.lastUserSearchPayload || {});
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

function tMaybe(key, fallback, vars = {}) {
  const dictionary = MESSAGES[state.locale] || MESSAGES[DEFAULT_LOCALE];
  const fallbackDictionary = MESSAGES[DEFAULT_LOCALE];
  if (!dictionary[key] && !fallbackDictionary[key]) {
    return fallback;
  }
  return t(key, vars);
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
  const posthogEmbedUrl = `${config.posthogEmbedUrl || ""}`.trim();
  const hasDashboardUrl = posthogUrl && posthogUrl.includes("http");
  const hasEmbedUrl = posthogEmbedUrl && posthogEmbedUrl.includes("http");

  if (!hasDashboardUrl) {
    elements.analyticsCallout.classList.add("hidden");
    elements.posthogLink.removeAttribute("href");
  } else {
    elements.analyticsCallout.classList.remove("hidden");
    elements.posthogLink.href = posthogUrl;
  }

  if (!hasDashboardUrl && !hasEmbedUrl) {
    elements.kpiPanel.classList.add("hidden");
    elements.kpiEmbedShell.classList.add("hidden");
    elements.posthogPanelLink.classList.add("hidden");
    elements.posthogEmbedFrame.removeAttribute("src");
    return;
  }

  elements.kpiPanel.classList.remove("hidden");

  if (hasDashboardUrl) {
    elements.posthogPanelLink.classList.remove("hidden");
    elements.posthogPanelLink.href = posthogUrl;
  } else {
    elements.posthogPanelLink.classList.add("hidden");
    elements.posthogPanelLink.removeAttribute("href");
  }

  if (hasEmbedUrl) {
    elements.kpiMeta.textContent = t("panel.kpi.meta.live");
    elements.kpiEmbedShell.classList.remove("hidden");
    elements.posthogEmbedFrame.src = posthogEmbedUrl;
  } else {
    elements.kpiMeta.textContent = t("panel.kpi.meta.empty");
    elements.kpiEmbedShell.classList.add("hidden");
    elements.posthogEmbedFrame.removeAttribute("src");
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
  await Promise.all([
    searchUsers({ query: state.currentSearchQuery, silent: true, autoSelect: true }),
    loadFeedback({ silent: true, autoSelect: true }),
  ]);
}

async function refreshOverview() {
  if (!tokens?.idToken) {
    setSignedOutState();
    setStatus(t("status.signInToContinue"), "info");
    return;
  }

  state.overviewBusy = true;
  updateBusyState();
  setStatus(t("status.loadingAdminOverview"), "info");
  try {
    currentUser = decodeIdToken(tokens?.idToken);
    if (!currentUser?.email) {
      clearTokens();
      throw new Error(t("status.sessionMissingEmail"));
    }

    const payload = await fetchAdminJson(OVERVIEW_PATH);
    state.overview = payload;
    setSignedInState(currentUser);
    renderOverview(payload);
    setStatus(t("status.adminOverviewLoaded"), "success");
  } catch (error) {
    handleAdminRequestError(error, t("status.loadAdminOverviewFailed"));
  } finally {
    state.overviewBusy = false;
    updateBusyState();
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
      limit: "24",
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
    const payload = await fetchAdminJson(`${ADMIN_FEEDBACK_PATH}?limit=50`);
    if (requestId !== state.feedbackRequestId) {
      return;
    }
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
  renderSummary(overview.summary || {});
  renderUsage(overview);
  renderTiers(overview.subscription_tiers || []);
  renderTrackedUsers(overview.users || []);
  renderProjects(overview.projects || []);

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
}

function renderSummary(summary) {
  const cards = [
    {
      title: t("summary.users"),
      value: formatNumber(summary.total_users || 0),
      detail: t("summary.usersDetail", {
        count: formatNumber(summary.tracked_users || 0),
      }),
      className: "summary-users",
    },
    {
      title: t("summary.projects"),
      value: formatNumber(summary.tracked_projects || 0),
      detail: t("summary.projectsDetail"),
      className: "summary-projects",
    },
    {
      title: t("summary.aiRequests"),
      value: formatNumber(summary.ai_requests_total || 0),
      detail: t("summary.aiRequestsDetail", {
        count: formatNumber(summary.ai_credits_charged_total || 0),
      }),
      className: "summary-ai",
    },
    {
      title: t("summary.paidUsers"),
      value: formatNumber(summary.paid_users || 0),
      detail: t("summary.paidUsersDetail", {
        count: formatNumber(summary.active_subscriptions || 0),
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

function renderUsage(overview) {
  const summary = overview.summary || {};
  const usage = overview.ai_usage || {};
  const eventRecords = Number(usage.event_records || 0);
  const successfulRequests = Number(usage.successful_requests || 0);
  const successRate = eventRecords
    ? `${Math.round((successfulRequests / eventRecords) * 100)}%`
    : t("usage.na");

  const metrics = [
    { label: t("usage.creditsToday"), value: formatNumber(summary.ai_credits_used_today || 0) },
    { label: t("usage.tokensMonth"), value: formatNumber(summary.ai_tokens_used_month || 0) },
    { label: t("usage.activeUsers"), value: formatNumber(usage.tracked_users || 0) },
    { label: t("usage.successRate"), value: successRate },
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
            <span class="tier-chip">${escapeHtml(formatTierLabel(tier.tier || "free"))}</span>
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
  if (!Array.isArray(users) || !users.length) {
    elements.trackedUsersTableBody.innerHTML = `
      <tr>
        <td colspan="7" class="table-empty">${escapeHtml(t("trackedUsers.none"))}</td>
      </tr>
    `;
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
}

function renderProjects(projects) {
  if (!Array.isArray(projects) || !projects.length) {
    elements.projectsTableBody.innerHTML = `
      <tr>
        <td colspan="6" class="table-empty">${escapeHtml(t("projects.none"))}</td>
      </tr>
    `;
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
    return;
  }

  if (!Array.isArray(users) || !users.length) {
    elements.adminUsersTableBody.innerHTML = `
      <tr>
        <td colspan="5" class="table-empty">${escapeHtml(t("adminUsers.none"))}</td>
      </tr>
    `;
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
}

function renderFeedbackTable(submissions) {
  if (!tokens?.idToken) {
    elements.feedbackTableBody.innerHTML = `
      <tr>
        <td colspan="5" class="table-empty">${escapeHtml(t("empty.signInFeedback"))}</td>
      </tr>
    `;
    return;
  }

  if (!Array.isArray(submissions) || !submissions.length) {
    elements.feedbackTableBody.innerHTML = `
      <tr>
        <td colspan="5" class="table-empty">${escapeHtml(t("feedback.none"))}</td>
      </tr>
    `;
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
  const confirmValue = inspectorConfirmValue(user);
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

      <div class="delete-card support-card">
        <p class="panel-label">${escapeHtml(t("support.label"))}</p>
        <h3>${escapeHtml(t("support.title"))}</h3>
        <p class="delete-copy">${escapeHtml(t("support.copy"))}</p>
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
              required
            />
          </label>
          <div class="search-actions">
            <button
              class="button button-secondary"
              type="submit"
              ${state.grantBusy ? "disabled" : ""}
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

function setSignedInState(user) {
  elements.signedInHero.classList.remove("hidden");
  elements.dashboard.classList.remove("hidden");
  elements.signedOutPanel.classList.add("hidden");
  elements.identityEmail.textContent = user.email || t("identity.employee");
  elements.identityMeta.textContent = t("identity.employeeAccess");
  updateBusyState();
}

function setSignedOutState() {
  elements.signedInHero.classList.add("hidden");
  elements.dashboard.classList.add("hidden");
  elements.signedOutPanel.classList.remove("hidden");
  elements.identityEmail.textContent = t("identity.notSignedIn");
  elements.identityMeta.textContent = t("identity.employeeEmailsOnly");
  resetAdminState();
  updateBusyState();
}

function updateBusyState() {
  const busy =
    state.overviewBusy ||
    state.userSearchBusy ||
    state.feedbackBusy ||
    state.deleteBusy ||
    state.grantBusy;
  const signedIn = !!tokens?.idToken;
  elements.refreshButton.disabled = busy || !signedIn;
  elements.signInButtonSecondary.disabled = busy || signedIn;
  elements.signOutButton.disabled = busy || !signedIn;
  elements.userSearchButton.disabled = busy || !signedIn;
  elements.userSearchClearButton.disabled = busy || !signedIn;
  elements.userSearchInput.disabled = state.deleteBusy || state.grantBusy || !signedIn;
}

function setStatus(message, tone = "info") {
  elements.statusPanel.textContent = message || "";
  elements.statusPanel.className = "status-panel";
  if (tone) {
    elements.statusPanel.classList.add(`status-${tone}`);
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
  searchUsers({ query: elements.userSearchInput.value.trim(), silent: false, autoSelect: true });
}

function clearUserSearch() {
  elements.userSearchInput.value = "";
  searchUsers({ query: "", silent: false, autoSelect: true });
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

async function handleInspectorSubmit(event) {
  event.preventDefault();

  const user = getSelectedUser();
  if (!user) {
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
  const force = formData.get("force") === "on";
  const confirmValue = inspectorConfirmValue(user);
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

function resetAdminState() {
  state.overviewBusy = false;
  state.userSearchBusy = false;
  state.feedbackBusy = false;
  state.deleteBusy = false;
  state.grantBusy = false;
  state.currentSearchQuery = "";
  state.overview = null;
  state.lastUserSearchPayload = null;
  state.adminUsers = [];
  state.selectedUserId = "";
  state.feedbackList = [];
  state.selectedFeedbackId = "";
  state.selectedFeedback = null;
  state.feedbackRequestId = 0;
  state.deleteFeedback = null;
  state.grantFeedback = null;
  state.searchRequestId = 0;

  elements.userSearchInput.value = "";
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
  const base64Data = `${screenshot.base64_data || screenshot.base64Data || ""}`.trim();
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

function formatWholeNumber(value) {
  return new Intl.NumberFormat(state.locale).format(Number(value || 0));
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
