# Infrastructure & Git Survey Report: Roo4u Constellation Overhaul

## 1. Executive Summary

This investigation surveys the git repository state, branch architecture, remote hosting, GitHub Pages deployment configuration, local testing/serving infrastructure, baseline file fingerprints, and safety boundaries for the Constellation Overhaul of repository \`s6pa1rta3n-lab/roof4u\`.

Key Findings:
1. **Branch Divergence**: The workspace is currently checked out on branch \`v2\` (commit \`1767c22\`). The target branch containing the constellation visualizer files is \`main\` (commit \`115a789\`), which is also the remote tracking branch configured for GitHub Pages deployment from the \`/docs\` folder.
2. **GitHub Pages Deployment**: GitHub Pages is active at \`https://s6pa1rta3n-lab.github.io/roof4u/\`, deployed automatically from \`main\` branch, path \`/docs\`.
3. **Dataset Invariance**: \`docs/data.js\` has SHA-256 \`b90ac01dc8fff2145506a405594790fadacedcc4bd5f547d4074d9489d6f823e\` (2,835,047 bytes, 19,732 lines). It contains extracted repository architecture for both \`main\` and \`v2\` branches and must remain strictly byte-identical.
4. **Local Verification Infrastructure**: Local HTTP serving via Python \`http.server\` and automated headless end-to-end testing via Python Playwright (Chromium) and Google Chrome CLI are fully functional and verified on this machine.
5. **Safety Isolation**: Scope is strictly isolated to \`docs/\` and root \`index.html\`. Foreign repositories (such as \`s6pa1rta3n-lab.github.io\`) and non-visualization codebase files (such as \`ocaml/*\`) must not be touched or committed.

---

## 2. Git Repository & Branch Topology

### 2.1 Branch State
- **Current Active Branch**: \`v2\` (HEAD: \`1767c22\`)
- **Remote Tracking Branches**:
  - \`origin/main\` -> \`115a789\` ("feat: Add interactive constellation network graph visualization")
  - \`origin/v2\` -> \`1767c22\` ("refactor(v3): remove deprecated Python architecture to enforce pure OCaml environment")
- **Remote Origin URL**: \`https://github.com/s6pa1rta3n-lab/roof4u.git\`

### 2.2 Branch Commit Graph
```
* 1767c22 (HEAD -> v2, origin/v2) refactor(v3): remove deprecated Python architecture to enforce pure OCaml environment
* d646d06 feat(v3): teamwork_preview completed pure OCaml rewrite and adversarial audit.
* 51986a5 feat(v2): implement OCaml mathematical verification engine, SKILLS.md catalog, and live SF data acquisition pipeline
| * 115a789 (main, origin/main) feat: Add interactive constellation network graph visualization
|/  
* ad88097 docs: rewrite README for offline architecture and literal communication standards
```

### 2.3 Commit 115a789 Artifacts (on `main`)
Commit \`115a789\` introduced the initial constellation visualization suite to \`main\`:
- \`docs/app.js\` (1,308 lines, 44,392 bytes)
- \`docs/data.js\` (19,732 lines, 2,835,047 bytes)
- \`docs/data.json\` (19,731 lines, 2,834,956 bytes)
- \`docs/index.html\` (371 lines, 17,527 bytes)
- \`docs/styles.css\` (1,327 lines, 25,515 bytes)
- \`index.html\` (14 lines, 528 bytes)
- \`scripts/generate_graph_data.py\` (520 lines, 22,462 bytes)

*Note*: Because \`v2\` diverged at \`ad88097\`, the working tree on \`v2\` does not have \`docs/\` checked out by default. Workers will need to checkout \`main\` or extract \`docs/\` when performing the overhaul.

---

## 3. GitHub Remote & GitHub Pages Configuration

### 3.1 GitHub API Pages Status
Verified via \`gh api repos/s6pa1rta3n-lab/roof4u/pages\`:
```json
{
  "url": "https://api.github.com/repos/s6pa1rta3n-lab/roof4u/pages",
  "status": "built",
  "cname": null,
  "custom_404": false,
  "html_url": "https://s6pa1rta3n-lab.github.io/roof4u/",
  "build_type": "legacy",
  "source": {
    "branch": "main",
    "path": "/docs"
  },
  "public": true,
  "https_enforced": true
}
```

### 3.2 Feature Issue Context
- **Issue**: \`https://github.com/s6pa1rta3n-lab/roof4u/issues/25\`
- **Title**: \`feat: Black Hole Aesthetic Overhaul + 3D Depth + Remove Minimap\`
- **Requirements**:
  1. Remove galactic radar minimap (DOM, JS, CSS)
  2. Pure black hole aesthetic (#000000 background, black glassmorphism, zero starfields/ambient light)
  3. 3D depth rendering engine (z-axis modulation of size, brightness, opacity, glow, parallax on pan/zoom, depth sorting)
  4. Full viewport fitting (100vw x 100vh with no scrollbar overflow)
  5. Multi-theme design proposal selector (live switching without page reload)

---

## 4. Local Serving & Automated Testing Infrastructure

### 4.1 Available Runtimes & Tooling
| Tool | Path / Version | Status |
|---|---|---|
| Python 3 | \`/opt/homebrew/bin/python3\` (3.14.7) | Verified |
| Node.js | \`/Users/solveetcoagula/.nvm/versions/node/v18.20.8/bin/node\` (v18.20.8) | Verified |
| npm / npx | \`/Users/solveetcoagula/.nvm/versions/node/v18.20.8/bin/npm\` / \`npx\` | Verified |
| Google Chrome | \`/Applications/Google Chrome.app/Contents/MacOS/Google Chrome\` | Verified |
| Playwright (Python) | \`/opt/homebrew/lib/python3.14/site-packages/playwright\` | Verified (headless Chromium operational) |
| curl | \`/usr/bin/curl\` | Verified |

### 4.2 Local HTTP Server Execution Pattern
To serve the visualizer locally for development and testing:
```bash
# Option A: Serve from project root (access at http://localhost:8080/docs/index.html or http://localhost:8080/index.html)
python3 -m http.server 8080

