/**
 * app.js - Interactive Constellation Force-Directed Network Graph Engine
 * Roo4u Architecture Visualizer for GitHub Pages
 */

(function () {
  'use strict';

  // --- Configuration & State ---
  const state = {
    currentBranch: 'main',
    activeLayout: 'cosmic',
    includeSwarm: true,
    activeCategoryFilters: new Set(),
    searchQuery: '',
    selectedNode: null,
    hoveredNode: null,
    isolatedNodeId: null,
    zoomTransform: d3.zoomIdentity,
    physics: {
      charge: -350,
      linkDistance: 90,
      collision: 18,
      gravity: 0.08,
      photonSpeed: 1.0,
      showPhotons: true,
      showNebulas: true
    },
    photons: [],
    starfield: []
  };

  let graphData = null;
  let currentGraph = { nodes: [], links: [], clusters: [] };
  let simulation = null;
  let animFrameId = null;

  // DOM Elements
  const starfieldCanvas = document.getElementById('starfield-canvas');
  const starfieldCtx = starfieldCanvas.getContext('2d');
  const graphCanvas = document.getElementById('graph-canvas');
  const graphCtx = graphCanvas.getContext('2d');
  const minimapCanvas = document.getElementById('minimap-canvas');
  const minimapCtx = minimapCanvas.getContext('2d');

  const tooltipEl = document.getElementById('graph-tooltip');
  const searchInput = document.getElementById('node-search');
  const searchResultsEl = document.getElementById('search-results');
  const searchClearBtn = document.getElementById('search-clear');
  const layoutSelect = document.getElementById('layout-mode');
  const toggleSwarmCheckbox = document.getElementById('toggle-swarm');
  const categoryChipsContainer = document.getElementById('category-chips');

  // Inspector Elements
  const inspectorDrawer = document.getElementById('inspector-drawer');
  const closeInspectorBtn = document.getElementById('close-inspector-btn');
  const focusConstellationBtn = document.getElementById('focus-constellation-btn');
  const clearFocusBtn = document.getElementById('clear-focus-btn');
  const copyShaBtn = document.getElementById('copy-sha-btn');

  // Physics Drawer
  const physicsPanel = document.getElementById('physics-panel');
  const toggleControlsBtn = document.getElementById('toggle-controls-btn');
  const closePhysicsBtn = document.getElementById('close-physics-btn');

  // Comparison Modal
  const compareModal = document.getElementById('compare-modal');
  const closeCompareBtn = document.getElementById('close-compare-btn');

  // --- D3 Zoom Setup ---
  const zoomBehavior = d3.zoom()
    .scaleExtent([0.15, 4.0])
    .on('zoom', (event) => {
      state.zoomTransform = event.transform;
      updateZoomIndicator();
    });

  d3.select(graphCanvas).call(zoomBehavior);

  // --- Initialization ---
  function init() {
    if (!window.ROO4U_GRAPH_DATA) {
      console.error('ROO4U_GRAPH_DATA not found.');
      return;
    }
    graphData = window.ROO4U_GRAPH_DATA;

    resizeCanvases();
    window.addEventListener('resize', () => {
      resizeCanvases();
      initStarfield();
    });

    initStarfield();
    setupEventListeners();
    setupComparisonModal();
    loadBranch(state.currentBranch);
    startRenderLoop();
  }

  function resizeCanvases() {
    const width = window.innerWidth;
    const height = window.innerHeight - 64; // header offset
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
  }

  // --- Starfield Background Generator ---
  function initStarfield() {
    const width = window.innerWidth;
    const height = window.innerHeight;
    const starCount = Math.floor((width * height) / 3200);
    state.starfield = [];

    const colors = ['#ffffff', '#e0f2fe', '#fef08a', '#ede9fe', '#bae6fd'];

    for (let i = 0; i < starCount; i++) {
      state.starfield.push({
        x: Math.random() * width,
        y: Math.random() * height,
        radius: Math.random() * 1.5 + 0.3,
        color: colors[Math.floor(Math.random() * colors.length)],
        alpha: Math.random() * 0.7 + 0.2,
        twinkleSpeed: Math.random() * 0.03 + 0.005,
        twinklePhase: Math.random() * Math.PI * 2
      });
    }
  }

  function renderStarfield() {
    const width = window.innerWidth;
    const height = window.innerHeight - 64;
    starfieldCtx.clearRect(0, 0, width, height);

    // Deep space gradient backdrop
    const grad = starfieldCtx.createRadialGradient(
      width * 0.5, height * 0.5, width * 0.1,
      width * 0.5, height * 0.5, width * 0.8
    );
    grad.addColorStop(0, '#0a0f24');
    grad.addColorStop(0.5, '#060814');
    grad.addColorStop(1, '#020308');
    starfieldCtx.fillStyle = grad;
    starfieldCtx.fillRect(0, 0, width, height);

    // Render twinkling stars with parallax
    const px = state.zoomTransform.x * 0.08;
    const py = state.zoomTransform.y * 0.08;

    state.starfield.forEach(star => {
      star.twinklePhase += star.twinkleSpeed;
      const currentAlpha = star.alpha * (0.6 + 0.4 * Math.sin(star.twinklePhase));

      let sx = (star.x + px) % width;
      let sy = (star.y + py) % height;
      if (sx < 0) sx += width;
      if (sy < 0) sy += height;

      starfieldCtx.beginPath();
      starfieldCtx.arc(sx, sy, star.radius, 0, Math.PI * 2);
      starfieldCtx.fillStyle = star.color;
      starfieldCtx.globalAlpha = currentAlpha;
      starfieldCtx.fill();
    });
    starfieldCtx.globalAlpha = 1.0;
  }

  // --- Branch & Graph Data Loading ---
  function loadBranch(branchName) {
    state.currentBranch = branchName;
    const rawBranch = graphData.branches[branchName];
    if (!rawBranch) return;

    // Filter nodes by swarm setting
    let filteredNodes = rawBranch.nodes.filter(n => state.includeSwarm || !n.isSwarm);

    // Filter nodes by active categories if any are selected
    if (state.activeCategoryFilters.size > 0) {
      filteredNodes = filteredNodes.filter(n => state.activeCategoryFilters.has(n.category));
    }

    const nodeIds = new Set(filteredNodes.map(n => n.id));
    const filteredLinks = rawBranch.links.filter(l => {
      const srcId = typeof l.source === 'object' ? l.source.id : l.source;
      const tgtId = typeof l.target === 'object' ? l.target.id : l.target;
      return nodeIds.has(srcId) && nodeIds.has(tgtId);
    });

    // Clone data for D3-force mutation
    const nodes = filteredNodes.map(n => ({ ...n }));
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

    initPhotons(links);
    updateHUDStats(rawBranch.stats);
    updateCategoryChips(rawBranch.clusters);
    buildSearchIndex(rawBranch.nodes);
    updateBranchUI(branchName);

    // Reset selection / isolation
    state.selectedNode = null;
    state.hoveredNode = null;
    state.isolatedNodeId = null;
    hideInspector();
    hideTooltip();

    initSimulation();
    centerCamera();
  }

  // --- Particle Photons (Animated Stardust along Links) ---
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

  // --- D3-Force Physics Simulation ---
  function initSimulation() {
    if (simulation) simulation.stop();

    const width = window.innerWidth;
    const height = window.innerHeight - 64;

    simulation = d3.forceSimulation(currentGraph.nodes)
      .force('link', d3.forceLink(currentGraph.links).id(d => d.id).distance(state.physics.linkDistance).strength(0.6))
      .force('charge', d3.forceManyBody().strength(state.physics.charge))
      .force('collide', d3.forceCollide().radius(d => (d.importance * 3) + state.physics.collision).iterations(2))
      .force('center', d3.forceCenter(width / 2, height / 2))
      .force('x', d3.forceX(width / 2).strength(state.physics.gravity))
      .force('y', d3.forceY(height / 2).strength(state.physics.gravity))
      .alphaDecay(0.025)
      .on('tick', () => {
        // Animation handled in requestAnimationFrame loop
      });

    applyLayoutPositions(state.activeLayout);
  }

  function applyLayoutPositions(layout) {
    state.activeLayout = layout;
    const width = window.innerWidth;
    const height = window.innerHeight - 64;
    const cx = width / 2;
    const cy = height / 2;

    if (!simulation) return;

    if (layout === 'cosmic') {
      simulation.force('x', d3.forceX(cx).strength(state.physics.gravity));
      simulation.force('y', d3.forceY(cy).strength(state.physics.gravity));
      simulation.force('charge').strength(state.physics.charge);
    } else if (layout === 'concentric') {
      // Concentric orbital rings by layer (Layer 1 in center -> Layer 6 outer)
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
      simulation.force('charge').strength(-200);
    } else if (layout === 'layered') {
      // Hierarchical layered architecture Left to Right
      simulation.force('x', d3.forceX(d => {
        return (d.layer - 3.5) * 220 + cx;
      }).strength(0.4));
      simulation.force('y', d3.forceY(cy).strength(0.05));
      simulation.force('charge').strength(-180);
    } else if (layout === 'clusters') {
      // Sector cluster islands
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
      simulation.force('charge').strength(-150);
    }

    simulation.alpha(0.6).restart();
  }

  // --- Main Animation & Render Loop ---
  function startRenderLoop() {
    function frame() {
      renderStarfield();
      renderGraph();
      renderMinimap();
      animFrameId = requestAnimationFrame(frame);
    }
    animFrameId = requestAnimationFrame(frame);
  }

  function renderGraph() {
    const width = window.innerWidth;
    const height = window.innerHeight - 64;
    graphCtx.clearRect(0, 0, width, height);

    graphCtx.save();
    graphCtx.translate(state.zoomTransform.x, state.zoomTransform.y);
    graphCtx.scale(state.zoomTransform.k, state.zoomTransform.k);

    const activeNode = state.hoveredNode || state.selectedNode;
    let connectedNodeIds = null;
    if (activeNode) {
      connectedNodeIds = getConnectedNodeIds(activeNode.id);
    } else if (state.isolatedNodeId) {
      connectedNodeIds = getConnectedNodeIds(state.isolatedNodeId);
    }

    // 1. Render Cluster Nebulas (if enabled)
    if (state.physics.showNebulas && state.activeLayout !== 'layered') {
      renderClusterNebulas();
    }

    // 2. Render Constellation Links / Filaments
    renderLinks(connectedNodeIds);

    // 3. Render Flowing Photons
    if (state.physics.showPhotons) {
      renderPhotons(connectedNodeIds);
    }

    // 4. Render Stellar Nodes
    renderNodes(connectedNodeIds);

    // 5. Render Labels
    renderLabels(connectedNodeIds);

    graphCtx.restore();
  }

  // --- Cluster Nebula Glows ---
  function renderClusterNebulas() {
    const clusterMap = {};
    currentGraph.nodes.forEach(n => {
      if (!n.x || !n.y) return;
      if (!clusterMap[n.category]) {
        clusterMap[n.category] = { color: n.color, points: [], sumX: 0, sumY: 0 };
      }
      clusterMap[n.category].points.push(n);
      clusterMap[n.category].sumX += n.x;
      clusterMap[n.category].sumY += n.y;
    });

    Object.keys(clusterMap).forEach(cat => {
      const c = clusterMap[cat];
      if (c.points.length < 2) return;
      const cx = c.sumX / c.points.length;
      const cy = c.sumY / c.points.length;

      // Estimate cluster radius
      let maxDist = 40;
      c.points.forEach(p => {
        const d = Math.hypot(p.x - cx, p.y - cy);
        if (d > maxDist) maxDist = d;
      });

      const radius = maxDist + 60;
      const grad = graphCtx.createRadialGradient(cx, cy, 10, cx, cy, radius);
      grad.addColorStop(0, hexToRgba(c.color, 0.14));
      grad.addColorStop(0.6, hexToRgba(c.color, 0.04));
      grad.addColorStop(1, 'rgba(0,0,0,0)');

      graphCtx.beginPath();
      graphCtx.arc(cx, cy, radius, 0, Math.PI * 2);
      graphCtx.fillStyle = grad;
      graphCtx.fill();
    });
  }

  // --- Links Rendering ---
  function renderLinks(connectedNodeIds) {
    currentGraph.links.forEach(l => {
      const s = l.source;
      const t = l.target;
      if (!s.x || !s.y || !t.x || !t.y) return;

      const isConnected = connectedNodeIds && connectedNodeIds.has(s.id) && connectedNodeIds.has(t.id);
      const isDimmed = connectedNodeIds && !isConnected;

      graphCtx.beginPath();
      graphCtx.moveTo(s.x, s.y);
      graphCtx.lineTo(t.x, t.y);

      if (isConnected) {
        // Glowing highlighted filament
        graphCtx.strokeStyle = 'rgba(0, 240, 255, 0.9)';
        graphCtx.lineWidth = 2.4;
        graphCtx.shadowColor = '#00f0ff';
        graphCtx.shadowBlur = 10;
      } else if (isDimmed) {
        graphCtx.strokeStyle = 'rgba(255, 255, 255, 0.03)';
        graphCtx.lineWidth = 0.6;
        graphCtx.shadowBlur = 0;
      } else {
        // Normal filament
        graphCtx.strokeStyle = 'rgba(148, 163, 184, 0.22)';
        graphCtx.lineWidth = 1.0;
        graphCtx.shadowBlur = 0;
      }

      graphCtx.stroke();
      graphCtx.shadowBlur = 0; // reset shadow
    });
  }

  // --- Photon Stardust Stream ---
  function renderPhotons(connectedNodeIds) {
    const speedMultiplier = state.physics.photonSpeed;
    if (speedMultiplier <= 0) return;

    state.photons.forEach(p => {
      const s = p.link.source;
      const t = p.link.target;
      if (!s.x || !s.y || !t.x || !t.y) return;

      p.progress += p.speed * speedMultiplier;
      if (p.progress >= 1.0) p.progress = 0;

      const px = s.x + (t.x - s.x) * p.progress;
      const py = s.y + (t.y - s.y) * p.progress;

      const isConnected = connectedNodeIds && connectedNodeIds.has(s.id) && connectedNodeIds.has(t.id);
      const isDimmed = connectedNodeIds && !isConnected;

      graphCtx.beginPath();
      graphCtx.arc(px, py, isConnected ? p.size * 1.5 : p.size, 0, Math.PI * 2);
      graphCtx.fillStyle = isConnected ? '#00f0ff' : (isDimmed ? 'rgba(255,255,255,0.1)' : 'rgba(255,255,255,0.75)');
      if (isConnected) {
        graphCtx.shadowColor = '#00f0ff';
        graphCtx.shadowBlur = 8;
      }
      graphCtx.fill();
      graphCtx.shadowBlur = 0;
    });
  }

  // --- Stellar Nodes Rendering ---
  function renderNodes(connectedNodeIds) {
    currentGraph.nodes.forEach(n => {
      if (!n.x || !n.y) return;

      const isConnected = connectedNodeIds && connectedNodeIds.has(n.id);
      const isDimmed = connectedNodeIds && !isConnected;
      const isSelected = state.selectedNode && state.selectedNode.id === n.id;
      const isHovered = state.hoveredNode && state.hoveredNode.id === n.id;

      const baseRadius = (n.importance * 2.2) + 3.5;
      const radius = isSelected ? baseRadius * 1.6 : (isHovered ? baseRadius * 1.3 : baseRadius);

      // 1. Soft Outer Atmospheric Halo
      const haloRadius = radius * 3.2;
      const haloGrad = graphCtx.createRadialGradient(n.x, n.y, radius * 0.5, n.x, n.y, haloRadius);
      haloGrad.addColorStop(0, hexToRgba(n.color, isConnected ? 0.6 : (isDimmed ? 0.05 : 0.35)));
      haloGrad.addColorStop(1, 'rgba(0,0,0,0)');

      graphCtx.beginPath();
      graphCtx.arc(n.x, n.y, haloRadius, 0, Math.PI * 2);
      graphCtx.fillStyle = haloGrad;
      graphCtx.fill();

      // 2. Pulsing Beacon Ring for Selected Node
      if (isSelected) {
        const time = Date.now() * 0.003;
        const pulseR = radius + 6 + Math.sin(time) * 4;
        graphCtx.beginPath();
        graphCtx.arc(n.x, n.y, pulseR, 0, Math.PI * 2);
        graphCtx.strokeStyle = 'rgba(0, 240, 255, 0.8)';
        graphCtx.lineWidth = 2;
        graphCtx.setLineDash([4, 4]);
        graphCtx.stroke();
        graphCtx.setLineDash([]);
      }

      // 3. Stellar Solid Core
      graphCtx.beginPath();
      graphCtx.arc(n.x, n.y, radius, 0, Math.PI * 2);
      graphCtx.fillStyle = isDimmed ? hexToRgba(n.color, 0.25) : n.color;
      graphCtx.fill();

      // 4. White Center Specular Glow
      if (!isDimmed) {
        graphCtx.beginPath();
        graphCtx.arc(n.x, n.y, radius * 0.45, 0, Math.PI * 2);
        graphCtx.fillStyle = '#ffffff';
        graphCtx.globalAlpha = isConnected ? 0.95 : 0.7;
        graphCtx.fill();
        graphCtx.globalAlpha = 1.0;
      }
    });
  }

  // --- Labels Rendering ---
  function renderLabels(connectedNodeIds) {
    const k = state.zoomTransform.k;
    const showAll = k > 1.3;
    const showImportant = k > 0.55;

    graphCtx.font = '10px Inter, sans-serif';
    graphCtx.textAlign = 'center';
    graphCtx.textBaseline = 'top';

    currentGraph.nodes.forEach(n => {
      if (!n.x || !n.y) return;

      const isConnected = connectedNodeIds && connectedNodeIds.has(n.id);
      const isDimmed = connectedNodeIds && !isConnected;
      const isSelected = state.selectedNode && state.selectedNode.id === n.id;
      const isMajor = n.importance >= 4;

      if (isConnected || isSelected || showAll || (showImportant && isMajor)) {
        const baseRadius = (n.importance * 2.2) + 3.5;
        const labelY = n.y + baseRadius + 4;

        if (isConnected || isSelected) {
          graphCtx.fillStyle = '#ffffff';
          graphCtx.font = 'bold 11px Inter, sans-serif';
          graphCtx.shadowColor = '#000000';
          graphCtx.shadowBlur = 4;
        } else if (isDimmed) {
          graphCtx.fillStyle = 'rgba(148, 163, 184, 0.2)';
          graphCtx.font = '10px Inter, sans-serif';
          graphCtx.shadowBlur = 0;
        } else {
          graphCtx.fillStyle = '#cbd5e1';
          graphCtx.font = '10px Inter, sans-serif';
          graphCtx.shadowBlur = 0;
        }

        graphCtx.fillText(n.label, n.x, labelY);
        graphCtx.shadowBlur = 0;
      }
    });
  }

  // --- Radar Minimap Rendering ---
  function renderMinimap() {
    const w = minimapCanvas.width;
    const h = minimapCanvas.height;
    minimapCtx.clearRect(0, 0, w, h);

    if (currentGraph.nodes.length === 0) return;

    // Determine bounding box of nodes
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    currentGraph.nodes.forEach(n => {
      if (n.x < minX) minX = n.x;
      if (n.x > maxX) maxX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.y > maxY) maxY = n.y;
    });

    const pad = 80;
    minX -= pad; maxX += pad;
    minY -= pad; maxY += pad;

    const spanX = Math.max(maxX - minX, 1);
    const spanY = Math.max(maxY - minY, 1);
    const scale = Math.min(w / spanX, h / spanY);

    const offsetX = (w - spanX * scale) / 2;
    const offsetY = (h - spanY * scale) / 2;

    // Render node dots
    currentGraph.nodes.forEach(n => {
      const mx = (n.x - minX) * scale + offsetX;
      const my = (n.y - minY) * scale + offsetY;
      minimapCtx.beginPath();
      minimapCtx.arc(mx, my, n.importance >= 4 ? 2 : 1, 0, Math.PI * 2);
      minimapCtx.fillStyle = n.color;
      minimapCtx.fill();
    });

    // Render Camera Viewport Frustum Box
    const winW = window.innerWidth;
    const winH = window.innerHeight - 64;
    const k = state.zoomTransform.k;
    const tx = state.zoomTransform.x;
    const ty = state.zoomTransform.y;

    const camX1 = (-tx) / k;
    const camY1 = (-ty) / k;
    const camX2 = (winW - tx) / k;
    const camY2 = (winH - ty) / k;

    const vmx1 = (camX1 - minX) * scale + offsetX;
    const vmy1 = (camY1 - minY) * scale + offsetY;
    const vmx2 = (camX2 - minX) * scale + offsetX;
    const vmy2 = (camY2 - minY) * scale + offsetY;

    minimapCtx.strokeStyle = 'rgba(0, 240, 255, 0.85)';
    minimapCtx.lineWidth = 1;
    minimapCtx.strokeRect(vmx1, vmy1, vmx2 - vmx1, vmy2 - vmy1);
    minimapCtx.fillStyle = 'rgba(0, 240, 255, 0.08)';
    minimapCtx.fillRect(vmx1, vmy1, vmx2 - vmx1, vmy2 - vmy1);
  }

  // --- Helper: Get Connected Nodes (1-hop & 2-hop) ---
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

  // --- Interactive Hit Detection & Mouse Events ---
  function setupEventListeners() {
    // 1. Branch Switcher Tabs
    document.getElementById('tab-main').addEventListener('click', () => {
      loadBranch('main');
    });

    document.getElementById('tab-v2').addEventListener('click', () => {
      loadBranch('v2');
    });

    document.getElementById('tab-compare').addEventListener('click', () => {
      showComparisonModal();
    });

    // 2. Swarm Filter Checkbox
    toggleSwarmCheckbox.addEventListener('change', (e) => {
      state.includeSwarm = e.target.checked;
      loadBranch(state.currentBranch);
    });

    // 3. Layout Mode Selector
    layoutSelect.addEventListener('change', (e) => {
      applyLayoutPositions(e.target.value);
    });

    // 4. Canvas Mouse Move (Hover & Tooltip)
    graphCanvas.addEventListener('mousemove', (e) => {
      const node = getNodeAtPosition(e.clientX, e.clientY - 64);
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

    // 5. Canvas Click (Select Node)
    graphCanvas.addEventListener('click', (e) => {
      const node = getNodeAtPosition(e.clientX, e.clientY - 64);
      if (node) {
        selectNode(node);
      } else if (!state.isolatedNodeId) {
        state.selectedNode = null;
        hideInspector();
      }
    });

    // 6. Node Dragging via D3
    d3.select(graphCanvas).call(
      d3.drag()
        .container(graphCanvas)
        .subject(event => {
          const p = getTransformedPoint(event.x, event.y);
          return findClosestNode(p.x, p.y);
        })
        .on('start', (event) => {
          if (!event.active && simulation) simulation.alphaTarget(0.3).restart();
          event.subject.fx = event.subject.x;
          event.subject.fy = event.subject.y;
        })
        .on('drag', (event) => {
          const p = getTransformedPoint(event.x, event.y);
          event.subject.fx = p.x;
          event.subject.fy = p.y;
        })
        .on('end', (event) => {
          if (!event.active && simulation) simulation.alphaTarget(0);
          event.subject.fx = null;
          event.subject.fy = null;
        })
    );

    // 7. Search Input Handlers
    searchInput.addEventListener('input', (e) => {
      handleSearch(e.target.value.trim());
    });

    searchInput.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        clearSearch();
      } else if (e.key === 'Enter') {
        const first = searchResultsEl.querySelector('.search-item');
        if (first) first.click();
      }
    });

    searchClearBtn.addEventListener('click', clearSearch);

    // 8. Drawer Controls
    closeInspectorBtn.addEventListener('click', hideInspector);
    focusConstellationBtn.addEventListener('click', () => {
      if (state.selectedNode) {
        state.isolatedNodeId = state.selectedNode.id;
        focusConstellationBtn.classList.add('hidden');
        clearFocusBtn.classList.remove('hidden');
      }
    });

    clearFocusBtn.addEventListener('click', () => {
      state.isolatedNodeId = null;
      clearFocusBtn.classList.add('hidden');
      focusConstellationBtn.classList.remove('hidden');
    });

    copyShaBtn.addEventListener('click', () => {
      if (state.selectedNode && state.selectedNode.sha256Full) {
        navigator.clipboard.writeText(state.selectedNode.sha256Full);
        copyShaBtn.textContent = '✓';
        setTimeout(() => { copyShaBtn.textContent = '⧉'; }, 2000);
      }
    });

    // Inspector Tabs
    document.querySelectorAll('.insp-tab-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.insp-tab-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.insp-tab-content').forEach(c => c.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById(btn.dataset.tab).classList.add('active');
      });
    });

    // 9. Physics Drawer Controls
    toggleControlsBtn.addEventListener('click', () => {
      physicsPanel.classList.toggle('hidden');
      toggleControlsBtn.classList.toggle('active');
    });

    closePhysicsBtn.addEventListener('click', () => {
      physicsPanel.classList.add('hidden');
      toggleControlsBtn.classList.remove('active');
    });

    document.getElementById('slider-charge').addEventListener('input', (e) => {
      state.physics.charge = +e.target.value;
      document.getElementById('val-charge').textContent = e.target.value;
      if (simulation) simulation.force('charge').strength(state.physics.charge).alpha(0.3).restart();
    });

    document.getElementById('slider-link-dist').addEventListener('input', (e) => {
      state.physics.linkDistance = +e.target.value;
      document.getElementById('val-link-dist').textContent = e.target.value;
      if (simulation) simulation.force('link').distance(state.physics.linkDistance).alpha(0.3).restart();
    });

    document.getElementById('slider-collision').addEventListener('input', (e) => {
      state.physics.collision = +e.target.value;
      document.getElementById('val-collision').textContent = e.target.value;
      if (simulation) simulation.force('collide').radius(d => (d.importance * 3) + state.physics.collision).alpha(0.3).restart();
    });

    document.getElementById('slider-gravity').addEventListener('input', (e) => {
      state.physics.gravity = +e.target.value;
      document.getElementById('val-gravity').textContent = e.target.value;
      if (simulation) {
        simulation.force('x').strength(state.physics.gravity);
        simulation.force('y').strength(state.physics.gravity);
        simulation.alpha(0.3).restart();
      }
    });

    document.getElementById('slider-photon-speed').addEventListener('input', (e) => {
      state.physics.photonSpeed = +e.target.value;
      document.getElementById('val-photon-speed').textContent = `${e.target.value}x`;
    });

    document.getElementById('toggle-photons').addEventListener('change', (e) => {
      state.physics.showPhotons = e.target.checked;
    });

    document.getElementById('toggle-nebulas').addEventListener('change', (e) => {
      state.physics.showNebulas = e.target.checked;
    });

    document.getElementById('reset-physics-btn').addEventListener('click', resetPhysics);
    document.getElementById('reheat-sim-btn').addEventListener('click', () => {
      if (simulation) simulation.alpha(0.8).restart();
    });

    // 10. Reset Camera Button
    document.getElementById('reset-cam-btn').addEventListener('click', centerCamera);

    // 11. Minimap Click to Pan
    minimapCanvas.addEventListener('click', handleMinimapClick);

    // 12. Close Modals on ESC
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        hideComparisonModal();
        hideInspector();
        clearSearch();
      }
    });
  }

  function resetPhysics() {
    state.physics = {
      charge: -350,
      linkDistance: 90,
      collision: 18,
      gravity: 0.08,
      photonSpeed: 1.0,
      showPhotons: true,
      showNebulas: true
    };
    document.getElementById('slider-charge').value = -350;
    document.getElementById('val-charge').textContent = -350;
    document.getElementById('slider-link-dist').value = 90;
    document.getElementById('val-link-dist').textContent = 90;
    document.getElementById('slider-collision').value = 18;
    document.getElementById('val-collision').textContent = 18;
    document.getElementById('slider-gravity').value = 0.08;
    document.getElementById('val-gravity').textContent = 0.08;
    document.getElementById('slider-photon-speed').value = 1;
    document.getElementById('val-photon-speed').textContent = '1.0x';
    document.getElementById('toggle-photons').checked = true;
    document.getElementById('toggle-nebulas').checked = true;
    initSimulation();
  }

  // --- Point Transformations & Hit Testing ---
  function getTransformedPoint(clientX, clientY) {
    const k = state.zoomTransform.k;
    const tx = state.zoomTransform.x;
    const ty = state.zoomTransform.y;
    return {
      x: (clientX - tx) / k,
      y: (clientY - ty) / k
    };
  }

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

  function findClosestNode(x, y) {
    let closest = null;
    let minDist = 30;
    currentGraph.nodes.forEach(n => {
      if (!n.x || !n.y) return;
      const d = Math.hypot(n.x - x, n.y - y);
      if (d < minDist) {
        minDist = d;
        closest = n;
      }
    });
    return closest;
  }

  // --- Tooltip & Inspector ---
  function showTooltip(node, x, y) {
    document.getElementById('tt-category').textContent = node.categoryName;
    document.getElementById('tt-category').style.backgroundColor = hexToRgba(node.color, 0.2);
    document.getElementById('tt-category').style.color = node.color;
    document.getElementById('tt-lang').textContent = node.language;
    document.getElementById('tt-title').textContent = node.label;
    document.getElementById('tt-path').textContent = node.path;
    document.getElementById('tt-summary').textContent = node.summary;
    document.getElementById('tt-loc').textContent = node.loc;

    // Calculate node degree
    const linksCount = currentGraph.links.filter(l => {
      const sId = typeof l.source === 'object' ? l.source.id : l.source;
      const tId = typeof l.target === 'object' ? l.target.id : l.target;
      return sId === node.id || tId === node.id;
    }).length;
    document.getElementById('tt-degree').textContent = linksCount;

    tooltipEl.style.left = `${x}px`;
    tooltipEl.style.top = `${y}px`;
    tooltipEl.classList.remove('hidden');
  }

  function moveTooltip(x, y) {
    tooltipEl.style.left = `${x}px`;
    tooltipEl.style.top = `${y}px`;
  }

  function hideTooltip() {
    tooltipEl.classList.add('hidden');
  }

  function selectNode(node) {
    state.selectedNode = node;
    showInspector(node);
  }

  function showInspector(node) {
    document.getElementById('insp-category').textContent = node.categoryName;
    document.getElementById('insp-category').style.backgroundColor = hexToRgba(node.color, 0.2);
    document.getElementById('insp-category').style.color = node.color;
    document.getElementById('insp-name').textContent = node.label;
    document.getElementById('insp-path').textContent = node.path;
    document.getElementById('insp-summary').textContent = node.summary;
    document.getElementById('insp-meta-lang').textContent = node.language;
    document.getElementById('insp-meta-loc').textContent = `${node.loc} LOC`;
    document.getElementById('insp-meta-size').textContent = `${(node.size / 1024).toFixed(1)} KB`;
    document.getElementById('insp-meta-layer').textContent = `Layer ${node.layer} (${node.categoryName})`;
    document.getElementById('insp-meta-sha').innerHTML = `${node.sha256} <button class="copy-sha-btn" id="copy-sha-btn" title="Copy SHA256">⧉</button>`;

    // Reattach copy listener
    document.getElementById('copy-sha-btn').addEventListener('click', () => {
      if (node.sha256Full) {
        navigator.clipboard.writeText(node.sha256Full);
        const btn = document.getElementById('copy-sha-btn');
        btn.textContent = '✓';
        setTimeout(() => { btn.textContent = '⧉'; }, 2000);
      }
    });

    // Inbound & Outbound Dependencies
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

    document.getElementById('insp-deps-count').textContent = inbound.length + outbound.length;
    renderDepList('insp-inbound-list', inbound);
    renderDepList('insp-outbound-list', outbound);

    // Symbols list
    const symbolsListEl = document.getElementById('insp-symbols-list');
    symbolsListEl.innerHTML = '';
    document.getElementById('insp-syms-count').textContent = (node.symbols || []).length;
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

    // Code Preview
    document.getElementById('code-preview-filename').textContent = node.label;
    document.getElementById('insp-code-content').textContent = node.preview || '[Empty Content]';

    // Focus state button
    if (state.isolatedNodeId === node.id) {
      focusConstellationBtn.classList.add('hidden');
      clearFocusBtn.classList.remove('hidden');
    } else {
      focusConstellationBtn.classList.remove('hidden');
      clearFocusBtn.classList.add('hidden');
    }

    inspectorDrawer.classList.remove('hidden');
  }

  function hideInspector() {
    inspectorDrawer.classList.add('hidden');
  }

  function renderDepList(elementId, items) {
    const el = document.getElementById(elementId);
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
          panToNode(targetNode);
        }
      });
      el.appendChild(li);
    });
  }

  // --- Search & Autocomplete ---
  let searchIndex = [];
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

  function handleSearch(query) {
    state.searchQuery = query;
    if (!query) {
      searchResultsEl.classList.add('hidden');
      searchClearBtn.classList.add('hidden');
      return;
    }

    searchClearBtn.classList.remove('hidden');
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
      div.className = 'search-item';
      div.innerHTML = `
        <div class="search-item-top">
          <span class="search-item-title">${m.label}</span>
          <span class="search-item-cat" style="background:${hexToRgba(m.color, 0.2)};color:${m.color}">${m.categoryName}</span>
        </div>
        <div class="search-item-path">${m.path}</div>
      `;
      div.addEventListener('click', () => {
        selectNode(m.node);
        panToNode(m.node);
        clearSearch();
      });
      searchResultsEl.appendChild(div);
    });
    searchResultsEl.classList.remove('hidden');
  }

  function clearSearch() {
    searchInput.value = '';
    searchResultsEl.classList.add('hidden');
    searchClearBtn.classList.add('hidden');
  }

  // --- Camera Operations (Pan, Zoom, Center) ---
  function panToNode(node) {
    if (!node.x || !node.y) return;
    const width = window.innerWidth;
    const height = window.innerHeight - 64;
    const k = 1.6;

    const t = d3.zoomIdentity
      .translate(width / 2 - node.x * k, height / 2 - node.y * k)
      .scale(k);

    d3.select(graphCanvas).transition().duration(750).call(zoomBehavior.transform, t);
  }

  function centerCamera() {
    const width = window.innerWidth;
    const height = window.innerHeight - 64;
    const t = d3.zoomIdentity.translate(0, 0).scale(1.0);
    d3.select(graphCanvas).transition().duration(600).call(zoomBehavior.transform, t);
  }

  function handleMinimapClick(e) {
    const rect = minimapCanvas.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const clickY = e.clientY - rect.top;

    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    currentGraph.nodes.forEach(n => {
      if (n.x < minX) minX = n.x;
      if (n.x > maxX) maxX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.y > maxY) maxY = n.y;
    });

    const pad = 80;
    minX -= pad; maxX += pad;
    minY -= pad; maxY += pad;

    const spanX = Math.max(maxX - minX, 1);
    const spanY = Math.max(maxY - minY, 1);
    const scale = Math.min(minimapCanvas.width / spanX, minimapCanvas.height / spanY);

    const offsetX = (minimapCanvas.width - spanX * scale) / 2;
    const offsetY = (minimapCanvas.height - spanY * scale) / 2;

    const targetWorldX = minX + (clickX - offsetX) / scale;
    const targetWorldY = minY + (clickY - offsetY) / scale;

    const width = window.innerWidth;
    const height = window.innerHeight - 64;
    const k = state.zoomTransform.k;

    const t = d3.zoomIdentity
      .translate(width / 2 - targetWorldX * k, height / 2 - targetWorldY * k)
      .scale(k);

    d3.select(graphCanvas).transition().duration(500).call(zoomBehavior.transform, t);
  }

  function updateZoomIndicator() {
    const pct = Math.round(state.zoomTransform.k * 100);
    document.getElementById('zoom-indicator').textContent = `${pct}%`;
  }

  // --- HUD Updates ---
  function updateHUDStats(stats) {
    document.getElementById('stat-nodes').textContent = stats.totalFiles;
    document.getElementById('stat-links').textContent = stats.linksCount;
    document.getElementById('stat-loc').textContent = stats.totalLoc.toLocaleString();
    document.getElementById('stat-clusters').textContent = stats.clustersCount;
    document.getElementById('hud-cert-text').textContent = stats.certStatus;
    document.getElementById('hud-branch-tag').textContent = `${state.currentBranch.toUpperCase()} BRANCH`;
  }

  function updateCategoryChips(clusters) {
    categoryChipsContainer.innerHTML = '';
    clusters.forEach(c => {
      const chip = document.createElement('div');
      chip.className = 'category-chip active';
      chip.style.setProperty('--chip-color', c.color);
      chip.innerHTML = `
        <span class="chip-dot"></span>
        <span>${c.name}</span>
        <span class="chip-count">(${c.nodeCount})</span>
      `;

      chip.addEventListener('click', () => {
        if (state.activeCategoryFilters.has(c.id)) {
          state.activeCategoryFilters.delete(c.id);
          chip.classList.remove('active');
        } else {
          state.activeCategoryFilters.add(c.id);
          chip.classList.add('active');
        }
        loadBranch(state.currentBranch);
      });

      categoryChipsContainer.appendChild(chip);
    });
  }

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

  // --- Comparison Modal Setup ---
  function setupComparisonModal() {
    const comp = graphData.comparison;
    if (!comp) return;

    // Metrics table
    const tbody = document.getElementById('compare-metrics-tbody');
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

    // Mappings grid
    const grid = document.getElementById('compare-mappings-grid');
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

    closeCompareBtn.addEventListener('click', hideComparisonModal);
  }

  function showComparisonModal() {
    compareModal.classList.remove('hidden');
  }

  function hideComparisonModal() {
    compareModal.classList.add('hidden');
  }

  // --- Utilities ---
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

  function getBasename(path) {
    const parts = path.split('/');
    return parts[parts.length - 1];
  }

  // Bootstrap when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
