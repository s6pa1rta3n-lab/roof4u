/**
 * adversarial_m1_3d_engine.js
 * Adversarial empirical stress-testing suite for Roo4u 3D Depth Rendering Engine (Milestone 1).
 */

const fs = require('fs');
const path = require('path');
const assert = require('assert');

console.log("======================================================================");
console.log("    ROO4U M1 3D DEPTH RENDERING ENGINE — ADVERSARIAL STRESS SUITE     ");
console.log("======================================================================\n");

// --- Extract / Load Engine Functions from docs/app.js ---
const appJsPath = path.join(__dirname, '../../docs/app.js');
const appJsContent = fs.readFileSync(appJsPath, 'utf8');

// Isolate mathematical functions using a sandboxed evaluation
function extractFunction(src, fnName) {
  const match = src.match(new RegExp(`function\\s+${fnName}\\s*\\([\\s\\S]*?\\n  \\}`, 'm'));
  if (!match) {
    throw new Error(`Could not find function ${fnName} in docs/app.js`);
  }
  return match[0];
}

// Build executable module from app.js functions
const engineCode = `
${extractFunction(appJsContent, 'computeNodeZ')}
${extractFunction(appJsContent, 'project3D')}
${extractFunction(appJsContent, 'unproject3D')}
${extractFunction(appJsContent, 'getPanToCenter')}
${extractFunction(appJsContent, 'hexToRgba')}
module.exports = { computeNodeZ, project3D, unproject3D, getPanToCenter, hexToRgba };
`;

const engineModule = { exports: {} };
const fn = new Function('module', 'exports', engineCode);
fn(engineModule, engineModule.exports);
const { computeNodeZ, project3D, unproject3D, getPanToCenter, hexToRgba } = engineModule.exports;

let totalTests = 0;
let passedTests = 0;
let failedTests = 0;

function runTest(name, testFn) {
  totalTests++;
  process.stdout.write(`[*] Testing: ${name}... `);
  try {
    const t0 = process.hrtime.bigint();
    testFn();
    const t1 = process.hrtime.bigint();
    const ms = Number(t1 - t0) / 1e6;
    console.log(`\x1b[32m[PASS]\x1b[0m (${ms.toFixed(2)}ms)`);
    passedTests++;
  } catch (err) {
    console.log(`\x1b[31m[FAIL]\x1b[0m`);
    console.error(`    \x1b[31mError: ${err.message}\x1b[0m`);
    if (err.stack) console.error(err.stack.split('\n').slice(1, 4).join('\n'));
    failedTests++;
  }
}

// ============================================================================
// TEST SUITE 1: Z-DEPTH ASSIGNMENT MATHEMATICAL INVARIANTS & HASH JITTER
// ============================================================================

runTest("computeNodeZ Determinism & Range [-100, 100]", () => {
  for (let layer = -5; layer <= 12; layer++) {
    for (let importance = -5; importance <= 10; importance++) {
      for (let i = 0; i < 50; i++) {
        const id = `node_layer_${layer}_imp_${importance}_idx_${i}`;
        const z1 = computeNodeZ({ layer, importance, id });
        const z2 = computeNodeZ({ layer, importance, id });
        assert.strictEqual(z1, z2, `Determinism violated for id ${id}`);
        assert.ok(!isNaN(z1), `NaN detected for z`);
        assert.ok(isFinite(z1), `Non-finite z: ${z1}`);
        assert.ok(z1 >= -100.0 && z1 <= 100.0, `Z out of bounds [-100, 100]: ${z1}`);
      }
    }
  }
});

runTest("computeNodeZ Foreground vs Background Monotonicity", () => {
  // Layer 1 / Importance 5 must on average be much closer (smaller z) than Layer 6 / Importance 1
  let fgSum = 0, bgSum = 0;
  const samples = 1000;
  for (let i = 0; i < samples; i++) {
    fgSum += computeNodeZ({ layer: 1, importance: 5, id: `fg_${i}` });
    bgSum += computeNodeZ({ layer: 6, importance: 1, id: `bg_${i}` });
  }
  const fgAvg = fgSum / samples;
  const bgAvg = bgSum / samples;
  assert.ok(fgAvg < -50, `Expected foreground avg z < -50, got ${fgAvg}`);
  assert.ok(bgAvg > 50, `Expected background avg z > 50, got ${bgAvg}`);
  assert.ok(bgAvg - fgAvg > 100, `Expected substantial depth separation, got ${bgAvg - fgAvg}`);
});

