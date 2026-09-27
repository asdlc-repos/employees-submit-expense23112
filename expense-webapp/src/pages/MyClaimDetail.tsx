import { useState, type JSX } from "react";
import { useNavigate, useParams } from "react-router-dom";
import {
  AppBreadcrumbs,
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  Grid,
  Link,
  ListingTable,
  PageContent,
  PageTitle,
  Stack,
  Typography,
} from "@wso2/oxygen-ui";
import { Pencil } from "@wso2/oxygen-ui-icons-react";
import { api, formatAmount, formatDate } from "../api";
import { authorizationHeader } from "../authz/client";
import { ErrorState, LoadingState, statusLabel, useLoad } from "./shared";
import type { Claim } from "../api";

// MyClaimDetail — "An employee follows one claim's review journey and corrects
// it when returned"

export function MyClaimDetailPage(): JSX.Element {
  const { claimId = "" } = useParams();
  const navigate = useNavigate();
  const [receiptError, setReceiptError] = useState<string | null>(null);

  const state = useLoad<Claim>(
    () => api.GET("/me/claims/{claimId}", { params: { path: { claimId } } }).then((r) => {
      if (r.data) return r.data;
      throw new Error(r.error?.message ?? "The claim could not be loaded.");
    }),
    [claimId],
  );

  if (state.status === "loading") return <PageContent><LoadingState /></PageContent>;
  if (state.status === "error") return <PageContent><ErrorState message={state.message} /></PageContent>;

  const claim = state.data;
  const status = statusLabel(claim.status);
  const lastComment = claim.comments?.length ? claim.comments[claim.comments.length - 1] : undefined;
  const activity = buildActivity(claim);

  return (
    <PageContent>
      <Box sx={{ mb: 2 }}>
        <AppBreadcrumbs
          items={[
            { key: "my", label: "My Claims", onClick: () => navigate("/claims/mine") },
            { key: "claim", label: claim.title },
          ]}
        />
      </Box>
      <PageTitle>
        <PageTitle.Header>{claim.title}</PageTitle.Header>
        <PageTitle.Actions>
          <Chip label={status.label} color={status.color} size="small" />
          {claim.status === "returned" && (
            <Button
              variant="contained"
              startIcon={<Pencil size={18} />}
              onClick={() => navigate(`/claims/mine/${claim.claimId}/edit`)}
            >
              Edit claim
            </Button>
          )}
        </PageTitle.Actions>
      </PageTitle>

      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        Total {formatAmount(claim.totalAmount)} — {claim.lines.length} expense{" "}
        {claim.lines.length === 1 ? "line" : "lines"}
      </Typography>

      <Grid container spacing={3}>
        <Grid size={{ xs: 12, md: 7 }}>
          <Typography variant="h6" sx={{ mb: 1 }}>
            Expense lines
          </Typography>
          <ListingTable.Container disablePaper sx={{ width: "100%" }}>
            <ListingTable>
              <ListingTable.Head>
                <ListingTable.Row>
                  <ListingTable.Cell>Date</ListingTable.Cell>
                  <ListingTable.Cell>Category</ListingTable.Cell>
                  <ListingTable.Cell>Description</ListingTable.Cell>
                  <ListingTable.Cell>Amount</ListingTable.Cell>
                  <ListingTable.Cell>Receipt</ListingTable.Cell>
                </ListingTable.Row>
              </ListingTable.Head>
              <ListingTable.Body>
                {claim.lines.map((l) => (
                  <ListingTable.Row key={l.lineId}>
                    <ListingTable.Cell>{l.expenseDate}</ListingTable.Cell>
                    <ListingTable.Cell>{l.category}</ListingTable.Cell>
                    <ListingTable.Cell>{l.description}</ListingTable.Cell>
                    <ListingTable.Cell>{formatAmount(l.amount)}</ListingTable.Cell>
                    <ListingTable.Cell>
                      {l.receipt ? (
                        <Link
                          sx={{ cursor: "pointer" }}
                          onClick={() => void openReceipt(claim.claimId, l.lineId, setReceiptError)}
                        >
                          View
                        </Link>
                      ) : (
                        "—"
                      )}
                    </ListingTable.Cell>
                  </ListingTable.Row>
                ))}
              </ListingTable.Body>
            </ListingTable>
          </ListingTable.Container>
          {receiptError !== null && (
            <Typography variant="caption" color="error" sx={{ mt: 1, display: "block" }}>
              {receiptError}
            </Typography>
          )}
        </Grid>

        <Grid size={{ xs: 12, md: 5 }}>
          <Stack spacing={2}>
            {claim.status === "returned" && (
              <Card variant="outlined">
                <CardContent>
                  <Typography variant="h6" sx={{ mb: 1 }}>
                    Why it was returned
                  </Typography>
                  <Typography variant="body2">
                    {lastComment
                      ? `${lastComment.author} (${lastComment.stage === "manager" ? "Manager" : "Finance"}) · ${new Date(lastComment.createdAt).toLocaleDateString("en-GB", { day: "2-digit", month: "short" })}: ${lastComment.body}`
                      : "Returned for correction."}
                  </Typography>
                </CardContent>
              </Card>
            )}
            <Box>
              <Typography variant="h6" sx={{ mb: 1 }}>
                Activity
              </Typography>
              <Stack spacing={1}>
                {activity.map((entry) => (
                  <Typography key={entry} variant="body2">
                    {entry}
                  </Typography>
                ))}
              </Stack>
            </Box>
          </Stack>
        </Grid>
      </Grid>
    </PageContent>
  );
}

async function openReceipt(
  claimId: string,
  lineId: string,
  onError: (message: string) => void,
): Promise<void> {
  try {
    const header = await authorizationHeader();
    const response = await fetch(`/api/me/claims/${claimId}/lines/${lineId}/receipt`, {
      headers: header ? { Authorization: header } : undefined,
    });
    if (!response.ok) {
      onError(`Could not open the receipt (${response.status}).`);
      return;
    }
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    window.open(url, "_blank");
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  } catch {
    onError("Could not open the receipt.");
  }
}

function buildActivity(claim: Claim): string[] {
  const entries: string[] = [];
  if (claim.submittedAt) {
    entries.push(`${formatDate(claim.submittedAt)} — submitted for review`);
  }
  for (const comment of claim.comments ?? []) {
    const when = formatDate(comment.createdAt);
    const stage = comment.stage === "manager" ? "Manager" : "Finance";
    entries.push(`${when} — returned by ${comment.author} (${stage}) for correction`);
  }
  if (claim.status === "awaiting-finance" && claim.submittedAt) {
    entries.push(`${formatDate(claim.submittedAt)} — approved by the manager`);
  }
  if (claim.status === "ready-for-export") {
    entries.push("Approved for export");
  }
  if (claim.exportedAt) {
    entries.push(`${formatDate(claim.exportedAt)} — sent to payroll`);
  }
  if (entries.length === 0) entries.push("Draft — not submitted yet");
  return entries;
}