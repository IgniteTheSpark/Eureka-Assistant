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
  const [valid, setValid] = useState<boolean | null>(token ? null : false);

  useEffect(() => {
    let active = true;
    if (!token) return () => undefined;
    void backendClient
      .me()
      .then(() => {
        if (active) setValid(true);
      })
      .catch(() => {
        window.localStorage.removeItem(AUTH_TOKEN_KEY);
        if (active) setValid(false);
      });
    return () => {
      active = false;
    };
  }, [backendClient, token]);

  if (valid === false) return <Navigate replace to="/setup" />;
  if (valid === null) {
    return <main className="auth-check">Checking your session…</main>;
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
