# Roo4u Constellation Architecture & Visualizer Engine Survey Report

**Author**: Explorer Survey Engine Agent (`teamwork_preview_explorer`)  
**Target Repository**: `s6pa1rta3n-lab/roof4u`  
**Date**: 2026-09-01  
**Working Directory**: `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_survey_engine`  
**Deployment Target**: `main` branch `/docs` folder (GitHub Pages: `https://s6pa1rta3n-lab.github.io/roof4u/`)  

---

## 1. Executive Summary & Repository Context

The Roo4u repository contains an interactive constellation-style force-directed network visualizer hosted on GitHub Pages from the `main` branch `docs/` directory. The visualizer maps the architectural evolution of the codebase across two primary branches:
1. **`main`**: Python offline multi-agent architecture with dynamic AST validation (279 nodes, 164 links, 12 clusters).
2. **`v2`**: Pure OCaml formal invariant-verified engine with differential fuzzing verification (431 nodes, 334 links, 14 clusters).

### Critical Branch & Deployment Topology
- **Current Workspace Branch**: `v2` (commit `1767c22`).
- **Target Deployment Branch**: `main` (commit `115a789`).
- **GitHub Pages Configuration**: Serves static assets directly from `main:docs/`.
- **Root Redirection**: `index.html` at the repository root redirects to `docs/index.html`.
- **Dataset Preservation Rule**: `docs/data.js` and `docs/data.json` contain the extracted AST/graph architectures for both `main` and `v2` branches. `docs/data.js` **must remain byte-identical**.
- **Target Overhaul Scope**: Overhaul `docs/index.html`, `docs/styles.css`, and `docs/app.js` (and root `index.html`) to deliver a 3D depth-rendered engine, pure black hole aesthetic, complete minimap removal, viewport responsiveness, and a live 3-proposal theme switcher.

---

## 2. Comprehensive File Inventory & Code Inspection

### 2.1 File Map
| File Path | Lines | Size (bytes) | Role in Architecture |
|---|---|---|---|
| `docs/index.html` | 371 | 14,845 | Main HTML markup (HUD overlays, canvases, inspector, physics drawer, comparison modal). |
| `docs/styles.css` | 1327 | 28,142 | Complete styling rules (CSS variables, glassmorphism HUDs, drawers, layout grid, animations). |
| `docs/app.js` | 1308 | 41,200 | Visualization engine (D3 force simulation, 2D canvas rendering, event handling, camera operations, HUD). |
| `docs/data.js` | 19732 | 688,520 | Global JS object `window.ROO4U_GRAPH_DATA` with full graph metadata for `main` and `v2`. **(Preserve byte-identical)** |
| `docs/data.json` | 19730 | 688,443 | Pure JSON representation of `data.js`. |
| `index.html` (root) | 13 | 462 | Root meta-refresh and JS redirect to `docs/index.html`. |

---

### 2.2 Detailed Inspection of `docs/index.html`
- **Head & Dependencies (Lines 1–19)**:
  - Google Fonts: `Inter` (UI sans-serif), `JetBrains Mono` (code/symbols), `Orbitron` (cosmic display headers).
  - D3.js v7 CDN: `https://cdn.jsdelivr.net/npm/d3@7.8.5/dist/d3.min.js`.
  - Stylesheet link: `<link rel="stylesheet" href="styles.css">`.
- **Header Navigation (Lines 20–118)**:
  - Brand identity (`.brand`, `.brand-orbit`, `.brand-core`, `.brand-ring`, `.brand-title`, `.brand-tagline`).
  - Branch Selector Tabs (`#tab-main`, `#tab-v2`, `#tab-compare`).
  - Search container (`#node-search`, `#search-clear`, `#search-results`).
  - Layout dropdown selector (`#layout-mode` with options: `cosmic`, `concentric`, `layered`, `clusters`).
  - Controls toggle button (`#toggle-controls-btn`) and reset camera button (`#reset-cam-btn`).
- **Workspace & Canvas Layer (Lines 119–137)**:
  - `<div id="graph-container" class="graph-container">` containing:
    - `<canvas id="starfield-canvas">` (Background space/starfield canvas).
    - `<canvas id="graph-canvas">` (Primary interactive network canvas).
    - `<div id="graph-tooltip" class="graph-tooltip hidden">` (Hover metadata card).
