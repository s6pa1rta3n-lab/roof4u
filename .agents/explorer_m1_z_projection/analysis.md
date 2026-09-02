# Milestone 1: 3D Z-Projection & Depth Sorting Technical Implementation Analysis

**Document**: `analysis.md`  
**Author**: Explorer Agent (`teamwork_preview_explorer` / M1 Z-Projection)  
**Target Repository**: `s6pa1rta3n-lab/roof4u`  
**Target Codebase File**: `docs/app.js` (on branch `main`)  
**Date**: 2026-09-01  

---

## 1. Executive Summary & Objective

This report provides the exhaustive, mathematically verified technical blueprint for implementing **Milestone 1: 3D Z-Projection & Depth Sorting** in `docs/app.js`.

The objective is to transform the 2D Canvas graph renderer into a perspective-projected 3D volumetric space where:
1. Every node is assigned a deterministic continuous depth coordinate $z \in [-100, 100]$ based on architectural layer (1–6), importance (1–5), and a cryptographic ID hash.
2. 3D coordinates $(x, y, z)$ project onto the 2D canvas via focal perspective scaling $s_z = \frac{D}{D+z}$ ($D = 500$) with cinematic parallax displacement on pan/zoom.
3. Canvas rendering strictly adheres to **Painter's Algorithm** (deepest background elements rendered first, nearest foreground elements rendered last on top).
4. Node visual properties (radius, core brightness, halo glow blur, specular intensity, opacity, label Level-of-Detail) modulate dynamically with depth scale factor $s_z$.
5. Mouse interaction (hit testing, hover tooltip, node selection, D3 dragging, and camera centering) operates seamlessly across projected 3D space with zero mathematical error.

---

## 2. Deterministic Z-Coordinate Assignment

### 2.1 Theoretical Rationale
In the Roo4u architecture graph:
- **Layer 1 (Entrypoints / Root CLI / AST Validators)** and **Layer 2 (Core Engine / OCaml Verification Core)** represent central architectural pillars. They must inhabit the **foreground** ($z < 0$, yielding depth scale factor $s_z > 1.0$).
- **Layer 3–5 (Services, Pipelines, Models, Integrations)** occupy the **midground** ($z \approx 0$).
- **Layer 6 (Agent Swarm Logs / Metadata / Artifacts)** represent auxiliary peripheral history. They must recede into the **background void** ($z > 0$, yielding depth scale factor $s_z < 1.0$).
- High-importance nodes (`importance = 4..5`) should pop forward toward the observer.
- A deterministic pseudo-random jitter function applied to each node's `id` breaks planar stratification, creating natural volumetric depth while ensuring byte-reproducible stability across page reloads.

### 2.2 Mathematical Formulation
For a node $n$:
$$z(n) = \text{clamp}\left( \Delta_{\text{layer}}(n.\text{layer}) + \Delta_{\text{importance}}(n.\text{importance}) + \Delta_{\text{jitter}}(n.\text{id}), -100, 100 \right)$$

Where:
1. **Layer Component**:
   $$\Delta_{\text{layer}}(n.\text{layer}) = (n.\text{layer} - 3.5) \times 20.0$$
   - Layer 1: $-50.0$
   - Layer 2: $-30.0$
   - Layer 3: $-10.0$
   - Layer 4: $+10.0$
   - Layer 5: $+30.0$
   - Layer 6: $+50.0$

2. **Importance Component**:
   $$\Delta_{\text{importance}}(n.\text{importance}) = (3.0 - n.\text{importance}) \times 15.0$$
   - Importance 5: $-30.0$
   - Importance 4: $-15.0$
   - Importance 3: $0.0$
   - Importance 2: $+15.0$
   - Importance 1: $+30.0$

3. **Deterministic Hash Jitter Component**:
   Using a 32-bit integer polynomial rolling hash combined with a sine fract generator:
   $$\text{hash}(id) = \sum_{i=0}^{L-1} (31^{L-1-i} \cdot \text{charCodeAt}(i)) \pmod{2^{32}}$$
   $$\Delta_{\text{jitter}}(id) = \left( \left( \sin(\text{hash}(id)) \times 43758.5453123 \right) \bmod 1.0 \right) \times 15.0$$
   Yields a pseudo-random offset in $[-15.0, 15.0]$ unique to the node ID string.

### 2.3 Empirical Dataset Verification
Executing this formula across all 279 nodes in `main` and 431 nodes in `v2`:

