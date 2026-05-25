const apiBaseUrl = import.meta.env.VITE_API_BASE_URL ?? "";

async function request(path, options = {}, token) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      ...(options.headers ?? {}),
    },
  });

  if (!response.ok) {
    let message = `${response.status} ${response.statusText}`;
    try {
      const body = await response.json();
      message = body.detail ?? message;
    } catch {
      // Keep the HTTP status message when the response has no JSON body.
    }
    throw new Error(message);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json();
}

export function getMe(token) {
  return request("/api/me", {}, token);
}

export function getItems(token) {
  return request("/api/items", {}, token);
}

export function createItem(token, item) {
  return request(
    "/api/items",
    {
      method: "POST",
      body: JSON.stringify(item),
    },
    token,
  );
}

export function updateItem(token, id, item) {
  return request(
    `/api/items/${id}`,
    {
      method: "PUT",
      body: JSON.stringify(item),
    },
    token,
  );
}

export function deleteItem(token, id) {
  return request(
    `/api/items/${id}`,
    {
      method: "DELETE",
    },
    token,
  );
}
