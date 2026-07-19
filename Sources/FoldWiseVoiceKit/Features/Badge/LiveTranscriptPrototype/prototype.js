const variants = [
  { key: "A", name: "Attached panel" },
  { key: "B", name: "Ribbon rail" },
  { key: "C", name: "Dictation stack" },
];

const scripts = {
  en: {
    tag: "EN",
    chunks: [
      ["The next release should", " make model choices"],
      ["The next release should make model choices", " easier to understand"],
      ["The next release should make model choices easier to understand", " without hiding"],
      ["The next release should make model choices easier to understand without hiding", " what each model can do"],
      ["The next release should make model choices easier to understand without hiding what each model can do.", " Live transcription"],
      ["The next release should make model choices easier to understand without hiding what each model can do. Live transcription", " should feel immediate"],
      ["The next release should make model choices easier to understand without hiding what each model can do. Live transcription should feel immediate", " but never unstable."],
    ],
    raw: "The next release should make model choices easier to understand without hiding what each model can do. Live transcription should feel immediate but never unstable.",
    polished: "The next release should make model choices easier to understand without obscuring each model’s capabilities. Live transcription should feel immediate, but never unstable.",
    prefix: "The next release should ",
  },
  pl: {
    tag: "PL",
    chunks: [
      ["W następnym wydaniu", " wybór modeli"],
      ["W następnym wydaniu wybór modeli", " powinien być prostszy"],
      ["W następnym wydaniu wybór modeli powinien być prostszy", " bez ukrywania"],
      ["W następnym wydaniu wybór modeli powinien być prostszy bez ukrywania", " ich możliwości"],
      ["W następnym wydaniu wybór modeli powinien być prostszy bez ukrywania ich możliwości.", " Transkrypcja na żywo"],
      ["W następnym wydaniu wybór modeli powinien być prostszy bez ukrywania ich możliwości. Transkrypcja na żywo", " powinna być natychmiastowa"],
      ["W następnym wydaniu wybór modeli powinien być prostszy bez ukrywania ich możliwości. Transkrypcja na żywo powinna być natychmiastowa", " ale nigdy niestabilna."],
    ],
    raw: "W następnym wydaniu wybór modeli powinien być prostszy bez ukrywania ich możliwości. Transkrypcja na żywo powinna być natychmiastowa, ale nigdy niestabilna.",
    polished: "W następnym wydaniu wybór modeli powinien być prostszy, bez ukrywania ich możliwości. Transkrypcja na żywo powinna działać natychmiastowo, lecz stabilnie.",
    prefix: "W następnym wydaniu ",
  },
};

const stage = document.querySelector("#badgeStage");
const badge = document.querySelector("#badge");
const primaryAction = document.querySelector("#primaryAction");
const cancelButton = document.querySelector("#cancel");
const restartButton = document.querySelector("#restart");
const timer = document.querySelector("#timer");
const workLabel = document.querySelector("#workLabel");
const resultIcon = document.querySelector("#resultIcon");
const resultLabel = document.querySelector("#resultLabel");
const stateCaption = document.querySelector("#stateCaption");
const languageTag = document.querySelector("#languageTag");
const transcriptViewport = document.querySelector("#transcriptViewport");
const continuousCommitted = document.querySelector("#variantAText .committed");
const continuousTentative = document.querySelector("#variantAText .tentative");
const railCommitted = document.querySelector("#variantBRail .committed");
const railTentative = document.querySelector("#variantBRail .tentative");
const segmentStack = document.querySelector("#variantCStack");
const insertedText = document.querySelector("#insertedText");
const variantLabel = document.querySelector("#variantLabel");
const reduceMotion = document.querySelector("#reduceMotion");
const outcomeSelect = document.querySelector("#outcome");

let language = "en";
let mode = "raw";
let position = "bottom";
let phase = "idle";
let chunkIndex = 0;
let elapsed = 0;
let transcriptTimer;
let elapsedTimer;
let dwellTimer;

function selectedVariant() {
  const requested = new URLSearchParams(window.location.search).get("variant")?.toUpperCase();
  return variants.find((variant) => variant.key === requested) ?? variants[0];
}

