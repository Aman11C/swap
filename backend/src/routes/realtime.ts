import { Router, Request, Response } from "express";
import { z } from "zod";
import { requireAuth, validate } from "../middleware";
import { getUserClient } from "../config";

const router = Router();

const typingSchema = z.object({
  session_id: z.string().uuid(),
});

router.post("/typing", requireAuth, validate(typingSchema), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { session_id } = req.body;

  const { data: session } = await client
    .from("swap_sessions")
    .select("initiator_id, partner_id")
    .eq("id", session_id)
    .single();
  if (!session) { res.status(404).json({ error: "Session not found" }); return; }
  if (session.initiator_id !== req.auth!.userId && session.partner_id !== req.auth!.userId) {
    res.status(403).json({ error: "Not a participant in this session" }); return;
  }

  const { error } = await client
    .from("typing_indicators")
    .upsert(
      { session_id, user_id: req.auth!.userId, created_at: new Date().toISOString() },
      { onConflict: "session_id, user_id" }
    );
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ success: true });
});

router.delete("/typing/:sessionId", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { error } = await client
    .from("typing_indicators")
    .delete()
    .eq("session_id", req.params.sessionId)
    .eq("user_id", req.auth!.userId);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ success: true });
});

const presenceSchema = z.object({
  status: z.enum(["online", "away", "offline"]),
});

router.post("/presence", requireAuth, validate(presenceSchema), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { status } = req.body;

  const { error } = await client
    .from("user_presence")
    .upsert(
      { user_id: req.auth!.userId, status, last_seen_at: new Date().toISOString() },
      { onConflict: "user_id" }
    );
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ success: true });
});

const readReceiptSchema = z.object({
  session_id: z.string().uuid(),
});

router.post("/read", requireAuth, validate(readReceiptSchema), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { session_id } = req.body;

  const { data: session } = await client
    .from("swap_sessions")
    .select("initiator_id, partner_id")
    .eq("id", session_id)
    .single();
  if (!session) { res.status(404).json({ error: "Session not found" }); return; }
  if (session.initiator_id !== req.auth!.userId && session.partner_id !== req.auth!.userId) {
    res.status(403).json({ error: "Not a participant in this session" }); return;
  }

  const { data: messages } = await client
    .from("messages")
    .select("id")
    .eq("session_id", session_id)
    .neq("sender_id", req.auth!.userId)
    .eq("is_deleted", false);

  if (!messages || messages.length === 0) { res.json({ marked_read: 0 }); return; }

  const reads = messages.map(m => ({
    user_id: req.auth!.userId,
    message_id: m.id,
  }));

  const { error } = await client.from("message_reads").upsert(reads, { onConflict: "user_id, message_id" });
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ marked_read: reads.length });
});

export default router;
