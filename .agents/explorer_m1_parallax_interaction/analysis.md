# Technical Investigation: Parallax Pan/Zoom, Depth-Aware Hit Testing & 3D Camera Transitions (Milestone 1)

**Target Repository**: `s6pa1rta3n-lab/roof4u`  
**File**: `docs/app.js`  
**Author**: Explorer Agent (`teamwork_preview_explorer`)  
**Working Directory**: `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_m1_parallax_interaction`  
**Date**: 2026-09-01  

---

## 1. Executive Summary

This report delivers the comprehensive technical architecture and exact mathematical implementation for **Feature F05 (Parallax Pan & Zoom Displacement)**, **Feature F07 (Depth-Aware Interactive Hit Testing)**, and **3D Camera Transitions** (Node & Cluster Focus) in `docs/app.js` for Milestone 1 of the Roo4u Constellation Overhaul.

The current implementation in `docs/app.js` operates strictly as a 2D canvas visualizer. It applies a uniform 2D affine transform matrix (`ctx.translate(tx, ty); ctx.scale(k, k);`), performs hit detection against un-projected world coordinates without depth awareness or occlusion sorting, and centers nodes using standard 2D offsets.

This investigation establishes:
1. **The Parallax Projection Formulation**: Closed-form perspective projection with depth-modulated pan translation $(dx, dy)$ and scale factor $(s_z)^p$ ($p = 0.6$), centering perspective expansion around the viewport vanishing point $(W/2, H/2)$.
2. **Depth-Aware Screen-Space Hit Testing (`findNodeAt`)**: High-performance $O(N)$ hit testing in projected screen coordinates with dynamic depth radii, combined with depth-priority sorting (foreground first) to prevent occlusion inversion.
3. **Exact Analytical Inverse Projection (`unproject3D`)**: Enables 1:1 mouse tracking during node dragging without drift, regardless of node depth $z$ or camera zoom $k$.
4. **Depth-Compensated Camera Transitions (`panToNode`, `focusCluster`, `centerCamera`)**: Analytical camera target solving that brings any node or cluster centroid $(x, y, z)$ precisely to screen center $(W/2, H/2)$ with smooth D3 ease-cubic interpolation.

---

## 2. Mathematical Formulations & Coordinate Transformations

### 2.1. Coordinate Systems
- **World Space $(x, y, z)$**: Continuous coordinates from D3 force simulation layout where $x, y \in \mathbb{R}$ and $z \in [-100, 100]$. Focal plane is at $z = 0$.
- **Camera State $(t_x, t_y, k)$**: D3 zoom transform where $t_x = \text{transform.x}$, $t_y = \text{transform.y}$, and $k = \text{transform.k} \in [0.15, 4.0]$.
- **Viewport Frame $(W, H)$**: Canvas pixel dimensions where vanishing point $(c_x, c_y) = (W/2, H/2)$.
- **Screen Space $(x'_{screen}, y'_{screen})$**: Canvas rendering pixel coordinates where $(0, 0)$ is top-left.

---

### 2.2. Perspective Depth Scale Factor ($s_z$)
With camera focal distance $D = 500$:
$$s_z = \frac{D}{D + z}$$

- **Foreground ($z = -100$)**: $s_z = \frac{500}{400} = 1.25$ ($+25\%$ size and parallax displacement).
- **Focal Plane ($z = 0$)**: $s_z = \frac{500}{500} = 1.00$ (Standard 1:1 scale).
- **Deep Void ($z = +100$)**: $s_z = \frac{500}{600} = 0.833$ ($-16.7\%$ size and reduced drift).

---

### 2.3. Parallax Pan & Zoom Projection (`project3D`)

To achieve realistic depth separation during camera pan, the camera translation $(t_x, t_y)$ is modulated by the non-linear depth power factor $(s_z)^p$ where $p = 0.6$:
$$\text{parallaxX} = t_x \cdot (s_z)^{0.6}$$
$$\text{parallaxY} = t_y \cdot (s_z)^{0.6}$$

