/* CRIMP, a hangboard timer for Garmin watches
 * Copyright (C) 2026 Jan-Frode Myklebust
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Plan editor. Runs entirely in the browser and produces a programs.json
 * in the format described in docs/program-format.md.
 *
 * checkNodes() and expand() mirror scripts/check_programs.py and Programs.expand()
 * in source/Program.mc. Change them together.
 */
"use strict";

const STORAGE_KEY = "crimp-plans";
const BASE_KEY = "crimp-plans-base";   // the built-in plans (as JSON text) that STORAGE_KEY started from
// The plans compiled into the watch app. Resolves when the server root is the repo root
// (python3 -m http.server from the project directory, then open /web/).
const BUILTIN_URL = "../resources/programs/programs.json";
const TYPES = ["hang", "rest"];
const MAX_DEPTH = 4;
const PREP_SEC = 10;
const PREVIEW_LIMIT = 2000;

// ---------------------------------------------------------------- model

const saved = loadSaved();
let state = saved || newState();
let sel = { f: 0, p: null };       // p === null: the folder itself is selected
let notice = "";
let genOpen = false;
const gen = { hang: 10, rest: 30, reps: 4, sets: 3, setRest: 120 };

selectFirst();

function isObj(v) { return v !== null && typeof v === "object" && !Array.isArray(v); }
function isInt(v, min) { return Number.isInteger(v) && v >= min; }
function nonEmptyStr(v) { return typeof v === "string" && v !== ""; }

function buildPlan(g) {
  const hang = { type: "hang", sec: g.hang };
  let inner = hang;
  if (g.reps > 1) {
    inner = { repeat: g.reps, name: "Rep", do: [hang] };
    if (g.rest > 0) inner.between = [{ type: "rest", sec: g.rest }];
  }
  let outer = inner;
  if (g.sets > 1) {
    outer = { repeat: g.sets, name: "Set", do: [inner] };
    if (g.setRest > 0) outer.between = [{ type: "rest", sec: g.setRest, label: "SET REST" }];
  }
  return [outer];
}

function defaultSteps() {
  return buildPlan({ hang: 10, rest: 30, reps: 4, sets: 3, setRest: 120 });
}

function newState() {
  return { format: 1, folders: [{ name: "My plans", programs: [{ name: "Week 1", steps: defaultSteps() }] }] };
}

// Work in progress kept in this browser, or null when there is none.
function loadSaved() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const d = JSON.parse(raw);
      const ok = isObj(d) && Array.isArray(d.folders) && d.folders.length && d.folders.every(
        f => isObj(f) && Array.isArray(f.programs) && f.programs.every(p => isObj(p) && Array.isArray(p.steps)));
      if (ok) return d;
    }
  } catch (e) { /* storage unavailable or corrupt: ignore */ }
  return null;
}

