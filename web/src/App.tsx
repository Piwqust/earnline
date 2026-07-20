import { lazy, useEffect } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import { syncController } from "./state/store";
import { useSettings } from "./state/settings";
import { AppShell } from "./ui/components/AppShell";
import { AuthCallback, AuthGate } from "./auth/AuthGate";
import { authStore, useAuthState } from "./auth/authStore";

const LedgerView = lazy(() => import("./ui/LedgerView").then((module) => ({ default: module.LedgerView })));
const ClientDetailView = lazy(() =>
  import("./ui/ClientDetailView").then((module) => ({ default: module.ClientDetailView })),
);
const SettingsView = lazy(() => import("./ui/SettingsView").then((module) => ({ default: module.SettingsView })));

const THEME_COLOR = { light: "#F4F5F7", dark: "#14161b" };

export default function App() {
  const theme = useSettings().theme;
  const auth = useAuthState();

  useEffect(() => {
    authStore.start();
    return () => authStore.stop();
  }, []);

  useEffect(() => {
    if (auth.status === "ready") void syncController.activateAuthenticatedSession();
    else syncController.stop();
  }, [auth.status]);

  // Apply the theme preference (omit the attribute for "auto" so the OS drives
  // it via prefers-color-scheme) and keep the browser chrome color in sync.
  useEffect(() => {
    const root = document.documentElement;
    if (theme === "auto") delete root.dataset.theme;
    else root.dataset.theme = theme;

    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const paint = () => {
      const dark = theme === "dark" || (theme === "auto" && mq.matches);
      document
        .querySelector('meta[name="theme-color"]')
        ?.setAttribute("content", dark ? THEME_COLOR.dark : THEME_COLOR.light);
    };
    paint();
    if (theme === "auto") {
      mq.addEventListener("change", paint);
      return () => mq.removeEventListener("change", paint);
    }
  }, [theme]);

  return (
    <Routes>
      <Route path="/auth/callback" element={<AuthCallback />} />
      {auth.status === "ready" ? <Route element={<AppShell />}>
        <Route path="/" element={<LedgerView />} />
        <Route path="/client/:id" element={<ClientDetailView />} />
        <Route path="/settings" element={<SettingsView />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route> : <Route path="*" element={<AuthGate />} />}
    </Routes>
  );
}
