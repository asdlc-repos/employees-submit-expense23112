// The browser-visible runtime config, read once at module load. The platform
// mounts /env-config.js which populates window._env_ before the bundle runs.
//
// The auth dependency is named `expense-auth`, so its keys are
// EXPENSE_AUTH_*. The JWKS URL is deliberately absent: the browser never
// validates a token — the API gateway does.

type Env = {
  EXPENSE_AUTH_CLIENT_ID: string;
  EXPENSE_AUTH_ISSUER: string;
  EXPENSE_AUTH_SCOPES: string;
  EXPENSE_AUTH_RESOURCE: string;
};

declare global {
  interface Window { _env_: Env }
}

if (!window._env_) {
  throw new Error(
    "window._env_ not set — /env-config.js failed to load. " +
    "The platform mounts this file; if you see this locally, host " +
    "/env-config.js from your dev server.",
  );
}

export const env: Env = window._env_;