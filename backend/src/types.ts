export type SwapRequestStatus = "pending" | "accepted" | "declined" | "cancelled";
export type SwapSessionStatus = "scheduled" | "in_progress" | "completed" | "cancelled" | "no_show";
export type NotificationType =
  | "swap_request" | "swap_accepted" | "swap_declined" | "swap_cancelled"
  | "new_message" | "session_reminder" | "review_received"
  | "achievement_unlocked" | "xp_milestone" | "system";
export type ReportReason =
  | "inappropriate_content" | "fake_profile" | "harassment"
  | "spam" | "scam" | "impersonation" | "other";
export type ReportStatus = "pending" | "under_review" | "resolved" | "dismissed";
export type ProficiencyLevel = "beginner" | "intermediate" | "advanced" | "expert";
export type AdminActionType =
  | "user_warned" | "user_suspended" | "user_banned" | "user_unbanned"
  | "content_removed" | "report_resolved" | "report_dismissed"
  | "achievement_awarded" | "xp_adjusted" | "system_config";

export interface Profile {
  id: string;
  username: string;
  display_name: string | null;
  bio: string;
  college: string;
  degree: string;
  year: string;
  location: string;
  avatar_url: string | null;
  xp: number;
  level: number;
  is_banned: boolean;
  is_admin: boolean;
  is_onboarded: boolean;
  created_at: string;
  updated_at: string;
}

export interface SkillCategory {
  id: string;
  name: string;
  slug: string;
  description: string;
  icon: string | null;
  sort_order: number;
  created_at: string;
}

export interface Skill {
  id: string;
  category_id: string;
  name: string;
  slug: string;
  description: string;
  created_at: string;
}

export interface TeachingSkill {
  id: string;
  user_id: string;
  skill_id: string;
  proficiency: ProficiencyLevel;
  created_at: string;
}

export interface LearningSkill {
  id: string;
  user_id: string;
  skill_id: string;
  priority: number;
  created_at: string;
}

export interface SwapRequest {
  id: string;
  sender_id: string;
  receiver_id: string;
  skill_offered_id: string;
  skill_requested_id: string;
  message: string;
  status: SwapRequestStatus;
  created_at: string;
  updated_at: string;
}

export interface SwapSession {
  id: string;
  request_id: string;
  initiator_id: string;
  partner_id: string;
  scheduled_at: string | null;
  started_at: string | null;
  ended_at: string | null;
  status: SwapSessionStatus;
  notes: string;
  created_at: string;
  updated_at: string;
}

export interface Message {
  id: string;
  session_id: string;
  sender_id: string;
  content: string;
  is_deleted: boolean;
  created_at: string;
  updated_at: string | null;
}

export interface MessageRead {
  id: string;
  user_id: string;
  message_id: string;
  read_at: string;
}

export interface TypingIndicator {
  id: string;
  session_id: string;
  user_id: string;
  created_at: string;
}

export interface UserPresence {
  user_id: string;
  status: "online" | "away" | "offline";
  last_seen_at: string;
  updated_at: string;
}

export interface Notification {
  id: string;
  user_id: string;
  type: NotificationType;
  title: string;
  body: string;
  data: Record<string, unknown>;
  is_read: boolean;
  created_at: string;
}

export interface Review {
  id: string;
  session_id: string;
  reviewer_id: string;
  reviewee_id: string;
  rating: number;
  comment: string;
  created_at: string;
}

export interface Achievement {
  id: string;
  name: string;
  slug: string;
  description: string;
  icon: string;
  xp_reward: number;
  criteria: Record<string, unknown>;
  created_at: string;
}

export interface UserAchievement {
  id: string;
  user_id: string;
  achievement_id: string;
  earned_at: string;
}

export interface Bookmark {
  id: string;
  user_id: string;
  target_user_id: string | null;
  skill_id: string | null;
  created_at: string;
}

export interface Report {
  id: string;
  reporter_id: string;
  reported_user_id: string;
  reason: ReportReason;
  description: string;
  status: ReportStatus;
  reviewed_by: string | null;
  reviewed_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface AdminLog {
  id: string;
  admin_id: string;
  action: AdminActionType;
  target_type: string;
  target_id: string | null;
  details: Record<string, unknown>;
  ip_address: string | null;
  created_at: string;
}

export interface AuthenticatedRequest {
  userId: string;
  userToken: string;
}

import { z } from "zod";

export const paginateSchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(20),
});

export interface PaginationParams {
  page: number;
  limit: number;
}

export function paginationParams(page?: number, limit?: number): PaginationParams {
  return {
    page: Math.max(1, page ?? 1),
    limit: Math.min(100, Math.max(1, limit ?? 20)),
  };
}
