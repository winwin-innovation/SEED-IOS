import { createDecartClient, models } from "@decartai/sdk";
import "./style.css";

const MODEL_NAME = "lucy_2_rt";
const heartbeatIntervalMs = 30000;
const signalPollIntervalMs = 4000;

const timerEl = document.getElementById("timer");
const stopSessionBtn = document.getElementById("stop-session");
const statusChip = document.getElementById("status-chip");
const sourceVideo = document.getElementById("source-video");
const characterImage = document.getElementById("character-image");
const resultLoading = document.getElementById("result-loading");
const fullscreenBtn = document.getElementById("fullscreen-btn");
const promptInput = document.getElementById("prompt-input");
const uploadBtn = document.getElementById("upload-btn");
const imageInput = document.getElementById("image-input");
const sendBtn = document.getElementById("send-btn");
const uploadedLabel = document.getElementById("uploaded-label");
const toast = document.getElementById("toast");
const remainingCreditsElem = document.getElementById("remaining-credits");

const roomNameInput = document.getElementById("room-name-input");
const hostNameInput = document.getElementById("host-name-input");
const guestNameInput = document.getElementById("guest-name-input");
const createRoomBtn = document.getElementById("create-room-btn");
const refreshRoomsBtn = document.getElementById("refresh-rooms-btn");
const roomsList = document.getElementById("rooms-list");
const roomCountBadge = document.getElementById("room-count-badge");
const activeRoomBadge = document.getElementById("active-room-badge");
const activeRoomSummary = document.getElementById("active-room-summary");
const joinRoomBtn = document.getElementById("join-room-btn");
const leaveRoomBtn = document.getElementById("leave-room-btn");
const signalTypeInput = document.getElementById("signal-type-input");
const signalTargetInput = document.getElementById("signal-target-input");
const signalPayloadInput = document.getElementById("signal-payload-input");
const sendSignalBtn = document.getElementById("send-signal-btn");
const pollSignalsBtn = document.getElementById("poll-signals-btn");
const signalsLog = document.getElementById("signals-log");
const pollingBadge = document.getElementById("polling-badge");
const signalSequenceBadge = document.getElementById("signal-sequence-badge");

let remainingSeconds = 3600;
let timerId = null;
let sessionActive = true;
let lastUploadedFile = null;
let localStream = null;
let realtimeClient = null;
let totalGenerationSeconds = 0;

const roomState = {
  rooms: [],
  selectedRoomId: "",
  activeRoom: null,
  participant: null,
  latestSequence: 0,
  heartbeatId: null,
  pollId: null,
};

async function getClientToken() {
  const response = await fetch("/api/realtime-token", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
  });

  if (!response.ok) {
    const fallbackMessage = "Could not get a secure client token.";
    let message = fallbackMessage;

    try {
      const body = await response.json();
      message = body?.error || fallbackMessage;
    } catch {
      // Keep fallback message if body cannot be parsed.
    }

    throw new Error(message);
  }

  const token = await response.json();

  if (!token?.apiKey) {
    throw new Error("Token response is missing apiKey.");
  }

  return token.apiKey;
}

