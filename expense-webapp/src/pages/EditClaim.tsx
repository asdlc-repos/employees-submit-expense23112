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
  ListingTable,
  PageContent,
  PageTitle,
  Stack,
  TextField,
  Typography,
} from "@wso2/oxygen-ui";
import { api, formatAmount } from "../api";
import { ErrorState, LoadingState, statusLabel, useLoad } from "./shared";
import type { Claim } from "../api";

// EditClaim — "An employee corrects a returned claim and sends it back for review"

export function EditClaimPage(): JSX.Element {
  const { claimId = "" } = useParams();
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);
  const [fixError, setFixError] = useState<string | null>(null);
  const [amountFix, setAmountFix] = useState<Record<string, string>>({});

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
  const missingReceipt = claim.lines.some((l) => !l.receipt);

  const saveLine = async (lineId: string): Promise<void> => {
    setBusy(true);
    try {
      const current = claim.lines.find((l) => l.lineId === lineId);
      if (!current) return;
      const amount = amountFix[lineId];
      const { error } = await api.PUT("/me/claims/{claimId}/lines/{lineId}", {
        params: { path: { claimId: claim.claimId, lineId } },
        body: {
          expenseDate: current.expenseDate,
          category: current.category,
          amount: amount !== undefined && amount !== "" ? Number(amount) : current.amount,
          description: current.description,
        },
      });
      if (error) {
        setFixError(error.message ?? "Could not save the line.");
        return;
      }
    } finally {
      setBusy(false);
    }
  };

  const submitAgain = async (): Promise<void> => {
    setBusy(true);
    try {
      for (const lineId of Object.keys(amountFix)) {
        await saveLine(lineId);
      }
      const { data, error } = await api.POST("/me/claims/{claimId}/submit", {
        params: { path: { claimId: claim.claimId } },
      });
      if (data) {
        navigate(`/claims/mine/${claim.claimId}`);
      } else {
        setFixError(error?.message ?? "Could not send the claim back for review.");
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <PageContent>
      <Box sx={{ mb: 2 }}>
        <AppBreadcrumbs
          items={[
            { key: "my", label: "My Claims", onClick: () => navigate("/claims/mine") },
            { key: "claim", label: claim.title, onClick: () => navigate(`/claims/mine/${claim.claimId}`) },
            { key: "edit", label: "Edit" },
          ]}
        />
      </Box>
      <PageTitle>
        <PageTitle.Header>Correct returned claim</PageTitle.Header>
        <PageTitle.Actions>
          <Chip label={status.label} color={status.color} size="small" />
        </PageTitle.Actions>
      </PageTitle>

      {claim.status === "returned" && (
        <Card variant="outlined" sx={{ mb: 2 }}>
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

      <Typography variant="h6" sx={{ mb: 1 }}>
        Expense lines
      </Typography>
      <ListingTable.Container disablePaper sx={{ width: "100%", mb: 2 }}>
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
                <ListingTable.Cell>
                  <Stack direction="row" spacing={1} alignItems="center">
                    <TextField
                      defaultValue={formatAmount(l.amount)}
                      onChange={(e) => setAmountFix({ ...amountFix, [l.lineId]: e.target.value })}
                      inputProps={{ inputMode: "decimal" }}
                      sx={{ width: 110 }}
                      size="small"
                    />
                  </Stack>
                </ListingTable.Cell>
                <ListingTable.Cell>{l.receipt?.fileName ?? "—"}</ListingTable.Cell>
              </ListingTable.Row>
            ))}
          </ListingTable.Body>
        </ListingTable>
      </ListingTable.Container>

      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        Fix the lines above and attach any missing receipt, then send the claim back.
      </Typography>
      {fixError !== null && (
        <Typography variant="caption" color="error" sx={{ display: "block", mb: 1 }}>
          {fixError}
        </Typography>
      )}

      <Grid container justifyContent="flex-end">
        <Button variant="contained" onClick={() => void submitAgain()} disabled={busy || missingReceipt}>
          Submit again
        </Button>
      </Grid>
    </PageContent>
  );
}