Projecting a world point $(x, y, z)$ to screen space $(screenX, screenY)$ relative to the viewport vanishing point $(W/2, H/2)$:
$$screenX = (x \cdot k + \text{parallaxX}) \cdot s_z + \frac{W}{2} (1 - s_z)$$
$$screenY = (y \cdot k + \text{parallaxY}) \cdot s_z + \frac{H}{2} (1 - s_z)$$

#### Algebraic Equivalence & Vanishing Point Invariance:
Expanding the terms:
$$screenX = \frac{W}{2} + s_z \cdot \left( x \cdot k + t_x \cdot s_z^{0.6} - \frac{W}{2} \right)$$
$$screenY = \frac{H}{2} + s_z \cdot \left( y \cdot k + t_y \cdot s_z^{0.6} - \frac{H}{2} \right)$$

- When $z = 0 \implies s_z = 1.0$:
  $$screenX = x \cdot k + t_x, \quad screenY = y \cdot k + t_y$$
  Matches the standard 2D D3 transform identically.
- When $z < 0$ (foreground): $s_z > 1.0$, objects expand outward from $(W/2, H/2)$ and translate faster on pan.
- When $z > 0$ (background): $s_z < 1.0$, objects contract towards $(W/2, H/2)$ and translate slower on pan.

```javascript
/**
 * Project a 3D world coordinate into 2D canvas screen space.
 * @param {number} x - World X
 * @param {number} y - World Y
 * @param {number} z - World Z [-100, 100]
 * @param {number} width - Viewport width
 * @param {number} height - Viewport height
 * @param {number} panX - D3 zoom transform X
 * @param {number} panY - D3 zoom transform Y
 * @param {number} zoomScale - D3 zoom transform K
 * @param {number} D - Focal distance (default 500)
 * @returns {{ screenX: number, screenY: number, sz: number }}
 */
function project3D(x, y, z, width, height, panX, panY, zoomScale, D = 500) {
  const sz = D / (D + (z || 0));
  const pFactor = Math.pow(sz, 0.6);
  const parallaxX = panX * pFactor;
  const parallaxY = panY * pFactor;
  const screenX = (x * zoomScale + parallaxX) * sz + (width / 2) * (1 - sz);
  const screenY = (y * zoomScale + parallaxY) * sz + (height / 2) * (1 - sz);
  return { screenX, screenY, sz };
}
```

---

### 2.4. Analytical Inverse 3D Projection (`unproject3D`)

During interactive node dragging, the user moves their cursor to screen pixel position $(m_x, m_y)$. To prevent visual "slipping" or coordinate snapping, we must compute the exact world coordinates $(fx, fy)$ at the node's specific depth $z$ such that $\text{project3D}(fx, fy, z) \equiv (m_x, m_y)$.

Starting from the projection formula:
$$m_x = (fx \cdot k + t_x \cdot s_z^{0.6}) \cdot s_z + \frac{W}{2}(1 - s_z)$$

1. Subtract vanishing point offset:
   $$m_x - \frac{W}{2}(1 - s_z) = (fx \cdot k + t_x \cdot s_z^{0.6}) \cdot s_z$$
2. Divide by $s_z$:
   $$\frac{m_x - \frac{W}{2}(1 - s_z)}{s_z} = fx \cdot k + t_x \cdot s_z^{0.6}$$
3. Subtract parallax pan translation:
   $$\frac{m_x - \frac{W}{2}(1 - s_z)}{s_z} - t_x \cdot s_z^{0.6} = fx \cdot k$$
4. Divide by zoom scale $k$:
   $$fx = \frac{\frac{m_x - \frac{W}{2}(1 - s_z)}{s_z} - t_x \cdot s_z^{0.6}}{k}$$
   $$fy = \frac{\frac{m_y - \frac{H}{2}(1 - s_z)}{s_z} - t_y \cdot s_z^{0.6}}{k}$$

