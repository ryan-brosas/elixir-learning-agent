defmodule LearningAgentWeb.Frontend do
  @moduledoc "Browser surface for local learning operations and model dogfooding."

  @html ~S"""
  <!doctype html>
  <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Learning Agent</title>
      <style>
        :root {
          color-scheme: dark;
          --ink: #12110f;
          --ink-soft: #1b1a17;
          --rule: rgba(236, 231, 220, 0.16);
          --paper: #ece7dc;
          --paper-mute: rgba(236, 231, 220, 0.64);
          --paper-faint: rgba(236, 231, 220, 0.42);
          --serif: ui-serif, "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
          --sans: ui-sans-serif, "Segoe UI", "Helvetica Neue", Helvetica, Arial, sans-serif;
          --mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
          --page: min(68rem, calc(100% - 2 * var(--gutter)));
          --gutter: clamp(1.25rem, 4vw, 3rem);
        }
        * { box-sizing: border-box; }
        html, body { margin: 0; min-height: 100%; }
        body {
          background: var(--ink);
          color: var(--paper);
          font-family: var(--sans);
          font-size: 1rem;
          line-height: 1.5;
          -webkit-font-smoothing: antialiased;
        }
        a { color: inherit; text-decoration: underline; text-underline-offset: 0.18em; }
        a:hover { text-decoration-thickness: 2px; }
        :focus-visible { outline: 1px solid var(--paper); outline-offset: 3px; }
        .skip {
          position: absolute; left: var(--gutter); top: 0.75rem;
          transform: translateY(-150%);
        }
        .skip:focus { transform: none; }
        .frame { width: var(--page); margin: 0 auto; padding-bottom: 4.5rem; }
        header { padding: 2.4rem 0 1.4rem; }
        .mark { margin: 0 0 1.1rem; color: var(--paper-mute); font-size: 0.78rem; }
        h1 {
          margin: 0 0 0.7rem;
          font-family: var(--serif);
          font-size: clamp(2.05rem, 4vw, 2.9rem);
          font-weight: 400;
          letter-spacing: -0.03em;
          line-height: 1.05;
        }
        .lede { margin: 0; max-width: 38rem; color: var(--paper-mute); }
        nav {
          display: flex;
          flex-wrap: wrap;
          gap: 1.1rem 1.4rem;
          padding: 0.9rem 0;
          border-top: 1px solid var(--rule);
          border-bottom: 1px solid var(--rule);
        }
        nav a { text-decoration: none; color: var(--paper-mute); }
        nav a[aria-current="page"] { color: var(--paper); text-decoration: underline; }
        .stage {
          display: grid;
          grid-template-columns: minmax(16.5rem, 21.5rem) minmax(0, 1fr);
          border-bottom: 1px solid var(--rule);
        }
        aside {
          padding: 1.9rem 1.75rem 2.1rem 0;
          border-right: 1px solid var(--rule);
        }
        .work { padding: 1.9rem 0 2.1rem 2.4rem; }
        .panel { padding: 1.8rem 0 2.2rem; }
        h2 {
          margin: 0 0 0.55rem;
          font-family: var(--serif);
          font-size: 1.35rem;
          font-weight: 400;
          letter-spacing: -0.02em;
        }
        .hint { margin: 0 0 1.35rem; color: var(--paper-faint); font-size: 0.86rem; line-height: 1.55; }
        label { display: block; margin: 1.15rem 0 0.4rem; color: var(--paper-mute); font-size: 0.78rem; }
        input, select, textarea, button { font: inherit; }
        input, select, textarea {
          width: 100%;
          margin: 0;
          padding: 0.7rem 0.15rem;
          border: 0;
          border-bottom: 1px solid var(--rule);
          border-radius: 0;
          background: #12110f;
          color: #ece7dc;
          color-scheme: dark;
        }
        option { background-color: #12110f; color: #ece7dc; }
        textarea { min-height: 10.5rem; padding-top: 0.8rem; resize: vertical; line-height: 1.55; }
        input:focus-visible, select:focus-visible, textarea:focus-visible {
          outline: 0; border-bottom-color: var(--paper);
        }
        ::placeholder { color: var(--paper-faint); opacity: 1; }
        .picker { position: relative; }
        .picker-select {
          position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
          overflow: hidden; clip: rect(0 0 0 0); clip-path: inset(50%); border: 0; white-space: nowrap;
        }
        button.picker-toggle {
          display: flex; align-items: center; justify-content: space-between; gap: 0.75rem;
          width: 100%; min-height: 2.7rem; padding: 0.55rem 0.1rem; border: 0;
          border-bottom: 1px solid var(--rule); background: transparent; color: #ece7dc;
          font-weight: 400; letter-spacing: 0; text-align: left;
        }
        button.picker-toggle:hover { background: transparent; color: #ece7dc; filter: none; }
        button.picker-toggle[aria-expanded="true"] { border-bottom-color: #ece7dc; }
        button.picker-toggle::after {
          content: ""; flex: 0 0 auto; width: 0.42rem; height: 0.42rem;
          border-right: 1px solid currentColor; border-bottom: 1px solid currentColor;
          transform: translateY(-0.12rem) rotate(45deg);
        }
        .picker-list {
          position: absolute; z-index: 5; left: 0; right: 0; top: calc(100% + 0.35rem);
          max-height: 16rem; margin: 0; padding: 0.25rem 0; overflow: auto; list-style: none;
          background: #1b1a17; color: #ece7dc; border: 1px solid #ece7dc;
        }
        .picker-list[hidden] { display: none; }
        button.picker-option {
          display: block; width: 100%; min-height: 2.5rem; padding: 0.55rem 0.85rem;
          border: 0; border-radius: 0; background: #1b1a17; color: #ece7dc;
          font-weight: 400; letter-spacing: 0; text-align: left;
        }
        button.picker-option:hover,
        button.picker-option:focus-visible,
        button.picker-option[aria-selected="true"] {
          background: #ece7dc; color: #12110f; filter: none;
        }
        .actions {
          display: flex; flex-wrap: wrap; align-items: center; gap: 0.65rem 0.75rem; margin-top: 1.35rem;
        }
        button {
          appearance: none; min-height: 2.7rem; padding: 0.65rem 1.05rem;
          border: 1px solid var(--paper); border-radius: 0; background: var(--paper); color: var(--ink);
          font-size: 0.86rem; font-weight: 500; letter-spacing: 0.01em; cursor: pointer;
        }
        button.ghost { background: transparent; color: var(--paper); }
        button:hover { filter: brightness(1.06); }
        button.ghost:hover { background: var(--paper); color: var(--ink); filter: none; }
        button:disabled { opacity: 0.45; cursor: wait; }
        .quiet { color: var(--paper-faint); font-size: 0.82rem; }
        .using {
          margin: 0 0 1.4rem;
          padding: 0 0 1.15rem;
          border-bottom: 1px solid var(--rule);
        }
        .using h3 {
          margin: 0 0 0.35rem;
          font-family: var(--serif);
          font-size: 1.05rem;
          font-weight: 400;
        }
        .using p { margin: 0; color: var(--paper-mute); font-size: 0.9rem; overflow-wrap: anywhere; }
        .facts { margin: 1.8rem 0 0; padding: 0; border-top: 1px solid var(--rule); }
        .facts > div {
          display: grid; grid-template-columns: 7.25rem minmax(0, 1fr); gap: 0.7rem 1rem;
          padding: 0.72rem 0; border-bottom: 1px solid var(--rule); font-size: 0.8rem;
        }
        dt { margin: 0; color: var(--paper-faint); font-weight: 400; }
        dd { margin: 0; overflow-wrap: anywhere; }
        .status { min-height: 1.2rem; margin: 1.1rem 0 0; color: var(--paper-faint); font-size: 0.82rem; }
        .ok { color: var(--paper-mute); }
        .error { color: var(--paper); box-shadow: inset 2px 0 0 var(--paper); padding-left: 0.7rem; }
        pre {
          min-height: 7.5rem; margin: 1.15rem 0 0; padding: 1.1rem 0; border-top: 1px solid var(--rule);
          background: transparent; color: var(--paper); font-family: var(--mono); font-size: 0.86rem;
          line-height: 1.6; white-space: pre-wrap; overflow-wrap: anywhere;
        }
        .metrics {
          display: grid; grid-template-columns: repeat(auto-fit, minmax(9.5rem, 1fr));
          gap: 0; border-top: 1px solid var(--rule); margin: 1.4rem 0 1.8rem;
        }
        .metrics div { padding: 1rem 1.1rem 1rem 0; border-bottom: 1px solid var(--rule); }
        .metrics dt { display: block; margin-bottom: 0.35rem; }
        .metrics dd { font-family: var(--serif); font-size: 1.6rem; letter-spacing: -0.03em; }
        table { width: 100%; border-collapse: collapse; font-size: 0.88rem; }
        th, td { padding: 0.7rem 0.75rem 0.7rem 0; border-bottom: 1px solid var(--rule); text-align: left; vertical-align: top; }
        th { color: var(--paper-faint); font-weight: 400; }
        td button { min-height: 2.1rem; padding: 0.35rem 0.7rem; font-size: 0.78rem; }
        .empty { color: var(--paper-faint); padding: 1.2rem 0; }
        .split { display: grid; grid-template-columns: minmax(16rem, 20rem) minmax(0, 1fr); gap: 0 2.4rem; }
        .lane-row {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 5.5rem auto;
          gap: 0.65rem 0.85rem;
          align-items: end;
          margin-top: 0.35rem;
        }
        .lane-row button { min-height: 2.3rem; padding: 0.4rem 0.7rem; }
        .conn-title { margin-top: 2.4rem; padding-top: 1.4rem; border-top: 1px solid var(--rule); }
        #activity-log {
          min-height: 14rem;
          max-height: 30rem;
          overflow: auto;
          padding: 0.9rem 0;
          border-top: 1px solid var(--rule);
          font-family: var(--mono);
          font-size: 0.8rem;
          line-height: 1.7;
        }
        #activity-log .ev { display: flex; gap: 0.75rem; padding: 0.12rem 0; }
        #activity-log .ev .t { color: var(--paper-faint); flex: 0 0 auto; }
        #activity-log .ev.ok .m { color: #b8e0b8; }
        #activity-log .ev.warn .m { color: #e6d29a; }
        #activity-log .ev.error .m { color: #f0a8a0; }
        #activity-log .ev .m { overflow-wrap: anywhere; }
        [hidden] { display: none !important; }
        @media (max-width: 840px) {
          .stage, .split { grid-template-columns: 1fr; }
          aside { padding: 1.6rem 0; border-right: 0; border-bottom: 1px solid var(--rule); }
          .work { padding: 1.6rem 0 2rem; }
        }
        @media (prefers-reduced-motion: reduce) {
          *, *::before, *::after { transition: none !important; animation: none !important; }
        }
      </style>
    </head>
    <body>
      <a class="skip" href="#overview">Skip to content</a>
      <div class="frame">
        <header>
          <p class="mark">Learning Agent</p>
          <h1 id="page-title">Overview</h1>
          <p class="lede" id="page-lede">Durable repository learning: register a source, queue a pass, and watch run state without giving the browser tools or secrets on the server.</p>
        </header>
        <nav aria-label="Primary">
          <a href="#overview">Overview</a>
          <a href="#graphs">Graphs</a>
          <a href="#runs">Runs</a>
          <a href="#activity">Activity</a>
          <a href="#settings">Settings</a>
          <a href="#model">Model playground</a>
        </nav>
        <section class="panel" data-view="overview" id="overview">
          <dl class="metrics">
            <div><dt>Service</dt><dd id="metric-live">—</dd></div>
            <div><dt>Database</dt><dd id="metric-ready">—</dd></div>
            <div><dt>Graphs</dt><dd id="metric-repos">—</dd></div>
            <div><dt>Queued</dt><dd id="metric-queued">—</dd></div>
            <div><dt>Active</dt><dd id="metric-active">—</dd></div>
            <div><dt>Workers</dt><dd id="metric-workers">—</dd></div>
            <div><dt>Outbox</dt><dd id="metric-outbox">—</dd></div>
          </dl>
          <p class="hint" id="overview-model">Detecting Codebase Memory graphs and playground model…</p>
          <div class="actions">
            <button type="button" class="js-start-learning">Start learning</button>
            <button type="button" class="ghost js-relearn-learning">Re-learn all</button>
            <button type="button" class="ghost js-stop-learning">Stop</button>
          </div>
          <div id="overview-status" class="status" role="status"></div>
        </section>
        <section class="panel" data-view="graphs" hidden>
          <h2>Codebase Memory</h2>
          <p class="hint" id="graph-hint">Loading every Codebase Memory graph…</p>
          <div class="actions">
            <button type="button" class="js-start-learning">Start learning</button>
            <button type="button" class="ghost js-relearn-learning">Re-learn all</button>
            <button type="button" class="ghost js-stop-learning">Stop</button>
          </div>
          <label for="graph-filter">Filter</label>
          <input id="graph-filter" placeholder="Filter by name or path" autocomplete="off">
          <table>
            <thead><tr><th>Graph</th><th>Memory</th><th>Status</th></tr></thead>
            <tbody id="graph-rows"></tbody>
          </table>
          <p class="empty" id="graph-empty">No graphs from Codebase Memory.</p>
          <div id="graph-status" class="status" role="status"></div>
        </section>
        <section class="panel" data-view="runs" hidden>
          <h2>Runs</h2>
          <p class="hint">Cancel sets durable intent. Resolve blocker returns a blocked run to queued when the domain allows it.</p>
          <table>
            <thead><tr><th>Pass</th><th>Repository</th><th>State</th><th>Outcome</th><th></th></tr></thead>
            <tbody id="run-rows"></tbody>
          </table>
          <p class="empty" id="run-empty">No runs yet.</p>
          <div id="run-status" class="status" role="status"></div>
        </section>
        <section class="panel" data-view="activity" hidden>
          <h2>Activity</h2>
          <p class="hint">Live feed of scheduler and worker events. Passes, requeues, model calls, drains — newest at the bottom.</p>
          <div id="activity-log" aria-live="polite"></div>
        </section>
        <section class="panel" data-view="settings" hidden>
          <h2>Workers</h2>
          <p class="hint">Each slot learns one graph. Pick models from the playground list, then split slots across them. Save writes this on the server.</p>
          <div id="lanes"></div>
          <div class="actions">
            <button id="add-lane" class="ghost" type="button">Add model</button>
            <button id="refresh-lanes" class="ghost" type="button">Refresh models</button>
            <button id="save-runtime" type="button">Save</button>
          </div>
          <label for="worker-slots">Total slots</label>
          <input id="worker-slots" type="number" min="1" max="64" step="1" value="1">
          <p class="hint" id="lane-total">1 of 64 slots</p>
          <dl class="facts">
            <div><dt>Active now</dt><dd id="settings-active">—</dd></div>
            <div><dt>Queued</dt><dd id="settings-queued">—</dd></div>
          </dl>
          <div id="settings-status" class="status" role="status"></div>
          <h2 class="conn-title">Learning connection (server-side)</h2>
          <p class="hint">The playground connection syncs here automatically — the fleet uses it like an env. The API key is stored on the server and never sent back to a browser.</p>
          <label for="server-base-url">Server base URL</label>
          <input id="server-base-url" type="url" autocomplete="url" placeholder="http://127.0.0.1:11434/v1" spellcheck="false">
          <label for="server-api-key">Server API key</label>
          <input id="server-api-key" type="password" autocomplete="off" placeholder="Optional · saved on the server">
          <label for="server-model">Default model</label>
          <input id="server-model" list="server-models" spellcheck="false" placeholder="e.g. qwen3:8b">
          <datalist id="server-models"></datalist>
          <div class="actions">
            <button id="save-connection" type="button">Save connection</button>
            <button id="probe-connection" class="ghost" type="button">Test connection</button>
          </div>
          <div id="connection-status" class="status" role="status"></div>
        </section>
        <section class="panel" data-view="model" hidden>
          <div class="stage">
            <aside>
              <h2>Connection</h2>
              <p class="hint">Save these settings in this browser, or clear them at any time. Saved API keys remain in this browser profile; use this only on a trusted machine.</p>
              <label for="base-url">OpenAI-compatible base URL</label>
              <input id="base-url" type="url" autocomplete="url" placeholder="https://api.openai.com/v1" spellcheck="false">
              <label for="api-key">API key</label>
              <input id="api-key" type="password" autocomplete="off" placeholder="Optional · saved only here">
              <div class="actions">
                <button id="save" type="button">Save in this browser</button>
                <button id="clear" class="ghost" type="button">Clear saved</button>
              </div>
              <div class="actions">
                <button id="load" class="ghost" type="button">Refresh models</button>
                <a class="quiet" href="/health/live" target="_blank" rel="noreferrer">Live health</a>
              </div>
              <div id="model-status" class="status" role="status">Enter a model URL and refresh models.</div>
              <dl class="facts">
                <div><dt>Status</dt><dd id="connection-ready">—</dd></div>
                <div><dt>Using</dt><dd id="configured-model">—</dd></div>
                <div><dt>Endpoint</dt><dd id="endpoint">—</dd></div>
                <div><dt>API key</dt><dd id="key-status">—</dd></div>
                <div><dt>Models</dt><dd id="model-count">not loaded</dd></div>
              </dl>
              <p class="hint" id="server-default" hidden></p>
            </aside>
            <section class="work">
              <h2>Reply</h2>
              <div class="using" id="using-card">
                <h3>Using</h3>
                <p id="using-line">Set a URL on the left, refresh models, then pick one. This page uses the browser connection, not server env.</p>
              </div>
              <p class="hint">One bounded reply. Nothing here can run tools or write notes.</p>
              <label id="model-label" for="model">Model</label>
              <div class="picker" id="model-picker">
                <select id="model" class="picker-select" tabindex="-1" aria-hidden="true"><option value="">Select a model after refreshing the list</option></select>
                <button type="button" class="picker-toggle" id="model-toggle" aria-labelledby="model-label" aria-haspopup="listbox" aria-expanded="false" aria-controls="model-list">Select a model after refreshing the list</button>
                <div class="picker-list" id="model-list" role="listbox" aria-labelledby="model-label" hidden></div>
              </div>
              <label for="prompt">Prompt</label>
              <textarea id="prompt" maxlength="16384">Respond with one short sentence confirming that the model playground is connected.</textarea>
              <div class="actions"><button id="send" type="button">Send</button></div>
              <div id="request-status" class="status" role="status"></div>
              <pre id="response" aria-live="polite">The reply will appear here.</pre>
            </section>
          </div>
        </section>
      </div>
      <script>
        const SETTINGS_KEY = "learning-agent.model-connection.v1";
        const VIEWS = {
          overview: ["Overview", "Start learning once. Workers drain every Codebase Memory graph; notes and skills land on disk, OpenViking gets the copy."],
          graphs: ["Graphs", "One Start queues every graph. Workers learn them in parallel up to the slot limit."],
          runs: ["Runs", "Inspect durable run state, cancel in-flight work, or return a blocked run to the queue."],
          activity: ["Activity", "Live feed: what the scheduler and every worker are doing right now."],
          settings: ["Settings", "Split worker slots across models. Saving writes the split on the server so a restart keeps it."],
          model: ["Model playground", "One bounded reply. The URL and key stay in this browser; they are never written to the server."]
        };
        const $ = (id) => document.getElementById(id);
        const status = (node, text, kind = "") => { node.textContent = text; node.className = `status ${kind}`; };
        const connection = () => ({ base_url: $("base-url").value.trim(), api_key: $("api-key").value.trim() });
        const updatePreview = () => {
          const current = connection();
          const model = ($("model") && $("model").value.trim()) || "";
          const ready = Boolean(current.base_url && model);
          if ($("connection-ready")) {
            $("connection-ready").textContent = ready ? "ready" : (current.base_url ? "pick a model" : "needs a URL");
          }
          if ($("configured-model")) $("configured-model").textContent = model || "not selected";
          $("endpoint").textContent = current.base_url || "not set";
          $("key-status").textContent = current.api_key ? "saved in this browser" : "not provided";
          if ($("using-line")) {
            $("using-line").textContent = ready
              ? `${model} · ${current.base_url}`
              : "Set a URL on the left, refresh models, then pick one. This page uses the browser connection, not server env.";
          }
        };
        function currentView() {
          const name = (location.hash || "#overview").slice(1);
          return VIEWS[name] ? name : "overview";
        }
        function showView() {
          const name = currentView();
          document.querySelectorAll("[data-view]").forEach((node) => { node.hidden = node.dataset.view !== name; });
          document.querySelectorAll("nav a").forEach((link) => {
            link.toggleAttribute("aria-current", link.getAttribute("href") === `#${name}`);
            if (link.getAttribute("href") === `#${name}`) link.setAttribute("aria-current", "page");
            else link.removeAttribute("aria-current");
          });
          $("page-title").textContent = VIEWS[name][0];
          $("page-lede").textContent = VIEWS[name][1];
          loadBoard();
          pollActivity();
          if (name === "model" || name === "settings") ensureModels();
          if (!window.__laActivityTimer) {
            window.__laActivityTimer = setInterval(() => { pollActivity(); }, 2000);
          }
          if (!window.__laBoardTimer) {
            window.__laBoardTimer = setInterval(() => { loadBoard(); }, 3000);
          }
        }
        let knownModels = [];
        let serverModels = [];
        let lanesDirty = false;
        const markLanesDirty = () => { lanesDirty = true; };
        async function refreshServerModels() {
          try {
            const body = await api("/v1/models/list", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({}) });
            serverModels = body.models || [];
          } catch (_) { serverModels = []; }
          const list = $("server-models");
          if (list && serverModels.length) {
            list.replaceChildren();
            for (const model of serverModels) {
              const option = document.createElement("option");
              option.value = model;
              list.append(option);
            }
          }
          return serverModels;
        }
        function closeAllPickers() {
          document.querySelectorAll(".picker-toggle").forEach((node) => node.setAttribute("aria-expanded", "false"));
          document.querySelectorAll(".picker-list").forEach((node) => { node.hidden = true; });
        }
        function closePicker() { closeAllPickers(); }
        function catalogModels() {
          const fromSelect = Array.from(($("model") && $("model").options) || []).map((option) => option.value).filter(Boolean);
          const merged = [];
          for (const model of knownModels.concat(serverModels).concat(fromSelect)) {
            if (model && !merged.includes(model)) merged.push(model);
          }
          return merged;
        }
        function fillPickerList(list, models, selected, onChoose) {
          list.replaceChildren();
          const items = models.length ? models : [];
          if (!items.length) {
            const empty = document.createElement("button");
            empty.type = "button";
            empty.className = "picker-option";
            empty.disabled = true;
            empty.textContent = "Refresh models in Model playground first";
            list.append(empty);
            return;
          }
          for (const model of items) {
            const item = document.createElement("button");
            item.type = "button";
            item.className = "picker-option";
            item.setAttribute("role", "option");
            item.dataset.value = model;
            item.setAttribute("aria-selected", model === selected ? "true" : "false");
            item.textContent = model;
            item.addEventListener("click", () => onChoose(model));
            list.append(item);
          }
        }
        function openPickerAt(toggle, list, selected, onChoose) {
          const opening = list.hidden;
          closeAllPickers();
          if (!opening) return;
          fillPickerList(list, catalogModels(), selected, onChoose);
          toggle.setAttribute("aria-expanded", "true");
          list.hidden = false;
          const focused = list.querySelector('[aria-selected="true"]') || list.querySelector(".picker-option");
          if (focused) focused.focus();
        }
        function optionButtons() { return Array.from($("model-list").querySelectorAll(".picker-option")); }
        function syncPicker() {
          const select = $("model");
          const current = select.selectedOptions[0];
          $("model-toggle").textContent = current && current.value ? current.textContent : "Select a model…";
        }
        function chooseModel(value) {
          $("model").value = value;
          closeAllPickers();
          syncPicker();
          persistConnection();
          syncConnectionToServer();
          loadBoard();
          $("model-toggle").focus();
        }
        function openPicker() {
          openPickerAt($("model-toggle"), $("model-list"), $("model").value, chooseModel);
        }
        function setModels(models, selected = $("model").value) {
          knownModels = Array.from(new Set((models || []).filter(Boolean)));
          const select = $("model");
          select.replaceChildren(new Option("Select a model…", ""));
          for (const model of knownModels) select.add(new Option(model, model));
          if (selected && !knownModels.includes(selected)) {
            select.add(new Option(`${selected} (saved)`, selected));
            knownModels.push(selected);
          }
          select.value = selected || "";
          $("model-count").textContent = knownModels.length ? `${knownModels.length} available` : "not loaded";
          closeAllPickers();
          syncPicker();
          updatePreview();
          renderLanes();
        }
        function restoreSettings() {
          try {
            const saved = JSON.parse(localStorage.getItem(SETTINGS_KEY) || "null");
            if (saved && typeof saved === "object") {
              if (typeof saved.base_url === "string") $("base-url").value = saved.base_url;
              if (typeof saved.api_key === "string") $("api-key").value = saved.api_key;
              const savedModels = Array.isArray(saved.models) ? saved.models.filter((model) => typeof model === "string") : [];
              setModels(savedModels, typeof saved.model === "string" ? saved.model : "");
            }
          } catch (_) { /* Storage may be disabled by the browser. */ }
          updatePreview();
          syncPicker();
        }
        function persistConnection() {
          try {
            localStorage.setItem(SETTINGS_KEY, JSON.stringify({
              ...connection(),
              model: $("model").value,
              models: catalogModels()
            }));
          } catch (_) { /* Storage may be disabled by the browser. */ }
        }
        // Browser storage is the source of truth for the connection: mirror it to
        // the server so the learning fleet uses the same endpoint like an env.
        async function syncConnectionToServer() {
          const c = connection();
          if (!c.base_url) return;
          try {
            await api("/v1/settings", {
              method: "PUT",
              headers: { "content-type": "application/json" },
              body: JSON.stringify({
                model: { base_url: c.base_url, api_key: c.api_key, model: ($("model").value || "").trim() }
              })
            });
          } catch (_) { /* Tokens required outside local dogfood; server env still rules. */ }
        }
        async function saveSettings() {
          persistConnection();
          updatePreview();
          status($("model-status"), "Settings saved in this browser.", "ok");
          if (connection().base_url) await refreshModels();
          await syncConnectionToServer();
          await loadBoard();
        }
        function clearSettings() {
          try { localStorage.removeItem(SETTINGS_KEY); } catch (_) { /* Nothing else to clear. */ }
          $("base-url").value = ""; $("api-key").value = ""; setModels([], ""); updatePreview();
          status($("model-status"), "Saved connection settings cleared.", "ok");
        }
        async function api(path, options = {}) {
          const headers = Object.assign({ accept: "application/json" }, options.headers || {});
          const response = await fetch(path, Object.assign({}, options, { headers }));
          const body = await response.json().catch(() => ({}));
          if (!response.ok) throw new Error(body.message || body.error || `HTTP ${response.status}`);
          return body;
        }
        async function refreshModels() {
          updatePreview();
          const current = connection();
          if (!current.base_url) { status($("model-status"), "Enter a model URL first.", "error"); return; }
          status($("model-status"), "Loading models…");
          try {
            const body = await api("/v1/models/list", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(current) });
            const models = body.models || [];
            const selected = $("model").value || models[0] || "";
            setModels(models, selected);
            persistConnection();
            status($("model-status"), `${models.length} model${models.length === 1 ? "" : "s"} loaded.`, "ok");
            await loadBoard();
          } catch (error) { status($("model-status"), error.message, "error"); }
        }
        async function ensureModels() {
          if (!connection().base_url) return;
          const select = $("model");
          if (select && select.options.length <= 1) await refreshModels();
        }
        async function applyCatalog() {
          const body = await api("/v1/models");
          const configured = (body.models && body.models[0]) || {};
          if ($("adapter")) $("adapter").textContent = configured.adapter || "openai_compatible";
          if (!$("base-url").value && configured.endpoint) $("base-url").value = configured.endpoint;
          if (!$("model").value && configured.model) setModels([], configured.model);
          if ($("server-default")) {
            if (configured.endpoint || configured.model) {
              $("server-default").hidden = false;
              $("server-default").textContent =
                `Server default ${configured.model || "unset"} at ${configured.endpoint || "unset"}. The fields above override it in this browser.`;
            } else {
              $("server-default").hidden = true;
            }
          }
          updatePreview();
          return configured;
        }
        async function load() {
          status($("model-status"), "Loading model status…");
          try {
            await applyCatalog();
            if (connection().base_url) await refreshModels();
            else status($("model-status"), "Enter a model URL and save it here.");
            await loadBoard();
          } catch (error) { status($("model-status"), error.message, "error"); }
        }
        async function send() {
          const button = $("send"); button.disabled = true; status($("request-status"), "Calling the provider…"); $("response").textContent = "";
          try {
            const model = $("model").value.trim();
            const request = { prompt: $("prompt").value, ...(model ? { model } : {}), ...connection() };
            const body = await api("/v1/models/test", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(request) });
            $("response").textContent = body.text || "(empty response)";
            status($("request-status"), `${body.model} · ${body.stop_reason || "completed"}`, "ok");
          } catch (error) { status($("request-status"), error.message, "error"); } finally { button.disabled = false; }
        }
        let lastSeq = 0;
        async function pollActivity() {
          try {
            const body = await api(`/v1/activity?since=${lastSeq}`);
            const events = body.events || [];
            if (!events.length) return;
            lastSeq = events[events.length - 1].seq;
            const log = $("activity-log");
            if (!log) return;
            const stick = log.scrollHeight - log.scrollTop - log.clientHeight < 40;
            for (const ev of events) {
              const row = document.createElement("div");
              row.className = `ev ${ev.kind || "info"}`;
              const time = new Date(ev.ts).toLocaleTimeString();
              row.innerHTML = `<span class="t">${time}</span><span class="m">${escapeHtml(ev.message)}</span>`;
              log.append(row);
            }
            while (log.children.length > 400) log.removeChild(log.firstChild);
            if (stick) log.scrollTop = log.scrollHeight;
          } catch (_) { /* Feed errors never break the board. */ }
        }
        function count(map, key) { return (map && map[key]) || 0; }
        function activeCount(counts) {
          return ["claimed","preflight","note_drafting","note_published","exploring","evidence_gathering","synthesizing","validating","publishing","recording_result"]
            .reduce((sum, key) => sum + count(counts, key), 0);
        }
        let lastBoard = { graphs: [], memory: {}, worker_slots: 1 };
        function playgroundModel() {
          let saved = {};
          try { saved = JSON.parse(localStorage.getItem(SETTINGS_KEY) || "null") || {}; } catch (_) {}
          return {
            model: ($("model") && $("model").value.trim()) || saved.model || "",
            url: ($("base-url") && $("base-url").value.trim()) || saved.base_url || ""
          };
        }
        function renderGraphs(body) {
          lastBoard = body || lastBoard;
          const graphs = (lastBoard.graphs || []).slice().sort((a, b) => (a.name || "").localeCompare(b.name || ""));
          const memory = lastBoard.memory || {};
          const q = (($("graph-filter") && $("graph-filter").value) || "").trim().toLowerCase();
          const shown = q ? graphs.filter((g) => ((g.name || "") + " " + (g.root || "")).toLowerCase().includes(q)) : graphs;
          const rows = $("graph-rows");
          rows.replaceChildren();
          $("graph-empty").hidden = shown.length > 0;
          $("graph-hint").textContent = memory.available === false
            ? "Codebase Memory is not connected."
            : `${shown.length} of ${graphs.length} graphs. Start queues every graph; workers drain the queue.`;
          for (const graph of shown) {
            const tr = document.createElement("tr");
            const learning = graph.learning || "idle";
            tr.innerHTML = `<td>${escapeHtml(graph.name)}<div class="quiet">${escapeHtml(graph.root || "")}</div></td><td>${memory.available === false ? "offline" : "ready"}</td><td>${escapeHtml(learning)}</td>`;
            rows.append(tr);
          }
        }
        function renderRuns(runs) {
          const rows = $("run-rows");
          rows.replaceChildren();
          $("run-empty").hidden = runs.length > 0;
          for (const run of runs) {
            const tr = document.createElement("tr");
            const outcome = run.blocked_reason || run.failure_class || run.outcome || "—";
            const stateLabel = run.state === "completed" ? "finished" : run.state;
            tr.innerHTML = `<td>${run.pass_number}</td><td>${escapeHtml(run.repository || run.repository_id)}</td><td>${escapeHtml(stateLabel)}${run.cancel_requested ? " · cancel" : ""}</td><td>${escapeHtml(outcome)}</td><td></td>`;
            const terminal = ["completed", "failed", "cancelled", "orphaned", "partial"].includes(run.state);
            if (!terminal && !run.cancel_requested) {
              const cancel = document.createElement("button");
              cancel.type = "button";
              cancel.className = "ghost";
              cancel.textContent = "Cancel";
              cancel.addEventListener("click", () => cancelRun(run.id));
              tr.lastElementChild.append(cancel);
            }
            if (run.state === "blocked") {
              const resolve = document.createElement("button");
              resolve.type = "button";
              resolve.className = "ghost";
              resolve.textContent = "Resolve";
              resolve.addEventListener("click", () => resolveRun(run.id));
              tr.lastElementChild.append(resolve);
            }
            rows.append(tr);
          }
        }
        function escapeHtml(value) {
          return String(value == null ? "" : value)
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
        }
        let lanesState = [{ model: "", slots: 1 }];
        function laneEditing() {
          const node = document.activeElement;
          return node && node.closest && node.closest("#lanes, #worker-slots");
        }
        function nextLaneModel() {
          const used = new Set(lanesState.map((lane) => lane.model).filter(Boolean));
          return catalogModels().find((model) => !used.has(model)) || "";
        }
        function syncLanesFromDom() {
          const rows = Array.from(document.querySelectorAll("#lanes .lane-row"));
          if (!rows.length) return;
          lanesState = rows.map((row) => ({
            model: row.dataset.model || "",
            slots: Number((row.querySelector(".lane-slots") || {}).value || 1)
          }));
        }
        function renderLanes() {
          const root = $("lanes");
          if (!root) return;
          root.replaceChildren();
          lanesState.forEach((lane, index) => {
            const row = document.createElement("div");
            row.className = "lane-row";
            row.dataset.model = lane.model || "";
            row.innerHTML = `<div><label>Model</label><div class="picker lane-picker"><button type="button" class="picker-toggle lane-toggle" aria-haspopup="listbox" aria-expanded="false">${escapeHtml(lane.model || "Select a model…")}</button><div class="picker-list lane-list" role="listbox" hidden></div></div></div><div><label>Slots</label><input class="lane-slots" type="number" min="1" max="64" step="1" value="${Number(lane.slots) || 1}"></div><button type="button" class="ghost lane-remove">Remove</button>`;
            const toggle = row.querySelector(".lane-toggle");
            const list = row.querySelector(".lane-list");
            toggle.addEventListener("click", () => {
              openPickerAt(toggle, list, row.dataset.model, (value) => {
                row.dataset.model = value;
                lanesState[index] = { model: value, slots: Number(row.querySelector(".lane-slots").value) || 1 };
                markLanesDirty();
                toggle.textContent = value;
                closeAllPickers();
                toggle.focus();
              });
            });
            row.querySelector(".lane-remove").disabled = lanesState.length === 1;
            row.querySelector(".lane-remove").addEventListener("click", () => {
              syncLanesFromDom();
              if (lanesState.length === 1) return;
              lanesState.splice(index, 1);
              markLanesDirty();
              renderLanes();
            });
            row.querySelector(".lane-slots").addEventListener("change", () => {
              syncLanesFromDom();
              markLanesDirty();
              const total = lanesState.reduce((sum, item) => sum + (Number(item.slots) || 0), 0);
              $("worker-slots").value = String(total);
              if ($("lane-total")) $("lane-total").textContent = `${total} of 64 slots`;
            });
            root.append(row);
          });
          const total = lanesState.reduce((sum, item) => sum + (Number(item.slots) || 0), 0);
          if ($("worker-slots") && document.activeElement !== $("worker-slots")) $("worker-slots").value = String(total);
          if ($("lane-total")) $("lane-total").textContent = `${total} of 64 slots`;
        }
        function applyRuntime(body) {
          const slots = body.worker_slots || 1;
          const conn = body.model_connection;
          if (conn && conn.base_url) {
            if (document.activeElement !== $("server-base-url")) $("server-base-url").value = conn.base_url;
            if (document.activeElement !== $("server-model") && conn.model) $("server-model").value = conn.model;
            if ($("connection-status") && !$("connection-status").dataset.custom) {
              status($("connection-status"), `Server connection: ${conn.base_url}${conn.model ? " · " + conn.model : ""}${conn.api_key_set ? " · key saved" : " · no key"}.`);
            }
          }
          if (!laneEditing() && !lanesDirty) {
            if (Array.isArray(body.lanes) && body.lanes.length) {
              lanesState = body.lanes.map((lane) => ({ model: lane.model || "", slots: Number(lane.slots) || 1 }));
            } else {
              lanesState = [{ model: "", slots: slots }];
            }
            if (lanesState.length === 1 && !lanesState[0].model) {
              const selected = ($("model") && $("model").value.trim()) || playgroundModel().model;
              if (selected) lanesState[0].model = selected;
            }
            renderLanes();
          }
          if ($("settings-active")) $("settings-active").textContent = String(activeCount(body.run_counts));
          if ($("settings-queued")) $("settings-queued").textContent = String(count(body.run_counts, "queued"));
          if ($("metric-workers")) $("metric-workers").textContent = `${activeCount(body.run_counts)} / ${slots}`;
        }
        async function saveRuntime() {
          syncLanesFromDom();
          const lanes = lanesState.map((lane) => ({
            model: (lane.model || "").trim(),
            slots: Number(lane.slots)
          }));
          const payload = { lanes };
          const serverUrl = $("server-base-url").value.trim();
          if (serverUrl) {
            payload.model = {
              base_url: serverUrl,
              api_key: $("server-api-key").value.trim(),
              model: $("server-model").value.trim()
            };
          }
          try {
            const body = await api("/v1/settings", {
              method: "PUT",
              headers: { "content-type": "application/json" },
              body: JSON.stringify(payload)
            });
            const parts = (body.lanes || []).map((lane) => `${lane.slots} on ${lane.model || "default"}`);
            status($("settings-status"), `${body.worker_slots} slots live${parts.length ? ": " + parts.join(", ") : ""}.`, "ok");
            lanesDirty = false;
            await loadBoard();
          } catch (error) {
            status($("settings-status"), error.message, "error");
          }
        }
        async function saveConnection() {
          const serverUrl = $("server-base-url").value.trim();
          if (!serverUrl) {
            status($("connection-status"), "Enter a base URL first.", "error");
            return;
          }
          try {
            const body = await api("/v1/settings", {
              method: "PUT",
              headers: { "content-type": "application/json" },
              body: JSON.stringify({
                model: {
                  base_url: serverUrl,
                  api_key: $("server-api-key").value.trim(),
                  model: $("server-model").value.trim()
                }
              })
            });
            const conn = body.model_connection || {};
            status($("connection-status"), `Saved. Workers will call ${conn.base_url}${conn.model ? " with " + conn.model : ""}.`, "ok");
            await refreshServerModels();
            await loadBoard();
          } catch (error) {
            status($("connection-status"), error.message, "error");
          }
        }
        async function testConnection() {
          const serverUrl = $("server-base-url").value.trim();
          if (!serverUrl) {
            status($("connection-status"), "Enter a base URL first.", "error");
            return;
          }
          status($("connection-status"), "Listing models through the typed connection…");
          try {
            const probe = { base_url: serverUrl, api_key: $("server-api-key").value.trim() };
            const body = await api("/v1/models/list", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(probe) });
            const models = body.models || [];
            const list = $("server-models");
            list.replaceChildren();
            for (const model of models) {
              const option = document.createElement("option");
              option.value = model;
              list.append(option);
            }
            status($("connection-status"), `Reachable. ${models.length} model${models.length === 1 ? "" : "s"}: ${models.slice(0, 5).join(", ")}${models.length > 5 ? "…" : ""}.`, "ok");
          } catch (error) {
            status($("connection-status"), `Unreachable: ${error.message}`, "error");
          }
        }
        async function loadBoard() {
          try {
            const body = await api("/v1/overview");
            $("metric-live").textContent = body.health && body.health.live ? "live" : "down";
            $("metric-ready").textContent = body.health && body.health.ready ? "ready" : "not ready";
            $("metric-repos").textContent = (body.graphs || []).length;
            $("metric-queued").textContent = count(body.run_counts, "queued");
            $("metric-active").textContent = activeCount(body.run_counts);
            $("metric-outbox").textContent = body.outbox_backlog ?? 0;
            applyRuntime(body);
            const play = playgroundModel();
            const server = body.model || {};
            const name = play.model || server.model || "";
            const url = play.url || server.endpoint || "";
            const memory = body.memory && body.memory.available
              ? `${(body.graphs || []).length} Codebase Memory graphs.`
              : "Codebase Memory offline.";
            $("overview-model").textContent = name
              ? `${memory} Model ${name}${url ? " · " + url : ""}.`
              : `${memory} Save a model in Model playground.`;
            renderGraphs(body);
            renderRuns(body.runs || []);
          } catch (error) {
            status($("overview-status"), error.message, "error");
          }
        }
        async function startLearning() {
          document.querySelectorAll(".js-start-learning").forEach((node) => { node.disabled = true; });
          status($("graph-status"), "Queueing every Codebase Memory graph…");
          status($("overview-status"), "Queueing every Codebase Memory graph…");
          try {
            const body = await api("/v1/graphs/start-all", { method: "POST" });
            let msg;
            if (body.queued === 0 && (body.drained || 0) > 0) {
              msg = `All ${body.drained} graph${body.drained === 1 ? " is" : "s are"} squeezed. Use Re-learn all to run fresh passes.`;
            } else {
              msg = `Queued ${body.queued} of ${body.graphs} graphs${body.drained ? `, ${body.drained} already squeezed` : ""}.`;
            }
            status($("graph-status"), msg, body.queued === 0 ? "" : "ok");
            status($("overview-status"), msg, body.queued === 0 ? "" : "ok");
            await loadBoard();
          } catch (error) {
            status($("graph-status"), error.message, "error");
            status($("overview-status"), error.message, "error");
          } finally {
            document.querySelectorAll(".js-start-learning").forEach((node) => { node.disabled = false; });
          }
        }
        async function relearnLearning() {
          document.querySelectorAll(".js-relearn-learning").forEach((node) => { node.disabled = true; });
          status($("graph-status"), "Re-opening completed graphs for a fresh pass…");
          status($("overview-status"), "Re-opening completed graphs for a fresh pass…");
          try {
            const body = await api("/v1/graphs/relearn-all", { method: "POST" });
            const msg = `Re-learning ${body.queued} of ${body.graphs} squeezed graph${body.graphs === 1 ? "" : "s"}.`;
            status($("graph-status"), msg, "ok");
            status($("overview-status"), msg, "ok");
            await loadBoard();
          } catch (error) {
            status($("graph-status"), error.message, "error");
            status($("overview-status"), error.message, "error");
          } finally {
            document.querySelectorAll(".js-relearn-learning").forEach((node) => { node.disabled = false; });
          }
        }
        async function stopLearning() {
          document.querySelectorAll(".js-stop-learning").forEach((node) => { node.disabled = true; });
          try {
            const body = await api("/v1/graphs/stop-all", { method: "POST" });
            const msg = `Stop requested${body.cancelled ? " for " + body.cancelled + " in-flight run" + (body.cancelled === 1 ? "" : "s") : ""}.`;
            status($("graph-status"), msg, "ok");
            status($("overview-status"), msg, "ok");
            await loadBoard();
          } catch (error) {
            status($("graph-status"), error.message, "error");
            status($("overview-status"), error.message, "error");
          } finally {
            document.querySelectorAll(".js-stop-learning").forEach((node) => { node.disabled = false; });
          }
        }
        async function cancelRun(id) {
          try {
            await api(`/v1/runs/${id}/cancel`, { method: "POST" });
            status($("run-status"), "Cancel requested.", "ok");
            await loadBoard();
          } catch (error) { status($("run-status"), error.message, "error"); }
        }
        async function resolveRun(id) {
          try {
            await api(`/v1/runs/${id}/resolve-blocker`, { method: "POST" });
            status($("run-status"), "Returned to queued.", "ok");
            await loadBoard();
          } catch (error) { status($("run-status"), error.message, "error"); }
        }
                document.querySelectorAll(".js-start-learning").forEach((node) => node.addEventListener("click", startLearning));
        document.querySelectorAll(".js-relearn-learning").forEach((node) => node.addEventListener("click", relearnLearning));
        document.querySelectorAll(".js-stop-learning").forEach((node) => node.addEventListener("click", stopLearning));
        $("save").addEventListener("click", saveSettings);
        $("save-runtime").addEventListener("click", saveRuntime);
        $("save-connection").addEventListener("click", saveConnection);
        $("probe-connection").addEventListener("click", testConnection);
        $("add-lane").addEventListener("click", () => {
          syncLanesFromDom();
          lanesState.push({ model: nextLaneModel(), slots: 20 });
          markLanesDirty();
          renderLanes();
        });
        $("refresh-lanes").addEventListener("click", async () => {
          status($("settings-status"), "Loading models from the server connection…");
          await refreshServerModels();
          await refreshModels();
          const count = catalogModels().length;
          status($("settings-status"), count ? `${count} model${count === 1 ? "" : "s"} available (server + playground).` : "Save a URL in Model playground, then refresh.", count ? "ok" : "error");
        });
        $("worker-slots").addEventListener("change", () => {
          syncLanesFromDom();
          markLanesDirty();
          const n = Number($("worker-slots").value);
          if (!Number.isInteger(n) || n < 1) return;
          if (lanesState.length === 1) {
            lanesState[0].slots = n;
            renderLanes();
          }
        });
        $("clear").addEventListener("click", clearSettings);
        $("load").addEventListener("click", load);
        $("send").addEventListener("click", send);
                let persistTimer;
        const schedulePersist = () => {
          updatePreview();
          clearTimeout(persistTimer);
          persistTimer = setTimeout(() => {
            persistConnection();
            syncConnectionToServer();
            loadBoard();
          }, 300);
        };
        $("base-url").addEventListener("input", schedulePersist);
        $("api-key").addEventListener("input", schedulePersist);
        $("base-url").addEventListener("change", () => {
          persistConnection();
          if (connection().base_url) refreshModels();
          loadBoard();
        });
        if ($("graph-filter")) $("graph-filter").addEventListener("input", () => renderGraphs(lastBoard));
        $("model-toggle").addEventListener("click", () => {
          if ($("model-list").hidden) openPicker(); else closePicker();
        });
        $("model-list").addEventListener("keydown", (event) => {
          const items = optionButtons();
          const index = items.indexOf(document.activeElement);
          if (event.key === "Escape") { event.preventDefault(); closePicker(); $("model-toggle").focus(); }
          if (event.key === "ArrowDown" && items[index + 1]) { event.preventDefault(); items[index + 1].focus(); }
          if (event.key === "ArrowUp" && items[index - 1]) { event.preventDefault(); items[index - 1].focus(); }
          if (event.key === "Home" && items[0]) { event.preventDefault(); items[0].focus(); }
          if (event.key === "End" && items.length) { event.preventDefault(); items[items.length - 1].focus(); }
        });
        document.addEventListener("click", (event) => {
          if (!event.target.closest(".picker")) closeAllPickers();
        });
        window.addEventListener("hashchange", showView);
        document.addEventListener("visibilitychange", () => {
          if (document.visibilityState === "visible") loadBoard();
        });
        restoreSettings();
        showView();
        (async () => {
          await refreshServerModels();
          try { await applyCatalog(); }
          catch (error) { status($("model-status"), error.message, "error"); }
          if (connection().base_url) {
            await refreshModels();
            persistConnection();
            await syncConnectionToServer();
          } else {
            status($("model-status"), "Enter a model URL and save it here.");
          }
          await loadBoard();
        })();
      </script>
    </body>
  </html>
  """

  def page, do: @html
end