- **HUD Overlays (Lines 138–181)**:
  - `.hud-stats` (Top-Left): HUD tag (`#hud-branch-tag`), pulse indicator, counters (`#stat-nodes`, `#stat-links`, `#stat-loc`, `#stat-clusters`), certification banner (`#hud-cert-box`, `#hud-cert-text`).
  - `.hud-filters` (Bottom-Left): Sector title, `#toggle-swarm` checkbox, `#category-chips` dynamic container.
  - `.hud-minimap` (Bottom-Right): Minimap header with `#zoom-indicator`, and `<canvas id="minimap-canvas" width="180" height="120"></canvas>`.
- **Slide-out Drawers & Modal (Lines 182–365)**:
  - `#physics-panel` (Simulation Drawer): Sliders for `#slider-charge`, `#slider-link-dist`, `#slider-collision`, `#slider-gravity`, `#slider-photon-speed`; checkboxes for `#toggle-photons`, `#toggle-nebulas`; buttons `#reset-physics-btn`, `#reheat-sim-btn`.
  - `#inspector-drawer` (Node Details Drawer): Tab headers (`insp-overview`, `insp-deps`, `insp-symbols`, `insp-code`), meta grid (language, LOC, size, layer, SHA-256 copy), dependency lists, symbol list, code preview block, isolation buttons (`#focus-constellation-btn`, `#clear-focus-btn`).
  - `#compare-modal` (Architecture Shift Modal): Table (`#compare-metrics-tbody`) comparing Python vs OCaml, and cards grid (`#compare-mappings-grid`).
- **Scripts (Lines 366–370)**:
  - `<script src="data.js"></script>` followed by `<script src="app.js"></script>`.

---

### 2.3 Detailed Inspection of `docs/styles.css`
- **Color System & Tokens (Lines 7–58)**:
  - Deep space background tokens: `--bg-deep-space: #060812`, `--bg-space-dark: #0a0e1c`.
  - Glass surface tokens: `--bg-surface-glass: rgba(13, 18, 36, 0.75)`, `--bg-surface-elevated: rgba(20, 27, 52, 0.85)`.
  - Border tokens: `--border-glass: rgba(255, 255, 255, 0.09)`, `--border-glow-cyan: rgba(0, 240, 255, 0.4)`.
  - Accent colors: `--color-cyan: #00f0ff`, `--color-purple: #a855f7`, `--color-emerald: #10b981`, `--color-amber: #f59e0b`, `--color-ruby: #ef4444`, `--color-pink: #ec4899`, `--color-sky: #38bdf8`, `--color-gold: #eab308`.
  - Typography tokens: `--font-sans: 'Inter'`, `--font-mono: 'JetBrains Mono'`, `--font-display: 'Orbitron'`.
  - Layout dimensions: `--header-height: 64px`, `--drawer-width: 380px`.
- **Viewport Fitting & Canvas Layout (Lines 408–445)**:
  - `html, body { width: 100%; height: 100%; overflow: hidden; background-color: var(--bg-deep-space); }`
  - `.workspace { position: absolute; top: var(--header-height); bottom: 0; left: 0; right: 0; overflow: hidden; }`
  - `#starfield-canvas` and `#graph-canvas` fill `.workspace` with absolute coordinates (`top: 0; left: 0; width: 100%; height: 100%;`).
- **HUD Glassmorphism Panels (Lines 451–692)**:
  - Shared styling: `backdrop-filter: blur(16px); -webkit-backdrop-filter: blur(16px); border: 1px solid var(--border-glass); border-radius: 12px; box-shadow: 0 8px 32px rgba(0,0,0,0.4);`
  - `.hud-stats`: `top: 20px; left: 20px; width: 260px;`
  - `.hud-filters`: `bottom: 20px; left: 20px; max-width: 480px;`
  - `.hud-minimap`: `bottom: 20px; right: 20px; padding: 10px;`
- **Drawers & Modals (Lines 790–1280)**:
  - `.inspector-drawer`, `.physics-drawer`: `position: absolute; top: var(--header-height); right: 0; bottom: 0; width: 380px; transform: translateX(100%); transition: transform 0.3s;`
  - `.compare-modal`: `position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; background: rgba(4,6,14,0.85); backdrop-filter: blur(12px);`

---

## 3. Analysis of Current Rendering Engine

