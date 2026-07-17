import { type FormEvent, useState } from "react";
import { useNavigate } from "react-router-dom";

import {
  backendClient as defaultBackendClient,
  type BackendClient,
} from "../lib/backend-client";

export const AUTH_TOKEN_KEY = "eureka.authToken";

type AuthClient = Pick<BackendClient, "login" | "register">;

export function SetupPage({
  backendClient = defaultBackendClient,
}: {
  backendClient?: AuthClient;
}) {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const authenticate = async (action: "login" | "register") => {
    if (!email.trim() || password.length < 6 || pending) return;
    setPending(true);
    setError(null);
    try {
      const result = await backendClient[action](email.trim(), password);
      window.localStorage.setItem(AUTH_TOKEN_KEY, result.token);
      navigate("/", { replace: true });
    } catch (authError) {
      setError(
        authError instanceof Error ? authError.message : "Authentication failed",
      );
    } finally {
      setPending(false);
    }
  };

  const submit = (event: FormEvent) => {
    event.preventDefault();
    void authenticate("login");
  };

  return (
    <main className="setup-page">
      <section className="setup-copy" aria-labelledby="setup-title">
        <p className="eyebrow">EUREKA RING · OPERATOR</p>
        <h1 id="setup-title">Operator account setup</h1>
        <p>
          Only needed when preparing this Mac. Visitors will enter the demo
          directly after setup.
        </p>
      </section>

      <form className="auth-form" onSubmit={submit}>
        <label htmlFor="setup-email">Email</label>
        <input
          autoComplete="email"
          id="setup-email"
          onChange={(event) => setEmail(event.target.value)}
          required
          type="email"
          value={email}
        />

        <label htmlFor="setup-password">Password</label>
        <input
          autoComplete="current-password"
          id="setup-password"
          minLength={6}
          onChange={(event) => setPassword(event.target.value)}
          required
          type="password"
          value={password}
        />

        {error ? <p role="alert">{error}</p> : null}

        <div className="auth-actions">
          <button disabled={pending} type="submit">
            {pending ? "Signing in…" : "Sign in"}
          </button>
          <button
            disabled={pending}
            onClick={() => void authenticate("register")}
            type="button"
          >
            Create account
          </button>
        </div>
      </form>
    </main>
  );
}
