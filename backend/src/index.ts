import express from "express";
import cors from "cors";
import { getPort } from "./config";
import { errorHandler } from "./middleware";

import profilesRouter from "./routes/profiles";
import skillsRouter from "./routes/skills";
import swapRequestsRouter from "./routes/swapRequests";
import swapSessionsRouter from "./routes/swapSessions";
import messagesRouter from "./routes/messages";
import notificationsRouter from "./routes/notifications";
import reviewsRouter from "./routes/reviews";
import bookmarksRouter from "./routes/bookmarks";
import realtimeRouter from "./routes/realtime";
import searchRouter from "./routes/search";
import adminRouter from "./routes/admin";

const app = express();

app.use(cors());
app.use(express.json());

app.get("/health", (_req, res) => res.json({ status: "ok" }));

app.use("/api/profiles", profilesRouter);
app.use("/api/skills", skillsRouter);
app.use("/api/swap-requests", swapRequestsRouter);
app.use("/api/swap-sessions", swapSessionsRouter);
app.use("/api/messages", messagesRouter);
app.use("/api/notifications", notificationsRouter);
app.use("/api/reviews", reviewsRouter);
app.use("/api/bookmarks", bookmarksRouter);
app.use("/api/realtime", realtimeRouter);
app.use("/api/search", searchRouter);
app.use("/api/admin", adminRouter);

app.use(errorHandler);

const port = getPort();
app.listen(port, () => console.log(`SWAP API running on port ${port}`));

export default app;