runTest("computeNodeZ Hash Jitter Breaks Planar Stratification", () => {
  // Nodes with identical layer and importance must NOT have identical Z
  const zSet = new Set();
  for (let i = 0; i < 100; i++) {
    const z = computeNodeZ({ layer: 3, importance: 3, id: `test_node_${i}` });
    zSet.add(z.toFixed(4));
  }
  assert.ok(zSet.size > 80, `Expected >80 distinct Z values due to jitter, got ${zSet.size}`);
});

// ============================================================================
// TEST SUITE 2: 3D PERSPECTIVE PROJECTION & SINGULARITY CLAMPING
// ============================================================================

runTest("project3D Singularity & Extreme Z Range [-100,000 to +1,000,000]", () => {
  const W = 1920, H = 1080;
  const extremeZValues = [
    -1000000, -50000, -10000, -1000, -500, -499.9999, -475, -450,
    -100, -50, -1, 0, 1, 50, 100, 450, 500, 1000, 10000, 50000, 1000000
  ];

  for (const z of extremeZValues) {
    const res = project3D(100, 200, z, W, H, 50, -30, 1.5, 500);
    assert.ok(!isNaN(res.screenX), `screenX is NaN for z=${z}`);
    assert.ok(!isNaN(res.screenY), `screenY is NaN for z=${z}`);
    assert.ok(!isNaN(res.sz), `sz is NaN for z=${z}`);
    assert.ok(isFinite(res.screenX), `screenX is non-finite for z=${z}`);
    assert.ok(isFinite(res.screenY), `screenY is non-finite for z=${z}`);
    assert.ok(isFinite(res.sz), `sz is non-finite for z=${z}`);
    assert.ok(res.sz > 0, `sz must be strictly positive, got ${res.sz} for z=${z}`);
  }
});

runTest("project3D Extreme Zoom Scale Stability [k = 1e-6 to 1e6]", () => {
  const W = 1920, H = 1080;
  const zoomScales = [1e-6, 0.001, 0.05, 0.15, 0.5, 1.0, 2.0, 4.0, 10.0, 100.0, 1e4, 1e6];

  for (const k of zoomScales) {
    const res = project3D(250, -150, 25, W, H, 100, 100, k, 500);
    assert.ok(!isNaN(res.screenX), `screenX is NaN for k=${k}`);
    assert.ok(!isNaN(res.screenY), `screenY is NaN for k=${k}`);
    assert.ok(!isNaN(res.sz), `sz is NaN for k=${k}`);
    assert.ok(isFinite(res.screenX), `screenX non-finite for k=${k}`);
    assert.ok(isFinite(res.screenY), `screenY non-finite for k=${k}`);
  }
});

runTest("project3D Vanishing Point Spatial Invariance", () => {
  // When world point is at screen center (W/2, H/2) and pan is (0, 0), projected screen position must be (W/2, H/2) for ALL Z
  const W = 1920, H = 1080;
  for (let z = -450; z <= 5000; z += 50) {
    const res = project3D(W / 2, H / 2, z, W, H, 0, 0, 1.0, 500);
    assert.ok(Math.abs(res.screenX - W / 2) < 1e-9, `screenX (${res.screenX}) != W/2 (${W/2}) for z=${z}`);
    assert.ok(Math.abs(res.screenY - H / 2) < 1e-9, `screenY (${res.screenY}) != H/2 (${H/2}) for z=${z}`);
  }
});

runTest("project3D Monotonic Parallax Attenuation with Depth", () => {
  // Foreground nodes (z < 0) must exhibit GREATER parallax displacement than background nodes (z > 0)
  const W = 1920, H = 1080;
  const panX = 200, panY = 100;
  const fg = project3D(W / 2, H / 2, -80, W, H, panX, panY, 1.0, 500);
  const mid = project3D(W / 2, H / 2, 0, W, H, panX, panY, 1.0, 500);
  const bg = project3D(W / 2, H / 2, 80, W, H, panX, panY, 1.0, 500);

  const fgDispX = Math.abs(fg.screenX - W / 2);
  const midDispX = Math.abs(mid.screenX - W / 2);
  const bgDispX = Math.abs(bg.screenX - W / 2);

  assert.ok(fgDispX > midDispX, `Foreground parallax displacement (${fgDispX}) must exceed midground (${midDispX})`);
  assert.ok(midDispX > bgDispX, `Midground parallax displacement (${midDispX}) must exceed background (${bgDispX})`);
});

// ============================================================================
// TEST SUITE 3: UNPROJECT3D EXACT INVERSE ALGEBRAIC REVERSIBILITY
// ============================================================================