```javascript
/**
 * Unproject 2D canvas screen coordinates back to 3D world space at depth z.
 * @param {number} screenX - Cursor screen X
 * @param {number} screenY - Cursor screen Y
 * @param {number} z - Node depth Z
 * @param {number} width - Viewport width
 * @param {number} height - Viewport height
 * @param {number} panX - D3 zoom transform X
 * @param {number} panY - D3 zoom transform Y
 * @param {number} zoomScale - D3 zoom transform K
 * @param {number} D - Focal distance (default 500)
 * @returns {{ worldX: number, worldY: number }}
 */
function unproject3D(screenX, screenY, z, width, height, panX, panY, zoomScale, D = 500) {
  const sz = D / (D + (z || 0));
  const pFactor = Math.pow(sz, 0.6);
  const parallaxX = panX * pFactor;
  const parallaxY = panY * pFactor;
  const worldX = ((screenX - (width / 2) * (1 - sz)) / sz - parallaxX) / zoomScale;
  const worldY = ((screenY - (height / 2) * (1 - sz)) / sz - parallaxY) / zoomScale;
  return { worldX, worldY };
}
```

---

## 3. Depth-Aware Interactive Hit Testing (`findNodeAt`)

### 3.1. Identified Deficiencies in Current 2D Code
In current `docs/app.js` (lines 886–896):
```javascript
// EXISTING (FLAWED FOR 3D):
function getNodeAtPosition(clientX, clientY) {
  const p = getTransformedPoint(clientX, clientY); // p.x = (clientX - tx)/k, p.y = (clientY - ty)/k
  for (let i = currentGraph.nodes.length - 1; i >= 0; i--) {
    const n = currentGraph.nodes[i];
    if (!n.x || !n.y) continue;
    const r = (n.importance * 2.2) + 5;
    const d = Math.hypot(n.x - p.x, n.y - p.y);
    if (d <= r) return n;
  }
  return null;
}
```
1. **Spatial Displacement Error**: Ignores depth scaling $s_z$ and $(s_z)^{0.6}$ parallax shift. The un-projected world point $(p.x, p.y)$ deviates significantly from where the 3D node is actually rendered on screen.
2. **Radius Inconsistency**: Tests against un-projected radius $r$, failing to account for perspective scale $s_z \cdot k$. Foreground nodes become hard to hit; background nodes have oversized invisible hitboxes.
3. **Occlusion Reversal**: Iterates raw array order rather than depth order. If a distant node happens to be later in `currentGraph.nodes`, it will steal clicks/hovers from a foreground node directly in front of it.

---

### 3.2. Technical Implementation for Depth-Aware Hit Testing

The new `findNodeAt(screenX, screenY, maxDistance)` function performs hit testing directly in **Screen Space** with depth-priority traversal:

