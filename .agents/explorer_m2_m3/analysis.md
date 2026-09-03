# Analysis Report: Milestone 2 & Milestone 3 Blueprint
**Agent**: `teamwork_preview_explorer` (M2 & M3 Exploration)  
**Date**: 2026-09-01  
**Target Files**: `docs/index.html`, `docs/styles.css`, `docs/app.js`  
**Test Harness**: `tests/e2e/test_runner.py` (Tiers 1–4)

---

## Executive Summary

This report establishes the complete architectural analysis and line-by-line implementation blueprint for:
1. **Milestone 2 (Pure Black Hole Void & Minimap Decommissioning)**:
   - Enforcing pure `#000000` (`rgb(0, 0, 0)`) void across `html`, `body`, `.workspace`, and `#graph-canvas`.
   - Complete decommissioning of the static starfield canvas (`#starfield-canvas`, `initStarfield()`, `renderStarfield()`).
   - Upgrading all UI glassmorphism elements (header, HUDs, drawers, tooltips, modals) to pure black-based translucency (`rgba(0, 0, 0, 0.88)` to `rgba(0, 0, 0, 0.96)`).
   - Complete removal of the galactic radar minimap (`#minimap-canvas`, `.hud-minimap`, `renderMinimap()`, `handleMinimapClick()`) and relocating `#zoom-indicator` to the top header.
   - Enforcing 100vh viewport fitting (`overflow: hidden`) with zero scrollbars across all target resolutions: 1920×1080 FHD, 1440×900, 1366×768, and 375×812 mobile viewport.
2. **Milestone 3 (Design Proposals & Live Zero-Reload Theme Switcher)**:
   - Defining 3 distinct design themes sharing the 3D depth and pure black hole foundation:
     - **Theme 1: "Event Horizon"** (Cyan `#00f0ff` / Violet `#7000ff`, Plasma node shader, Electric beam filaments, JetBrains Mono font).
     - **Theme 2: "Accretion Disk"** (Solar Gold `#ffaa00` / Crimson `#ff3300`, Thermal corona node shader, Solar flare filaments, Space Grotesk font).
     - **Theme 3: "Quantum Void"** (Cyber Emerald `#00ff88` / Deep Teal `#006644`, Matrix grid node shader, Quantum flux filaments, Fira Code font).
   - Embedding a live `<select id="theme-selector">` in the top header with instantaneous theme switching without page reload.
   - Dynamic canvas shader palette modulation and persistent theme selection in `localStorage`.

---

## 1. Baseline Test Suite Verification & Failure Analysis

Running `python3 tests/e2e/test_runner.py` on the baseline repository produces:
- Total Tests: 17
- Passed: 11 (64.7%)
- Failed: 6 (35.3%)

### Detailed Breakdown of Baseline Failures

| Test ID | Requirement | Failure Reason in Baseline | Root Cause in Codebase |
|---|---|---|---|
| `T1.2_BLACK_HOLE_VOID` | R2 Pure Black Hole Void | `document.body background must be pure black rgb(0,0,0), got: rgb(6, 8, 18)` | `styles.css:7`: `--bg-deep-space: #060812;` |
| `T1.3_GLASS_PANELS_STARFIELD` | R2 Starfield Removal & Black Glassmorphism | `Static starfield canvas is still present and active in DOM/view!` | `index.html:113`: `<canvas id="starfield-canvas"></canvas>` & `styles.css:9`: `--bg-surface-glass: rgba(13, 18, 36, 0.75)` |
| `T1.4_MINIMAP_REMOVAL_VIEWPORT` | R3 Minimap Removal & 100vh Fitting | `Minimap canvas #minimap-canvas is still present in DOM!` | `index.html:181-189`: `.hud-minimap` & `#minimap-canvas` present |
| `T1.6_THEME_SWITCHER` | R4 3 Design Proposals & Live Selector | `Theme selector element (#theme-selector) not found in header/DOM!` | `index.html`: `#theme-selector` element missing |
| `T2.3_RAPID_THEME_TOGGLE` | R4 Rapid Theme Switching Stability | `No #theme-selector` | `index.html`: `#theme-selector` missing |
| `T2.4_MULTI_VIEWPORT_FITTING` | R3 Multi-Resolution Screen Fitting | `Viewport 375x812 Mobile Viewport failed scrollbar check: Scrollbar detected: docScroll=(1142x812) vs window=(375x812)` | `styles.css`: `.app-header` lacks responsive collapsing on `<600px` viewports, forcing `scrollWidth` to 1142px |

