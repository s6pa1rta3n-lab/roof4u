# Roo4u: Autonomous Real Estate Intelligence & Local AI Lead Generation

Roo4u is an autonomous lead generation pipeline engineered for roofing contractors targeting Victorian, flat, and Mansard roofs in high-value San Francisco corridors. It combines a pure OCaml 5 deterministic calculation engine with a strictly local, zero-spend autonomous AI agent swarm.

## System Architecture

The system operates as a dual-runtime architecture:
1. **Deterministic Core (Pure OCaml 5)**: High-speed algebraic invariants (INV1-INV4), GIS ray-casting algorithms, SODA municipal data connectors, actionability scoring, SHA-256 cryptographic proofs, dual memory persistence (`lessons_learned.json`, `vector_store.sqlite`), CSV exports, and Google Sheets API v4 integration.
2. **Local AI Swarm (Python 3.11+)**: Vision-free headless browsing, local LLM orchestration via `llama.cpp`, AST code modification, and a 5-step recursive self-healing loop.

```
+----------------------------------------------------------------------------------------------------+
|                                    Roo4u System Architecture                                       |
+----------------------------------------------------------------------------------------------------+
|                                                                                                    |
|  +----------------------------------------------------------------------------------------------+  |
|  | Pure OCaml 5 Deterministic Engine                                                            |  |
|  | - GIS Polygon Ray-Casting & Morphological Classifiers (gods-eye-view)                        |  |
|  | - Public Record Connectors (SF Assessor-Recorder Secured Roll, SF DBI Permits)               |  |
|  | - Formal Invariant Verification (INV1-INV4) & SHA-256 Cryptographic Proofs                   |  |
|  | - Transactional Lead Storage (SQLite WAL) & Google Sheets API v4 Integration                 |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                                |                                                   |
|                        Inter-process Communication / Unix Sockets                                  |
|                                                v                                                   |
|  +----------------------------------------------------------------------------------------------+  |
|  | Strictly Local AI Infrastructure (Zero External API Spend)                                  |  |
|  | - Model Serving: llama.cpp (llama-server) on 127.0.0.1:8000/v1 (api_key="not-needed")         |  |
|  | - Model Checkpoints: Qwen2.5-Coder-7B (Workstation) / Qwen2.5-Coder-1.5B (CI/CD) GGUF Q4_K_M   |  |
|  | - Vision-Free Browsing Agent: Playwright Chromium + DOMDistiller (data-agent-id annotation)  |  |
|  | - Autonomous Coding Agent: AST Parser, DiffEngine (unified diffs), Sandbox Test Runner      |  |
|  | - 5-Step Recursive Self-Healing Loop: Failure Capture -> Vector Retrieval -> Fix -> Deploy   |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                                |                                                   |
|                                Automated Verification & CI/CD                                      |
|                                                v                                                   |
|  +----------------------------------------------------------------------------------------------+  |
|  | GitHub Actions CI/CD Automation                                                              |  |
|  | - ci.yml: Dual OCaml 5 dune runtest + Python pytest verification                             |  |
|  | - local-ai-verify.yml: Model weight caching, local llama-server launch, non-mock tests        |  |
|  | - daily-acquisition.yml: Scheduled daily cron updating validated_leads.csv                   |  |
|  | - security-audit.yml: Adversarial invariant validation and secret leak scans                |  |
|  | - issue_hygiene.yml: Automated issue hygiene and telemetry queue reconciliation              |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                                                                                    |
+----------------------------------------------------------------------------------------------------+
```

## Zero-Spend Local AI Infrastructure

The entire AI layer operates without external commercial LLM APIs (OpenAI, Google Gemini, Anthropic). All inference executes locally on consumer workstations or standard GitHub Actions CI runners.

### Model Runtime & Serving
- **Server Engine**: `llama.cpp` (`llama-server`) or `llama-cpp-python` exposing standard OpenAI-compatible endpoints (`/v1/chat/completions`, `/v1/models`, `/health`).
- **Endpoint Binding**: Binds strictly to `127.0.0.1:8000`. Authentication defaults to `api_key = "not-needed"`.
- **Model Checkpoints**: Qwen2.5-Coder series in GGUF format:
  - **Workstation**: `Qwen2.5-Coder-7B-Instruct (Q4_K_M GGUF)` (4.37 GB footprint, fits inside 6GB VRAM/RAM).
  - **CI/CD Runner**: `Qwen2.5-Coder-1.5B-Instruct (Q4_K_M GGUF)` (1.05 GB footprint, fits inside 1.8GB RAM on 2-core CPU runners).

### Hardware Profiling & Quantization Matrix

The hardware profiler (`agents/models/hardware_profiler.py`) introspects system compute resources and selects optimal context sizes and layer offloading:

