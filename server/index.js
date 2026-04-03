import "dotenv/config";
import express from "express";
import { createDecartClient } from "@decartai/sdk";

const app = express();
const port = Number(process.env.PORT || 8787);
const host = process.env.HOST || "0.0.0.0";

app.use(express.json());

app.post("/api/realtime-token", async (_req, res) => {
  if (!process.env.DECART_API_KEY) {
    return res.status(500).json({
      error: "DECART_API_KEY is missing on the server.",
    });
  }

  try {
    const client = createDecartClient({
      apiKey: process.env.DECART_API_KEY,
    });

    const token = await client.tokens.create({
      expiresIn: 60,
      allowedModels: ["lucy_2_rt"],
    });

    return res.json(token);
  } catch (error) {
    console.error("Failed to mint realtime token:", error);
    return res.status(500).json({
      error: "Failed to create realtime token.",
    });
  }
});

app.get("/api/health", (_req, res) => {
  res.json({ ok: true });
});

app.listen(port, host, () => {
  console.log(`Secure token server running on http://${host}:${port}`);
});
