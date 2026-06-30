import { Router, Request, Response } from "express";
import { z } from "zod";
import { requireAuth, validate } from "../middleware";
import { getUserClient } from "../config";
import { engine } from "../engine";
import { paginationParams } from "../types";

const router = Router();

const updateSessionSchema = z.object({
  status: z.enum(["scheduled", "in_progress", "completed", "cancelled", "no_show"]),
  notes: z.string().max(2000).optional(),
});

router.get("/", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { page, limit } = paginationParams(Number(req.query.page), Number(req.query.limit));
  const offset = (page - 1) * limit;
  const status = req.query.status as string | undefined;

  let db = client
    .from("swap_sessions")
    .select("*, request:request_id(*), initiator:initiator_id(*), partner:partner_id(*)", { count: "exact" })
    .or(`initiator_id.eq.${req.auth!.userId},partner_id.eq.${req.auth!.userId}`);

  if (status) db = db.eq("status", status);
  db = db.order("created_at", { ascending: false });

  const { data, error, count } = await db.range(offset, offset + limit - 1);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ data, count, page, limit });
});

router.get("/:id", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { data, error } = await client
    .from("swap_sessions")
    .select("*, request:request_id(*), initiator:initiator_id(*), partner:partner_id(*)")
    .eq("id", req.params.id)
    .single();
  if (error) { res.status(404).json({ error: "Session not found" }); return; }
  res.json(data);
});

router.put("/:id/status", requireAuth, validate(updateSessionSchema), async (req: Request, res: Response) => {
  const userId = req.auth!.userId;
  const token = req.auth!.userToken;
  const newStatus = req.body.status as string;
  const notes = req.body.notes as string | undefined;

  const { data: result, error } = await engine.updateSessionStatus({
    session_id: req.params.id as string,
    user_id: userId,
    new_status: newStatus,
    notes,
  });

  if (error) {
    const msg = error.message.toLowerCase();
    if (msg.includes("not found")) { res.status(404).json({ error: error.message }); return; }
    if (msg.includes("cannot transition")) { res.status(400).json({ error: error.message }); return; }
    if (msg.includes("not authorized")) { res.status(403).json({ error: error.message }); return; }
    res.status(400).json({ error: error.message }); return;
  }

  const client = getUserClient(token);
  const { data: full, error: fetchError } = await client
    .from("swap_sessions")
    .select("*, request:request_id(*), initiator:initiator_id(*), partner:partner_id(*)")
    .eq("id", req.params.id)
    .single();
  if (fetchError) { res.status(500).json({ error: "Failed to fetch updated session" }); return; }
  res.json(full);
});

export default router;
