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

export function RingConnection({
  connection: suppliedConnection,
  onConnectionChange,
  ringClient = defaultRingClient,
}: {
  connection?: RingConnectionSnapshot;
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
      onConnectionChange={notifyConnection ?? (() => undefined)}
      ringClient={ringClient}
    />
  );
}

function RingConnectionView({
  connection,
  onConnectionChange,
  ringClient,
}: {
  connection: RingConnectionSnapshot;
  onConnectionChange: (connection: RingConnectionSnapshot) => void;
  ringClient: ConnectionClient;
}) {
  const [devices, setDevices] = useState(connection.devices);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => setDevices(connection.devices), [connection.devices]);

  const refresh = async () => {
    const next = await ringClient.getConnection();
    setDevices(next.devices);
    onConnectionChange(next);
    return next;
  };

  const run = async (command: () => Promise<unknown>) => {
    setPending(true);
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
      setPending(false);
    }
  };

  const scan = () => run(() => ringClient.scan());
  const connect = (device: RingDevice) => run(() => ringClient.connect(device));
  const disconnect = () => run(() => ringClient.disconnect());

  if (connection.connected && connection.device) {
    return (
      <section className="ring-connection is-connected" aria-label="Ring connection">
        <div className="connected-ring-visual" role="img" aria-label="Connected ring" />
        <div className="ring-device-copy">
          <p className="connection-status">Connected</p>
          <h2>{connection.device.name}</h2>
        </div>
        <button disabled={pending} onClick={() => void disconnect()} type="button">
          Disconnect
        </button>
        {error ? <p role="alert">{error}</p> : null}
      </section>
    );
  }

  return (
    <section className="ring-connection" aria-label="Ring connection">
      <div>
        <p className="connection-status">Not connected</p>
        <h2>Connect your ring</h2>
      </div>
      <button disabled={pending} onClick={() => void scan()} type="button">
        {pending ? "Scanning…" : "Scan for rings"}
      </button>
      {devices.length > 0 ? (
        <ul className="ring-device-list" aria-label="Discovered rings">
          {devices.map((device) => (
            <li key={device.address}>
              <button
                disabled={pending}
                onClick={() => void connect(device)}
                type="button"
              >
                {device.name}
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