---

## 2. Milestone 2 Implementation Blueprint

### 2.1 Pure Black Void Styling (`#000000`)
- **Target File**: `docs/styles.css`
- **Modifications**:
  1. Set `--bg-void: #000000;`, `--bg-deep-space: #000000;`, `--bg-space-dark: #000000;`.
  2. Set `html, body` rule:
     ```css
     html, body {
       width: 100%;
       height: 100%;
       max-width: 100vw;
       max-height: 100vh;
       overflow: hidden;
       background-color: #000000;
       color: var(--text-main);
       font-family: var(--font-sans);
     }
     ```
  3. Set `.workspace`, `.graph-container`, and `#graph-canvas` to `background-color: #000000;`.

### 2.2 Starfield Decommissioning
- **Target Files**: `docs/index.html`, `docs/styles.css`, `docs/app.js`
- **Modifications**:
  1. `docs/index.html`: Remove `<canvas id="starfield-canvas"></canvas>` (line 113).
  2. `docs/styles.css`: Remove `#starfield-canvas` rule block (lines 430-437).
  3. `docs/app.js`:
     - Remove `const starfieldCanvas = document.getElementById('starfield-canvas');`
     - Remove `const starfieldCtx = ...`
     - Remove `state.starfield` array
     - Remove `initStarfield()` and `renderStarfield()` functions
     - Remove calls to `initStarfield()` and `renderStarfield()` in lifecycle hooks and render loop.

### 2.3 Black Glassmorphism Refactoring
- **Target File**: `docs/styles.css`
- **Modifications**:
  - Update all translucent glass variables:
    ```css
    --bg-surface-glass: rgba(0, 0, 0, 0.88);
    --bg-surface-elevated: rgba(0, 0, 0, 0.92);
    --bg-surface-active: rgba(0, 0, 0, 0.96);
    --border-glass: rgba(255, 255, 255, 0.08);
    --border-glass-bright: rgba(255, 255, 255, 0.16);
    ```
  - Apply black glassmorphism to:
    - `.app-header`: `background: var(--bg-surface-glass);`
    - `.hud-panel` (`.hud-stats`, `.hud-filters`): `background: var(--bg-surface-glass);`
    - `.search-dropdown`: `background: var(--bg-surface-elevated);`
    - `.graph-tooltip`: `background: rgba(0, 0, 0, 0.92);`
    - `.inspector-drawer`, `.physics-drawer`: `background: var(--bg-surface-elevated);`
    - `.compare-modal`: `background: rgba(0, 0, 0, 0.85);`
    - `.compare-modal-content`: `background: var(--bg-surface-elevated);`
    - `.code-preview-block`: `background: #000000;`

### 2.4 Minimap Removal & Zoom Indicator Relocation
- **Target Files**: `docs/index.html`, `docs/styles.css`, `docs/app.js`
- **Modifications**:
  1. `docs/index.html`:
     - Delete the entire `.hud-minimap` container:
       ```html
       <!-- Radar Minimap (Bottom-Right) -->
       <div class="hud-panel hud-minimap"> ... </div>
       ```
     - Add `#zoom-indicator` in `.header-right`:
       ```html
       <!-- Zoom Indicator (Relocated from Minimap) -->
       <div class="zoom-badge" title="Camera Zoom Level">
         <span id="zoom-indicator" class="zoom-indicator">100%</span>
       </div>
       ```
  2. `docs/styles.css`:
     - Remove `.hud-minimap`, `.minimap-header`, `.minimap-canvas-wrapper`, `#minimap-canvas`.
     - Add `.zoom-badge` styling:
       ```css
       .zoom-badge {
         display: flex;
         align-items: center;
         justify-content: center;
         background: rgba(0, 0, 0, 0.7);
         border: 1px solid var(--border-glass);
         border-radius: 8px;
         padding: 0 10px;
         height: 34px;
         font-family: var(--font-mono);
         font-size: 11px;
         font-weight: 600;
         color: var(--color-primary);
         user-select: none;
       }
       ```
  3. `docs/app.js`:
     - Remove `minimapCanvas`, `minimapCtx`, `renderMinimap()`, `handleMinimapClick()`, and the event listener on `minimapCanvas`.
     - Maintain `updateZoomIndicator()` to update the DOM text on zoom transforms.