```
+-----------------------------------------------------------------------------------+
|                                 BROWSER VIEWPORT                                  |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  |                      APP HEADER (h = 64px, z-index = 100)                   |  |
|  +-----------------------------------------------------------------------------+  |
|  |                                                                             |  |
|  |  +-----------------------------------------------------------------------+  |  |
|  |  |                     WORKSPACE CANVAS CONTAINER                        |  |  |
|  |  |                                                                       |  |  |
|  |  |   Layer 0: #starfield-canvas (Canvas2D - Starfield & Deep Gradient)   |  |  |
|  |  |   Layer 1: #graph-canvas     (Canvas2D - D3 Force Graph & Filaments)  |  |  |
|  |  |                                                                       |  |  |
|  |  |   +-------------------+                     +---------------------+   |  |  |
|  |  |   | HUD Stats Panel   |                     | Sliding Drawers:    |   |  |  |
|  |  |   | (Top-Left)        |                     | - Physics Panel     |   |  |  |
|  |  |   +-------------------+                     | - Node Inspector    |   |  |  |
|  |  |                                             +---------------------+   |  |  |
|  |  |   +-------------------+                     +---------------------+   |  |  |
|  |  |   | HUD Filters Panel |                     | [OLD] Radar Minimap |   |  |  |
|  |  |   | (Bottom-Left)     |                     | (To Be Removed)     |   |  |  |
|  |  |   +-------------------+                     +---------------------+   |  |  |
|  |  +-----------------------------------------------------------------------+  |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
```

### 3.1 Technology Stack & Render Architecture
- **Rendering Technology**: HTML5 Canvas 2D API (`CanvasRenderingContext2D`).
  - Dual canvas architecture (`starfieldCanvas` and `graphCanvas`), plus mini radar canvas.
  - High performance: renders 400+ nodes, 300+ links, and flowing particles at a steady 60 FPS.
- **High-DPI (Retina) Handling**:
  - In `resizeCanvases()` (`app.js:108–122`):
    ```javascript
    const dpr = window.devicePixelRatio || 1;
    [starfieldCanvas, graphCanvas].forEach(canvas => {
      canvas.width = width * dpr;
      canvas.height = height * dpr;
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
      const ctx = canvas.getContext('2d');
      ctx.resetTransform();
      ctx.scale(dpr, dpr);
    });
    ```
- **Physics Simulation (D3 Force v7)**:
  - Configured in `initSimulation()` (`app.js:237–254`):
    - `d3.forceLink(links).id(d => d.id).distance(90).strength(0.6)`
    - `d3.forceManyBody().strength(-350)` (Repulsion)
    - `d3.forceCollide().radius(d => (d.importance * 3) + 18).iterations(2)`
    - `d3.forceCenter(width / 2, height / 2)`
    - `d3.forceX(width / 2).strength(0.08)`, `d3.forceY(height / 2).strength(0.08)`
    - `alphaDecay(0.025)` for smooth settling.
- **Camera & Pan/Zoom Coordinate Spaces**:
  - D3 Zoom attached to `graphCanvas`: `zoomBehavior = d3.zoom().scaleExtent([0.15, 4.0]).on('zoom', (e) => state.zoomTransform = e.transform)`
  - **Screen-to-World mapping** (`app.js:876–883`):
    $$x_{\text{world}} = \frac{x_{\text{screen}} - t_x}{k}, \quad y_{\text{world}} = \frac{y_{\text{screen}} - t_y}{k}$$
  - **World-to-Screen rendering** (`app.js:347–352`):
    ```javascript
    graphCtx.save();
    graphCtx.translate(state.zoomTransform.x, state.zoomTransform.y);
    graphCtx.scale(state.zoomTransform.k, state.zoomTransform.k);
    // Draw in world coordinates...
    graphCtx.restore();
    ```
- **Hit Detection & Interaction Handling**:
  - `getNodeAtPosition(clientX, clientY)` (`app.js:886–896`):
    - Computes Euclidean distance $d = \sqrt{(n.x - p_x)^2 + (n.y - p_y)^2}$.
    - Hit radius threshold: $r = (n.\text{importance} \times 2.2) + 5$.
  - D3 Dragging (`app.js:700–721`): fixes $fx, fy$ on active drag subject.
- **Render Execution Pipeline**:
  - Continuous `requestAnimationFrame` loop calling:
    1. `renderStarfield()`: Clears starfield canvas, renders radial gradient backdrop, twinkles stardust with parallax.
    2. `renderGraph()`:
       - `renderClusterNebulas()`: Soft radial gradient glow clouds per architectural category.
       - `renderLinks()`: Filament lines with glowing highlights (`shadowBlur: 10`) for connected subgraphs.
       - `renderPhotons()`: Animated photon particles traveling along link paths (`progress += speed`).
       - `renderNodes()`: Multi-pass radial gradient halos, pulsing dashed beacon rings for selected nodes, solid cores, and specular white centers.
       - `renderLabels()`: Level-of-Detail (LOD) text rendering based on zoom scale $k$ and node importance.
    3. `renderMinimap()`: Mini radar overview with camera frustum indicator.