function formatClock(seconds) {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${String(mins).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
}

function setStatus(text) {
  statusChip.textContent = text;
}

function showToast(message) {
  toast.textContent = message;
  toast.classList.remove("hidden");
  window.clearTimeout(showToast._timeout);
  showToast._timeout = window.setTimeout(() => {
    toast.classList.add("hidden");
  }, 2200);
}

function updateGenerationStats(seconds) {
  totalGenerationSeconds = seconds;
  remainingCreditsElem.textContent = `${seconds}s used`;
}

async function apiFetch(path, options = {}) {
  const response = await fetch(path, {
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
    ...options,
  });

  if (!response.ok) {
    let message = `Request failed with ${response.status}`;
    try {
      const body = await response.json();
      message = body?.error || message;
    } catch {
      // Ignore non-JSON error bodies.
    }
    throw new Error(message);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json();
}

function formatDateTime(value) {
  if (!value) {
    return "Unknown";
  }

  return new Date(value).toLocaleString();
}

function updateDebuggerControls() {
  const hasSelectedRoom = Boolean(roomState.selectedRoomId);
  const hasParticipant = Boolean(roomState.participant?.id && roomState.activeRoom?.id);

  joinRoomBtn.disabled = !hasSelectedRoom || hasParticipant;
  leaveRoomBtn.disabled = !hasParticipant;
  sendSignalBtn.disabled = !hasParticipant;
  pollSignalsBtn.disabled = !hasParticipant;

  if (hasParticipant) {
    activeRoomBadge.textContent = `${roomState.activeRoom.name} / ${roomState.participant.name}`;
    activeRoomBadge.className = "badge live";
    pollingBadge.textContent = roomState.pollId ? "Polling every 4s" : "Connected";
    pollingBadge.className = roomState.pollId ? "badge live" : "badge";
  } else {
    activeRoomBadge.textContent = roomState.selectedRoomId ? "Room selected" : "Not connected";
    activeRoomBadge.className = roomState.selectedRoomId ? "badge" : "badge muted";
    pollingBadge.textContent = "Idle";
    pollingBadge.className = "badge muted";
  }
}

function renderRoomSummary() {
  if (!roomState.activeRoom) {
    const selectedRoom = roomState.rooms.find((room) => room.id === roomState.selectedRoomId);
    if (!selectedRoom) {
      activeRoomSummary.innerHTML = "<p>Pick a room and join it as a participant to start sending test signals.</p>";
      return;
    }

    activeRoomSummary.innerHTML = `
      <p><strong>${selectedRoom.name}</strong></p>
      <p>${selectedRoom.participants.length} participant(s) connected.</p>
      <p>Choose a guest name, then join the room to post offers, answers, or ICE messages.</p>
    `;
    return;
  }

  const participantsMarkup = roomState.activeRoom.participants
    .map((participant) => {
      const current = participant.id === roomState.participant?.id ? " (you)" : "";
      return `<li><code>${participant.id}</code> ${participant.name}${current}</li>`;
    })
    .join("");

  activeRoomSummary.innerHTML = `
    <p><strong>${roomState.activeRoom.name}</strong></p>
    <p>Room ID: <code>${roomState.activeRoom.id}</code></p>
    <p>Updated: ${formatDateTime(roomState.activeRoom.updatedAt)}</p>
    <ul class="summary-list">${participantsMarkup}</ul>
  `;
}

function renderRooms() {
  roomCountBadge.textContent = `${roomState.rooms.length} room${roomState.rooms.length === 1 ? "" : "s"}`;

  if (roomState.rooms.length === 0) {
    roomsList.innerHTML = '<p class="empty-copy">No rooms yet. Create one to start testing signaling.</p>';
    updateDebuggerControls();
    renderRoomSummary();
    return;
  }

  roomsList.innerHTML = roomState.rooms
    .map((room) => {
      const isSelected = room.id === roomState.selectedRoomId;
      return `
        <button class="room-item${isSelected ? " selected" : ""}" data-room-id="${room.id}" type="button">
          <span class="room-item-name">${room.name}</span>
          <span class="room-item-meta">${room.participants.length} participant(s) · ${room.signalCount} signal(s)</span>
        </button>
      `;
    })
    .join("");

  renderRoomSummary();
  updateDebuggerControls();
}

function appendSignalLogEntry(signal) {
  const entry = document.createElement("article");
  entry.className = "signal-entry";
  const payloadText = JSON.stringify(signal.payload ?? {}, null, 2);
  entry.innerHTML = `
    <div class="signal-entry-head">
      <strong>${signal.type}</strong>
      <span>Seq ${signal.sequence}</span>
    </div>
    <p>From <code>${signal.fromParticipantId}</code>${signal.toParticipantId ? ` to <code>${signal.toParticipantId}</code>` : " to everyone"}</p>
    <pre>${payloadText}</pre>
  `;

  const empty = signalsLog.querySelector(".empty-copy");
  if (empty) {
    empty.remove();
  }

  signalsLog.prepend(entry);
}

function clearSignalFeed() {
  signalsLog.innerHTML = '<p class="empty-copy">Signals will appear here once a room is active.</p>';
  roomState.latestSequence = 0;
  signalSequenceBadge.textContent = "Seq 0";
}

async function refreshRooms({ silent = false } = {}) {
  try {
    const data = await apiFetch("/api/call-rooms");
    roomState.rooms = data.rooms || [];

    if (
      roomState.selectedRoomId &&
      !roomState.rooms.some((room) => room.id === roomState.selectedRoomId)
    ) {
      roomState.selectedRoomId = "";
    }

    if (roomState.activeRoom?.id) {
      const activeMatch = roomState.rooms.find((room) => room.id === roomState.activeRoom.id);
      roomState.activeRoom = activeMatch || null;
    }

    renderRooms();
    if (!silent) {
      showToast("Room list refreshed");
    }
  } catch (error) {
    console.error("Failed to refresh rooms:", error);
    showToast(`Room refresh failed: ${error.message}`);
  }
}

async function createRoom() {
  try {
    createRoomBtn.disabled = true;
    const data = await apiFetch("/api/call-rooms", {
      method: "POST",
      body: JSON.stringify({
        name: roomNameInput.value.trim(),
        hostName: hostNameInput.value.trim(),
      }),
    });

    roomState.selectedRoomId = data.room.id;
    roomState.activeRoom = data.room;
    roomState.participant = data.participant;
    roomState.latestSequence = 0;

    await refreshRooms({ silent: true });
    startHeartbeat();
    startSignalPolling();
    clearSignalFeed();
    renderRoomSummary();
    updateDebuggerControls();
    showToast(`Room ${data.room.name} created`);
  } catch (error) {
    console.error("Failed to create room:", error);
    showToast(`Create room failed: ${error.message}`);
  } finally {
    createRoomBtn.disabled = false;
  }
}

async function joinSelectedRoom() {
  if (!roomState.selectedRoomId) {
    showToast("Select a room first");
    return;
  }

  try {
    joinRoomBtn.disabled = true;
    const data = await apiFetch(`/api/call-rooms/${roomState.selectedRoomId}/participants`, {
      method: "POST",
      body: JSON.stringify({
        name: guestNameInput.value.trim(),
      }),
    });

    roomState.activeRoom = data.room;
    roomState.participant = data.participant;
    roomState.latestSequence = 0;

    clearSignalFeed();
    await refreshRooms({ silent: true });
    startHeartbeat();
    startSignalPolling();
    renderRoomSummary();
    updateDebuggerControls();
    showToast(`Joined ${data.room.name} as ${data.participant.name}`);
  } catch (error) {
    console.error("Failed to join room:", error);
    showToast(`Join failed: ${error.message}`);
  } finally {
    joinRoomBtn.disabled = false;
  }
}

async function leaveActiveRoom() {
  if (!roomState.activeRoom?.id || !roomState.participant?.id) {
    return;
  }

  const roomId = roomState.activeRoom.id;
  const participantId = roomState.participant.id;

  try {
    await apiFetch(`/api/call-rooms/${roomId}/participants/${participantId}`, {
      method: "DELETE",
    });
  } catch (error) {
    console.error("Failed to leave room:", error);
    showToast(`Leave failed: ${error.message}`);
  } finally {
    stopHeartbeat();
    stopSignalPolling();
    roomState.activeRoom = null;
    roomState.participant = null;
    clearSignalFeed();
    await refreshRooms({ silent: true });
    renderRoomSummary();
    updateDebuggerControls();
  }
}

function startHeartbeat() {
  stopHeartbeat();

  if (!roomState.activeRoom?.id || !roomState.participant?.id) {
    return;
  }

  roomState.heartbeatId = window.setInterval(async () => {
    try {
      await apiFetch(
        `/api/call-rooms/${roomState.activeRoom.id}/participants/${roomState.participant.id}/heartbeat`,
        {
          method: "POST",
        },
      );
    } catch (error) {
      console.error("Heartbeat failed:", error);
    }
  }, heartbeatIntervalMs);
}

function stopHeartbeat() {
  if (roomState.heartbeatId) {
    window.clearInterval(roomState.heartbeatId);
    roomState.heartbeatId = null;
  }
}

async function pollSignals({ silent = false } = {}) {
  if (!roomState.activeRoom?.id || !roomState.participant?.id) {
    return;
  }

  try {
    const params = new URLSearchParams({
      participantId: roomState.participant.id,
      after: String(roomState.latestSequence),
    });
    const data = await apiFetch(`/api/call-rooms/${roomState.activeRoom.id}/signals?${params.toString()}`);

    roomState.latestSequence = data.latestSequence ?? roomState.latestSequence;
    signalSequenceBadge.textContent = `Seq ${roomState.latestSequence}`;

    if (Array.isArray(data.signals) && data.signals.length > 0) {
      data.signals
        .slice()
        .reverse()
        .forEach((signal) => appendSignalLogEntry(signal));
      if (!silent) {
        showToast(`Received ${data.signals.length} signal${data.signals.length === 1 ? "" : "s"}`);
      }
    } else if (!silent) {
      showToast("No new signals");
    }

    await refreshRooms({ silent: true });
  } catch (error) {
    console.error("Signal poll failed:", error);
    showToast(`Signal poll failed: ${error.message}`);
  }
}

function startSignalPolling() {
  stopSignalPolling();

  if (!roomState.activeRoom?.id || !roomState.participant?.id) {
    return;
  }

  roomState.pollId = window.setInterval(() => {
    pollSignals({ silent: true });
  }, signalPollIntervalMs);

  updateDebuggerControls();
}

function stopSignalPolling() {
  if (roomState.pollId) {
    window.clearInterval(roomState.pollId);
    roomState.pollId = null;
  }
  updateDebuggerControls();
}

async function sendSignal() {
  if (!roomState.activeRoom?.id || !roomState.participant?.id) {
    showToast("Join a room before sending signals");
    return;
  }

  let payload = {};
  const rawPayload = signalPayloadInput.value.trim();

  if (rawPayload) {
    try {
      payload = JSON.parse(rawPayload);
    } catch {
      showToast("Payload must be valid JSON");
      return;
    }
  }

  try {
    sendSignalBtn.disabled = true;
    const data = await apiFetch(`/api/call-rooms/${roomState.activeRoom.id}/signals`, {
      method: "POST",
      body: JSON.stringify({
        fromParticipantId: roomState.participant.id,
        toParticipantId: signalTargetInput.value.trim() || null,
        type: signalTypeInput.value.trim(),
        payload,
      }),
    });

    appendSignalLogEntry(data.signal);
    roomState.latestSequence = Math.max(roomState.latestSequence, data.signal.sequence);
    signalSequenceBadge.textContent = `Seq ${roomState.latestSequence}`;
    await refreshRooms({ silent: true });
    showToast(`Signal ${data.signal.type} sent`);
  } catch (error) {
    console.error("Failed to send signal:", error);
    showToast(`Send failed: ${error.message}`);
  } finally {
    sendSignalBtn.disabled = false;
  }
}

async function setupCameraOnly() {
  try {
    setStatus("Camera Ready");

    const model = models.realtime(MODEL_NAME);
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        frameRate: model.fps,
        width: model.width,
        height: model.height,
      },
    });

    sourceVideo.srcObject = stream;
    sourceVideo.classList.remove("hidden");
    localStream = stream;
    showToast("Camera ready. Upload an image to begin transformation.");
  } catch (error) {
    console.error("Failed to setup camera:", error);
    setStatus("Camera Failed");

    if (error.name === "NotAllowedError") {
      showToast("Camera access denied. Please allow camera permissions.");
    } else if (error.name === "NotFoundError") {
      showToast("No camera found. Please check your device.");
    } else {
      showToast(`Camera setup failed: ${error.message}`);
    }
  }
}

