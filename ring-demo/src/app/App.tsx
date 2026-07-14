import { useEffect, useState } from "react";
import {
  Navigate,
  Outlet,
  Route,
  Routes,
  useLocation,
  useNavigate,
  useOutletContext,
} from "react-router-dom";

import { OperatorControls } from "../components/OperatorControls";
import {
  ApiError,
  backendClient as defaultBackendClient,
  type BackendClient,
} from "../lib/backend-client";
import {
  ringClient as defaultRingClient,
  type RingClient,
} from "../lib/ring-client";
import { FlashPage } from "../pages/FlashPage";
import { HomePage } from "../pages/HomePage";
import { AUTH_TOKEN_KEY, SetupPage } from "../pages/SetupPage";
import { VibePage } from "../pages/VibePage";
import { DemoProvider, type DemoRingClient } from "../state/demo-store";
import { useDemo } from "../state/demo-store";
import type { User } from "../lib/types";

type AppBackendClient = Pick<
  BackendClient,
  "login" | "register" | "me" | "flash" | "resetDemo"
>;
type AppRingClient = DemoRingClient &
  Pick<RingClient, "scan" | "connect" | "disconnect">;

function AuthGate({ backendClient }: { backendClient: AppBackendClient }) {
  const token = window.localStorage.getItem(AUTH_TOKEN_KEY);
  const [status, setStatus] = useState<
    "checking" | "valid" | "invalid" | "error"
  >(token ? "checking" : "invalid");
  const [error, setError] = useState<string | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let active = true;
    if (!token) return () => undefined;
    setStatus("checking");
    setError(null);
    void backendClient
      .me()
      .then((response) => {
        if (active) {
          setUser(response.user);
          setStatus("valid");
        }
      })
      .catch((authError: unknown) => {
        if (!active) return;
        if (
          authError instanceof ApiError &&
          (authError.status === 401 || authError.status === 403)
        ) {
          window.localStorage.removeItem(AUTH_TOKEN_KEY);
          setStatus("invalid");
          return;
        }
        setError(
          authError instanceof Error
            ? authError.message
            : "Could not verify your session",
        );
        setStatus("error");
      });
    return () => {
      active = false;
    };
  }, [attempt, backendClient, token]);

  if (status === "invalid") return <Navigate replace to="/setup" />;
  if (status === "checking") {
    return <main className="auth-check">Checking your session…</main>;
  }
  if (status === "error") {
    return (
      <main className="auth-check auth-error" role="alert">
        <p>{error}</p>
        <button onClick={() => setAttempt((value) => value + 1)} type="button">
          Retry authentication
        </button>
      </main>
    );
  }
  return <Outlet context={user} />;
}

function DemoLayout({
  backendClient,
  ringClient,
}: {
  backendClient: AppBackendClient;
  ringClient: AppRingClient;
}) {
  const user = useOutletContext<User>();
  return (
    <DemoProvider ringClient={ringClient}>
      <DemoShell backendClient={backendClient} email={user.email} />
    </DemoProvider>
  );
}

function DemoShell({
  backendClient,
  email,
}: {
  backendClient: AppBackendClient;
  email: string;
}) {
  const demo = useDemo();
  const location = useLocation();
  const navigate = useNavigate();

  useEffect(() => {
    if (location.pathname === "/") {
      void demo.setMode("idle").catch(() => undefined);
    }
  }, [demo.setMode, location.pathname]);

  return (
    <>
      <Outlet />
      <OperatorControls
        backendClient={backendClient}
        email={email}
        onUnauthorized={() => {
          window.localStorage.removeItem(AUTH_TOKEN_KEY);
          navigate("/setup", { replace: true });
        }}
        resetLocalExperience={demo.resetLocalExperience}
      />
    </>
  );
}

export function App({
  backendClient = defaultBackendClient,
  ringClient = defaultRingClient,
}: {
  backendClient?: AppBackendClient;
  ringClient?: AppRingClient;
}) {
  return (
    <Routes>
      <Route
        path="/setup"
        element={<SetupPage backendClient={backendClient} />}
      />
      <Route element={<AuthGate backendClient={backendClient} />}>
        <Route
          element={
            <DemoLayout
              backendClient={backendClient}
              ringClient={ringClient}
            />
          }
        >
          <Route path="/" element={<HomePage />} />
          <Route
            path="/flash"
            element={
              <FlashPage
                backendClient={backendClient}
                ringClient={ringClient}
              />
            }
          />
          <Route
            path="/vibe"
            element={<VibePage ringClient={ringClient} />}
          />
        </Route>
      </Route>
      <Route path="*" element={<Navigate replace to="/" />} />
    </Routes>
  );
}