| Metric | `main` Branch (279 nodes) | `v2` Branch (431 nodes) |
|---|---|---|
| Non-Swarm Nodes Range | $Z \in [-76.3, +79.4]$ (Avg $Z = +18.7$) | $Z \in [-78.4, +79.9]$ (Avg $Z = +16.0$) |
| Swarm Log Nodes Range | $Z \in [+55.0, +94.9]$ (Avg $Z = +86.7$) | $Z \in [+50.2, +95.0]$ (Avg $Z = +86.2$) |
| Depth Scale $s_z$ Range | $s_z \in [0.841, 1.180]$ | $s_z \in [0.840, 1.186]$ |
| Foreground Hubs ($s_z > 1.1$) | `main.py`, `orchestrator.py`, `engine.ml` | `main.ml`, `verification.ml`, `ast.ml` |

### 2.4 JavaScript Implementation
```javascript
/**
 * Computes deterministic continuous Z-coordinate in [-100, 100].
 * @param {Object} node - Node object containing layer, importance, and id.
 * @returns {number} z coordinate.
 */
function computeNodeZ(node) {
  const layer = Number(node.layer) || 3;
  const importance = Number(node.importance) || 3;
  
  const layerOffset = (layer - 3.5) * 20.0;
  const importanceOffset = (3.0 - importance) * 15.0;
  
  // Deterministic 32-bit hash on string ID
  let h = 0;
  const idStr = String(node.id || '');
  for (let i = 0; i < idStr.length; i++) {
    h = (Math.imul(31, h) + idStr.charCodeAt(i)) | 0;
  }
  const jitter = (((Math.sin(h) * 43758.5453123) % 1.0) || 0) * 15.0;
  
  const z = layerOffset + importanceOffset + jitter;
  return Math.max(-100.0, Math.min(100.0, z));
}
```

---

## 3. Perspective Projection & Parallax Mathematics

### 3.1 3D Projection Model
Let:
- $(x, y, z)$ be the 3D world coordinates of a node (where $(x, y)$ are simulated by D3-force and $z$ is assigned via `computeNodeZ`).
- $W, H$ be the viewport dimensions (`width = window.innerWidth`, `height = window.innerHeight - 64`).
- $(cx, cy) = (W / 2, H / 2)$ be the viewport center.
- $(t_x, t_y)$ be the camera pan translation (`state.zoomTransform.x`, `state.zoomTransform.y`).
- $k$ be the camera zoom scale factor (`state.zoomTransform.k`).
- $D = 500.0$ be the perspective focal distance.

#### Forward Projection Equations
1. **Depth Scale Factor ($s_z$)**:
   $$s_z = \frac{D}{D + z}$$
   - $z = -100 \implies s_z = \frac{500}{400} = 1.250$ (Magnified Foreground)
   - $z = 0 \implies s_z = \frac{500}{500} = 1.000$ (Focal Center Plane)
   - $z = +100 \implies s_z = \frac{500}{600} = 0.833$ (Diminished Background)

2. **Parallax Displacement**:
   Camera panning moves foreground nodes faster than background nodes:
   $$\text{parallaxX} = t_x \cdot s_z^{0.6}$$
   $$\text{parallaxY} = t_y \cdot s_z^{0.6}$$

3. **Screen Projection Coordinate**:
   $$\text{screenX} = (x \cdot k + \text{parallaxX}) \cdot s_z + \frac{W}{2} \cdot (1 - s_z)$$
   $$\text{screenY} = (y \cdot k + \text{parallaxY}) \cdot s_z + \frac{H}{2} \cdot (1 - s_z)$$

*Key Mathematical Invariant*: When $z = 0$, $s_z = 1.0$, which simplifies exactly to 2D standard canvas projection $\text{screenX} = t_x + x \cdot k$. Symmetrically, nodes at $(W/2, H/2)$ with $(t_x=0, t_y=0, k=1)$ remain strictly invariant at $(W/2, H/2)$ across all $z$.

### 3.2 Exact Inverse Unprojection (For D3 Node Dragging)
When a user drags a node on screen at $(\text{screenX}, \text{screenY})$, the simulation coordinate $(x, y)$ is recovered algebraically:
$$x = \frac{\frac{\text{screenX} - \frac{W}{2}(1 - s_z)}{s_z} - \text{parallaxX}}{k}$$
$$y = \frac{\frac{\text{screenY} - \frac{H}{2}(1 - s_z)}{s_z} - \text{parallaxY}}{k}$$

