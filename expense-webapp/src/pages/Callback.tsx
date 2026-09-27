import { useEffect, useRef, type JSX } from "react";
import { useNavigate } from "react-router-dom";
import { Box, Button, Typography } from "@wso2/oxygen-ui";
import { handleCallback } from "../authz/session";

export function CallbackPage(): JSX.Element {
  const navigate = useNavigate();
  const started = useRef(false);

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    handleCallback()
      .then(() => {
        navigate("/", { replace: true });
      })
      .catch((err: unknown) => {
        console.error("callback: sign-in failed", err);
      });
  }, [navigate]);

  return (
    <Box sx={{ textAlign: "center", py: 8 }}>
      <Typography variant="h5">Signing you in…</Typography>
      <Button sx={{ mt: 2 }} variant="text" onClick={() => navigate("/")}>
        Continue
      </Button>
    </Box>
  );
}