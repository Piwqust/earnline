import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import App from "./App";
import "@fontsource-variable/inter";
import "./ui/theme/tokens.css";
import "./ui/theme/base.css";
import "./ui/theme/shell.css";
import "./ui/theme/components.css";
import "./ui/theme/ledger.css";
import "./ui/theme/screens.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>,
);
