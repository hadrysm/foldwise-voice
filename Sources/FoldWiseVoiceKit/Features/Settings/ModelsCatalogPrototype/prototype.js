const variants = [
  { key: "A", name: "Inspector rail", thesis: "Your active model first; the complete catalog one selection away." },
  { key: "B", name: "Comparison table", thesis: "Compare every declared fact without pretending unknowns are scores." },
  { key: "C", name: "Guided shelves", thesis: "Start with your language and job; open the full catalog only when needed." },
];

const fallbackCatalog = [
  { id: "parakeet-unified-en-0.6b", name: "Parakeet Unified EN 0.6B", architecture: "parakeet", family: "parakeet", parameters: "0.6B", base_model: "nvidia/parakeet-unified-en-0.6b", license: "cc-by-4.0", languages: ["en"], capabilities: { streaming: true, translate: false, lang_detect: false, timestamps: "token" }, default_quant: "Q8_0", files: [{ quant: "Q8_0", size_bytes: 731357568 }], recommended_rank: 1, description: "Fast, accurate live English transcription" },
  { id: "nemotron-3.5-asr-streaming-0.6b", name: "Nemotron Streaming 3.5", architecture: "parakeet", family: "nemotron", parameters: "0.6B", base_model: "nvidia/nemotron-3.5-asr-streaming-0.6b", license: "other", languages: ["en", "es", "fr", "it", "pt", "nl", "de", "tr", "ru", "ar", "hi", "ja", "ko", "vi", "uk", "pl", "sv", "cs", "nb", "da", "bg", "fi", "hr", "sk", "zh", "hu", "ro", "et"], capabilities: { streaming: true, translate: false, lang_detect: true, timestamps: "token" }, default_quant: "Q8_0", files: [{ quant: "Q8_0", size_bytes: 751094240 }], recommended_rank: 2, description: "Live multilingual transcription across 28 languages" },
  { id: "canary-180m-flash", name: "Canary 180M Flash", architecture: "canary", family: "canary", parameters: "180M", base_model: "nvidia/canary-180m-flash", license: "cc-by-4.0", languages: ["en", "de", "es", "fr"], capabilities: { streaming: false, translate: true, lang_detect: false, timestamps: "none" }, default_quant: "Q8_0", files: [{ quant: "Q8_0", size_bytes: 218447552 }], recommended_rank: 3, description: "Tiny and instant, runs well on any hardware" },
  { id: "whisper-medium", name: "Whisper Medium", architecture: "whisper", family: "whisper", parameters: "764M", base_model: "openai/whisper-medium", license: "apache-2.0", languages: ["en", "pl", "de", "fr", "es"], capabilities: { streaming: false, translate: true, lang_detect: true, timestamps: "segment" }, default_quant: "Q8_0", files: [{ quant: "Q8_0", size_bytes: 831538144 }], recommended_rank: 5, description: "Broadest language coverage, but may run a bit slow" },
];

const state = {
  catalog: [],
  selectedID: "parakeet-unified-en-0.6b",
  inspectedID: "nemotron-3.5-asr-streaming-0.6b",
  installed: new Set([
    "parakeet-unified-en-0.6b",
    "nemotron-3.5-asr-streaming-0.6b",
    "canary-180m-flash",
  ]),
  quantization: new Map(),
  search: "",
  language: "all",
  capability: "all",
  status: "all",
  guideLanguage: "pl",
  guideJob: "live",
  job: "speech",
  download: null,
};

const speechSurface = document.querySelector("#speechSurface");
const polishSurface = document.querySelector("#polishSurface");
const loading = document.querySelector("#catalogLoading");
const variantLabel = document.querySelector("#variantLabel");
const variantThesis = document.querySelector("#variantThesis");
const toast = document.querySelector("#toast");
let toastTimer;

function selectedVariant() {
  const key = new URLSearchParams(window.location.search).get("variant")?.toUpperCase();
  return variants.find((variant) => variant.key === key) ?? variants[0];
}

function setVariant(key) {
  const variant = variants.find((item) => item.key === key) ?? variants[0];
  const url = new URL(window.location.href);
  url.searchParams.set("variant", variant.key);
  window.history.replaceState({}, "", url);
  variantLabel.textContent = `${variant.key} — ${variant.name}`;
  variantThesis.textContent = state.job === "speech"
    ? variant.thesis
    : "Writing models stay separate from the speech catalog and ASR model selection.";
  render();
}

