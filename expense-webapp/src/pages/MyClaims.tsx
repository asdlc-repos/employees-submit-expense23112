import { useEffect, useState, type JSX } from "react";
import { useNavigate } from "react-router-dom";
import {
  Button,
  Chip,
  ListingTable,
  PageContent,
  PageTitle,
  Tab,
  Tabs,
  Typography,
} from "@wso2/oxygen-ui";
import { Plus } from "@wso2/oxygen-ui-icons-react";
import { api, formatAmount, formatDate, type Claim } from "../api";
import { ErrorState, LoadingState, statusLabel, useLoad } from "./shared";

// MyClaims — "An employee tracks the status of every claim they have filed"
const TABS = ["All", "Draft", "Awaiting approval", "Returned"] as const;

const TAB_STATUS: Record<(typeof TABS)[number], string | null> = {
  All: null,
  Draft: "draft",
  "Awaiting approval": "awaiting-manager",
  Returned: "returned",
};

export function MyClaimsPage(): JSX.Element {
  const navigate = useNavigate();
  const [tab, setTab] = useState<(typeof TABS)[number]>("All");

  const [claims, setClaims] = useState<Claim[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    setError(null);
    setClaims(null);
    const status = TAB_STATUS[tab];
    api.GET("/me/claims", { params: { query: status ? { status } : {} } })
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
  }, [tab]);

  return (
    <PageContent>
      <PageTitle>
        <PageTitle.Header>My Claims</PageTitle.Header>
        <PageTitle.Actions>
          <Button
            variant="contained"
            startIcon={<Plus size={18} />}
            onClick={() => navigate("/claims/new")}
          >
            New claim
          </Button>
        </PageTitle.Actions>
      </PageTitle>

      <Tabs value={tab} onChange={(_, value: (typeof TABS)[number]) => setTab(value)} sx={{ mb: 2 }}>
        {TABS.map((label) => (
          <Tab key={label} value={label} label={label} />
        ))}
      </Tabs>

      {error !== null ? (
        <ErrorState message={error} />
      ) : claims === null ? (
        <LoadingState />
      ) : claims.length === 0 ? (
        <ListingTable.Container disablePaper sx={{ width: "100%" }}>
          <ListingTable>
            <ListingTable.Head>
              <ListingTable.Row>
                <ListingTable.Cell>Claim</ListingTable.Cell>
                <ListingTable.Cell>Total</ListingTable.Cell>
                <ListingTable.Cell>Status</ListingTable.Cell>
                <ListingTable.Cell>Submitted</ListingTable.Cell>
              </ListingTable.Row>
            </ListingTable.Head>
            <ListingTable.Body>
              <ListingTable.Row>
                <ListingTable.Cell colSpan={4}>
                  <ListingTable.EmptyState
                    title="No claims here yet"
                    description="Nothing filed under this filter."
                  />
                </ListingTable.Cell>
              </ListingTable.Row>
            </ListingTable.Body>
          </ListingTable>
        </ListingTable.Container>
      ) : (
        <ListingTable.Container disablePaper sx={{ width: "100%" }}>
          <ListingTable>
            <ListingTable.Head>
              <ListingTable.Row>
                <ListingTable.Cell>Claim</ListingTable.Cell>
                <ListingTable.Cell>Total</ListingTable.Cell>
                <ListingTable.Cell>Status</ListingTable.Cell>
                <ListingTable.Cell>Submitted</ListingTable.Cell>
              </ListingTable.Row>
            </ListingTable.Head>
            <ListingTable.Body>
              {claims.map((claim) => {
                const status = statusLabel(claim.status);
                return (
                  <ListingTable.Row
                    key={claim.claimId}
                    hover
                    clickable
                    onClick={() => navigate(`/claims/mine/${claim.claimId}`)}
                  >
                    <ListingTable.Cell>
                      <Typography variant="body1">{claim.title}</Typography>
                    </ListingTable.Cell>
                    <ListingTable.Cell>{formatAmount(claim.totalAmount)}</ListingTable.Cell>
                    <ListingTable.Cell>
                      <Chip label={status.label} color={status.color} size="small" />
                    </ListingTable.Cell>
                    <ListingTable.Cell>{formatDate(claim.submittedAt ?? "")}</ListingTable.Cell>
                  </ListingTable.Row>
                );
              })}
            </ListingTable.Body>
          </ListingTable>
        </ListingTable.Container>
      )}
    </PageContent>
  );
}