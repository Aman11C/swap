import { Router, Request, Response } from "express";
import { z } from "zod";
import { requireAuth, validate } from "../middleware";
import { getUserClient } from "../config";

const router = Router();

const createBookmarkSchema = z.object({
  target_user_id: z.string().uuid().optional().nullable(),
  skill_id: z.string().uuid().optional().nullable(),
}).refine((d) => d.target_user_id || d.skill_id, { message: "Provide target_user_id or skill_id" });

router.get("/", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { data, error } = await client
    .from("bookmarks")
    .select("*, target_user:target_user_id(*), skill:skill_id(*)")
    .eq("user_id", req.auth!.userId)
    .order("created_at", { ascending: false });
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json(data);
});

router.post("/", requireAuth, validate(createBookmarkSchema), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);

  const { data: existing } = await client
    .from("bookmarks")
    .select("id")
    .eq("user_id", req.auth!.userId)
    .eq("target_user_id", req.body.target_user_id ?? "00000000-0000-0000-0000-000000000000")
    .eq("skill_id", req.body.skill_id ?? "00000000-0000-0000-0000-000000000000")
    .maybeSingle();
  if (existing) { res.status(409).json({ error: "Bookmark already exists" }); return; }

  const { data, error } = await client
    .from("bookmarks")
    .insert({ user_id: req.auth!.userId, target_user_id: req.body.target_user_id ?? null, skill_id: req.body.skill_id ?? null })
    .select()
    .single();
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.status(201).json(data);
});

router.delete("/:id", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { error } = await client
    .from("bookmarks")
    .delete()
    .eq("id", req.params.id)
    .eq("user_id", req.auth!.userId);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.status(204).end();
});

export default router;
