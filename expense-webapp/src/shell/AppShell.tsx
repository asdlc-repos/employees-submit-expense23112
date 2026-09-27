import {
  AppShell,
  ColorSchemeToggle,
  Divider,
  Footer,
  Header,
  Sidebar,
  UserMenu,
  version as OXYGEN_UI_VERSION,
} from "@wso2/oxygen-ui";
import {
  Bell,
  FileSpreadsheet,
  FileText,
  Inbox,
  LogOut,
  Users,
} from "@wso2/oxygen-ui-icons-react";
import { Outlet, Link as NavigateLink, useLocation } from "react-router-dom";
import type { JSX } from "react";
import { Can, useAuthz } from "../authz/gates";
import { SCREEN_ROUTES } from "../authz/screens";
import { signOut } from "../authz/session";
import { WSO2 } from "@wso2/oxygen-ui-icons-react";
import { Box } from "@wso2/oxygen-ui";

const RAIL_ICONS: Record<string, JSX.Element> = {
  myclaims: <FileText size={18} />,
  notifications: <Bell size={18} />,
  managerqueue: <Users size={18} />,
  financequeue: <Inbox size={18} />,
  financeexports: <FileSpreadsheet size={18} />,
};

// Only the rail items the wireframes' sidebars draw — screens off the rail
// (forms, detail pages) are reached by navigation, not the sidebar.
const RAIL_KEYS = ["myclaims", "notifications", "managerqueue", "financequeue", "financeexports"] as const;

function activeFromPath(pathname: string): string {
  if (pathname.startsWith("/team-claims")) return "managerqueue";
  if (pathname.startsWith("/finance/exports")) return "financeexports";
  if (pathname.startsWith("/finance")) return "financequeue";
  if (pathname.startsWith("/claims")) return "myclaims";
  return "myclaims";
}

export function AppShellLayout(): JSX.Element {
  const { pathname } = useLocation();
  const { username } = useAuthz();
  const active = activeFromPath(pathname);

  return (
    <AppShell initialCollapsed={false} collapseOnSelectOnMobile={true}>
      <AppShell.Navbar>
        <Header>
          <Header.Toggle />
          <Header.Brand>
            <Header.BrandTitle>Expense Claims</Header.BrandTitle>
          </Header.Brand>
          <Header.Spacer />
          <Header.Actions>
            <ColorSchemeToggle />
            <Divider orientation="vertical" flexItem sx={{ mx: 2 }} />
            <UserMenu>
              <UserMenu.Trigger name={username || "Signed in"} />
              <UserMenu.Header name={username || "Signed in"} email="" />
              <UserMenu.Divider />
              <UserMenu.Logout
                icon={<LogOut size={18} />}
                onClick={() => void signOut()}
              />
            </UserMenu>
          </Header.Actions>
        </Header>
      </AppShell.Navbar>

      <AppShell.Sidebar>
        <Sidebar activeItem={active}>
          <Sidebar.Nav>
            <Sidebar.Category>
              {SCREEN_ROUTES.filter((screen) =>
                (RAIL_KEYS as readonly string[]).includes(screen.key),
              ).map((screen) => (
                <Can key={screen.key} op={screen.loads!} fallback={null}>
                  <Sidebar.Item
                    id={screen.key}
                    link={<NavigateLink to={screen.path} />}
                  >
                    <Sidebar.ItemIcon>{RAIL_ICONS[screen.key]}</Sidebar.ItemIcon>
                    <Sidebar.ItemLabel>{screen.label}</Sidebar.ItemLabel>
                  </Sidebar.Item>
                </Can>
              ))}
            </Sidebar.Category>
          </Sidebar.Nav>
          <Sidebar.Footer>
            <Sidebar.Category>
              <Sidebar.Item id="settings">
                <Sidebar.ItemIcon>
                  <Users size={18} />
                </Sidebar.ItemIcon>
                <Sidebar.ItemLabel>Settings</Sidebar.ItemLabel>
              </Sidebar.Item>
            </Sidebar.Category>
          </Sidebar.Footer>
        </Sidebar>
      </AppShell.Sidebar>

      <AppShell.Main>
        <Outlet />
      </AppShell.Main>

      <AppShell.Footer>
        <Footer>
          <Footer.Copyright>
            © {new Date().getFullYear()} |
            <Box sx={{ verticalAlign: "middle", mt: 0.2, mx: 0.5, display: "inline-block" }}>
              <WSO2 size={12} />
            </Box>
            WSO2 LLC.
          </Footer.Copyright>
          <Footer.Divider />
          <Footer.Version>oxygen-ui-v{OXYGEN_UI_VERSION}</Footer.Version>
        </Footer>
      </AppShell.Footer>
    </AppShell>
  );
}