function cycleVariant(direction) {
  const current = variants.findIndex((item) => item.key === selectedVariant().key);
  setVariant(variants[(current + direction + variants.length) % variants.length].key);
}

function escapeHTML(value = "") {
  return String(value).replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]);
}

function defaultFile(model) {
  return model.files.find((file) => file.quant === (state.quantization.get(model.id) ?? model.default_quant)) ?? model.files[0];
}

function formatBytes(bytes) {
  if (!bytes) return "Unknown";
  const gb = bytes / 1_000_000_000;
  return gb >= 1 ? `${gb.toFixed(gb >= 10 ? 0 : 1)} GB` : `${Math.round(bytes / 1_000_000)} MB`;
}

function languageText(model) {
  if (model.languages.length === 1) return model.languages[0].toUpperCase();
  return `${model.languages.length} languages`;
}

function installed(model) { return state.installed.has(model.id); }

function compatibility(model) {
  if (model.id === state.selectedID) return { label: "Ready on this Mac", className: "ready" };
  if (installed(model)) return { label: "Downloaded · untested", className: "unverified" };
  return { label: "Not checked", className: "unverified" };
}

function chips(model, compact = false) {
  const items = [];
  if (model.capabilities.streaming) items.push(`<span class="live-chip" title="FoldWise runtime verification pending">Live</span>`);
  if (!compact && model.capabilities.translate) items.push(`<span class="fact-chip">Translation</span>`);
  if (!compact && model.capabilities.lang_detect) items.push(`<span class="fact-chip">Language detect</span>`);
  items.push(`<span class="language-fact">${escapeHTML(languageText(model))}</span>`);
  return items.join("");
}

function activeAnchor() {
  const model = state.catalog.find((entry) => entry.id === state.selectedID) ?? state.catalog[0];
  return `<section class="active-anchor" aria-label="Active ASR model">
    <div class="anchor-copy"><span class="eyebrow">ASR model selection</span><strong>${escapeHTML(model.name)}</strong><small>${escapeHTML(model.family)} · ${escapeHTML(model.parameters)}</small></div>
    <div class="anchor-facts">${chips(model)}<span class="fact-chip">${escapeHTML(state.quantization.get(model.id) ?? model.default_quant)}</span><span class="fact-chip"><strong>${formatBytes(defaultFile(model)?.size_bytes)}</strong></span></div>
    <span class="active-mark">● Active</span>
  </section>`;
}

function filteredCatalog() {
  const needle = state.search.trim().toLowerCase();
  return state.catalog.filter((model) => {
    const matchesSearch = !needle || [model.name, model.family, model.architecture, model.description, model.languages.join(" ")].join(" ").toLowerCase().includes(needle);
    const matchesLanguage = state.language === "all" || model.languages.includes(state.language);
    const matchesCapability = state.capability === "all"
      || (state.capability === "live" && model.capabilities.streaming)
      || (state.capability === "translate" && model.capabilities.translate)
      || (state.capability === "detect" && model.capabilities.lang_detect);
    const matchesStatus = state.status === "all" || (state.status === "downloaded" ? installed(model) : !installed(model));
    return matchesSearch && matchesLanguage && matchesCapability && matchesStatus;
  }).sort((a, b) => {
    const aRank = a.recommended_rank ?? 999;
    const bRank = b.recommended_rank ?? 999;
    return aRank - bRank || a.name.localeCompare(b.name);
  });
}

function toolbar() {
  return `<div class="toolbar">
    <label class="search-field"><input id="catalogSearch" type="search" placeholder="Search ${state.catalog.length} models, families, or languages…" value="${escapeHTML(state.search)}" aria-label="Search catalog"></label>
    <select id="languageFilter" aria-label="Language"><option value="all">All languages</option><option value="en" ${state.language === "en" ? "selected" : ""}>English</option><option value="pl" ${state.language === "pl" ? "selected" : ""}>Polish</option><option value="de" ${state.language === "de" ? "selected" : ""}>German</option><option value="es" ${state.language === "es" ? "selected" : ""}>Spanish</option><option value="zh" ${state.language === "zh" ? "selected" : ""}>Chinese</option></select>
    <select id="capabilityFilter" aria-label="Capability"><option value="all">All capabilities</option><option value="live" ${state.capability === "live" ? "selected" : ""}>Live transcript</option><option value="translate" ${state.capability === "translate" ? "selected" : ""}>Translation</option><option value="detect" ${state.capability === "detect" ? "selected" : ""}>Language detect</option></select>
    <select id="statusFilter" aria-label="Download status"><option value="all">Any status</option><option value="downloaded" ${state.status === "downloaded" ? "selected" : ""}>Downloaded</option><option value="available" ${state.status === "available" ? "selected" : ""}>Available</option></select>
  </div>`;
}