async function setupRealtimeConnection() {
  try {
    setStatus("Connecting to AI");
    showToast("Starting AI transformation...");

    const model = models.realtime(MODEL_NAME);
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        frameRate: model.fps,
        width: model.width,
        height: model.height,
      },
    });

    sourceVideo.srcObject = stream;
    sourceVideo.classList.remove("hidden");
    localStream = stream;

    const clientApiKey = await getClientToken();
    const client = createDecartClient({ apiKey: clientApiKey });

    realtimeClient = await client.realtime.connect(stream, {
      model,
      onRemoteStream: (transformedStream) => {
        characterImage.style.display = "none";
        resultLoading.classList.add("hidden");

        let videoEl = document.getElementById("result-video");
        if (!videoEl) {
          videoEl = document.createElement("video");
          videoEl.id = "result-video";
          videoEl.autoplay = true;
          videoEl.playsInline = true;
          videoEl.muted = true;
          videoEl.style.width = "100%";
          videoEl.style.height = "100%";
          videoEl.style.objectFit = "cover";
          characterImage.parentElement.insertBefore(videoEl, characterImage);
        }
        videoEl.srcObject = transformedStream;
      },
      initialState: {
        prompt: {
          text: promptInput.value || "Smoothen and upscale the quality of the image",
          enhance: true,
        },
      },
    });

    realtimeClient.on("connectionChange", (state) => {
      const stateText = state.charAt(0).toUpperCase() + state.slice(1);
      setStatus(stateText);

      if (state === "connected") {
        showToast("Connected to AI service");
        sendBtn.disabled = false;
      } else if (state === "disconnected") {
        showToast("Disconnected from AI service");
        sendBtn.disabled = true;
      }
    });

    realtimeClient.on("error", (error) => {
      console.error("Realtime error:", error);
      showToast(`Error: ${error.message}`);
      setStatus("Error");
    });

    realtimeClient.on("generationTick", ({ seconds }) => {
      updateGenerationStats(seconds);
    });

    setStatus("Live");
    showToast("Realtime connection established!");
    return realtimeClient;
  } catch (error) {
    console.error("Failed to setup realtime connection:", error);
    setStatus("Connection Failed");

    if (error.name === "NotAllowedError") {
      showToast("Camera access denied. Please allow camera permissions.");
    } else if (error.name === "NotFoundError") {
      showToast("No camera found. Please check your device.");
    } else {
      showToast(`Connection failed: ${error.message}`);
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
      sourceVideo.srcObject = stream;
      sourceVideo.classList.remove("hidden");
      localStream = stream;
      setStatus("Camera Only");
    } catch {
      setStatus("Camera Unavailable");
    }
  }
}