### 2.5 Viewport 100vh Screen Fitting & Multi-Resolution Responsive Rules
- **Target File**: `docs/styles.css`
- **Modifications**:
  - Add strict box-sizing and overflow restrictions:
    ```css
    html, body {
      max-width: 100vw;
      max-height: 100vh;
      overflow: hidden;
    }
    .app-header {
      max-width: 100vw;
      overflow: hidden;
      box-sizing: border-box;
    }
    .workspace {
      max-width: 100vw;
      overflow: hidden;
    }
    ```
  - Add comprehensive media queries for `< 960px`, `< 600px`, and `< 380px` to hide or shrink auxiliary controls (e.g. brand tagline, category filters HUD, search input width) ensuring `document.documentElement.scrollWidth <= window.innerWidth` across all 4 tested screen sizes (1920×1080, 1440×900, 1366×768, 375×812).

---

## 3. Milestone 3 Implementation Blueprint

### 3.1 Three Distinct Design Themes
The 3 design proposals are defined with unique visual signatures:

| Dimension | Theme 1: "Event Horizon" | Theme 2: "Accretion Disk" | Theme 3: "Quantum Void" |
|---|---|---|---|
| **Key Palette** | Primary: `#00f0ff` (Cyan)<br>Secondary: `#7000ff` (Violet)<br>Accent: `#ffffff` (Pure White)<br>Glow: `rgba(0, 240, 255, 0.4)` | Primary: `#ffaa00` (Solar Gold)<br>Secondary: `#ff3300` (Crimson)<br>Accent: `#fff3d1` (Warm Starlight)<br>Glow: `rgba(255, 170, 0, 0.4)` | Primary: `#00ff88` (Cyber Emerald)<br>Secondary: `#006644` (Deep Teal)<br>Accent: `#e0fff0` (Mint White)<br>Glow: `rgba(0, 255, 136, 0.4)` |
| **Node Shader** | `plasma`: Dual-ring electric aura, high-frequency core | `solar`: Thermal corona, solar flare aura, fiery radiant core | `matrix`: Cyber grid nodes, digital data pulses |
| **Filament Shader** | `plasma-beam`: Electric beam gradient with starlight white core | `solar-flare`: Solar magnetic arcs with warm golden core | `quantum-flux`: Quantum flux pulses with neon mint core |
| **Typography** | `JetBrains Mono, monospace` | `Space Grotesk, sans-serif` | `Fira Code, monospace` |
| **CSS Class / Attr** | `.theme-event-horizon` / `data-theme="event-horizon"` | `.theme-accretion-disk` / `data-theme="accretion-disk"` | `.theme-quantum-void` / `data-theme="quantum-void"` |

### 3.2 HTML Theme Selector Markup
- **Target File**: `docs/index.html`
- **Markup**:
  ```html
  <!-- Live Theme Selector Dropdown (M3) -->
  <div class="theme-selector-wrapper">
    <label for="theme-selector" class="theme-label" title="Cosmic Theme">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="12" cy="12" r="5"></circle>
        <line x1="12" y1="1" x2="12" y2="3"></line>
        <line x1="12" y1="21" x2="12" y2="23"></line>
        <line x1="4.22" y1="4.22" x2="5.64" y2="5.64"></line>
        <line x1="18.36" y1="18.36" x2="19.78" y2="19.78"></line>
        <line x1="1" y1="12" x2="3" y2="12"></line>
        <line x1="21" y1="12" x2="23" y2="12"></line>
        <line x1="4.22" y1="19.78" x2="5.64" y2="18.36"></line>
        <line x1="18.36" y1="5.64" x2="19.78" y2="4.22"></line>
      </svg>
      Theme
    </label>
    <select id="theme-selector" class="theme-select" aria-label="Theme Selector">
      <option value="event-horizon" selected>Event Horizon (Cyan / Violet)</option>
      <option value="accretion-disk">Accretion Disk (Solar Gold / Amber)</option>
      <option value="quantum-void">Quantum Void (Cyber Emerald / Teal)</option>
    </select>
  </div>
  ```

### 3.3 Google Fonts Ingestion
- **Target File**: `docs/index.html`
- Include all necessary font families:
  ```html
  <link href="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;500;600;700&family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500;700&family=Orbitron:wght@600;800;900&family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet">
  ```

