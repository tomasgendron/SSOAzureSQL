import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { MsalProvider } from "@azure/msal-react";

import App from "./App.jsx";
import { msalInstance } from "./authConfig.js";
import "./styles.css";

function Root() {
  const [state, setState] = useState({ status: "loading", message: "" });

  useEffect(() => {
    async function initializeAuth() {
      try {
        await msalInstance.initialize();
        await msalInstance.handleRedirectPromise();
        setState({ status: "ready", message: "" });
      } catch (error) {
        setState({
          status: "error",
          message: error instanceof Error ? error.message : String(error),
        });
      }
    }

    initializeAuth();
  }, []);

  if (state.status === "loading") {
    return (
      <div className="startup">
        <div>
          <p className="eyebrow">Microsoft Entra SSO</p>
          <h1>Starting SQL SSO CRUD</h1>
        </div>
      </div>
    );
  }

  if (state.status === "error") {
    return (
      <div className="startup">
        <div>
          <p className="eyebrow">Microsoft Entra SSO</p>
          <h1>Startup error</h1>
          <p>{state.message}</p>
        </div>
      </div>
    );
  }

  return (
    <MsalProvider instance={msalInstance}>
      <App />
    </MsalProvider>
  );
}

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <Root />
  </React.StrictMode>,
);