# Option B: Serve directly from docs/ (access at http://localhost:8080/index.html)
python3 -m http.server 8080 --directory docs
```

### 4.3 Automated End-to-End Headless Test Pattern
A Python Playwright script can spin up an ephemeral background server, launch Chromium headlessly, and validate:
1. Zero console errors or unhandled exceptions.
2. Background color is computed as \`rgb(0, 0, 0)\` (#000000).
3. Complete absence of \`#minimap-container\` and \`#minimap-canvas\`.
4. Theme selector switches between >= 3 proposals without reload, maintaining black hole foundation.
5. Canvas rendering and depth calculation integrity.
6. Responsive viewport fitting (1920x1080, 1440x900, 1280x800, mobile/tablet) with zero scrollbar overflow (\`scrollWidth <= clientWidth\`, \`scrollHeight <= clientHeight\`).

---

## 5. Baseline File Integrity & Fingerprints

The following table records the authoritative baseline hashes and sizes from the \`main\` branch commit \`115a789\`:

| Relative Path | Blob SHA-1 | Byte Size | Lines | SHA-256 Checksum | Invariance Status |
|---|---|---|---|---|---|
| \`docs/data.js\` | \`d0788e2a4338a988b994cd17f20225a0fff33c45\` | 2,835,047 | 19,732 | \`b90ac01dc8fff2145506a405594790fadacedcc4bd5f547d4074d9489d6f823e\` | **STRICTLY IMMUTABLE** (Must be byte-identical) |
| \`docs/data.json\` | \`78a9974899bb8c786aaa98742245c969bfad2ff5\` | 2,834,956 | 19,731 | \`3c8a3a57c29b9c5e729826b343852fb79cd718b5b7d344b944ce71449371ab2a\` | Preserved |
| \`docs/app.js\` | \`a40158f516a9521361810aa0116aed303ce41bdc\` | 44,392 | 1,308 | \`488dac6e43d26f877f22ce8bdf9311fac1d6b184083c3b235599f39f49e4df08\` | Target for overhaul |
| \`docs/styles.css\` | \`da510e0a4d2d860eebdad8fe90cf57b4339a2fd9\` | 25,515 | 1,327 | \`1a0a9e231b89882ecab05bc6aa7e05821a5c0805915002b78290623fc86714fb\` | Target for overhaul |
| \`docs/index.html\` | \`6344cd9b5f9f5e65306355e625cf0cec96a80779\` | 17,527 | 371 | \`f63b5ef10462da0f7c51a95b42f8c4f1b834e3d76eb12495937e9f9b4b7e55b6\` | Target for overhaul |
| \`index.html\` | \`8d2d374ee0c53d615330713c5dde65cd9962575a\` | 528 | 14 | \`2a9d9bd6b83f9b93b6257e65a74a2ebfd437d07fdab30066945e1202347f47da\` | Target for redirect / black bg |
| \`scripts/generate_graph_data.py\` | \`87ca86b1f2e16d4cfa2b988f0cb646f9ea22e5be\` | 22,462 | 520 | \`faacac82aee74973f64d3a08f45295db5be93c4342931afd1dc9fe41d346d41a\` | Baseline generator reference |

### 5.1 Verification Command for `docs/data.js`
```bash
python3 -c '
import hashlib
with open("docs/data.js", "rb") as f:
    sha = hashlib.sha256(f.read()).hexdigest()
