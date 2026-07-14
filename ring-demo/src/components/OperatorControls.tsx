import { useEffect, useRef, useState } from "react";

import {
  ApiError,
  type BackendClient,
} from "../lib/backend-client";

type OperatorBackendClient = Pick<BackendClient, "resetDemo">;

function validDeletionCounts(value: unknown): value is Record<string, number> {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.values(value).every(
      (count) =>
        typeof count === "number" &&
        Number.isFinite(count) &&
        count >= 0,
    )
  );
}

export function OperatorControls({
  email,
  backendClient,
  resetLocalExperience,
  onUnauthorized,
  flashProcessing,
}: {
  email: string;
  backendClient: OperatorBackendClient;
  resetLocalExperience: () => void;
  onUnauthorized: () => void;
  flashProcessing: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [pending, setPending] = useState(false);
  const [disabled, setDisabled] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const startResetRef = useRef<HTMLButtonElement>(null);
  const confirmResetRef = useRef<HTMLButtonElement>(null);
  const wasConfirmingRef = useRef(false);

  useEffect(() => {
    if (confirming) {
      confirmResetRef.current?.focus();
    } else if (wasConfirmingRef.current) {
      startResetRef.current?.focus();
    }
    wasConfirmingRef.current = confirming;
  }, [confirming]);

  const reset = async () => {
    if (pending || disabled || flashProcessing) return;
    setPending(true);
    setError(null);
    setMessage(null);
    try {
      const response = await backendClient.resetDemo();
      if (response.ok !== true || !validDeletionCounts(response.deleted)) {
        throw new Error("Invalid demo reset response");
      }
      const total = Object.values(response.deleted).reduce(
        (sum, count) => sum + count,
        0,
      );
      resetLocalExperience();
      setConfirming(false);
      setMessage(`${total} demo records deleted. The Ring session is still connected.`);
    } catch (resetError) {
      setConfirming(false);
      if (resetError instanceof ApiError && resetError.status === 409) {
        setError(
          "Flash is still processing. Wait for it to finish, then retry the reset.",
        );
      } else if (resetError instanceof ApiError && resetError.status === 404) {
        setDisabled(true);
        setError("Demo reset is not available on this server.");
      } else if (
        resetError instanceof ApiError &&
        (resetError.status === 401 || resetError.status === 403)
      ) {
        onUnauthorized();
      } else {
        setError(
          "Demo data could not be reset. The service may be under maintenance; your current experience was preserved.",
        );
      }
    } finally {
      setPending(false);
    }
  };

  return (
    <aside className="operator-controls">
      <button
        aria-controls="operator-controls-panel"
        aria-expanded={open}
        className="operator-controls-trigger"
        disabled={pending}
        onClick={() => setOpen((value) => !value)}
        type="button"
      >
        Operator controls
      </button>

      {open ? (
        <section
          aria-label="Operator controls panel"
          className="operator-controls-panel"
          id="operator-controls-panel"
        >
          <p className="operator-controls-label">SIGNED IN</p>
          <p className="operator-controls-email">{email}</p>

          {confirming ? (
            <div className="operator-reset-confirmation">
              <p>
                Delete this account&apos;s demo data? Your Ring connection will
                stay active.
              </p>
              <div className="operator-controls-actions">
                <button
                  className="operator-reset-confirm"
                  disabled={pending || flashProcessing}
                  onClick={() => void reset()}
                  ref={confirmResetRef}
                  type="button"
                >
                  {pending ? "Resetting demo data…" : "Confirm reset"}
                </button>
                <button
                  disabled={pending}
                  onClick={() => setConfirming(false)}
                  type="button"
                >
                  Cancel
                </button>
              </div>
            </div>
          ) : (
            <button
              className="operator-reset-start"
              disabled={disabled || pending || flashProcessing}
              onClick={() => {
                setConfirming(true);
                setError(null);
                setMessage(null);
              }}
              ref={startResetRef}
              type="button"
            >
              Reset demo data
            </button>
          )}

          {flashProcessing ? (
            <p className="operator-controls-notice" role="status">
              Wait for Flash to finish before resetting demo data.
            </p>
          ) : null}

          {message ? (
            <p className="operator-controls-success" role="status">
              {message}
            </p>
          ) : null}
          {error ? (
            <p className="operator-controls-error" role="alert">
              {error}
            </p>
          ) : null}
        </section>
      ) : null}
    </aside>
  );
}
