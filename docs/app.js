/**
 * Interactive Constellation 3D Depth Rendering Engine.
 * Roo4u Architecture Visualizer for GitHub Pages.
 */

(function () {
  'use strict';

  const THEMES = {
    'event-horizon': {
      name: 'Event Horizon',
      cssClass: 'theme-event-horizon',
      palette: {
        primary: '#00f0ff',
        secondary: '#7000ff',
        accent: '#ffffff',
        glow: 'rgba(0, 240, 255, 0.4)'
      },
      nodeStyle: 'plasma',
      filamentStyle: 'plasma-beam',
      font: 'JetBrains Mono, monospace'
    },
    'accretion-disk': {
      name: 'Accretion Disk',
      cssClass: 'theme-accretion-disk',
      palette: {
        primary: '#ffaa00',
        secondary: '#ff3300',
        accent: '#fff3d1',
        glow: 'rgba(255, 170, 0, 0.4)'
      },
      nodeStyle: 'solar',
      filamentStyle: 'solar-flare',
      font: 'Space Grotesk, sans-serif'
    },
    'quantum-void': {
      name: 'Quantum Void',
      cssClass: 'theme-quantum-void',
      palette: {
        primary: '#00ff88',
        secondary: '#006644',
        accent: '#e0fff0',
        glow: 'rgba(0, 255, 136, 0.4)'
      },
      nodeStyle: 'matrix',
      filamentStyle: 'quantum-flux',
      font: 'Fira Code, monospace'
    }
  };

  const state = {
    currentBranch: 'main',
    activeBranch: 'main',
    theme: 'event-horizon',
    activeLayout: 'cosmic',
    includeSwarm: true,
    activeCategoryFilters: new Set(),
    searchQuery: '',
    selectedNode: null,
    hoveredNode: null,
    isolatedNodeId: null,
    userHasPannedOrZoomed: false,
    zoomTransform: d3.zoomIdentity,
    nodes: [],
    physics: {
      charge: -480,
      linkDistance: 85,
      collision: 16,
      gravity: 0.055,
      photonSpeed: 1.0,
      showPhotons: true,
      showNebulas: true
    },
    photons: []
  };

  let graphData = null;
  let currentGraph = { nodes: [], links: [], clusters: [] };
  let simulation = null;
  let animFrameId = null;

  const graphCanvas = document.getElementById('graph-canvas');
  const graphCtx = graphCanvas.getContext('2d');

  const tooltipEl = document.getElementById('graph-tooltip');
  const searchInput = document.getElementById('node-search');
  const searchResultsEl = document.getElementById('search-results');
  const searchClearBtn = document.getElementById('search-clear');
  const layoutSelect = document.getElementById('layout-mode');
  const toggleSwarmCheckbox = document.getElementById('toggle-swarm');
  const categoryChipsContainer = document.getElementById('category-chips');
  const themeSelector = document.getElementById('theme-selector');

  const inspectorDrawer = document.getElementById('inspector-drawer');
  const closeInspectorBtn = document.getElementById('close-inspector-btn');
  const focusConstellationBtn = document.getElementById('focus-constellation-btn');
  const clearFocusBtn = document.getElementById('clear-focus-btn');
  const copyShaBtn = document.getElementById('insp-sha-copy') || document.getElementById('copy-sha-btn');

  const settingsDrawer = document.getElementById('settings-drawer') || document.getElementById('physics-panel');
  const toggleSettingsBtn = document.getElementById('toggle-settings-btn') || document.getElementById('toggle-controls-btn');
  const closeSettingsBtn = document.getElementById('close-settings-btn') || document.getElementById('close-physics-btn');

  const compareModal = document.getElementById('compare-modal');
  const closeCompareBtn = document.getElementById('close-compare-btn');

  const zoomBehavior = d3.zoom()
    .scaleExtent([0.15, 4.0])
    .on('zoom', (event) => {
      state.zoomTransform = event.transform;
      if (event.sourceEvent) {
        state.userHasPannedOrZoomed = true;
      }
      updateZoomIndicator();
    });

  d3.select(graphCanvas).call(zoomBehavior);

  /**
   * Computes deterministic continuous Z-coordinate in range [-100.0, 100.0].
   *
   * @param {Object} node Node object containing layer, importance, and id.
   * @returns {number} Z-depth coordinate in range [-100.0, 100.0].
   */
  function computeNodeZ(node) {
    const layer = Number(node.layer) || 3;
    const importance = Number(node.importance) || 3;
    const layerOffset = (layer - 3.5) * 20.0;
    const importanceOffset = (3.0 - importance) * 15.0;

    let h = 0;
    const idStr = String(node.id || '');
    for (let i = 0; i < idStr.length; i++) {
      h = (Math.imul(31, h) + idStr.charCodeAt(i)) | 0;
    }
    const jitter = (((Math.sin(h) * 43758.5453123) % 1.0) || 0) * 15.0;

    const z = layerOffset + importanceOffset + jitter;
    return Math.max(-100.0, Math.min(100.0, z));
  }

  /**
   * Projects 3D world coordinate (x, y, z) into 2D canvas screen space.
   *
   * @param {number} x World X coordinate.
   * @param {number} y World Y coordinate.
   * @param {number} z Depth Z coordinate in [-100, 100].
   * @param {number} width Viewport width in pixels.
   * @param {number} height Viewport height in pixels.
   * @param {number} panX D3 pan transform X translation.
   * @param {number} panY D3 pan transform Y translation.
   * @param {number} zoomScale D3 zoom transform K scale factor.
   * @param {number} [D=500] Focal distance constant.
   * @returns {{ screenX: number, screenY: number, sz: number }} Projected screen coordinates and perspective scale.
   */
  function project3D(x, y, z, width, height, panX, panY, zoomScale, D = 500) {
    const nodeZ = (z !== undefined && !isNaN(z)) ? Number(z) : 0;
    const clampedZ = Math.max(-D * 0.95, Math.min(10000, nodeZ));
    const sz = D / (D + clampedZ);
    const pFactor = Math.pow(sz, 0.6);
    const parallaxX = (panX || 0) * pFactor;
    const parallaxY = (panY || 0) * pFactor;
    const k = zoomScale || 1.0;

    const screenX = (x * k + parallaxX) * sz + (width / 2) * (1 - sz);
    const screenY = (y * k + parallaxY) * sz + (height / 2) * (1 - sz);

    return { screenX, screenY, sz };
  }

  /**
   * Analytical exact inverse of project3D for interactive node dragging.
   *
   * @param {number} screenX Cursor screen X coordinate.
   * @param {number} screenY Cursor screen Y coordinate.
   * @param {number} z Node depth Z coordinate.
   * @param {number} width Viewport width in pixels.
   * @param {number} height Viewport height in pixels.
   * @param {number} panX D3 pan transform X translation.
   * @param {number} panY D3 pan transform Y translation.
   * @param {number} zoomScale D3 zoom transform K scale factor.
   * @param {number} [D=500] Focal distance constant.
   * @returns {{ worldX: number, worldY: number, x: number, y: number }} Recovered world space coordinates.
   */
  function unproject3D(screenX, screenY, z, width, height, panX, panY, zoomScale, D = 500) {
    const nodeZ = (z !== undefined && !isNaN(z)) ? Number(z) : 0;
    const clampedZ = Math.max(-D * 0.95, Math.min(10000, nodeZ));
    const sz = D / (D + clampedZ);
    const pFactor = Math.pow(sz, 0.6);
    const parallaxX = (panX || 0) * pFactor;
    const parallaxY = (panY || 0) * pFactor;
    const k = zoomScale || 1.0;

    const worldX = ((screenX - (width / 2) * (1 - sz)) / sz - parallaxX) / k;
    const worldY = ((screenY - (height / 2) * (1 - sz)) / sz - parallaxY) / k;

    return { worldX, worldY, x: worldX, y: worldY };
  }

  /**
   * Solves analytical camera pan translation to center target 3D point at viewport center.
   *
   * @param {number} x Target world X coordinate.
   * @param {number} y Target world Y coordinate.
   * @param {number} z Target world Z coordinate.
   * @param {number} width Viewport width in pixels.
   * @param {number} height Viewport height in pixels.
   * @param {number} k Zoom scale factor.
   * @param {number} [D=500] Focal distance constant.
   * @returns {{ tx: number, ty: number }} Pan translation coordinates.
   */
  function getPanToCenter(x, y, z, width, height, k, D = 500) {
    const nodeZ = (z !== undefined && !isNaN(z)) ? Number(z) : 0;
    const clampedZ = Math.max(-D * 0.95, Math.min(10000, nodeZ));
    const sz = D / (D + clampedZ);
    const pFactor = Math.pow(sz, 0.6);

    const tx = (width / 2 - x * k) / pFactor;
    const ty = (height / 2 - y * k) / pFactor;

    return { tx, ty };
  }

  /**
   * Retrieves the dynamic rendered height of the application top header.
   *
   * @returns {number} Header height in pixels.
   */
  function getHeaderHeight() {
    const el = document.querySelector('.app-header');
    return el ? el.offsetHeight : 48;
  }

  /**
   * Performs depth-aware screen-space hit detection with front-to-back priority.
   *
   * @param {number} screenX Cursor screen X coordinate.
   * @param {number} screenY Cursor screen Y coordinate.
   * @param {number|null} [maxDistance=null] Optional fallback distance threshold.
   * @returns {Object|null} Top-most hit node or null if no node intersected.
   */
  function findNodeAt(screenX, screenY, maxDistance = null) {
    const width = window.innerWidth;
    const height = window.innerHeight - getHeaderHeight();
    const k = state.zoomTransform.k;
    const tx = state.zoomTransform.x;
    const ty = state.zoomTransform.y;

    const candidates = [];
    for (let i = 0; i < currentGraph.nodes.length; i++) {
      const n = currentGraph.nodes[i];
      if (n.x === undefined || n.y === undefined) continue;

      const z = n.z !== undefined ? n.z : 0;
      const proj = project3D(n.x, n.y, z, width, height, tx, ty, k);

      const isSelected = state.selectedNode && state.selectedNode.id === n.id;
      const isHovered = state.hoveredNode && state.hoveredNode.id === n.id;
      const baseRadius = (n.importance * 2.2) + 3.5;
      const radiusMultiplier = isSelected ? 1.6 : (isHovered ? 1.3 : 1.0);
      const screenRadius = Math.max(8, baseRadius * radiusMultiplier * proj.sz * Math.sqrt(k) + 6);
      const dist = Math.hypot(proj.screenX - screenX, proj.screenY - screenY);

      candidates.push({
        node: n,
        dist: dist,
        screenRadius: screenRadius,
        z: z,
        sz: proj.sz
      });
    }

    candidates.sort((a, b) => a.z - b.z);

    for (let i = 0; i < candidates.length; i++) {
      const c = candidates[i];
      if (c.dist <= c.screenRadius) {
        return c.node;
      }
    }

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

  /**
   * Retrieves node located at screen position coordinates.
   *
   * @param {number} screenX Screen X coordinate.
   * @param {number} screenY Screen Y coordinate.
   * @returns {Object|null} Intersected node or null.
   */
  function getNodeAtPosition(screenX, screenY) {
    return findNodeAt(screenX, screenY);
  }

  /**
   * Finds closest node within proximity fallback radius.
   *
   * @param {number} screenX Screen X coordinate.
   * @param {number} screenY Screen Y coordinate.
   * @returns {Object|null} Closest node or null.
   */
  function findClosestNode(screenX, screenY) {
    return findNodeAt(screenX, screenY, 35);
  }

  /**
   * Bootstraps application theme, canvas listeners, data, and render loops.
   */
  function init() {
    if (!window.ROO4U_GRAPH_DATA) {
      return;
    }
    graphData = window.ROO4U_GRAPH_DATA;

    initTheme();
    resizeCanvases();
    window.addEventListener('resize', resizeCanvases);

    setupEventListeners();
    setupComparisonModal();
    loadBranch(state.currentBranch);
    startRenderLoop();
    syncWindowExports();
  }

  /**
   * Resizes canvases to viewport dimensions with device pixel ratio scaling.
   */
  function resizeCanvases() {
    const width = window.innerWidth;
    const height = window.innerHeight - getHeaderHeight();
    const dpr = window.devicePixelRatio || 1;

    graphCanvas.width = width * dpr;
    graphCanvas.height = height * dpr;
    graphCanvas.style.width = `${width}px`;
    graphCanvas.style.height = `${height}px`;
    const ctx = graphCanvas.getContext('2d');
    ctx.resetTransform();
    ctx.scale(dpr, dpr);

    if (simulation) {
      const cx = width / 2;
      const cy = height / 2;
      const centerForce = simulation.force('center');
      if (centerForce) centerForce.x(cx).y(cy);
      if (state.activeLayout === 'cosmic') {
        const xForce = simulation.force('x');
        const yForce = simulation.force('y');
        if (xForce) xForce.x(cx);
        if (yForce) yForce.y(cy);
      }
    }
  }

  /**
   * Loads specified branch dataset, initializes graph structures, and restarts simulation.
   *
   * @param {string} branchName Branch identifier key ('main' or 'v2').
   */
  function loadBranch(branchName) {
    if (state.currentBranch !== branchName) {
      state.activeCategoryFilters.clear();
      state.userHasPannedOrZoomed = false;
    }
    state.currentBranch = branchName;
    state.activeBranch = branchName;
    const rawBranch = graphData.branches[branchName];
    if (!rawBranch) return;

    let filteredNodes = rawBranch.nodes.filter(n => state.includeSwarm || !n.isSwarm);

    if (state.activeCategoryFilters.size > 0) {
      filteredNodes = filteredNodes.filter(n => state.activeCategoryFilters.has(n.category));
    }

    const nodeIds = new Set(filteredNodes.map(n => n.id));
    const filteredLinks = rawBranch.links.filter(l => {
      const srcId = typeof l.source === 'object' ? l.source.id : l.source;
      const tgtId = typeof l.target === 'object' ? l.target.id : l.target;
      return nodeIds.has(srcId) && nodeIds.has(tgtId);
    });

    const nodes = filteredNodes.map(n => {
      const nodeClone = { ...n };
      nodeClone.z = computeNodeZ(nodeClone);
      return nodeClone;
    });

    const links = filteredLinks.map(l => ({
      ...l,
      source: typeof l.source === 'object' ? l.source.id : l.source,
      target: typeof l.target === 'object' ? l.target.id : l.target
    }));

    currentGraph = {
      nodes,
      links,
      clusters: rawBranch.clusters
    };
    state.nodes = nodes;

    initPhotons(links);
    updateHUDStats(rawBranch.stats);
    updateCategoryChips(rawBranch.clusters);
    buildSearchIndex(rawBranch.nodes);
    updateBranchUI(branchName);

    state.selectedNode = null;
    state.hoveredNode = null;
    state.isolatedNodeId = null;
    hideInspector();
    hideTooltip();

    initSimulation();
    syncWindowExports();
  }

  /**
   * Initializes volumetric photon particles traversing graph filaments.
   *
   * @param {Array<Object>} links Graph links array.
   */
  function initPhotons(links) {
    state.photons = [];
    links.forEach((l, index) => {
      if (index % 2 === 0) {
        state.photons.push({
          link: l,
          progress: Math.random(),
          speed: 0.006 + Math.random() * 0.008,
          size: Math.random() * 1.5 + 1.2,
          color: '#ffffff'
        });
      }
    });
  }

  /**
   * Initializes force simulation with warm-up settling iterations and viewport framing.
   */
  function initSimulation() {
    if (simulation) simulation.stop();

    const width = window.innerWidth;
    const height = window.innerHeight - getHeaderHeight();
    const cx = width / 2;
    const cy = height / 2;

    const nodeCount = currentGraph.nodes.length;
    currentGraph.nodes.forEach((n, idx) => {
      if (n.x === undefined || n.y === undefined || isNaN(n.x) || isNaN(n.y)) {
        const angle = (idx / nodeCount) * Math.PI * 2 * 3;
        const dist = 60 + (idx % 10) * 45;
        n.x = cx + Math.cos(angle) * dist;
        n.y = cy + Math.sin(angle) * dist;
      }
    });

    simulation = d3.forceSimulation(currentGraph.nodes)
      .force('link', d3.forceLink(currentGraph.links).id(d => d.id).distance(state.physics.linkDistance).strength(0.5))
      .force('charge', d3.forceManyBody().strength(state.physics.charge))
      .force('collide', d3.forceCollide().radius(d => (d.importance * 3) + state.physics.collision).iterations(2))
      .force('center', d3.forceCenter(cx, cy))
      .force('x', d3.forceX(cx).strength(state.physics.gravity))
      .force('y', d3.forceY(cy).strength(state.physics.gravity))
      .alphaDecay(0.02)
      .velocityDecay(0.35)
      .on('tick', () => {});

    applyLayoutPositions(state.activeLayout);

    const warmupTicks = 120;
    for (let i = 0; i < warmupTicks; i++) {
      simulation.tick();
    }

    fitToViewport(0);

    setTimeout(() => {
      if (state.selectedNode === null && state.isolatedNodeId === null && !state.userHasPannedOrZoomed) {
        fitToViewport(600);
      }
    }, 1200);

    syncWindowExports();
  }

  /**
   * Applies layout positioning forces based on selected mode.
   *
   * @param {string} layout Layout name ('cosmic', 'concentric', 'layered', 'clusters').
   */
  function applyLayoutPositions(layout) {
    state.activeLayout = layout;
    const width = window.innerWidth;
    const height = window.innerHeight - getHeaderHeight();
    const cx = width / 2;
    const cy = height / 2;

    if (!simulation) return;

    if (layout === 'cosmic') {
      simulation.force('x', d3.forceX(cx).strength(state.physics.gravity));
      simulation.force('y', d3.forceY(cy).strength(state.physics.gravity));
      simulation.force('charge').strength(state.physics.charge);
    } else if (layout === 'concentric') {
      simulation.force('x', d3.forceX(d => {
        const radius = (d.layer - 1) * 120 + 80;
        const angle = (currentGraph.nodes.indexOf(d) / currentGraph.nodes.length) * Math.PI * 2;
        return cx + Math.cos(angle) * radius;
      }).strength(0.3));
      simulation.force('y', d3.forceY(d => {
        const radius = (d.layer - 1) * 120 + 80;
        const angle = (currentGraph.nodes.indexOf(d) / currentGraph.nodes.length) * Math.PI * 2;
        return cy + Math.sin(angle) * radius;
      }).strength(0.3));
      simulation.force('charge').strength(-300);
    } else if (layout === 'layered') {
      simulation.force('x', d3.forceX(d => {
        return (d.layer - 3.5) * 220 + cx;
      }).strength(0.4));
      simulation.force('y', d3.forceY(cy).strength(0.05));
      simulation.force('charge').strength(-250);
    } else if (layout === 'clusters') {
      const clusterNames = Array.from(new Set(currentGraph.nodes.map(n => n.category)));
      const clusterAngles = {};
      clusterNames.forEach((c, idx) => {
        clusterAngles[c] = (idx / clusterNames.length) * Math.PI * 2;
      });

      simulation.force('x', d3.forceX(d => {
        const a = clusterAngles[d.category] || 0;
        return cx + Math.cos(a) * 320;
      }).strength(0.35));
      simulation.force('y', d3.forceY(d => {
        const a = clusterAngles[d.category] || 0;
        return cy + Math.sin(a) * 260;
      }).strength(0.35));
      simulation.force('charge').strength(-200);
    }

    simulation.alpha(0.6).restart();
  }

  /**
   * Starts continuous animation frame rendering loop.
   */
  function startRenderLoop() {
    function frame() {
      renderGraph();
      animFrameId = requestAnimationFrame(frame);
    }
    animFrameId = requestAnimationFrame(frame);
  }

  /**
   * Unified 3D depth render pipeline executing painter algorithm rasterization.
   */
  function renderGraph() {
    const width = window.innerWidth;
    const height = window.innerHeight - getHeaderHeight();
    graphCtx.clearRect(0, 0, width, height);

    const panX = state.zoomTransform.x;
    const panY = state.zoomTransform.y;
    const zoomScale = state.zoomTransform.k;
    const activeTheme = THEMES[state.theme] || THEMES['event-horizon'];

    const activeNode = state.hoveredNode || state.selectedNode;
    let connectedNodeIds = null;
    if (activeNode) {
      connectedNodeIds = getConnectedNodeIds(activeNode.id);
    } else if (state.isolatedNodeId) {
      connectedNodeIds = getConnectedNodeIds(state.isolatedNodeId);
    }

    if (state.physics.showNebulas && state.activeLayout !== 'layered') {
      renderClusterNebulas3D(width, height, panX, panY, zoomScale);
    }

    const renderQueue = [];

    for (let i = 0; i < currentGraph.nodes.length; i++) {
      const n = currentGraph.nodes[i];
      if (n.x === undefined || n.y === undefined) continue;
      if (n.z === undefined) n.z = computeNodeZ(n);

      const proj = project3D(n.x, n.y, n.z, width, height, panX, panY, zoomScale);
      n.screenX = proj.screenX;
      n.screenY = proj.screenY;
      n.sz = proj.sz;

      renderQueue.push({ type: 'node', z: n.z, data: n, proj });
    }

    for (let i = 0; i < currentGraph.links.length; i++) {
      const l = currentGraph.links[i];
      const s = l.source;
      const t = l.target;
      if (!s.x || !s.y || !t.x || !t.y) continue;

      if (s.screenX === undefined || s.screenY === undefined) {
        const sProj = project3D(s.x, s.y, s.z || 0, width, height, panX, panY, zoomScale);
        s.screenX = sProj.screenX; s.screenY = sProj.screenY; s.sz = sProj.sz;
      }
      if (t.screenX === undefined || t.screenY === undefined) {
        const tProj = project3D(t.x, t.y, t.z || 0, width, height, panX, panY, zoomScale);
        t.screenX = tProj.screenX; t.screenY = tProj.screenY; t.sz = tProj.sz;
      }

      const sProj = { screenX: s.screenX, screenY: s.screenY, sz: s.sz };
      const tProj = { screenX: t.screenX, screenY: t.screenY, sz: t.sz };
      const linkZ = ((s.z !== undefined ? s.z : 0) + (t.z !== undefined ? t.z : 0)) / 2 + 0.4;

      renderQueue.push({ type: 'link', z: linkZ, data: l, sProj, tProj });
    }

    if (state.physics.showPhotons && (state.physics.photonSpeed || 1.0) > 0) {
      for (let i = 0; i < state.photons.length; i++) {
        const p = state.photons[i];
        const s = p.link.source;
        const t = p.link.target;
        if (!s.x || !s.y || !t.x || !t.y) continue;

        const sz_s = s.z !== undefined ? s.z : 0;
        const sz_t = t.z !== undefined ? t.z : 0;
        const pz = sz_s + (sz_t - sz_s) * p.progress;

        renderQueue.push({ type: 'photon', z: pz - 0.2, data: p });
      }
    }

    renderQueue.sort((a, b) => b.z - a.z);

    for (let i = 0; i < renderQueue.length; i++) {
      const item = renderQueue[i];
      if (item.type === 'link') {
        renderLink3D(graphCtx, item.data, item.sProj, item.tProj, connectedNodeIds, activeTheme);
      } else if (item.type === 'photon') {
        drawPhotonParticle(graphCtx, item.data, connectedNodeIds, activeTheme, width, height, panX, panY, zoomScale);
      } else if (item.type === 'node') {
        renderNode3D(graphCtx, item.data, item.proj, connectedNodeIds, activeTheme);
      }
    }

    renderLabels3D(graphCtx, connectedNodeIds, activeTheme);
  }

  /**
   * Renders volumetric radial gradients for constellation clusters in 3D perspective.
   *
   * @param {number} width Viewport width in pixels.
   * @param {number} height Viewport height in pixels.
   * @param {number} panX Camera pan X translation.
   * @param {number} panY Camera pan Y translation.
   * @param {number} zoomScale Camera zoom scale factor.
   */
  function renderClusterNebulas3D(width, height, panX, panY, zoomScale) {
    const clusterMap = {};
    currentGraph.nodes.forEach(n => {
      if (n.x === undefined || n.y === undefined) return;
      if (!clusterMap[n.category]) {
        clusterMap[n.category] = { color: n.color, points: [], sumX: 0, sumY: 0, sumZ: 0 };
      }
      clusterMap[n.category].points.push(n);
      clusterMap[n.category].sumX += n.x;
      clusterMap[n.category].sumY += n.y;
      clusterMap[n.category].sumZ += (n.z !== undefined ? n.z : 0);
    });

    const clusters = Object.values(clusterMap).filter(c => c.points.length >= 2);
    clusters.sort((a, b) => {
      const za = a.sumZ / a.points.length;
      const zb = b.sumZ / b.points.length;
      return zb - za;
    });

    clusters.forEach(c => {
      const avgX = c.sumX / c.points.length;
      const avgY = c.sumY / c.points.length;
      const avgZ = c.sumZ / c.points.length;

      const proj = project3D(avgX, avgY, avgZ, width, height, panX, panY, zoomScale);

      let maxDist = 40;
      c.points.forEach(p => {
        const d = Math.hypot(p.x - avgX, p.y - avgY);
        if (d > maxDist) maxDist = d;
      });

      const radius = (maxDist + 60) * proj.sz * Math.sqrt(zoomScale);
      if (radius < 5) return;

      const grad = graphCtx.createRadialGradient(
        proj.screenX, proj.screenY, 10 * proj.sz,
        proj.screenX, proj.screenY, radius
      );
      grad.addColorStop(0, hexToRgba(c.color, 0.14 * Math.pow(proj.sz, 1.5)));
      grad.addColorStop(0.6, hexToRgba(c.color, 0.04 * Math.pow(proj.sz, 1.5)));
      grad.addColorStop(1, 'rgba(0,0,0,0)');

      graphCtx.beginPath();
      graphCtx.arc(proj.screenX, proj.screenY, radius, 0, Math.PI * 2);
      graphCtx.fillStyle = grad;
      graphCtx.fill();
    });
  }

  /**
   * Extrudes a trapezoidal polygon (Quad) between source and target screen positions.
   *
   * @param {CanvasRenderingContext2D} ctx Canvas 2D rendering context.
   * @param {{ screenX: number, screenY: number }} sScreen Source screen coordinate object.
   * @param {{ screenX: number, screenY: number }} tScreen Target screen coordinate object.
   * @param {number} rs Radius at source star.
   * @param {number} rt Radius at target star.
   * @param {string|CanvasGradient} fillStyle Fill style for extruded polygon.
   * @param {string|null} shadowColor Glow shadow color string.
   * @param {number} shadowBlur Glow shadow blur radius in pixels.
   */
  function drawTaperedFilament(ctx, sScreen, tScreen, rs, rt, fillStyle, shadowColor, shadowBlur) {
    const dx = tScreen.screenX - sScreen.screenX;
    const dy = tScreen.screenY - sScreen.screenY;
    const len = Math.hypot(dx, dy);
    if (len < 0.5) return;

    const nx = -dy / len;
    const ny = dx / len;

    const halfRs = Math.max(rs, 0.35);
    const halfRt = Math.max(rt, 0.35);

    const v1x = sScreen.screenX + nx * halfRs;
    const v1y = sScreen.screenY + ny * halfRs;
    const v2x = tScreen.screenX + nx * halfRt;
    const v2y = tScreen.screenY + ny * halfRt;
    const v3x = tScreen.screenX - nx * halfRt;
    const v3y = tScreen.screenY - ny * halfRt;
    const v4x = sScreen.screenX - nx * halfRs;
    const v4y = sScreen.screenY - ny * halfRs;

    ctx.beginPath();
    ctx.moveTo(v1x, v1y);
    ctx.lineTo(v2x, v2y);
    ctx.lineTo(v3x, v3y);
    ctx.lineTo(v4x, v4y);
    ctx.closePath();

    ctx.fillStyle = fillStyle;
    if (shadowBlur > 0 && shadowColor) {
      ctx.shadowColor = shadowColor;
      ctx.shadowBlur = shadowBlur;
    }
    ctx.fill();
    if (shadowBlur > 0) {
      ctx.shadowBlur = 0;
    }
  }

  /**
   * Renders a depth-tapered connection between source and target stars in 3D space.
   *
   * @param {CanvasRenderingContext2D} ctx Canvas 2D rendering context.
   * @param {Object} link Link object connecting two nodes.
   * @param {{ screenX: number, screenY: number, sz: number }} sScreen Source projected screen position.
   * @param {{ screenX: number, screenY: number, sz: number }} tScreen Target projected screen position.
   * @param {Set<string>|null} connectedNodeIds Active connected node ID set.
   * @param {Object} theme Active theme configuration object.
   */
  function renderLink3D(ctx, link, sScreen, tScreen, connectedNodeIds, theme) {
    const s = link.source;
    const t = link.target;
    const isConnected = connectedNodeIds && connectedNodeIds.has(s.id) && connectedNodeIds.has(t.id);
    const isDimmed = connectedNodeIds && !isConnected;

    const szS = sScreen.sz || 1.0;
    const szT = tScreen.sz || 1.0;
    const avgSz = (szS + szT) / 2;

    let baseWidth = 1.0;
    if (isConnected) {
      baseWidth = 2.4;
    } else if (isDimmed) {
      baseWidth = 0.6;
    }

    const rs = (baseWidth * szS) / 2;
    const rt = (baseWidth * szT) / 2;

    const alphaS = isConnected ? 0.95 : (isDimmed ? 0.02 * Math.pow(szS, 1.8) : Math.min(0.5, 0.22 * Math.pow(szS, 1.8)));
    const alphaT = isConnected ? 0.95 : (isDimmed ? 0.02 * Math.pow(szT, 1.8) : Math.min(0.5, 0.22 * Math.pow(szT, 1.8)));

    const grad = ctx.createLinearGradient(sScreen.screenX, sScreen.screenY, tScreen.screenX, tScreen.screenY);
    const colorPrimary = (theme && theme.palette && theme.palette.primary) || '#00f0ff';
    const colorSecondary = (theme && theme.palette && theme.palette.secondary) || '#7000ff';
    const colorAccent = (theme && theme.palette && theme.palette.accent) || '#ffffff';

    if (isConnected) {
      grad.addColorStop(0, hexToRgba(colorPrimary, alphaS));
      grad.addColorStop(0.5, hexToRgba(colorAccent, (alphaS + alphaT) * 0.5));
      grad.addColorStop(1, hexToRgba(colorSecondary, alphaT));
      drawTaperedFilament(ctx, sScreen, tScreen, rs, rt, grad, colorPrimary, 12 * avgSz);
    } else if (isDimmed) {
      grad.addColorStop(0, hexToRgba('#94a3b8', alphaS));
      grad.addColorStop(1, hexToRgba('#64748b', alphaT));
      drawTaperedFilament(ctx, sScreen, tScreen, rs, rt, grad, null, 0);
    } else {
      const colS = s.color || colorPrimary;
      const colT = t.color || colorSecondary;
      grad.addColorStop(0, hexToRgba(colS, alphaS));
      grad.addColorStop(1, hexToRgba(colT, alphaT));
      drawTaperedFilament(ctx, sScreen, tScreen, rs, rt, grad, null, 0);
    }
  }

  /**
   * Simulates and renders volumetric 3D photons traversing links in perspective.
   *
   * @param {CanvasRenderingContext2D} ctx Canvas 2D rendering context.
   * @param {Object} photon Photon particle state object.
   * @param {Set<string>|null} connectedNodeIds Active connected node ID set.
   * @param {Object} theme Active theme configuration object.
   * @param {number} width Viewport width in pixels.
   * @param {number} height Viewport height in pixels.
   * @param {number} panX Camera pan X translation.
   * @param {number} panY Camera pan Y translation.
   * @param {number} zoomScale Camera zoom scale factor.
   */
  function drawPhotonParticle(ctx, photon, connectedNodeIds, theme, width, height, panX, panY, zoomScale) {
    const s = photon.link.source;
    const t = photon.link.target;
    if (!s.x || !s.y || !t.x || !t.y) return;

    const isConnected = connectedNodeIds && connectedNodeIds.has(s.id) && connectedNodeIds.has(t.id);
    const isDimmed = connectedNodeIds && !isConnected;

    const speedMult = (state.physics.photonSpeed || 1.0) * (isConnected ? 1.6 : 1.0);
    photon.progress = (photon.progress + (photon.speed || 0.008) * speedMult);
    if (photon.progress >= 1.0) photon.progress = photon.progress % 1.0;

    const tau = photon.progress;
    const sz_s = s.z !== undefined ? s.z : 0;
    const sz_t = t.z !== undefined ? t.z : 0;

    const px = s.x + (t.x - s.x) * tau;
    const py = s.y + (t.y - s.y) * tau;
    const pz = sz_s + (sz_t - sz_s) * tau;
    const headProj = project3D(px, py, pz, width, height, panX, panY, zoomScale);

    const tauTail = Math.max(0, tau - 0.05);
    const tx = s.x + (t.x - s.x) * tauTail;
    const ty = s.y + (t.y - s.y) * tauTail;
    const tz = sz_s + (sz_t - sz_s) * tauTail;
    const tailProj = project3D(tx, ty, tz, width, height, panX, panY, zoomScale);

    const radius = (photon.size || 1.5) * headProj.sz * (isConnected ? 1.4 : 1.0);
    const alpha = isDimmed ? 0.06 : Math.min(1.0, 0.85 * Math.pow(headProj.sz, 1.5));
    const particleColor = isConnected
      ? ((theme && theme.palette && theme.palette.primary) || '#00f0ff')
      : ((theme && theme.palette && theme.palette.accent) || '#ffffff');

    if (tau > 0.05 && !isDimmed) {
      const trailGrad = ctx.createLinearGradient(
        tailProj.screenX, tailProj.screenY,
        headProj.screenX, headProj.screenY
      );
      trailGrad.addColorStop(0, hexToRgba(particleColor, 0));
      trailGrad.addColorStop(1, hexToRgba(particleColor, alpha * 0.7));

      ctx.strokeStyle = trailGrad;
      ctx.lineWidth = Math.max(0.6, radius * 1.5);
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.moveTo(tailProj.screenX, tailProj.screenY);
      ctx.lineTo(headProj.screenX, headProj.screenY);
      ctx.stroke();
    }

    const glowR = Math.max(1.5, radius * 2.2);
    const orbGrad = ctx.createRadialGradient(
      headProj.screenX, headProj.screenY, radius * 0.2,
      headProj.screenX, headProj.screenY, glowR
    );
    orbGrad.addColorStop(0, '#ffffff');
    orbGrad.addColorStop(0.35, hexToRgba(particleColor, alpha));
    orbGrad.addColorStop(1, 'rgba(0,0,0,0)');

    ctx.fillStyle = orbGrad;
    ctx.beginPath();
    ctx.arc(headProj.screenX, headProj.screenY, glowR, 0, Math.PI * 2);
    ctx.fill();
  }

  /**
   * Renders a stellar node with depth-scaled radius, core brightness, and theme-specific shaders.
   *
   * @param {CanvasRenderingContext2D} ctx Canvas 2D rendering context.
   * @param {Object} n Stellar node data object.
   * @param {{ screenX: number, screenY: number, sz: number }} proj Projected screen coordinates and scale.
   * @param {Set<string>|null} connectedNodeIds Active connected node ID set.
   * @param {Object} theme Active theme configuration object.
   */
  function renderNode3D(ctx, n, proj, connectedNodeIds, theme) {
    const isConnected = connectedNodeIds && connectedNodeIds.has(n.id);
    const isDimmed = connectedNodeIds && !isConnected;
    const isSelected = state.selectedNode && state.selectedNode.id === n.id;
    const isHovered = state.hoveredNode && state.hoveredNode.id === n.id;

    const k = state.zoomTransform.k;
    const sz = proj.sz || 1.0;
    const sx = proj.screenX;
    const sy = proj.screenY;

    const baseRadius = (n.importance * 2.2) + 3.5;
    const radiusMultiplier = isSelected ? 1.6 : (isHovered ? 1.3 : 1.0);
    const radius = Math.max(0.8, baseRadius * radiusMultiplier * sz * Math.sqrt(k));

    const nodeStyle = (theme && theme.nodeStyle) || 'plasma';
    const colorPrimary = (theme && theme.palette && theme.palette.primary) || '#00f0ff';
    const colorSecondary = (theme && theme.palette && theme.palette.secondary) || '#7000ff';
    const colorAccent = (theme && theme.palette && theme.palette.accent) || '#ffffff';

    const alphaZ = Math.max(0.20, Math.min(1.0, 0.25 + 0.75 * sz));

    if (nodeStyle === 'solar') {
      const coronaRadius = Math.max(radius * 1.8, radius * (2.2 + 2.5 * sz));
      const baseCoronaAlpha = isConnected ? 0.75 : (isDimmed ? 0.05 : 0.45);
      const coronaAlpha = Math.max(0.02, Math.min(1.0, baseCoronaAlpha * Math.pow(sz, 1.5)));

      const coronaGrad = ctx.createRadialGradient(sx, sy, radius * 0.3, sx, sy, coronaRadius);
      coronaGrad.addColorStop(0, hexToRgba(colorPrimary, coronaAlpha));
      coronaGrad.addColorStop(0.5, hexToRgba(colorSecondary, coronaAlpha * 0.6));
      coronaGrad.addColorStop(1, 'rgba(0,0,0,0)');

      ctx.beginPath();
      ctx.arc(sx, sy, coronaRadius, 0, Math.PI * 2);
      ctx.fillStyle = coronaGrad;
      ctx.fill();

      if (isSelected) {
        const time = Date.now() * 0.004;
        const flareR = radius + (8 + Math.sin(time) * 5) * sz;
        ctx.beginPath();
        ctx.arc(sx, sy, flareR, 0, Math.PI * 2);
        ctx.strokeStyle = hexToRgba(colorPrimary, 0.9);
        ctx.lineWidth = Math.max(1.2, 2.5 * sz);
        ctx.stroke();
      }

      ctx.beginPath();
      ctx.arc(sx, sy, radius, 0, Math.PI * 2);
      if (isDimmed) {
        ctx.fillStyle = hexToRgba(n.color, 0.25 * alphaZ);
      } else if (isConnected || isSelected) {
        ctx.fillStyle = n.color;
      } else {
        ctx.fillStyle = hexToRgba(n.color, alphaZ);
      }
      ctx.fill();

      if (!isDimmed) {
        const specR = Math.max(0.4, radius * 0.5 * sz);
        const specAlpha = Math.max(0.2, Math.min(1.0, (isConnected ? 0.95 : 0.7) * sz));
        ctx.beginPath();
        ctx.arc(sx, sy, specR, 0, Math.PI * 2);
        ctx.fillStyle = colorAccent;
        ctx.globalAlpha = specAlpha;
        ctx.fill();
        ctx.globalAlpha = 1.0;
      }
    } else if (nodeStyle === 'matrix') {
      const gridRadius = Math.max(radius * 1.5, radius * (1.9 + 2.0 * sz));
      const baseGridAlpha = isConnected ? 0.70 : (isDimmed ? 0.05 : 0.40);
      const gridAlpha = Math.max(0.02, Math.min(1.0, baseGridAlpha * Math.pow(sz, 1.5)));

      const gridGrad = ctx.createRadialGradient(sx, sy, radius * 0.3, sx, sy, gridRadius);
      gridGrad.addColorStop(0, hexToRgba(colorPrimary, gridAlpha));
      gridGrad.addColorStop(0.6, hexToRgba(colorSecondary, gridAlpha * 0.5));
      gridGrad.addColorStop(1, 'rgba(0,0,0,0)');

      ctx.beginPath();
      ctx.arc(sx, sy, gridRadius, 0, Math.PI * 2);
      ctx.fillStyle = gridGrad;
      ctx.fill();

      if (isSelected) {
        const crossSize = radius + 10 * sz;
        ctx.strokeStyle = hexToRgba(colorPrimary, 0.85);
        ctx.lineWidth = Math.max(1, 1.5 * sz);
        ctx.beginPath();
        ctx.moveTo(sx - crossSize, sy); ctx.lineTo(sx + crossSize, sy);
        ctx.moveTo(sx, sy - crossSize); ctx.lineTo(sx, sy + crossSize);
        ctx.stroke();

        ctx.beginPath();
        ctx.arc(sx, sy, radius + 4 * sz, 0, Math.PI * 2);
        ctx.stroke();
      }

      ctx.beginPath();
      ctx.arc(sx, sy, radius, 0, Math.PI * 2);
      if (isDimmed) {
        ctx.fillStyle = hexToRgba(n.color, 0.25 * alphaZ);
      } else if (isConnected || isSelected) {
        ctx.fillStyle = n.color;
      } else {
        ctx.fillStyle = hexToRgba(n.color, alphaZ);
      }
      ctx.fill();

      if (!isDimmed) {
        const specR = Math.max(0.4, radius * 0.4 * sz);
        const specAlpha = Math.max(0.2, Math.min(1.0, (isConnected ? 0.95 : 0.65) * sz));
        ctx.beginPath();
        ctx.arc(sx, sy, specR, 0, Math.PI * 2);
        ctx.fillStyle = colorAccent;
        ctx.globalAlpha = specAlpha;
        ctx.fill();
        ctx.globalAlpha = 1.0;
      }
    } else {
      const haloRadius = Math.max(radius * 1.5, radius * (1.8 + 2.2 * sz));
      const baseHaloAlpha = isConnected ? 0.60 : (isDimmed ? 0.05 : 0.35);
      const haloAlpha = Math.max(0.02, Math.min(1.0, baseHaloAlpha * Math.pow(sz, 1.5)));

      const haloGrad = ctx.createRadialGradient(sx, sy, radius * 0.4, sx, sy, haloRadius);
      haloGrad.addColorStop(0, hexToRgba(n.color, haloAlpha));
      haloGrad.addColorStop(1, 'rgba(0,0,0,0)');

      ctx.beginPath();
      ctx.arc(sx, sy, haloRadius, 0, Math.PI * 2);
      ctx.fillStyle = haloGrad;
      ctx.fill();

      if (isSelected) {
        const time = Date.now() * 0.003;
        const pulseR = radius + (6 + Math.sin(time) * 4) * sz;
        ctx.beginPath();
        ctx.arc(sx, sy, pulseR, 0, Math.PI * 2);
        ctx.strokeStyle = hexToRgba(colorPrimary, 0.85);
        ctx.lineWidth = Math.max(1, 2 * sz);
        ctx.setLineDash([4 * sz, 4 * sz]);
        ctx.stroke();
        ctx.setLineDash([]);
      }

      ctx.beginPath();
      ctx.arc(sx, sy, radius, 0, Math.PI * 2);
      if (isDimmed) {
        ctx.fillStyle = hexToRgba(n.color, 0.25 * alphaZ);
      } else if (isConnected || isSelected) {
        ctx.fillStyle = n.color;
      } else {
        ctx.fillStyle = hexToRgba(n.color, alphaZ);
      }
      ctx.fill();

      if (!isDimmed) {
        const specR = Math.max(0.4, radius * 0.45 * sz);
        const specAlpha = Math.max(0.2, Math.min(1.0, (isConnected ? 0.95 : 0.65) * sz));
        ctx.beginPath();
        ctx.arc(sx, sy, specR, 0, Math.PI * 2);
        ctx.fillStyle = '#ffffff';
        ctx.globalAlpha = specAlpha;
        ctx.fill();
        ctx.globalAlpha = 1.0;
      }
    }
  }

  /**
   * Renders labels overlay with Level-of-Detail (LOD) and depth-scaled typography.
   *
   * @param {CanvasRenderingContext2D} ctx Canvas 2D rendering context.
   * @param {Set<string>|null} connectedNodeIds Active connected node ID set.
   * @param {Object} theme Active theme configuration object.
   */
  function renderLabels3D(ctx, connectedNodeIds, theme) {
    const k = state.zoomTransform.k;

    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';

    currentGraph.nodes.forEach(n => {
      if (n.screenX === undefined || n.screenY === undefined) return;

      const isConnected = connectedNodeIds && connectedNodeIds.has(n.id);
      const isDimmed = connectedNodeIds && !isConnected;
      const isSelected = state.selectedNode && state.selectedNode.id === n.id;
      const isMajor = n.importance >= 4;

      const sz = n.sz || 1.0;
      const kEff = k * sz;
      const showAll = kEff > 1.3;
      const showImportant = kEff > 0.55;

      if (isConnected || isSelected || showAll || (showImportant && isMajor)) {
        const baseRadius = (n.importance * 2.2) + 3.5;
        const radiusMultiplier = isSelected ? 1.6 : 1.0;
        const r = Math.max(0.8, baseRadius * radiusMultiplier * sz * Math.sqrt(k));
        const labelY = n.screenY + r + 4;

        const fontSize = Math.max(8, Math.round(10 * sz));
        const fontFace = (theme && theme.font) ? theme.font : 'Inter, sans-serif';

        if (isConnected || isSelected) {
          ctx.fillStyle = '#ffffff';
          ctx.font = `bold ${fontSize + 1}px ${fontFace}`;
          ctx.shadowColor = '#000000';
          ctx.shadowBlur = 4;
        } else if (isDimmed) {
          ctx.fillStyle = 'rgba(148, 163, 184, 0.2)';
          ctx.font = `${fontSize}px ${fontFace}`;
          ctx.shadowBlur = 0;
        } else {
          ctx.fillStyle = '#cbd5e1';
          ctx.font = `${fontSize}px ${fontFace}`;
          ctx.shadowBlur = 0;
        }

        ctx.fillText(n.label, n.screenX, labelY);
        ctx.shadowBlur = 0;
      }
    });
  }

  /**
   * Retrieves adjacent connected node IDs for 1-hop and 2-hop graph traversal.
   *
   * @param {string} nodeId Target node identifier.
   * @returns {Set<string>} Set of connected node identifiers.
   */
  function getConnectedNodeIds(nodeId) {
    const connected = new Set([nodeId]);
    currentGraph.links.forEach(l => {
      const sId = typeof l.source === 'object' ? l.source.id : l.source;
      const tId = typeof l.target === 'object' ? l.target.id : l.target;
      if (sId === nodeId) connected.add(tId);
      if (tId === nodeId) connected.add(sId);
    });
    return connected;
  }

  /**
   * Binds user interaction listeners across DOM controls, keyboard, search, and canvas.
   */
  function setupEventListeners() {
    const tabMain = document.getElementById('tab-main');
    if (tabMain) tabMain.addEventListener('click', () => loadBranch('main'));

    const tabV2 = document.getElementById('tab-v2');
    if (tabV2) tabV2.addEventListener('click', () => loadBranch('v2'));

    const tabCompare = document.getElementById('tab-compare');
    if (tabCompare) tabCompare.addEventListener('click', showComparisonModal);

    if (toggleSwarmCheckbox) {
      toggleSwarmCheckbox.addEventListener('change', (e) => {
        state.includeSwarm = e.target.checked;
        loadBranch(state.currentBranch);
      });
    }

    if (layoutSelect) {
      layoutSelect.addEventListener('change', (e) => {
        applyLayoutPositions(e.target.value);
      });
    }

    if (themeSelector) {
      themeSelector.addEventListener('change', (e) => {
        setTheme(e.target.value);
      });
    }

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

    d3.select(graphCanvas).call(
      d3.drag()
        .container(graphCanvas)
        .subject(event => {
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
          const width = window.innerWidth;
          const height = window.innerHeight - getHeaderHeight();
          const unproj = unproject3D(
            event.x,
            event.y,
            event.subject.z || 0,
            width,
            height,
            state.zoomTransform.x,
            state.zoomTransform.y,
            state.zoomTransform.k
          );
          event.subject.fx = unproj.worldX;
          event.subject.fy = unproj.worldY;
        })
        .on('end', (event) => {
          if (!event.subject) return;
          if (!event.active && simulation) simulation.alphaTarget(0);
          event.subject.fx = null;
          event.subject.fy = null;
        })
    );

    if (searchInput) {
      searchInput.addEventListener('input', (e) => {
        handleSearch(e.target.value.trim());
      });

      searchInput.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
          clearSearch();
        } else if (e.key === 'Enter') {
          const first = searchResultsEl ? searchResultsEl.querySelector('.search-item') : null;
          if (first) first.click();
        }
      });
    }

    if (searchClearBtn) searchClearBtn.addEventListener('click', clearSearch);

    if (closeInspectorBtn) closeInspectorBtn.addEventListener('click', hideInspector);
    if (focusConstellationBtn) {
      focusConstellationBtn.addEventListener('click', () => {
        if (state.selectedNode) {
          state.isolatedNodeId = state.selectedNode.id;
          state.isIsolated = true;
          focusConstellationBtn.classList.add('hidden');
          if (clearFocusBtn) clearFocusBtn.classList.remove('hidden');
        }
      });
    }

    if (clearFocusBtn) {
      clearFocusBtn.addEventListener('click', () => {
        state.isolatedNodeId = null;
        state.isIsolated = false;
        clearFocusBtn.classList.add('hidden');
        if (focusConstellationBtn) focusConstellationBtn.classList.remove('hidden');
      });
    }

    if (copyShaBtn) {
      copyShaBtn.addEventListener('click', () => {
        if (state.selectedNode && state.selectedNode.sha256Full) {
          navigator.clipboard.writeText(state.selectedNode.sha256Full);
          copyShaBtn.textContent = '✓';
          setTimeout(() => { copyShaBtn.textContent = '⧉'; }, 2000);
        }
      });
    }

    document.querySelectorAll('.insp-tab-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.insp-tab-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.insp-tab-content').forEach(c => c.classList.remove('active'));
        btn.classList.add('active');
        const content = document.getElementById(btn.dataset.tab);
        if (content) content.classList.add('active');
      });
    });

    if (toggleSettingsBtn) {
      toggleSettingsBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        toggleSettings();
      });
    }

    if (closeSettingsBtn) {
      closeSettingsBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        hideSettings();
      });
    }

    document.addEventListener('click', (e) => {
      if (!settingsDrawer || settingsDrawer.classList.contains('hidden')) return;
      const path = e.composedPath ? e.composedPath() : [];
      if (path.includes(settingsDrawer) || (toggleSettingsBtn && path.includes(toggleSettingsBtn))) {
        return;
      }
      if (settingsDrawer.contains(e.target) || (toggleSettingsBtn && toggleSettingsBtn.contains(e.target))) {
        return;
      }
      hideSettings();
    });

    const sliderCharge = document.getElementById('slider-charge');
    if (sliderCharge) {
      sliderCharge.addEventListener('input', (e) => {
        state.physics.charge = +e.target.value;
        const valEl = document.getElementById('val-charge');
        if (valEl) valEl.textContent = e.target.value;
        if (simulation) {
          simulation.force('charge').strength(state.physics.charge);
          simulation.alpha(0.3).restart();
        }
      });
    }

    const sliderLinkDist = document.getElementById('slider-link-dist');
    if (sliderLinkDist) {
      sliderLinkDist.addEventListener('input', (e) => {
        state.physics.linkDistance = +e.target.value;
        const valEl = document.getElementById('val-link-dist');
        if (valEl) valEl.textContent = e.target.value;
        if (simulation) {
          simulation.force('link').distance(state.physics.linkDistance);
          simulation.alpha(0.3).restart();
        }
      });
    }

    const sliderCollision = document.getElementById('slider-collision');
    if (sliderCollision) {
      sliderCollision.addEventListener('input', (e) => {
        state.physics.collision = +e.target.value;
        const valEl = document.getElementById('val-collision');
        if (valEl) valEl.textContent = e.target.value;
        if (simulation) {
          simulation.force('collide').radius(d => (d.importance * 3) + state.physics.collision);
          simulation.alpha(0.3).restart();
        }
      });
    }

    const sliderGravity = document.getElementById('slider-gravity');
    if (sliderGravity) {
      sliderGravity.addEventListener('input', (e) => {
        state.physics.gravity = +e.target.value;
        const valEl = document.getElementById('val-gravity');
        if (valEl) valEl.textContent = e.target.value;
        if (simulation) {
          simulation.force('x').strength(state.physics.gravity);
          simulation.force('y').strength(state.physics.gravity);
          simulation.alpha(0.3).restart();
        }
      });
    }

    const sliderPhotonSpeed = document.getElementById('slider-photon-speed');
    if (sliderPhotonSpeed) {
      sliderPhotonSpeed.addEventListener('input', (e) => {
        state.physics.photonSpeed = +e.target.value;
        const valEl = document.getElementById('val-photon-speed');
        if (valEl) valEl.textContent = `${e.target.value}x`;
      });
    }

    const togglePhotons = document.getElementById('toggle-photons');
    if (togglePhotons) {
      togglePhotons.addEventListener('change', (e) => {
        state.physics.showPhotons = e.target.checked;
      });
    }

    const toggleNebulas = document.getElementById('toggle-nebulas');
    if (toggleNebulas) {
      toggleNebulas.addEventListener('change', (e) => {
        state.physics.showNebulas = e.target.checked;
      });
    }

    const resetPhysicsBtn = document.getElementById('reset-physics-btn');
    if (resetPhysicsBtn) resetPhysicsBtn.addEventListener('click', resetPhysics);

    const reheatSimBtn = document.getElementById('reheat-sim-btn');
    if (reheatSimBtn) {
      reheatSimBtn.addEventListener('click', () => {
        if (simulation) simulation.alpha(0.8).restart();
      });
    }

    const resetCamBtn = document.getElementById('reset-cam-btn');
    if (resetCamBtn) resetCamBtn.addEventListener('click', centerCamera);

    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        hideComparisonModal();
        hideInspector();
        hideSettings();
        clearSearch();
      }
    });
  }

  /**
   * Opens the settings and physics controls drawer.
   */
  function openSettings() {
    if (!settingsDrawer) return;
    settingsDrawer.classList.remove('hidden');
    settingsDrawer.classList.add('open');
    if (toggleSettingsBtn) toggleSettingsBtn.classList.add('active');
    hideInspector();
  }

  /**
   * Closes the settings and physics controls drawer.
   */
  function hideSettings() {
    if (!settingsDrawer) return;
    settingsDrawer.classList.add('hidden');
    settingsDrawer.classList.remove('open');
    if (toggleSettingsBtn) toggleSettingsBtn.classList.remove('active');
  }

  /**
   * Toggles visibility state of the settings and controls drawer.
   */
  function toggleSettings() {
    if (!settingsDrawer) return;
    if (settingsDrawer.classList.contains('hidden')) {
      openSettings();
    } else {
      hideSettings();
    }
  }

  /**
   * Initializes theme preference from localStorage with Event Horizon default fallback.
   */
  function initTheme() {
    let savedTheme = 'event-horizon';
    try {
      savedTheme = localStorage.getItem('roo4u_theme') || 'event-horizon';
    } catch (e) {}
    if (!THEMES[savedTheme]) savedTheme = 'event-horizon';
    setTheme(savedTheme);
  }

  /**
   * Sets current active theme palette and updates CSS custom properties.
   *
   * @param {string} themeKey Theme configuration key ('event-horizon', 'accretion-disk', 'quantum-void').
   */
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

  /**
   * Restores default physics simulation parameters and restarts simulation.
   */
  function resetPhysics() {
    state.physics = {
      charge: -480,
      linkDistance: 85,
      collision: 16,
      gravity: 0.055,
      photonSpeed: 1.0,
      showPhotons: true,
      showNebulas: true
    };
    const sliderCharge = document.getElementById('slider-charge');
    if (sliderCharge) sliderCharge.value = -480;
    const valCharge = document.getElementById('val-charge');
    if (valCharge) valCharge.textContent = -480;

    const sliderLinkDist = document.getElementById('slider-link-dist');
    if (sliderLinkDist) sliderLinkDist.value = 85;
    const valLinkDist = document.getElementById('val-link-dist');
    if (valLinkDist) valLinkDist.textContent = 85;

    const sliderCollision = document.getElementById('slider-collision');
    if (sliderCollision) sliderCollision.value = 16;
    const valCollision = document.getElementById('val-collision');
    if (valCollision) valCollision.textContent = 16;

    const sliderGravity = document.getElementById('slider-gravity');
    if (sliderGravity) sliderGravity.value = 0.055;
    const valGravity = document.getElementById('val-gravity');
    if (valGravity) valGravity.textContent = 0.055;

    const sliderPhotonSpeed = document.getElementById('slider-photon-speed');
    if (sliderPhotonSpeed) sliderPhotonSpeed.value = 1;
    const valPhotonSpeed = document.getElementById('val-photon-speed');
    if (valPhotonSpeed) valPhotonSpeed.textContent = '1.0x';

    const togglePhotons = document.getElementById('toggle-photons');
    if (togglePhotons) togglePhotons.checked = true;
    const toggleNebulas = document.getElementById('toggle-nebulas');
    if (toggleNebulas) toggleNebulas.checked = true;

    initSimulation();
  }

  /**
   * Displays node summary tooltip at specified cursor coordinates.
   *
   * @param {Object} node Target node data object.
   * @param {number} x Screen cursor X position in pixels.
   * @param {number} y Screen cursor Y position in pixels.
   */
  function showTooltip(node, x, y) {
    if (!tooltipEl) return;
    const ttCategory = document.getElementById('tt-category');
    if (ttCategory) {
      ttCategory.textContent = node.categoryName;
      ttCategory.style.backgroundColor = hexToRgba(node.color, 0.2);
      ttCategory.style.color = node.color;
    }
    const ttLang = document.getElementById('tt-lang');
    if (ttLang) ttLang.textContent = node.language;
    const ttTitle = document.getElementById('tt-title');
    if (ttTitle) ttTitle.textContent = node.label;
    const ttPath = document.getElementById('tt-path');
    if (ttPath) ttPath.textContent = node.path;
    const ttSummary = document.getElementById('tt-summary');
    if (ttSummary) ttSummary.textContent = node.summary;
    const ttLoc = document.getElementById('tt-loc');
    if (ttLoc) ttLoc.textContent = node.loc;

    const linksCount = currentGraph.links.filter(l => {
      const sId = typeof l.source === 'object' ? l.source.id : l.source;
      const tId = typeof l.target === 'object' ? l.target.id : l.target;
      return sId === node.id || tId === node.id;
    }).length;
    const ttDegree = document.getElementById('tt-degree');
    if (ttDegree) ttDegree.textContent = linksCount;

    tooltipEl.style.left = `${x}px`;
    tooltipEl.style.top = `${y}px`;
    tooltipEl.classList.remove('hidden');
  }

  /**
   * Moves tooltip overlay to follow current cursor coordinates.
   *
   * @param {number} x Screen cursor X position in pixels.
   * @param {number} y Screen cursor Y position in pixels.
   */
  function moveTooltip(x, y) {
    if (!tooltipEl) return;
    tooltipEl.style.left = `${x}px`;
    tooltipEl.style.top = `${y}px`;
  }

  /**
   * Hides hover tooltip overlay.
   */
  function hideTooltip() {
    if (tooltipEl) tooltipEl.classList.add('hidden');
  }

  /**
   * Selects target node, opens right inspector drawer, and centers camera.
   *
   * @param {Object} node Target node data object.
   */
  function selectNode(node) {
    state.selectedNode = node;
    hideSettings();
    showInspector(node);
    panToNode(node);
  }

  /**
   * Populates and displays inspector drawer for selected star node.
   *
   * @param {Object} node Target node data object.
   */
  function showInspector(node) {
    if (!inspectorDrawer) return;

    const inspCategory = document.getElementById('insp-category');
    if (inspCategory) {
      inspCategory.textContent = node.categoryName;
      inspCategory.style.backgroundColor = hexToRgba(node.color, 0.2);
      inspCategory.style.color = node.color;
    }
    const inspName = document.getElementById('insp-name');
    if (inspName) inspName.textContent = node.label;
    const inspPath = document.getElementById('insp-path');
    if (inspPath) inspPath.textContent = node.path;
    const inspSummary = document.getElementById('insp-summary');
    if (inspSummary) inspSummary.textContent = node.summary;
    const inspMetaLang = document.getElementById('insp-meta-lang');
    if (inspMetaLang) inspMetaLang.textContent = node.language;
    const inspMetaLoc = document.getElementById('insp-meta-loc');
    if (inspMetaLoc) inspMetaLoc.textContent = `${node.loc} LOC`;
    const inspMetaSize = document.getElementById('insp-meta-size');
    if (inspMetaSize) inspMetaSize.textContent = `${(node.size / 1024).toFixed(1)} KB`;
    const inspMetaLayer = document.getElementById('insp-meta-layer');
    if (inspMetaLayer) inspMetaLayer.textContent = `Layer ${node.layer} (${node.categoryName})`;

    const inspMetaSha = document.getElementById('insp-meta-sha');
    if (inspMetaSha) {
      inspMetaSha.innerHTML = `${node.sha256} <button class="copy-sha-btn sha-copy-btn" id="insp-sha-copy" title="Copy SHA256">⧉</button>`;
      const copyBtn = document.getElementById('insp-sha-copy');
      if (copyBtn) {
        copyBtn.addEventListener('click', () => {
          if (node.sha256Full) {
            navigator.clipboard.writeText(node.sha256Full);
            copyBtn.textContent = '✓';
            setTimeout(() => { copyBtn.textContent = '⧉'; }, 2000);
          }
        });
      }
    }

    const inbound = [];
    const outbound = [];

    currentGraph.links.forEach(l => {
      const sId = typeof l.source === 'object' ? l.source.id : l.source;
      const tId = typeof l.target === 'object' ? l.target.id : l.target;

      if (tId === node.id) {
        inbound.push({ id: sId, label: getBasename(sId), type: l.label || l.type });
      }
      if (sId === node.id) {
        outbound.push({ id: tId, label: getBasename(tId), type: l.label || l.type });
      }
    });

    const depsCountEl = document.getElementById('insp-deps-count');
    if (depsCountEl) depsCountEl.textContent = inbound.length + outbound.length;
    renderDepList('insp-inbound-list', inbound);
    renderDepList('insp-outbound-list', outbound);

    const symbolsListEl = document.getElementById('insp-symbols-list');
    if (symbolsListEl) {
      symbolsListEl.innerHTML = '';
      const symsCountEl = document.getElementById('insp-syms-count');
      if (symsCountEl) symsCountEl.textContent = (node.symbols || []).length;
      if (node.symbols && node.symbols.length > 0) {
        node.symbols.forEach(sym => {
          const li = document.createElement('li');
          li.className = 'symbol-item';
          li.textContent = sym;
          symbolsListEl.appendChild(li);
        });
      } else {
        symbolsListEl.innerHTML = '<li class="symbol-item" style="color:var(--text-dim);">No explicit exported AST symbols found.</li>';
      }
    }

    const codeFilename = document.getElementById('code-preview-filename');
    if (codeFilename) codeFilename.textContent = node.label;
    const codeContent = document.getElementById('insp-code-content');
    if (codeContent) codeContent.textContent = node.preview || '[Empty Content]';

    if (focusConstellationBtn && clearFocusBtn) {
      if (state.isolatedNodeId === node.id) {
        focusConstellationBtn.classList.add('hidden');
        clearFocusBtn.classList.remove('hidden');
      } else {
        focusConstellationBtn.classList.remove('hidden');
        clearFocusBtn.classList.add('hidden');
      }
    }

    inspectorDrawer.classList.remove('hidden');
    inspectorDrawer.classList.add('open');
  }

  /**
   * Closes the right inspector drawer.
   */
  function hideInspector() {
    if (!inspectorDrawer) return;
    inspectorDrawer.classList.add('hidden');
    inspectorDrawer.classList.remove('open');
  }

  /**
   * Renders dependency star items inside the inspector list container.
   *
   * @param {string} elementId DOM element ID of target list.
   * @param {Array<{ id: string, label: string, type: string }>} items Dependency list items.
   */
  function renderDepList(elementId, items) {
    const el = document.getElementById(elementId);
    if (!el) return;
    el.innerHTML = '';
    if (items.length === 0) {
      el.innerHTML = '<li class="dep-item" style="color:var(--text-dim);">None</li>';
      return;
    }

    items.forEach(item => {
      const li = document.createElement('li');
      li.className = 'dep-item';
      li.innerHTML = `
        <span>${item.label}</span>
        <span class="dep-type-badge">${item.type}</span>
      `;
      li.addEventListener('click', () => {
        const targetNode = currentGraph.nodes.find(n => n.id === item.id);
        if (targetNode) {
          selectNode(targetNode);
        }
      });
      el.appendChild(li);
    });
  }

  let searchIndex = [];

  /**
   * Builds searchable index from array of graph node metadata objects.
   *
   * @param {Array<Object>} nodes Node metadata array.
   */
  function buildSearchIndex(nodes) {
    searchIndex = nodes.map(n => ({
      id: n.id,
      label: n.label,
      path: n.path,
      categoryName: n.categoryName,
      color: n.color,
      symbols: n.symbols || [],
      summary: n.summary || '',
      node: n
    }));
  }

  /**
   * Executes substring search against indexed node attributes and updates dropdown results.
   *
   * @param {string} query Search input query string.
   */
  function handleSearch(query) {
    state.searchQuery = query;
    if (!searchResultsEl) return;
    if (!query) {
      searchResultsEl.classList.add('hidden');
      if (searchClearBtn) searchClearBtn.classList.add('hidden');
      return;
    }

    if (searchClearBtn) searchClearBtn.classList.remove('hidden');
    const qLower = query.toLowerCase();

    const matches = searchIndex.filter(item => {
      return item.label.toLowerCase().includes(qLower) ||
             item.path.toLowerCase().includes(qLower) ||
             item.categoryName.toLowerCase().includes(qLower) ||
             item.symbols.some(s => s.toLowerCase().includes(qLower));
    }).slice(0, 8);

    if (matches.length === 0) {
      searchResultsEl.innerHTML = '<div class="search-item" style="color:var(--text-dim);">No stellar matches found</div>';
      searchResultsEl.classList.remove('hidden');
      return;
    }

    searchResultsEl.innerHTML = '';
    matches.forEach(m => {
      const div = document.createElement('div');
      div.className = 'search-item search-result-item';
      div.innerHTML = `
        <div class="search-item-top">
          <span class="search-item-title">${escapeHtml(m.label)}</span>
          <span class="search-item-cat" style="background:${hexToRgba(m.color, 0.2)};color:${m.color}">${escapeHtml(m.categoryName)}</span>
        </div>
        <div class="search-item-path">${escapeHtml(m.path)}</div>
      `;
      div.addEventListener('click', () => {
        selectNode(m.node);
        clearSearch();
        hideSettings();
      });
      searchResultsEl.appendChild(div);
    });
    searchResultsEl.classList.remove('hidden');
  }

  /**
   * Clears search input and hides dropdown results.
   */
  function clearSearch() {
    if (searchInput) searchInput.value = '';
    if (searchResultsEl) searchResultsEl.classList.add('hidden');
    if (searchClearBtn) searchClearBtn.classList.add('hidden');
  }

  /**
   * Escapes HTML special characters for safe template insertion.
   *
   * @param {string} str Input raw string.
   * @returns {string} Sanitized string.
   */
  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  /**
   * Smoothly pans and zooms camera to center on target 3D node with depth compensation.
   *
   * @param {Object} node Target node data object.
   * @param {number} [targetZoom=1.6] Target zoom level.
   * @param {number} [duration=750] Animation transition duration in ms.
   */
  function panToNode(node, targetZoom = 1.6, duration = 750) {
    if (!node || node.x === undefined || node.y === undefined) return;
    const width = window.innerWidth;
    const height = window.innerHeight - getHeaderHeight();
    const k = targetZoom;
    const z = node.z !== undefined ? node.z : 0;

    const { tx, ty } = getPanToCenter(node.x, node.y, z, width, height, k);
    const targetTransform = d3.zoomIdentity.translate(tx, ty).scale(k);

    d3.select(graphCanvas)
      .transition()
      .duration(duration)
      .ease(d3.easeCubicOut)
      .call(zoomBehavior.transform, targetTransform);
  }

  /**
   * Frames a cluster or constellation within the viewport in 3D perspective.
   *
   * @param {Array<Object>} nodes Array of node objects to frame.
   * @param {number} [duration=800] Animation transition duration in ms.
   */
  function focusCluster(nodes, duration = 800) {
    if (!nodes || nodes.length === 0) return;
    const width = window.innerWidth;
    const height = window.innerHeight - getHeaderHeight();

    let minX = Infinity, maxX = -Infinity;
    let minY = Infinity, maxY = -Infinity;
    let sumZ = 0;
    let count = 0;

    nodes.forEach(n => {
      if (n.x === undefined || n.y === undefined || isNaN(n.x) || isNaN(n.y)) return;
      if (n.x < minX) minX = n.x;
      if (n.x > maxX) maxX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.y > maxY) maxY = n.y;
      sumZ += (n.z !== undefined ? n.z : 0);
      count++;
    });

    if (count === 0 || !isFinite(minX) || !isFinite(maxX)) return;

    const bboxCenterX = (minX + maxX) / 2;
    const bboxCenterY = (minY + maxY) / 2;
    const avgZ = sumZ / count;

    const spanX = Math.max(maxX - minX + 120, 200);
    const spanY = Math.max(maxY - minY + 120, 200);

    const fitK = Math.min((width * 0.85) / spanX, (height * 0.85) / spanY);
    const k = Math.max(0.15, Math.min(2.5, fitK));

    const { tx, ty } = getPanToCenter(bboxCenterX, bboxCenterY, avgZ, width, height, k);
    const targetTransform = d3.zoomIdentity.translate(tx, ty).scale(k);

    if (duration > 0) {
      d3.select(graphCanvas)
        .transition()
        .duration(duration)
        .ease(d3.easeCubicOut)
        .call(zoomBehavior.transform, targetTransform);
    } else {
      d3.select(graphCanvas).call(zoomBehavior.transform, targetTransform);
      state.zoomTransform = targetTransform;
      updateZoomIndicator();
    }
  }

  /**
   * Auto-fits visible nodes within viewport bounds.
   *
   * @param {number} [duration=650] Animation transition duration in ms.
   */
  function fitToViewport(duration = 650) {
    const visibleNodes = currentGraph.nodes.filter(n => n.x !== undefined && n.y !== undefined && !isNaN(n.x) && !isNaN(n.y));
    if (visibleNodes.length === 0) {
      const t = d3.zoomIdentity.translate(0, 0).scale(1.0);
      d3.select(graphCanvas).call(zoomBehavior.transform, t);
      state.zoomTransform = t;
      updateZoomIndicator();
      return;
    }
    focusCluster(visibleNodes, duration);
  }

  /**
   * Centers camera on all visible nodes with smooth transition.
   */
  function centerCamera() {
    state.userHasPannedOrZoomed = false;
    fitToViewport(650);
  }

  /**
   * Updates zoom indicator percentage display in UI.
   */
  function updateZoomIndicator() {
    const indicator = document.getElementById('zoom-indicator');
    if (indicator) {
      const pct = Math.round(state.zoomTransform.k * 100);
      indicator.textContent = `${pct}%`;
    }
  }

  /**
   * Updates HUD statistics counters and pass verification badges.
   *
   * @param {Object} stats Branch statistics payload.
   */
  function updateHUDStats(stats) {
    const statNodes = document.getElementById('stat-nodes');
    if (statNodes) statNodes.textContent = stats.totalFiles;
    const statLinks = document.getElementById('stat-links');
    if (statLinks) statLinks.textContent = stats.linksCount;
    const statLoc = document.getElementById('stat-loc');
    if (statLoc) statLoc.textContent = stats.totalLoc.toLocaleString();
    const statClusters = document.getElementById('stat-clusters');
    if (statClusters) statClusters.textContent = stats.clustersCount;
    const hudCertText = document.getElementById('hud-cert-text');
    if (hudCertText) hudCertText.textContent = stats.certStatus;
    const hudBranchTag = document.getElementById('hud-branch-tag');
    if (hudBranchTag) hudBranchTag.textContent = `${state.currentBranch.toUpperCase()} BRANCH`;
  }

  /**
   * Rebuilds sector filter chips for active branch clusters.
   *
   * @param {Array<Object>} clusters Cluster metadata array.
   */
  function updateCategoryChips(clusters) {
    if (!categoryChipsContainer) return;
    categoryChipsContainer.innerHTML = '';
    clusters.forEach(c => {
      const chip = document.createElement('div');
      const isActive = state.activeCategoryFilters.size === 0 || state.activeCategoryFilters.has(c.id);
      chip.className = `category-chip ${isActive ? 'active' : ''}`;
      chip.style.setProperty('--chip-color', c.color);
      chip.innerHTML = `
        <span class="chip-dot"></span>
        <span>${c.name}</span>
        <span class="chip-count">(${c.nodeCount})</span>
      `;

      chip.addEventListener('click', () => {
        if (state.activeCategoryFilters.has(c.id)) {
          state.activeCategoryFilters.delete(c.id);
        } else {
          state.activeCategoryFilters.add(c.id);
        }
        loadBranch(state.currentBranch);
      });

      categoryChipsContainer.appendChild(chip);
    });
  }

  /**
   * Updates active state and ARIA attributes on branch navigation tabs.
   *
   * @param {string} branchName Active branch name.
   */
  function updateBranchUI(branchName) {
    document.querySelectorAll('.branch-tab').forEach(t => {
      t.classList.remove('active');
      t.setAttribute('aria-selected', 'false');
    });

    const activeTab = document.getElementById(`tab-${branchName}`);
    if (activeTab) {
      activeTab.classList.add('active');
      activeTab.setAttribute('aria-selected', 'true');
    }
  }

  /**
   * Initializes architectural shift comparison modal tables and component cards.
   */
  function setupComparisonModal() {
    const comp = graphData.comparison;
    if (!comp) return;

    const tbody = document.getElementById('compare-metrics-tbody');
    if (tbody) {
      tbody.innerHTML = '';
      comp.metrics.forEach(m => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td>${m.category}</td>
          <td>${m.python}</td>
          <td>${m.ocaml}</td>
          <td>${m.winner === 'ocaml' ? '✓ Pure Type Invariants' : 'Standard'}</td>
        `;
        tbody.appendChild(tr);
      });
    }

    const grid = document.getElementById('compare-mappings-grid');
    if (grid) {
      grid.innerHTML = '';
      comp.moduleMappings.forEach(map => {
        const card = document.createElement('div');
        card.className = 'mapping-card';
        card.innerHTML = `
          <div class="mapping-paths">
            <span class="mapping-py">${map.pyFile}</span>
            <span class="mapping-arrow">➔</span>
            <span class="mapping-ocaml">${map.ocamlFile}</span>
          </div>
          <div class="mapping-desc">${map.description}</div>
        `;
        grid.appendChild(card);
      });
    }

    if (closeCompareBtn) closeCompareBtn.addEventListener('click', hideComparisonModal);
  }

  /**
   * Opens architectural shift comparison modal.
   */
  function showComparisonModal() {
    if (compareModal) compareModal.classList.remove('hidden');
  }

  /**
   * Closes architectural shift comparison modal.
   */
  function hideComparisonModal() {
    if (compareModal) compareModal.classList.add('hidden');
  }

  /**
   * Converts 3-digit or 6-digit hexadecimal color string into rgba notation.
   *
   * @param {string} hex Hex color string.
   * @param {number} alpha Opacity value in range [0.0, 1.0].
   * @returns {string} Computed CSS rgba string.
   */
  function hexToRgba(hex, alpha) {
    if (!hex || hex[0] !== '#') return `rgba(0, 240, 255, ${alpha})`;
    let r = 0, g = 0, b = 0;
    if (hex.length === 4) {
      r = parseInt(hex[1] + hex[1], 16);
      g = parseInt(hex[2] + hex[2], 16);
      b = parseInt(hex[3] + hex[3], 16);
    } else if (hex.length === 7) {
      r = parseInt(hex.substring(1, 3), 16);
      g = parseInt(hex.substring(3, 5), 16);
      b = parseInt(hex.substring(5, 7), 16);
    }
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }

  /**
   * Extracts filename basename from file path string safely.
   *
   * @param {string|null|undefined} path File path string.
   * @returns {string} Basename filename component.
   */
  function getBasename(path) {
    const safePath = String(path || '');
    const parts = safePath.split('/');
    return parts[parts.length - 1];
  }

  /**
   * Exposes internal engine state and methods on window object for testing.
   */
  function syncWindowExports() {
    window.state = state;
    window.currentGraph = currentGraph;
    window.graphNodes = currentGraph.nodes;
    window.simulation = simulation;
    window.zoomBehavior = zoomBehavior;
    window.computeNodeZ = computeNodeZ;
    window.project3D = project3D;
    window.projectNode = project3D;
    window.unproject3D = unproject3D;
    window.findNodeAt = findNodeAt;
    window.getNodeAtPosition = getNodeAtPosition;
    window.findClosestNode = findClosestNode;
    window.panToNode = panToNode;
    window.centerCamera = centerCamera;
    window.focusCluster = focusCluster;
    window.fitToViewport = fitToViewport;
    window.loadBranch = loadBranch;
    window.selectNode = selectNode;
    window.openSettings = openSettings;
    window.hideSettings = hideSettings;
    window.toggleSettings = toggleSettings;
    window.THEMES = THEMES;
    window.setTheme = setTheme;
    window.showComparisonModal = showComparisonModal;
    window.hideComparisonModal = hideComparisonModal;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