function startSessionTimer() {
  timerEl.textContent = formatClock(remainingSeconds);

  timerId = window.setInterval(() => {
    if (!sessionActive) {
      return;
    }

    if (remainingSeconds > 0) {
      remainingSeconds -= 1;
      timerEl.textContent = formatClock(remainingSeconds);
    }
  }, 1000);
}

async function updateTransformation() {
  const prompt = promptInput.value.trim();

  if (!lastUploadedFile) {
    showToast("Please upload an image first");
    return;
  }

  if (!prompt) {
    showToast("Enter a prompt first");
    return;
  }

  if (!realtimeClient || !realtimeClient.isConnected()) {
    await setupRealtimeConnection();
  }

  try {
    setStatus("Generating");
    resultLoading.classList.remove("hidden");
    sendBtn.disabled = true;

    await realtimeClient.set({
      prompt,
      image: lastUploadedFile || undefined,
      enhance: true,
    });

    setStatus("Live");
    resultLoading.classList.add("hidden");
    sendBtn.disabled = false;
    showToast("Transformation updated");
  } catch (error) {
    console.error("Update error:", error);
    showToast(`Error updating transformation: ${error.message}`);
    setStatus("Error");
    resultLoading.classList.add("hidden");
    sendBtn.disabled = false;
  }
}