function modelRow(model) {
  return `<button class="model-row ${model.id === state.inspectedID ? "selected" : ""}" data-inspect="${escapeHTML(model.id)}">
    <span class="model-identity"><strong>${escapeHTML(model.name)}</strong><span>${escapeHTML(model.family)} · ${escapeHTML(model.architecture)}</span></span>
    <span class="row-capabilities">${chips(model, true)}</span>
    <span class="row-size">${formatBytes(defaultFile(model)?.size_bytes)}</span>
    <i class="availability-dot ${installed(model) ? "installed" : ""}" title="${installed(model) ? "Downloaded" : "Available to download"}"></i>
  </button>`;
}

function inspector(model) {
  const file = defaultFile(model);
  const isInstalled = installed(model);
  const isActive = model.id === state.selectedID;
  const compatibilityFact = compatibility(model);
  const downloading = state.download?.id === model.id;
  return `<aside class="inspector" aria-label="Model details">
    <div class="inspector-head"><span class="section-label">Model details</span><button title="Close details" aria-label="Close details">⌘I</button></div>
    <div class="inspector-body">
      <h2 class="inspector-title">${escapeHTML(model.name)}</h2>
      <p class="inspector-description">${escapeHTML(model.description || "No catalog description.")}</p>
      <div class="inspector-chips">${chips(model)}<span class="status ${isInstalled ? "ready" : ""}">${isInstalled ? "Downloaded" : "Available"}</span><span class="compatibility ${compatibilityFact.className}">${compatibilityFact.label}</span></div>
      <div class="fact-grid">
        <div class="fact-cell"><span>Engine architecture</span><strong>${escapeHTML(model.architecture)}</strong></div>
        <div class="fact-cell"><span>Parameters</span><strong>${escapeHTML(model.parameters)}</strong></div>
        <div class="fact-cell"><span>Languages</span><strong>${escapeHTML(languageText(model))}</strong></div>
        <div class="fact-cell"><span>Timestamps</span><strong>${escapeHTML(model.capabilities.timestamps)}</strong></div>
        <div class="fact-cell"><span>Accuracy</span><strong>Not benchmarked</strong></div>
        <div class="fact-cell"><span>Speed</span><strong>Not benchmarked</strong></div>
        <div class="fact-cell"><span>License label</span><strong>${escapeHTML(model.license)}</strong></div>
        <div class="fact-cell"><span>Source model</span><strong>${escapeHTML(model.base_model)}</strong></div>
      </div>
      <div class="truth-note"><strong>Catalog evidence, not a FoldWise guarantee.</strong> Compatibility, behavior, legal terms, speed, and accuracy still need FoldWise verification.</div>
      <div class="quant-row"><label><span>Quantization</span><select data-quant="${escapeHTML(model.id)}">${model.files.map((candidate) => `<option value="${candidate.quant}" ${candidate.quant === file.quant ? "selected" : ""}>${candidate.quant} · ${formatBytes(candidate.size_bytes)}</option>`).join("")}</select></label><div class="storage-impact"><span>Download size</span><strong>${formatBytes(file.size_bytes)}</strong></div></div>
      ${downloading ? `<div class="progress-track" style="--progress:${state.download.progress}%"><i></i></div>` : ""}
      <div class="actions">
        ${!isInstalled ? `<button class="primary-button" data-download="${escapeHTML(model.id)}">${downloading ? `Downloading ${state.download.progress}%` : "Download"}</button>` : `<button class="primary-button" data-use="${escapeHTML(model.id)}" ${isActive ? "disabled" : ""}>${isActive ? "Active model" : "Use model"}</button>`}
        ${isInstalled && !isActive ? `<button class="danger-button" data-delete="${escapeHTML(model.id)}">Delete…</button>` : ""}
      </div>
    </div>
  </aside>`;
}

