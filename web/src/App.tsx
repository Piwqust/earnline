import { useEffect } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import { syncController } from "./state/store";
import { AppShell } from "./ui/components/AppShell";
import { LedgerView } from "./ui/LedgerView";
import { ClientDetailView } from "./ui/ClientDetailView";
import { SettingsView } from "./ui/SettingsView";

export default function App() {
  useEffect(() => {
    syncController.start();
  }, []);

  return (
    <Routes>
      <Route element={<AppShell />}>
        <Route path="/" element={<LedgerView />} />
        <Route path="/client/:id" element={<ClientDetailView />} />
        <Route path="/settings" element={<SettingsView />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
