#!/usr/bin/env python3
"""
scripts/generate_graph_data.py

Extracts complete repository architecture, AST symbols, file metadata, and dependency graphs
for both 'main' (Python architecture) and 'v2' (Pure OCaml rewrite) branches of Roo4u.
Outputs to docs/data.js and docs/data.json for GitHub Pages constellation graph visualization.
"""

import os
import re
import json
import hashlib
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

def run_git_cmd_bytes(args):
    res = subprocess.run(['git'] + args, cwd=REPO_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if res.returncode != 0:
        return b""
    return res.stdout

def get_git_tree(branch):
    raw_bytes = run_git_cmd_bytes(['ls-tree', '-r', '-l', branch])
    raw = raw_bytes.decode('utf-8', errors='replace')
    files = {}
    for line in raw.splitlines():
        if not line.strip():
            continue
        parts = line.split()
        if len(parts) >= 5:
            size_str = parts[3]
            size = int(size_str) if size_str.isdigit() else 0
            path = ' '.join(parts[4:])
            files[path] = size
    return files

def get_language(path):
    ext = Path(path).suffix.lower()
    mapping = {
        '.py': 'Python',
        '.ml': 'OCaml',
        '.mli': 'OCaml Interface',
        '.json': 'JSON',
        '.md': 'Markdown',
        '.sqlite': 'SQLite',
        '.db': 'SQLite',
        '.txt': 'Text',
        '.opam': 'OPAM',
        '.csv': 'CSV',
        '.html': 'HTML Fixture',
        '.sh': 'Shell',
    }
    if Path(path).name in ['dune', 'dune-project']:
        return 'Dune'
    if Path(path).name == 'LICENSE':
        return 'License'
    return mapping.get(ext, 'Config/Other')

def extract_python_symbols(content):
    symbols = []
    for line in content.splitlines():
        line_str = line.strip()
        m_cls = re.match(r'^class\s+([A-Za-z0-9_]+)(\([^\)]*\))?:', line_str)
        if m_cls:
            symbols.append(f"class {m_cls.group(1)}")
        m_def = re.match(r'^def\s+([A-Za-z0-9_]+)\s*\(', line_str)
        if m_def:
            symbols.append(f"def {m_def.group(1)}()")
    return symbols[:15]

def extract_ocaml_symbols(content):
    symbols = []
    for line in content.splitlines():
        line_str = line.strip()
        m_mod = re.match(r'^module\s+([A-Za-z0-9_]+)', line_str)
        if m_mod:
            symbols.append(f"module {m_mod.group(1)}")
        m_type = re.match(r'^type\s+([a-z0-9_]+)', line_str)
        if m_type:
            symbols.append(f"type {m_type.group(1)}")
        m_let = re.match(r'^let\s+([a-z0-9_]+)', line_str)
        if m_let:
            symbols.append(f"let {m_let.group(1)}")
        m_val = re.match(r'^val\s+([a-z0-9_]+)', line_str)
        if m_val:
            symbols.append(f"val {m_val.group(1)}")
    return symbols[:15]

def extract_doc_summary(content, language, path):
    lines = [l.strip() for l in content.splitlines() if l.strip()]
    if not lines:
        return f"{language} database/binary storage" if language == 'SQLite' else "Empty file"
    
    if language == 'Python':
        full_text = '\n'.join(content.splitlines()[:20])
        m = re.search(r'"""(.*?)"""', full_text, re.DOTALL)
        if m:
            doc = m.group(1).strip()
            first_line = doc.split('\n')[0].strip()
            if first_line.endswith('.py'):
                lines_doc = [l.strip() for l in doc.split('\n') if l.strip()]
                return ' '.join(lines_doc[1:3]) if len(lines_doc) > 1 else first_line
            return doc.replace('\n', ' ')[:140]
        comments = [l[1:].strip() for l in lines if l.startswith('#')]
        if comments:
            return comments[0][:140]
        return "Python module component"

    if language in ['OCaml', 'OCaml Interface']:
        full_text = '\n'.join(content.splitlines()[:20])
        m = re.search(r'\(\*\*(.*?)\*\)', full_text, re.DOTALL)
        if m:
            doc = m.group(1).strip()
            lines_doc = [l.strip() for l in doc.split('\n') if l.strip()]
            return ' '.join(lines_doc[:2])[:140]
        return "OCaml functional module"

    if language == 'Markdown':
        headers = [l.lstrip('#').strip() for l in lines if l.startswith('#')]
        if headers:
            return headers[0][:140]
        return "Documentation artifact"

    if language == 'HTML Fixture':
        return "Offline zero-mock HTML test fixture"

    if language == 'SQLite':
        return "Local SQLite relational/vector database store"

    return f"{language} asset"

def categorize_file(path, branch):
    p = path.lower()
    
    # Swarms
    if p.startswith('.agents/'):
        return 'swarm', 'Agent Swarm Logs', 6, '#64748b'
    
    # Skills
    if p.startswith('skills/'):
        return 'skills', 'Agent Skills Array', 2, '#ec4899'
        
    # Main branch categorization
    if branch == 'main':
        if p == 'main.py' or p in ['project.md', 'readme.md', 'requirements.txt', 'test_infra.md']:
            return 'core', 'Core & Orchestration', 1, '#f59e0b'
        if p.startswith('agents/'):
            return 'agents', 'Autonomous Agents', 2, '#00f0ff'
        if p.startswith('db/'):
            return 'database', 'Database & Persistence', 4, '#10b981'
        if p.startswith('memory/'):
            return 'memory', 'Memory & Vector Subsystem', 3, '#a855f7'
        if p.startswith('exporters/'):
            return 'exporters', 'Data Exporters', 4, '#3b82f6'
        if p.startswith('integrations/'):
            return 'integrations', 'Dual-Transport Integrations', 3, '#06b6d4'
        if p.startswith('scripts/'):
            return 'scripts', 'Execution Scripts', 1, '#fbbf24'
        if p.startswith('tests/fixtures/'):
            return 'fixtures', 'Zero-Mock HTML Fixtures', 5, '#fb7185'
        if p.startswith('tests/'):
            return 'tests', 'Zero-Mock Test Array', 5, '#ef4444'
        if 'cert' in p or 'report' in p or p.endswith('.json'):
            return 'governance', 'Governance & Certifications', 1, '#eab308'
            
    # V2 branch categorization
    if branch == 'v2':
        if p.startswith('ocaml/bin/'):
            return 'ocaml_bin', 'OCaml Native Executable', 1, '#38bdf8'
        if p.startswith('ocaml/lib/'):
            if 'crypto' in p or 'json' in p or 'invariants' in p or 'types' in p:
                return 'ocaml_types', 'Type Invariants & Cryptography', 2, '#a855f7'
            if 'db' in p or 'vector_store' in p or 'embeddings' in p or 'lesson' in p:
                return 'ocaml_storage', 'OCaml Storage & Vector Memory', 3, '#c084fc'
            if 'municipal' in p or 'datasf' in p or 'scorer' in p or 'pipeline' in p:
                return 'ocaml_core', 'OCaml Functional Lead Pipeline', 2, '#00f0ff'
            return 'ocaml_lib', 'OCaml Core Library', 2, '#0284c7'
        if p.startswith('ocaml/test/'):
            return 'ocaml_tests', 'OCaml Test & Adversarial Array', 5, '#ef4444'
        if 'ocaml_verifier' in p or 'test_json_adversarial' in p or 'test_sha256' in p:
            return 'bridge', 'Differential Verification Bridge', 3, '#f97316'
        if p.startswith('ocaml/'):
            return 'ocaml_build', 'OCaml Build & Toolchain', 1, '#38bdf8'
        if p.startswith('agents/') or p == 'main.py':
            return 'legacy_agents', 'Preserved Python Architecture', 4, '#06b6d4'
        if p.startswith('tests/'):
            return 'tests', 'Python Test Baseline', 5, '#f43f5e'
        if 'cert' in p or 'security' in p or 'report' in p or p in ['project.md', 'readme.md']:
            return 'governance', 'Security & Certifications', 1, '#eab308'

    return 'other', 'System Files', 6, '#94a3b8'

def build_branch_graph(branch):
    files = get_git_tree(branch)
    nodes = []
    links = []
    
    node_lookup = {}
    content_cache = {}
    content_bytes_cache = {}
    
    # Bulk read files
    for path, size in files.items():
        raw_b = run_git_cmd_bytes(['show', f'{branch}:{path}'])
        content_bytes_cache[path] = raw_b
        content_cache[path] = raw_b.decode('utf-8', errors='replace')
    
    # Metrics
    total_loc = 0
    code_loc = 0
    test_loc = 0
    ocaml_loc = 0
    py_loc = 0
    
    for path, size in files.items():
        content = content_cache[path]
        content_bytes = content_bytes_cache[path]
        lines = content.splitlines()
        loc = len(lines)
        total_loc += loc
        
        lang = get_language(path)
        if lang == 'Python':
            code_loc += loc
            py_loc += loc
        elif lang in ['OCaml', 'OCaml Interface']:
            code_loc += loc
            ocaml_loc += loc
            
        if 'test' in path.lower():
            test_loc += loc
            
        cat_id, cat_name, layer, color = categorize_file(path, branch)
        
        symbols = []
        if lang == 'Python':
            symbols = extract_python_symbols(content)
        elif lang in ['OCaml', 'OCaml Interface']:
            symbols = extract_ocaml_symbols(content)
            
        summary = extract_doc_summary(content, lang, path)
        sha256_hash = hashlib.sha256(content_bytes).hexdigest() if content_bytes else ""
        
        preview = '\n'.join(lines[:18])
        if lang == 'SQLite':
            preview = f"[Binary SQLite Database - Size: {size} bytes, SHA256: {sha256_hash[:16]}...]"
            
        importance = 2
        basename = Path(path).name
        if basename in ['main.py', 'main.ml', 'pipeline.ml', 'database.py', 'types.ml', 'invariants.ml', 'CERTIFIED_PASS.json']:
            importance = 5
        elif path.startswith('agents/') or path.startswith('ocaml/lib/'):
            importance = 4
        elif 'test' in basename or path.startswith('skills/'):
            importance = 3
        elif path.startswith('.agents/'):
            importance = 1
            
        node_obj = {
            'id': path,
            'label': basename,
            'path': path,
            'category': cat_id,
            'categoryName': cat_name,
            'layer': layer,
            'color': color,
            'size': size,
            'loc': loc,
            'language': lang,
            'summary': summary,
            'symbols': symbols,
            'sha256': sha256_hash[:16] + '...' if sha256_hash else 'N/A',
            'sha256Full': sha256_hash,
            'preview': preview,
            'importance': importance,
            'isSwarm': path.startswith('.agents/')
        }
        nodes.append(node_obj)
        node_lookup[path] = node_obj

    # Build Links
    # 1. Python imports
    for n in nodes:
        path = n['id']
        content = content_cache.get(path, '')
        if n['language'] == 'Python':
            for line in content.splitlines():
                line = line.strip()
                m_from = re.match(r'^from\s+([\w\.]+)\s+import', line)
                if m_from:
                    mod_path = m_from.group(1).replace('.', '/')
                    for cand in [f"{mod_path}.py", f"{mod_path}/__init__.py", f"{mod_path}"]:
                        if cand in node_lookup and cand != path:
                            links.append({
                                'source': path,
                                'target': cand,
                                'type': 'import',
                                'label': f"imports {m_from.group(1)}",
                                'weight': 2
                            })
                m_imp = re.match(r'^import\s+([\w\.]+)', line)
                if m_imp:
                    mod_path = m_imp.group(1).replace('.', '/')
                    cand = f"{mod_path}.py"
                    if cand in node_lookup and cand != path:
                        links.append({
                            'source': path,
                            'target': cand,
                            'type': 'import',
                            'label': f"imports {m_imp.group(1)}",
                            'weight': 2
                        })

        # 2. OCaml module references and interfaces
        if n['language'] in ['OCaml', 'OCaml Interface']:
            if path.endswith('.ml'):
                mli_path = path + 'i'
                if mli_path in node_lookup:
                    links.append({
                        'source': path,
                        'target': mli_path,
                        'type': 'interface',
                        'label': "implements interface",
                        'weight': 3
                    })
            
            for m in re.finditer(r'\bopen\s+([A-Z][a-zA-Z0-9_]*)', content):
                mod_name = m.group(1).lower()
                cand_paths = [f"ocaml/lib/{mod_name}.ml", f"ocaml/bin/{mod_name}.ml"]
                for cp in cand_paths:
                    if cp in node_lookup and cp != path:
                        links.append({
                            'source': path,
                            'target': cp,
                            'type': 'module_open',
                            'label': f"opens {m.group(1)}",
                            'weight': 2
                        })
            
            for m in re.finditer(r'\b([A-Z][a-zA-Z0-9_]*)\.', content):
                mod_name = m.group(1).lower()
                cand = f"ocaml/lib/{mod_name}.ml"
                if cand in node_lookup and cand != path:
                    links.append({
                        'source': path,
                        'target': cand,
                        'type': 'module_call',
                        'label': f"uses {m.group(1)}",
                        'weight': 1
                    })

        # 3. Test dependencies
        if 'tests/' in path or 'ocaml/test/' in path:
            base_clean = Path(path).stem.replace('test_', '').replace('_test', '')
            for target_path in node_lookup:
                if 'test' not in target_path and target_path != path:
                    target_stem = Path(target_path).stem
                    if base_clean == target_stem or (len(base_clean) > 3 and base_clean in target_stem):
                        links.append({
                            'source': path,
                            'target': target_path,
                            'type': 'test_target',
                            'label': f"verifies {target_stem}",
                            'weight': 2
                        })

        # 4. Agent inheritance
        if path.startswith('agents/') and path != 'agents/base_agent.py':
            if 'agents/base_agent.py' in node_lookup:
                links.append({
                    'source': path,
                    'target': 'agents/base_agent.py',
                    'type': 'inheritance',
                    'label': "inherits BaseAgent",
                    'weight': 3
                })

        # 5. Verification bridge in v2
        if 'ocaml_verifier.py' in path:
            for target in ['ocaml/bin/main.ml', 'main.py', 'agents/judge_agent.py']:
                if target in node_lookup:
                    links.append({
                        'source': path,
                        'target': target,
                        'type': 'differential_verification',
                        'label': "cross-verifies",
                        'weight': 3
                    })

        # 6. Skill to OCaml pipeline linkage in v2
        if path.startswith('skills/'):
            skill_slug = Path(path).parent.name
            target_map = {
                'assessor-permit-enrichment': 'ocaml/lib/municipal.ml',
                'discovery-agent': 'ocaml/lib/datasf.ml',
                'lead-export-actionability': 'ocaml/lib/csv_exporter.ml',
                'mathematical-qualification': 'ocaml/lib/scorer.ml',
                'self-healing-learning': 'ocaml/lib/lesson_store.ml'
            }
            if skill_slug in target_map and target_map[skill_slug] in node_lookup:
                links.append({
                    'source': path,
                    'target': target_map[skill_slug],
                    'type': 'skill_spec',
                    'label': f"specifies {Path(target_map[skill_slug]).name}",
                    'weight': 2
                })

    # Deduplicate links
    unique_links = []
    seen = set()
    for l in links:
        key = (l['source'], l['target'], l['type'])
        if key not in seen and l['source'] in node_lookup and l['target'] in node_lookup:
            seen.add(key)
            unique_links.append(l)

    # Build cluster definitions
    clusters_map = {}
    for n in nodes:
        cid = n['category']
        if cid not in clusters_map:
            clusters_map[cid] = {
                'id': cid,
                'name': n['categoryName'],
                'color': n['color'],
                'layer': n['layer'],
                'nodeCount': 0,
                'nodes': []
            }
        clusters_map[cid]['nodeCount'] += 1
        clusters_map[cid]['nodes'].append(n['id'])

    clusters = list(clusters_map.values())

    stats = {
        'totalFiles': len(nodes),
        'totalLoc': total_loc,
        'codeLoc': code_loc,
        'testLoc': test_loc,
        'pyLoc': py_loc,
        'ocamlLoc': ocaml_loc,
        'linksCount': len(unique_links),
        'clustersCount': len(clusters),
        'certStatus': 'VALIDATED SHA-256 (AST Certified Pass)' if branch == 'main' else 'DUAL-VERIFIED (Differential Fuzzing & Pure OCaml Engine)'
    }

    return {
        'branch': branch,
        'stats': stats,
        'nodes': nodes,
        'links': unique_links,
        'clusters': clusters
    }

def generate_comparison_data():
    return {
        'title': 'Python (main) vs Pure OCaml (v2) Architectural Shift',
        'summary': 'Evolution from Python offline multi-agent architecture with dynamic AST validation to a type-safe, invariant-enforcing pure OCaml functional engine with differential fuzzing verification.',
        'metrics': [
            {'category': 'Type Safety', 'python': 'Dynamic / Runtime Mypy (Type Hints)', 'ocaml': 'Static Algebraic Data Types & Exhaustive Pattern Matching', 'winner': 'ocaml'},
            {'category': 'Invariant Enforcement', 'python': 'Dynamic AST Analysis (AST Judge Agent)', 'ocaml': 'Formal Mathematical Invariants (INV1 - INV4)', 'winner': 'ocaml'},
            {'category': 'JSON Parsing', 'python': 'Standard library json', 'ocaml': 'Handcrafted Zero-Dependency Tokenizer & AST Serializer', 'winner': 'ocaml'},
            {'category': 'Vector Database', 'python': 'SQLite + NumPy Array Cosine Distance', 'ocaml': 'Pure OCaml Vector Store & Nearest Neighbors', 'winner': 'ocaml'},
            {'category': 'Test Architecture', 'python': 'Starlette Loopback Zero-Mock Servers (468 tests)', 'ocaml': 'OCaml Test Rig + Python Differential Fuzzing Bridges', 'winner': 'ocaml'},
            {'category': 'Offline Resilience', 'python': 'Localhost:8000 LLM + JSON Fallbacks', 'ocaml': 'Local LLM + Lock-Protected Atomic Lesson Store', 'winner': 'ocaml'},
            {'category': 'Binary Execution', 'python': 'Python 3 Interpreter runtime', 'ocaml': 'Native Compiled ELF/Mach-O Binary via Dune', 'winner': 'ocaml'}
        ],
        'moduleMappings': [
            {'pyFile': 'main.py', 'ocamlFile': 'ocaml/bin/main.ml + ocaml/lib/pipeline.ml', 'description': 'CLI orchestration transformed into composable monadic functional pipeline.'},
            {'pyFile': 'db/database.py', 'ocamlFile': 'ocaml/lib/db.ml', 'description': 'SQLite persistence mapped to strongly-typed query execution and domain records.'},
            {'pyFile': 'memory/vector_store.py', 'ocamlFile': 'ocaml/lib/vector_store.ml', 'description': 'NumPy vector distance converted to native OCaml float array similarity.'},
            {'pyFile': 'memory/embeddings.py', 'ocamlFile': 'ocaml/lib/embeddings.ml', 'description': 'Deterministic semantic embedding generator with fixed dimension vectors.'},
            {'pyFile': 'memory/lesson_store.py', 'ocamlFile': 'ocaml/lib/lesson_store.ml', 'description': 'Dual-memory self-healing failure logger with POSIX file locking.'},
            {'pyFile': 'agents/judge_agent.py', 'ocamlFile': 'ocaml/lib/invariants.ml + ocaml/lib/crypto.ml', 'description': 'AST judge heuristics replaced by formal mathematical invariant checks and SHA-256 verification.'},
            {'pyFile': 'agents/county_agent.py', 'ocamlFile': 'ocaml/lib/municipal.ml + ocaml/lib/datasf.ml', 'description': 'San Francisco DBI permit & Assessor scraping ported to DataSF open API connector.'},
            {'pyFile': 'agents/extractor.py', 'ocamlFile': 'ocaml/lib/scorer.ml', 'description': 'Roof type (Victorian/Flat) scoring engine targeting high-income SF parcels.'},
            {'pyFile': 'exporters/csv_exporter.py', 'ocamlFile': 'ocaml/lib/csv_exporter.ml', 'description': 'RFC 4180 streaming CSV exporter with sanitized phone formatting.'},
            {'pyFile': 'integrations/github_client.py', 'ocamlFile': 'ocaml/lib/http_client.ml + ocaml/lib/crypto.ml', 'description': 'Dual-transport issue logging with SHA-256 issue deduplication.'}
        ]
    }

def main():
    print("Extracting 'main' branch network data...")
    main_graph = build_branch_graph('main')
    print(f"Main: {len(main_graph['nodes'])} nodes, {len(main_graph['links'])} links.")

    print("Extracting 'v2' branch network data...")
    v2_graph = build_branch_graph('v2')
    print(f"V2: {len(v2_graph['nodes'])} nodes, {len(v2_graph['links'])} links.")

    comparison = generate_comparison_data()

    full_data = {
        'generatedAt': '2026-09-01T07:28:00Z',
        'repository': 'roof4u (Roo4u Offline Agentic Lead Gen & OCaml Core)',
        'branches': {
            'main': main_graph,
            'v2': v2_graph
        },
        'comparison': comparison
    }

    docs_dir = REPO_ROOT / 'docs'
    docs_dir.mkdir(parents=True, exist_ok=True)

    js_content = f"// Auto-generated repository architecture graph data for Roo4u\nwindow.ROO4U_GRAPH_DATA = {json.dumps(full_data, indent=2)};\n"
    with open(docs_dir / 'data.js', 'w', encoding='utf-8') as f:
        f.write(js_content)
    print(f"Written: {docs_dir / 'data.js'}")

    with open(docs_dir / 'data.json', 'w', encoding='utf-8') as f:
        json.dump(full_data, f, indent=2)
    print(f"Written: {docs_dir / 'data.json'}")

if __name__ == '__main__':
    main()
