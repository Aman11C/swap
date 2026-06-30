import { Router, Request, Response } from "express";
import { z } from "zod";
import { requireAuth, validate } from "../middleware";
import { getUserClient, getServiceClient } from "../config";
import { paginationParams } from "../types";

const router = Router();

const updateProfileSchema = z.object({
  display_name: z.string().max(100).optional(),
  bio: z.string().max(500).optional(),
  college: z.string().max(200).optional(),
  degree: z.string().max(200).optional(),
  year: z.string().max(50).optional(),
  location: z.string().max(200).optional(),
  avatar_url: z.string().url().max(500).optional().nullable(),
  is_onboarded: z.boolean().optional(),
});

router.get("/me", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { data, error } = await client.from("profiles").select("*").eq("id", req.auth!.userId).single();
  if (error) { res.status(404).json({ error: "Profile not found" }); return; }
  res.json(data);
});

router.put("/me", requireAuth, validate(updateProfileSchema), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { data, error } = await client.from("profiles").update(req.body).eq("id", req.auth!.userId).select().single();
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json(data);
});

router.get("/search", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { page, limit } = paginationParams(Number(req.query.page), Number(req.query.limit));
  const query = String(req.query.q || "").trim();
  const offset = (page - 1) * limit;

  let db = client.from("profiles").select("*", { count: "exact" });
  if (query) {
    db = db.or(`username.ilike.%${query}%,display_name.ilike.%${query}%,bio.ilike.%${query}%,college.ilike.%${query}%`);
  }
  const { data, error, count } = await db.range(offset, offset + limit - 1);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ data, count, page, limit });
});

router.get("/:id", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { data, error } = await client.from("profiles").select("*").eq("id", req.params.id).single();
  if (error) { res.status(404).json({ error: "Profile not found" }); return; }
  res.json(data);
});

export default router;