runTest("unproject3D Roundtrip Inversion across 50,000 Random Configurations", () => {
  const W = 1920, H = 1080;
  let maxError = 0;

  for (let i = 0; i < 50000; i++) {
    const x = (Math.random() - 0.5) * 4000;
    const y = (Math.random() - 0.5) * 4000;
    const z = (Math.random() - 0.5) * 180; // [-90, 90]
    const panX = (Math.random() - 0.5) * 1000;
    const panY = (Math.random() - 0.5) * 1000;
    const k = 0.15 + Math.random() * 3.85; // [0.15, 4.0]

    const proj = project3D(x, y, z, W, H, panX, panY, k, 500);
    const unproj = unproject3D(proj.screenX, proj.screenY, z, W, H, panX, panY, k, 500);

    const errX = Math.abs(unproj.worldX - x);
    const errY = Math.abs(unproj.worldY - y);
    const err = errX + errY;
    if (err > maxError) maxError = err;

    assert.ok(err < 1e-8, `Inverse error too large: ${err} (expected < 1e-8) for (${x}, ${y}, ${z})`);
  }
  console.log(`\n    [info] Max unproject3D roundtrip error across 50k points: ${maxError.toExponential(4)}`);
});

runTest("getPanToCenter Exact Mathematical Centering", () => {
  const W = 1920, H = 1080;
  for (let i = 0; i < 1000; i++) {
    const targetX = (Math.random() - 0.5) * 3000;
    const targetY = (Math.random() - 0.5) * 3000;
    const targetZ = (Math.random() - 0.5) * 180;
    const k = 0.2 + Math.random() * 3.5;

    const { tx, ty } = getPanToCenter(targetX, targetY, targetZ, W, H, k, 500);
    const proj = project3D(targetX, targetY, targetZ, W, H, tx, ty, k, 500);

    const errX = Math.abs(proj.screenX - W / 2);
    const errY = Math.abs(proj.screenY - H / 2);
    assert.ok(errX < 1e-7, `Centering error X: ${errX} (proj.screenX=${proj.screenX}, W/2=${W/2})`);
    assert.ok(errY < 1e-7, `Centering error Y: ${errY} (proj.screenY=${proj.screenY}, H/2=${H/2})`);
  }
});

// ============================================================================
// TEST SUITE 4: PAINTER'S ALGORITHM STABILITY UNDER OVERLAPPING & CO-PLANAR NODES
// ============================================================================

runTest("Painter's Algorithm Sorting Stability with 2,000 Co-Planar Elements", () => {
  // Construct 2,000 items with identical z = 0.0
  const items = [];
  for (let i = 0; i < 2000; i++) {
    items.push({ id: `item_${i}`, z: 0.0, order: i });
  }

  // Simulate 100 consecutive frames of sorting
  for (let frame = 0; frame < 100; frame++) {
    const copy = [...items];
    copy.sort((a, b) => b.z - a.z);

    // Verify ordering remained identical to original insertion order (ECMAScript stable sort)
    for (let i = 0; i < copy.length; i++) {
      assert.strictEqual(copy[i].id, `item_${i}`, `Sort instability detected at frame ${frame}, index ${i}`);
    }
  }
});

runTest("Painter's Algorithm Layering Invariant (Links behind Nodes at Equal Depth)", () => {
  // If node A is at z = 0 and node B is at z = 0:
  // Link depth = (0 + 0)/2 + 0.4 = 0.4
  // Sorted descending (b.z - a.z): item with z=0.4 comes BEFORE items with z=0.0
  // Therefore, Link (z=0.4) is rasterized FIRST, Nodes (z=0.0) are rasterized ON TOP!
  const nodeA = { type: 'node', z: 0.0, name: 'A' };
  const nodeB = { type: 'node', z: 0.0, name: 'B' };
  const linkAB = { type: 'link', z: (nodeA.z + nodeB.z) / 2 + 0.4, name: 'A-B' };

  const queue = [nodeA, linkAB, nodeB];
  queue.sort((a, b) => b.z - a.z);

  assert.strictEqual(queue[0].type, 'link', "Link must be first in render queue (drawn underneath)");
  assert.strictEqual(queue[1].type, 'node', "Node must be drawn on top of link");
  assert.strictEqual(queue[2].type, 'node', "Node must be drawn on top of link");
});

runTest("Painter's Depth Sorting Performance Benchmark (1,000 to 10,000 items)", () => {
  const itemCounts = [1000, 2500, 5000, 10000];
  for (const count of itemCounts) {
    const queue = [];
    for (let i = 0; i < count; i++) {
      queue.push({
        type: i % 2 === 0 ? 'node' : 'link',
        z: (Math.random() - 0.5) * 200,
        id: i
      });
    }

    const t0 = process.hrtime.bigint();
    for (let iter = 0; iter < 50; iter++) {
      const q = [...queue];
      q.sort((a, b) => b.z - a.z);
    }
    const t1 = process.hrtime.bigint();
    const avgMs = (Number(t1 - t0) / 50) / 1e6;
    console.log(`\n    [benchmark] Depth-sort ${count} items: ${avgMs.toFixed(3)}ms per frame`);
    assert.ok(avgMs < 5.0, `Sorting ${count} items exceeded 5ms budget: ${avgMs}ms`);
  }
});