```javascript
/**
 * Find the top-most visible node under the screen cursor coordinates.
 * @param {number} screenX - Cursor X relative to canvas
 * @param {number} screenY - Cursor Y relative to canvas
 * @param {number|null} [maxDistance=null] - Optional maximum proximity threshold
 * @returns {object|null} - The hit node, or null
 */
function findNodeAt(screenX, screenY, maxDistance = null) {
  const width = graphCanvas.clientWidth || window.innerWidth;
  const height = graphCanvas.clientHeight || (window.innerHeight - 64);
  const k = state.zoomTransform.k;
  const tx = state.zoomTransform.x;
  const ty = state.zoomTransform.y;

  // Filter valid nodes and compute projected screen parameters
  const candidates = [];
  for (let i = 0; i < currentGraph.nodes.length; i++) {
    const n = currentGraph.nodes[i];
    if (n.x === undefined || n.y === undefined) continue;

    const z = n.z !== undefined ? n.z : 0;
    const { screenX: sx, screenY: sy, sz } = project3D(n.x, n.y, z, width, height, tx, ty, k);

    // Dynamic screen hit radius: base radius scaled by depth and zoom
    const isSelected = state.selectedNode && state.selectedNode.id === n.id;
    const isHovered = state.hoveredNode && state.hoveredNode.id === n.id;
    const baseRadius = (n.importance * 2.2) + 3.5;
    const radiusMultiplier = isSelected ? 1.6 : (isHovered ? 1.3 : 1.0);
    
    // Scale to screen pixels, ensure minimum clickable target (8px) for accessibility
    const screenRadius = Math.max(8, baseRadius * radiusMultiplier * sz * k + 6);
    const dist = Math.hypot(sx - screenX, sy - screenY);

    candidates.push({
      node: n,
      dist: dist,
      screenRadius: screenRadius,
      z: z,
      sz: sz
    });
  }

  // Depth-Priority Sorting: Foreground first (smallest z, largest sz)
  candidates.sort((a, b) => a.z - b.z);

  // 1. Direct Hit Check (Inside node radius + margin)
  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i];
    if (c.dist <= c.screenRadius) {
      return c.node;
    }
  }

  // 2. Fuzzy Proximity Fallback (if maxDistance specified)
  if (maxDistance !== null && maxDistance > 0) {
    let closestNode = null;
    let minDist = maxDistance;
    for (let i = 0; i < candidates.length; i++) {
      const c = candidates[i];
      if (c.dist < minDist) {
        minDist = c.dist;
        closestNode = c.node;
      }
    }
    return closestNode;
  }

  return null;
}
```

---

### 3.3. Event Handler Integrations

#### 1. Canvas Hover & Tooltip (`mousemove`)
```javascript
graphCanvas.addEventListener('mousemove', (e) => {
  const rect = graphCanvas.getBoundingClientRect();
  const screenX = e.clientX - rect.left;
  const screenY = e.clientY - rect.top;

  const node = findNodeAt(screenX, screenY);
  if (node !== state.hoveredNode) {
    state.hoveredNode = node;
    if (node) {
      showTooltip(node, e.clientX, e.clientY);
    } else {
      hideTooltip();
    }
  } else if (node) {
    moveTooltip(e.clientX, e.clientY);
  }
});
```

#### 2. Canvas Click & Selection (`click`)
```javascript
graphCanvas.addEventListener('click', (e) => {
  const rect = graphCanvas.getBoundingClientRect();
  const screenX = e.clientX - rect.left;
  const screenY = e.clientY - rect.top;

  const node = findNodeAt(screenX, screenY);
  if (node) {
    selectNode(node);
  } else if (!state.isolatedNodeId) {
    state.selectedNode = null;
    hideInspector();
  }
});
```

#### 3. D3 Node Dragging (`d3.drag()`)
```javascript
d3.select(graphCanvas).call(
  d3.drag()
    .container(graphCanvas)
    .subject(event => {
      // event.x, event.y are container-relative canvas screen coordinates
      return findNodeAt(event.x, event.y, 25);
    })
    .on('start', (event) => {
      if (!event.subject) return;
      if (!event.active && simulation) simulation.alphaTarget(0.3).restart();
      event.subject.fx = event.subject.x;
      event.subject.fy = event.subject.y;
    })
    .on('drag', (event) => {
      if (!event.subject) return;
      const width = graphCanvas.clientWidth || window.innerWidth;
      const height = graphCanvas.clientHeight || (window.innerHeight - 64);
      
      const { worldX, worldY } = unproject3D(
        event.x,
        event.y,
        event.subject.z || 0,
        width,
        height,
        state.zoomTransform.x,
        state.zoomTransform.y,
        state.zoomTransform.k
      );
      event.subject.fx = worldX;
      event.subject.fy = worldY;
    })
    .on('end', (event) => {
      if (!event.subject) return;
      if (!event.active && simulation) simulation.alphaTarget(0);
      event.subject.fx = null;
      event.subject.fy = null;
    })
);
```

---

