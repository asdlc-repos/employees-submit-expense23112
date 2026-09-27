import { useEffect, useState, type JSX } from "react";
import { useNavigate } from "react-router-dom";
import {
  Button,
  Card,
  CardContent,
  Chip,
  Grid,
  ListingTable,
  MenuItem,
  PageContent,
  PageTitle,
  TextField,
  Typography,
} from "@wso2/oxygen-ui";
import { ArrowRight } from "@wso2/oxygen-ui-icons-react";
import { api, formatAmount, formatDate, type Claim, type Person } from "../api";
import { ErrorState, LoadingState, statusLabel } from "./shared";

// ManagerQueue — "A manager reviews the claims their direct reports have submitted"

export function ManagerQueuePage(): JSX.Element {
  const navigate = useNavigate();
  const [allClaims, setAllClaims] = useState<Claim[] | null>(null);
  const [people, setPeople] = useState<Person[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [claimant, setClaimant] = useState("All reports");

  useEffect(() => {
    let live = true;
    setError(null);
    api.GET("/me/reports/claims", { params: { query: {} } })
      .then(({ data, error: err }) => {
        if (!live) return;
        if (data) setAllClaims(data.data);
        else setError(err?.message ?? "The request failed.");
      })
      .catch((e: unknown) => {
        if (live) setError(e instanceof Error ? e.message : "The request failed.");
      });
    return () => {
      live = false;
    };
  }, []);

  // The claimant filter needs the claimants' display names: one people request.
  useEffect(() => {
    api.GET("/people")
      .then(({ data }) => setPeople(data ?? []))
      .catch(() => setPeople([]));
  }, []);

  const nameOf = (username: string): string =>
    people.find((p) => p.username === username)?.displayName ?? username;

  const all = allClaims ?? [];
  const awaiting = all.filter((c) => c.status === "awaiting-manager");
  const approvedThisMonth = all.filter((c) => c.status === "awaiting-finance" || c.status === "ready-for-export" || c.status === "exported");
  const returnedCount = all.filter((c) => c.status === "returned").length;
  const approvedTotal = approvedThisMonth.reduce((sum, c) => sum + c.totalAmount, 0);
  const awaitingTotal = awaiting.reduce((sum, c) => sum + c.totalAmount, 0);
  const reportCount = new Set(awaiting.map((c) => c.claimant)).size;

  const filtered =
    claimant === "All reports"
      ? awaiting
      : awaiting.filter((c) => c.claimant === claimant);

  return (
    <PageContent>
      <PageTitle>
        <PageTitle.Header>Team Claims</PageTitle.Header>
        <PageTitle.Actions>
          <TextField select label="Filter" value={claimant} onChange={(e) => setClaimant(e.target.value)} sx={{ minWidth: 180 }}>
            <MenuItem value="All reports">All reports</MenuItem>
            {[...new Set(awaiting.map((c) => c.claimant))].map((username) => (
              <MenuItem key={username} value={username}>
                {nameOf(username)}
              </MenuItem>
            ))}
          </TextField>
        </PageTitle.Actions>
      </PageTitle>

      <Grid container spacing={2} sx={{ mb: 3 }}>
        <Grid size={{ xs: 12, md: 4 }}>
          <Card variant="outlined">
            <CardContent>
              <Typography variant="overline">Awaiting my approval</Typography>
              <Typography variant="h4">{awaiting.length}</Typography>
              <Typography variant="caption" color="text.secondary">
                claims from {reportCount} reports
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid size={{ xs: 12, md: 4 }}>
          <Card variant="outlined">
            <CardContent>
              <Typography variant="overline">Approved this month</Typography>
              <Typography variant="h4">{approvedThisMonth.length}</Typography>
              <Typography variant="caption" color="text.secondary">
                {formatAmount(approvedTotal)} total
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid size={{ xs: 12, md: 4 }}>
          <Card variant="outlined">
            <CardContent>
              <Typography variant="overline">Returned for correction</Typography>
              <Typography variant="h4">{returnedCount}</Typography>
              <Typography variant="caption" color="text.secondary">
                back with their owners
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      <PageTitle>
        <PageTitle.Header>Needs your approval</PageTitle.Header>
        <PageTitle.Actions>
          <Button
            variant="contained"
            endIcon={<ArrowRight size={18} />}
            disabled={filtered.length === 0}
            onClick={() => navigate(`/team-claims/${filtered[0].claimId}`)}
          >
            Review next
          </Button>
        </PageTitle.Actions>
      </PageTitle>

      {error !== null ? (
        <ErrorState message={error} />
      ) : allClaims === null ? (
        <LoadingState />
      ) : filtered.length === 0 ? (
        <Typography variant="body2" color="text.secondary" sx={{ py: 4 }}>
          No claims awaiting your approval.
        </Typography>
      ) : (
        <ListingTable.Container disablePaper sx={{ width: "100%" }}>
          <ListingTable>
            <ListingTable.Head>
              <ListingTable.Row>
                <ListingTable.Cell>Claimant</ListingTable.Cell>
                <ListingTable.Cell>Claim</ListingTable.Cell>
                <ListingTable.Cell>Total</ListingTable.Cell>
                <ListingTable.Cell>Submitted</ListingTable.Cell>
              </ListingTable.Row>
            </ListingTable.Head>
            <ListingTable.Body>
              {filtered.map((claim) => (
                <ListingTable.Row
                  key={claim.claimId}
                  hover
                  clickable
                  onClick={() => navigate(`/team-claims/${claim.claimId}`)}
                >
                  <ListingTable.Cell>{nameOf(claim.claimant)}</ListingTable.Cell>
                  <ListingTable.Cell>{claim.title}</ListingTable.Cell>
                  <ListingTable.Cell>{formatAmount(claim.totalAmount)}</ListingTable.Cell>
                  <ListingTable.Cell>{formatDate(claim.submittedAt)}</ListingTable.Cell>
                </ListingTable.Row>
              ))}
            </ListingTable.Body>
          </ListingTable>
        </ListingTable.Container>
      )}
    </PageContent>
  );
}