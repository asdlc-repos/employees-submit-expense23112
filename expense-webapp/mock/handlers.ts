import { http, HttpResponse } from "msw";
import type { components } from "../src/generated/expense-api";
import { scopesFromToken } from "./authz/session";

type ExpenseClaim = components["schemas"]["ExpenseClaim"] & {
  // The contract's required list names these but declares no property for
  // them; the service carries them, so the mock models them locally.
  createdAt: string;
  updatedAt: string;
};
type ExpenseLine = components["schemas"]["ExpenseLine"];
type Receipt = components["schemas"]["Receipt"];
type Person = components["schemas"]["Person"];
type Notification = components["schemas"]["Notification"];
type ExportRecord = components["schemas"]["ExportRecord"];
type ReviewComment = components["schemas"]["ReviewComment"];

// Seed data mirrors the wireframes' rows (specs/design/components/
// expense-webapp/wireframes.dsl): the reviewer compares the running page
// against the rendered wireframe, so the rows the DSL draws are served here.
//
// State lives in module scope so the app behaves like an app: a create shows
// up in the next list, a decision moves a claim's status. A full page load
// re-runs this module and puts the seed data back — that is what makes a
// verification run repeatable, and also why a row created a moment ago can
// vanish if the run leaves the app mid-scenario.

const CATEGORIES = ["travel", "meals", "supplies", "training", "other"];

const PEOPLE: Person[] = [
  { username: "maya-patel", displayName: "Maya Patel", email: "maya.patel@example.test", manager: "j-weber" },
  { username: "priya-nair", displayName: "Priya Nair", email: "priya.nair@example.test", manager: "j-weber" },
  { username: "ken-sato", displayName: "Ken Sato", email: "ken.sato@example.test", manager: "j-weber" },
  { username: "j-weber", displayName: "J. Weber", email: "j.weber@example.test", manager: null },
  { username: "mock-employee", displayName: "Mock Employee", email: "employee@example.test", manager: "j-weber" },
  { username: "mock-manager", displayName: "J. Weber", email: "manager@example.test", manager: null },
  { username: "mock-financereviewer", displayName: "Mock FinanceReviewer", email: "finance@example.test", manager: null },
];

// Who the mock caller is, resolved from the mock token's role segment the way
// the gateway's assertion would carry it. `/me/` handlers answer this person's
// rows; a row that exists but is not theirs is a 404, never a 403.
function callerUsername(request: Request): string {
  const auth = request.headers.get("authorization");
  const token = auth?.replace(/^Bearer\s+/i, "") ?? "";
  if (!token.startsWith("mock:")) return "mock-employee";
  const roleSegment = decodeURIComponent(token.slice("mock:".length).split(";")[0] ?? "");
  const roles = roleSegment.split("+").filter(Boolean);
  // The wired/mocked role names map onto the seeded people the way the
  // testUsers would: Employee -> the seeded employee, Manager -> J. Weber,
  // FinanceReviewer -> the finance person.
  if (roles.includes("Manager")) return "j-weber";
  if (roles.includes("FinanceReviewer")) return "mock-financereviewer";
  if (roles.includes("Employee")) return "mock-employee";
  return "mock-employee";
}

const RECEIPT_PIXEL =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAwAB/wD/oQAAAA==";

function receipt(fileName: string, contentType: string): Receipt {
  return {
    receiptId: `rcpt-${fileName.replace(/\W+/g, "-").toLowerCase()}`,
    fileName,
    contentType,
    fileSize: 48,
  };
}

const SEED_LINES: ExpenseLine[] = [
  {
    lineId: "line-1",
    expenseDate: "2026-10-10",
    category: "travel",
    amount: 89.5,
    description: "Train to Leeds",
    receipt: receipt("ticket.jpg", "image/jpeg"),
  },
  {
    lineId: "line-2",
    expenseDate: "2026-10-10",
    category: "meals",
    amount: 68.2,
    description: "Dinner with the client",
    receipt: receipt("dinner.png", "image/png"),
  },
];

const WORKSHOP_COMMENT: ReviewComment = {
  commentId: "cmt-1",
  author: "j-weber",
  stage: "manager",
  body: "the amount doesn't match the dinner receipt.",
  createdAt: "2026-10-21T09:30:00Z",
};

