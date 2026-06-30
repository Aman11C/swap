-- Add updated_at column for edit tracking
ALTER TABLE public.reviews ADD COLUMN updated_at TIMESTAMPTZ DEFAULT now();

-- RPC to compute average rating for a user
CREATE OR REPLACE FUNCTION public.get_average_rating(target_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'average_rating', ROUND(AVG(rating)::numeric, 2)
  )
  INTO result
  FROM public.reviews
  WHERE reviewee_id = target_user_id;
  RETURN COALESCE(result, '{"average_rating": null}'::jsonb);
END;
$$;

-- Trigger: prevent rating changes and enforce 24h edit window
CREATE FUNCTION public.check_review_update()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NEW.rating IS DISTINCT FROM OLD.rating THEN
    RAISE EXCEPTION 'Cannot change review rating';
  END IF;
  IF OLD.created_at < now() - interval '24 hours' THEN
    RAISE EXCEPTION 'Review can only be edited within 24 hours of creation';
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER check_review_update
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.check_review_update();

-- Trigger: rate-limit reviews (max 1 per minute per user)
CREATE FUNCTION public.check_review_spam()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  last_review_time TIMESTAMPTZ;
BEGIN
  SELECT created_at INTO last_review_time
  FROM public.reviews
  WHERE reviewer_id = NEW.reviewer_id
  ORDER BY created_at DESC
  LIMIT 1;
  IF last_review_time IS NOT NULL AND last_review_time > now() - interval '1 minute' THEN
    RAISE EXCEPTION 'Please wait at least 1 minute between reviews';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER check_review_spam
  BEFORE INSERT ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.check_review_spam();

-- Enable reviews for realtime
alter publication supabase_realtime add table public.reviews;

-- RLS: Reviewers can update their own reviews
CREATE POLICY "Reviewers can update their own reviews"
  ON public.reviews FOR UPDATE
  USING (reviewer_id = auth.uid())
  WITH CHECK (reviewer_id = auth.uid());
