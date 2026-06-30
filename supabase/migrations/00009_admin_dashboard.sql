ALTER TABLE public.profiles ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.is_admin(user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER SET search_path = ''
AS $$
  SELECT COALESCE((SELECT is_admin FROM public.profiles WHERE id = user_id), false);
$$;

CREATE OR REPLACE FUNCTION public.admin_ban_user(p_admin_id UUID, p_user_id UUID, p_reason TEXT DEFAULT '')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin(p_admin_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE public.profiles SET is_banned = true WHERE id = p_user_id;
  INSERT INTO public.admin_logs (admin_id, action, target_type, target_id, details)
  VALUES (p_admin_id, 'user_banned', 'user', p_user_id, jsonb_build_object('reason', p_reason));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_unban_user(p_admin_id UUID, p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin(p_admin_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE public.profiles SET is_banned = false WHERE id = p_user_id;
  INSERT INTO public.admin_logs (admin_id, action, target_type, target_id)
  VALUES (p_admin_id, 'user_unbanned', 'user', p_user_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_warn_user(p_admin_id UUID, p_user_id UUID, p_reason TEXT DEFAULT '')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin(p_admin_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  INSERT INTO public.admin_logs (admin_id, action, target_type, target_id, details)
  VALUES (p_admin_id, 'user_warned', 'user', p_user_id, jsonb_build_object('reason', p_reason));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_resolve_report(p_admin_id UUID, p_report_id UUID, p_action TEXT DEFAULT 'resolved')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_status report_status;
  v_action admin_action_type;
BEGIN
  IF NOT public.is_admin(p_admin_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_action = 'dismissed' THEN
    v_status := 'dismissed'::report_status;
    v_action := 'report_dismissed'::admin_action_type;
  ELSE
    v_status := 'resolved'::report_status;
    v_action := 'report_resolved'::admin_action_type;
  END IF;
  UPDATE public.reports SET status = v_status, reviewed_by = p_admin_id, reviewed_at = now() WHERE id = p_report_id;
  INSERT INTO public.admin_logs (admin_id, action, target_type, target_id)
  VALUES (p_admin_id, v_action, 'report', p_report_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_remove_content(p_admin_id UUID, p_target_type TEXT, p_target_id UUID, p_reason TEXT DEFAULT '')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin(p_admin_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_target_type = 'review' THEN
    UPDATE public.reviews SET comment = '[removed by admin]' WHERE id = p_target_id;
  ELSIF p_target_type = 'swap_request' THEN
    UPDATE public.swap_requests SET status = 'cancelled' WHERE id = p_target_id;
  END IF;
  INSERT INTO public.admin_logs (admin_id, action, target_type, target_id, details)
  VALUES (p_admin_id, 'content_removed', p_target_type, p_target_id, jsonb_build_object('reason', p_reason));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_adjust_xp(p_admin_id UUID, p_user_id UUID, p_amount INTEGER, p_reason TEXT DEFAULT '')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin(p_admin_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE public.profiles SET xp = GREATEST(0, xp + p_amount) WHERE id = p_user_id;
  INSERT INTO public.admin_logs (admin_id, action, target_type, target_id, details)
  VALUES (p_admin_id, 'xp_adjusted', 'user', p_user_id, jsonb_build_object('amount', p_amount, 'reason', p_reason));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_stats(p_admin_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  result JSONB;
BEGIN
  IF NOT public.is_admin(p_admin_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT jsonb_build_object(
    'total_users', (SELECT count(*) FROM public.profiles),
    'total_swaps', (SELECT count(*) FROM public.swap_requests),
    'completed_sessions', (SELECT count(*) FROM public.swap_sessions WHERE status = 'completed'),
    'pending_reports', (SELECT count(*) FROM public.reports WHERE status = 'pending' OR status = 'under_review'),
    'banned_users', (SELECT count(*) FROM public.profiles WHERE is_banned = true),
    'total_reviews', (SELECT count(*) FROM public.reviews),
    'total_skills', (SELECT count(*) FROM public.skills),
    'reports_today', (SELECT count(*) FROM public.reports WHERE created_at > CURRENT_DATE)
  ) INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_search_users(p_admin_id UUID, p_query TEXT DEFAULT '', p_page INTEGER DEFAULT 1, p_limit INTEGER DEFAULT 20)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  result JSONB;
  v_offset INTEGER;
BEGIN
  IF NOT public.is_admin(p_admin_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  v_offset := (p_page - 1) * p_limit;
  SELECT jsonb_build_object(
    'data', COALESCE((SELECT jsonb_agg(to_jsonb(p)) FROM (
      SELECT id, username, display_name, college, degree, year, location, xp, level, is_banned, is_admin, is_onboarded, created_at
      FROM public.profiles p2
      WHERE p_query = '' OR p2.username ILIKE '%' || p_query || '%' OR p2.display_name ILIKE '%' || p_query || '%' OR p2.college ILIKE '%' || p_query || '%'
      ORDER BY p2.created_at DESC
      LIMIT p_limit OFFSET v_offset
    ) p), '[]'::jsonb),
    'count', (SELECT count(*) FROM public.profiles p2
      WHERE p_query = '' OR p2.username ILIKE '%' || p_query || '%' OR p2.display_name ILIKE '%' || p_query || '%' OR p2.college ILIKE '%' || p_query || '%'),
    'page', p_page,
    'limit', p_limit
  ) INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_reports(p_admin_id UUID, p_status TEXT DEFAULT 'pending', p_page INTEGER DEFAULT 1, p_limit INTEGER DEFAULT 20)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  result JSONB;
  v_offset INTEGER;
BEGIN
  IF NOT public.is_admin(p_admin_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  v_offset := (p_page - 1) * p_limit;
  SELECT jsonb_build_object(
    'data', COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM (
      SELECT r.*,
        jsonb_build_object('id', reporter.id, 'username', reporter.username, 'display_name', reporter.display_name) as reporter,
        jsonb_build_object('id', reported.id, 'username', reported.username, 'display_name', reported.display_name) as reported_user
      FROM public.reports r
      LEFT JOIN public.profiles reporter ON reporter.id = r.reporter_id
      LEFT JOIN public.profiles reported ON reported.id = r.reported_user_id
      WHERE (p_status = '' OR r.status = p_status::report_status)
      ORDER BY r.created_at DESC
      LIMIT p_limit OFFSET v_offset
    ) r), '[]'::jsonb),
    'count', (SELECT count(*) FROM public.reports r WHERE (p_status = '' OR r.status = p_status::report_status)),
    'page', p_page,
    'limit', p_limit
  ) INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_logs(p_admin_id UUID, p_page INTEGER DEFAULT 1, p_limit INTEGER DEFAULT 50)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  result JSONB;
  v_offset INTEGER;
BEGIN
  IF NOT public.is_admin(p_admin_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  v_offset := (p_page - 1) * p_limit;
  SELECT jsonb_build_object(
    'data', COALESCE((SELECT jsonb_agg(to_jsonb(l)) FROM (
      SELECT l.*, jsonb_build_object('id', admin.id, 'username', admin.username) as admin
      FROM public.admin_logs l
      LEFT JOIN public.profiles admin ON admin.id = l.admin_id
      ORDER BY l.created_at DESC
      LIMIT p_limit OFFSET v_offset
    ) l), '[]'::jsonb),
    'count', (SELECT count(*) FROM public.admin_logs),
    'page', p_page,
    'limit', p_limit
  ) INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_award_achievement(p_admin_id UUID, p_user_id UUID, p_achievement_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin(p_admin_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  INSERT INTO public.user_achievements (user_id, achievement_id) VALUES (p_user_id, p_achievement_id)
  ON CONFLICT DO NOTHING;
  INSERT INTO public.admin_logs (admin_id, action, target_type, target_id, details)
  VALUES (p_admin_id, 'achievement_awarded', 'user', p_user_id, jsonb_build_object('achievement_id', p_achievement_id));
END;
$$;

CREATE INDEX IF NOT EXISTS idx_admin_logs_admin_id ON public.admin_logs(admin_id);
CREATE INDEX IF NOT EXISTS idx_reports_reported_user_id ON public.reports(reported_user_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_user_id ON public.bookmarks(user_id);
