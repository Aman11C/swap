-- ============================================================================
-- SWAP — Supabase Storage Configuration
-- ============================================================================
-- Buckets:
--   avatars        (public)        — profile pictures
--   skill-images   (public)        — skill showcase photos
--   certificates   (private)       — achievement certificates (signed URLs)
--   documents      (private)       — shared documents      (signed URLs)
-- ============================================================================

-- ############################################################################
-- 1. CREATE BUCKETS
-- ############################################################################

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types, avif_autodetection)
VALUES
  ('avatars',       'avatars',       true,  2097152,  ARRAY['image/jpeg','image/png','image/webp','image/avif'],             true),
  ('skill-images',  'skill-images',  true,  5242880,  ARRAY['image/jpeg','image/png','image/webp','image/avif'],             true),
  ('certificates',  'certificates',  false, 5242880,  ARRAY['image/jpeg','image/png','image/webp','application/pdf'],        false),
  ('documents',     'documents',     false, 10485760, ARRAY['image/jpeg','image/png','image/webp','application/pdf', 'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document'], false)
ON CONFLICT (id) DO UPDATE SET
  public             = EXCLUDED.public,
  file_size_limit    = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types,
  avif_autodetection = EXCLUDED.avif_autodetection;

-- ############################################################################
-- 2. FOLDER CONVENTION
-- All uploads follow:    {bucket}/{user_id}/{filename}
-- Example:              avatars/a1b2c3d4-e5f6-7890-abcd-ef1234567890/me.jpg
-- This convention lets RLS policies scope access to the owning user.
-- ############################################################################

-- ############################################################################
-- 3. RLS POLICIES ON storage.objects
-- ############################################################################

-- ── AVATARS (public read, write own) ────────────────────────────────────────

CREATE POLICY "Avatars are publicly readable"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Users can upload own avatar"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

CREATE POLICY "Users can update own avatar"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

CREATE POLICY "Users can delete own avatar"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

-- ── SKILL-IMAGES (public read, write own) ───────────────────────────────────

CREATE POLICY "Skill images are publicly readable"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'skill-images');

CREATE POLICY "Users can upload own skill images"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'skill-images'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

CREATE POLICY "Users can update own skill images"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'skill-images'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

CREATE POLICY "Users can delete own skill images"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'skill-images'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

-- ── CERTIFICATES (private — owner only via signed URLs) ─────────────────────

CREATE POLICY "Users can view own certificates"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'certificates'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

CREATE POLICY "Users can upload own certificates"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'certificates'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

CREATE POLICY "Users can update own certificates"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'certificates'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

CREATE POLICY "Users can delete own certificates"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'certificates'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

-- ── DOCUMENTS (private — owner only via signed URLs) ────────────────────────

CREATE POLICY "Users can view own documents"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'documents'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

CREATE POLICY "Users can upload own documents"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'documents'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

CREATE POLICY "Users can update own documents"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'documents'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

CREATE POLICY "Users can delete own documents"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'documents'
    AND auth.role() = 'authenticated'
    AND SPLIT_PART(name, '/', 1) = auth.uid()::text
  );

-- ############################################################################
-- 4. SIGNED-URL HELPER (for private buckets: certificates, documents)
-- ############################################################################
-- Usage from the client:
--   SELECT get_signed_url('certificates', 'uuid-here/filename.pdf', 3600);
--
-- This returns a time-limited URL the user can open directly
-- without needing a SELECT policy on the bucket.

CREATE OR REPLACE FUNCTION public.get_signed_url(
  bucket_name  text,
  file_path    text,
  expires_in   int DEFAULT 3600
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  url text;
BEGIN
  SELECT storage.sign(bucket_name, file_path, expires_in) INTO url;
  RETURN url;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_signed_url TO authenticated;

-- ############################################################################
-- 5. STORAGE USAGE SUMMARY (for reference)
-- ############################################################################
-- Bucket         Access       Max Size  Allowed Types                     Compression
-- ─────────────  ───────────  ────────  ─────────────────────────────────  ──────────
-- avatars        public        2 MB     jpeg, png, webp, avif             auto
-- skill-images   public        5 MB     jpeg, png, webp, avif             auto
-- certificates   private       5 MB     jpeg, png, webp, pdf              none
-- documents      private      10 MB     jpeg, png, webp, pdf, doc, docx   none
--
-- Image compression for public buckets is handled automatically at read time
-- via Supabase Image Transformation URL parameters:
--   ?width=200&height=200&quality=80&format=webp
--
-- For avatars shown in the UI:
--   https://<project>.supabase.co/storage/v1/render/image/public/avatars/{uid}/{file}?width=96&height=96&quality=80&format=webp
