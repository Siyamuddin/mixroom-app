// This file is safe for local smoke tests.
// Hosted deployments should generate config.js via admin_site/scripts/deploy_site.sh.
window.MIXROOM_ADMIN_CONFIG = {
  apiBaseUrl: "",
  cognitoDomainUrl: "",
  cognitoClientId: "",
  redirectUri: window.location.origin + window.location.pathname,
  logoutUri: window.location.origin + window.location.pathname,
  scopes: ["openid", "email"],
  posthogDashboardUrl: "",
  posthogEmbedUrl: "",
};