let claims: ExpenseClaim[] = [
  {
    claimId: "claim-1",
    title: "Client workshop in Leeds",
    claimant: "maya-patel",
    status: "awaiting-manager",
    totalAmount: 157.7,
    lines: SEED_LINES,
    comments: [],
    createdAt: "2026-09-20T10:00:00Z",
    updatedAt: "2026-09-20T10:00:00Z",
    submittedAt: "2026-09-20T10:00:00Z",
    returnedAt: null,
    exportedAt: null,
  },
  {
    claimId: "claim-2",
    title: "Team lunch, sprint review",
    claimant: "priya-nair",
    status: "awaiting-manager",
    totalAmount: 86.4,
    lines: [SEED_LINES[0]],
    comments: [],
    createdAt: "2026-09-19T11:00:00Z",
    updatedAt: "2026-09-19T11:00:00Z",
    submittedAt: "2026-09-19T11:00:00Z",
    returnedAt: null,
    exportedAt: null,
  },
  {
    claimId: "claim-3",
    title: "Design conference ticket",
    claimant: "ken-sato",
    status: "awaiting-manager",
    totalAmount: 340,
    lines: [SEED_LINES[1]],
    comments: [],
    createdAt: "2026-09-17T09:00:00Z",
    updatedAt: "2026-09-17T09:00:00Z",
    submittedAt: "2026-09-17T09:00:00Z",
    returnedAt: null,
    exportedAt: null,
  },
  {
    // The returned claim the employee journey corrects (F1's EditClaim step) —
    // matches the MyClaimDetail and EditClaim wireframes, comment included.
    claimId: "claim-4",
    title: "Client workshop in Leeds",
    claimant: "mock-employee",
    status: "returned",
    totalAmount: 214.6,
    lines: SEED_LINES,
    comments: [WORKSHOP_COMMENT],
    createdAt: "2026-09-20T10:00:00Z",
    updatedAt: "2026-10-21T09:30:00Z",
    submittedAt: "2026-09-20T10:00:00Z",
    returnedAt: "2026-10-21T09:30:00Z",
    exportedAt: null,
  },
  {
    // An awaiting-manager row of the caller's own, so the "Awaiting approval"
    // tab holds a row before the walk submits a new one.
    claimId: "claim-10",
    title: "Design conference ticket",
    claimant: "mock-employee",
    status: "awaiting-manager",
    totalAmount: 340,
    lines: [SEED_LINES[1]],
    comments: [],
    createdAt: "2026-09-17T09:00:00Z",
    updatedAt: "2026-09-17T09:00:00Z",
    submittedAt: "2026-09-17T09:00:00Z",
    returnedAt: null,
    exportedAt: null,
  },
  {
    // A finance-queue row: past manager approval.
    claimId: "claim-5",
    title: "Client workshop in Leeds",
    claimant: "maya-patel",
    status: "awaiting-finance",
    totalAmount: 214.6,
    lines: SEED_LINES,
    comments: [{ commentId: "cmt-2", author: "j-weber", stage: "manager", body: "Looks good.", createdAt: "2026-09-21T10:00:00Z" }],
    createdAt: "2026-09-20T10:00:00Z",
    updatedAt: "2026-09-21T10:00:00Z",
    submittedAt: "2026-09-20T10:00:00Z",
    returnedAt: null,
    exportedAt: null,
  },
  {
    claimId: "claim-6",
    title: "Team lunch, sprint review",
    claimant: "priya-nair",
    status: "awaiting-finance",
    totalAmount: 86.4,
    lines: [SEED_LINES[0]],
    comments: [],
    createdAt: "2026-09-19T11:00:00Z",
    updatedAt: "2026-09-19T11:00:00Z",
    submittedAt: "2026-09-19T11:00:00Z",
    returnedAt: null,
    exportedAt: null,
  },
  {
    claimId: "claim-7",
    title: "Design conference ticket",
    claimant: "ken-sato",
    status: "awaiting-finance",
    totalAmount: 340,
    lines: [SEED_LINES[1]],
    comments: [],
    createdAt: "2026-09-17T09:00:00Z",
    updatedAt: "2026-09-17T09:00:00Z",
    submittedAt: "2026-09-17T09:00:00Z",
    returnedAt: null,
    exportedAt: null,
  },
  {
    // A draft of the caller's own, so the Draft tab holds a row.
    claimId: "claim-11",
    title: "Taxi to the airport",
    claimant: "mock-employee",
    status: "draft",
    totalAmount: 0,
    lines: [],
    comments: [],
    createdAt: "2026-10-01T08:00:00Z",
    updatedAt: "2026-10-01T08:00:00Z",
    submittedAt: null,
    returnedAt: null,
    exportedAt: null,
  },
  {
    // The MyClaims "Ready for export" row.
    claimId: "claim-8",
    title: "Team lunch, sprint review",
    claimant: "mock-employee",
    status: "ready-for-export",
    totalAmount: 86.4,
    lines: [SEED_LINES[0]],
    comments: [],
    createdAt: "2026-09-19T11:00:00Z",
    updatedAt: "2026-09-19T11:00:00Z",
    submittedAt: "2026-09-19T11:00:00Z",
    returnedAt: null,
    exportedAt: null,
  },
  {
    // The MyClaims "Exported" row.
    claimId: "claim-9",
    title: "Printer paper for the office",
    claimant: "mock-employee",
    status: "exported",
    totalAmount: 24.8,
    lines: [SEED_LINES[0]],
    comments: [],
    createdAt: "2026-09-05T08:00:00Z",
    updatedAt: "2026-09-05T08:00:00Z",
    submittedAt: "2026-09-05T08:00:00Z",
    returnedAt: null,
    exportedAt: "2026-09-30T12:00:00Z",
  },
];