function renderVariantA() {
  const models = filteredCatalog();
  const inspected = state.catalog.find((model) => model.id === state.inspectedID) ?? models[0] ?? state.catalog[0];
  const recommended = state.status === "all" ? models.filter((model) => model.recommended_rank) : [];
  const remaining = state.status === "all" ? models.filter((model) => !model.recommended_rank) : models;
  const rows = state.status === "all"
    ? `${recommended.length ? `<div class="catalog-group-label">FoldWise picks <span>${recommended.length}</span></div>${recommended.map(modelRow).join("")}` : ""}<div class="catalog-group-label">Complete catalog <span>${remaining.length}</span></div>${remaining.map(modelRow).join("")}`
    : models.map(modelRow).join("");
  return `<div class="variant-a">${activeAnchor()}${toolbar()}<div class="master-detail">
    <section class="catalog-list"><div class="list-head"><strong>${state.status === "downloaded" ? "Downloaded" : "Catalog"}</strong><span>${models.length} of ${state.catalog.length}</span></div><div class="model-scroll">${rows || emptyResult()}</div></section>
    ${inspector(inspected)}
  </div></div>`;
}

function tableRow(model) {
  const compatibilityFact = compatibility(model);
  return `<tr class="${model.id === state.inspectedID ? "selected" : ""}" data-inspect="${escapeHTML(model.id)}" tabindex="0">
    <td><strong>${escapeHTML(model.name)}</strong><span>${escapeHTML(model.family)} · ${escapeHTML(model.parameters)}</span></td>
    <td>${escapeHTML(languageText(model))}</td>
    <td class="${model.capabilities.streaming ? "yes" : "no"}">${model.capabilities.streaming ? "LIVE" : "—"}</td>
    <td class="${model.capabilities.translate ? "yes" : "no"}">${model.capabilities.translate ? "Yes" : "—"}</td>
    <td>${escapeHTML(model.architecture)}</td>
    <td class="mono">${escapeHTML(state.quantization.get(model.id) ?? model.default_quant)}</td>
    <td class="mono">${formatBytes(defaultFile(model)?.size_bytes)}</td>
    <td>${installed(model) ? "Downloaded" : "Available"}</td>
    <td class="compatibility ${compatibilityFact.className}">${compatibilityFact.label}</td>
  </tr>`;
}

function tableDetail(model) {
  const isInstalled = installed(model);
  const isActive = model.id === state.selectedID;
  return `<div class="table-detail">
    <div><strong>${escapeHTML(model.name)}</strong><span>${escapeHTML(model.description)}</span></div>
    <div><span class="metric-label">Accuracy</span><span class="metric-value">Not benchmarked</span></div>
    <div><span class="metric-label">Speed</span><span class="metric-value">Not benchmarked</span></div>
    <div><span class="metric-label">License</span><span class="metric-value">${escapeHTML(model.license)}</span></div>
    <div><span class="metric-label">Source model</span><span class="metric-value">${escapeHTML(model.base_model)}</span></div>
    ${isInstalled ? `<button class="primary-button" data-use="${escapeHTML(model.id)}" ${isActive ? "disabled" : ""}>${isActive ? "Active" : "Use model"}</button>` : `<button class="primary-button" data-download="${escapeHTML(model.id)}">Download</button>`}
  </div>`;
}

function renderVariantB() {
  const models = filteredCatalog();
  const inspected = state.catalog.find((model) => model.id === state.inspectedID) ?? models[0] ?? state.catalog[0];
  return `<div class="variant-b">${activeAnchor()}${toolbar()}<section class="table-wrap"><div class="table-head"><strong>Complete catalog</strong><span>${models.length} of ${state.catalog.length} · unknown facts stay unknown</span></div>
    <table class="comparison-table"><thead><tr><th>Model</th><th>Languages</th><th>Live</th><th>Translate</th><th>Engine</th><th>Quant</th><th>Size</th><th>Status</th><th>FoldWise compatibility</th></tr></thead><tbody>${models.map(tableRow).join("")}</tbody></table>
    ${tableDetail(inspected)}
  </section></div>`;
}

function matchesGuide(model) {
  const language = state.guideLanguage;
  const languageMatch = model.languages.includes(language);
  const jobMatch = state.guideJob === "live" ? model.capabilities.streaming : state.guideJob === "translate" ? model.capabilities.translate : true;
  return languageMatch && jobMatch;
}

function recommendationCard(model) {
  return `<article class="recommend-card ${model.id === state.inspectedID ? "selected" : ""}" data-inspect="${escapeHTML(model.id)}" tabindex="0">
    <div>${model.capabilities.streaming ? `<span class="live-chip">Live</span>` : `<span class="fact-chip">${model.capabilities.translate ? "Translation" : "Transcription"}</span>`}</div>
    <h4>${escapeHTML(model.name)}</h4><p>${escapeHTML(model.description)}</p>
    <footer><span>${escapeHTML(languageText(model))}</span><span>${formatBytes(defaultFile(model)?.size_bytes)}</span></footer>
  </article>`;
}