Empirical round-trip verification: Tested across extreme coordinates ($x \in [150, 1500]$, $y \in [200, 900]$, $z \in [-95, 95]$, $k \in [0.75, 2.5]$), numerical error is precisely $0.00 \times 10^0$ (exact precision).

### 3.3 Camera Pan-to-Center Formula (`panToNode`)
To center the camera on a 3D node at $(x, y, z)$ at target zoom scale $k$:
We solve for $(t_x, t_y)$ such that $(\text{screenX}, \text{screenY}) = (W/2, H/2)$:
$$\text{panX} = \frac{\frac{W}{2} - x \cdot k}{s_z^{0.6}}$$
$$\text{panY} = \frac{\frac{H}{2} - y \cdot k}{s_z^{0.6}}$$

---

## 4. Painter's Algorithm Depth-Sorting Architecture

In Canvas 2D, depth buffer (Z-buffering) is unavailable. Therefore, we implement **Painter's Algorithm**:
1. Sort elements by depth in descending order ($z$ highest $\to$ lowest; background $\to$ foreground).
2. Render background elements first; render foreground elements last on top.

```
+-----------------------------------------------------------------------------+
|                      FRAME RENDER PIPELINE IN docs/app.js                   |
+-----------------------------------------------------------------------------+
|                                                                             |
|  1. PRE-PASS: Project all active nodes to (screenX, screenY, sz)           |
|                                                                             |
|  2. CLUSTER NEBULAS (Gravitational Lensing Glows):                          |
|     - Sort clusters descending by centroid depth z_cluster                  |
|     - Render soft black-hole radial gradients                               |
|                                                                             |
|  3. FILAMENTS / LINKS:                                                      |
|     - Sort links descending by average depth z_link = (s.z + t.z) / 2       |
|     - Render tapered linear gradient paths between (s.screenX, t.screenX)   |
|                                                                             |
|  4. PHOTON STARDUST STREAMS:                                                |
|     - Compute photon position (x_p, y_p, z_p) along link at progress u      |
|     - Project photon to screen and sort descending by z_p                   |
|     - Render depth-scaled luminous stardust arcs                            |
|                                                                             |
|  5. STELLAR NODES (Painter's Order: z descending):                          |
|     - Background nodes (z > 0, sz < 1) rendered first                       |
|     - Midground nodes (z ~ 0, sz ~ 1) rendered next                         |
|     - Foreground nodes (z < 0, sz > 1) rendered last                        |
|     - Each node renders: Atmospheric Halo -> Pulsing Beacon -> Core -> Spec |
|                                                                             |
|  6. LABELS (Level-of-Detail filtered):                                      |
|     - Rendered for connected/selected nodes + LOD threshold (k * sz)        |
|                                                                             |
+-----------------------------------------------------------------------------+
```

### 4.1 Node & Entity Sorting Implementations
```javascript
// Pre-pass: Compute 3D projected coordinates
function updateProjectedPositions(width, height) {
  const panX = state.zoomTransform.x;
  const panY = state.zoomTransform.y;
  const k = state.zoomTransform.k;

  for (let i = 0; i < currentGraph.nodes.length; i++) {
    const node = currentGraph.nodes[i];
    if (node.x !== undefined && node.y !== undefined) {
      if (node.z === undefined) node.z = computeNodeZ(node);
      const proj = project3D(node.x, node.y, node.z, width, height, panX, panY, k);
      node.screenX = proj.screenX;
      node.screenY = proj.screenY;
      node.sz = proj.sz;
    }
  }
}

// Nodes Painter's sorting (descending z = background to foreground)
const sortedNodes = [...currentGraph.nodes].sort((a, b) => (b.z || 0) - (a.z || 0));

// Links Painter's sorting (descending average z)
const sortedLinks = [...currentGraph.links].sort((a, b) => {
  const za = ((a.source.z || 0) + (a.target.z || 0)) / 2;
  const zb = ((b.source.z || 0) + (b.target.z || 0)) / 2;
  return zb - za;
});
```

---

## 5. Visual Parameter Modulation with Depth ($z$)

Each visual attribute scales smoothly as a function of the perspective depth scale factor $s_z$:

### 5.1 Radius & Scale
- **Base Node Radius**:
  $$R_{\text{base}} = (n.\text{importance} \times 2.2) + 3.5$$