## 4. 3D Camera Transitions & Focus Centering

### 4.1. Single Node Centering (`panToNode`)

When focusing on a node $(x_0, y_0, z_0)$ at zoom scale $k$, we want its projected screen coordinate to land precisely at the viewport center $(W/2, H/2)$:
$$screenX(x_0, y_0, z_0, t_x, t_y, k) = \frac{W}{2}$$
$$screenY(x_0, y_0, z_0, t_x, t_y, k) = \frac{H}{2}$$

Substituting the projection formula:
$$\left(x_0 \cdot k + t_x \cdot s_z^{0.6}\right) \cdot s_z + \frac{W}{2}(1 - s_z) = \frac{W}{2}$$
$$\left(x_0 \cdot k + t_x \cdot s_z^{0.6}\right) \cdot s_z = \frac{W}{2} s_z$$
$$x_0 \cdot k + t_x \cdot s_z^{0.6} = \frac{W}{2}$$
$$t_x = \frac{\frac{W}{2} - x_0 \cdot k}{(s_z)^{0.6}}$$
$$t_y = \frac{\frac{H}{2} - y_0 \cdot k}{(s_z)^{0.6}}$$

```javascript
/**
 * Smoothly pan and zoom camera to center on a target 3D node.
 * @param {object} node - Target graph node with { x, y, z }
 * @param {number} [targetZoom=1.6] - Target zoom scale
 * @param {number} [duration=750] - Transition duration in ms
 */
function panToNode(node, targetZoom = 1.6, duration = 750) {
  if (!node || node.x === undefined || node.y === undefined) return;
  const width = graphCanvas.clientWidth || window.innerWidth;
  const height = graphCanvas.clientHeight || (window.innerHeight - 64);
  const k = targetZoom;
  const z = node.z !== undefined ? node.z : 0;
  const sz = 500 / (500 + z);
  const pFactor = Math.pow(sz, 0.6);

  const tx = (width / 2 - node.x * k) / pFactor;
  const ty = (height / 2 - node.y * k) / pFactor;

  const targetTransform = d3.zoomIdentity.translate(tx, ty).scale(k);

  d3.select(graphCanvas)
    .transition()
    .duration(duration)
    .ease(d3.easeCubicOut)
    .call(zoomBehavior.transform, targetTransform);
}
```

---

### 4.2. Cluster & Constellation Framing (`focusCluster`)

When isolating a cluster or focusing connected constellations:
1. Compute the 3D bounding box and 3D centroid $(\bar{x}, \bar{y}, \bar{z})$ of the member nodes.
2. Determine the optimal zoom scale $k_{\text{fit}}$ to fit within $75\%$ of the viewport dimensions.
3. Compute the target pan translation $(t_x, t_y)$ for centroid $(\bar{x}, \bar{y}, \bar{z})$.

```javascript
/**
 * Frame a collection of nodes (cluster or constellation) within the viewport.
 * @param {Array<object>} nodes - Array of graph nodes
 * @param {number} [duration=800] - Transition duration in ms
 */
function focusCluster(nodes, duration = 800) {
  if (!nodes || nodes.length === 0) return;
  const width = graphCanvas.clientWidth || window.innerWidth;
  const height = graphCanvas.clientHeight || (window.innerHeight - 64);

  let minX = Infinity, maxX = -Infinity;
  let minY = Infinity, maxY = -Infinity;
  let sumX = 0, sumY = 0, sumZ = 0;
  let count = 0;

  nodes.forEach(n => {
    if (n.x === undefined || n.y === undefined) return;
    if (n.x < minX) minX = n.x;
    if (n.x > maxX) maxX = n.x;
    if (n.y < minY) minY = n.y;
    if (n.y > maxY) maxY = n.y;
    sumX += n.x;
    sumY += n.y;
    sumZ += (n.z !== undefined ? n.z : 0);
    count++;
  });

  if (count === 0) return;

  const avgX = sumX / count;
  const avgY = sumY / count;
  const avgZ = sumZ / count;

  const spanX = Math.max(maxX - minX + 80, 150);
  const spanY = Math.max(maxY - minY + 80, 150);

  // Compute zoom scale to fit cluster with 25% padding margin
  const fitK = Math.min(
    (width * 0.75) / spanX,
    (height * 0.75) / spanY
  );
  const k = Math.max(0.3, Math.min(2.2, fitK));

  const sz = 500 / (500 + avgZ);
  const pFactor = Math.pow(sz, 0.6);
  const tx = (width / 2 - avgX * k) / pFactor;
  const ty = (height / 2 - avgY * k) / pFactor;

  const targetTransform = d3.zoomIdentity.translate(tx, ty).scale(k);

  d3.select(graphCanvas)
    .transition()
    .duration(duration)
    .ease(d3.easeCubicOut)
    .call(zoomBehavior.transform, targetTransform);
}
```

