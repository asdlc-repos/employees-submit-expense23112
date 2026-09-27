import { useEffect, useRef, useState, type JSX } from "react";
import { useNavigate } from "react-router-dom";
import {
  AppBreadcrumbs,
  Box,
  Button,
  Card,
  CardContent,
  Form,
  ListingTable,
  MenuItem,
  PageContent,
  PageTitle,
  Stack,
  TextField,
  Typography,
} from "@wso2/oxygen-ui";
import { Paperclip, Plus } from "@wso2/oxygen-ui-icons-react";
import { api, formatAmount, type Claim } from "../api";
import { ErrorState, LoadingState } from "./shared";

// NewClaim — "An employee builds a new claim from expense lines with receipts"

const EMPTY_LINE = { expenseDate: "", category: "", description: "", amount: "" };

export function NewClaimPage(): JSX.Element {
  const navigate = useNavigate();

  const [claim, setClaim] = useState<Claim | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [title, setTitle] = useState("");
  const [claimError, setClaimError] = useState<string | null>(null);

  const [categories, setCategories] = useState<string[] | null>(null);
  const [line, setLine] = useState(EMPTY_LINE);
  const [lineError, setLineError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const fileInput = useRef<HTMLInputElement | null>(null);
  const pendingReceipt = useRef<{ fileName: string; contentType: string; content: string } | null>(null);

  // The categories list is finance-maintained: GET /categories (public).
  useEffect(() => {
    let live = true;
    api.GET("/categories")
      .then(({ data }) => {
        if (live) setCategories(data ?? []);
      })
      .catch(() => {
        if (live) setCategories([]);
      });
    return () => {
      live = false;
    };
  }, []);

  const ensureClaim = async (): Promise<Claim | null> => {
    if (claim) return claim;
    if (!title.trim()) {
      setClaimError("Give the claim a title first.");
      return null;
    }
    const { data, error } = await api.POST("/me/claims", { body: { title } });
    if (data) {
      setClaim(data);
      return data;
    }
    setClaimError(error?.message ?? "Could not create the draft claim.");
    return null;
  };

  const attachReceipt = (): void => {
    fileInput.current?.click();
  };

  const onReceiptPicked = (files: FileList | null): void => {
    const file = files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      pendingReceipt.current = {
        fileName: file.name,
        contentType: file.type || "application/octet-stream",
        content: String(reader.result).split(",")[1] ?? "",
      };
      setLine((l) => ({ ...l }));
    };
    reader.readAsDataURL(file);
  };

  const addLine = async (): Promise<void> => {
    setLineError(null);
    if (!line.expenseDate || !line.category || !line.description || !line.amount) {
      setLineError("Fill in every field of the expense line.");
      return;
    }
    setBusy(true);
    try {
      const target = await ensureClaim();
      if (!target) return;
      const { data: created, error } = await api.POST("/me/claims/{claimId}/lines", {
        params: { path: { claimId: target.claimId } },
        body: {
          expenseDate: line.expenseDate,
          category: line.category,
          amount: Number(line.amount),
          description: line.description,
        },
      });
      if (!created) {
        setLineError(error?.message ?? "Could not add the line.");
        return;
      }
      // The receipt belongs to the line it backs, so attach it right after the
      // line exists: every line needs a receipt before the claim can be submitted.
      const receipt = pendingReceipt.current;
      if (receipt) {
        const { error: uploadError } = await api.POST(
          "/me/claims/{claimId}/lines/{lineId}/receipt",
          {
            params: { path: { claimId: target.claimId, lineId: created.lineId } },
            body: { ...receipt, fileSize: Math.max(1, Math.floor((receipt.content.length * 3) / 4)) },
          },
        );
        if (uploadError) {
          setLineError(uploadError?.message ?? "Could not attach the receipt.");
          return;
        }
      }
      const refreshed = await api.GET("/me/claims/{claimId}", {
        params: { path: { claimId: target.claimId } },
      });
      if (refreshed.data) setClaim(refreshed.data);
      pendingReceipt.current = null;
      setLine(EMPTY_LINE);
    } finally {
      setBusy(false);
    }
  };

  const missingReceipt = (claim?.lines ?? []).some((l) => !l.receipt);
  const canSubmit = claim !== null && claim.lines.length > 0 && !missingReceipt && !busy;

  const submit = async (): Promise<void> => {
    if (!claim) return;
    setBusy(true);
    try {
      const { data, error } = await api.POST("/me/claims/{claimId}/submit", {
        params: { path: { claimId: claim.claimId } },
      });
      if (data) {
        navigate(`/claims/mine/${claim.claimId}`);
      } else {
        setError(error?.message ?? "Could not submit the claim.");
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
            { key: "new", label: "New claim" },
          ]}
        />
      </Box>
      <PageTitle>
        <PageTitle.Header>New Claim</PageTitle.Header>
      </PageTitle>

      {error !== null ? <ErrorState message={error} /> : (
        <Stack spacing={3}>
          <TextField
            label="Claim title — e.g. Client workshop in Leeds"
            value={title}
            onChange={(e) => {
              setTitle(e.target.value);
              setClaimError(null);
            }}
            error={claimError !== null}
            helperText={claimError ?? undefined}
            fullWidth
          />

          <Box>
            <Typography variant="h6" sx={{ mb: 1 }}>
              Expense lines
            </Typography>
            {claim === null || claim.lines.length === 0 ? (
              <Typography variant="body2" color="text.secondary" sx={{ py: 2 }}>
                No expense lines yet — add the first one below.
              </Typography>
            ) : (
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
                        <ListingTable.Cell>{l.receipt?.fileName ?? "—"}</ListingTable.Cell>
                      </ListingTable.Row>
                    ))}
                  </ListingTable.Body>
                </ListingTable>
              </ListingTable.Container>
            )}
          </Box>

          <Card variant="outlined">
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                Add an expense line
              </Typography>
              <Form.Section>
                <Form.Stack direction="row" spacing={2}>
                  <TextField
                    type="date"
                    label="Date"
                    slotProps={{ inputLabel: { shrink: true } }}
                    value={line.expenseDate}
                    onChange={(e) => setLine({ ...line, expenseDate: e.target.value })}
                  />
                  <TextField
                    select
                    label="Category"
                    value={line.category}
                    onChange={(e) => setLine({ ...line, category: e.target.value })}
                  >
                    <MenuItem value="" disabled>
                      Choose a category
                    </MenuItem>
                    {(categories ?? []).map((c) => (
                      <MenuItem key={c} value={c}>
                        {c}
                      </MenuItem>
                    ))}
                  </TextField>
                </Form.Stack>
                <Form.Stack direction="row" spacing={2} sx={{ mt: 2 }}>
                  <TextField
                    label="Description — what was it for?"
                    value={line.description}
                    onChange={(e) => setLine({ ...line, description: e.target.value })}
                    fullWidth
                  />
                  <TextField
                    label="Amount — 0.00"
                    value={line.amount}
                    onChange={(e) => setLine({ ...line, amount: e.target.value })}
                    inputProps={{ inputMode: "decimal" }}
                  />
                </Form.Stack>
                <Box sx={{ display: "flex", justifyContent: "flex-end", gap: 2, mt: 2 }}>
                  <input
                    ref={fileInput}
                    type="file"
                    accept="image/*"
                    style={{ display: "none" }}
                    onChange={(e) => onReceiptPicked(e.target.files)}
                  />
                  <Button
                    variant="outlined"
                    startIcon={<Paperclip size={18} />}
                    onClick={attachReceipt}
                  >
                    {pendingReceipt.current ? pendingReceipt.current.fileName : "Attach receipt"}
                  </Button>
                  <Button
                    variant="outlined"
                    startIcon={<Plus size={18} />}
                    onClick={() => void addLine()}
                    disabled={busy}
                  >
                    Add line
                  </Button>
                </Box>
                {lineError !== null && (
                  <Typography variant="caption" color="error" sx={{ mt: 1, display: "block" }}>
                    {lineError}
                  </Typography>
                )}
              </Form.Section>
            </CardContent>
          </Card>

          <Typography variant="body2" color="text.secondary">
            Every line needs a receipt before the claim can be submitted.
          </Typography>

          <Box sx={{ display: "flex", justifyContent: "flex-end" }}>
            <Button
              variant="contained"
              onClick={() => void submit()}
              disabled={!canSubmit}
            >
              Submit claim
            </Button>
          </Box>
        </Stack>
      )}
    </PageContent>
  );
}