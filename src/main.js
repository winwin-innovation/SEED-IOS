import { createDecartClient, models } from "@decartai/sdk";
import "./style.css";

const MODEL_NAME = "lucy_2_rt";

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

let remainingSeconds = 3600; // 1 hour - session continues until user stops it
let timerId = null;
let sessionActive = true;
let selectedExample = "";
let lastUploadedFile = null;
let localStream = null;
let realtimeClient = null;
let totalGenerationSeconds = 0;

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
      // No-op: keep fallback error message if body is not JSON.
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

// Display generation time as credits proxy (since balance API doesn't exist)
function updateGenerationStats(seconds) {
  totalGenerationSeconds = seconds;
  remainingCreditsElem.textContent = `${seconds}s used`;
}

// Initialize Camera Only (No AI transformation yet)
async function setupCameraOnly() {
  try {
    setStatus("Camera Ready");
    
    // Get camera stream with optimal settings
    const model = models.realtime(MODEL_NAME);
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        frameRate: model.fps,
        width: model.width,
        height: model.height,
      },
    });

    // Display source video
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

// Initialize Decart Realtime Connection (with AI transformation - deducts credits)
async function setupRealtimeConnection() {
  try {
    setStatus("Connecting to AI");
    showToast("Starting AI transformation...");
    
    // Get camera stream with optimal settings
    const model = models.realtime(MODEL_NAME);
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        frameRate: model.fps,
        width: model.width,
        height: model.height,
      },
    });

    // Display source video
    sourceVideo.srcObject = stream;
    sourceVideo.classList.remove("hidden");
    localStream = stream;

    const clientApiKey = await getClientToken();

    // Create Decart client using short-lived key minted by the backend
    const client = createDecartClient({
      apiKey: clientApiKey,
    });

    // Connect to realtime API
    realtimeClient = await client.realtime.connect(stream, {
      model,
      onRemoteStream: (transformedStream) => {
        characterImage.style.display = "none";
        resultLoading.classList.add("hidden");
        
        // Create a video element for the transformed stream
        let videoEl = document.getElementById("result-video");
        if (!videoEl) {
          videoEl = document.createElement("video");
          videoEl.id = "result-video";
          videoEl.autoplay = true;
          videoEl.playsinline = true;
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

    // Handle connection state changes
    realtimeClient.on("connectionChange", (state) => {
      console.log(`Connection state: ${state}`);
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

    // Handle errors
    realtimeClient.on("error", (error) => {
      console.error("Realtime error:", error);
      showToast(`Error: ${error.message}`);
      setStatus("Error");
    });

    // Track generation time (usage proxy for credits)
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
    
    // Fallback to camera only (no AI)
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
      sourceVideo.srcObject = stream;
      sourceVideo.classList.remove("hidden");
      localStream = stream;
      setStatus("Camera Only");
    } catch (e) {
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
  
  // Check if image was uploaded
  if (!lastUploadedFile) {
    showToast("Please upload an image first");
    return;
  }
  
  if (!prompt) {
    showToast("Enter a prompt first");
    return;
  }
  
  // If not connected yet, establish connection first (this starts deducting credits)
  if (!realtimeClient || !realtimeClient.isConnected()) {
    await setupRealtimeConnection();
  }

  try {
    setStatus("Generating");
    resultLoading.classList.remove("hidden");
    sendBtn.disabled = true;

    // Update prompt in realtime
    await realtimeClient.set({
      prompt: prompt,
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
  
  // Remove result video if exists
  const resultVideo = document.getElementById("result-video");
  if (resultVideo) resultVideo.remove();
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
  sendBtn.disabled = true; // Require new image upload for restart
  
  // Show camera again and hide previous transformation
  const resultVideo = document.getElementById("result-video");
  if (resultVideo) resultVideo.remove();
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
    
    // Enable Send button and show status
    sendBtn.disabled = false;
    setStatus("Ready to Transform");
    showToast("Image uploaded. Ready to transform!");

    // Try to set the image in realtime if connected
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
    // Try fullscreen on result video first, then image container
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
}

async function main() {
  sendBtn.disabled = true; // Disabled until image is uploaded
  setStatus("Initializing");
  attachEvents();
  startSessionTimer();
  
  // Auto-start camera on page load (no credits deducted yet)
  await setupCameraOnly();
  
  // Cleanup on page unload
  window.addEventListener("beforeunload", () => {
    if (realtimeClient) {
      realtimeClient.disconnect();
    }
    if (localStream) {
      localStream.getTracks().forEach(track => track.stop());
    }
  });
}

// Initialize when document is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", main);
} else {
  main();
}
