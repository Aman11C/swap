import { getServiceClient } from "./config";
import type { PostgrestError } from "@supabase/supabase-js";

interface RpcResult<T> {
  data: T | null;
  error: PostgrestError | null;
}

class AdminEngine {
  private client = getServiceClient();

  async banUser(adminId: string, userId: string, reason: string): Promise<RpcResult<null>> {
    return this.client.rpc("admin_ban_user", { p_admin_id: adminId, p_user_id: userId, p_reason: reason });
  }

  async unbanUser(adminId: string, userId: string): Promise<RpcResult<null>> {
    return this.client.rpc("admin_unban_user", { p_admin_id: adminId, p_user_id: userId });
  }

  async warnUser(adminId: string, userId: string, reason: string): Promise<RpcResult<null>> {
    return this.client.rpc("admin_warn_user", { p_admin_id: adminId, p_user_id: userId, p_reason: reason });
  }

  async resolveReport(adminId: string, reportId: string, action: string): Promise<RpcResult<null>> {
    return this.client.rpc("admin_resolve_report", { p_admin_id: adminId, p_report_id: reportId, p_action: action });
  }

  async removeContent(adminId: string, targetType: string, targetId: string, reason: string): Promise<RpcResult<null>> {
    return this.client.rpc("admin_remove_content", { p_admin_id: adminId, p_target_type: targetType, p_target_id: targetId, p_reason: reason });
  }

  async adjustXp(adminId: string, userId: string, amount: number, reason: string): Promise<RpcResult<null>> {
    return this.client.rpc("admin_adjust_xp", { p_admin_id: adminId, p_user_id: userId, p_amount: amount, p_reason: reason });
  }

  async getStats(adminId: string): Promise<RpcResult<Record<string, number>>> {
    return this.client.rpc("admin_get_stats", { p_admin_id: adminId });
  }

  async searchUsers(adminId: string, query: string, page: number, limit: number): Promise<RpcResult<Record<string, unknown>>> {
    return this.client.rpc("admin_search_users", { p_admin_id: adminId, p_query: query, p_page: page, p_limit: limit });
  }

  async getReports(adminId: string, status: string, page: number, limit: number): Promise<RpcResult<Record<string, unknown>>> {
    return this.client.rpc("admin_get_reports", { p_admin_id: adminId, p_status: status, p_page: page, p_limit: limit });
  }

  async getLogs(adminId: string, page: number, limit: number): Promise<RpcResult<Record<string, unknown>>> {
    return this.client.rpc("admin_get_logs", { p_admin_id: adminId, p_page: page, p_limit: limit });
  }

  async awardAchievement(adminId: string, userId: string, achievementId: string): Promise<RpcResult<null>> {
    return this.client.rpc("admin_award_achievement", { p_admin_id: adminId, p_user_id: userId, p_achievement_id: achievementId });
  }
}

export const adminEngine = new AdminEngine();