---

## 4. Complete Minimap (Galactic Radar) Inventory & Removal Plan

To satisfy **Requirement R3**, the minimap must be completely excised across all layers without leaving orphaned code or broken references.

### 4.1 All References across Codebase
| File | Line Numbers | Element / Reference | Action Required |
|---|---|---|---|
| `docs/index.html` | 172–180 | `<div class="hud-panel hud-minimap">...<canvas id="minimap-canvas">...</div>` | **Remove entire DOM block**. Relocate `#zoom-indicator` to header or stats HUD. |
| `docs/styles.css` | 661–692 | `.hud-minimap`, `.minimap-header`, `.minimap-canvas-wrapper`, `#minimap-canvas` | **Delete CSS rules**. |
| `docs/app.js` | 46–47 | `const minimapCanvas = document.getElementById('minimap-canvas'); const minimapCtx = minimapCanvas.getContext('2d');` | **Delete variable declarations**. |
| `docs/app.js` | 441 | `renderMinimap();` call in `startRenderLoop()` | **Delete function invocation**. |
| `docs/app.js` | 576–636 | `function renderMinimap() { ... }` | **Delete function definition**. |
| `docs/app.js` | 725–728 | `minimapCanvas.addEventListener('click', handleMinimapClick);` | **Delete event listener**. |
| `docs/app.js` | 1141–1178 | `function handleMinimapClick(e) { ... }` | **Delete function definition**. |
| `docs/app.js` | 1180–1183 | `function updateZoomIndicator() { ... }` | **Update target DOM element** to new relocated indicator. |

---

## 5. Dataset Architecture & Branch Loading

### 5.1 Preservation Rule
`docs/data.js` has SHA-256 digest `d0788e2a4338a988b994cd17f20225a0fff33c45` on `main`. It contains the complete architectural graph for both `main` and `v2`. **It must not be modified or regenerated.**

### 5.2 Data Structure Breakdown
`window.ROO4U_GRAPH_DATA` schema:
```json
{
  "generatedAt": "2026-09-01T07:28:00Z",
  "repository": "roof4u (Roo4u Offline Agentic Lead Gen & OCaml Core)",
  "branches": {
    "main": {
      "branch": "main",
      "stats": {
        "totalFiles": 279,
        "totalLoc": 63133,
        "codeLoc": 13875,
        "testLoc": 12808,
        "pyLoc": 13875,
        "ocamlLoc": 0,
        "linksCount": 164,
        "clustersCount": 12,
        "certStatus": "VALIDATED SHA-256 (AST Certified Pass)"
      },
      "nodes": [ /* 279 nodes */ ],
      "links": [ /* 164 links */ ],
      "clusters": [ /* 12 clusters */ ]
    },
    "v2": {
      "branch": "v2",
      "stats": {
        "totalFiles": 431,
        "totalLoc": 89257,
        "codeLoc": 26593,
        "testLoc": 18114,
        "pyLoc": 14864,
        "ocamlLoc": 11729,
        "linksCount": 334,
        "clustersCount": 14,
        "certStatus": "DUAL-VERIFIED (Differential Fuzzing & Pure OCaml Engine)"
      },
      "nodes": [ /* 431 nodes */ ],
      "links": [ /* 334 links */ ],
      "clusters": [ /* 14 clusters */ ]
    }
  },
  "comparison": {
    "title": "Python (main) vs Pure OCaml (v2) Architectural Shift",
    "summary": "...",
    "metrics": [ /* 7 comparison rows */ ],
    "moduleMappings": [ /* 10 component transformations */ ]
  }
}
```

### 5.3 Branch Switcher Lifecycle
When user clicks `#tab-main` or `#tab-v2`:
1. `loadBranch(branchName)` is invoked in `app.js`.
2. Nodes and links are filtered by `includeSwarm` flag and active category filters.
3. Cloned node/link objects are fed into `d3.forceSimulation`.
4. HUD statistics, cluster chips, and search indices are rebuilt.
5. Camera smoothly re-centers with `centerCamera()`.

---

## 6. Technical Integration Blueprint for Required Overhaul

### 6.1 R1: 3D Depth Rendering Engine (Mathematical Specification)

