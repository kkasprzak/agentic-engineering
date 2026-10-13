#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/adr
cat > docs/adr/0009-adopt-kafka.md <<'ADR'
---
status: "rejected"
date: 2025-01-22
decision-makers: Bo Larsen
consulted: platform guild
informed:
---

# Adopt Kafka for asynchronous messaging

## Context and Problem Statement

Two services needed to hand work to each other without a synchronous call, and the question was
whether to bring in a broker or keep using the outbox table we already had.

## Decision Drivers

* nobody on the team had run Kafka in production
* the existing outbox was handling the volume we had

## Considered Options

* adopt Kafka
* keep the database outbox

## Decision Outcome

Chosen option: "keep the database outbox", because the volume did not justify an operational
dependency nobody on the team had run before. Kafka is not adopted.

### Consequences

* Good, because no new infrastructure to operate
* Bad, because a genuine fan-out case later has no good answer
ADR