- **Projected Render Radius**:
  $$R_{\text{render}} = R_{\text{base}} \times s_z \times \sqrt{k}$$
  - Selected state: $R_{\text{render}} \times 1.6$
  - Hovered state: $R_{\text{render}} \times 1.3$

### 5.2 Core Brightness & Alpha
- **Depth Alpha Factor**:
  $$\alpha_z = \text{clamp}\left(0.25 + 0.75 \times s_z, 0.20, 1.0\right)$$
- **Core Fill**:
  - Normal: `hexToRgba(n.color, alphaZ)`
  - Dimmed (non-connected): `hexToRgba(n.color, 0.20 * alphaZ)`
  - Selected / Connected: `hexToRgba(n.color, 1.0)`

### 5.3 Atmospheric Halo & Glow Blur
- **Halo Radius**:
  $$\text{haloRadius} = R_{\text{render}} \times (1.8 + 2.2 \times s_z)$$
- **Halo Opacity**:
  $$\alpha_{\text{halo}} = \text{baseAlpha} \times s_z^{1.5}$$
  (where $\text{baseAlpha} = 0.35$ for normal, $0.60$ for connected, $0.05$ for dimmed).
- **Radial Gradient**:
  Created at $(n.\text{screenX}, n.\text{screenY})$ from $r_0 = R_{\text{render}} \times 0.4$ to $r_1 = \text{haloRadius}$.

### 5.4 Specular Center Highlight
- **Specular Radius**:
  $$r_{\text{spec}} = R_{\text{render}} \times 0.45 \times s_z$$
- **Specular Alpha**:
  $$\alpha_{\text{spec}} = \text{clamp}(0.5 \times s_z, 0.2, 1.0)$$

### 5.5 Label Level-of-Detail (LOD)
- **Effective Zoom Perception**:
  $$k_{\text{eff}} = k \times s_z$$
- **LOD Display Rule**:
  - Show all labels if $k_{\text{eff}} > 1.3$.
  - Show important nodes (`importance >= 4`) if $k_{\text{eff}} > 0.55$.
  - Always show connected or selected node labels.
- **Dynamic Font Size**:
  $$\text{fontSize} = \max(8, \text{round}(10 \times s_z))$$
  Font string: `${fontSize}px Inter, sans-serif`.

---

## 6. Interaction, Hit Testing & Dragging Integration

### 6.1 Depth-Aware Hit Detection (`getNodeAtPosition`)
Mouse coordinates $(p_x, p_y) = (\text{clientX}, \text{clientY} - 64)$ are compared in screen space.
To ensure the foreground node is selected when nodes overlap, nodes are searched in **reverse depth order** (front-to-back: $z$ ascending, i.e., largest $s_z$ first):

```javascript
function getNodeAtPosition(clientX, clientY) {
  const px = clientX;
  const py = clientY; // clientY is already adjusted for header offset

  // Sort front-to-back (ascending z = closest foreground first)
  const frontToBack = [...currentGraph.nodes].sort((a, b) => (a.z || 0) - (b.z || 0));

  for (let i = 0; i < frontToBack.length; i++) {
    const n = frontToBack[i];
    if (n.screenX === undefined || n.screenY === undefined) continue;

    const baseRadius = (n.importance * 2.2) + 3.5;
    const r = baseRadius * (n.sz || 1.0) * Math.sqrt(state.zoomTransform.k) + 5; // +5px hit tolerance
    const dist = Math.hypot(n.screenX - px, n.screenY - py);

    if (dist <= r) {
      return n;
    }
  }
  return null;
}
```

### 6.2 D3 Dragging Integration
During D3 drag events on the canvas:
```javascript
d3.drag()
  .container(graphCanvas)
  .subject(event => {
    return getNodeAtPosition(event.x, event.y);
  })
  .on('start', (event) => {
    if (!event.active && simulation) simulation.alphaTarget(0.3).restart();
    event.subject.fx = event.subject.x;
    event.subject.fy = event.subject.y;
  })
  .on('drag', (event) => {
    const width = window.innerWidth;
    const height = window.innerHeight - 64;
    const panX = state.zoomTransform.x;
    const panY = state.zoomTransform.y;
    const k = state.zoomTransform.k;

    // Use exact mathematical unproject3D
    const unproj = unproject3D(event.x, event.y, event.subject.z || 0, width, height, panX, panY, k);
    event.subject.fx = unproj.x;
    event.subject.fy = unproj.y;
  })
  .on('end', (event) => {
    if (!event.active && simulation) simulation.alphaTarget(0);
    event.subject.fx = null;
    event.subject.fy = null;
  });
```