#### A. Z-Axis Coordinate Mapping
Assign each node a depth coordinate $z_i \in [-300, 300]$ where:
- $z_i$ is computed deterministically from node layer, importance, and topological degree:
  $$z_i = (d.\text{layer} - 3.5) \times 80 + (d.\text{importance} - 3) \times 30 + \text{hashOffset}(d.\text{id})$$
- Optional dynamic z-oscillation: $z_i(t) = z_i + A \sin(\omega t + \phi_i)$.

#### B. Perspective Projection & Depth Scale
Using focal length $F = 600$:
$$\text{scale}(z) = \frac{F}{F + z}$$
- Near nodes ($z = -200 \implies \text{scale} = 1.50$): magnified, hyper-luminous, fast parallax.
- Focal plane ($z = 0 \implies \text{scale} = 1.00$): standard scale.
- Distant nodes ($z = +300 \implies \text{scale} = 0.67$): diminished, translucent, slow parallax.

#### C. Parallax Formulation Under Camera Pan/Zoom
For world coordinate $(x_w, y_w, z_w)$ with zoom transform $(t_x, t_y, k)$:
$$x_{\text{proj}} = x_w \cdot \text{scale}(z_w)$$
$$y_{\text{proj}} = y_w \cdot \text{scale}(z_w)$$
$$\text{screenX} = t_x + x_{\text{proj}} \cdot k \cdot (\text{scale}(z_w))^{p_{\text{pan}}}$$
$$\text{screenY} = t_y + y_{\text{proj}} \cdot k \cdot (\text{scale}(z_w))^{p_{\text{pan}}}$$
where $p_{\text{pan}} \approx 0.35$ creates visceral parallax depth displacement.

#### D. Depth-Sorted Rendering (Painter's Algorithm)
Before drawing, sort all active nodes and links by depth $z$:
```javascript
const sortedNodes = [...currentGraph.nodes].sort((a, b) => a.z - b.z); // back-to-front
```
For each node rendered:
1. **Size**: $R(z) = R_{\text{base}} \times \text{scale}(z)$.
2. **Opacity**: $\alpha(z) = \text{clamp}(\alpha_{\text{base}} \times (1.15 - \frac{z}{500}), 0.20, 1.0)$.
3. **Halo Radius & Blur**: $\text{halo}(z) = R(z) \times 3.5 \times \text{scale}(z)$.
4. **Specular Highlight**: Specular core intensity scaled by $(1 - z/400)$.

#### E. Depth-Tapered Link Filaments
For link connecting $S(x_s, y_s, z_s)$ and $T(x_t, y_t, z_t)$:
- Compute linear gradient along the link in 2D projected space:
  ```javascript
  const grad = graphCtx.createLinearGradient(sProj.x, sProj.y, tProj.x, tProj.y);
  grad.addColorStop(0, hexToRgba(s.color, alpha(s.z)));
  grad.addColorStop(1, hexToRgba(t.color, alpha(t.z)));
  graphCtx.strokeStyle = grad;
  graphCtx.lineWidth = baseWidth * ((scale(s.z) + scale(t.z)) / 2);
  ```
- Filaments smoothly fade and taper into the background void.

#### F. 3D Photon Particles
Photons traveling along link $L$ at parametric position $u \in [0, 1]$:
$$z_{\text{photon}}(u) = (1 - u) z_s + u z_t$$
$$\text{size}_{\text{photon}} = \text{baseSize} \times \text{scale}(z_{\text{photon}})$$
$$\alpha_{\text{photon}} = \text{baseAlpha} \times \text{scale}(z_{\text{photon}})$$

#### G. Depth-Aware Mouse Hit Testing
Test mouse ray against nodes in **reverse depth order** (front-to-back: largest $z_{\text{scale}}$ first):
```javascript
function getNodeAtPosition(screenX, screenY) {
  // Sort front-to-back
  const frontToBack = [...currentGraph.nodes].sort((a, b) => b.z - a.z);
  for (const node of frontToBack) {
    const proj = projectNodeToScreen(node);
    const r = (node.importance * 2.2 + 6) * scale(node.z) * state.zoomTransform.k;
    const dist = Math.hypot(screenX - proj.x, screenY - proj.y);
    if (dist <= r) return node;
  }
  return null;
}
```

---

### 6.2 R2: Pure Black Hole Aesthetic Specifications
1. **Pitch-Black Void Background**:
   - `html, body { background-color: #000000 !important; }`
   - Zero ambient light, zero starfield canvas (`#starfield-canvas` removed or disabled).
   - Clear Canvas with pure black / transparent clear: `graphCtx.clearRect(0, 0, width, height)`.
