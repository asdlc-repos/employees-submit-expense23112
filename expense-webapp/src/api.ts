import createClient, { type Middleware } from "openapi-fetch";
import type { paths } from "./generated/expense-api";
import { authorizationHeader, classifyResponse, ForbiddenError } from "./authz/client";

// Same-origin /api: nginx reverse-proxies it to the expense-api sibling (via
// the API gateway when the platform offers it). No browser-visible API host.
export const api = createClient<paths>({ baseUrl: "/api" });

// Attach the bearer and apply the 401 rule — the ONLY authorization this
// client does. The rule itself lives in src/authz/client.ts.
const authMiddleware: Middleware = {
  async onRequest({ request }) {
    const header = await authorizationHeader();
    if (header) request.headers.set("Authorization", header);
    return request;
  },
  async onResponse({ response }) {
    if ((await classifyResponse(response.status)) === "forbidden") {
      throw new ForbiddenError(response.status);
    }
    return response;
  },
};

api.use(authMiddleware);

// Convenience wrappers for the screens' typed calls.
export type components = import("./generated/expense-api").components;

export type Claim = components["schemas"]["ExpenseClaim"];
export type ExpenseLine = components["schemas"]["ExpenseLine"];
export type Receipt = components["schemas"]["Receipt"];
export type Notification = components["schemas"]["Notification"];
export type ExportRecord = components["schemas"]["ExportRecord"];
export type Person = components["schemas"]["Person"];
export type ClaimPage = components["schemas"]["ClaimPage"];
export type NotificationPage = components["schemas"]["NotificationPage"];
export type ExportPage = components["schemas"]["ExportPage"];

export function formatAmount(value: number): string {
  return value.toFixed(2);
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return "—";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleDateString("en-GB", { day: "2-digit", month: "short" });
}

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" });
}