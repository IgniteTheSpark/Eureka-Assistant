import type {
  AuthResponse,
  DemoResetResponse,
  FlashResponse,
  MeResponse,
} from "./types";

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly body: Record<string, unknown>,
  ) {
    const detail = body.detail ?? body.error;
    super(typeof detail === "string" ? detail : `Request failed (${status})`);
    this.name = "ApiError";
  }
}

export async function requestJson<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new ApiError(
      response.status,
      typeof body === "object" && body !== null
        ? (body as Record<string, unknown>)
        : {},
    );
  }
  return body as T;
}

function trimTrailingSlash(value: string) {
  return value.replace(/\/+$/, "");
}

export class BackendClient {
  private readonly baseUrl: string;

  constructor(
    baseUrl = "http://localhost:8000",
    private readonly getToken: () => string | null = () =>
      localStorage.getItem("eureka.authToken"),
  ) {
    this.baseUrl = trimTrailingSlash(baseUrl);
  }

  login(email: string, password: string) {
    return this.auth("login", email, password);
  }

  register(email: string, password: string) {
    return this.auth("register", email, password);
  }

  me() {
    return requestJson<MeResponse>(`${this.baseUrl}/api/auth/me`, {
      headers: this.headers(true),
    });
  }

  flash(text: string) {
    return requestJson<FlashResponse>(`${this.baseUrl}/api/flash`, {
      method: "POST",
      headers: this.headers(true),
      body: JSON.stringify({ text, source: "voice" }),
    });
  }

  resetDemo() {
    return requestJson<DemoResetResponse>(`${this.baseUrl}/api/demo/reset`, {
      method: "POST",
      headers: this.headers(true),
    });
  }

  private auth(action: "login" | "register", email: string, password: string) {
    return requestJson<AuthResponse>(`${this.baseUrl}/api/auth/${action}`, {
      method: "POST",
      headers: this.headers(false),
      body: JSON.stringify({ email, password }),
    });
  }

  private headers(authenticated: boolean) {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    const token = authenticated ? this.getToken() : null;
    if (token) headers.Authorization = `Bearer ${token}`;
    return headers;
  }
}

export const backendClient = new BackendClient();
