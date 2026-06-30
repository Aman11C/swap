import { createClient, RealtimeChannel, type RealtimePostgresChangesPayload } from "@supabase/supabase-js";

export type RealtimeMessagePayload = RealtimePostgresChangesPayload<Record<string, unknown>>;

export interface SessionChannelConfig {
  channel: RealtimeChannel;
  unsubscribe: () => void;
}

/**
 * Subscribe to Realtime changes for a specific swap session.
 * Returns a config object with the channel and an unsubscribe function.
 */
export function subscribeToSession(
  supabaseUrl: string,
  supabaseAnonKey: string,
  sessionId: string,
  userId: string,
  callbacks: {
    onMessage?: (payload: RealtimeMessagePayload) => void;
    onReadReceipt?: (payload: RealtimeMessagePayload) => void;
    onTyping?: (payload: RealtimeMessagePayload) => void;
  }
): SessionChannelConfig {
  const client = createClient(supabaseUrl, supabaseAnonKey);
  const channelName = `session:${sessionId}`;

  const channel = client.channel(channelName);

  if (callbacks.onMessage) {
    channel.on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "messages",
        filter: `session_id=eq.${sessionId}`,
      },
      callbacks.onMessage
    );
  }

  if (callbacks.onReadReceipt) {
    channel.on(
      "postgres_changes",
      {
        event: "INSERT",
        schema: "public",
        table: "message_reads",
      },
      (payload: RealtimeMessagePayload) => {
        const record = payload.new as Record<string, unknown>;
        if (record.user_id !== userId) {
          callbacks.onReadReceipt?.(payload);
        }
      }
    );
  }

  if (callbacks.onTyping) {
    channel.on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "typing_indicators",
        filter: `session_id=eq.${sessionId}`,
      },
      (payload: RealtimeMessagePayload) => {
        const record = payload.new as Record<string, unknown>;
        if (record.user_id !== userId) {
          callbacks.onTyping?.(payload);
        }
      }
    );
  }

  channel.subscribe();

  return {
    channel,
    unsubscribe: () => {
      client.removeChannel(channel);
    },
  };
}

/**
 * Subscribe to presence changes for a list of user IDs.
 */
export function subscribeToPresence(
  supabaseUrl: string,
  supabaseAnonKey: string,
  userIds: string[],
  onPresenceChange: (payload: RealtimeMessagePayload) => void
): SessionChannelConfig {
  const client = createClient(supabaseUrl, supabaseAnonKey);

  const channel = client.channel("presence");
  channel.on(
    "postgres_changes",
    {
      event: "*",
      schema: "public",
      table: "user_presence",
    },
    (payload: RealtimeMessagePayload) => {
      const record = payload.new as Record<string, unknown>;
      if (userIds.includes(record.user_id as string)) {
        onPresenceChange(payload);
      }
    }
  );

  channel.subscribe();

  return {
    channel,
    unsubscribe: () => {
      client.removeChannel(channel);
    },
  };
}
