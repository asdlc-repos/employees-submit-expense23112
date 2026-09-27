import { useEffect, useState, type JSX } from "react";
import {
  ListingTable,
  PageContent,
  PageTitle,
  Tab,
  Tabs,
  Typography,
} from "@wso2/oxygen-ui";
import { api, formatDate, type Notification } from "../api";
import { ErrorState, LoadingState } from "./shared";

// Notifications — "The notices the app records for the signed-in person,
// standing in for email"

const TABS = ["All", "Claim activity", "Exports"] as const;

export function NotificationsPage(): JSX.Element {
  const [tab, setTab] = useState<(typeof TABS)[number]>("All");
  const [items, setItems] = useState<Notification[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    api.GET("/me/notifications", { params: { query: { limit: 100 } } })
      .then(({ data, error: err }) => {
        if (!live) return;
        if (data) setItems(data.data);
        else setError(err?.message ?? "The request failed.");
      })
      .catch((e: unknown) => {
        if (live) setError(e instanceof Error ? e.message : "The request failed.");
      });
    return () => {
      live = false;
    };
  }, []);

  const rows = items ?? [];
  const filtered = rows.filter((n) => {
    if (tab === "All") return true;
    if (tab === "Exports") {
      return /export|payroll/i.test(n.subject) || /export|payroll/i.test(n.body);
    }
    return !/export|payroll/i.test(n.subject);
  });

  return (
    <PageContent>
      <PageTitle>
        <PageTitle.Header>Notifications</PageTitle.Header>
      </PageTitle>

      <Tabs value={tab} onChange={(_, value: (typeof TABS)[number]) => setTab(value)} sx={{ mb: 2 }}>
        {TABS.map((label) => (
          <Tab key={label} value={label} label={label} />
        ))}
      </Tabs>

      {error !== null ? (
        <ErrorState message={error} />
      ) : items === null ? (
        <LoadingState />
      ) : filtered.length === 0 ? (
        <Typography variant="body2" color="text.secondary" sx={{ py: 4 }}>
          No notifications.
        </Typography>
      ) : (
        <ListingTable.Container disablePaper sx={{ width: "100%" }}>
          <ListingTable>
            <ListingTable.Head>
              <ListingTable.Row>
                <ListingTable.Cell>Notice</ListingTable.Cell>
                <ListingTable.Cell>Claim</ListingTable.Cell>
                <ListingTable.Cell>When</ListingTable.Cell>
              </ListingTable.Row>
            </ListingTable.Head>
            <ListingTable.Body>
              {filtered.map((n) => (
                <ListingTable.Row key={n.notificationId}>
                  <ListingTable.Cell>{n.subject}</ListingTable.Cell>
                  <ListingTable.Cell>{n.body}</ListingTable.Cell>
                  <ListingTable.Cell>{formatDate(n.sentAt)}</ListingTable.Cell>
                </ListingTable.Row>
              ))}
            </ListingTable.Body>
          </ListingTable>
        </ListingTable.Container>
      )}
    </PageContent>
  );
}