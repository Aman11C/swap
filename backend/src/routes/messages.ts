import { Router, Request, Response } from "express";
import { z } from "zod";
import { requireAuth, validate } from "../middleware";
import { getUserClient } from "../config";
import { engine } from "../engine";
import { paginationParams, paginateSchema } from "../types";

const router = Router();

const sendMessageSchema = z.object({
  content: z.string().min(1).max(5000),
});

router.get("/session/:sessionId", requireAuth, validate(paginateSchema, "query"), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { page, limit } = paginationParams(Number(req.query.page), Number(req.query.limit));
  const offset = (page - 1) * limit;

  const { data: session } = await client
    .from("swap_sessions")
    .select("initiator_id, partner_id")
    .eq("id", req.params.sessionId)
    .single();
  if (!session) { res.status(404).json({ error: "Session not found" }); return; }
  if (session.initiator_id !== req.auth!.userId && session.partner_id !== req.auth!.userId) {
    res.status(403).json({ error: "Not a participant in this session" }); return;
  }

  const { data, error, count } = await client
    .from("messages")
    .select("*, sender:sender_id(*)", { count: "exact" })
    .eq("session_id", req.params.sessionId)
    .eq("is_deleted", false)
    .range(offset, offset + limit - 1)
    .order("created_at", { ascending: false });
  if (error) { res.status(400).json({ error: error.message }); return; }
  (data as Record<string, unknown>[])?.reverse();
  res.json({ data, count, page, limit });
});

router.post("/session/:sessionId", requireAuth, validate(sendMessageSchema), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { content } = req.body;

  const { data: session } = await client
    .from("swap_sessions")
    .select("initiator_id, partner_id")
    .eq("id", req.params.sessionId)
    .single();
  if (!session) { res.status(404).json({ error: "Session not found" }); return; }
  if (session.initiator_id !== req.auth!.userId && session.partner_id !== req.auth!.userId) {
    res.status(403).json({ error: "Not a participant in this session" }); return;
  }

  const { data: msg, error } = await client
    .from("messages")
    .insert({ session_id: req.params.sessionId, sender_id: req.auth!.userId, content })
    .select("*, sender:sender_id(*)")
    .single();
  if (error) { res.status(400).json({ error: error.message }); return; }

  const otherUserId = session.initiator_id === req.auth!.userId ? session.partner_id : session.initiator_id;
  await engine.createNotification({
    user_id: otherUserId,
    type: "new_message",
    title: "New message",
    body: content.length > 120 ? content.slice(0, 120) + "..." : content,
    data: { session_id: req.params.sessionId, message_id: msg.id },
  });

  res.status(201).json(msg);
});

router.delete("/:id", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);

  const { data: msg } = await client
    .from("messages")
    .select("id, sender_id, session_id")
    .eq("id", req.params.id)
    .single();
  if (!msg) { res.status(404).json({ error: "Message not found" }); return; }
  if (msg.sender_id !== req.auth!.userId) {
    res.status(403).json({ error: "Cannot delete another user's message" }); return;
  }

  const { error } = await client
    .from("messages")
    .update({ is_deleted: true })
    .eq("id", req.params.id);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ success: true });
});

router.get("/session/:sessionId/unread", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);

  const { data: session } = await client
    .from("swap_sessions")
    .select("initiator_id, partner_id")
    .eq("id", req.params.sessionId)
    .single();
  if (!session) { res.status(404).json({ error: "Session not found" }); return; }
  if (session.initiator_id !== req.auth!.userId && session.partner_id !== req.auth!.userId) {
    res.status(403).json({ error: "Not a participant in this session" }); return;
  }

  const { count, error } = await client
    .from("messages")
    .select("id", { count: "exact", head: true })
    .eq("session_id", req.params.sessionId)
    .neq("sender_id", req.auth!.userId)
    .eq("is_deleted", false)
    .not("id", "in", (
      await client.from("message_reads").select("message_id").eq("user_id", req.auth!.userId)
    ).data?.map(r => r.message_id) ?? []);

  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ unread_count: count ?? 0 });
});

export default router;
