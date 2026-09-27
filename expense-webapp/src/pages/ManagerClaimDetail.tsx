import { useEffect, useState, type JSX } from "react";
import { useNavigate, useParams } from "react-router-dom";
import {
  AppBreadcrumbs,
  Box,
  Button,
  Chip,
  Grid,
  Link,
  ListingTable,
  PageContent,
  PageTitle,
  Stack,
  Typography,
} from "@wso2/oxygen-ui";
import { api, formatAmount, type Claim, type Person } from "../api";
import { ErrorState, LoadingState, statusLabel } from "./shared";
import { authorizationHeader } from "../authz/client";

// ManagerClaimDetail — "A manager checks one claim's lines and receipts, then
// approves or returns it"

export function ManagerClaimDetailPage(): JSX.Element {
  const { claimId = "" } = useParams();
  const navigate = useNavigate();
  const [claim, setClaim] = useState<Claim | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [people, setPeople] = useState<Person[]>([]);
  const [receiptError, setReceiptError] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    api.GET("/me/reports/claims/{claimId}", { params: { path: { claimId } } })
      .then(({ data, error: err }) => {
        if (!live) return;
        if (data) setClaim(data);
        else setError(err?.message ?? "The claim could not be loaded.");
      })
      .catch((e: unknown) => {
        if (live) setError(e instanceof Error ? e.message : "The claim could not be loaded.");
      });
    return () => {
      live = false;
    };
  }, [claimId]);

  useEffect(() => {
    api.GET("/people")
      .then(({ data }) => setPeople(data ?? []))
      .catch(() => setPeople([]));
  }, []);

  const nameOf = (username: string): string =>
    people.find((p) => p.username === username)?.displayName ?? username;

  const approve = async (): Promise<void> => {
    if (!claim) return;
    setBusy(true);
    try {
      const { error: err } = await api.POST("/me/reports/claims/{claimId}/approve", {
        params: { path: { claimId: claim.claimId } },
      });
      if (err) {
        setError(err.message ?? "Could not approve the claim.");
        return;
      }
      navigate("/team-claims");
    } finally {
      setBusy(false);
    }
  };

  const viewReceipt = async (receiptId: string): Promise<void> => {
    try {
      const header = await authorizationHeader();
      const response = await fetch(`/api/me/reports/receipts/${receiptId}`, {
        headers: header ? { Authorization: header } : undefined,
      });
      if (!response.ok) {
        setReceiptError(`Could not open the receipt (${response.status}).`);
        return;
      }
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      window.open(url, "_blank");
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    } catch {
      setReceiptError("Could not open the receipt.");
    }
  };

  if (error !== null) return <PageContent><ErrorState message={error} /></PageContent>;
  if (claim === null) return <PageContent><LoadingState /></PageContent>;

  const status = statusLabel(claim.status);
  const claimantName = nameOf(claim.claimant);

  return (
    <PageContent>
      <Box sx={{ mb: 2 }}>
        <AppBreadcrumbs
          items={[
            { key: "queue", label: "Team Claims", onClick: () => navigate("/team-claims") },
            { key: "claimant", label: claimantName },
            { key: "claim", label: claim.title },
          ]}
        />
      </Box>
      <PageTitle>
        <PageTitle.Header>{claim.title}</PageTitle.Header>
        <PageTitle.Actions>
          <Chip label={status.label} color={status.color} size="small" />
        </PageTitle.Actions>
      </PageTitle>

      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        {claimantName} — {claim.lines.length} expense{" "}
        {claim.lines.length === 1 ? "line" : "lines"} — {formatAmount(claim.totalAmount)} total —
        submitted {new Date(claim.submittedAt ?? "").toLocaleDateString("en-GB", { day: "2-digit", month: "short" })}
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
                          onClick={() => void viewReceipt(l.receipt!.receiptId)}
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
          <Box sx={{ display: "flex", justifyContent: "flex-end", gap: 2, mt: 2 }}>
            <Button
              variant="outlined"
              onClick={() => navigate(`/team-claims/${claim.claimId}/return`)}
            >
              Return claim
            </Button>
            <Button variant="contained" onClick={() => void approve()} disabled={busy}>
              Approve
            </Button>
          </Box>
        </Grid>

        <Grid size={{ xs: 12, md: 5 }}>
          <Typography variant="h6" sx={{ mb: 1 }}>
            Activity
          </Typography>
          <Stack spacing={1}>
            <Typography variant="body2">
              {new Date(claim.submittedAt ?? "").toLocaleDateString("en-GB", { day: "2-digit", month: "short" })} — {claimantName} submitted the claim
            </Typography>
          </Stack>
        </Grid>
      </Grid>
    </PageContent>
  );
}