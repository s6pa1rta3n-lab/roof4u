---
name: ocaml-mathematical-lead-qualification
description: Mathematical verification engine compiled in OCaml 5.5.0 providing type-safe invariant verification and deterministic actionability scoring.
---

# OCaml Mathematical Lead Qualification Skill

## 1. Overview
The Mathematical Lead Qualification skill executes the compiled OCaml verification binary (`roof_verif_cli`) to enforce mathematical invariants over lead records, preventing false positives and ensuring actionable leads for roofing contractors.

## 2. Formal Invariants Checked

### Invariant 1: Physical Eligibility ($\text{INV}_1$)
$$\text{RoofType} \in \{\text{Victorian}, \text{Flat}, \text{Mansard}\} \land \text{PropertyType} \in \{\text{SingleFamily}, \text{MultiUnit2To4}\}$$

### Invariant 2: Temporal Degradation ($\text{INV}_2$)
$$\text{RoofAge} \ge 15.0 \lor (\text{YearBuilt} \le (\text{CurrentYear} - 30) \land \text{LastRoofPermit} = \text{None})$$

### Invariant 3: Economic Viability ($\text{INV}_3$)
$$\text{AssessedValue} \ge \$1,000,000.00 \land \neg \text{IsHOA} \land \neg \text{IsRental}$$

### Invariant 4: Permit Recency Non-Conflict ($\text{INV}_4$)
$$\forall p \in \text{Permits}, p.\text{is\_roof\_replacement} \implies (\text{CurrentYear} - p.\text{year}) \ge 15$$

## 3. Deterministic Actionability Scoring Formula

The total lead score $S(L) \in [0.0, 100.0]$ is computed as:
$$S(L) = C_{\text{age}}(L) + C_{\text{val}}(L) + C_{\text{type}}(L)$$

Where:
- **Age Component ($0.0 \le C_{\text{age}} \le 40.0$)**:
  $$C_{\text{age}}(L) = 40.0 \times \min\left(1.0, \frac{\text{RoofAge}}{30.0}\right)$$
- **Value Component ($0.0 \le C_{\text{val}} \le 35.0$)**:
  $$C_{\text{val}}(L) = 15.0 + 20.0 \times \min\left(1.0, \max\left(0.0, \frac{\text{AssessedValue} - \$1,000,000.00}{\$4,000,000.00}\right)\right)$$
- **Architectural Type Component ($10.0 \le C_{\text{type}} \le 25.0$)**:
  $$C_{\text{type}}(L) = \begin{cases}
  25.0 & \text{if Victorian Single-Family} \\
  24.0 & \text{if Mansard Single-Family} \\
  22.0 & \text{if Flat Single-Family} \\
  20.0 & \text{if Victorian 2-4 Unit} \\
  18.0 & \text{if Flat 2-4 Unit} \\
  10.0 & \text{otherwise}
  \end{cases}$$

## 4. Execution & Certification
- Invocation: `ocaml/_build/default/bin/main.exe --json '<lead_json>'`
- Returns a signed JSON proof certificate containing status (`QUALIFIED` or `DISQUALIFIED`), component scores, invariant audit trail, and proof ID.
