// What window._env_ holds in mock mode: exactly the keys the platform emits
// for this component's auth dependency (named `expense-auth`). No
// EXPENSE_AUTH_JWKS_URL — the browser never validates a token.
export const mockEnv = {
  EXPENSE_AUTH_CLIENT_ID: "mock-client",
  EXPENSE_AUTH_ISSUER: "https://mock-idp.test",
  // The OIDC scopes are SINGULAR (`group`, `ou`), then the project's catalog
  // handles, exactly as the platform requests them.
  EXPENSE_AUTH_SCOPES:
    "openid profile email group ou claims:read claims:write claims:submit claims:review claims:approve claims:review-all claims:export",
  EXPENSE_AUTH_RESOURCE: "https://aep.wso2.com/orgs/mock/projects/employees-submit-expense23112",
};