---

### 4.3. Full Graph Auto-Framing (`centerCamera`)

```javascript
/**
 * Center camera on the entire graph's center of mass.
 */
function centerCamera() {
  const visibleNodes = currentGraph.nodes.filter(n => n.x !== undefined && n.y !== undefined);
  if (visibleNodes.length === 0) {
    const t = d3.zoomIdentity.translate(0, 0).scale(1.0);
    d3.select(graphCanvas).transition().duration(600).ease(d3.easeCubicOut).call(zoomBehavior.transform, t);
    return;
  }
  focusCluster(visibleNodes, 650);
}
```

---

## 5. Performance Optimizations & Per-Frame Cache Architecture

To maintain 60 FPS across high-density graphs (431+ nodes, 334+ links, 500+ particles) on retina displays:

1. **Per-Frame Projection Cache**:
   In `renderGraph()`, compute `project3D` for each node once at the beginning of the frame and store the projected properties directly on the node instance (`n._projX, n._projY, n._projR, n._sz`).
2. **Re-use Cached Projections in Multi-Pass Rendering**:
   - `renderClusterNebulas()`: Uses cached cluster centroid projections.
   - `renderLinks()`: Directly accesses endpoints `l.source._projX, l.source._projY` and `l.target._projX, l.target._projY` without re-computing trigonometric or exponential functions.
   - `renderPhotons()`: Computes linear interpolation between cached endpoint coordinates.
   - `renderNodes()` and `renderLabels()`: Consume cached screen coordinates directly.
3. **Painter's Algorithm Depth-Sort**:
   Sort active node array once per frame:
   `const depthSortedNodes = [...currentGraph.nodes].sort((a, b) => (b.z || 0) - (a.z || 0));`
   Renders background ($z = +100$) first and foreground ($z = -100$) last.

---

## 6. Implementation Checklist for Worker Agent

| Item | Component | Exact Function in `docs/app.js` | Action |
|---|---|---|---|
| 1 | 3D Projection Math | `project3D(x, y, z, w, h, panX, panY, k, D)` | Add helper function with $(s_z)^{0.6}$ parallax modulation |
| 2 | Inverse Projection Math | `unproject3D(sx, sy, z, w, h, panX, panY, k, D)` | Add helper function for exact inverse mapping |
| 3 | Depth Hit-Testing | `findNodeAt(screenX, screenY, maxDistance)` | Replace `getNodeAtPosition` and `findClosestNode` |
| 4 | Event Listeners | `setupEventListeners()` | Update `mousemove`, `click`, and `d3.drag` subject/drag handlers |
| 5 | Node Centering | `panToNode(node, targetZoom, duration)` | Update with 3D analytical centering formula |
| 6 | Cluster Centering | `focusCluster(nodes, duration)` | Add cluster framing helper |
| 7 | Global Centering | `centerCamera()` | Update to frame entire graph centroid in 3D |
| 8 | Frame Projection Cache | `renderGraph()` | Compute projected coordinates once per frame before render passes |
