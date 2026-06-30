import { Request, Response, NextFunction } from "express";
import { ZodSchema, ZodError } from "zod";
import { getUserClient } from "./config";

export interface AuthPayload {
  userId: string;
  userToken: string;
}

declare global {
  namespace Express {
    interface Request {
      auth?: AuthPayload;
    }
  }
}

export async function requireAuth(req: Request, res: Response, next: NextFunction): Promise<void> {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    res.status(401).json({ error: "Missing or invalid Authorization header" });
    return;
  }
  const token = header.slice(7);

  try {
    const client = getUserClient(token);
    const { data, error } = await client.auth.getUser(token);
    if (error || !data.user) {
      res.status(401).json({ error: "Invalid or expired token" });
      return;
    }
    req.auth = { userId: data.user.id, userToken: token };
    next();
  } catch {
    res.status(401).json({ error: "Token verification failed" });
  }
}

export function optionalAuth(req: Request, _res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (header?.startsWith("Bearer ")) {
    const token = header.slice(7);
    getUserClient(token)
      .auth.getUser(token)
      .then(({ data }) => {
        if (data.user) {
          req.auth = { userId: data.user.id, userToken: token };
        }
        next();
      })
      .catch(() => next());
  } else {
    next();
  }
}

export function validate(schema: ZodSchema, source: "body" | "query" | "params" = "body") {
  return (req: Request, res: Response, next: NextFunction): void => {
    try {
      req[source] = schema.parse(req[source]);
      next();
    } catch (err) {
      if (err instanceof ZodError) {
        res.status(400).json({
          error: "Validation failed",
          details: err.errors.map((e) => ({
            path: e.path.join("."),
            message: e.message,
          })),
        });
        return;
      }
      next(err);
    }
  };
}

export function errorHandler(err: Error, _req: Request, res: Response, _next: NextFunction): void {
  console.error("[Error]", err);
  res.status(500).json({ error: "Internal server error" });
}
