import { Router, Request, Response } from "express";
import { z } from "zod";
import { requireAuth, validate } from "../middleware";
import { getUserClient } from "../config";
import { engine } from "../engine";
import { paginationParams, paginateSchema } from "../types";

const router = Router();

const createRequestSchema = z.object({
  receiver_id: z.string().uuid(),
  skill_offered_id: z.string().uuid(),
  skill_requested_id: z.string().uuid(),
  message: z.string().max(500).default(""),
});

const updateStatusSchema = z.object({
  status: z.enum(["accepted", "declined", "cancelled"]),
});

router.post("/", requireAuth, validate(createRequestSchema), async (req: Request, res: Response) => {
  const userId = req.auth!.userId;
  const token = req.auth!.userToken;
  const { receiver_id, skill_offered_id, skill_requested_id, message } = req.body;

  const { data: result, error } = await engine.createRequest({
    sender_id: userId,
    receiver_id,
    skill_offered_id,
    skill_requested_id,
    message,
  });

  if (error) {
    const msg = error.message.toLowerCase();
    if (msg.includes("already exists")) { res.status(409).json({ error: error.message }); return; }
    if (msg.includes("cannot swap with yourself")) { res.status(400).json({ error: error.message }); return; }
    res.status(400).json({ error: error.message }); return;
  }

  const client = getUserClient(token);
  const { data: full, error: fetchError } = await client
    .from("swap_requests")
    .select("*, skill_offered:skill_offered_id(*), skill_requested:skill_requested_id(*), sender:sender_id(*), receiver:receiver_id(*)")
    .eq("id", result!.id)
    .single();
  if (fetchError) { res.status(500).json({ error: "Failed to fetch created request" }); return; }
  res.status(201).json(full);
});

router.get("/", requireAuth, validate(paginateSchema, "query"), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { page, limit } = paginationParams(Number(req.query.page), Number(req.query.limit));
  const offset = (page - 1) * limit;
  const status = req.query.status as string | undefined;
  const direction = req.query.direction as string | undefined;

  let db = client.from("swap_requests").select("*, skill_offered:skill_offered_id(*), skill_requested:skill_requested_id(*), sender:sender_id(*), receiver:receiver_id(*)", { count: "exact" });

  if (direction === "sent") db = db.eq("sender_id", req.auth!.userId);
  else if (direction === "received") db = db.eq("receiver_id", req.auth!.userId);
  else db = db.or(`sender_id.eq.${req.auth!.userId},receiver_id.eq.${req.auth!.userId}`);

  if (status) db = db.eq("status", status);
  db = db.order("created_at", { ascending: false });

  const { data, error, count } = await db.range(offset, offset + limit - 1);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ data, count, page, limit });
});

router.get("/:id", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { data, error } = await client
    .from("swap_requests")
    .select("*, skill_offered:skill_offered_id(*), skill_requested:skill_requested_id(*), sender:sender_id(*), receiver:receiver_id(*)")
    .eq("id", req.params.id)
    .single();
  if (error) { res.status(404).json({ error: "Swap request not found" }); return; }
  res.json(data);
});

router.put("/:id/status", requireAuth, validate(updateStatusSchema), async (req: Request, res: Response) => {
  const userId = req.auth!.userId;
  const token = req.auth!.userToken;
  const newStatus = req.body.status as string;

  const { data: result, error } = await engine.updateRequestStatus({
    request_id: req.params.id as string,
    user_id: userId,
    new_status: newStatus,
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
    .from("swap_requests")
    .select("*, skill_offered:skill_offered_id(*), skill_requested:skill_requested_id(*), sender:sender_id(*), receiver:receiver_id(*)")
    .eq("id", req.params.id)
    .single();
  if (fetchError) { res.status(500).json({ error: "Failed to fetch updated request" }); return; }
  res.json(full);
});

export default router;