assert sha == "b90ac01dc8fff2145506a405594790fadacedcc4bd5f547d4074d9489d6f823e", f"Checksum mismatch: {sha}"
print("docs/data.js SHA-256 verification: PASS (byte-identical)")
'
```

---

## 6. Safety Boundaries & Execution Protocols

### 6.1 Repository Boundaries
1. **Target Repository**: ONLY \`s6pa1rta3n-lab/roof4u\`.
2. **Strictly Prohibited**: DO NOT touch, inspect, or modify \`s6pa1rta3n-lab.github.io\` root repository or any peer repository under \`/Users/solveetcoagula/Desktop/activeProjects/\`.
3. **Commit & Push Target**: Changes must be committed and pushed exclusively to \`main\` branch of \`origin\` (\`s6pa1rta3n-lab/roof4u\`).

### 6.2 File Modification Scope
- **Permitted Modifications**:
  - \`docs/index.html\`
  - \`docs/styles.css\`
  - \`docs/app.js\`
  - \`index.html\` (root redirect file)
  - Agent workspace files in \`.agents/<assigned_folder>/\`
- **Strictly Forbidden Modifications**:
  - \`docs/data.js\` (Must remain byte-identical)
  - Any files in \`ocaml/\`, \`agents/\`, \`db/\`, \`exporters/\`, \`integrations/\`, \`memory/\`, \`skills/\`, \`tests/\`
  - \`PROJECT.md\`, \`README.md\`, \`SKILLS.md\`, \`TEST_READY.md\`, \`TEST_INFRA.md\`, \`CERTIFICATION_REPORT.md\`, \`CERTIFIED_PASS.json\`
  - Database files (\`leads.db\`, \`vector_store.sqlite\`, \`*.db\`, \`*.csv\`)

### 6.3 Branch Transition Protocol for Workers
1. Ensure uncommitted metadata in \`.agents/\` is intact.
2. Checkout \`main\` branch:
   \`git checkout main\`
   (If untracked agent files conflict, keep them intact).
3. Verify working directory matches \`main\` and \`docs/\` exists.
4. Perform code modifications in \`docs/index.html\`, \`docs/styles.css\`, \`docs/app.js\`, and \`index.html\`.
5. Run full E2E automated verification test suite and SHA-256 check on \`docs/data.js\`.
6. Commit changes to \`main\`.
7. Victory audit verification prior to pushing to \`origin main\`.
