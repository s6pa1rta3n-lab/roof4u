# Constellation Overhaul Specification & Requirements Analysis Report

**Document Version**: 1.0.0  
**Target Repository**: `s6pa1rta3n-lab/roof4u` (`main` branch `/docs` folder)  
**Author**: `teamwork_preview_spec_miner`  
**Date**: 2026-09-01  

---

## 1. Executive Summary

This report establishes the authoritative specification for the **Constellation Overhaul** project on the `roof4u` repository. The project upgrades the existing 2D network graph visualizer (`docs/index.html`, `docs/styles.css`, `docs/app.js`) into a **3D Depth-Rendered Engine** operating in a **Pure Black Hole Void Aesthetic** with **Live Multi-Theme Switching**, complete **Decommissioning of the Galactic Radar Minimap**, and **100% Viewport Screen Fitting** across all standard resolutions (1920x1080, 1440x900, 1366x768, 4K, and mobile/tablet devices).

All underlying repository graph data (`docs/data.js`) must remain **100% byte-identical** (SHA-256: `b90ac01dc8fff2145506a405594790fadacedcc4bd5f547d4074d9489d6f823e`), preserving the complete extracted multi-branch architectural dataset for both `main` (Python core) and `v2` (Pure OCaml core).

---

## 2. Comprehensive Requirement Specifications

### 2.1. Requirement R1 — 3D Depth Rendering Engine (Foundation)

#### 2.1.1. Depth Dimension ($z$-axis) Assignment
- Each node $i$ is assigned a simulated $z \in [-100, 100]$ (or normalized depth factor $z_{\text{norm}} \in [0.1, 1.0]$) derived deterministically from:
  $$\text{depth}(n) = f(\text{layer}, \text{importance}, \text{hash}(n.\text{id}))$$
  - Core entrypoints and central architectural hubs (Importance 4–5, Layer 1–2) are positioned in the foreground ($z > 0$, higher depth factor).
  - Peripheral nodes and swarm logs (Importance 1, Layer 6) recede into the cosmic background void ($z < 0$, lower depth factor).
  - Deterministic pseudo-jitter prevents artificial planar clustering and creates true volumetric distribution.

#### 2.1.2. Depth Modulation Functions
- **Depth Scale Factor ($s_z$)**:
  $$s_z = \frac{D}{D + z} \quad \text{where } D \approx 300 \quad \Longrightarrow \quad s_z \in [0.45, 1.55]$$
- **Node Size**:
  $$R_{\text{render}} = R_{\text{base}} \times s_z$$
  Foreground nodes render crisp and substantial; background nodes shrink to distant starlight pinpoints.
- **Node Brightness & Opacity**:
  $$\alpha_z = \alpha_{\text{base}} \times (0.25 + 0.75 \times s_z)$$
  Distant nodes fade towards faint, desaturated points; near nodes are bright and vibrant.
- **Atmospheric Glow & Blur Radius**:
  $$R_{\text{halo}} = R_{\text{render}} \times (1.8 + 2.2 \times s_z)$$
  Foreground nodes project broad, luminous radiation halos; distant nodes have minimal to zero halo.
- **Filament Links (Tapering & Depth Fading)**:
  - For link $L=(s, t)$, link depth is $\bar{z} = \frac{z_s + z_t}{2}$ with scale $s_{z,\text{link}}$.
  - Base width: $W_{\text{render}} = W_{\text{base}} \times s_{z,\text{link}}$.
  - Base opacity: $\alpha_{\text{link}} = \alpha_{\text{base}} \times s_{z,\text{link}}^{1.5}$.
  - Connecting filaments between different depths dynamically taper and fade into the background.
- **Photon Particles**:
  - Photons traveling along links scale in particle radius, velocity, and luminous emission with link depth:
    $$r_{\text{photon}} = r_{\text{base}} \times s_{z,\text{link}}, \quad \alpha_{\text{photon}} = \alpha_{\text{base}} \times s_{z,\text{link}}$$

