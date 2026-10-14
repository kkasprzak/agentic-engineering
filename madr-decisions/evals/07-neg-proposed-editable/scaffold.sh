#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/adr
cat > docs/adr/0011-cache-strategy.md <<'ADR'
---
status: "proposed"
date: 2025-06-09
decision-makers:
consulted:
informed:
---

# Cache strategy for room metadata

## Context and Problem Statement

Room metadata is read on every join and changes rarely. The read path currently hits the database
each time, and the join call is the one users wait on.

## Decision Drivers

* the join call is the latency the user actually feels
* room metadata changes orders of magnitude less often than it is read

## Considered Options

* Redis with a short TTL
* an in-process cache per pod
* no cache, tune the query instead

## Decision Outcome

Chosen option: "{option}", because {justification}.

### Consequences

* Good, because {consequence}
* Bad, because {consequence}
ADR
