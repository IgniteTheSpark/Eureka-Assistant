import { useEffect, useState } from "react";
import {
  Link,
  Navigate,
  Outlet,
  Route,
  Routes,
} from "react-router-dom";

import { RingConnection } from "../components/RingConnection";
import {
  ApiError,
  backendClient as defaultBackendClient,
  type BackendClient,
} from "../lib/backend-client";
import {
  ringClient as defaultRingClient,
  type RingClient,
} from "../lib/ring-client";
import type { DemoMode } from "../lib/types";
import { HomePage } from "../pages/HomePage";
import { AUTH_TOKEN_KEY, SetupPage } from "../pages/SetupPage";
import {
  DemoProvider,
  type DemoRingClient,
  useDemo,
} from "../state/demo-store";

type AppBackendClient = Pick<BackendClient, "login" | "register" | "me">;
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

function ModePlaceholder({
  title,
  mode,
  ringClient,
}: {
  title: string;
  mode: DemoMode;
  ringClient: AppRingClient;
}) {
  const demo = useDemo();
  useEffect(() => {
    void demo.setMode(mode).catch(() => undefined);
  }, [demo.setMode, mode]);

  return (
    <main className="placeholder-page">
      <nav className="demo-nav" aria-label="Demo modes">
        <Link to="/">Home</Link>
        <Link to="/flash">Flash</Link>
        <Link to="/vibe">Vibe</Link>
      </nav>
      <p className="eyebrow">EUREKA RING</p>
      <h1>{title}</h1>
      <RingConnection ringClient={ringClient} />
    </main>
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
              <ModePlaceholder
                mode="flash"
                ringClient={ringClient}
                title="Flash Mode"
              />
            }
          />
          <Route
            path="/vibe"
            element={
              <ModePlaceholder
                mode="vibe"
                ringClient={ringClient}
                title="Vibe Mode"
              />
            }
          />
        </Route>
      </Route>
      <Route path="*" element={<Navigate replace to="/" />} />
    </Routes>
  );
}