function setVariant(key) {
  const variant = variants.find((item) => item.key === key) ?? variants[0];
  const url = new URL(window.location.href);
  url.searchParams.set("variant", variant.key);
  window.history.replaceState({}, "", url);
  stage.classList.remove("variant-a", "variant-b", "variant-c");
  stage.classList.add(`variant-${variant.key.toLowerCase()}`);
  variantLabel.textContent = `${variant.key} — ${variant.name}`;
  stage.classList.remove("focus-flash");
  requestAnimationFrame(() => stage.classList.add("focus-flash"));
}

function cycleVariant(direction) {
  const current = variants.findIndex((item) => item.key === selectedVariant().key);
  const next = (current + direction + variants.length) % variants.length;
  setVariant(variants[next].key);
}

function clearTimers() {
  clearInterval(transcriptTimer);
  clearInterval(elapsedTimer);
  clearTimeout(dwellTimer);
}

function formatTime(seconds) {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

function setTranscript(committed, tentative, final = false) {
  continuousCommitted.textContent = committed ? `${committed} ` : "";
  continuousTentative.textContent = tentative;
  railCommitted.textContent = committed ? `${committed} ` : "";
  railTentative.textContent = tentative;
  renderSegments(committed, tentative, final);
  stage.classList.toggle("has-text", Boolean(committed || tentative));
  requestAnimationFrame(() => {
    transcriptViewport.scrollTop = transcriptViewport.scrollHeight;
    document.querySelector("#variantBRail").scrollLeft = document.querySelector("#variantBRail").scrollWidth;
  });
}

function renderSegments(committed, tentative, final) {
  segmentStack.replaceChildren();
  const sentences = committed.match(/[^.!?]+[.!?]?/g)?.filter((item) => item.trim()) ?? [];
  sentences.forEach((sentence, index) => {
    const element = document.createElement("div");
    element.className = "segment";
    if (!final && index === sentences.length - 1 && !/[.!?]$/.test(sentence.trim())) {
      element.classList.add("tentative-segment");
    }
    element.textContent = sentence.trim();
    segmentStack.append(element);
  });
  if (tentative) {
    const element = document.createElement("div");
    element.className = "segment tentative-segment";
    element.textContent = tentative.trim();
    segmentStack.append(element);
  }
}

function setBadgeClass(name) {
  badge.className = `badge ${name}`;
}

function setIdle() {
  clearTimers();
  phase = "idle";
  chunkIndex = 0;
  elapsed = 0;
  timer.textContent = "0:00";
  stage.classList.remove("has-text", "is-finalizing");
  setBadgeClass("is-idle");
  setTranscript("", "");
  primaryAction.disabled = false;
  primaryAction.textContent = "Start live comparison";
  stateCaption.textContent = "Start once, then use ← → while the transcript runs";
  insertedText.textContent = scripts[language].prefix;
}

function startListening() {
  clearTimers();
  phase = "listening";
  chunkIndex = 0;
  elapsed = 0;
  setTranscript("", "");
  setBadgeClass("is-listening");
  stage.classList.remove("is-finalizing");
  primaryAction.disabled = false;
  primaryAction.textContent = "Stop";
  stateCaption.textContent = "Listening · click Stop to commit the session";

  elapsedTimer = setInterval(() => {
    elapsed += 1;
    timer.textContent = formatTime(elapsed);
  }, 1000);

  function advance() {
    const chunk = scripts[language].chunks[Math.min(chunkIndex, scripts[language].chunks.length - 1)];
    setTranscript(chunk[0], chunk[1]);
    chunkIndex += 1;
  }
  advance();
  transcriptTimer = setInterval(advance, 1080);
}

function stopListening() {
  if (phase !== "listening") return;
  clearInterval(transcriptTimer);
  clearInterval(elapsedTimer);
  phase = "finalizing";
  const current = scripts[language].chunks[Math.min(Math.max(chunkIndex - 1, 0), scripts[language].chunks.length - 1)];
  setTranscript(`${current[0]}${current[1]}`, "", true);
  setBadgeClass("is-finalizing");
  stage.classList.add("is-finalizing");
  workLabel.textContent = mode === "polish" ? "polishing…" : "finalizing…";
  primaryAction.textContent = "Finalizing…";
  primaryAction.disabled = true;
  stateCaption.textContent = mode === "polish"
    ? "Finalizing · raw transcript remains visible during Polish"
    : "Finalizing · committed transcript remains visible";
  dwellTimer = setTimeout(finishScenario, mode === "polish" ? 1800 : 1200);
}

function finishScenario() {
  const outcome = outcomeSelect.value;
  const script = scripts[language];
  stage.classList.remove("is-finalizing");
  primaryAction.disabled = false;
  primaryAction.textContent = "Run again";

  if (outcome === "recognition-error") {
    showResult("is-error", "!", "speech wasn’t recognized", "Error · retry keeps focus in the target app");
    return;
  }

  const rawText = script.raw;
  if (outcome === "polish-error" && mode === "polish") {
    setTranscript(rawText, "", true);
    insertedText.textContent = rawText;
    showResult("is-error", "!", "Polish unavailable · raw inserted", "Fallback · raw transcript inserted truthfully");
    return;
  }

  const finalText = mode === "polish" ? script.polished : rawText;
  setTranscript(finalText, "", true);
  insertedText.textContent = finalText;
  if (outcome === "clipboard") {
    showResult("is-error", "⌘", "copied — press ⌘V", "Insertion failed · transcript is safe on the clipboard");
  } else {
    showResult("is-result", "✓", "inserted", mode === "polish" ? "Success · polished text inserted" : "Success · transcript inserted");
  }
}

function showResult(badgeClass, icon, label, caption) {
  phase = "result";
  setBadgeClass(badgeClass);
  resultIcon.textContent = icon;
  resultLabel.textContent = label;
  stateCaption.textContent = caption;
}

function cancelSession() {
  if (phase !== "listening" && phase !== "finalizing") return;
  clearTimers();
  phase = "cancelled";
  stage.classList.remove("is-finalizing", "has-text");
  setTranscript("", "");
  setBadgeClass("is-cancelled");
  resultIcon.textContent = "×";
  resultLabel.textContent = "cancelled";
  stateCaption.textContent = "Cancelled · no transcript inserted or saved";
  primaryAction.disabled = true;
  primaryAction.textContent = "Cancelled";
  dwellTimer = setTimeout(setIdle, 1150);
}

function activatePrimary() {
  if (phase === "idle" || phase === "result") startListening();
  else if (phase === "listening") stopListening();
}

document.querySelectorAll("[data-language]").forEach((button) => {
  button.addEventListener("click", () => {
    language = button.dataset.language;
    document.querySelectorAll("[data-language]").forEach((item) => item.classList.toggle("selected", item === button));
    languageTag.textContent = scripts[language].tag;
    document.documentElement.lang = language;
    setIdle();
  });
});

document.querySelectorAll("[data-mode]").forEach((button) => {
  button.addEventListener("click", () => {
    mode = button.dataset.mode;
    document.querySelectorAll("[data-mode]").forEach((item) => item.classList.toggle("selected", item === button));
    setIdle();
  });
});

document.querySelectorAll("[data-position]").forEach((button) => {
  button.addEventListener("click", () => {
    position = button.dataset.position;
    document.querySelectorAll("[data-position]").forEach((item) => item.classList.toggle("selected", item === button));
    stage.classList.toggle("position-top", position === "top");
    stateCaption.textContent = position === "top" ? "Top position · growth flows down" : "Bottom position · growth flows up";
  });
});

reduceMotion.addEventListener("change", () => {
  document.body.classList.toggle("reduce-motion", reduceMotion.checked);
});
primaryAction.addEventListener("click", activatePrimary);
badge.addEventListener("click", () => {
  if (phase === "listening") stopListening();
});
cancelButton.addEventListener("click", (event) => {
  event.stopPropagation();
  cancelSession();
});
restartButton.addEventListener("click", setIdle);
document.querySelector("#previousVariant").addEventListener("click", () => cycleVariant(-1));
document.querySelector("#nextVariant").addEventListener("click", () => cycleVariant(1));

window.addEventListener("keydown", (event) => {
  const target = event.target;
  if (target.matches("input, select, textarea, [contenteditable]")) return;
  if (event.key === "ArrowLeft") cycleVariant(-1);
  if (event.key === "ArrowRight") cycleVariant(1);
  if (event.key === "Escape") cancelSession();
});

window.addEventListener("popstate", () => setVariant(selectedVariant().key));
setVariant(selectedVariant().key);
setIdle();
