import { useEffect, useState } from "react";

import {
  ringClient as defaultRingClient,
  type RingClient,
} from "../lib/ring-client";
import type { RingConnectionSnapshot, RingDevice } from "../lib/types";
import { useOptionalDemo } from "../state/demo-store";

type ConnectionClient = Pick<
  RingClient,
  "scan" | "getConnection" | "connect" | "disconnect"
>;

export interface RingConnectionCopy {
  connectTitle: string;
  connected: string;
  connecting: string;
  disconnect: string;
  disconnected: string;
  discoveredLabel: string;
  scan: string;
  scanning: string;
}

const DEFAULT_COPY: RingConnectionCopy = {
  connectTitle: "Connect your ring",
  connected: "Connected",
  connecting: "Connecting…",
  disconnect: "Disconnect",
  disconnected: "Not connected",
  discoveredLabel: "Discovered rings",
  scan: "Scan for rings",
  scanning: "Scanning…",
};

export function RingConnection({
  connection: suppliedConnection,
  copy: suppliedCopy,
  onActivityChange,
  onConnectionChange,
  ringClient = defaultRingClient,
}: {
  connection?: RingConnectionSnapshot;
  copy?: Partial<RingConnectionCopy>;
  onActivityChange?: (status: "scanning" | "connecting" | "disconnecting" | null) => void;
  onConnectionChange?: (connection: RingConnectionSnapshot) => void;
  ringClient?: ConnectionClient;
}) {
  const demo = useOptionalDemo();
  const connection = suppliedConnection ?? demo?.connection;
  if (!connection) {
    throw new Error("RingConnection requires a DemoProvider or connection prop");
  }
  const notifyConnection = onConnectionChange ?? demo?.updateConnection;
  return (
    <RingConnectionView
      connection={connection}
      copy={{ ...DEFAULT_COPY, ...suppliedCopy }}
      onActivityChange={onActivityChange}
      onConnectionChange={notifyConnection ?? (() => undefined)}
      ringClient={ringClient}
    />
  );
}

function RingConnectionView({
  connection,
  copy,
  onActivityChange,
  onConnectionChange,
  ringClient,
}: {
  connection: RingConnectionSnapshot;
  copy: RingConnectionCopy;
  onActivityChange?: (status: "scanning" | "connecting" | "disconnecting" | null) => void;
  onConnectionChange: (connection: RingConnectionSnapshot) => void;
  ringClient: ConnectionClient;
}) {
  const [devices, setDevices] = useState(connection.devices);
  const [pendingAction, setPendingAction] = useState<
    "scan" | "connect" | "disconnect" | null
  >(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => setDevices(connection.devices), [connection.devices]);

  const refresh = async () => {
    const next = await ringClient.getConnection();
    setDevices(next.devices);
    onConnectionChange(next);
    return next;
  };

  const run = async (
    action: "scan" | "connect" | "disconnect",
    command: () => Promise<unknown>,
  ) => {
    setPendingAction(action);
    onActivityChange?.(
      action === "scan" ? "scanning" : action === "connect" ? "connecting" : "disconnecting",
    );
    setError(null);
    try {
      await command();
      await refresh();
    } catch (connectionError) {
      setError(
        connectionError instanceof Error
          ? connectionError.message
          : "Could not reach Ring Desktop",
      );
    } finally {
      setPendingAction(null);
      onActivityChange?.(null);
    }
  };

  const scan = () => run("scan", () => ringClient.scan());
  const connect = (device: RingDevice) =>
    run("connect", () => ringClient.connect(device));
  const disconnect = () => run("disconnect", () => ringClient.disconnect());
  const scanning = connection.status === "scanning" || pendingAction === "scan";
  const connecting =
    connection.status === "connecting" || pendingAction === "connect";
  const pending = scanning || connecting || pendingAction === "disconnect";

  if (connection.connected && connection.device) {
    return (
      <section className="ring-connection is-connected" aria-label="Ring connection">
        <div className="connected-ring-visual" role="img" aria-label="Connected ring" />
        <div className="ring-device-copy">
          <p className="connection-status">{copy.connected}</p>
          <h2>{connection.device.name}</h2>
        </div>
        <button disabled={pending} onClick={() => void disconnect()} type="button">
          {copy.disconnect}
        </button>
        {error ? <p role="alert">{error}</p> : null}
      </section>
    );
  }

  return (
    <section className="ring-connection" aria-label="Ring connection">
      <div>
        <p className="connection-status">{copy.disconnected}</p>
        <h2>{copy.connectTitle}</h2>
      </div>
      <button disabled={pending} onClick={() => void scan()} type="button">
        {scanning ? copy.scanning : copy.scan}
      </button>
      {devices.length > 0 ? (
        <ul className="ring-device-list" aria-label={copy.discoveredLabel}>
          {devices.map((device) => (
            <li key={device.address}>
              <button
                disabled={pending}
                onClick={() => void connect(device)}
                type="button"
              >
                {connecting ? copy.connecting : device.name}
              </button>
            </li>
          ))}
        </ul>
      ) : null}
      {error || connection.lastError ? (
        <p role="alert">{error ?? connection.lastError}</p>
      ) : null}
    </section>
  );
}
