import { Router, Request, Response } from "express";
import { z } from "zod";
import { requireAuth, validate } from "../middleware";
import { adminEngine } from "../adminEngine";
import { getUserClient } from "../config";

const router = Router();

async function requireAdmin(req: Request, res: Response, next: () => void): Promise<void> {
  const client = getUserClient(req.auth!.userToken);
  const { data: profile } = await client.from("profiles").select("is_admin").eq("id", req.auth!.userId).single();
  if (!profile?.is_admin) {
    res.status(403).json({ error: "Admin access required" });
    return;
  }
  next();
}

router.use(requireAuth);

const paginateSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

router.get("/stats", requireAdmin, async (req: Request, res: Response) => {
  const { data, error } = await adminEngine.getStats(req.auth!.userId);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json(data);
});

router.get("/users", requireAdmin, validate(paginateSchema, "query"), async (req: Request, res: Response) => {
  const { page, limit } = req.query as unknown as { page: number; limit: number };
  const query = (req.query.q as string) || "";
  const { data, error } = await adminEngine.searchUsers(req.auth!.userId, query, page, limit);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json(data);
});

const banSchema = z.object({ user_id: z.string().uuid(), reason: z.string().default("") });
const warnSchema = z.object({ user_id: z.string().uuid(), reason: z.string().default("") });

router.post("/users/:userId/ban", requireAdmin, validate(banSchema), async (req: Request, res: Response) => {
  const { reason } = req.body;
  const userId = req.params.userId as string;
  const { error } = await adminEngine.banUser(req.auth!.userId, userId, reason);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ success: true });
});

router.post("/users/:userId/unban", requireAdmin, async (req: Request, res: Response) => {
  const userId = req.params.userId as string;
  const { error } = await adminEngine.unbanUser(req.auth!.userId, userId);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ success: true });
});

router.post("/users/:userId/warn", requireAdmin, validate(warnSchema), async (req: Request, res: Response) => {
  const { reason } = req.body;
  const userId = req.params.userId as string;
  const { error } = await adminEngine.warnUser(req.auth!.userId, userId, reason);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ success: true });
});

const xpSchema = z.object({ user_id: z.string().uuid(), amount: z.number().int(), reason: z.string().default("") });

router.post("/users/:userId/xp", requireAdmin, validate(xpSchema), async (req: Request, res: Response) => {
  const { amount, reason } = req.body;
  const userId = req.params.userId as string;
  const { error } = await adminEngine.adjustXp(req.auth!.userId, userId, amount, reason);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ success: true });
});

const achievementSchema = z.object({ user_id: z.string().uuid(), achievement_id: z.string().uuid() });

router.post("/achievements/award", requireAdmin, validate(achievementSchema), async (req: Request, res: Response) => {
  const { user_id, achievement_id } = req.body;
  const { error } = await adminEngine.awardAchievement(req.auth!.userId, user_id, achievement_id);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ success: true });
});

router.get("/reports", requireAdmin, validate(paginateSchema, "query"), async (req: Request, res: Response) => {
  const { page, limit } = req.query as unknown as { page: number; limit: number };
  const status = (req.query.status as string) || "pending";
  const { data, error } = await adminEngine.getReports(req.auth!.userId, status, page, limit);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json(data);
});

const resolveSchema = z.object({ action: z.enum(["resolved", "dismissed"]).default("resolved") });

router.post("/reports/:reportId/resolve", requireAdmin, validate(resolveSchema), async (req: Request, res: Response) => {
  const { action } = req.body;
  const reportId = req.params.reportId as string;
  const { error } = await adminEngine.resolveReport(req.auth!.userId, reportId, action);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ success: true });
});

const removeSchema = z.object({ target_type: z.enum(["review", "swap_request"]), target_id: z.string().uuid(), reason: z.string().default("") });

router.post("/content/remove", requireAdmin, validate(removeSchema), async (req: Request, res: Response) => {
  const { target_type, target_id, reason } = req.body;
  const { error } = await adminEngine.removeContent(req.auth!.userId, target_type, target_id, reason);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json({ success: true });
});

router.get("/logs", requireAdmin, validate(paginateSchema, "query"), async (req: Request, res: Response) => {
  const { page, limit } = req.query as unknown as { page: number; limit: number };
  const { data, error } = await adminEngine.getLogs(req.auth!.userId, page, limit);
  if (error) { res.status(500).json({ error: error.message }); return; }
  res.json(data);
});

export default router;
