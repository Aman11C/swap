-- ============================================================================
-- SWAP — Production PostgreSQL Schema for Supabase
-- ============================================================================

-- ############################################################################
-- 1. ENUMS
-- ############################################################################

CREATE TYPE swap_request_status AS ENUM (
  'pending', 'accepted', 'declined', 'cancelled'
);

CREATE TYPE swap_session_status AS ENUM (
  'scheduled', 'in_progress', 'completed', 'cancelled', 'no_show'
);

CREATE TYPE notification_type AS ENUM (
  'swap_request',
  'swap_accepted',
  'swap_declined',
  'swap_cancelled',
  'new_message',
  'session_reminder',
  'review_received',
  'achievement_unlocked',
  'xp_milestone',
  'system'
);

CREATE TYPE report_reason AS ENUM (
  'inappropriate_content',
  'fake_profile',
  'harassment',
  'spam',
  'scam',
  'impersonation',
  'other'
);

CREATE TYPE report_status AS ENUM (
  'pending', 'under_review', 'resolved', 'dismissed'
);

CREATE TYPE proficiency_level AS ENUM (
  'beginner', 'intermediate', 'advanced', 'expert'
);

CREATE TYPE admin_action_type AS ENUM (
  'user_warned',
  'user_suspended',
  'user_banned',
  'user_unbanned',
  'content_removed',
  'report_resolved',
  'report_dismissed',
  'achievement_awarded',
  'xp_adjusted',
  'system_config'
);

-- ############################################################################
-- 2. TABLES
-- ############################################################################

-- ---------------------------------------------------------------------------
-- 2.1 PROFILES (extends auth.users)
-- ---------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username      TEXT NOT NULL,
  display_name  TEXT,
  bio           TEXT DEFAULT ''::TEXT,
  college       TEXT DEFAULT ''::TEXT,
  degree        TEXT DEFAULT ''::TEXT,
  year          TEXT DEFAULT ''::TEXT,
  location      TEXT DEFAULT ''::TEXT,
  avatar_url    TEXT,
  xp            INTEGER NOT NULL DEFAULT 0 CHECK (xp >= 0),
  level         INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
  is_banned     BOOLEAN NOT NULL DEFAULT FALSE,
  is_onboarded  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_profiles_username ON public.profiles(LOWER(username));

-- ---------------------------------------------------------------------------
-- 2.2 SKILL CATEGORIES
-- ---------------------------------------------------------------------------
CREATE TABLE public.skill_categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT NOT NULL,
  description TEXT DEFAULT ''::TEXT,
  icon        TEXT,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_skill_categories_slug ON public.skill_categories(slug);

