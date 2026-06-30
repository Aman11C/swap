import { createClient, SupabaseClient } from "@supabase/supabase-js";

function getEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required env var: ${name}`);
  return value;
}

let _serviceClient: SupabaseClient | null = null;

export function getServiceClient(): SupabaseClient {
  if (!_serviceClient) {
    _serviceClient = createClient(getEnv("SUPABASE_URL"), getEnv("SUPABASE_SERVICE_KEY"), {
      auth: { persistSession: false },
    });
  }
  return _serviceClient;
}

export function getUserClient(token: string): SupabaseClient {
  return createClient(getEnv("SUPABASE_URL"), getEnv("SUPABASE_ANON_KEY"), {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

export function getSupabaseUrl(): string {
  return getEnv("SUPABASE_URL");
}

export function getPort(): number {
  return Number(process.env.PORT) || 3001;
}