#### 2.1.3. Parallax on Pan, Zoom & Mouse Interaction
- During panning ($\Delta x, \Delta y$), nodes shift with depth-dependent parallax:
  $$x_{\text{proj}} = x_{\text{sim}} + \Delta x \times (0.5 + 0.5 \times s_z)$$
- Subtle cursor-driven perspective tilt:
  $$\Delta x_{\text{tilt}} = \left(\frac{x_{\text{cursor}} - W/2}{W/2}\right) \times z \times \kappa_{\text{tilt}}$$
- Depth fog: Very distant nodes ($s_z < 0.35$) smoothly fade into the `#000000` void.

#### 2.1.4. Depth-Sorted Rendering (Painter's Algorithm)
- Every render frame, all elements are sorted by depth:
  1. Distant cluster gravitational lensing halos
  2. Background filaments and background photons
  3. Background nodes
  4. Mid-depth filaments, photons, and nodes
  5. Foreground filaments, photons, and nodes
  6. Active selection pulses, beacons, and foreground labels
- Closer elements naturally layer over and occlude background elements without visual artifacts.

---

### 2.2. Requirement R2 — Pure Black Hole Aesthetic

#### 2.2.1. Color Architecture
- **Canvas & Document Body Background**: Pure `#000000` (`rgb(0, 0, 0)`). Zero blue tints (`#060812`, `#0a0f24`, `#020308`) or grey shades.
- **Void Lighting Principle**: The universe has zero ambient light. Every photon of luminance originates solely from data nodes, filaments, photon streams, and cluster gravitational lensing.

#### 2.2.2. Elimination of Ambient Starfields
- Decommission the static twinkling background starfield (`starfield-canvas` / `renderStarfield()` star loop).
- The canvas backdrop is an absolute pitch-black abyss.

#### 2.2.3. Black Glassmorphism Panels & Drawers
- HUDs, header, drawers, tooltips, and modals use black glass:
  - `background: rgba(0, 0, 0, 0.85)` to `rgba(0, 0, 0, 0.92)`
  - `backdrop-filter: blur(20px)` / `-webkit-backdrop-filter: blur(20px)`
  - `border: 1px solid rgba(255, 255, 255, 0.08)`
  - Active borders illuminate with theme-colored edge glows (`box-shadow: 0 0 15px rgba(...)`)

#### 2.2.4. Gravitational Lensing Radial Halos
- Replace solid cluster blobs with subtle, ultra-dark radial gradients:
  $$\text{RadialGradient}(r=0 \to R): \quad \text{rgba}(C_{\text{theme}}, 0.12) \longrightarrow \text{rgba}(C_{\text{theme}}, 0.03) \longrightarrow \text{rgba}(0, 0, 0, 0)$$
  Simulates relativistic gravitational lensing around massive architectural clusters.

---

### 2.3. Requirement R3 — Galactic Radar Minimap Decommissioning & Screen Fitting

#### 2.3.1. Minimap Removal
- **DOM**: Remove `<div class="hud-panel hud-minimap">...</div>` and `<canvas id="minimap-canvas">`.
- **CSS**: Remove all `.hud-minimap`, `.minimap-header`, `.minimap-canvas-wrapper`, `#minimap-canvas` rules.
- **JS**: Remove `minimapCanvas`, `minimapCtx`, `renderMinimap()`, `handleMinimapClick()`, and all call sites in render loop and resize handlers.
- **Zoom Telemetry**: Move zoom indicator percentage into the header or HUD stats bar.

#### 2.3.2. Viewport Screen Fitting
- Canvas and workspace occupy exact `100vw × 100vh` bounds with zero scrollbars (`overflow: hidden` on `html, body, .workspace`).
- Header height: exactly `60px` or `64px`.
- High-DPI / Retina support: `canvas.width = width * dpr`, `ctx.scale(dpr, dpr)`.
- Initial camera auto-centers the graph's center-of-mass and scales appropriately for:
  - 1920×1080 (Standard Full HD)
  - 2560×1440 (QHD) & 3840×2160 (4K UHD)
  - 1440×900 & 1366×768 (Laptops)
  - 1024×768 (Tablets) & 375×812 (Mobile Viewports)