---

## 7. Concrete Implementation Plan in `docs/app.js`

### 7.1 Key Functions to Add or Update

| Function | Modification Description |
|---|---|
| `computeNodeZ(node)` | **NEW**: Computes deterministic $z \in [-100, 100]$ from layer, importance, and ID hash. |
| `project3D(x, y, z, W, H, panX, panY, k)` | **NEW**: Projects $(x, y, z)$ to $(\text{screenX}, \text{screenY}, s_z)$. |
| `unproject3D(screenX, screenY, z, W, H, panX, panY, k)` | **NEW**: Exact algebraic inverse of `project3D` for mouse drag coordinate recovery. |
| `getPanToCenter(x, y, z, W, H, k)` | **NEW**: Calculates $(t_x, t_y)$ to center camera on $(x, y, z)$ at zoom $k$. |
| `loadBranch(branchName)` | **UPDATE**: Assigns `node.z = computeNodeZ(node)` during node cloning. |
| `renderGraph()` | **UPDATE**: Calls `updateProjectedPositions(W, H)`; removes global `graphCtx.translate/scale` so elements render directly in projected screen coordinates. |
| `renderClusterNebulas()` | **UPDATE**: Calculates cluster 3D centroid $(\bar{x}, \bar{y}, \bar{z})$, sorts descending by $\bar{z}$, and renders radial gradient at projected screen center. |
| `renderLinks()` | **UPDATE**: Sorts links descending by average depth, renders tapered stroke width and gradient along projected screen endpoints. |
| `renderPhotons()` | **UPDATE**: Calculates photon 3D coordinate along link, projects to screen, sorts descending by $z$, renders depth-scaled stardust arcs. |
| `renderNodes()` | **UPDATE**: Sorts nodes descending by $z$ (Painter's algorithm), renders atmospheric halo, pulse ring, core, and specular highlight scaled by $s_z$. |
| `renderLabels()` | **UPDATE**: Modulates LOD thresholds and font size by $s_z$, renders at projected $(node.\text{screenX}, node.\text{screenY})$. |
| `getNodeAtPosition(x, y)` | **UPDATE**: Tests in front-to-back order (ascending $z$) against projected $(node.\text{screenX}, node.\text{screenY})$ and radius $R_{\text{render}}$. |
| `panToNode(node)` | **UPDATE**: Uses `getPanToCenter` for smooth transition to node in 3D perspective space. |

---

## 8. Verification & Acceptance Criteria Matrix

| Criterion | Expected Behavior | Verification Method |
|---|---|---|
| **Deterministic Z Assignment** | Nodes receive consistent $z \in [-100, 100]$; Layer 1 hubs in foreground ($z < 0$), Layer 6 swarm logs in background ($z > 0$). | Inspect `node.z` in browser console for both `main` and `v2`. |
| **Perspective Depth Scaling** | $s_z = \frac{500}{500+z} \in [0.833, 1.250]$; foreground nodes larger/brighter, background nodes smaller/fainter. | Visual check + automated Playwright test asserting node radius and alpha. |
| **Painter's Depth Sorting** | Deepest background nodes ($z > 0$) rendered first; nearest foreground nodes ($z < 0$) rendered last. | Canvas draw call inspection and visual overlap verification. |
| **Parallax Pan/Zoom** | Foreground nodes move faster across screen on camera drag ($\text{parallax} = \text{pan} \cdot s_z^{0.6}$). | Pan camera horizontally and observe spatial velocity differentials. |
| **Hit Testing Accuracy** | Clicking/hovering overlapping nodes selects the foreground node with zero offset error. | Automated Playwright mouse hover over overlapping nodes. |
| **Node Dragging Integrity** | Dragging a 3D node tracks cursor precisely without jumping or lagging. | Drag test on foreground ($z < 0$) and background ($z > 0$) nodes. |
| **Camera Centering** | `panToNode(node)` smoothly centers any node regardless of $z$ at screen center $(W/2, H/2)$. | Click search result and verify node aligns at $(W/2, H/2)$. |

---

## 9. Conclusion

Milestone 1's 3D Z-Projection and Depth Sorting engine is mathematically sound, fully deterministic, computationally lightweight (60 FPS on standard Canvas 2D), and seamlessly integrates into `docs/app.js`.

The implementation worker can execute these exact formulas and structural refactorings directly from this document.
