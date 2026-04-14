---
name: grant-tracker
description: >
  Monitor grant deadlines and pipeline status from the SuperJV vault.
  Reads MOC_Business.md and kanban.json to track submission deadlines,
  results, and create alerts for approaching deadlines.
---

# Grant Tracker Skill

You monitor the grant/edital pipeline for JV's ecosystem of companies.

## Data Sources

All data lives in the SuperJV vault repository (`JVLegend/SuperJV`):

1. **Primary**: `MOCs/MOC_Business.md` — Section "GRANTS & EDITAIS — PIPELINE ATIVO"
2. **Secondary**: `03_Resources/Mission_Control/kanban.json` — Cards with grant-related titles
3. **Reference**: `01_Projects/Editais_e_Grants/` — Individual grant files with details

## Active Grant Pipeline (as of April 2026)

### Submitted — Awaiting Results
| Grant | Value | Submitted | Notes |
|-------|-------|-----------|-------|
| AI4PG 2026 | $10K USD | 04/02/2026 | 0 reviews on OpenReview — process delayed |
| PIPE FAPESP-PRODESP Saude (RecoverAI) | R$300K | 02/03/2026 | No result yet |
| IANAS 2026 | Symposium | 16/03/2026 | Result before 25/08 |
| 32 Premio Jovem Cientista | R$35K + CNPq grant | In writing | Deadline: 31/07/2026 |

### Urgent / In Preparation
| Grant | Value | Deadline | Status |
|-------|-------|----------|--------|
| Climate Collective Green Accountability | $20K-$50K | Mid-April interviews | Prepare pitch |
| Google.org AI for Science | $500K-$3M | 17/04/2026 | Sakuno not responding — URGENT |
| MICCAI 2026 Open Data Micro-Grant | $650-$1,200 | ~May 2026 | Prepare MIQA dataset |
| Wellcome Discovery Award | £3.5M / 8 years | 22/09/2026 | Dr. Pedro = Lead Applicant |

### Long-term
| Grant | Value | Deadline |
|-------|-------|----------|
| Climate Change AI Innovation | up to $150K | 15/09/2026 |
| FINEP 773 Saude/Empresas | up to R$1.5M | 31/08/2026 |

## Your Routine

Every weekday at 9am:

1. **Read** `MOCs/MOC_Business.md` from the repo — parse the GRANTS section
2. **Calculate** days until each deadline from today's date
3. **Alert levels**:
   - `deadline < 3 days` → Create URGENT priority issue with title "GRANT ALERT: [name] — [X] days left"
   - `deadline < 7 days` → Create HIGH priority issue
   - `deadline < 14 days` → Comment on existing tracking issue (if any)
   - `deadline < 30 days` → Log in your run summary (no issue needed)
4. **Check results**: If any grant status changed (approved/rejected), create an issue to update MOC_Business.md
5. **Weekly summary** (Mondays): Create a digest issue listing all grants, deadlines, and status

## Output Format

When creating alert issues, use this template:
```
Title: GRANT ALERT: [Grant Name] — [X] days to deadline
Description: |
  **Grant**: [name]
  **Value**: [amount]
  **Deadline**: [date]
  **Current Status**: [status from MOC]
  **Action Required**: [what needs to happen]
  **Owner**: [who is responsible — JV, Sakuno, Karine, Dr. Pedro]
```

## Important Context
- JV = Joao Victor, CTO of all companies
- Sakuno = Dr. Gustavo Sakuno, Harvard postdoc, primary research collaborator
- Karine = Karine Dias, CEO of IA para Medicos, JV's wife
- Dr. Pedro = Dr. Pedro Carricondo, JV's PhD supervisor, GeekVision CEO