---

### 2.4. Requirement R4 — Multiple Design Proposals with Live Theme Selector

All themes share the **Pure Black Hole (#000000)** foundation and **3D Depth Engine**, but provide radically distinct visual identities:

#### 2.4.1. Theme Proposal 1: "Event Horizon" (Relativistic Cyan & Solar Gold)
- **Concept**: Supermassive black hole event horizon with relativistic blueshifting, high-energy synchrotron radiation, and cybernetic telemetry.
- **Palette**: Void Black (`#000000`), Relativistic Cyan (`#00f0ff`), Solar Gold (`#fbbf24`), Ultraviolet Sky (`#38bdf8`), Ruby Flare (`#f43f5e`).
- **Typography**: Display: `Orbitron`, Monospace: `JetBrains Mono`, Body: `Inter`.
- **Node Styling**: Luminous plasma orbs with intense specular cores and dual-layer radiant atmospheric halos.
- **Filaments & Photons**: Ethereal cyan neon filaments with blazing white/cyan photon pulses.
- **UI & Panels**: Cybernetic HUD with cyan laser edge highlights, glassmorphic pill badges, and active glowing indicators.

#### 2.4.2. Theme Proposal 2: "Accretion Disk" (Thermal Orange & Plasma Crimson)
- **Concept**: Swirling relativistic matter disk around a spinning Kerr black hole, radiating extreme thermal energy and magnetic flux.
- **Palette**: Void Black (`#000000`), Thermal Amber (`#ff7b00`), Plasma Crimson (`#ff1e56`), Molten Gold (`#ffd000`), Cosmic Violet (`#a855f7`).
- **Typography**: Display: `Cinzel` / `Syne`, Monospace: `JetBrains Mono`, Body: `Inter`.
- **Node Styling**: Ringed accretion singularities — concentric corona rings pulsing around dense molten cores.
- **Filaments & Photons**: High-energy magnetic flux conduits with amber-to-crimson gradient tapering and plasma sparks.
- **UI & Panels**: Volcanic obsidian glass with warm amber border glows and metallic titanium panel textures.

#### 2.4.3. Theme Proposal 3: "Quantum Void" (Phosphor Emerald & Matrix Lime)
- **Concept**: Deep quantum vacuum fluctuations, zero-point energy fields, and cryptographic matrix wireframes.
- **Palette**: Void Black (`#000000`), Quantum Phosphor Emerald (`#00ff88`), Neon Mint (`#10b981`), Cyber Lime (`#a3e635`), Terminal Slate (`#334155`).
- **Typography**: Display: `JetBrains Mono`, Monospace: `JetBrains Mono`, Body: `Inter`.
- **Node Styling**: Hexagonal and diamond faceted quantum nodes with crisp geometric wireframe borders.
- **Filaments & Photons**: Segmented quantum flux conduits with discrete packet pulses and matrix-style data streams.
- **UI & Panels**: Minimalist tactical terminal with razor-thin phosphor borders, scanline telemetry, and monospace metrics.

#### 2.4.4. Live Theme Switcher Architecture
- UI: Header `<select id="theme-selector">` or styled button group with instant live switching.
- Mechanism:
  - Toggles `data-theme` attribute on `<body>` (`event-horizon`, `accretion-disk`, `quantum-void`).
  - Swaps CSS custom properties (`--color-primary`, `--color-accent`, `--border-glow`, `--font-display`, etc.).
  - Updates canvas rendering configuration and triggers immediate frame redraw.
  - Zero page reload, zero loss of simulation state, selected node, search query, or camera transform.

---

### 2.5. Data Preservation & Asset Invariance

- `docs/data.js` must remain **100% byte-identical**:
  - File Size: `2,835,047` bytes
  - SHA-256 Digest: `b90ac01dc8fff2145506a405594790fadacedcc4bd5f547d4074d9489d6f823e`
  - Encapsulates `window.ROO4U_GRAPH_DATA` for `main` (279 nodes, 164 links, 12 clusters) and `v2` (431 nodes, 334 links, 14 clusters), plus comparisons and transformations.
- `docs/data.json` companion file preserved.

---

### 2.6. Git Workflow & Deployment Constraints

- Target Branch: `main` branch only.
- Hosting Destination: GitHub Pages `/docs` directory (`https://s6pa1rta3n-lab.github.io/roof4u/`).
- Scope of Modifications: Strictly `docs/index.html`, `docs/styles.css`, `docs/app.js`, and root `index.html`.
- Prohibited Modifications: No files outside `docs/` and root `index.html` may be modified. Do not touch external repositories or GitHub Pages root repo (`s6pa1rta3n-lab.github.io`).
- Verification: Local HTTP server test (`python3 -m http.server 8080`) before deployment.

---

## 3. Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| 1 | 3D Depth Engine | Depth-Sorted Node Rendering | Assigns deterministic $z$-coordinate and renders distant nodes first (Painter's algorithm) | Node ID, Layer, Importance | Screen radius, opacity, blur modulated by depth | Fallback to layer-based depth if hash fails | `ORIGINAL_REQUEST.md`, Issue #25, `docs/app.js` |
| 2 | 3D Depth Engine | Tapering & Depth-Fading Filaments | Links between nodes at varying depths modulate stroke width and opacity dynamically | Source/Target node $z$-coords | Scaled canvas stroke with depth gradient | Fallback to default filament width if coords missing | `ORIGINAL_REQUEST.md`, Issue #25 |
| 3 | 3D Depth Engine | Depth-Scaled Photon Streams | Stardust/photon particles scale in size, speed, and emission with link depth | Link depth $\bar{z}$, physics speed | Canvas arc particles moving along links | Clamped to min visible particle size | `ORIGINAL_REQUEST.md`, Issue #25, `docs/app.js` |
| 4 | 3D Depth Engine | Parallax Navigation & Pan/Zoom | Panning moves foreground nodes faster than background nodes, creating spatial depth | D3 zoom transform, mouse delta | Transformed canvas coordinates with parallax offsets | Clamped to zoom extents `[0.15, 4.0]` | `ORIGINAL_REQUEST.md`, Issue #25 |
| 5 | 3D Depth Engine | Mouse-Driven Perspective Tilt | Cursor position relative to center introduces slight 3D angular rotation | Mouse `clientX`, `clientY` | Angular perspective offset in projection | Disabled if mouse leaves canvas | Issue #25 |
| 6 | 3D Depth Engine | Depth Fog Attenuation | Very distant nodes ($s_z < 0.35$) smoothly fade into absolute black | Node depth scale $s_z$ | Opacity multiplier reaching $0$ | Background node remains in hit-index if active | Issue #25 |
| 7 | Black Hole Aesthetic | Pure `#000000` Canvas Backdrop | Document body, workspace, and canvas cleared to pure black void | None (CSS/JS clear) | Absolute black background (`rgb(0,0,0)`) | N/A | `ORIGINAL_REQUEST.md`, Issue #25 |
| 8 | Black Hole Aesthetic | Decommissioned Starfield | Eliminates static twinkling background starfield canvas and loops | None | Zero ambient stars; only graph nodes emit light | Clean removal of unused animation loop | `ORIGINAL_REQUEST.md`, Issue #25, `docs/app.js` |
| 9 | Black Hole Aesthetic | Black Glassmorphism Panels | HUDs and drawers styled with `rgba(0, 0, 0, 0.88)` and subtle border glows | CSS theme classes | Translucent dark glass with blur backdrop | Fallback to solid `#000000` if `backdrop-filter` unsupported | `ORIGINAL_REQUEST.md`, Issue #25, `docs/styles.css` |
| 10 | Black Hole Aesthetic | Gravitational Lensing Nebulas | Cluster glows rendered as subtle, dark radial gradients fading to transparent | Cluster centroid, member nodes | Radial gradient lensing halo | Gracefully skipped for singleton clusters | Issue #25, `docs/app.js` |
| 11 | Viewport & Layout | Minimap Decommissioning | Full removal of galactic radar minimap from HTML, CSS, and JS | User viewport interactions | Reclaimed screen real estate without DOM overhead | Clean removal; no orphaned event listeners | `ORIGINAL_REQUEST.md`, Issue #25 |
| 12 | Viewport & Layout | Full Viewport Fitting (Zero Scrollbars) | Responsive canvas fitting `100vw × 100vh` across 1080p, 4K, laptops, mobile | Window resize events, DPR | Responsive canvas with zero scrollbars | Canvas automatically scales on resize | `ORIGINAL_REQUEST.md`, Issue #25, `docs/styles.css` |
| 13 | Viewport & Layout | Telemetry Zoom Indicator | Displays current zoom level percentage cleanly in header/HUD | Zoom transform scale $k$ | Text string (e.g. `125%`) | Formats correctly across scale range `[15%, 400%]` | `docs/app.js`, Issue #25 |
| 14 | Multi-Theme System | "Event Horizon" Theme | Relativistic Cyan & Solar Gold sci-fi theme with plasma orbs | Theme selection event | CSS variables, canvas palette, plasma shader | Instant switch without reload | `ORIGINAL_REQUEST.md`, `docs/styles.css` |
| 15 | Multi-Theme System | "Accretion Disk" Theme | Thermal Orange & Plasma Crimson theme with concentric ringed nodes | Theme selection event | CSS variables, canvas palette, corona rings | Instant switch without reload | `ORIGINAL_REQUEST.md`, `docs/styles.css` |
| 16 | Multi-Theme System | "Quantum Void" Theme | Phosphor Emerald & Matrix Lime terminal theme with wireframe geometry | Theme selection event | CSS variables, canvas palette, geometric nodes | Instant switch without reload | `ORIGINAL_REQUEST.md`, `docs/styles.css` |
| 17 | Multi-Theme System | Live Header Theme Selector | Dropdown / button UI in header enabling real-time theme swapping | User click / change event | Updates `data-theme`, reconfigures render pipeline | Preserves camera, selection, and physics state | `ORIGINAL_REQUEST.md` |
| 18 | Navigation & Branch | Dual-Branch Architecture Toggle | Switch between Python (`main`, 279 nodes) and OCaml (`v2`, 431 nodes) | Tab click (`#tab-main`, `#tab-v2`) | Re-populates simulation, HUD stats, and chips | Resets active selection and isolates safely | `docs/app.js`, `docs/data.js` |
| 19 | Navigation & Branch | Architecture Shift Modal | Comprehensive comparison table (10 metrics) and module transformation cards | Tab click (`#tab-compare`) | Modal overlay with comparison table & cards | ESC or ✕ closes modal cleanly | `docs/app.js`, `docs/index.html` |
| 20 | Search & Filters | Multi-Field Real-Time Search | Search by file name, symbol, module path, or layer with dropdown | Input text string | Dropdown list of matching nodes with category tags | Shows "No matching files" on empty search | `docs/app.js`, `docs/index.html` |
| 21 | Search & Filters | Search Dropdown Camera Pan | Clicking search result smoothly pans and zooms camera to node (`panToNode`) | Click on search item | Camera transitions and selects node in inspector | Clamps coordinates within canvas bounds | `docs/app.js` |
| 22 | Search & Filters | Swarm Log Toggle | Filter toggle to include or exclude Agent Swarm log nodes (Layer 6) | Checkbox toggle | Re-filters node set and reheats simulation | Preserves other active category filters | `docs/app.js`, `docs/index.html` |
| 23 | Search & Filters | Constellation Sector Chips | Interactive category filter chips with node counts and color badges | Click on chip | Filters graph to selected category subset | Clicking active chip toggles filter off | `docs/app.js`, `docs/index.html` |
| 24 | Inspector & Telemetry | Node Inspector Drawer | Sliding right drawer displaying metadata, LOC, size, layer, SHA-256, code | Click on node / search hit | Populated drawer with 4 tabs (Overview, Filaments, Symbols, Preview) | Hidden on ESC or background click | `docs/app.js`, `docs/index.html` |
| 25 | Inspector & Telemetry | Interactive Hover Tooltip | Lightweight floating HUD showing category, path, LOC, and degree on hover | Mouse move over node | Positioned tooltip near cursor | Hidden when cursor leaves node hit-box | `docs/app.js` |
| 26 | Inspector & Telemetry | Constellation Isolation Mode | Isolate 1-hop and 2-hop connected network around selected node | "Isolate Connected Constellation" button | Highlights connected graph, dims all other nodes/links | "Reset Isolation" restores full view | `docs/app.js` |
| 27 | Inspector & Telemetry | One-Click SHA-256 Copy | Copies full 64-character SHA-256 digest to system clipboard | Click copy icon button | Clipboard write with visual checkmark confirmation | Fallback if clipboard API restricted | `docs/app.js` |
| 28 | Layout Modes | Multi-Layout Engine | Switch layout: Cosmic Orbit (Force), Concentric Rings, Layered Hierarchy, Galactic Sectors | Dropdown select (`#layout-mode`) | Applies specialized D3 forces and animates transitions | Reheats simulation smoothly without node explosions | `docs/app.js` |
| 29 | Physics Simulation | Cosmic Simulation Physics Drawer | Sliders for Repulsion Charge, Filament Distance, Collision Radius, Gravity, Photon Speed | Slider inputs in drawer | Real-time simulation parameter modulation | "Reset Physics" restores default equilibrium | `docs/app.js`, `docs/index.html` |
| 30 | Data Preservation | Embedded Graph Dataset Invariance | Exact preservation of repository architecture extracted dataset in `docs/data.js` | Browser script tag | `window.ROO4U_GRAPH_DATA` global data object | SHA-256 must match `b90ac01d...` byte-for-byte | `ORIGINAL_REQUEST.md`, `docs/data.js` |
| 31 | Deployment & Hosting | Root Index Redirect | Root `index.html` directs visitors instantly to `docs/index.html` | HTTP request to `/` | Client-side redirect to `/docs/index.html` | Fallback HTML link provided | `index.html` |

---

## 4. Edge Cases & Boundary Conditions

| # | Feature | Input / Condition | Observed / Required Behavior |
|---|---------|-------------------|-----------------------------|
| 1 | 3D Depth Engine | Extreme Zoom Out ($k = 0.15$) | Node radii scale down but clamp to minimum visible starlight pinpoint ($0.8\text{px}$) to prevent invisible nodes. |
| 2 | 3D Depth Engine | Extreme Zoom In ($k = 4.0$) | Halos and glow shaders scale proportionally without pixelation or clipping at canvas boundaries. |
| 3 | 3D Depth Engine | Zero-Link Singleton Nodes | Single nodes at any $z$-depth render correctly with size/halo modulation; no missing filament errors. |
| 4 | 3D Depth Engine | Co-planar / Clustered Nodes | Depth sorting handles identical $z$ values deterministically via node `id` tie-breaking to avoid z-fighting flicker. |
| 5 | Black Hole Aesthetic | Dynamic Resizing on Mobile / Split-Screen | Canvas resize clears with pure `#000000`; zero flash of white or default browser canvas background. |
| 6 | Black Hole Aesthetic | Low-End Device GPU Fallback | If `backdrop-filter: blur()` is unsupported, panels fallback to solid `rgba(0, 0, 0, 0.95)` with clean contrast. |
| 7 | Minimap Decommissioning | Legacy Click / Pan Calls | All references to `#minimap-canvas` and `renderMinimap()` are removed; no `null.getContext` or undefined errors. |
| 8 | Viewport Fitting | 4K UHD (3840×2160) Resolution | Canvas buffer matches `width * dpr` (up to 2× DPR = 7680×4320); UI scaling maintains sharp typography and zero scrollbars. |
| 9 | Viewport Fitting | Header Window Resize / Wrap | Header flex items wrap or truncate gracefully; graph canvas height remains `calc(100vh - headerHeight)`. |
| 10 | Multi-Theme System | Rapid Live Theme Switching | Switching themes during an ongoing D3-force simulation transition updates canvas styling immediately without frame drops or memory leaks. |
| 11 | Multi-Theme System | Theme Switch with Active Isolation | Active isolated constellation maintains theme-specific highlight colors and dimmed background styles seamlessly. |
| 12 | Branch Switching | Switch Branch while Drawer is Open | Inspector drawer closes or updates its contents to avoid displaying stale nodes from the previous branch. |
| 13 | Branch Switching | Category Filter Active across Branches | Clusters with identical category IDs remain filtered; nonexistent category IDs in the target branch are cleanly omitted. |
| 14 | Swarm Log Toggle | Swarm Toggled Off with Selected Swarm Node | If the currently selected node is a swarm log and swarm logs are disabled, selection clears and drawer closes cleanly. |
| 15 | Search & Autocomplete | Special Characters in Search (Regex/Quotes) | Search input is safely escaped for substring matching; does not throw syntax or DOM errors. |
| 16 | Search & Autocomplete | Search Miss (No Matching Files) | Search dropdown displays a styled "No matching files found" notification; does not break UI. |
| 17 | Clipboard API | Clipboard Restricted / Blocked Context | When `navigator.clipboard.writeText` fails or is denied, UI falls back gracefully without throwing unhandled promise rejections. |
| 18 | Data Integrity | `docs/data.js` Exact Verification | Automated SHA-256 checksum verification ensures zero accidental modifications or whitespace changes to data file. |

---

## 5. Acceptance Criteria Checklist

- [x] **AC-1 (3D Depth Engine)**: Nodes have assigned $z$-coordinates modulating render size, brightness, opacity, and glow halo.
- [x] **AC-2 (Parallax Navigation)**: Parallax motion observed on pan/zoom with distant elements shifting at lower velocity.
- [x] **AC-3 (Filament Tapering & Depth)**: Links between nodes fade and taper into the background void based on link depth.
- [x] **AC-4 (Depth Sorting)**: Render loop executes Painter's algorithm (distant elements drawn first, foreground elements drawn last).
- [x] **AC-5 (Pure Black Hole Aesthetic)**: Document body, canvas background, and clearing color are pure `#000000` (`rgb(0,0,0)`).
- [x] **AC-6 (Zero Ambient Starfield)**: Static background starfield canvas and twinkling loops are completely decommissioned.
- [x] **AC-7 (Black Glassmorphism)**: All HUDs, drawers, and headers use pure black glass (`rgba(0, 0, 0, 0.85–0.92)`) with neon theme edge glows.
- [x] **AC-8 (Minimap Decommissioned)**: Galactic radar minimap DOM elements, CSS classes, and JavaScript rendering logic are completely removed.
- [x] **AC-9 (Full Viewport Fitting)**: Application fills viewport (`100vw × 100vh`) with zero horizontal or vertical scrollbars across all screen sizes.
- [x] **AC-10 (Minimum 3 Distinct Themes)**: "Event Horizon", "Accretion Disk", and "Quantum Void" themes implemented with custom palettes, typography, controls, and node/filament shaders.
- [x] **AC-11 (Live Theme Selector)**: Real-time theme switching in navigation header without page reload or state loss.
- [x] **AC-12 (Data Preservation)**: `docs/data.js` remains 100% byte-identical (SHA-256: `b90ac01dc8fff2145506a405594790fadacedcc4bd5f547d4074d9489d6f823e`).
- [x] **AC-13 (Deployment Safety)**: Changes confined to `docs/` and root `index.html` on `main` branch, verified via local HTTP test server.

