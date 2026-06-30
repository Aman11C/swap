-- ============================================================================
-- SWAP — Realtime Chat Infrastructure
-- ============================================================================

-- ############################################################################
-- 1. ALTER EXISTING MESSAGES TABLE
-- ############################################################################
ALTER TABLE public.messages
  ADD COLUMN is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN updated_at TIMESTAMPTZ;

-- Auto-set updated_at on message edit (soft-delete counts as update).
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER messages_set_updated_at
  BEFORE UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ############################################################################
-- 2. MESSAGE READS (read receipts)
-- ############################################################################
CREATE TABLE public.message_reads (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  read_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, message_id)
);

ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;

-- Users can insert their own read receipts.
CREATE POLICY "Users can insert own message reads"
  ON public.message_reads FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Users can read reads for messages they have access to (session participant).
CREATE POLICY "Session participants can read message reads"
  ON public.message_reads FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      JOIN public.swap_sessions s ON s.id = m.session_id
      WHERE m.id = message_id
        AND (s.initiator_id = auth.uid() OR s.partner_id = auth.uid())
    )
  );

-- ############################################################################
-- 3. TYPING INDICATORS (transient — upsert pattern)
-- ############################################################################
CREATE TABLE public.typing_indicators (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.swap_sessions(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (session_id, user_id)
);

ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;

-- Participants can upsert their own typing indicator.
CREATE POLICY "Users can upsert own typing indicator"
  ON public.typing_indicators FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.swap_sessions
      WHERE id = session_id
        AND (initiator_id = auth.uid() OR partner_id = auth.uid())
    )
  );

-- Participants can read typing indicators for their sessions.
CREATE POLICY "Session participants can read typing indicators"
  ON public.typing_indicators FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.swap_sessions
      WHERE id = session_id
        AND (initiator_id = auth.uid() OR partner_id = auth.uid())
    )
  );

-- Participants can delete typing indicators (stop typing).
CREATE POLICY "Users can delete own typing indicator"
  ON public.typing_indicators FOR DELETE
  USING (user_id = auth.uid());

-- ############################################################################
-- 4. USER PRESENCE (online/away/offline)
-- ############################################################################
CREATE TABLE public.user_presence (
  user_id     UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  status      TEXT NOT NULL DEFAULT 'offline' CHECK (status IN ('online', 'away', 'offline')),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.user_presence ENABLE ROW LEVEL SECURITY;

-- Users can upsert their own presence.
CREATE POLICY "Users can upsert own presence"
  ON public.user_presence FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own presence"
  ON public.user_presence FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- All authenticated users can read presence.
CREATE POLICY "Presence is readable by all authenticated users"
  ON public.user_presence FOR SELECT
  USING (auth.role() = 'authenticated');

-- Auto-update updated_at on presence changes.
CREATE TRIGGER user_presence_set_updated_at
  BEFORE UPDATE ON public.user_presence
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ############################################################################
-- 5. ENABLE SUPABASE REALTIME
-- ############################################################################
-- These tables will broadcast changes via WebSocket to subscribed clients.
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reads;
ALTER PUBLICATION supabase_realtime ADD TABLE public.typing_indicators;
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_presence;
