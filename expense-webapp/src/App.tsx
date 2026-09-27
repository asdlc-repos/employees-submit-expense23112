/**
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except in
 * compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Routing structure (prescribed by thunder-authentication's App.example.tsx):
//   /callback          outside the provider — no session to read yet
//   NoAccess           ABOVE the shell route — replaces it
//   /forbidden         INSIDE the shell — the rail stays
//   each gated route   wrapped in <RequireOperation op={screen.loads}>
//   landing            the first reachable rail screen

import { useEffect, type ReactElement } from "react";
import { Navigate, Route, Routes, useNavigate } from "react-router-dom";
import { Box, PageContent, Typography } from "@wso2/oxygen-ui";
import {
  AuthzProvider,
  Forbidden,
  NoAccess,
  RequireOperation,
  useAuthz,
  useScopes,
} from "./authz/gates";
import { SCREEN_ROUTES, hasScopedReach, reachableScreens } from "./authz/screens";
import { setForbiddenNavigator } from "./authz/client";
import { signIn } from "./authz/session";
import { AppShellLayout } from "./shell/AppShell";
import { CallbackPage } from "./pages/Callback";
import { MyClaimsPage } from "./pages/MyClaims";
import { NewClaimPage } from "./pages/NewClaim";
import { MyClaimDetailPage } from "./pages/MyClaimDetail";
import { EditClaimPage } from "./pages/EditClaim";
import { ManagerQueuePage } from "./pages/ManagerQueue";
import { ManagerClaimDetailPage } from "./pages/ManagerClaimDetail";
import { ManagerReturnClaimPage } from "./pages/ManagerReturnClaim";
import { FinanceQueuePage } from "./pages/FinanceQueue";
import { FinanceClaimDetailPage } from "./pages/FinanceClaimDetail";
import { FinanceReturnClaimPage } from "./pages/FinanceReturnClaim";
import { FinanceExportsPage } from "./pages/FinanceExports";
import { NotificationsPage } from "./pages/Notifications";

const APP_NAME = "Expense Claims";

const PAGE_BY_KEY: Record<string, ReactElement> = {
  myclaims: <MyClaimsPage />,
  notifications: <NotificationsPage />,
  managerqueue: <ManagerQueuePage />,
  financequeue: <FinanceQueuePage />,
  financeexports: <FinanceExportsPage />,
  newclaim: <NewClaimPage />,
  myclaimdetail: <MyClaimDetailPage />,
  editclaim: <EditClaimPage />,
  managerclaimdetail: <ManagerClaimDetailPage />,
  managerreturnclaim: <ManagerReturnClaimPage />,
  financeclaimdetail: <FinanceClaimDetailPage />,
  financereturnclaim: <FinanceReturnClaimPage />,
};

const PUBLIC_SCREENS = SCREEN_ROUTES.filter((screen) => screen.public);

export default function App(): ReactElement {
  return (
    <>
      <ForbiddenWiring />
      <Routes>
        <Route path="/callback" element={<CallbackPage />} />
        {PUBLIC_SCREENS.map((screen) => (
          <Route
            key={screen.key}
            path={screen.path}
            element={
              <AuthzProvider fallback={<Splash />}>{PAGE_BY_KEY[screen.key]}</AuthzProvider>
            }
          />
        ))}
        <Route
          path="*"
          element={
            <AuthzProvider fallback={<Splash />}>
              <SignedIn />
            </AuthzProvider>
          }
        />
      </Routes>
    </>
  );
}

function ForbiddenWiring(): null {
  const navigate = useNavigate();
  useEffect(() => {
    setForbiddenNavigator(() => navigate("/forbidden", { replace: true }));
  }, [navigate]);
  return null;
}

function Splash(): ReactElement {
  return (
    <PageContent>
      <Box sx={{ textAlign: "center", py: 8 }}>
        <Typography variant="h4" gutterBottom>
          {APP_NAME}
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Checking your session…
        </Typography>
      </Box>
    </PageContent>
  );
}

function SignedIn(): ReactElement {
  const { signedIn } = useAuthz();
  const scopes = useScopes();

  useEffect(() => {
    if (!signedIn) void signIn();
  }, [signedIn]);

  if (!signedIn) return <Splash />;

  if (!hasScopedReach(scopes, signedIn)) return <NoAccess appName={APP_NAME} />;

  const reachable = reachableScreens(scopes, signedIn);
  const landing = (reachable.find((s) => !s.public && s.loads !== null) ?? reachable[0]).path;

  return (
    <Routes>
      <Route element={<AppShellLayout />}>
        <Route index element={<Navigate to={landing} replace />} />
        {SCREEN_ROUTES.map((screen) => {
          if (screen.public) return null;
          const page = PAGE_BY_KEY[screen.key];
          if (screen.loads === null) {
            return <Route key={screen.key} path={screen.path} element={page} />;
          }
          return (
            <Route
              key={screen.key}
              element={<RequireOperation op={screen.loads} screen={screen.label} />}
            >
              <Route path={screen.path} element={page} />
            </Route>
          );
        })}
        <Route path="/forbidden" element={<Forbidden />} />
        <Route path="*" element={<Navigate to={landing} replace />} />
      </Route>
    </Routes>
  );
}