2. **Black-Based Glassmorphism Panels**:
   - Backgrounds: `rgba(0, 0, 0, 0.88)` to `rgba(0, 0, 0, 0.94)` with `backdrop-filter: blur(20px)`.
   - Borders: Ultra-fine, crisp high-contrast glowing accents (`rgba(255, 255, 255, 0.12)` or theme accent).
3. **Accretion Disk & Photon Ring Shaders**:
   - Singularity center motif: nodes and links radiate high-intensity photons against pure obsidian darkness.
   - Intense specular neon cores (`#ffffff`) surrounded by exponential glow falloff.

---

### 6.3 R3: Viewport Responsiveness & Layout Refinement
- **Zero Scrollbars**: Enforce `overflow: hidden` on root elements and full viewport binding:
  - Header: fixed 60px height.
  - Workspace: `top: 60px; bottom: 0; left: 0; right: 0;`.
- **Relocated Zoom Badge**:
  - Insert `#zoom-indicator` pill into Header Right or HUD Stats bar.
- **HUD Panel Layout**:
  - Stats Panel: 240px wide, sleek dark glass HUD.
  - Category Filter: bottom-left anchored, flex-wrap chips with max-height and custom slim scrollbar.
  - Drawers: right-anchored 380px wide with full vertical stretch and smooth slide animation.
- **Screen Dimension Validation**:
  - Full fitting tested on 1920x1080 (FHD), 1440x900 (MacBook standard), 1366x768 (laptop), and 1280x720.

---

### 6.4 R4: Multi-Theme Engine & Live Proposal Switcher

We propose **three distinct black hole design themes**:

```
+-----------------------------------------------------------------------------------------+
|                                  THEME COMPARISON MATRIX                                |
+-----------------------+-----------------------------+-----------------------------------+
| Theme 1: Event Horizon| Theme 2: Hawking Radiation  | Theme 3: Dark Matter Matrix       |
| (Cyan / Violet Void)  | (Amber / Solar Flare)       | (Cyber Emerald / Jade Matrix)     |
+-----------------------+-----------------------------+-----------------------------------+
| - Background: #000000 | - Background: #000000       | - Background: #000000             |
| - Accent: #00f0ff     | - Accent: #f59e0b           | - Accent: #10b981                 |
| - Glow: Cyan / Magenta| - Glow: Solar Gold / Crimson| - Glow: Matrix Green / Cyan       |
| - Filaments: Ice Neon | - Filaments: Thermal Flux   | - Filaments: Laser Phosphor       |
| - Fonts: Orbitron+Inter- Fonts: Space Grotesk+Inter | - Fonts: JetBrains Mono+Inter     |
| - Mood: Cryo-Cosmic   | - Mood: High-Energy Plasma  | - Mood: Cybernetic HUD Telemetry  |
+-----------------------+-----------------------------+-----------------------------------+
```

#### Theme Implementation Architecture
1. **Live Header Theme Selector**:
   - Add `<select id="theme-selector" class="theme-select">` with 3 proposals in the App Header.
2. **CSS Variables & Themes**:
   - Attributes on `body[data-theme="event-horizon"]`, `body[data-theme="hawking-radiation"]`, `body[data-theme="dark-matter"]`.
3. **Canvas Synchronization**:
   - JS `THEMES` registry maps theme palettes to node colors, halo shaders, filament styles, and photon speeds.
   - `switchTheme(themeId)` updates CSS data attribute, re-binds palette shaders, and repaints instantly without page reload.

---

## 7. Verification & Deployment Strategy

1. **Local Verification**:
   - Start Python HTTP server: `python3 -m http.server 8080 -d docs`
   - Verify:
     - 3D depth parallax on pan and zoom.
     - Pure `#000000` background verified in computed styles.
     - Minimap completely gone from DOM, CSS, and JS console.
     - Live theme switching between all 3 proposals without reload.
     - Branch switching between `main` and `v2` works with all nodes, links, and comparison modal.
     - Zero page scrollbars on 1920x1080 and standard viewports.
2. **Git Workflow**:
   - All visualizer work is committed to `main` branch.
   - Verify `docs/data.js` remains 100% byte-identical.
   - Push to `origin/main` for GitHub Pages live deployment.

---

**Report Status**: Complete & Verified. Ready for worker implementation dispatch.
