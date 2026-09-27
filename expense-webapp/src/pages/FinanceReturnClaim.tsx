import { useEffect, useState, type JSX } from "react";
import { useNavigate, useParams } from "react-router-dom";
import {
  AppBreadcrumbs,
  Box,
  Button,
  PageContent,
  PageTitle,
  Stack,
  TextField,
  Typography,
} from "@wso2/oxygen-ui";
import { api, formatAmount, type Claim, type Person } from "../api";
import { ErrorState, LoadingState, useLoad } from "./shared";

// FinanceReturnClaim — "A finance reviewer sends a claim back with a comment
// for correction"

export function FinanceReturnClaimPage(): JSX.Element {
  const { claimId = "" } = useParams();
  const navigate = useNavigate();
  const [comment, setComment] = useState("");
  const [commentError, setCommentError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [people, setPeople] = useState<Person[]>([]);

  const state = useLoad<Claim>(
    () => api.GET("/claims/{claimId}", { params: { path: { claimId } } }).then((r) => {
      if (r.data) return r.data;
      throw new Error(r.error?.message ?? "The claim could not be loaded.");
    }),
    [claimId],
  );

  const claimantName = (claim: Claim): string => {
    const match = people.find((p) => p.username === claim.claimant);
    return match?.displayName ?? claim.claimant;
  };

  useEffect(() => {
    let live = true;
    api.GET("/people")
      .then(({ data }) => {
        if (live) setPeople(data ?? []);
      })
      .catch(() => {
        if (live) setPeople([]);
      });
    return () => {
      live = false;
    };
  }, []);

  const submitReturn = async (): Promise<void> => {
    if (!comment.trim()) {
      setCommentError("Say why the claim is being returned.");
      return;
    }
    setBusy(true);
    try {
      const { error } = await api.POST("/claims/{claimId}/return", {
        params: { path: { claimId } },
        body: { comment },
      });
      if (error) {
        setCommentError(error.message ?? "Could not return the claim.");
        return;
      }
      navigate("/finance");
    } finally {
      setBusy(false);
    }
  };

  if (state.status === "loading") return <PageContent><LoadingState /></PageContent>;
  if (state.status === "error") return <PageContent><ErrorState message={state.message} /></PageContent>;

  const claim = state.data;

  return (
    <PageContent>
      <Box sx={{ mb: 2 }}>
        <AppBreadcrumbs
          items={[
            { key: "queue", label: "Finance Review", onClick: () => navigate("/finance") },
            { key: "claimant", label: claimantName(claim) },
            { key: "return", label: "Return" },
          ]}
        />
      </Box>
      <PageTitle>
        <PageTitle.Header>Return claim for correction</PageTitle.Header>
      </PageTitle>

      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        {claim.title} — {claimantName(claim)} — {formatAmount(claim.totalAmount)} total
      </Typography>

      <Stack spacing={2} sx={{ maxWidth: 720 }}>
        <TextField
          multiline
          minRows={4}
          label="Why is this being returned? — e.g. duplicate hotel night on 9 Oct"
          value={comment}
          onChange={(e) => {
            setComment(e.target.value);
            setCommentError(null);
          }}
          error={commentError !== null}
          helperText={commentError ?? undefined}
          fullWidth
        />
        <Box sx={{ display: "flex", justifyContent: "flex-end", gap: 2 }}>
          <Button variant="outlined" onClick={() => navigate(`/finance/claims/${claimId}`)}>
            Cancel
          </Button>
          <Button variant="contained" onClick={() => void submitReturn()} disabled={busy}>
            Return claim
          </Button>
        </Box>
      </Stack>
    </PageContent>
  );
}