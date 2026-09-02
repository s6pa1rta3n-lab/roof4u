# Handoff Report: Parallax Pan/Zoom, Depth-Aware Hit Testing & 3D Camera Transitions

**Author**: Explorer Agent (`teamwork_preview_explorer`)  
**Target Milestone**: Milestone 1 (3D Depth Rendering Engine)  
**Assigned Sub-Scope**: Parallax Pan/Zoom, Depth-Aware Hit Testing, 3D Camera Centering  
**Date**: 2026-09-01  
**Working Directory**: `/Users/solveetcoagula/Desktop/activeProjects/Roo4u/.agents/explorer_m1_parallax_interaction`  

---

## 1. Observation

1. **2D Uniform Canvas Matrix**: In `docs/app.js` (lines 347–352), the current rendering loop applies a global 2D transform `graphCtx.translate(state.zoomTransform.x, state.zoomTransform.y); graphCtx.scale(state.zoomTransform.k, state.zoomTransform.k);`. All elements are drawn in world coordinates without depth-dependent parallax shift or scale factor.
2. **Un-Projected 2D Hit Testing**: In `docs/app.js` (lines 886–896), `getNodeAtPosition(clientX, clientY)` computes $p.x = (clientX - tx)/k, p.y = (clientY - ty)/k$ and tests against an un-projected radius $r = (\text{importance} \cdot 2.2) + 5$.
   ```javascript
   function getNodeAtPosition(clientX, clientY) {
     const p = getTransformedPoint(clientX, clientY);
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
3. **Hardcoded Viewport Header Offset**: In `docs/app.js` (lines 678, 693), mouse event listeners call `getNodeAtPosition(e.clientX, e.clientY - 64)`, hardcoding the 64px header height instead of dynamically reading `canvas.getBoundingClientRect()`.
4. **D3 Drag World Coordinate Slipping**: In `docs/app.js` (lines 700–721), node dragging calls `findClosestNode(p.x, p.y)` and updates $fx, fy$ using the 2D `getTransformedPoint(event.x, event.y)`. Under 3D projection, dragging a foreground ($z < 0$) or background ($z > 0$) node using 2D inverse causes immediate visual disconnect (drift/slippage) between the cursor and the rendered node orb.
5. **2D Camera Centering**: In `docs/app.js` (lines 1122–1132), `panToNode(node)` translates the camera by $(W/2 - node.x \cdot k, H/2 - node.y \cdot k)$, which fails to place a 3D node at the screen center due to uncompensated $(s_z)^p$ parallax and perspective vanishing point offsets.
6. **Interface Specification Alignment**: In `PROJECT.md` (lines 84–91), the 3D perspective projection formula specifies $s_z = \frac{D}{D+z}$ ($D=500$) with pan translation modulation $\text{parallaxX} = panX \cdot (s_z)^{0.6}$ and vanishing point $(W/2, H/2)$.

---

## 2. Logic Chain

1. **Parallax Motion**: Because nodes reside at depths $z \in [-100, 100]$, modulating the camera pan translation $(panX, panY)$ by $(s_z)^{0.6}$ (where $s_z = \frac{500}{500+z}$) ensures foreground nodes shift by $1.1435\times$ during camera pan while background nodes shift by $0.896\times$, creating an immersive depth illusion (Observation 6).
2. **Screen-Space Hit Detection**: Because the rendered screen position $(sx, sy)$ and rendered radius $R_{screen} = \text{baseRadius} \cdot s_z \cdot k$ depend on $z$ and $s_z$, hit testing must compare the cursor screen position directly against the projected screen positions $(sx, sy)$ and dynamic screen radii (Observation 2).
3. **Occlusion Priority**: Sorting hit-test candidates by ascending depth ($z$ ascending, $s_z$ descending) guarantees that foreground nodes take precedence over background nodes when click/hover occurs in overlapping regions (Observation 2).
4. **Exact Drag Inversion**: Inverting the projection formula analytically yields $worldX = \frac{\frac{screenX - (W/2)(1 - s_z)}{s_z} - panX \cdot s_z^{0.6}}{k}$. Setting $(fx, fy)$ via this formula guarantees 1:1 cursor tracking during dragging without drift across all depths and zoom levels (Observations 4, 6).
5. **Precise Camera Centering**: Solving $screenX(x_0, y_0, z_0, tx, ty, k) = W/2$ and $screenY(x_0, y_0, z_0, tx, ty, k) = H/2$ yields $tx = \frac{W/2 - x_0 \cdot k}{(s_z)^{0.6}}$ and $ty = \frac{H/2 - y_0 \cdot k}{(s_z)^{0.6}}$, which lands the target node or cluster centroid precisely at the viewport center $(W/2, H/2)$ (Observation 5).

---

## 3. Caveats

1. **D3 Force Layout Remains in 2D**: The D3 physics simulation continues to solve $(x, y)$ positions in 2D world space; depth $z$ is assigned deterministically as a static or layout-dependent property.
2. **Singularity Prevention**: $D = 500$ ensures $D + z > 0$ for all $z \in [-100, 100]$. If custom depth configurations exceed $-500$, $D + z$ must be clamped to prevent division by zero.
3. **Multi-Touch Gestures**: Touch events will follow the standard D3 zoom behavior; pinch-to-zoom is supported through D3 zoom's built-in touch handling.

---

## 4. Conclusion

The technical architecture for Parallax Pan/Zoom, Depth-Aware Hit Testing, and 3D Camera Transitions is fully solved with closed-form mathematical equations and exact JavaScript implementations ready for integration in `docs/app.js`.

Key deliverables established in `analysis.md`:
- `project3D(x, y, z, width, height, panX, panY, zoomScale, D)`
- `unproject3D(screenX, screenY, z, width, height, panX, panY, zoomScale, D)`
- `findNodeAt(screenX, screenY, maxDistance)` with depth-priority sorting
- Updated `d3.drag()` handler with depth-aware inversion
- Updated `panToNode()`, `focusCluster()`, and `centerCamera()` with 3D analytical centering formulas

---

## 5. Verification Method

1. **Unit / Mathematical Verification**:
   Verify that for any node $(x, y, z)$, camera transform $(tx, ty, k)$, and viewport $(W, H)$:
   - `const proj = project3D(x, y, z, W, H, tx, ty, k);`
   - `const unproj = unproject3D(proj.screenX, proj.screenY, z, W, H, tx, ty, k);`
   - Assert $\lvert unproj.worldX - x \rvert < 10^{-6}$ and $\lvert unproj.worldY - y \rvert < 10^{-6}$.
2. **Centering Verification**:
   - For a node $(x, y, z)$, calculate $tx = \frac{W/2 - x \cdot k}{(s_z)^{0.6}}$ and $ty = \frac{H/2 - y \cdot k}{(s_z)^{0.6}}$.
   - Assert `project3D(x, y, z, W, H, tx, ty, k).screenX === W / 2` and `screenY === H / 2`.
3. **End-to-End Test Suite Verification**:
   - Run automated Playwright tests: `python3 tests/e2e/test_runner.py`.
   - Invalidation condition: Cursor clicking a foreground node over a background node activates the background node, or node dragging drifts from the mouse cursor.
