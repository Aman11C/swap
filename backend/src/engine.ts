import { getServiceClient } from "./config";
import type { PostgrestError } from "@supabase/supabase-js";

interface RpcResult<T> {
  data: T | null;
  error: PostgrestError | null;
}

interface CreateRequestParams {
  sender_id: string;
  receiver_id: string;
  skill_offered_id: string;
  skill_requested_id: string;
  message?: string;
}

interface UpdateRequestStatusParams {
  request_id: string;
  user_id: string;
  new_status: string;
}

interface UpdateSessionStatusParams {
  session_id: string;
  user_id: string;
  new_status: string;
  notes?: string;
}

interface CreateNotificationParams {
  user_id: string;
  type: string;
  title: string;
  body?: string;
  data?: Record<string, unknown>;
}

class SkillSwapEngine {
  private client = getServiceClient();

  async createRequest(
    params: CreateRequestParams
  ): Promise<RpcResult<{ id: string }>> {
    return this.client.rpc("create_swap_request", {
      p_sender_id: params.sender_id,
      p_receiver_id: params.receiver_id,
      p_skill_offered_id: params.skill_offered_id,
      p_skill_requested_id: params.skill_requested_id,
      p_message: params.message ?? "",
    });
  }

  async updateRequestStatus(
    params: UpdateRequestStatusParams
  ): Promise<RpcResult<{ id: string; session_id?: string }>> {
    return this.client.rpc("update_swap_request_status", {
      p_request_id: params.request_id,
      p_user_id: params.user_id,
      p_new_status: params.new_status,
    });
  }

  async updateSessionStatus(
    params: UpdateSessionStatusParams
  ): Promise<RpcResult<{ id: string }>> {
    return this.client.rpc("update_swap_session_status", {
      p_session_id: params.session_id,
      p_user_id: params.user_id,
      p_new_status: params.new_status,
      p_notes: params.notes ?? null,
    });
  }

  async createNotification(
    params: CreateNotificationParams
  ): Promise<RpcResult<{ id: string }>> {
    return this.client.rpc("insert_notification", {
      p_user_id: params.user_id,
      p_type: params.type,
      p_title: params.title,
      p_body: params.body ?? "",
      p_data: params.data ?? {},
    });
  }
}

export const engine = new SkillSwapEngine();
