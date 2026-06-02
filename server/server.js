// ─────────────────────────────────────────────────────────────────────────────
// Valkyrious Revive — Multiplayer Relay Server
//
// Responsibilities:
//   • Room management  (create / join by code)
//   • Random matchmaking queue
//   • Action relay between the two players in a room
//   • Disconnect notification
//
// Start:  node server.js          (default port 8765)
//         PORT=9000 node server.js (custom port)
//
// Protocol — all messages are JSON objects.
//
// Client → Server:
//   { type: "create_room" }
//   { type: "join_room",   code: "ABCD" }
//   { type: "join_random" }
//   { type: "action",      action: { type:"deploy", card_id, row, col } }
//   { type: "game_over",   winner: "owner" | "enemy" | "draw" }
//   { type: "ping" }
//
// Server → Client:
//   { type: "room_created",          code: "ABCD" }
//   { type: "waiting" }              ← waiting in random queue
//   { type: "match_found",           role: "owner"|"enemy", seed: <int> }
//   { type: "opponent_action",       action: { ... } }
//   { type: "game_over",             winner: "owner"|"enemy"|"draw" }
//   { type: "opponent_disconnected" }
//   { type: "error",                 message: "..." }
//   { type: "pong" }
// ─────────────────────────────────────────────────────────────────────────────

"use strict";

const { WebSocketServer, WebSocket } = require("ws");

const PORT = parseInt(process.env.PORT || "8765", 10);
const wss  = new WebSocketServer({ port: PORT });

// ── State ─────────────────────────────────────────────────────────────────────

/** @type {Map<string, { code:string, players:WebSocket[], state:'waiting'|'playing' }>} */
const rooms       = new Map();   // code → room

/** @type {WebSocket[]} */
const randomQueue = [];          // players waiting for a random opponent

/** @type {Map<WebSocket, string>} */
const playerRoom  = new Map();   // ws → room code

// ── Helpers ───────────────────────────────────────────────────────────────────

function genCode() {
  let code;
  do {
    code = Math.random().toString(36).substring(2, 6).toUpperCase();
  } while (rooms.has(code));
  return code;
}

/** @param {WebSocket} ws @param {object} obj */
function send(ws, obj) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(obj));
  }
}

// ── Room actions ──────────────────────────────────────────────────────────────

function createRoom(ws) {
  if (playerRoom.has(ws)) {
    send(ws, { type: "error", message: "Already in a room" });
    return;
  }
  const code = genCode();
  const room = { code, players: [ws], state: "waiting" };
  rooms.set(code, room);
  playerRoom.set(ws, code);
  send(ws, { type: "room_created", code });
  console.log(`[Room] Created ${code}`);
}

function joinRoom(ws, code) {
  if (playerRoom.has(ws)) {
    send(ws, { type: "error", message: "Already in a room" });
    return;
  }
  const room = rooms.get(code);
  if (!room) {
    send(ws, { type: "error", message: "Room not found" });
    return;
  }
  if (room.players.length >= 2) {
    send(ws, { type: "error", message: "Room is full" });
    return;
  }
  room.players.push(ws);
  playerRoom.set(ws, code);
  startMatch(room);
}

function joinRandom(ws) {
  if (playerRoom.has(ws)) {
    send(ws, { type: "error", message: "Already in a room" });
    return;
  }

  // Find first alive player in queue
  while (randomQueue.length > 0) {
    const candidate = randomQueue[0];
    if (candidate.readyState === WebSocket.OPEN) break;
    randomQueue.shift();  // remove disconnected candidate
  }

  if (randomQueue.length > 0) {
    const opponent = randomQueue.shift();
    const code     = genCode();
    const room     = { code, players: [opponent, ws], state: "waiting" };
    rooms.set(code, room);
    playerRoom.set(opponent, code);
    playerRoom.set(ws, code);
    console.log(`[Matchmaking] Paired in room ${code}`);
    startMatch(room);
  } else {
    randomQueue.push(ws);
    send(ws, { type: "waiting" });
    console.log(`[Matchmaking] Player queued (queue size: ${randomQueue.length})`);
  }
}