function stopSession() {
  sessionActive = false;
  setStatus("Stopped");

  if (realtimeClient) {
    realtimeClient.disconnect();
    realtimeClient = null;
  }

  if (localStream) {
    localStream.getTracks().forEach((track) => track.stop());
    localStream = null;
  }

  sourceVideo.classList.add("hidden");

  const resultVideo = document.getElementById("result-video");
  if (resultVideo) {
    resultVideo.remove();
  }
  characterImage.style.display = "block";

  showToast("Thank you for using GINX SEED, for more information contact us via @godandinternet");
}

function restartSession() {
  remainingSeconds = 80;
  timerEl.textContent = formatClock(remainingSeconds);
  sessionActive = true;
  stopSessionBtn.textContent = "Stop Session";
  totalGenerationSeconds = 0;
  remainingCreditsElem.textContent = "0s used";
  sendBtn.disabled = true;

  const resultVideo = document.getElementById("result-video");
  if (resultVideo) {
    resultVideo.remove();
  }
  characterImage.style.display = "block";
  sourceVideo.classList.remove("hidden");

  setStatus("Camera Ready");
  lastUploadedFile = null;
  uploadedLabel.textContent = "";
  uploadedLabel.classList.add("hidden");
  showToast("Session restarted. Upload a new image to begin.");
}