-- ---------------------------------------------------------------------------
-- 2.3 SKILLS
-- ---------------------------------------------------------------------------
CREATE TABLE public.skills (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID NOT NULL REFERENCES public.skill_categories(id) ON DELETE RESTRICT,
  name        TEXT NOT NULL,
  slug        TEXT NOT NULL,
  description TEXT DEFAULT ''::TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_skills_slug ON public.skills(slug);
CREATE INDEX idx_skills_category ON public.skills(category_id);

-- ---------------------------------------------------------------------------
-- 2.4 TEACHING SKILLS (skills the user can teach)
-- ---------------------------------------------------------------------------
CREATE TABLE public.teaching_skills (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  skill_id          UUID NOT NULL REFERENCES public.skills(id) ON DELETE CASCADE,
  proficiency       proficiency_level NOT NULL DEFAULT 'intermediate',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_teaching_skills_unique
  ON public.teaching_skills(user_id, skill_id);
CREATE INDEX idx_teaching_skills_user ON public.teaching_skills(user_id);
CREATE INDEX idx_teaching_skills_skill ON public.teaching_skills(skill_id);
CREATE INDEX idx_teaching_skills_proficiency
  ON public.teaching_skills(proficiency);

-- ---------------------------------------------------------------------------
-- 2.5 LEARNING SKILLS (skills the user wants to learn)
-- ---------------------------------------------------------------------------
CREATE TABLE public.learning_skills (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  skill_id    UUID NOT NULL REFERENCES public.skills(id) ON DELETE CASCADE,
  priority    INTEGER NOT NULL DEFAULT 0 CHECK (priority >= 0),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_learning_skills_unique
  ON public.learning_skills(user_id, skill_id);
CREATE INDEX idx_learning_skills_user ON public.learning_skills(user_id);
CREATE INDEX idx_learning_skills_skill ON public.learning_skills(skill_id);
CREATE INDEX idx_learning_skills_priority
  ON public.learning_skills(user_id, priority DESC);

-- ---------------------------------------------------------------------------
-- 2.6 SWAP REQUESTS
-- ---------------------------------------------------------------------------
CREATE TABLE public.swap_requests (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id          UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  receiver_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  skill_offered_id   UUID NOT NULL REFERENCES public.skills(id) ON DELETE RESTRICT,
  skill_requested_id UUID NOT NULL REFERENCES public.skills(id) ON DELETE RESTRICT,
  message            TEXT DEFAULT ''::TEXT,
  status             swap_request_status NOT NULL DEFAULT 'pending',
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_swap_no_self CHECK (sender_id <> receiver_id),
  CONSTRAINT chk_swap_diff_skills CHECK (skill_offered_id <> skill_requested_id)
);

CREATE INDEX idx_swap_requests_sender   ON public.swap_requests(sender_id);
CREATE INDEX idx_swap_requests_receiver ON public.swap_requests(receiver_id);
CREATE INDEX idx_swap_requests_status   ON public.swap_requests(status);
CREATE INDEX idx_swap_requests_created  ON public.swap_requests(created_at DESC);

-- ---------------------------------------------------------------------------
-- 2.7 SWAP SESSIONS
-- ---------------------------------------------------------------------------
CREATE TABLE public.swap_sessions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id    UUID NOT NULL REFERENCES public.swap_requests(id) ON DELETE CASCADE,
  initiator_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  partner_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  scheduled_at  TIMESTAMPTZ,
  started_at    TIMESTAMPTZ,
  ended_at      TIMESTAMPTZ,
  status        swap_session_status NOT NULL DEFAULT 'scheduled',
  notes         TEXT DEFAULT ''::TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_session_no_self CHECK (initiator_id <> partner_id)
);

CREATE UNIQUE INDEX idx_swap_sessions_request
  ON public.swap_sessions(request_id);
CREATE INDEX idx_swap_sessions_initiator ON public.swap_sessions(initiator_id);
CREATE INDEX idx_swap_sessions_partner   ON public.swap_sessions(partner_id);
CREATE INDEX idx_swap_sessions_status    ON public.swap_sessions(status);
CREATE INDEX idx_swap_sessions_scheduled ON public.swap_sessions(scheduled_at)
  WHERE scheduled_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2.8 MESSAGES
-- ---------------------------------------------------------------------------
CREATE TABLE public.messages (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.swap_sessions(id) ON DELETE CASCADE,
  sender_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content    TEXT NOT NULL CHECK (char_length(content) > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_messages_session ON public.messages(session_id);
CREATE INDEX idx_messages_sender  ON public.messages(sender_id);
CREATE INDEX idx_messages_created ON public.messages(session_id, created_at ASC);

-- ---------------------------------------------------------------------------
-- 2.9 NOTIFICATIONS
-- ---------------------------------------------------------------------------
CREATE TABLE public.notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type       notification_type NOT NULL,
  title      TEXT NOT NULL,
  body       TEXT DEFAULT ''::TEXT,
  data       JSONB DEFAULT '{}'::JSONB,
  is_read    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_user   ON public.notifications(user_id);
CREATE INDEX idx_notifications_unread ON public.notifications(user_id, is_read)
  WHERE NOT is_read;
CREATE INDEX idx_notifications_created ON public.notifications(user_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 2.10 REVIEWS
-- ---------------------------------------------------------------------------
CREATE TABLE public.reviews (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id   UUID NOT NULL REFERENCES public.swap_sessions(id) ON DELETE CASCADE,
  reviewer_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reviewee_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating       INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment      TEXT DEFAULT ''::TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_review_no_self CHECK (reviewer_id <> reviewee_id)
);

CREATE UNIQUE INDEX idx_reviews_session_reviewer
  ON public.reviews(session_id, reviewer_id);
CREATE INDEX idx_reviews_reviewer ON public.reviews(reviewer_id);
CREATE INDEX idx_reviews_reviewee ON public.reviews(reviewee_id);
CREATE INDEX idx_reviews_rating   ON public.reviews(rating);

-- ---------------------------------------------------------------------------
-- 2.11 ACHIEVEMENTS
-- ---------------------------------------------------------------------------
CREATE TABLE public.achievements (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT NOT NULL,
  description TEXT NOT NULL,
  icon        TEXT NOT NULL DEFAULT '🏆',
  xp_reward   INTEGER NOT NULL DEFAULT 0 CHECK (xp_reward >= 0),
  criteria    JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_achievements_slug ON public.achievements(slug);

-- ---------------------------------------------------------------------------
-- 2.12 USER ACHIEVEMENTS
-- ---------------------------------------------------------------------------
CREATE TABLE public.user_achievements (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  achievement_id UUID NOT NULL REFERENCES public.achievements(id) ON DELETE CASCADE,
  earned_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_user_achievements_unique
  ON public.user_achievements(user_id, achievement_id);
CREATE INDEX idx_user_achievements_user
  ON public.user_achievements(user_id);

-- ---------------------------------------------------------------------------
-- 2.13 BOOKMARKS
-- ---------------------------------------------------------------------------
CREATE TABLE public.bookmarks (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  skill_id       UUID REFERENCES public.skills(id) ON DELETE CASCADE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_bookmark_has_target CHECK (
    (target_user_id IS NOT NULL)::INTEGER +
    (skill_id IS NOT NULL)::INTEGER = 1
  )
);

CREATE UNIQUE INDEX idx_bookmarks_user_target
  ON public.bookmarks(user_id, target_user_id)
  WHERE target_user_id IS NOT NULL;
CREATE UNIQUE INDEX idx_bookmarks_user_skill
  ON public.bookmarks(user_id, skill_id)
  WHERE skill_id IS NOT NULL;
CREATE INDEX idx_bookmarks_user ON public.bookmarks(user_id);

-- ---------------------------------------------------------------------------
-- 2.14 REPORTS
-- ---------------------------------------------------------------------------
CREATE TABLE public.reports (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reported_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason           report_reason NOT NULL,
  description      TEXT DEFAULT ''::TEXT,
  status           report_status NOT NULL DEFAULT 'pending',
  reviewed_by      UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at      TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_report_no_self CHECK (reporter_id <> reported_user_id)
);

CREATE INDEX idx_reports_reporter ON public.reports(reporter_id);
CREATE INDEX idx_reports_reported ON public.reports(reported_user_id);
CREATE INDEX idx_reports_status   ON public.reports(status);
CREATE INDEX idx_reports_pending  ON public.reports(created_at ASC)
  WHERE status = 'pending';

-- ---------------------------------------------------------------------------
-- 2.15 ADMIN LOGS
-- ---------------------------------------------------------------------------
CREATE TABLE public.admin_logs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  action      admin_action_type NOT NULL,
  target_type TEXT NOT NULL,
  target_id   UUID,
  details     JSONB DEFAULT '{}'::JSONB,
  ip_address  INET,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_admin_logs_admin   ON public.admin_logs(admin_id);
CREATE INDEX idx_admin_logs_action  ON public.admin_logs(action);
CREATE INDEX idx_admin_logs_target  ON public.admin_logs(target_type, target_id);
CREATE INDEX idx_admin_logs_created ON public.admin_logs(created_at DESC);

-- ############################################################################
-- 3. TRIGGER: auto-create profile on user signup
-- ############################################################################

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, username, display_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'username', SPLIT_PART(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data ->> 'display_name', SPLIT_PART(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ############################################################################
-- 4. TRIGGER: auto-update updated_at
-- ############################################################################

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER set_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE TRIGGER set_swap_requests_updated_at
  BEFORE UPDATE ON public.swap_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE TRIGGER set_swap_sessions_updated_at
  BEFORE UPDATE ON public.swap_sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE TRIGGER set_reports_updated_at
  BEFORE UPDATE ON public.reports
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ############################################################################
-- 5. INDEXES FOR FULLTEXT SEARCH
-- ############################################################################

CREATE INDEX idx_profiles_search
  ON public.profiles
  USING GIN (to_tsvector('english', coalesce(display_name, '') || ' ' || coalesce(bio, '')));

CREATE INDEX idx_skills_search
  ON public.skills
  USING GIN (to_tsvector('english', name || ' ' || coalesce(description, '')));
