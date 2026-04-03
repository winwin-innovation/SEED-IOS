import "dotenv/config";
import express from "express";
import crypto from "node:crypto";
import { createDecartClient } from "@decartai/sdk";

const app = express();
const port = Number(process.env.PORT || 8787);
const host = process.env.HOST || "0.0.0.0";
const roomTtlMs = 1000 * 60 * 60 * 6;
const callRooms = new Map();

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
  pruneExpiredRooms();
  res.json({
    ok: true,
    activeRooms: callRooms.size,
  });
});

app.get("/api/call-rooms", (_req, res) => {
  pruneExpiredRooms();

  const rooms = Array.from(callRooms.values()).map((room) => serializeRoom(room));
  return res.json({ rooms });
});

app.post("/api/call-rooms", (req, res) => {
  pruneExpiredRooms();

  const roomName = normalizeRoomName(req.body?.name);
  const hostName = normalizeParticipantName(req.body?.hostName) || "Host";

  const roomId = createId("room");
  const hostId = createId("participant");
  const now = Date.now();
  const room = {
    id: roomId,
    name: roomName || `SEED Room ${roomId.slice(-4).toUpperCase()}`,
    createdAt: now,
    updatedAt: now,
    expiresAt: now + roomTtlMs,
    participants: [
      {
        id: hostId,
        name: hostName,
        role: "host",
        joinedAt: now,
        lastSeenAt: now,
      },
    ],
    signals: [],
    nextSignalSequence: 1,
  };

  callRooms.set(roomId, room);

  return res.status(201).json({
    room: serializeRoom(room),
    participant: serializeParticipant(room.participants[0]),
  });
});

app.get("/api/call-rooms/:roomId", (req, res) => {
  pruneExpiredRooms();

  const room = callRooms.get(req.params.roomId);
  if (!room) {
    return res.status(404).json({ error: "Call room not found." });
  }

  touchRoom(room);
  return res.json({ room: serializeRoom(room) });
});

app.post("/api/call-rooms/:roomId/participants", (req, res) => {
  pruneExpiredRooms();

  const room = callRooms.get(req.params.roomId);
  if (!room) {
    return res.status(404).json({ error: "Call room not found." });
  }

  const participantName = normalizeParticipantName(req.body?.name) || "Guest";
  const participant = {
    id: createId("participant"),
    name: participantName,
    role: "guest",
    joinedAt: Date.now(),
    lastSeenAt: Date.now(),
  };

  room.participants.push(participant);
  touchRoom(room);

  return res.status(201).json({
    room: serializeRoom(room),
    participant: serializeParticipant(participant),
  });
});

app.post("/api/call-rooms/:roomId/participants/:participantId/heartbeat", (req, res) => {
  pruneExpiredRooms();

  const room = callRooms.get(req.params.roomId);
  if (!room) {
    return res.status(404).json({ error: "Call room not found." });
  }

  const participant = room.participants.find(
    (entry) => entry.id === req.params.participantId,
  );

  if (!participant) {
    return res.status(404).json({ error: "Participant not found." });
  }

  participant.lastSeenAt = Date.now();
  touchRoom(room);

  return res.json({
    ok: true,
    participant: serializeParticipant(participant),
  });
});

app.delete("/api/call-rooms/:roomId/participants/:participantId", (req, res) => {
  pruneExpiredRooms();

  const room = callRooms.get(req.params.roomId);
  if (!room) {
    return res.status(404).json({ error: "Call room not found." });
  }

  room.participants = room.participants.filter(
    (entry) => entry.id !== req.params.participantId,
  );
  room.signals = room.signals.filter(
    (signal) =>
      signal.fromParticipantId !== req.params.participantId &&
      signal.toParticipantId !== req.params.participantId,
  );

  if (room.participants.length === 0) {
    callRooms.delete(room.id);
    return res.status(204).send();
  }

  touchRoom(room);
  return res.status(204).send();
});

app.post("/api/call-rooms/:roomId/signals", (req, res) => {
  pruneExpiredRooms();

  const room = callRooms.get(req.params.roomId);
  if (!room) {
    return res.status(404).json({ error: "Call room not found." });
  }

  const fromParticipantId = req.body?.fromParticipantId;
  const toParticipantId = req.body?.toParticipantId ?? null;
  const type = normalizeSignalType(req.body?.type);
  const payload = req.body?.payload;

  if (!fromParticipantId || !type) {
    return res.status(400).json({
      error: "fromParticipantId and type are required.",
    });
  }

  if (!room.participants.some((entry) => entry.id === fromParticipantId)) {
    return res.status(404).json({ error: "Sender participant not found." });
  }

  if (
    toParticipantId &&
    !room.participants.some((entry) => entry.id === toParticipantId)
  ) {
    return res.status(404).json({ error: "Target participant not found." });
  }

  const signal = {
    id: createId("signal"),
    sequence: room.nextSignalSequence++,
    type,
    payload: payload ?? {},
    fromParticipantId,
    toParticipantId,
    createdAt: Date.now(),
  };

  room.signals.push(signal);
  room.signals = room.signals.slice(-500);
  touchRoom(room);

  return res.status(201).json({ signal });
});

app.get("/api/call-rooms/:roomId/signals", (req, res) => {
  pruneExpiredRooms();

  const room = callRooms.get(req.params.roomId);
  if (!room) {
    return res.status(404).json({ error: "Call room not found." });
  }

  const participantId = req.query.participantId;
  const after = Number(req.query.after || 0);
  const signals = room.signals.filter((signal) => {
    if (signal.sequence <= after) {
      return false;
    }

    if (!participantId) {
      return true;
    }

    return (
      signal.fromParticipantId === participantId ||
      signal.toParticipantId === null ||
      signal.toParticipantId === participantId
    );
  });

  touchRoom(room);
  return res.json({
    roomId: room.id,
    signals,
    latestSequence: room.nextSignalSequence - 1,
  });
});

app.listen(port, host, () => {
  console.log(`Secure token server running on http://${host}:${port}`);
});

function serializeRoom(room) {
  return {
    id: room.id,
    name: room.name,
    createdAt: room.createdAt,
    updatedAt: room.updatedAt,
    expiresAt: room.expiresAt,
    participants: room.participants.map((entry) => serializeParticipant(entry)),
    signalCount: room.signals.length,
  };
}

function serializeParticipant(participant) {
  return {
    id: participant.id,
    name: participant.name,
    role: participant.role,
    joinedAt: participant.joinedAt,
    lastSeenAt: participant.lastSeenAt,
  };
}

function touchRoom(room) {
  room.updatedAt = Date.now();
  room.expiresAt = room.updatedAt + roomTtlMs;
}

function pruneExpiredRooms() {
  const now = Date.now();
  for (const [roomId, room] of callRooms.entries()) {
    if (room.expiresAt < now) {
      callRooms.delete(roomId);
    }
  }
}

function createId(prefix) {
  return `${prefix}_${crypto.randomBytes(4).toString("hex")}`;
}

function normalizeRoomName(value) {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim().slice(0, 60);
}

function normalizeParticipantName(value) {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim().slice(0, 40);
}

function normalizeSignalType(value) {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim().slice(0, 40);
}
