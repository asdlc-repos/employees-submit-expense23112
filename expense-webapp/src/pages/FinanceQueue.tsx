import { useEffect, useState, type JSX } from "react";
import { useNavigate } from "react-router-dom";
import {
  Button,
  Card,
  CardContent,
  Grid,
  ListingTable,
  MenuItem,
  PageContent,
  PageTitle,
  Tab,
  Tabs,
  TextField,
  Typography,
} from "@wso2/oxygen-ui";
import { ArrowRight } from "@wso2/oxygen-ui-icons-react";
import { api, formatAmount, formatDate, type Claim, type Person } from "../api";
import { ErrorState, LoadingState } from "./shared";

// FinanceQueue — "A finance reviewer checks manager-approved claims before export"

const TABS = [
  { label: "Awaiting review", status: "awaiting-finance" },
  { label: "Ready for export", status: "ready-for-export" },
  { label: "Exported", status: "exported" },
] as const;

export function FinanceQueuePage(): JSX.Element {
  const navigate = useNavigate();
  const [claims, setClaims] = useState<Claim[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<(typeof TABS)[number]["label"]>("Awaiting review");
  const [claimant, setClaimant] = useState("All");
  const [people, setPeople] = useState<Person[]>([]);

  const activeStatus = TABS.find((t) => t.label === tab)?.status ?? "awaiting-finance";

  useEffect(() => {
    let live = true;
    setError(null);
    setClaims(null);
    api.GET("/claims", { params: { query: { status: activeStatus } } })
      .then(({ data, error: err }) => {
        if (!live) return;
        if (data) setClaims(data.data);
        else setError(err?.message ?? "The request failed.");
      })
      .catch((e: unknown) => {
        if (live) setError(e instanceof Error ? e.message : "The request failed.");
      });
    return () => {
      live = false;
    };
  }, [activeStatus]);

  useEffect(() => {
    api.GET("/people")
      .then(({ data }) => setPeople(data ?? []))
      .catch(() => setPeople([]));
  }, []);

  const [awaitingCount, setAwaitingCount] = useState<number | null>(null);
  const [readyCount, setReadyCount] = useState<number | null>(null);
  const [exportedCount, setExportedCount] = useState<number | null>(null);
  const [exportFiles, setExportFiles] = useState<number>(0);

  useEffect(() => {
    // Stat values derive from the rows, one bulk request per status column.
    let live = true;
    api.GET("/claims", { params: { query: { status: "awaiting-finance" } } })
      .then(({ data }) => {
        if (live) setAwaitingCount(data?.data.length ?? 0);
      })
      .catch(() => {
        if (live) setAwaitingCount(0);
      });
    api.GET("/claims", { params: { query: { status: "ready-for-export" } } })
      .then(({ data }) => {
        if (live) setReadyCount(data?.data.length ?? 0);
      })
      .catch(() => {
        if (live) setReadyCount(0);
      });
    api.GET("/claims", { params: { query: { status: "exported" } } })
      .then(({ data }) => {
        if (live) setExportedCount(data?.data.length ?? 0);
      })
      .catch(() => {
        if (live) setExportedCount(0);
      });
    api.GET("/claims/exports")
      .then(({ data }) => {
        if (live) setExportFiles(data?.data.length ?? 0);
      })
      .catch(() => {
        if (live) setExportFiles(0);
      });
    return () => {
      live = false;
    };
  }, [activeStatus]);

  const nameOf = (username: string): string =>
    people.find((p) => p.username === username)?.displayName ?? username;

  const rows = claims ?? [];
  const filtered = claimant === "All" ? rows : rows.filter((c) => c.claimant === claimant);

  return (
    <PageContent>
      <PageTitle>
        <PageTitle.Header>Finance Review</PageTitle.Header>
        <PageTitle.Actions>
          <TextField select label="Claimant" value={claimant} onChange={(e) => setClaimant(e.target.value)} sx={{ minWidth: 180 }}>
            <MenuItem value="All">All</MenuItem>
            {[...new Set(rows.map((c) => c.claimant))].map((username) => (
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
              <Typography variant="overline">Awaiting review</Typography>
              <Typography variant="h4">{awaitingCount ?? "…"}</Typography>
              <Typography variant="caption" color="text.secondary">
                past manager approval
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid size={{ xs: 12, md: 4 }}>
          <Card variant="outlined">
            <CardContent>
              <Typography variant="overline">Ready for export</Typography>
              <Typography variant="h4">{readyCount ?? "…"}</Typography>
              <Typography variant="caption" color="text.secondary">
                approved and waiting
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid size={{ xs: 12, md: 4 }}>
          <Card variant="outlined">
            <CardContent>
              <Typography variant="overline">Exported this month</Typography>
              <Typography variant="h4">{exportedCount ?? "…"}</Typography>
              <Typography variant="caption" color="text.secondary">
                across {exportFiles} payroll {exportFiles === 1 ? "file" : "files"}
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      <PageTitle>
        <PageTitle.Header>Claims past manager approval</PageTitle.Header>
        <PageTitle.Actions>
          <Button
            variant="contained"
            endIcon={<ArrowRight size={18} />}
            disabled={filtered.length === 0}
            onClick={() => navigate(`/finance/claims/${filtered[0].claimId}`)}
          >
            Review next
          </Button>
        </PageTitle.Actions>
      </PageTitle>

      <Tabs value={tab} onChange={(_, value: string) => setTab(value as (typeof TABS)[number]["label"])} sx={{ mb: 2 }}>
        {TABS.map((t) => (
          <Tab key={t.label} value={t.label} label={t.label} />
        ))}
      </Tabs>

      {error !== null ? (
        <ErrorState message={error} />
      ) : claims === null ? (
        <LoadingState />
      ) : filtered.length === 0 ? (
        <Typography variant="body2" color="text.secondary" sx={{ py: 4 }}>
          No claims in this view.
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
                  onClick={() => navigate(`/finance/claims/${claim.claimId}`)}
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