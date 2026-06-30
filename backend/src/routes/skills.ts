import { Router, Request, Response } from "express";
import { z } from "zod";
import { requireAuth, validate } from "../middleware";
import { getUserClient, getServiceClient } from "../config";
import { paginationParams } from "../types";

const router = Router();

const teachSkillSchema = z.object({
  skill_id: z.string().uuid(),
  proficiency: z.enum(["beginner", "intermediate", "advanced", "expert"]),
});

const learnSkillSchema = z.object({
  skill_id: z.string().uuid(),
  priority: z.number().int().min(0).max(100).default(0),
});

router.get("/categories", requireAuth, async (_req: Request, res: Response) => {
  const client = getServiceClient();
  const { data, error } = await client
    .from("skill_categories")
    .select("*, skills(*)")
    .order("sort_order");
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json(data);
});

router.get("/", requireAuth, async (req: Request, res: Response) => {
  const client = getServiceClient();
  const { page, limit } = paginationParams(Number(req.query.page), Number(req.query.limit));
  const offset = (page - 1) * limit;
  const query = String(req.query.q || "").trim();
  const categoryId = req.query.category_id as string | undefined;

  let db = client.from("skills").select("*", { count: "exact" });
  if (query) db = db.ilike("name", `%${query}%`);
  if (categoryId) db = db.eq("category_id", categoryId);

  const { data, error, count } = await db.range(offset, offset + limit - 1).order("name");
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json({ data, count, page, limit });
});

router.get("/teaching/:userId", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { data, error } = await client
    .from("teaching_skills")
    .select("*, skills(*)")
    .eq("user_id", req.params.userId);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json(data);
});

router.get("/learning/:userId", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { data, error } = await client
    .from("learning_skills")
    .select("*, skills(*)")
    .eq("user_id", req.params.userId)
    .order("priority", { ascending: false });
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.json(data);
});

router.post("/teaching", requireAuth, validate(teachSkillSchema), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { data: existing } = await client
    .from("teaching_skills")
    .select("id")
    .eq("user_id", req.auth!.userId)
    .eq("skill_id", req.body.skill_id)
    .maybeSingle();
  if (existing) { res.status(409).json({ error: "Already teaching this skill" }); return; }

  const { data, error } = await client
    .from("teaching_skills")
    .insert({ user_id: req.auth!.userId, skill_id: req.body.skill_id, proficiency: req.body.proficiency })
    .select()
    .single();
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.status(201).json(data);
});

router.post("/learning", requireAuth, validate(learnSkillSchema), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { data: existing } = await client
    .from("learning_skills")
    .select("id")
    .eq("user_id", req.auth!.userId)
    .eq("skill_id", req.body.skill_id)
    .maybeSingle();
  if (existing) { res.status(409).json({ error: "Already learning this skill" }); return; }

  const { data, error } = await client
    .from("learning_skills")
    .insert({ user_id: req.auth!.userId, skill_id: req.body.skill_id, priority: req.body.priority })
    .select()
    .single();
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.status(201).json(data);
});

router.delete("/teaching/:skillId", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { error } = await client
    .from("teaching_skills")
    .delete()
    .eq("user_id", req.auth!.userId)
    .eq("skill_id", req.params.skillId);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.status(204).end();
});

router.delete("/learning/:skillId", requireAuth, async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { error } = await client
    .from("learning_skills")
    .delete()
    .eq("user_id", req.auth!.userId)
    .eq("skill_id", req.params.skillId);
  if (error) { res.status(400).json({ error: error.message }); return; }
  res.status(204).end();
});

export default router;
