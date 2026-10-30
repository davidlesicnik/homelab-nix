import { existsSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';

// Bootstrap only the first install. Later changes, including authentication,
// environment names and connection settings, belong to the persisted UI state.
const marker = join(process.env.DATA_DIR, '.nixos-environment-initialized');
if (!existsSync(marker)) {
  const base = 'http://127.0.0.1:3000';
  const deadline = Date.now() + 90_000;
  let ready = false;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${base}/api/health`, { signal: AbortSignal.timeout(2_000) });
      if (response.ok) {
        ready = true;
        break;
      }
    } catch {
      // The application is still starting.
    }
    await sleep(500);
  }
  if (!ready) throw new Error('Dockhand did not become healthy within 90 seconds');

  const response = await fetch(`${base}/api/environments`);
  if (!response.ok) throw new Error(`Cannot read initial environments: HTTP ${response.status}`);
  const environments = await response.json();
  const local = environments.find(
    (environment) => environment.connectionType === 'socket'
      && environment.socketPath === '/var/run/docker.sock',
  );
  if (!local) {
    const created = await fetch(`${base}/api/environments`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: 'NixOS Podman',
        connectionType: 'socket',
        socketPath: '/var/run/docker.sock',
        publicIp: '192.168.10.20',
        icon: 'server',
        collectMetrics: true,
        collectActivity: true,
        highlightChanges: true,
      }),
    });
    if (!created.ok) throw new Error(`Cannot create local environment: HTTP ${created.status}`);
  }
  writeFileSync(marker, 'Local Podman environment initialized.\n', { mode: 0o600 });
  console.log('Dockhand local Podman environment initialized.');
}