// ── Match ─────────────────────────────────────────────────────────────────────

function startMatch(room) {
  room.state    = "playing";
  const [p0, p1] = room.players;
  const seed    = Math.floor(Math.random() * 2_147_483_647);
  send(p0, { type: "match_found", role: "owner", seed });
  send(p1, { type: "match_found", role: "enemy", seed });
  console.log(`[Room ${room.code}] Match started — seed ${seed}`);
}

// ── Relay ─────────────────────────────────────────────────────────────────────

function relayAction(ws, action) {
  const code = playerRoom.get(ws);
  if (!code) return;
  const room = rooms.get(code);
  if (!room) return;
  const opp = room.players.find(p => p !== ws);
  if (opp) {
    console.log(`[Room ${code}] Relaying action:`, JSON.stringify(action));
    send(opp, { type: "opponent_action", action });
  } else {
    console.log(`[Room ${code}] No opponent to relay to!`);
  }
}

function relayProfile(ws, msg) {
  const code = playerRoom.get(ws);
  if (!code) return;
  const room = rooms.get(code);
  if (!room) return;
  const opp = room.players.find(p => p !== ws);
  if (opp) send(opp, { type: "profile", player_name: msg.player_name || "", profile_icon: msg.profile_icon || "" });
}

function relayGameOver(ws, winner) {
  const code = playerRoom.get(ws);
  if (!code) return;
  const room = rooms.get(code);
  if (!room) return;
  const opp = room.players.find(p => p !== ws);
  if (opp) send(opp, { type: "game_over", winner });
  console.log(`[Room ${code}] Game over — winner: ${winner}`);
  // Clean up after a short delay so both clients receive the message
  setTimeout(() => cleanRoom(code), 10_000);
}

// ── Disconnect ────────────────────────────────────────────────────────────────

function handleDisconnect(ws) {
  // Remove from random queue if present
  const qi = randomQueue.indexOf(ws);
  if (qi !== -1) randomQueue.splice(qi, 1);

  const code = playerRoom.get(ws);
  playerRoom.delete(ws);
  if (!code) return;

  const room = rooms.get(code);
  if (!room) return;

  const opp = room.players.find(p => p !== ws);
  if (opp && opp.readyState === WebSocket.OPEN) {
    send(opp, { type: "opponent_disconnected" });
  }
  cleanRoom(code);
  console.log(`[Room ${code}] Player disconnected — room closed`);
}

function cleanRoom(code) {
  const room = rooms.get(code);
  if (!room) return;
  room.players.forEach(p => playerRoom.delete(p));
  rooms.delete(code);
}

// ── WebSocket server ──────────────────────────────────────────────────────────

wss.on("connection", (ws) => {
  console.log(`[Server] Client connected (total: ${wss.clients.size})`);

  ws.on("message", (data) => {
    let msg;
    try { msg = JSON.parse(data); } catch { return; }

    switch (msg.type) {
      case "create_room":  createRoom(ws); break;
      case "join_room":    joinRoom(ws, String(msg.code || "").toUpperCase()); break;
      case "join_random":  joinRandom(ws); break;
      case "action":       relayAction(ws, msg.action || {}); break;
      case "profile":      relayProfile(ws, msg); break;
      case "game_over":    relayGameOver(ws, msg.winner || "draw"); break;
      case "ping":         send(ws, { type: "pong" }); break;
      default: break;
    }
  });

  ws.on("close", () => {
    console.log(`[Server] Client disconnected (total: ${wss.clients.size})`);
    handleDisconnect(ws);
  });

  ws.on("error", (err) => {
    console.error(`[Server] WS error: ${err.message}`);
    handleDisconnect(ws);
  });
});

console.log(`[Server] Valkyrious relay listening on ws://0.0.0.0:${PORT}`);