### 3.4 Live Theme Switcher Architecture in `docs/app.js`
- **State & Theme Config**:
  ```javascript
  const THEMES = {
    'event-horizon': {
      name: 'Event Horizon',
      cssClass: 'theme-event-horizon',
      palette: { primary: '#00f0ff', secondary: '#7000ff', accent: '#ffffff', glow: 'rgba(0, 240, 255, 0.4)' },
      nodeStyle: 'plasma',
      filamentStyle: 'plasma-beam',
      font: 'JetBrains Mono, monospace'
    },
    'accretion-disk': {
      name: 'Accretion Disk',
      cssClass: 'theme-accretion-disk',
      palette: { primary: '#ffaa00', secondary: '#ff3300', accent: '#fff3d1', glow: 'rgba(255, 170, 0, 0.4)' },
      nodeStyle: 'solar',
      filamentStyle: 'solar-flare',
      font: 'Space Grotesk, sans-serif'
    },
    'quantum-void': {
      name: 'Quantum Void',
      cssClass: 'theme-quantum-void',
      palette: { primary: '#00ff88', secondary: '#006644', accent: '#e0fff0', glow: 'rgba(0, 255, 136, 0.4)' },
      nodeStyle: 'matrix',
      filamentStyle: 'quantum-flux',
      font: 'Fira Code, monospace'
    }
  };
  ```
- **Lifecycle & Persistence**:
  ```javascript
  function initTheme() {
    let savedTheme = 'event-horizon';
    try {
      savedTheme = localStorage.getItem('roo4u_theme') || 'event-horizon';
    } catch (e) {}
    if (!THEMES[savedTheme]) savedTheme = 'event-horizon';
    setTheme(savedTheme);
  }

  function setTheme(themeKey) {
    if (!THEMES[themeKey]) return;
    state.theme = themeKey;
    document.body.setAttribute('data-theme', themeKey);
    document.body.className = `theme-${themeKey}`;
    
    const selector = document.getElementById('theme-selector');
    if (selector && selector.value !== themeKey) {
      selector.value = themeKey;
    }
    try {
      localStorage.setItem('roo4u_theme', themeKey);
    } catch (e) {}
  }
  ```
- **Shader Palettes**:
  - `renderNode3D()` reads `activeTheme = THEMES[state.theme]` and renders halos, beacons, and cores matching theme styles.
  - `renderLink3D()` renders filaments with linear gradients from `activeTheme.palette.primary` to `activeTheme.palette.secondary`.
  - `drawPhotonParticle()` draws photons in `activeTheme.palette.primary` or `activeTheme.palette.accent`.
  - `renderLabels3D()` uses `activeTheme.font`.

---

## 4. Requirement Verification & Test Alignment

| Requirement | Test Assertion | Target File(s) | Verification Command |
|---|---|---|---|
| R2 Pure Black Void | `T1.2_BLACK_HOLE_VOID` | `docs/styles.css` | `python3 tests/e2e/test_runner.py --tier 1` |
| R2 Starfield Cleanup & Glassmorphism | `T1.3_GLASS_PANELS_STARFIELD` | `docs/index.html`, `docs/styles.css`, `docs/app.js` | `python3 tests/e2e/test_runner.py --tier 1` |
| R3 Minimap Removal & 100vh Viewport | `T1.4_MINIMAP_REMOVAL_VIEWPORT` | `docs/index.html`, `docs/styles.css`, `docs/app.js` | `python3 tests/e2e/test_runner.py --tier 1` |
| R4 Design Proposals & Theme Switcher | `T1.6_THEME_SWITCHER` | `docs/index.html`, `docs/styles.css`, `docs/app.js` | `python3 tests/e2e/test_runner.py --tier 1` |
| Rapid Theme Toggling (12x Cycles) | `T2.3_RAPID_THEME_TOGGLE` | `docs/app.js` | `python3 tests/e2e/test_runner.py --tier 2` |
| Multi-Resolution Screen Fitting | `T2.4_MULTI_VIEWPORT_FITTING` | `docs/styles.css` | `python3 tests/e2e/test_runner.py --tier 2` |
| Complete Test Suite (17/17 PASS) | Tiers 1, 2, 3, 4 | All 3 docs files | `python3 tests/e2e/test_runner.py` |

---

## 5. Risk Assessment & Invariance Guardrails

1. **Dataset Invariance**: `docs/data.js` must remain untouched and byte-identical (SHA-256: `b90ac01dc8fff2145506a405594790fadacedcc4bd5f547d4074d9489d6f823e`).
2. **Global Export Preservation**: `window.state`, `window.currentGraph`, `window.simulation`, `window.zoomBehavior`, `window.project3D`, `window.THEMES`, `window.setTheme` must remain bound to `window` for test automation fixtures.
3. **No External Dependencies**: Keep vanilla JS / CSS with only D3 v7 and Google Fonts loaded via CDN.
4. **Git Branch Discipline**: All changes belong on `main` branch under `docs/`.