// Fetch and validate resources/programs/programs.json. Throws on failure.
async function fetchBuiltin() {
  const res = await fetch(BUILTIN_URL, { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  const errs = validate(data);
  if (errs.length) throw new Error(errs[0]);
  return data;
}

function failedBuiltin(e) {
  return `Could not load the built-in plans (${e.message}). Run "python3 -m http.server" from the project root and open /web/.`;
}

function useBuiltin(data) {
  state = data;
  try { localStorage.setItem(BASE_KEY, JSON.stringify(data)); } catch (err) { /* ignore */ }
  selectFirst();
}

function savedBase() {
  try { return localStorage.getItem(BASE_KEY); } catch (e) { return null; }
}

// On startup: show the built-in plans, unless the user has edited a saved copy.
async function startup() {
  let data = null;
  let failure = "";
  try { data = await fetchBuiltin(); } catch (e) { failure = failedBuiltin(e); }

  // The placeholder from newState() or the last built-in copy means "never edited": follow the file.
  const untouched = saved && (JSON.stringify(saved) === savedBase() || JSON.stringify(saved) === JSON.stringify(newState()));

  if (!saved) {
    if (data) { useBuiltin(data); notice = "Loaded the built-in plans from resources/programs/programs.json."; }
    else notice = failure;
  } else if (data && untouched) {
    useBuiltin(data);
    notice = "Loaded the built-in plans from resources/programs/programs.json.";
  } else if (data && JSON.stringify(data) !== savedBase()) {
    notice = "Restored your edits from this browser. The built-in plans have changed since; “Built-in plans” loads them (discarding your edits).";
  } else {
    notice = failure || "Restored your edits from this browser. “Built-in plans” reloads the original ones.";
  }
  render();
}

function saveState() {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch (e) { /* ignore */ }
}

function selectFirst() {
  sel = { f: 0, p: null };
  if (state.folders.length && state.folders[0].programs.length) sel.p = 0;
}

function clampSel() {
  if (!state.folders.length) { sel = { f: 0, p: null }; return; }
  sel.f = Math.min(sel.f, state.folders.length - 1);
  const n = state.folders[sel.f].programs.length;
  if (sel.p !== null) sel.p = n ? Math.min(sel.p, n - 1) : null;
}

function move(arr, i, d) {
  const j = i + d;
  if (j < 0 || j >= arr.length) return i;
  [arr[i], arr[j]] = [arr[j], arr[i]];
  return j;
}

// Drop empty optional values so the output only holds what the app reads.
function cleanNodes(nodes) {
  return nodes.map(n => {
    if ("repeat" in n) {
      const o = { repeat: n.repeat };
      if (nonEmptyStr(n.name)) o.name = n.name;
      o.do = cleanNodes(n.do);
      if (Array.isArray(n.between) && n.between.length) o.between = cleanNodes(n.between);
      return o;
    }
    const o = { type: n.type, sec: n.sec };
    if (nonEmptyStr(n.label)) o.label = n.label;
    return o;
  });
}

function clean(data) {
  return {
    format: 1,
    folders: data.folders.map(f => {
      const o = { name: f.name };
      if (nonEmptyStr(f.source)) o.source = f.source;
      o.programs = f.programs.map(p => ({ name: p.name, steps: cleanNodes(p.steps) }));
      return o;
    }),
  };
}

// ---------------------------------------------------------------- validation

function checkNodes(nodes, where, depth, errs) {
  if (!Array.isArray(nodes) || !nodes.length) { errs.push(`${where}: needs at least one step`); return; }
  if (depth > MAX_DEPTH) { errs.push(`${where}: repeats nested deeper than ${MAX_DEPTH}`); return; }
  nodes.forEach((node, i) => {
    const here = `${where} › step ${i + 1}`;
    if (!isObj(node)) { errs.push(`${here}: must be an object`); return; }
    if ("repeat" in node) {
      const extra = Object.keys(node).filter(k => !["repeat", "name", "do", "between"].includes(k));
      if (extra.length) errs.push(`${here}: unknown keys ${extra.join(", ")}`);
      if (!isInt(node.repeat, 1)) errs.push(`${here}: repeat count must be an integer >= 1`);
      if ("name" in node && typeof node.name !== "string") errs.push(`${here}: name must be a string`);
      if (!("do" in node)) errs.push(`${here}: a repeat needs a 'do' list`);
      else checkNodes(node.do, `${here} › do`, depth + 1, errs);
      if ("between" in node) checkNodes(node.between, `${here} › between`, depth + 1, errs);
    } else {
      const extra = Object.keys(node).filter(k => !["type", "sec", "label"].includes(k));
      if (extra.length) errs.push(`${here}: unknown keys ${extra.join(", ")}`);
      if (!TYPES.includes(node.type)) errs.push(`${here}: type must be hang or rest`);
      if (!isInt(node.sec, 1)) errs.push(`${here}: seconds must be an integer >= 1`);
      if ("label" in node && typeof node.label !== "string") errs.push(`${here}: label must be a string`);
    }
  });
}

function validate(data) {
  const errs = [];
  if (!isObj(data)) return ["The file must hold a JSON object"];
  if (data.format !== 1) errs.push("format must be 1");
  if (!Array.isArray(data.folders) || !data.folders.length) {
    errs.push("There must be at least one folder");
    return errs;
  }
  data.folders.forEach((folder, f) => {
    if (!isObj(folder)) { errs.push(`folder ${f + 1}: must be an object`); return; }
    const fw = nonEmptyStr(folder.name) ? folder.name : `folder ${f + 1}`;
    if (!nonEmptyStr(folder.name)) errs.push(`${fw}: needs a name`);
    if (!Array.isArray(folder.programs) || !folder.programs.length) {
      errs.push(`${fw}: needs at least one program`);
      return;
    }
    folder.programs.forEach((prog, p) => {
      if (!isObj(prog)) { errs.push(`${fw}: program ${p + 1} must be an object`); return; }
      const pw = nonEmptyStr(prog.name) ? prog.name : `program ${p + 1}`;
      if (!nonEmptyStr(prog.name)) errs.push(`${fw} › ${pw}: needs a name`);
      checkNodes(prog.steps, `${fw} › ${pw}`, 0, errs);
    });
  });
  return errs;
}

// ---------------------------------------------------------------- expansion

function expand(nodes, counters, out) {
  for (const node of nodes) {
    if ("repeat" in node) {
      const total = node.repeat;
      const name = node.name;
      for (let n = 1; n <= total; n++) {
        const inner = name ? [[name, n, total]].concat(counters) : counters;
        expand(node.do, inner, out);
        if (n < total && node.between) expand(node.between, inner, out);
      }
    } else {
      if (out.length >= PREVIEW_LIMIT) throw new Error("too many steps");
      out.push({ type: node.type, sec: node.sec, label: node.label, counters });
    }
  }
}

function fmt(sec) {
  return sec >= 60 ? `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, "0")}` : `${sec}s`;
}

function progressText(counters) {
  return counters.slice().reverse().map(([n, i, t]) => `${n} ${i}/${t}`).join("   ");
}

// Returns steps and totals for a valid program, or { error } otherwise.
function summarize(prog) {
  const errs = [];
  const nodes = cleanNodes(prog.steps);
  checkNodes(nodes, prog.name, 0, errs);
  if (errs.length) return { error: "has errors" };
  const steps = [];
  try { expand(nodes, [], steps); } catch (e) { return { error: `more than ${PREVIEW_LIMIT} steps` }; }
  const hangs = steps.filter(s => s.type === "hang").length;
  const total = steps.reduce((a, s) => a + s.sec, 0);
  return { steps, hangs, total };
}

// ---------------------------------------------------------------- DOM helpers

const $ = id => document.getElementById(id);

function h(tag, props, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (k === "class") e.className = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else if (v === true) e.setAttribute(k, "");
    else if (v !== false && v != null) e.setAttribute(k, v);
  }
  const add = kid => {
    if (Array.isArray(kid)) kid.forEach(add);
    else if (kid !== null && kid !== undefined && kid !== false) {
      e.append(typeof kid === "string" ? document.createTextNode(kid) : kid);
    }
  };
  kids.forEach(add);
  return e;
}

function textInput(obj, key, placeholder, cls) {
  const i = h("input", {
    type: "text", class: cls, placeholder, value: obj[key] ?? "",
    oninput: () => { obj[key] = i.value; update(); },
  });
  return i;
}

function numInput(obj, key, min, onchange) {
  const i = h("input", {
    type: "number", min, step: 1, value: obj[key] ?? "",
    oninput: () => {
      const v = i.value.trim();
      obj[key] = v === "" ? null : Number(v);
      (onchange || update)();
    },
  });
  return i;
}

function btn(label, title, disabled, fn, cls) {
  return h("button", {
    type: "button", class: cls, title, "aria-label": title, disabled,
    onclick: () => fn(),
  }, label);
}

// ---------------------------------------------------------------- refresh

// Typing in a field: refresh everything except the editor, so focus is kept.
function update() {
  notice = "";
  saveState();
  renderSidebar();
  renderPreview();
  renderStatus();
}

// Adding, removing or moving things: rebuild the editor too.
function structural() {
  update();
  renderEditor();
}

function renderAll() {
  saveState();
  render();
}

function render() {
  renderSidebar();
  renderEditor();
  renderPreview();
  renderStatus();
}

function select(f, p) {
  sel = { f, p };
  renderSidebar();
  renderEditor();
  renderPreview();
}

// ---------------------------------------------------------------- status

function renderStatus() {
  const box = $("status");
  const errs = validate(clean(state));
  box.replaceChildren();
  box.className = errs.length ? "bad" : "";
  if (notice) box.append(h("div", {}, notice));
  if (errs.length) {
    box.append(h("div", {}, `${errs.length} problem${errs.length > 1 ? "s" : ""} to fix before downloading:`));
    box.append(h("ul", {}, errs.slice(0, 8).map(e => h("li", {}, e)),
      errs.length > 8 ? h("li", {}, `…and ${errs.length - 8} more`) : null));
  } else {
    const progs = state.folders.reduce((a, f) => a + f.programs.length, 0);
    box.append(h("div", {}, `Valid: ${state.folders.length} folder${state.folders.length > 1 ? "s" : ""}, ${progs} program${progs > 1 ? "s" : ""}.`));
  }
  $("btn-download").disabled = errs.length > 0;
}

// ---------------------------------------------------------------- sidebar

function renderSidebar() {
  const nav = $("sidebar");
  nav.replaceChildren();
  state.folders.forEach((folder, f) => {
    nav.append(h("div", { class: "folder" },
      h("button", {
        type: "button", class: "folder-name" + (sel.f === f && sel.p === null ? " sel" : ""),
        onclick: () => select(f, null),
      }, folder.name || "(unnamed folder)"),
      folder.programs.map((prog, p) => h("button", {
        type: "button", class: "prog" + (sel.f === f && sel.p === p ? " sel" : ""),
        onclick: () => select(f, p),
      }, prog.name || "(unnamed program)")),
      btn("+ program", "Add a program to this folder", false, () => addProgram(f), "add-link")));
  });
  nav.append(btn("+ folder", "Add a folder", false, addFolder));
}

function addFolder() {
  state.folders.push({ name: "New folder", programs: [{ name: "New program", steps: defaultSteps() }] });
  sel = { f: state.folders.length - 1, p: 0 };
  renderAll();
}

function addProgram(f) {
  const progs = state.folders[f].programs;
  progs.push({ name: "New program", steps: defaultSteps() });
  sel = { f, p: progs.length - 1 };
  renderAll();
}

// ---------------------------------------------------------------- editor

function renderEditor() {
  const box = $("editor");
  box.replaceChildren();
  const folder = state.folders[sel.f];
  if (!folder) {
    box.append(h("p", {}, "No folders. Use “+ folder” in the sidebar."));
    return;
  }
  box.append(sel.p === null ? folderEditor(folder) : programEditor(folder, folder.programs[sel.p]));
}

function folderEditor(folder) {
  const f = sel.f;
  return h("div", {},
    h("h2", {}, "Folder"),
    h("div", { class: "row" },
      textInput(folder, "name", "Folder name", "grow"),
      btn("↑", "Move folder up", f === 0, () => { sel.f = move(state.folders, f, -1); renderAll(); }),
      btn("↓", "Move folder down", f === state.folders.length - 1, () => { sel.f = move(state.folders, f, 1); renderAll(); }),
      btn("Delete", "Delete this folder and its programs", false, () => {
        if (!confirm(`Delete folder “${folder.name}” and all its programs?`)) return;
        state.folders.splice(f, 1);
        clampSel();
        renderAll();
      }, "danger")),
    h("div", { class: "row" }, textInput(folder, "source", "Source note (optional, ignored by the app)", "grow")),
    h("p", { class: "hint" }, `${folder.programs.length} program${folder.programs.length === 1 ? "" : "s"}. Select one in the sidebar to edit its steps.`));
}

function programEditor(folder, prog) {
  const p = sel.p;
  return h("div", {},
    h("h2", {}, `Program in “${folder.name}”`),
    h("div", { class: "row" },
      textInput(prog, "name", "Program name", "grow"),
      btn("↑", "Move program up", p === 0, () => { sel.p = move(folder.programs, p, -1); renderAll(); }),
      btn("↓", "Move program down", p === folder.programs.length - 1, () => { sel.p = move(folder.programs, p, 1); renderAll(); }),
      btn("Copy", "Duplicate this program", false, () => {
        const c = structuredClone(prog);
        c.name = `${prog.name} copy`;
        folder.programs.splice(p + 1, 0, c);
        sel.p = p + 1;
        renderAll();
      }),
      btn("Delete", "Delete this program", false, () => {
        if (!confirm(`Delete program “${prog.name}”?`)) return;
        folder.programs.splice(p, 1);
        clampSel();
        renderAll();
      }, "danger")),
    h("p", { class: "hint" }, "The program name is also the Garmin activity name, so keep it short. A 10 s get-ready countdown is added automatically."),
    generator(prog),
    h("h3", {}, "Steps"),
    nodeList(prog.steps, 0));
}

function generator(prog) {
  const err = h("span", { class: "warn" });
  const field = (label, key, min) => h("label", {}, `${label} `, numInput(gen, key, min, () => { err.textContent = ""; }));
  return h("details", { class: "gen", open: genOpen, ontoggle: e => { genOpen = e.target.open; } },
    h("summary", {}, "Quick builder: hang, rest, reps, sets"),
    h("div", { class: "row" },
      field("Hang (s)", "hang", 1),
      field("Rest between reps (s)", "rest", 0),
      field("Reps per set", "reps", 1),
      field("Sets", "sets", 1),
      field("Rest between sets (s)", "setRest", 0)),
    h("div", { class: "row" },
      btn("Replace steps", "Replace all steps of this program", false, () => {
        const ok = isInt(gen.hang, 1) && isInt(gen.rest, 0) && isInt(gen.reps, 1) && isInt(gen.sets, 1) && isInt(gen.setRest, 0);
        if (!ok) { err.textContent = "Use whole numbers: hang, reps and sets at least 1; rests at least 0."; return; }
        if (!confirm("Replace all steps of this program?")) return;
        prog.steps = buildPlan(gen);
        genOpen = true;
        structural();
      }),
      err),
    h("p", { class: "hint" }, "Builds the usual structure: sets of reps with a rest between reps and a longer rest between sets. Rest 0 leaves the rest out."));
}

function nodeList(nodes, depth) {
  return h("div", { class: "nodes" },
    nodes.map((n, i) => nodeView(nodes, i, depth)),
    h("div", { class: "addbar" },
      btn("+ Hang", "Add a hang", false, () => { nodes.push({ type: "hang", sec: 10 }); structural(); }),
      btn("+ Rest", "Add a rest", false, () => { nodes.push({ type: "rest", sec: 30 }); structural(); }),
      btn("+ Repeat", depth >= MAX_DEPTH ? `Repeats can nest at most ${MAX_DEPTH} levels` : "Add a repeat",
        depth >= MAX_DEPTH,
        () => { nodes.push({ repeat: 2, name: "", do: [{ type: "hang", sec: 10 }] }); structural(); })));
}

function controls(nodes, i) {
  return h("span", { class: "ctl" },
    btn("↑", "Move up", i === 0, () => { move(nodes, i, -1); structural(); }, "small"),
    btn("↓", "Move down", i === nodes.length - 1, () => { move(nodes, i, 1); structural(); }, "small"),
    btn("Copy", "Duplicate", false, () => { nodes.splice(i + 1, 0, structuredClone(nodes[i])); structural(); }, "small"),
    btn("✕", "Delete", false, () => { nodes.splice(i, 1); structural(); }, "small danger"));
}

function nodeView(nodes, i, depth) {
  const n = nodes[i];
  if ("repeat" in n) return repeatView(nodes, i, depth);
  const type = h("select", {
    "aria-label": "Step type",
    onchange: () => { n.type = type.value; structural(); },
  }, TYPES.map(t => h("option", { value: t }, t)));
  type.value = n.type;
  return h("div", { class: `node ${n.type}` },
    h("div", { class: "row" },
      type,
      numInput(n, "sec", 1),
      "s",
      textInput(n, "label", "Label (optional), replaces the title on screen", "grow"),
      controls(nodes, i)));
}

function repeatView(nodes, i, depth) {
  const n = nodes[i];
  const sub = [
    h("div", { class: "sub" },
      h("div", { class: "sub-title" }, "Do"),
      nodeList(n.do, depth + 1)),
  ];
  if (Array.isArray(n.between)) {
    sub.push(h("div", { class: "sub" },
      h("div", { class: "sub-title" }, "Between repetitions (not after the last)",
        btn("Remove", "Remove the between steps", false, () => { delete n.between; structural(); }, "small")),
      nodeList(n.between, depth + 1)));
  } else {
    sub.push(h("div", { class: "addbar" },
      btn("+ Between repetitions", "Add steps that run between repetitions", false,
        () => { n.between = [{ type: "rest", sec: 30 }]; structural(); })));
  }
  return h("div", { class: "node repeat" },
    h("div", { class: "row" },
      "Repeat",
      numInput(n, "repeat", 1),
      "×",
      textInput(n, "name", "Name shown as “Rep 2/4” (optional)", "grow"),
      controls(nodes, i)),
    sub);
}

// ---------------------------------------------------------------- preview

function renderPreview() {
  const box = $("preview");
  box.replaceChildren();
  const folder = state.folders[sel.f];
  if (!folder) return;

  if (sel.p === null) {
    box.append(h("h2", {}, "Programs"));
    folder.programs.forEach(prog => {
      const s = summarize(prog);
      box.append(h("p", { class: "totals" },
        s.error ? `${prog.name}: ${s.error}` : `${prog.name}: ${s.hangs} hangs, ${fmt(s.total)} total, ${s.steps.length} steps`));
    });
    return;
  }

  const prog = folder.programs[sel.p];
  const s = summarize(prog);
  box.append(h("h2", {}, "Preview"));
  if (s.error) {
    box.append(h("p", { class: "totals" }, `Cannot preview: ${s.error}.`));
    return;
  }
  box.append(h("p", { class: "totals" },
    `${s.hangs} hangs, ${fmt(s.total)} total (plus ${PREP_SEC} s get-ready), ${s.steps.length} steps`));
  box.append(h("table", { id: "steps" }, h("tbody", {},
    h("tr", { class: "prep" }, h("td", { class: "t" }, "READY"), h("td", { class: "d" }, fmt(PREP_SEC)), h("td", { class: "p" }, "")),
    s.steps.map(st => h("tr", { class: st.type },
      h("td", { class: "t" }, st.label || st.type.toUpperCase()),
      h("td", { class: "d" }, fmt(st.sec)),
      h("td", { class: "p" }, progressText(st.counters)))))));
}

// ---------------------------------------------------------------- file I/O

// Steps stay on one line, everything else is indented like programs.json.
function isStep(v) { return isObj(v) && !("repeat" in v) && "type" in v; }

function ser(v, ind) {
  const pad = "  ".repeat(ind);
  const pad1 = "  ".repeat(ind + 1);
  if (Array.isArray(v)) {
    if (!v.length) return "[]";
    if (v.length <= 3 && v.every(isStep)) return `[ ${v.map(x => ser(x, 0)).join(", ")} ]`;
    return `[\n${v.map(x => pad1 + ser(x, ind + 1)).join(",\n")}\n${pad}]`;
  }
  if (isObj(v)) {
    const entries = Object.entries(v);
    if (isStep(v)) return `{ ${entries.map(([k, x]) => `${JSON.stringify(k)}: ${JSON.stringify(x)}`).join(", ")} }`;
    return `{\n${entries.map(([k, x]) => `${pad1}${JSON.stringify(k)}: ${ser(x, ind + 1)}`).join(",\n")}\n${pad}}`;
  }
  return JSON.stringify(v);
}

function download() {
  const data = clean(state);
  if (validate(data).length) return;
  const blob = new Blob([ser(data, 0) + "\n"], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = h("a", { href: url, download: "programs.json" });
  document.body.append(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

async function openFile(file) {
  if (!file) return;
  let data;
  try {
    data = JSON.parse(await file.text());
  } catch (e) {
    notice = `${file.name}: not valid JSON.`;
    renderStatus();
    return;
  }
  const errs = validate(data);
  if (errs.length) {
    notice = `${file.name} was not loaded: ${errs[0]}${errs.length > 1 ? ` (and ${errs.length - 1} more)` : ""}`;
    renderStatus();
    return;
  }
  state = data;
  selectFirst();
  renderAll();
  notice = `Loaded ${file.name}.`;
  renderStatus();
}

$("btn-new").addEventListener("click", () => {
  if (!confirm("Discard the current plans and start with an empty one?")) return;
  state = newState();
  selectFirst();
  renderAll();
});
$("btn-builtin").addEventListener("click", async () => {
  if (!confirm("Discard your changes and reload the built-in plans?")) return;
  try {
    useBuiltin(await fetchBuiltin());
    notice = "Loaded the built-in plans from resources/programs/programs.json.";
  } catch (e) {
    notice = failedBuiltin(e);
  }
  renderAll();
});
$("btn-open").addEventListener("click", () => {
  if (confirm("Opening a file replaces the plans you are editing. Continue?")) $("file-open").click();
});
$("file-open").addEventListener("change", e => {
  const file = e.target.files[0];
  e.target.value = "";
  openFile(file);
});
$("btn-download").addEventListener("click", download);

startup();