let notifications: Notification[] = [
  {
    notificationId: "ntf-1",
    recipient: "j-weber",
    subject: "Claim awaiting your approval",
    body: "Maya Patel filed 'Client workshop in Leeds'",
    claimId: "claim-1",
    sentAt: "2026-09-20T10:00:00Z",
  },
  {
    notificationId: "ntf-2",
    recipient: "mock-employee",
    subject: "Claim approved",
    body: "'Client workshop in Leeds' now awaits finance review",
    claimId: "claim-5",
    sentAt: "2026-09-21T10:00:00Z",
  },
  {
    notificationId: "ntf-3",
    recipient: "mock-employee",
    subject: "Claim returned",
    body: "'Client workshop in Leeds' was returned with a comment",
    claimId: "claim-4",
    sentAt: "2026-10-21T09:30:00Z",
  },
  {
    notificationId: "ntf-4",
    recipient: "mock-employee",
    subject: "Claim exported",
    body: "'Client workshop in Leeds' was sent to payroll",
    claimId: "claim-9",
    sentAt: "2026-09-30T12:00:00Z",
  },
];

let exports: ExportRecord[] = [
  {
    exportId: "exp-1",
    exportedBy: "mock-financereviewer",
    exportedAt: "2026-09-30T12:00:00Z",
    fileFormat: "CSV",
    claimCount: 46,
    totalAmount: 3842.1,
  },
  {
    exportId: "exp-2",
    exportedBy: "mock-financereviewer",
    exportedAt: "2026-09-15T12:00:00Z",
    fileFormat: "CSV",
    claimCount: 38,
    totalAmount: 2954.75,
  },
];

function page<T>(data: T[]) {
  return { count: data.length, next: null, previous: null, data };
}

function notify(recipient: string, subject: string, body: string, claimId?: string): void {
  notifications = [
    {
      notificationId: `ntf-${notifications.length + 1}`,
      recipient,
      subject,
      body,
      claimId,
      sentAt: new Date().toISOString(),
    },
    ...notifications,
  ];
}

const CLAIM_1_PNG = Uint8Array.from(atob(RECEIPT_PIXEL), (c) => c.charCodeAt(0));