| Deployment Tier | Hardware Profile | Model & Quantization | Offload Layers (`-ngl`) | Context Window |
|---|---|---|---|---|
| Tier 1: CI Runner | 7 GB RAM, 2 CPU Cores | Qwen2.5-Coder-1.5B (Q4_K_M) | 0 (CPU) | 4,096 tokens |
| Tier 2: Base Laptop | 8 GB Unified RAM (M1/M2/M3) | Qwen2.5-Coder-1.5B (Q8_0) | 99 (Metal) | 8,192 tokens |
| Tier 3: Workstation | 16-32 GB RAM / RTX 3060+ | Qwen2.5-Coder-7B (Q4_K_M) | 99 (Metal / CUDA) | 16,384 tokens |
| Tier 4: Enterprise | 64 GB+ RAM / RTX 4090+ | Qwen2.5-Coder-7B (Q8_0) / 14B | 99 (Metal / CUDA) | 32,768 tokens |

Analytical memory model for KV cache:
$$\text{KV Cache Bytes} = 2 \times n_{\text{layers}} \times n_{\text{heads}} \times d_{\text{head}} \times c_{\text{ctx}} \times \text{bytes per element}$$

## Vision-Free Local Browsing Agent

The browsing agent (`agents/browser/browser_agent.py`) eliminates reliance on commercial vision APIs by distilling webpage DOMs into structured textual representations:
- **Pruning**: Eliminates scripts, styles, inline SVGs, tracking pixels, and hidden containers.
- **Sequential Annotation**: Injects sequential numeric attributes `data-agent-id="1..N"` into interactive targets (`input`, `button`, `select`, `a`).
- **Table Linearization**: Converts municipal permit and zoning tables into Markdown tables under 2,000 tokens.
- **Token Budget Enforcement**: Restricts distilled prompt payloads to 3,500 tokens.
- **Air-Gapped Fixture Cache**: Intercepts Playwright network traffic when `ROOF4U_OFFLINE=1`, serving local HTML fixtures from `tests/fixtures/html/` for deterministic offline testing.

## Recursive Self-Healing Learning Engine

The learning engine continuously captures operational failures, searches historical lessons, and deploys autonomous code patches:

1. **Step 1: Failure Capture & Telemetry**: Scraper or parser exceptions generate SHA-256 fingerprints matching OCaml `telemetry.ml` (`domain|failure_type|selector|error_message[:120]`) and queue into `.github_issues_queue.json`.
2. **Step 2: Dual Memory Retrieval**: Queries `vector_store.sqlite` via 256-dimensional cosine similarity embeddings and `lessons_learned.json` via atomic file locking (`Unix.lockf`).
3. **Step 3: Solution Architecture & Diff Proposals**: Local LLM synthesizes unified diff patches (`diff -u`) with root-cause diagnoses.
4. **Step 4: Autonomous Coding Agent Deployment**: Applies patches, validates AST syntax, executes tests (`dune runtest` and `pytest`), and executes atomic rollback if tests fail.
5. **Step 5: Continuous Weight Updates**: Compiles verified fixes into instruction datasets (`training/fine_tuning_pairs.jsonl`) for local LoRA fine-tuning and updates evaluator preference weights.

## GitHub Actions CI/CD Automation

All workflows run on standard `ubuntu-latest` runners with zero external API fees:

| Workflow File | Trigger | Purpose | Key Commands |
|---|---|---|---|
| `.github/workflows/ci.yml` | `push`, `pull_request` | Core engine compilation and test verification | `dune build --root ocaml`, `dune runtest --root ocaml`, `pytest tests/ai/ -v` |
| `.github/workflows/local-ai-verify.yml` | `push`, `pull_request` | Background model server and live inference tests | Cache GGUF weights, launch `llama-server` on CPU, `pytest tests/ai/test_live_inference.py` |
| `.github/workflows/daily-acquisition.yml` | Scheduled (`0 6 * * *`) | Autonomous daily lead acquisition batch | `dune exec bin/main.exe -- --run --neighborhood "Pacific Heights" --csv validated_leads.csv` |
| `.github/workflows/security-audit.yml` | `push`, weekly schedule | Adversarial invariant audits and credential leak checks | `test_tier5_adversarial.exe`, `test_security.exe`, credential pattern grep |
| `.github/workflows/issue_hygiene.yml` | Scheduled (`0 12 * * *`) | Telemetry issue queue reconciliation | Inspect `.github_issues_queue.json`, audit open issues |

## Setup and Verification

### Prerequisites
- OCaml 5.1+ and Dune (`opam install dune zarith sqlite3`)
- Python 3.11+ with virtual environment
- System libraries: `libgmp-dev`, `libsqlite3-dev`

### Installation
```bash
# Clone repository
git clone https://github.com/s6pa1rta3n-lab/roof4u.git
cd roof4u

# Setup Python environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
playwright install chromium
```

### Verification Commands
```bash
# 1. Run all OCaml test suites
dune runtest --root ocaml

# 2. Run all Python AI test suites
pytest tests/ai/ -v

# 3. Run live inference tests (launches local socket server)
pytest tests/ai/test_live_inference.py -v

# 4. Run browser agent offline fixture tests
ROOF4U_OFFLINE=1 pytest tests/ai/test_browser_agent.py -v

# 5. Run coding agent and self-healing loop verification
pytest tests/ai/test_coding_agent.py tests/ai/test_self_healing_loop.py -v
```

## License

MIT License.
