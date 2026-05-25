import React from "react";
import { useEffect, useMemo, useState } from "react";
import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from "@azure/msal-react";
import { LogIn, LogOut, Plus, RefreshCw, Save, ShieldCheck, Trash2, X } from "lucide-react";

import { createItem, deleteItem, getItems, getMe, updateItem } from "./api.js";
import { loginRequest } from "./authConfig.js";

const emptyForm = {
  title: "",
  description: "",
  status: "Open",
};

function formatDate(value) {
  if (!value) {
    return "Never";
  }
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function useIdentityToken() {
  const { instance, accounts } = useMsal();

  return async function getToken() {
    const account = accounts[0];
    if (!account) {
      throw new Error("No signed-in account");
    }

    const result = await instance.acquireTokenSilent({
      ...loginRequest,
      account,
    });

    return result.idToken;
  };
}

function AppShell() {
  const { instance, accounts } = useMsal();
  const getToken = useIdentityToken();
  const [items, setItems] = useState([]);
  const [me, setMe] = useState(null);
  const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState(null);
  const [isBusy, setIsBusy] = useState(false);
  const [error, setError] = useState("");

  const isAdmin = useMemo(() => me?.roles?.includes("Admin"), [me]);

  async function load() {
    setIsBusy(true);
    setError("");
    try {
      const token = await getToken();
      const [profile, records] = await Promise.all([getMe(token), getItems(token)]);
      setMe(profile);
      setItems(records);
    } catch (err) {
      setError(err.message);
    } finally {
      setIsBusy(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  function editItem(item) {
    setEditingId(item.id);
    setForm({
      title: item.title,
      description: item.description ?? "",
      status: item.status,
    });
  }

  function resetForm() {
    setEditingId(null);
    setForm(emptyForm);
  }

  async function submitForm(event) {
    event.preventDefault();
    setIsBusy(true);
    setError("");
    try {
      const token = await getToken();
      if (editingId) {
        await updateItem(token, editingId, form);
      } else {
        await createItem(token, form);
      }
      resetForm();
      await load();
    } catch (err) {
      setError(err.message);
    } finally {
      setIsBusy(false);
    }
  }

  async function removeItem(id) {
    setIsBusy(true);
    setError("");
    try {
      const token = await getToken();
      await deleteItem(token, id);
      await load();
    } catch (err) {
      setError(err.message);
    } finally {
      setIsBusy(false);
    }
  }

  return (
    <div className="app">
      <header className="topbar">
        <div>
          <p className="eyebrow">Azure SQL CRUD</p>
          <h1>Items</h1>
        </div>
        <div className="account">
          <div>
            <span>{accounts[0]?.name}</span>
            <small>{me?.roles?.join(", ") || "Loading roles"}</small>
          </div>
          <button className="iconButton" onClick={load} disabled={isBusy} title="Refresh">
            <RefreshCw size={18} />
          </button>
          <button className="iconButton" onClick={() => instance.logoutRedirect()} title="Sign out">
            <LogOut size={18} />
          </button>
        </div>
      </header>

      {error && <div className="alert">{error}</div>}

      <main className="workspace">
        <section className="editor">
          <div className="sectionTitle">
            <h2>{editingId ? "Edit item" : "New item"}</h2>
            {isAdmin && (
              <span className="roleBadge">
                <ShieldCheck size={15} />
                Admin
              </span>
            )}
          </div>

          <form onSubmit={submitForm}>
            <label>
              Title
              <input
                value={form.title}
                onChange={(event) => setForm({ ...form, title: event.target.value })}
                placeholder="Quarterly planning"
                required
                maxLength={200}
                disabled={!isAdmin}
              />
            </label>
            <label>
              Description
              <textarea
                value={form.description}
                onChange={(event) => setForm({ ...form, description: event.target.value })}
                placeholder="Notes, context, or next action"
                maxLength={1000}
                disabled={!isAdmin}
              />
            </label>
            <label>
              Status
              <select
                value={form.status}
                onChange={(event) => setForm({ ...form, status: event.target.value })}
                disabled={!isAdmin}
              >
                <option>Open</option>
                <option>In progress</option>
                <option>Done</option>
                <option>Blocked</option>
              </select>
            </label>

            <div className="formActions">
              <button type="submit" className="primary" disabled={!isAdmin || isBusy}>
                {editingId ? <Save size={17} /> : <Plus size={17} />}
                {editingId ? "Save" : "Create"}
              </button>
              {editingId && (
                <button type="button" className="secondary" onClick={resetForm}>
                  <X size={17} />
                  Cancel
                </button>
              )}
            </div>
          </form>
        </section>

        <section className="list">
          <div className="sectionTitle">
            <h2>Records</h2>
            <span>{items.length} total</span>
          </div>

          <div className="tableWrap">
            <table>
              <thead>
                <tr>
                  <th>Title</th>
                  <th>Status</th>
                  <th>Created</th>
                  <th>Updated</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {items.map((item) => (
                  <tr key={item.id}>
                    <td>
                      <button className="linkButton" onClick={() => editItem(item)}>
                        {item.title}
                      </button>
                      <p>{item.description || "No description"}</p>
                    </td>
                    <td>
                      <span className={`status ${item.status.toLowerCase().replaceAll(" ", "-")}`}>
                        {item.status}
                      </span>
                    </td>
                    <td>
                      <span>{formatDate(item.created_at)}</span>
                      <small>{item.created_by}</small>
                    </td>
                    <td>
                      <span>{formatDate(item.updated_at)}</span>
                      <small>{item.updated_by || "Not updated"}</small>
                    </td>
                    <td className="rowActions">
                      <button
                        className="iconButton danger"
                        onClick={() => removeItem(item.id)}
                        disabled={!isAdmin || isBusy}
                        title="Delete"
                      >
                        <Trash2 size={17} />
                      </button>
                    </td>
                  </tr>
                ))}
                {items.length === 0 && (
                  <tr>
                    <td colSpan="5" className="empty">
                      No records yet.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </section>
      </main>
    </div>
  );
}

export default function App() {
  const { instance } = useMsal();

  return (
    <>
      <AuthenticatedTemplate>
        <AppShell />
      </AuthenticatedTemplate>
      <UnauthenticatedTemplate>
        <div className="signin">
          <div>
            <p className="eyebrow">Microsoft Entra SSO</p>
            <h1>SQL SSO CRUD</h1>
            <p>Sign in with your Microsoft account to manage records backed by Azure SQL.</p>
            <button className="primary" onClick={() => instance.loginRedirect(loginRequest)}>
              <LogIn size={18} />
              Sign in
            </button>
          </div>
        </div>
      </UnauthenticatedTemplate>
    </>
  );
}
