import { Router, Request, Response } from "express";
import { z } from "zod";
import { requireAuth, validate } from "../middleware";
import { getUserClient } from "../config";
import { engine } from "../engine";
import { paginationParams, paginateSchema } from "../types";

const router = Router();

const createReviewSchema = z.object({
  session_id: z.string().uuid(),
  reviewee_id: z.string().uuid(),
  rating: z.number().int().min(1).max(5),
  comment: z.string().max(1000).default(""),
});

router.post("/", requireAuth, validate(createReviewSchema), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);

  const { data: existing } = await client
    .from("reviews")
    .select("id")
    .eq("session_id", req.body.session_id)
    .eq("reviewer_id", req.auth!.userId)
    .maybeSingle();
  if (existing) { res.status(409).json({ error: "You have already reviewed this session" }); return; }

  const { data, error } = await client
    .from("reviews")
    .insert({
      session_id: req.body.session_id,
      reviewer_id: req.auth!.userId,
      reviewee_id: req.body.reviewee_id,
      rating: req.body.rating,
      comment: req.body.comment,
    })
    .select()
    .single();
  if (error) { res.status(400).json({ error: error.message }); return; }

  await engine.createNotification({
    user_id: req.body.reviewee_id,
    type: "review_received",
    title: `You received a ${req.body.rating}-star review!`,
    body: req.body.comment ? req.body.comment : undefined,
    data: { review_id: data.id, session_id: req.body.session_id, rating: req.body.rating },
  });

  res.status(201).json(data);
});

router.get("/user/:userId", requireAuth, validate(paginateSchema, "query"), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);
  const { page, limit } = paginationParams(Number(req.query.page), Number(req.query.limit));
  const offset = (page - 1) * limit;

  const { data, error, count } = await client
    .from("reviews")
    .select("*, reviewer:reviewer_id(*)", { count: "exact" })
    .eq("reviewee_id", req.params.userId)
    .range(offset, offset + limit - 1)
    .order("created_at", { ascending: false });
  if (error) { res.status(400).json({ error: error.message }); return; }

  const { count: totalReviews } = await client
    .from("reviews")
    .select("*", { count: "exact", head: true })
    .eq("reviewee_id", req.params.userId);
  const avgResult = await client
    .rpc("get_average_rating", { target_user_id: req.params.userId })
    .single();
  const avgRating = avgResult.data ? (avgResult.data as { average_rating: number }).average_rating : null;

  res.json({
    data,
    count,
    page,
    limit,
    average_rating: avgRating,
    total_reviews: totalReviews,
  });
});

const updateReviewSchema = z.object({
  comment: z.string().max(1000),
});

router.put("/:id", requireAuth, validate(updateReviewSchema), async (req: Request, res: Response) => {
  const client = getUserClient(req.auth!.userToken);

  const { data: existing, error: fetchErr } = await client
    .from("reviews")
    .select("id, reviewer_id")
    .eq("id", req.params.id)
    .single();
  if (fetchErr || !existing) { res.status(404).json({ error: "Review not found" }); return; }
  if (existing.reviewer_id !== req.auth!.userId) { res.status(403).json({ error: "Cannot edit another user's review" }); return; }

  const { data, error } = await client
    .from("reviews")
    .update({ comment: req.body.comment })
    .eq("id", req.params.id)
    .select()
    .single();
  if (error) { res.status(400).json({ error: error.message }); return; }

  res.json(data);
});

export default router;
