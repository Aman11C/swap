CREATE OR REPLACE FUNCTION public.search_users_profiles(
  p_search_text TEXT DEFAULT '',
  p_location TEXT DEFAULT NULL,
  p_availability public.availability_status DEFAULT NULL,
  p_college TEXT DEFAULT NULL,
  p_sort_by TEXT DEFAULT 'relevance',
  p_page INT DEFAULT 1,
  p_limit INT DEFAULT 20
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_offset INT;
  v_total INT;
  v_results JSONB;
BEGIN
  v_offset := (p_page - 1) * p_limit;

  SELECT COUNT(*) INTO v_total
  FROM public.profiles p
  WHERE NOT p.is_banned
    AND (p_search_text = '' OR to_tsvector('english', coalesce(p.display_name, '') || ' ' || coalesce(p.bio, '')) @@ plainto_tsquery('english', p_search_text))
    AND (p_location IS NULL OR p.location ILIKE '%' || p_location || '%')
    AND (p_availability IS NULL OR p.availability = p_availability)
    AND (p_college IS NULL OR p.college ILIKE '%' || p_college || '%');

  WITH matched AS (
    SELECT p.*
    FROM public.profiles p
    WHERE NOT p.is_banned
      AND (p_search_text = '' OR to_tsvector('english', coalesce(p.display_name, '') || ' ' || coalesce(p.bio, '')) @@ plainto_tsquery('english', p_search_text))
      AND (p_location IS NULL OR p.location ILIKE '%' || p_location || '%')
      AND (p_availability IS NULL OR p.availability = p_availability)
      AND (p_college IS NULL OR p.college ILIKE '%' || p_college || '%')
  ),
  with_rating AS (
    SELECT *,
      (SELECT ROUND(AVG(r.rating)::numeric, 2) FROM public.reviews r WHERE r.reviewee_id = matched.id) AS avg_rating
    FROM matched
  ),
  ordered AS (
    SELECT * FROM with_rating
    ORDER BY
      CASE WHEN p_sort_by = 'newest' THEN created_at END DESC,
      CASE WHEN p_sort_by = 'xp' THEN xp END DESC,
      CASE WHEN p_sort_by = 'rating' THEN avg_rating END DESC NULLS LAST,
      created_at DESC
    LIMIT p_limit
    OFFSET v_offset
  )
  SELECT jsonb_build_object(
    'total', v_total,
    'page', p_page,
    'limit', p_limit,
    'data', COALESCE(jsonb_agg(sub), '[]'::jsonb)
  ) INTO v_results
  FROM (
    SELECT
      o.id, o.username, o.display_name, o.bio, o.college, o.degree, o.year,
      o.location, o.avatar_url, o.availability, o.xp, o.level, o.created_at,
      o.avg_rating AS average_rating,
      COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
          'skill_id', ts.skill_id,
          'name', s.name,
          'slug', s.slug,
          'proficiency', ts.proficiency
        )) FROM public.teaching_skills ts
        JOIN public.skills s ON s.id = ts.skill_id
        WHERE ts.user_id = o.id),
        '[]'::jsonb
      ) AS teaching_skills
    FROM ordered o
  ) sub;

  RETURN v_results;
END;
$$;

CREATE OR REPLACE FUNCTION public.search_skills(
  p_search_text TEXT DEFAULT '',
  p_category_id UUID DEFAULT NULL,
  p_page INT DEFAULT 1,
  p_limit INT DEFAULT 20
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_offset INT;
  v_total INT;
  v_results JSONB;
BEGIN
  v_offset := (p_page - 1) * p_limit;

  SELECT COUNT(*) INTO v_total
  FROM public.skills s
  WHERE (p_search_text = '' OR to_tsvector('english', coalesce(s.name, '') || ' ' || coalesce(s.description, '')) @@ plainto_tsquery('english', p_search_text))
    AND (p_category_id IS NULL OR s.category_id = p_category_id);

  WITH ordered AS (
    SELECT s.*
    FROM public.skills s
    WHERE (p_search_text = '' OR to_tsvector('english', coalesce(s.name, '') || ' ' || coalesce(s.description, '')) @@ plainto_tsquery('english', p_search_text))
      AND (p_category_id IS NULL OR s.category_id = p_category_id)
    ORDER BY s.name
    LIMIT p_limit
    OFFSET v_offset
  )
  SELECT jsonb_build_object(
    'total', v_total,
    'page', p_page,
    'limit', p_limit,
    'data', COALESCE(jsonb_agg(sub), '[]'::jsonb)
  ) INTO v_results
  FROM (
    SELECT
      o.id, o.category_id, o.name, o.slug, o.description, o.created_at,
      (SELECT row_to_json(c) FROM (SELECT id, name, slug FROM public.skill_categories WHERE id = o.category_id) c) AS category
    FROM ordered o
  ) sub;

  RETURN v_results;
END;
$$;