function familyGroup([family, models], index) {
  return `<details class="family-group" ${index === 0 ? "open" : ""}><summary><strong>${escapeHTML(family)}</strong><span>${models.length} models</span></summary><div class="family-models">${models.map((model) => `<button class="family-model ${model.id === state.inspectedID ? "selected" : ""}" data-inspect="${escapeHTML(model.id)}"><strong>${escapeHTML(model.name)}</strong>${model.capabilities.streaming ? `<span class="yes">LIVE</span>` : `<span>${escapeHTML(languageText(model))}</span>`}<span>${formatBytes(defaultFile(model)?.size_bytes)}</span></button>`).join("")}</div></details>`;
}

function guidedSelection(model) {
  const isInstalled = installed(model);
  const isActive = model.id === state.selectedID;
  return `<div class="guided-selection"><div><strong>${escapeHTML(model.name)}</strong><span>${escapeHTML(model.description)}</span><span class="guided-facts">${escapeHTML(model.architecture)} · ${escapeHTML(state.quantization.get(model.id) ?? model.default_quant)} · ${formatBytes(defaultFile(model)?.size_bytes)} · ${escapeHTML(model.license)} · source ${escapeHTML(model.base_model)} · accuracy/speed not benchmarked</span></div><span class="compatibility ${compatibility(model).className}">${compatibility(model).label}</span>${isInstalled ? `<button class="primary-button" data-use="${escapeHTML(model.id)}" ${isActive ? "disabled" : ""}>${isActive ? "Active" : "Use model"}</button>` : `<button class="primary-button" data-download="${escapeHTML(model.id)}">Download ${formatBytes(defaultFile(model)?.size_bytes)}</button>`}</div>`;
}

function renderVariantC() {
  const matches = state.catalog.filter(matchesGuide).sort((a, b) => (a.recommended_rank ?? 999) - (b.recommended_rank ?? 999));
  const recommendations = (matches.length ? matches : state.catalog).slice(0, 3);
  const groups = Object.entries(state.catalog.reduce((result, model) => { (result[model.family] ??= []).push(model); return result; }, {})).sort(([a], [b]) => a.localeCompare(b));
  const inspected = state.catalog.find((model) => model.id === state.inspectedID) ?? recommendations[0];
  return `<div class="variant-c"><section class="guide-banner"><div class="guide-copy"><span class="eyebrow">Find a speech model</span><h2>What needs to work?</h2><p>FoldWise narrows the catalog using declared facts. A recommendation remains provisional until compatibility and quality are measured on this Mac.</p></div><div class="guide-controls">
    <label><span>I speak</span><select id="guideLanguage"><option value="pl" ${state.guideLanguage === "pl" ? "selected" : ""}>Polish</option><option value="en" ${state.guideLanguage === "en" ? "selected" : ""}>English</option><option value="de" ${state.guideLanguage === "de" ? "selected" : ""}>German</option><option value="es" ${state.guideLanguage === "es" ? "selected" : ""}>Spanish</option><option value="zh" ${state.guideLanguage === "zh" ? "selected" : ""}>Chinese</option></select></label>
    <label><span>I need</span><select id="guideJob"><option value="live" ${state.guideJob === "live" ? "selected" : ""}>Live transcript</option><option value="translate" ${state.guideJob === "translate" ? "selected" : ""}>Translation</option><option value="transcribe" ${state.guideJob === "transcribe" ? "selected" : ""}>Transcription</option></select></label>
    <button class="quiet-button" data-clear-guide>Browse all ${state.catalog.length}</button>
  </div></section>
  <div class="guided-scroll"><section class="shelf"><div class="shelf-heading"><div><span class="eyebrow">Closest declared matches</span><h3>${recommendations.length} to inspect</h3></div><span>${matches.length} catalog matches</span></div><div class="recommendation-grid">${recommendations.map(recommendationCard).join("")}</div>${guidedSelection(inspected)}</section>
  <section class="shelf"><div class="shelf-heading"><div><span class="eyebrow">Complete catalog</span><h3>Browse by family</h3></div><span>${groups.length} families · ${state.catalog.length} models</span></div><div class="family-stack">${groups.map(familyGroup).join("")}</div></section></div></div>`;
}

function emptyResult() { return `<div class="loading-state">No models match these filters.</div>`; }

