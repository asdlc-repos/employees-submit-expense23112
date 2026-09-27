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

// THE ONLY FILE THAT KNOWS ABOUT SCREENS, and all it says about each one is
// which API operation it LOADS. The gate follows: a screen is reachable when
// the caller may call that operation, and what the operation needs is in the
// contract, projected into ./operations.gen.ts. Nothing here names a scope, a
// role or a handle.
//
// THE ORDER OF THIS TABLE IS THE RAIL'S ORDER, and its first reachable row is
// the screen the app lands on. The wireframes draw the employee rail first
// (My Claims, Notifications), then the manager's Team Claims, then finance's
// Finance Review and Exports.

import { canCall } from "./core";
import { OPERATIONS, isOperationKey, type OperationKey } from "./operations.gen";

export interface ScreenRoute {
  readonly key: string;
  readonly label: string;
  readonly path: string;
  readonly loads: OperationKey | null;
  readonly public?: boolean;
}

export const SCREEN_ROUTES: readonly ScreenRoute[] = [
  // Employee + shared rail
  { key: "myclaims", label: "My Claims", path: "/claims/mine", loads: "GET /me/claims" },
  { key: "notifications", label: "Notifications", path: "/notifications", loads: "GET /me/notifications" },
  // Manager rail
  { key: "managerqueue", label: "Team Claims", path: "/team-claims", loads: "GET /me/reports/claims" },
  // Finance rail
  { key: "financequeue", label: "Finance Queue", path: "/finance", loads: "GET /claims" },
  { key: "financeexports", label: "Exports", path: "/finance/exports", loads: "GET /claims/exports" },
  // Screens off the rail (reached by navigation from the ones above)
  { key: "newclaim", label: "New Claim", path: "/claims/new", loads: "POST /me/claims" },
  { key: "myclaimdetail", label: "My Claim", path: "/claims/mine/:claimId", loads: "GET /me/claims/{claimId}" },
  { key: "editclaim", label: "Edit Claim", path: "/claims/mine/:claimId/edit", loads: "GET /me/claims/{claimId}" },
  { key: "managerclaimdetail", label: "Team Claim", path: "/team-claims/:claimId", loads: "GET /me/reports/claims/{claimId}" },
  { key: "managerreturnclaim", label: "Return Team Claim", path: "/team-claims/:claimId/return", loads: "POST /me/reports/claims/{claimId}/return" },
  { key: "financeclaimdetail", label: "Finance Claim", path: "/finance/claims/:claimId", loads: "GET /claims/{claimId}" },
  { key: "financereturnclaim", label: "Return Finance Claim", path: "/finance/claims/:claimId/return", loads: "POST /claims/{claimId}/return" },
];

// FAIL LOUDLY at module load: a committed operations.gen.ts that went stale
// against a contract nobody regenerated from. `loads` is typed as an
// OperationKey so tsc catches the rest.
for (const screen of SCREEN_ROUTES) {
  if (screen.loads !== null && !isOperationKey(screen.loads)) {
    throw new Error(
      `src/authz/screens.ts: screen "${screen.label}" loads "${screen.loads}", which ` +
        `no contract declares. Re-run \`npm run gen\`, or name the operation the ` +
        `way openapi.yaml spells it.`,
    );
  }
}

export function reachableScreens(
  scopes: ReadonlySet<string>,
  signedIn: boolean,
): readonly ScreenRoute[] {
  return SCREEN_ROUTES.filter((screen) => {
    if (screen.public) return true;
    if (screen.loads === null) return signedIn;
    return canCall(OPERATIONS[screen.loads], scopes, signedIn);
  });
}

export function hasScopedReach(scopes: ReadonlySet<string>, signedIn: boolean): boolean {
  return reachableScreens(scopes, signedIn).some((screen) => !screen.public && screen.loads !== null);
}