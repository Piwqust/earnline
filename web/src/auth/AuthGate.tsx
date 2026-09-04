import { BrowserQRCodeReader } from "@zxing/browser";
import { useCallback, useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type MouseEvent, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { toDataURL } from "qrcode";
import { authStore, type AuthState, type PairedDevice, useAuthState } from "./authStore";
import { Button } from "../ui/components/Button";

const INTRO_SEEN_KEY = "earnline.auth-introduction.seen";

export function AuthGate() {
  const auth = useAuthState();
  const [pairing, setPairing] = useState(false);
  const [hasSeenIntroduction, setHasSeenIntroduction] = useState(readIntroductionState);
  const showWelcome = !hasSeenIntroduction && (auth.status === "signed-out" || auth.status === "error");

  const continueToAccount = () => {
    try { localStorage.setItem(INTRO_SEEN_KEY, "true"); } catch { /* The flow still works if storage is unavailable. */ }
    setHasSeenIntroduction(true);
  };

  return (
    <AuthShell step={showWelcome ? "01 / 02" : "02 / 02"}>
      {showWelcome ? <WelcomeStep onContinue={continueToAccount} /> : (
        <AuthContent auth={auth} onPair={() => setPairing(true)} />
      )}
      {pairing && <PairDeviceDialog onClose={() => setPairing(false)} />}
    </AuthShell>
  );
}

function readIntroductionState(): boolean {
  try { return localStorage.getItem(INTRO_SEEN_KEY) === "true"; } catch { return false; }
}

function AuthShell({ children, step }: { children: ReactNode; step: string }) {
  return <main className="auth-gate" aria-labelledby="auth-title">
    <aside className="auth-story" aria-label="Earnline introduction">
      <div className="auth-brand"><span className="auth-brand__signal" aria-hidden="true" />earn›line</div>
      <div className="auth-story__body">
        <p className="auth-kicker">PRIVATE, BY DEFAULT</p>
        <h2>Keep the work visible, not your business.</h2>
        <p>Earnline gives your finished work one quiet, personal place to land.</p>
      </div>
      <div className="auth-story__devices" aria-label="Your private workspace is available on your own devices">
        <span>Phone</span><i aria-hidden="true" /><span>Private workspace</span><i aria-hidden="true" /><span>Web</span>
      </div>
      <p className="auth-story__note">Your local app lock remains a separate control on each device.</p>
    </aside>
    <section className="auth-stage">
      <div className="auth-stage__mobile-brand"><span className="auth-brand__signal" aria-hidden="true" />earn›line</div>
      <div className="auth-stage__meta"><span>{step}</span><span>Private workspace</span></div>
      {children}
    </section>
  </main>;
}

function WelcomeStep({ onContinue }: { onContinue: () => void }) {
  return <div className="auth-flow auth-flow--welcome">
    <p className="auth-kicker">WELCOME TO EARNLINE</p>
    <h1 id="auth-title">Your work, kept in one clear place.</h1>
    <p className="auth-lede">A calm income ledger for the projects you finish, wherever you choose to review them.</p>
    <div className="auth-welcome-proof">
      <span className="auth-welcome-proof__lock" aria-hidden="true">✓</span>
      <p><strong>Private workspace</strong><br />The account you choose next identifies the ledger that belongs to you.</p>
    </div>
    <Button full variant="primary" size="lg" onClick={onContinue}>Get started</Button>
    <p className="auth-caption">You’ll choose a sign-in method next.</p>
  </div>;
}

function AuthContent({ auth, onPair }: { auth: AuthState; onPair: () => void }) {
  if (auth.status === "checking" || auth.status === "redirecting") {
    return <AuthProcessing message={auth.status === "redirecting" ? "Opening secure sign in…" : "Checking your account…"} />;
  }
  if (auth.status === "awaiting-workspace") return <WorkspacePending auth={auth} onPair={onPair} />;
  return <AccountChoice error={auth.status === "error" ? auth.message : undefined} onPair={onPair} />;
}

function AccountChoice({ error, onPair }: { error?: string; onPair: () => void }) {
  return <div className="auth-flow">
    <p className="auth-kicker">PRIVATE WORKSPACE</p>
    <h1 id="auth-title">Continue to your ledger.</h1>
    <p className="auth-lede">Choose the account that owns your workspace. You can add another device after you’re in.</p>
    {error && <p className="auth-error" role="alert"><strong>Couldn’t continue.</strong> {error}</p>}
    <ProviderButtons />
    <button className="auth-pair-link" type="button" onClick={onPair}>
      <span className="auth-pair-link__icon" aria-hidden="true">QR</span>
      <span><strong>Pair a device</strong><small>Scan a one-time code from your owner device</small></span>
      <span className="auth-pair-link__chevron" aria-hidden="true">›</span>
    </button>
    <p className="auth-trust">Your device app lock remains separate from sign in.</p>
  </div>;
}

function ProviderButtons() {
  return <div className="auth-providers" aria-label="Sign-in methods">
    <Button full variant="secondary" size="lg" className="auth-provider" trailing={<span aria-hidden="true">↗</span>} onClick={() => void authStore.beginOAuth("google")}>Continue with Google</Button>
    <Button full variant="secondary" size="lg" className="auth-provider" trailing={<span aria-hidden="true">↗</span>} onClick={() => void authStore.beginOAuth("github")}>Continue with GitHub</Button>
  </div>;
}

function WorkspacePending({ auth, onPair }: { auth: Extract<AuthState, { status: "awaiting-workspace" }>; onPair: () => void }) {
  return <div className="auth-flow auth-pending">
    <p className="auth-kicker">ONE STEP REMAINS</p>
    <h1 id="auth-title">{auth.isPairedDevice ? "Finish pairing this device." : "Your account is ready."}</h1>
    <p>{auth.isPairedDevice
      ? "Scan a new one-time code from your owner device. The code connects this device only."
      : "One private workspace step remains. When it’s complete, check again and we’ll open your ledger."}
    </p>
    <div className="auth-providers">
      <Button full variant="primary" size="lg" onClick={() => void authStore.refresh()}>Check again</Button>
      {auth.isPairedDevice && <Button full variant="secondary" size="lg" onClick={onPair}>Pair this device</Button>}
      <button className="auth-link" type="button" onClick={() => void authStore.signOut()}>Sign out</button>
    </div>
  </div>;
}

function AuthProcessing({ message }: { message: string }) {
  return <div className="auth-flow auth-processing" role="status">
    <span className="auth-spinner" aria-hidden />
    <p className="auth-kicker">PRIVATE WORKSPACE</p>
    <h1 id="auth-title">{message}</h1>
    <p className="auth-lede">Nothing syncs until your account and workspace are resolved.</p>
  </div>;
}

export function AuthCallback() {
  const navigate = useNavigate();
  const auth = useAuthState();
  const [callbackFinished, setCallbackFinished] = useState(false);
  useEffect(() => {
    void authStore.completeCallback().finally(() => setCallbackFinished(true));
  }, []);
  useEffect(() => {
    if (callbackFinished && (auth.status === "ready" || auth.status === "awaiting-workspace" || auth.status === "signed-out" || auth.status === "error")) {
      navigate("/", { replace: true });
    }
  }, [auth.status, callbackFinished, navigate]);
  return <AuthShell step="02 / 02"><AuthProcessing message="Completing sign in…" /></AuthShell>;
}

export function AccountDevicesPanel() {
  const auth = useAuthState();
  const [dialog, setDialog] = useState(false);
  const [devices, setDevices] = useState<PairedDevice[]>([]);
  const [devicesLoading, setDevicesLoading] = useState(false);
  const [deviceError, setDeviceError] = useState<string | null>(null);
  const [pendingRemoval, setPendingRemoval] = useState<PairedDevice | null>(null);
  const [renderedAt] = useState(Date.now);
  const canManageDevices = auth.status === "ready" && auth.role === "owner" && !auth.isPairedDevice;

  const loadDevices = useCallback(async () => {
    if (!canManageDevices) return;
    setDevicesLoading(true);
    setDeviceError(null);
    try { setDevices(await authStore.listDevices()); }
    catch (error) { setDeviceError(error instanceof Error ? error.message : "Could not load paired devices."); }
    finally { setDevicesLoading(false); }
  }, [canManageDevices]);

  useEffect(() => {
    const frame = requestAnimationFrame(() => void loadDevices());
    return () => cancelAnimationFrame(frame);
  }, [loadDevices]);

  const removeDevice = async () => {
    if (!pendingRemoval) return;
    const device = pendingRemoval;
    setPendingRemoval(null);
    setDeviceError(null);
    try {
      await authStore.revokeDevice(device.userId);
      setDevices((current) => current.filter((item) => item.userId !== device.userId));
    } catch (error) {
      setDeviceError(error instanceof Error ? error.message : "Could not remove the paired device.");
    }
  };

  if (auth.status !== "ready") return null;
  return <section className="settings-group" aria-labelledby="account-devices-heading">
    <h2 className="settings-group__title" id="account-devices-heading">Account &amp; devices</h2>
    <div className="settings-card account-devices">
      <div className="setting-row"><span className="setting-row__label">Account</span><span className="setting-row__value">{auth.isPairedDevice ? "Paired device" : auth.email ?? "Signed-in account"}</span></div>
      <div className="setting-row"><span className="setting-row__label">This device</span><span className="setting-row__value">{auth.isPairedDevice ? "Paired" : "Owner"}</span></div>
      {auth.role === "owner" && !auth.isPairedDevice && <div className="paired-devices" aria-live="polite">
        <div className="paired-devices__heading">
          <span className="setting-row__label">Paired devices</span>
          <button className="auth-link" type="button" disabled={devicesLoading} onClick={() => void loadDevices()}>Refresh</button>
        </div>
        {devicesLoading ? <p className="auth-note">Loading devices…</p> : devices.length === 0 ? (
          <p className="auth-note">No other devices are connected.</p>
        ) : <ul className="paired-devices__list">
          {devices.map((device) => <li key={device.userId}>
            <span><strong>Paired device</strong><small>{device.lastSignInAt
              ? `Last signed in ${new Intl.RelativeTimeFormat(undefined, { numeric: "auto" }).format(Math.round((new Date(device.lastSignInAt).getTime() - renderedAt) / 86_400_000), "day")}`
              : `Added ${new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(device.createdAt))}`}</small></span>
            <Button variant="danger" onClick={() => setPendingRemoval(device)}>Remove</Button>
          </li>)}
        </ul>}
        {deviceError && <p className="auth-error" role="alert">{deviceError}</p>}
      </div>}
      <div className="settings-actions">
        {auth.role === "owner" && !auth.isPairedDevice && <Button variant="secondary" onClick={() => setDialog(true)}>Pair another device</Button>}
        <Button variant="danger" onClick={() => void authStore.signOut()}>Sign out</Button>
      </div>
    </div>
    {dialog && <PairingCodeDialog onClose={() => setDialog(false)} />}
    {pendingRemoval && <Dialog title="Remove paired device?" onClose={() => setPendingRemoval(null)}>
      <p>This device will be signed out and must scan a new code before it can sync again.</p>
      <div className="auth-dialog__actions">
        <Button variant="secondary" onClick={() => setPendingRemoval(null)}>Cancel</Button>
        <Button variant="danger" onClick={() => void removeDevice()}>Remove device</Button>
      </div>
    </Dialog>}
  </section>;
}

function PairDeviceDialog({ onClose }: { onClose: () => void }) {
  const [code, setCode] = useState("");
  const [camera, setCamera] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const input = useRef<HTMLInputElement>(null);
  const submit = () => void authStore.redeemPairingCode(code);

  return <Dialog title="Pair a device" onClose={onClose}>
    <p>Scan the one-time QR code shown on your owner device. It expires in 10 minutes and can be used once.</p>
    {camera ? <QrScanner onCode={(value) => { setCode(value); setCamera(false); }} onError={(value) => { setCameraError(value); setCamera(false); input.current?.focus(); }} /> : (
      <Button variant="secondary" onClick={() => setCamera(true)}>Use camera</Button>
    )}
    {cameraError && <p className="auth-error" role="alert">{cameraError}</p>}
    <label className="auth-field">Pairing code
      <input ref={input} className="input" value={code} onChange={(event) => setCode(event.target.value)} autoCapitalize="off" autoCorrect="off" spellCheck={false} />
    </label>
    <div className="auth-dialog__actions"><Button variant="secondary" onClick={onClose}>Cancel</Button><Button variant="primary" disabled={!code.trim()} onClick={submit}>Pair this device</Button></div>
  </Dialog>;
}

function PairingCodeDialog({ onClose }: { onClose: () => void }) {
  const [url, setUrl] = useState<string | null>(null);
  const [expiresAt, setExpiresAt] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => {
    setError(null); setUrl(null);
    try {
      const token = await authStore.createPairingToken();
      setExpiresAt(token.expiresAt);
      setUrl(await toDataURL(`earnline-pairing://v1/${token.token}`, { margin: 1, width: 280, errorCorrectionLevel: "M" }));
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Could not create a pairing code."); }
  }, []);
  useEffect(() => {
    const frame = requestAnimationFrame(() => void load());
    return () => cancelAnimationFrame(frame);
  }, [load]);
  return <Dialog title="Pair another device" onClose={onClose}>
    <p>Scan this QR code on the device you want to pair. It authorizes only that device.</p>
    {url ? <img className="pairing-qr" src={url} alt="One-time device pairing QR code" /> : !error && <div className="auth-status" role="status"><span className="auth-spinner" aria-hidden />Creating a secure code…</div>}
    {expiresAt && <p className="auth-note">Expires {new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(new Date(expiresAt))} and can be used once.</p>}
    {error && <p className="auth-error" role="alert">{error}</p>}
    <div className="auth-dialog__actions"><Button variant="secondary" onClick={() => void load()}>Generate a new code</Button><Button variant="primary" onClick={onClose}>Done</Button></div>
  </Dialog>;
}

function Dialog({ title, children, onClose }: { title: string; children: ReactNode; onClose: () => void }) {
  const dialog = useRef<HTMLElement>(null);
  useEffect(() => {
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const frame = requestAnimationFrame(() => dialog.current?.querySelector<HTMLElement>("button, input, [tabindex]:not([tabindex='-1'])")?.focus());
    return () => {
      cancelAnimationFrame(frame);
      opener?.focus({ preventScroll: true });
    };
  }, []);
  const close = (event: MouseEvent<HTMLDivElement>) => { if (event.target === event.currentTarget) onClose(); };
  const trapFocus = (event: ReactKeyboardEvent<HTMLElement>) => {
    if (event.key === "Escape") { event.preventDefault(); onClose(); return; }
    if (event.key !== "Tab") return;
    const focusable = Array.from(dialog.current?.querySelectorAll<HTMLElement>("button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex='-1'])") ?? []);
    if (!focusable.length) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  };
  return <div className="auth-dialog-backdrop" role="presentation" onMouseDown={close}>
    <section ref={dialog} className="auth-dialog" role="dialog" aria-modal="true" aria-labelledby="pairing-dialog-title" onKeyDown={trapFocus}>
      <div className="auth-dialog__heading"><h2 id="pairing-dialog-title">{title}</h2><button className="auth-close" type="button" aria-label="Close" onClick={onClose}>×</button></div>
      {children}
    </section>
  </div>;
}

function QrScanner({ onCode, onError }: { onCode: (value: string) => void; onError: (message: string) => void }) {
  const video = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    if (!video.current) return;
    const reader = new BrowserQRCodeReader();
    let disposed = false;
    let controls: { stop: () => void } | undefined;
    reader.decodeFromVideoDevice(undefined, video.current, (result) => {
      if (!result || disposed) return;
      controls?.stop();
      onCode(result.getText());
    }).then((nextControls) => { controls = nextControls; }).catch(() => {
      if (!disposed) onError("Camera access was not granted. Enter the code manually instead.");
    });
    return () => { disposed = true; controls?.stop(); };
  }, [onCode, onError]);
  return <video className="pairing-camera" ref={video} muted playsInline aria-label="Pairing code camera preview" />;
}
