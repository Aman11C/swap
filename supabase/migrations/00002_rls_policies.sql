-- ============================================================================
-- SWAP — Complete Row Level Security Policies
-- ============================================================================

-- ############################################################################
-- 0. ENABLE RLS ON ALL TABLES
-- ############################################################################

ALTER TABLE public.profiles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skill_categories    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skills              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teaching_skills     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.learning_skills     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.swap_requests       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.swap_sessions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.achievements        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_achievements   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookmarks           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_logs          ENABLE ROW LEVEL SECURITY;

-- ############################################################################
-- 1. PROFILES
-- ############################################################################
-- Users can read public profiles.
CREATE POLICY "Profiles are readable by all authenticated users"
  ON public.profiles FOR SELECT
  USING (auth.role() = 'authenticated');

-- Users can insert only their own profile.
CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (id = auth.uid());

-- Users can update only their own profile.
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Users can delete only their own profile.
CREATE POLICY "Users can delete own profile"
  ON public.profiles FOR DELETE
  USING (id = auth.uid());

-- ############################################################################
-- 2. SKILL CATEGORIES (reference table)
-- ############################################################################
CREATE POLICY "Skill categories are readable by all authenticated users"
  ON public.skill_categories FOR SELECT
  USING (auth.role() = 'authenticated');

-- ############################################################################
-- 3. SKILLS (reference table)
-- ############################################################################
CREATE POLICY "Skills are readable by all authenticated users"
  ON public.skills FOR SELECT
  USING (auth.role() = 'authenticated');

-- ############################################################################
-- 4. TEACHING SKILLS
-- ############################################################################
-- Anyone can view.
CREATE POLICY "Teaching skills are readable by all authenticated users"
  ON public.teaching_skills FOR SELECT
  USING (auth.role() = 'authenticated');

-- Only owner can insert.
CREATE POLICY "Users can insert own teaching skills"
  ON public.teaching_skills FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Only owner can update.
CREATE POLICY "Users can update own teaching skills"
  ON public.teaching_skills FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Only owner can delete.
CREATE POLICY "Users can delete own teaching skills"
  ON public.teaching_skills FOR DELETE
  USING (user_id = auth.uid());

-- ############################################################################
-- 5. LEARNING SKILLS
-- ############################################################################
-- Anyone can view.
CREATE POLICY "Learning skills are readable by all authenticated users"
  ON public.learning_skills FOR SELECT
  USING (auth.role() = 'authenticated');

-- Only owner can insert.
CREATE POLICY "Users can insert own learning skills"
  ON public.learning_skills FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Only owner can update.
CREATE POLICY "Users can update own learning skills"
  ON public.learning_skills FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Only owner can delete.
CREATE POLICY "Users can delete own learning skills"
  ON public.learning_skills FOR DELETE
  USING (user_id = auth.uid());

-- ############################################################################
-- 6. SWAP REQUESTS
-- ############################################################################
-- Sender can create.
CREATE POLICY "Sender can create swap request"
  ON public.swap_requests FOR INSERT
  WITH CHECK (sender_id = auth.uid());

-- Participants (sender and receiver) can view.
CREATE POLICY "Participants can view swap request"
  ON public.swap_requests FOR SELECT
  USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Only participants can update.
CREATE POLICY "Participants can update swap request"
  ON public.swap_requests FOR UPDATE
  USING (sender_id = auth.uid() OR receiver_id = auth.uid())
  WITH CHECK (sender_id = auth.uid() OR receiver_id = auth.uid());

-- ############################################################################
-- 7. SWAP SESSIONS
-- ############################################################################
-- Participants can view.
CREATE POLICY "Participants can view swap session"
  ON public.swap_sessions FOR SELECT
  USING (initiator_id = auth.uid() OR partner_id = auth.uid());

-- Participants can update (e.g. mark as completed).
CREATE POLICY "Participants can update swap session"
  ON public.swap_sessions FOR UPDATE
  USING (initiator_id = auth.uid() OR partner_id = auth.uid())
  WITH CHECK (initiator_id = auth.uid() OR partner_id = auth.uid());

-- ############################################################################
-- 8. MESSAGES
-- ############################################################################
-- Only sender and receiver (session participants) can read.
CREATE POLICY "Session participants can read messages"
  ON public.messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.swap_sessions
      WHERE id = session_id
        AND (initiator_id = auth.uid() OR partner_id = auth.uid())
    )
  );

-- Sender can create a message.
CREATE POLICY "Session participants can insert messages"
  ON public.messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.swap_sessions
      WHERE id = session_id
        AND (initiator_id = auth.uid() OR partner_id = auth.uid())
    )
  );

-- ############################################################################
-- 9. NOTIFICATIONS
-- ############################################################################
-- Only owner can read.
CREATE POLICY "Users can read own notifications"
  ON public.notifications FOR SELECT
  USING (user_id = auth.uid());

-- Only owner can mark as read.
CREATE POLICY "Users can update own notifications"
  ON public.notifications FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Only owner can delete.
CREATE POLICY "Users can delete own notifications"
  ON public.notifications FOR DELETE
  USING (user_id = auth.uid());

-- ############################################################################
-- 10. REVIEWS
-- ############################################################################
-- Anyone can view.
CREATE POLICY "Reviews are readable by all authenticated users"
  ON public.reviews FOR SELECT
  USING (auth.role() = 'authenticated');

-- Only verified participants can create.
-- A verified participant is someone who has a COMPLETED swap session
-- with the reviewee (initiator or partner).
CREATE POLICY "Verified session participants can create reviews"
  ON public.reviews FOR INSERT
  WITH CHECK (
    reviewer_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.swap_sessions
      WHERE id = session_id
        AND status = 'completed'
        AND (
          (initiator_id = auth.uid() AND partner_id = reviewee_id)
          OR
          (initiator_id = reviewee_id AND partner_id = auth.uid())
        )
    )
  );

-- ############################################################################
-- 11. ACHIEVEMENTS (reference table)
-- ############################################################################
CREATE POLICY "Achievements are readable by all authenticated users"
  ON public.achievements FOR SELECT
  USING (auth.role() = 'authenticated');

-- ############################################################################
-- 12. USER ACHIEVEMENTS
-- ############################################################################
CREATE POLICY "Users can read own achievements"
  ON public.user_achievements FOR SELECT
  USING (user_id = auth.uid());

-- ############################################################################
-- 13. BOOKMARKS
-- ############################################################################
CREATE POLICY "Users can read own bookmarks"
  ON public.bookmarks FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "Users can create own bookmarks"
  ON public.bookmarks FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete own bookmarks"
  ON public.bookmarks FOR DELETE
  USING (user_id = auth.uid());

-- ############################################################################
-- 14. REPORTS
-- ############################################################################
CREATE POLICY "Users can create reports"
  ON public.reports FOR INSERT
  WITH CHECK (reporter_id = auth.uid());

CREATE POLICY "Reporters can read own reports"
  ON public.reports FOR SELECT
  USING (reporter_id = auth.uid());
