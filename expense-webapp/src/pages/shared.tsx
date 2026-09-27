import { useEffect, useState } from "react";
import type { JSX } from "react";
import { Box, Typography } from "@wso2/oxygen-ui";
import { FileQuestion } from "@wso2/oxygen-ui-icons-react";

/** Request state for a screen's load call. */
export type LoadState<T> =
  | { status: "loading" }
  | { status: "error"; message: string }
  | { status: "ok"; data: T };

export function useLoad<T>(load: () => Promise<T>, deps: readonly unknown[]): LoadState<T> {
  const [state, setState] = useState<LoadState<T>>({ status: "loading" });
  useEffect(() => {
    let live = true;
    setState({ status: "loading" });
    load()
      .then((data) => {
        if (live) setState({ status: "ok", data });
      })
      .catch((err: unknown) => {
        if (live) {
          setState({
            status: "error",
            message: err instanceof Error ? err.message : "The request failed.",
          });
        }
      });
    return () => {
      live = false;
    };
  }, deps);
  return state;
}

export function LoadingState(): JSX.Element {
  return (
    <Box sx={{ textAlign: "center", py: 8 }}>
      <Typography variant="body1" color="text.secondary">
        Loading…
      </Typography>
    </Box>
  );
}

export function ErrorState({ message }: { message: string }): JSX.Element {
  return (
    <Box sx={{ textAlign: "center", py: 8 }}>
      <FileQuestion size={48} style={{ opacity: 0.3, marginBottom: 16 }} />
      <Typography variant="h6" gutterBottom>
        Something went wrong
      </Typography>
      <Typography variant="body2" color="text.secondary">
        {message}
      </Typography>
    </Box>
  );
}

export function EmptyState({ title, description }: { title: string; description: string }): JSX.Element {
  return (
    <Box sx={{ textAlign: "center", py: 8 }}>
      <Typography variant="h6" gutterBottom>
        {title}
      </Typography>
      <Typography variant="body2" color="text.secondary">
        {description}
      </Typography>
    </Box>
  );
}

/** Map the API's claim status onto the label the wireframes show. */
export const STATUS_LABELS: Record<string, { label: string; color: "default" | "info" | "success" | "warning" | "error" }> = {
  draft: { label: "Draft", color: "default" },
  "awaiting-manager": { label: "Awaiting manager", color: "info" },
  "awaiting-finance": { label: "Awaiting finance", color: "info" },
  "ready-for-export": { label: "Ready for export", color: "success" },
  returned: { label: "Returned", color: "warning" },
  exported: { label: "Exported", color: "default" },
};

export function statusLabel(status: string): { label: string; color: "default" | "info" | "success" | "warning" | "error" } {
  return STATUS_LABELS[status] ?? { label: status, color: "default" };
}