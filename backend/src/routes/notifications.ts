import { Router, Request, Response } from "express";
import { z } from "zod";
import { requireAuth, validate } from "../middleware";
import { getUserClient, getServiceClient } from "../config";
import { paginationParams, paginateSchema } from "../types";

const router = Router();

router.get("/", requireAuth, validate(paginateSchema, "query"), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { page, limit } = paginationParams(Number(req.query.page), Number(req.query.limit));
  const offset = (page - 1) * limit;

  const { data, error, count } = await client
    .from("notifications")
    .select("*", { count: "exact" })
    .eq("user_id", req.auth!.userId)
    .range(offset, offset + limit - 1)
    .order("created_at", { ascending: false });
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ data, count, page, limit });
});

router.get("/unread-count", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { count, error } = await client
    .from("notifications")
    .select("*", { count: "exact", head: true })
    .eq("user_id", req.auth!.userId)
    .eq("is_read", false);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ count });
});

router.put("/:id/read", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { error } = await client
    .from("notifications")
    .update({ is_read: true })
    .eq("id", req.params.id)
    .eq("user_id", req.auth!.userId);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.status(204).end();
});

router.put("/read-all", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { error } = await client
    .from("notifications")
    .update({ is_read: true })
    .eq("user_id", req.auth!.userId)
    .eq("is_read", false);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.status(204).end();
});

router.delete("/:id", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { error } = await client
    .from("notifications")
    .delete()
    .eq("id", req.params.id)
    .eq("user_id", req.auth!.userId);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.status(204).end();
});

export default router;