function render() {
  if (!state.catalog.length) return;
  const variant = selectedVariant();
  speechSurface.innerHTML = variant.key === "A" ? renderVariantA() : variant.key === "B" ? renderVariantB() : renderVariantC();
  bindSurfaceEvents();
}

function bindSurfaceEvents() {
  document.querySelectorAll("[data-inspect]").forEach((element) => {
    const inspect = () => { state.inspectedID = element.dataset.inspect; render(); };
    element.addEventListener("click", inspect);
    element.addEventListener("keydown", (event) => { if (event.key === "Enter" || event.key === " ") inspect(); });
  });
  const search = document.querySelector("#catalogSearch");
  search?.addEventListener("input", (event) => { state.search = event.target.value; render(); document.querySelector("#catalogSearch")?.focus(); });
  document.querySelector("#languageFilter")?.addEventListener("change", (event) => { state.language = event.target.value; render(); });
  document.querySelector("#capabilityFilter")?.addEventListener("change", (event) => { state.capability = event.target.value; render(); });
  document.querySelector("#statusFilter")?.addEventListener("change", (event) => { state.status = event.target.value; render(); });
  document.querySelector("#guideLanguage")?.addEventListener("change", (event) => { state.guideLanguage = event.target.value; render(); });
  document.querySelector("#guideJob")?.addEventListener("change", (event) => { state.guideJob = event.target.value; render(); });
  document.querySelector("[data-clear-guide]")?.addEventListener("click", () => { state.guideJob = "transcribe"; render(); });
  document.querySelectorAll("[data-quant]").forEach((select) => select.addEventListener("change", () => { state.quantization.set(select.dataset.quant, select.value); render(); }));
  document.querySelectorAll("[data-use]").forEach((button) => button.addEventListener("click", () => { state.selectedID = button.dataset.use; showToast(`${modelByID(button.dataset.use).name} is active for the next Dictation session`); render(); }));
  document.querySelectorAll("[data-download]").forEach((button) => button.addEventListener("click", () => startDownload(button.dataset.download)));
  document.querySelectorAll("[data-delete]").forEach((button) => button.addEventListener("click", () => deleteModel(button.dataset.delete)));
}

function modelByID(id) { return state.catalog.find((model) => model.id === id); }

function startDownload(id) {
  if (state.download) return;
  state.download = { id, progress: 8 };
  render();
  const timer = setInterval(() => {
    state.download.progress = Math.min(100, state.download.progress + 17);
    if (state.download.progress >= 100) {
      clearInterval(timer);
      state.installed.add(id);
      state.download = null;
      showToast(`${modelByID(id).name} downloaded — selection unchanged`);
    }
    render();
  }, 280);
}

function deleteModel(id) {
  const model = modelByID(id);
  if (!window.confirm(`Delete ${model.name}?\n\nThis removes the selected ${state.quantization.get(id) ?? model.default_quant} data from this Mac. Your active model is unchanged.`)) return;
  state.installed.delete(id);
  showToast(`${model.name} deleted`);
  render();
}

function showToast(message) {
  clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.add("visible");
  toastTimer = setTimeout(() => toast.classList.remove("visible"), 2600);
}

document.querySelectorAll("[data-job]").forEach((button) => button.addEventListener("click", () => {
  document.querySelectorAll("[data-job]").forEach((item) => item.classList.toggle("selected", item === button));
  const speech = button.dataset.job === "speech";
  state.job = button.dataset.job;
  speechSurface.hidden = !speech;
  polishSurface.hidden = speech;
  variantThesis.textContent = speech ? selectedVariant().thesis : "Writing models stay separate from the speech catalog and ASR model selection.";
}));
document.querySelector("#previousVariant").addEventListener("click", () => cycleVariant(-1));
document.querySelector("#nextVariant").addEventListener("click", () => cycleVariant(1));
window.addEventListener("keydown", (event) => {
  if (event.target.matches("input, select, textarea, [contenteditable]")) return;
  if (event.key === "ArrowLeft") cycleVariant(-1);
  if (event.key === "ArrowRight") cycleVariant(1);
});
window.addEventListener("popstate", render);

async function loadCatalog() {
  state.catalog = fallbackCatalog;
  for (const model of state.catalog) state.quantization.set(model.id, model.default_quant);
  if (!modelByID(state.inspectedID)) state.inspectedID = state.catalog[0].id;
  loading.hidden = true;
  setVariant(selectedVariant().key);
}

loadCatalog();