export const handlers = [
  // ---- public operations -------------------------------------------------
  http.get("/api/health", () => new HttpResponse(null, { status: 200 })),

  http.get("/api/categories", () => HttpResponse.json(CATEGORIES)),

  // ---- signed-in operations ---------------------------------------------
  http.get("/api/people", () => HttpResponse.json(PEOPLE)),

  // The caller's notifications — a `/me/` path answers the caller's rows.
  http.get("/api/me/notifications", ({ request }) => {
    const who = callerUsername(request);
    return HttpResponse.json(page(notifications.filter((n) => n.recipient === who)));
  }),

  // ---- the caller's claims ------------------------------------------------
  http.get("/api/me/claims", ({ request }) => {
    const who = callerUsername(request);
    const url = new URL(request.url);
    const status = url.searchParams.get("status");
    const mine = claims.filter((c) => c.claimant === who);
    return HttpResponse.json(page(status ? mine.filter((c) => c.status === status) : mine));
  }),

  http.post("/api/me/claims", async ({ request }) => {
    const who = callerUsername(request);
    const body = (await request.json()) as { title?: string };
    if (!body?.title) {
      return HttpResponse.json({ code: 400, message: "title is required" }, { status: 400 });
    }
    const created: ExpenseClaim = {
      claimId: `claim-${claims.length + 1}`,
      title: body.title,
      claimant: who,
      status: "draft",
      totalAmount: 0,
      lines: [],
      comments: [],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      submittedAt: null,
      returnedAt: null,
      exportedAt: null,
    };
    claims = [created, ...claims];
    return HttpResponse.json(created, {
      status: 201,
      headers: { Location: `/me/claims/${created.claimId}` },
    });
  }),

  http.get("/api/me/claims/:claimId", ({ params, request }) => {
    const who = callerUsername(request);
    const claim = claims.find((c) => c.claimId === params.claimId && c.claimant === who);
    return claim
      ? HttpResponse.json(claim)
      : HttpResponse.json({ code: 404, message: "No such claim of the caller's." }, { status: 404 });
  }),

  http.put("/api/me/claims/:claimId", async ({ params, request }) => {
    const who = callerUsername(request);
    const claim = claims.find((c) => c.claimId === params.claimId && c.claimant === who);
    if (!claim || claim.status !== "draft") {
      return HttpResponse.json({ code: 404, message: "No such editable claim." }, { status: 404 });
    }
    const body = (await request.json()) as { title?: string };
    if (!body?.title) {
      return HttpResponse.json({ code: 400, message: "title is required" }, { status: 400 });
    }
    claim.title = body.title;
    claim.updatedAt = new Date().toISOString();
    return HttpResponse.json(claim);
  }),

  http.delete("/api/me/claims/:claimId", ({ params, request }) => {
    const who = callerUsername(request);
    const claim = claims.find((c) => c.claimId === params.claimId && c.claimant === who);
    if (!claim || claim.status !== "draft") {
      return HttpResponse.json({ code: 404, message: "No such deletable claim." }, { status: 404 });
    }
    claims = claims.filter((c) => c.claimId !== claim.claimId);
    return new HttpResponse(null, { status: 204 });
  }),

  http.post("/api/me/claims/:claimId/submit", ({ params, request }) => {
    const who = callerUsername(request);
    const claim = claims.find((c) => c.claimId === params.claimId && c.claimant === who);
    if (!claim) {
      return HttpResponse.json({ code: 404, message: "No such claim of the caller's." }, { status: 404 });
    }
    if (claim.status !== "draft" && claim.status !== "returned") {
      return HttpResponse.json({ code: 404, message: "Not submittable." }, { status: 404 });
    }
    if (claim.lines.length === 0 || claim.lines.some((l) => !l.receipt)) {
      return HttpResponse.json(
        { code: 400, message: "Every line needs a receipt before the claim can be submitted." },
        { status: 400 },
      );
    }
    claim.status = "awaiting-manager";
    claim.submittedAt = new Date().toISOString();
    claim.returnedAt = null;
    claim.updatedAt = claim.submittedAt;
    const manager = PEOPLE.find((p) => p.username === claim.claimant)?.manager;
    if (manager) {
      const person = PEOPLE.find((p) => p.username === claim.claimant);
      notify(
        manager,
        "Claim awaiting your approval",
        `${person?.displayName ?? claim.claimant} filed '${claim.title}'`,
        claim.claimId,
      );
    }
    return HttpResponse.json(claim);
  }),

  http.post("/api/me/claims/:claimId/lines", async ({ params, request }) => {
    const who = callerUsername(request);
    const claim = claims.find((c) => c.claimId === params.claimId && c.claimant === who);
    if (!claim || (claim.status !== "draft" && claim.status !== "returned")) {
      return HttpResponse.json({ code: 404, message: "No such editable claim." }, { status: 404 });
    }
    const body = (await request.json()) as {
      expenseDate?: string;
      category?: string;
      amount?: number;
      description?: string;
    };
    if (!body?.expenseDate || !body?.category || !body?.description || body?.amount === undefined) {
      return HttpResponse.json({ code: 400, message: "The line body is invalid." }, { status: 400 });
    }
    const line: ExpenseLine = {
      lineId: `line-${claim.lines.length + 1}-${Date.now()}`,
      expenseDate: body.expenseDate,
      category: body.category,
      amount: body.amount,
      description: body.description,
      receipt: undefined,
    };
    claim.lines = [...claim.lines, line];
    claim.totalAmount = claim.lines.reduce((sum, l) => sum + l.amount, 0);
    claim.updatedAt = new Date().toISOString();
    return HttpResponse.json(line, {
      status: 201,
      headers: { Location: `/me/claims/${claim.claimId}/lines/${line.lineId}` },
    });
  }),

  http.put("/api/me/claims/:claimId/lines/:lineId", async ({ params, request }) => {
    const who = callerUsername(request);
    const claim = claims.find((c) => c.claimId === params.claimId && c.claimant === who);
    const line = claim?.lines.find((l) => l.lineId === params.lineId);
    if (!claim || !line || (claim.status !== "draft" && claim.status !== "returned")) {
      return HttpResponse.json({ code: 404, message: "No such editable line." }, { status: 404 });
    }
    const body = (await request.json()) as {
      expenseDate?: string;
      category?: string;
      amount?: number;
      description?: string;
    };
    if (body?.expenseDate) line.expenseDate = body.expenseDate;
    if (body?.category) line.category = body.category;
    if (body?.amount !== undefined) line.amount = body.amount;
    if (body?.description) line.description = body.description;
    claim.totalAmount = claim.lines.reduce((sum, l) => sum + l.amount, 0);
    claim.updatedAt = new Date().toISOString();
    return HttpResponse.json(line);
  }),

  http.delete("/api/me/claims/:claimId/lines/:lineId", ({ params, request }) => {
    const who = callerUsername(request);
    const claim = claims.find((c) => c.claimId === params.claimId && c.claimant === who);
    if (!claim || (claim.status !== "draft" && claim.status !== "returned")) {
      return HttpResponse.json({ code: 404, message: "No such editable claim." }, { status: 404 });
    }
    const before = claim.lines.length;
    claim.lines = claim.lines.filter((l) => l.lineId !== params.lineId);
    if (claim.lines.length === before) {
      return HttpResponse.json({ code: 404, message: "No such line." }, { status: 404 });
    }
    claim.totalAmount = claim.lines.reduce((sum, l) => sum + l.amount, 0);
    return new HttpResponse(null, { status: 204 });
  }),

  http.post("/api/me/claims/:claimId/lines/:lineId/receipt", async ({ params, request }) => {
    const who = callerUsername(request);
    const claim = claims.find((c) => c.claimId === params.claimId && c.claimant === who);
    const line = claim?.lines.find((l) => l.lineId === params.lineId);
    if (!claim || !line || (claim.status !== "draft" && claim.status !== "returned")) {
      return HttpResponse.json({ code: 404, message: "No such editable line." }, { status: 404 });
    }
    const body = (await request.json()) as {
      fileName?: string;
      contentType?: string;
      fileSize?: number;
      content?: string;
    };
    if (!body?.fileName || !body?.contentType || body?.fileSize === undefined || !body?.content) {
      return HttpResponse.json({ code: 400, message: "The upload body is invalid." }, { status: 400 });
    }
    line.receipt = {
      receiptId: `rcpt-${params.claimId}-${params.lineId}`,
      fileName: body.fileName,
      contentType: body.contentType,
      fileSize: body.fileSize,
    };
    claim.updatedAt = new Date().toISOString();
    return HttpResponse.json(line.receipt, { status: 201 });
  }),

  http.get("/api/me/claims/:claimId/lines/:lineId/receipt", ({ params, request }) => {
    const who = callerUsername(request);
    const claim = claims.find((c) => c.claimId === params.claimId && c.claimant === who);
    const line = claim?.lines.find((l) => l.lineId === params.lineId);
    if (!line?.receipt) {
      return HttpResponse.json({ code: 404, message: "No such receipt." }, { status: 404 });
    }
    return new HttpResponse(CLAIM_1_PNG, { headers: { "Content-Type": line.receipt.contentType } });
  }),

  // ---- the caller's reports' claims (Manager) ----------------------------
  http.get("/api/me/reports/claims", ({ request }) => {
    const who = callerUsername(request);
    const url = new URL(request.url);
    const status = url.searchParams.get("status");
    const reports = PEOPLE.filter((p) => p.manager === who).map((p) => p.username);
    const rows = claims.filter((c) => reports.includes(c.claimant));
    return HttpResponse.json(page(status ? rows.filter((c) => c.status === status) : rows));
  }),

  http.get("/api/me/reports/claims/:claimId", ({ params, request }) => {
    const who = callerUsername(request);
    const reports = PEOPLE.filter((p) => p.manager === who).map((p) => p.username);
    const claim = claims.find((c) => c.claimId === params.claimId && reports.includes(c.claimant));
    return claim
      ? HttpResponse.json(claim)
      : HttpResponse.json({ code: 404, message: "No such claim of the caller's reports." }, { status: 404 });
  }),

  http.get("/api/me/reports/receipts/:receiptId", () =>
    new HttpResponse(CLAIM_1_PNG, { headers: { "Content-Type": "image/png" } }),
  ),

  http.post("/api/me/reports/claims/:claimId/approve", ({ params, request }) => {
    const who = callerUsername(request);
    const reports = PEOPLE.filter((p) => p.manager === who).map((p) => p.username);
    const claim = claims.find((c) => c.claimId === params.claimId && reports.includes(c.claimant));
    if (!claim) {
      return HttpResponse.json({ code: 404, message: "No such claim awaiting the caller." }, { status: 404 });
    }
    if (claim.status !== "awaiting-manager") {
      return HttpResponse.json({ code: 409, message: "The claim is not awaiting the caller's approval." }, { status: 409 });
    }
    claim.status = "awaiting-finance";
    claim.updatedAt = new Date().toISOString();
    notify(
      claim.claimant,
      "Claim approved",
      `'${claim.title}' now awaits finance review`,
      claim.claimId,
    );
    return HttpResponse.json(claim);
  }),

  http.post("/api/me/reports/claims/:claimId/return", async ({ params, request }) => {
    const who = callerUsername(request);
    const reports = PEOPLE.filter((p) => p.manager === who).map((p) => p.username);
    const claim = claims.find((c) => c.claimId === params.claimId && reports.includes(c.claimant));
    if (!claim) {
      return HttpResponse.json({ code: 404, message: "No such claim awaiting the caller." }, { status: 404 });
    }
    const body = (await request.json()) as { comment?: string };
    if (!body?.comment?.trim()) {
      return HttpResponse.json({ code: 400, message: "The comment is empty." }, { status: 400 });
    }
    if (claim.status !== "awaiting-manager") {
      return HttpResponse.json({ code: 409, message: "The claim is not awaiting the caller's approval." }, { status: 409 });
    }
    claim.status = "returned";
    claim.returnedAt = new Date().toISOString();
    claim.updatedAt = claim.returnedAt;
    claim.comments = [
      ...(claim.comments ?? []),
      {
        commentId: `cmt-${(claim.comments?.length ?? 0) + 1}`,
        author: who,
        stage: "manager",
        body: body.comment,
        createdAt: claim.returnedAt,
      },
    ];
    notify(
      claim.claimant,
      "Claim returned",
      `'${claim.title}' was returned with a comment`,
      claim.claimId,
    );
    return HttpResponse.json(claim);
  }),

  // ---- the finance queue (FinanceReviewer) -------------------------------
  http.get("/api/claims", ({ request }) => {
    const url = new URL(request.url);
    const status = url.searchParams.get("status") ?? "awaiting-finance";
    const claimant = url.searchParams.get("claimant");
    let rows = claims.filter((c) => c.status === status);
    if (claimant) rows = rows.filter((c) => c.claimant === claimant);
    return HttpResponse.json(page(rows));
  }),

  http.get("/api/claims/exports", () => HttpResponse.json(page(exports))),

  http.post("/api/claims/exports", ({ request }) => {
    const who = callerUsername(request);
    const included = claims.filter((c) => c.status === "ready-for-export");
    const record: ExportRecord = {
      exportId: `exp-${exports.length + 1}`,
      exportedBy: who,
      exportedAt: new Date().toISOString(),
      fileFormat: "CSV",
      claimCount: included.length,
      totalAmount: included.reduce((sum, c) => sum + c.totalAmount, 0),
    };
    for (const claim of included) {
      claim.status = "exported";
      claim.exportedAt = record.exportedAt;
      claim.updatedAt = record.exportedAt;
      notify(
        claim.claimant,
        "Claim exported",
        `'${claim.title}' was sent to payroll`,
        claim.claimId,
      );
    }
    exports = [record, ...exports];
    return HttpResponse.json(record);
  }),

  http.get("/api/claims/exports/:exportId", ({ params }) => {
    const record = exports.find((e) => e.exportId === params.exportId);
    if (!record) {
      return HttpResponse.json({ code: 404, message: "No such export." }, { status: 404 });
    }
    const csv =
      "claimant,claim,category,amount\n" +
      claims
        .filter((c) => c.status === "exported")
        .flatMap((c) =>
          c.lines.map((l) => `${c.claimant},${JSON.stringify(c.title)},${l.category},${l.amount}`),
        )
        .join("\n");
    return new HttpResponse(csv, { headers: { "Content-Type": "text/csv" } });
  }),

  // Receipt image: most-specific literal paths must come before /api/claims/:claimId.
  http.get("/api/claims/receipts/:receiptId", () =>
    new HttpResponse(CLAIM_1_PNG, { headers: { "Content-Type": "image/png" } }),
  ),

  http.get("/api/claims/:claimId", ({ params }) => {
    const claim = claims.find((c) => c.claimId === params.claimId);
    return claim
      ? HttpResponse.json(claim)
      : HttpResponse.json({ code: 404, message: "No such claim." }, { status: 404 });
  }),

  http.post("/api/claims/:claimId/approve", ({ params }) => {
    const claim = claims.find((c) => c.claimId === params.claimId);
    if (!claim) {
      return HttpResponse.json({ code: 404, message: "No such claim." }, { status: 404 });
    }
    if (claim.status !== "awaiting-finance") {
      return HttpResponse.json({ code: 409, message: "The claim is not awaiting finance review." }, { status: 409 });
    }
    claim.status = "ready-for-export";
    claim.updatedAt = new Date().toISOString();
    notify(
      claim.claimant,
      "Claim approved",
      `'${claim.title}' is approved for export`,
      claim.claimId,
    );
    return HttpResponse.json(claim);
  }),

  http.post("/api/claims/:claimId/return", async ({ params, request }) => {
    const claim = claims.find((c) => c.claimId === params.claimId);
    if (!claim) {
      return HttpResponse.json({ code: 404, message: "No such claim." }, { status: 404 });
    }
    const body = (await request.json()) as { comment?: string };
    const comment = body?.comment;
    if (!comment?.trim()) {
      return HttpResponse.json({ code: 400, message: "The comment is empty." }, { status: 400 });
    }
    if (claim.status !== "awaiting-finance") {
      return HttpResponse.json({ code: 409, message: "The claim is not awaiting finance review." }, { status: 409 });
    }
    claim.status = "returned";
    claim.returnedAt = new Date().toISOString();
    claim.updatedAt = claim.returnedAt;
    claim.comments = [
      ...(claim.comments ?? []),
      {
        commentId: `cmt-${(claim.comments?.length ?? 0) + 1}`,
        author: "mock-financereviewer",
        stage: "finance",
        body: comment,
        createdAt: claim.returnedAt,
      },
    ];
    notify(
      claim.claimant,
      "Claim returned",
      `'${claim.title}' was returned with a comment`,
      claim.claimId,
    );
    return HttpResponse.json(claim);
  }),
];