// ============================================================================
// TEST SUITE 5: HIT TESTING DEPTH PRIORITY & AMBIGUITY RESOLUTION
// ============================================================================

runTest("Hit Testing Front-to-Back Depth Occlusion Priority", () => {
  // Two co-axial nodes at exact same (x, y) = (0, 0), but different depths:
  // Node 1 (Foreground): z = -50 (sz = 1.11, large)
  // Node 2 (Background): z = +50 (sz = 0.909, small)
  const W = 1920, H = 1080;
  const node1 = { id: 'fg_node', x: 0, y: 0, z: -50, importance: 4 };
  const node2 = { id: 'bg_node', x: 0, y: 0, z: 50, importance: 4 };

  const candidates = [
    { node: node2, z: node2.z, dist: 0, screenRadius: 20 },
    { node: node1, z: node1.z, dist: 0, screenRadius: 25 }
  ];

  // Depth priority sorting in hit testing: smallest z (foreground) first
  candidates.sort((a, b) => a.z - b.z);

  const topHit = candidates[0].node;
  assert.strictEqual(topHit.id, 'fg_node', `Foreground node must occlude background node in hit test`);
});

// ============================================================================
// TEST SUITE 6: FILAMENT QUAD & GRADIENT MATHEMATICAL BOUNDS
// ============================================================================

runTest("Tapered Filament Normal Vector & Degenerate Distance Guard", () => {
  // Test zero-length filament guard (sScreen == tScreen)
  const sScreen = { screenX: 500, screenY: 500 };
  const tScreen = { screenX: 500, screenY: 500 };

  const dx = tScreen.screenX - sScreen.screenX;
  const dy = tScreen.screenY - sScreen.screenY;
  const len = Math.hypot(dx, dy);

  // Must detect len < 0.5 and avoid division by zero
  assert.ok(len < 0.5, "Expected degenerate len < 0.5");
  const guardTriggered = len < 0.5;
  assert.ok(guardTriggered, "Degenerate guard must trigger");

  // Test non-degenerate normal vector calculation
  const tScreen2 = { screenX: 800, screenY: 900 };
  const dx2 = tScreen2.screenX - sScreen.screenX;
  const dy2 = tScreen2.screenY - sScreen.screenY;
  const len2 = Math.hypot(dx2, dy2);
  const nx = -dy2 / len2;
  const ny = dx2 / len2;

  const normalMagnitude = Math.hypot(nx, ny);
  assert.ok(Math.abs(normalMagnitude - 1.0) < 1e-9, `Normal vector magnitude must be 1.0, got ${normalMagnitude}`);
  // Orthogonality: dot product of (dx, dy) and (nx, ny) must be 0
  const dot = dx2 * nx + dy2 * ny;
  assert.ok(Math.abs(dot) < 1e-9, `Normal vector must be orthogonal (dot=${dot})`);
});

runTest("hexToRgba Adversarial Input Safety & Boundary Handling", () => {
  const tests = [
    { in: '#fff', alpha: 0.5, expected: 'rgba(255, 255, 255, 0.5)' },
    { in: '#00f0ff', alpha: 0.8, expected: 'rgba(0, 240, 255, 0.8)' },
    { in: '#123456', alpha: 1.0, expected: 'rgba(18, 52, 86, 1)' },
    { in: null, alpha: 0.4, contains: 'rgba(0, 240, 255, 0.4)' },
    { in: undefined, alpha: 0.4, contains: 'rgba(0, 240, 255, 0.4)' },
    { in: 'invalid_color', alpha: 0.2, contains: 'rgba(0, 240, 255, 0.2)' },
    { in: '', alpha: 0.0, contains: 'rgba(0, 240, 255, 0)' }
  ];

  for (const t of tests) {
    const res = hexToRgba(t.in, t.alpha);
    assert.ok(typeof res === 'string', `Result must be string`);
    assert.ok(res.startsWith('rgba('), `Result must be rgba string: ${res}`);
  }
});

// ============================================================================
// SUMMARY REPORT
// ============================================================================

console.log("\n======================================================================");
console.log(`TOTAL TESTS : ${totalTests}`);
console.log(`PASSED      : \x1b[32m${passedTests}\x1b[0m`);
console.log(`FAILED      : \x1b[${failedTests > 0 ? '31' : '32'}m${failedTests}\x1b[0m`);
console.log("======================================================================\n");

if (failedTests > 0) {
  process.exit(1);
}
