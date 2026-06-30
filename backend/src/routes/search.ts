import { Router, Request, Response } from "express";
import { z } from "zod";
import { optionalAuth, validate } from "../middleware";
import { getServiceClient } from "../config";
import { paginationParams } from "../types";

const router = Router();

const searchQuerySchema = z.object({
  q: z.string().optional().default(""),
  type: z.enum(["users", "skills", "all"]).optional().default("users"),
  location: z.string().optional(),
  college: z.string().optional(),
  proficiency: z.enum(["beginner", "intermediate", "advanced", "expert"]).optional(),
  availability: z.enum(["available", "limited", "unavailable"]).optional(),
  category_id: z.string().uuid().optional(),
  sort: z.enum(["relevance", "newest", "xp", "rating", "name", "popularity"]).optional().default("relevance"),
  page: z.coerce.number().int().min(1).optional().default(1),
  limit: z.coerce.number().int().min(1).max(100).optional().default(20),
});

router.get("/", optionalAuth, validate(searchQuerySchema), async (req: Request, res: Response) => {
  const { q, type, location, college, proficiency, availability, category_id, sort, page, limit } = req.query as unknown as z.infer<typeof searchQuerySchema>;

  if (type === "users" || type === "all") {
    const sortBy = sort === "relevance" || sort === "newest" || sort === "xp" || sort === "rating" ? sort : "relevance";

    const { data: usersData, error: usersError } = await getServiceClient().rpc("search_users_profiles", {
      p_search_text: q,
      p_location: location ?? null,
      p_availability: availability ?? null,
      p_college: college ?? null,
      p_sort_by: sortBy,
      p_page: page,
      p_limit: limit,
    });

    if (usersError) { res.status(400).json({ error: usersError.message }); return; }

    let users = usersData as Record<string, unknown> | null;

    if (proficiency && users && typeof users === "object" && "data" in users && Array.isArray(users.data)) {
      const filtered = users.data.filter((u: Record<string, unknown>) =>
        Array.isArray(u.teaching_skills) &&
        u.teaching_skills.some((ts: Record<string, unknown>) => ts.proficiency === proficiency)
      );
      users = { ...users, data: filtered, total: filtered.length };
    }

    if (type === "users") {
      res.json(users ?? { total: 0, page, limit, data: [] });
      return;
    }

    const { data: skillsData, error: skillsError } = await getServiceClient().rpc("search_skills", {
      p_search_text: q,
      p_category_id: category_id ?? null,
      p_page: page,
      p_limit: limit,
    });

    if (skillsError) { res.status(400).json({ error: skillsError.message }); return; }

    res.json({
      users: users ?? { total: 0, page, limit, data: [] },
      skills: skillsData ?? { total: 0, page, limit, data: [] },
    });
    return;
  }

  const { data, error } = await getServiceClient().rpc("search_skills", {
    p_search_text: q,
    p_category_id: category_id ?? null,
    p_page: page,
    p_limit: limit,
  });

  if (error) { res.status(400).json({ error: error.message }); return; }

  res.json(data ?? { total: 0, page, limit, data: [] });
});

export const searchHandlers = { searchQuerySchema };
export default router;
