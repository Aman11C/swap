-- ============================================================================
-- 00005: Swap Engine — Atomic RPC functions for swap lifecycle
-- ============================================================================

-- ############################################################################
-- 1. Partial unique index to enforce no duplicate pending requests
-- ############################################################################

CREATE UNIQUE INDEX IF NOT EXISTS idx_swap_requests_pending_unique
  ON public.swap_requests(sender_id, receiver_id, skill_offered_id, skill_requested_id)
  WHERE status = 'pending';

-- ############################################################################
-- 2. Helper: insert_notification
-- ############################################################################

CREATE OR REPLACE FUNCTION public.insert_notification(
  p_user_id UUID,
  p_type    public.notification_type,
  p_title   TEXT,
  p_body    TEXT DEFAULT '',
  p_data    JSONB DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.notifications (user_id, type, title, body, data)
  VALUES (p_user_id, p_type, p_title, p_body, p_data)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ############################################################################
-- 3. RPC: create_swap_request
-- ############################################################################

CREATE OR REPLACE FUNCTION public.create_swap_request(
  p_sender_id          UUID,
  p_receiver_id        UUID,
  p_skill_offered_id   UUID,
  p_skill_requested_id UUID,
  p_message            TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_request_id UUID;
BEGIN
  -- Prevent self-swap
  IF p_sender_id = p_receiver_id THEN
    RAISE EXCEPTION 'Cannot send swap request to yourself';
  END IF;

  -- Check for duplicate pending request (backed by partial unique index)
  IF EXISTS (
    SELECT 1 FROM public.swap_requests
    WHERE sender_id = p_sender_id
      AND receiver_id = p_receiver_id
      AND skill_offered_id = p_skill_offered_id
      AND skill_requested_id = p_skill_requested_id
      AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'A pending request already exists for this swap';
  END IF;

  -- Insert request
  INSERT INTO public.swap_requests (sender_id, receiver_id, skill_offered_id, skill_requested_id, message)
  VALUES (p_sender_id, p_receiver_id, p_skill_offered_id, p_skill_requested_id, p_message)
  RETURNING id INTO v_request_id;

  -- Notify receiver
  PERFORM public.insert_notification(
    p_receiver_id,
    'swap_request',
    'New Swap Request',
    '',
    jsonb_build_object(
      'request_id', v_request_id,
      'sender_id', p_sender_id,
      'skill_offered_id', p_skill_offered_id,
      'skill_requested_id', p_skill_requested_id
    )
  );

  RETURN jsonb_build_object('id', v_request_id);
END;
$$;

-- ############################################################################
-- 4. RPC: update_swap_request_status
-- ############################################################################
-- Handles accept, decline, and cancel with proper authorization and side-
-- effects (session creation on accept, session cancellation on cancel).

CREATE OR REPLACE FUNCTION public.update_swap_request_status(
  p_request_id UUID,
  p_user_id    UUID,
  p_new_status public.swap_request_status
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_request   public.swap_requests%ROWTYPE;
  v_session_id UUID;
  v_notify_id   UUID;
  v_notify_type public.notification_type;
BEGIN
  -- Lock and fetch request
  SELECT * INTO v_request
  FROM public.swap_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Swap request not found';
  END IF;

  -- Validate transition
  IF v_request.status = 'pending' AND p_new_status NOT IN ('accepted', 'declined', 'cancelled') THEN
    RAISE EXCEPTION 'Cannot transition from pending to %', p_new_status;
  END IF;
  IF v_request.status = 'accepted' AND p_new_status != 'cancelled' THEN
    RAISE EXCEPTION 'Cannot transition from accepted to %', p_new_status;
  END IF;
  IF v_request.status IN ('declined', 'cancelled') THEN
    RAISE EXCEPTION 'Request is already %', v_request.status;
  END IF;

  -- Authorize
  IF p_new_status = 'cancelled' AND p_user_id != v_request.sender_id THEN
    RAISE EXCEPTION 'Only the sender can cancel a request';
  END IF;
  IF p_new_status IN ('accepted', 'declined') AND p_user_id != v_request.receiver_id THEN
    RAISE EXCEPTION 'Only the receiver can accept or decline a request';
  END IF;

  -- Apply side effects before status update

  -- ACCEPTED → create session
  IF p_new_status = 'accepted' THEN
    INSERT INTO public.swap_sessions (request_id, initiator_id, partner_id)
    VALUES (v_request.id, v_request.sender_id, v_request.receiver_id)
    RETURNING id INTO v_session_id;

    v_notify_type := 'swap_accepted';
    PERFORM public.insert_notification(
      v_request.sender_id,
      v_notify_type,
      'Swap Request Accepted',
      '',
      jsonb_build_object('request_id', v_request.id, 'session_id', v_session_id, 'status', 'accepted')
    );
  END IF;

  -- DECLINED → notify sender
  IF p_new_status = 'declined' THEN
    v_notify_type := 'swap_declined';
    PERFORM public.insert_notification(
      v_request.sender_id,
      v_notify_type,
      'Swap Request Declined',
      '',
      jsonb_build_object('request_id', v_request.id, 'status', 'declined')
    );
  END IF;

  -- CANCELLED
  IF p_new_status = 'cancelled' THEN
    -- If the request was already accepted, cancel the associated session
    IF v_request.status = 'accepted' THEN
      UPDATE public.swap_sessions
      SET status = 'cancelled', ended_at = now()
      WHERE request_id = v_request.id
        AND status IN ('scheduled', 'in_progress');
    END IF;

    v_notify_type := 'swap_cancelled';
    PERFORM public.insert_notification(
      v_request.receiver_id,
      v_notify_type,
      'Swap Request Cancelled',
      '',
      jsonb_build_object('request_id', v_request.id, 'status', 'cancelled')
    );
  END IF;

  -- Update request status
  UPDATE public.swap_requests
  SET status = p_new_status
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'id', p_request_id,
    'session_id', v_session_id
  );
END;
$$;

-- ############################################################################
-- 5. RPC: update_swap_session_status
-- ############################################################################

CREATE OR REPLACE FUNCTION public.update_swap_session_status(
  p_session_id UUID,
  p_user_id    UUID,
  p_new_status public.swap_session_status,
  p_notes      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_session   public.swap_sessions%ROWTYPE;
  v_notify_id  UUID;
  v_other_id   UUID;
BEGIN
  -- Lock and fetch session
  SELECT * INTO v_session
  FROM public.swap_sessions
  WHERE id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Session not found';
  END IF;

  -- Validate transition
  IF v_session.status = 'scheduled' AND p_new_status NOT IN ('in_progress', 'cancelled', 'no_show') THEN
    RAISE EXCEPTION 'Cannot transition from scheduled to %', p_new_status;
  END IF;
  IF v_session.status = 'in_progress' AND p_new_status NOT IN ('completed', 'cancelled', 'no_show') THEN
    RAISE EXCEPTION 'Cannot transition from in_progress to %', p_new_status;
  END IF;
  IF v_session.status IN ('completed', 'cancelled', 'no_show') THEN
    RAISE EXCEPTION 'Session is already %', v_session.status;
  END IF;

  -- Authorize: must be initiator or partner
  IF p_user_id NOT IN (v_session.initiator_id, v_session.partner_id) THEN
    RAISE EXCEPTION 'Not authorized to update this session';
  END IF;

  -- Determine the other participant (for notification)
  IF p_user_id = v_session.initiator_id THEN
    v_other_id := v_session.partner_id;
  ELSE
    v_other_id := v_session.initiator_id;
  END IF;

  -- Update status with timestamps
  UPDATE public.swap_sessions
  SET
    status     = p_new_status,
    started_at = CASE WHEN p_new_status = 'in_progress' AND v_session.started_at IS NULL THEN now() ELSE started_at END,
    ended_at   = CASE WHEN p_new_status IN ('completed', 'cancelled', 'no_show') THEN now() ELSE ended_at END,
    notes      = CASE WHEN p_notes IS NOT NULL THEN p_notes ELSE notes END
  WHERE id = p_session_id;

  -- Notify the other participant
  PERFORM public.insert_notification(
    v_other_id,
    'system',
    'Session ' || p_new_status,
    '',
    jsonb_build_object('session_id', p_session_id, 'status', p_new_status)
  );

  RETURN jsonb_build_object('id', p_session_id);
END;
$$;
