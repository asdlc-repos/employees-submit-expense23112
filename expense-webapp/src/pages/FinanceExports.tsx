import { useEffect, useState, type JSX } from "react";
import { useNavigate } from "react-router-dom";
import {
  AppBreadcrumbs,
  Box,
  Button,
  ListingTable,
  PageContent,
  PageTitle,
  Typography,
} from "@wso2/oxygen-ui";
import { Download } from "@wso2/oxygen-ui-icons-react";
import { api, formatAmount, formatDateTime, type ExportRecord } from "../api";
import { ErrorState, LoadingState } from "./shared";
import { authorizationHeader } from "../authz/client";

// FinanceExports — "A finance reviewer downloads the payroll file and audits
// past exports"

export function FinanceExportsPage(): JSX.Element {
  const navigate = useNavigate();
  const [exports, setExports] = useState<ExportRecord[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    let live = true;
    setError(null);
    api.GET("/claims/exports")
      .then(({ data, error: err }) => {
        if (!live) return;
        if (data) setExports(data.data);
        else setError(err?.message ?? "The request failed.");
      })
      .catch((e: unknown) => {
        if (live) setError(e instanceof Error ? e.message : "The request failed.");
      });
    return () => {
      live = false;
    };
  }, [reloadKey]);

  const reload = (): void => setReloadKey((k) => k + 1);

  const downloadPayrollFile = async (): Promise<void> => {
    setBusy(true);
    try {
      const { data, error: err } = await api.POST("/claims/exports");
      if (!data) {
        setError(err?.message ?? "Could not build the payroll file.");
        return;
      }
      await downloadFile(data.exportId, data.fileFormat ?? "csv");
      reload();
    } finally {
      setBusy(false);
    }
  };

  const downloadFile = async (exportId: string, format: string): Promise<void> => {
    const header = await authorizationHeader();
    const response = await fetch(`/api/claims/exports/${exportId}`, {
      headers: header ? { Authorization: header } : undefined,
    });
    if (!response.ok) {
      setError(`Could not download the payroll file (${response.status}).`);
      return;
    }
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `payroll-export-${exportId}.${format.toLowerCase()}`;
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  };

  return (
    <PageContent>
      <Box sx={{ mb: 2 }}>
        <AppBreadcrumbs
          items={[
            { key: "finance", label: "Finance Review", onClick: () => navigate("/finance") },
            { key: "exports", label: "Exports" },
          ]}
        />
      </Box>
      <PageTitle>
        <PageTitle.Header>Payroll Exports</PageTitle.Header>
        <PageTitle.Actions>
          <Button
            variant="contained"
            startIcon={<Download size={18} />}
            onClick={() => void downloadPayrollFile()}
            disabled={busy}
          >
            Download payroll file
          </Button>
        </PageTitle.Actions>
      </PageTitle>

      <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
        The file holds every approved claim that has not been exported yet. Downloading marks
        each included claim exported with the date, and every affected employee is notified.
      </Typography>

      <Typography variant="h6" sx={{ mb: 1 }}>
        Past exports
      </Typography>
      {error !== null ? (
        <ErrorState message={error} />
      ) : exports === null ? (
        <LoadingState />
      ) : exports.length === 0 ? (
        <Typography variant="body2" color="text.secondary" sx={{ py: 4 }}>
          No payroll exports yet.
        </Typography>
      ) : (
        <ListingTable.Container disablePaper sx={{ width: "100%", mb: 2 }}>
          <ListingTable>
            <ListingTable.Head>
              <ListingTable.Row>
                <ListingTable.Cell>Exported</ListingTable.Cell>
                <ListingTable.Cell>Claims</ListingTable.Cell>
                <ListingTable.Cell>Total</ListingTable.Cell>
                <ListingTable.Cell>File</ListingTable.Cell>
              </ListingTable.Row>
            </ListingTable.Head>
            <ListingTable.Body>
              {exports.map((record) => (
                <ListingTable.Row key={record.exportId}>
                  <ListingTable.Cell>{formatDateTime(record.exportedAt)}</ListingTable.Cell>
                  <ListingTable.Cell>{record.claimCount}</ListingTable.Cell>
                  <ListingTable.Cell>{formatAmount(record.totalAmount)}</ListingTable.Cell>
                  <ListingTable.Cell>
                    <Typography
                      variant="body2"
                      sx={{ cursor: "pointer", color: "primary.main" }}
                      onClick={() => void downloadFile(record.exportId, record.fileFormat)}
                    >
                      {record.fileFormat}
                    </Typography>
                  </ListingTable.Cell>
                </ListingTable.Row>
              ))}
            </ListingTable.Body>
          </ListingTable>
        </ListingTable.Container>
      )}

      <Typography variant="body2" color="text.secondary">
        Each row's file can be downloaded again — check the exported date on a claim before
        re-loading a file, so nothing is reimbursed twice.
      </Typography>
    </PageContent>
  );
}