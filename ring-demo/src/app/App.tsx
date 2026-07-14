import { useEffect, useState } from "react";
import {
  Navigate,
  Outlet,
  Route,
  Routes,
} from "react-router-dom";

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

type AppBackendClient = Pick<
  BackendClient,
  "login" | "register" | "me" | "flash"
>;
type AppRingClient = DemoRingClient &
  Pick<RingClient, "scan" | "connect" | "disconnect">;

function AuthGate({ backendClient }: { backendClient: AppBackendClient }) {
  const token = window.localStorage.getItem(AUTH_TOKEN_KEY);
  const [status, setStatus] = useState<
    "checking" | "valid" | "invalid" | "error"
  >(token ? "checking" : "invalid");
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let active = true;
    if (!token) return () => undefined;
    setStatus("checking");
    setError(null);
    void backendClient
      .me()
      .then(() => {
        if (active) setStatus("valid");
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
  return <Outlet />;
}

function DemoLayout({
  ringClient,
}: {
  ringClient: AppRingClient;
}) {
  return (
    <DemoProvider ringClient={ringClient}>
      <Outlet />
    </DemoProvider>
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
        <Route element={<DemoLayout ringClient={ringClient} />}>
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