function attachEvents() {
  uploadBtn.addEventListener("click", () => imageInput.click());

  imageInput.addEventListener("change", async () => {
    if (!imageInput.files || !imageInput.files[0]) {
      return;
    }

    const file = imageInput.files[0];
    lastUploadedFile = file;
    uploadedLabel.textContent = `Uploaded: ${file.name}`;
    uploadedLabel.classList.remove("hidden");

    sendBtn.disabled = false;
    setStatus("Ready to Transform");
    showToast("Image uploaded. Ready to transform!");

    if (realtimeClient && realtimeClient.isConnected()) {
      try {
        await realtimeClient.setImage(file);
        showToast("Reference image applied to transformation");
      } catch (error) {
        console.error("Error setting image:", error);
        showToast("Error applying reference image");
      }
    }
  });

  sendBtn.addEventListener("click", updateTransformation);

  promptInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      updateTransformation();
    }
  });

  fullscreenBtn.addEventListener("click", async () => {
    let target = document.getElementById("result-video");
    if (!target || !target.srcObject) {
      target = characterImage.closest(".video-container");
    }

    if (!target) {
      return;
    }

    if (document.fullscreenElement) {
      await document.exitFullscreen();
    } else {
      await target.requestFullscreen();
    }
  });

  stopSessionBtn.addEventListener("click", () => {
    if (sessionActive) {
      stopSession();
      stopSessionBtn.textContent = "Restart Session";
      return;
    }

    restartSession();
  });

  refreshRoomsBtn.addEventListener("click", () => refreshRooms());
  createRoomBtn.addEventListener("click", createRoom);
  joinRoomBtn.addEventListener("click", joinSelectedRoom);
  leaveRoomBtn.addEventListener("click", leaveActiveRoom);
  sendSignalBtn.addEventListener("click", sendSignal);
  pollSignalsBtn.addEventListener("click", () => pollSignals());

  roomsList.addEventListener("click", (event) => {
    const button = event.target.closest("[data-room-id]");
    if (!button) {
      return;
    }

    roomState.selectedRoomId = button.getAttribute("data-room-id") || "";
    roomState.activeRoom = roomState.participant?.id && roomState.activeRoom?.id === roomState.selectedRoomId
      ? roomState.activeRoom
      : null;
    renderRooms();
    updateDebuggerControls();
  });
}

async function main() {
  sendBtn.disabled = true;
  setStatus("Initializing");
  attachEvents();
  startSessionTimer();
  clearSignalFeed();
  renderRooms();
  await refreshRooms({ silent: true });

  await setupCameraOnly();

  window.addEventListener("beforeunload", () => {
    if (realtimeClient) {
      realtimeClient.disconnect();
    }
    if (localStream) {
      localStream.getTracks().forEach((track) => track.stop());
    }
    stopHeartbeat();
    stopSignalPolling();
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", main);
} else {
  main();
}
