#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/adr
cat > docs/adr/0014-event-payload-shape.md <<'ADR'
---
status: "accepted"
date: 2025-03-04
decision-makers: Ana Mirek, Bo Larsen
consulted: platform guild
informed:
---

# Event payload shape

## Context and Problem Statement

Chat events were being published with ad-hoc envelopes: some carried routing hints, some carried a
correlation field, some carried neither. Consumers had to branch on the shape before they could read
the body, and every new producer invented one more variant.

## Decision Drivers

* a consumer should be able to read any chat event without knowing which producer wrote it
* the envelope is read far more often than it is written

## Considered Options

* type and payload only
* type, payload and a free-form metadata map
* a full CloudEvents envelope

## Decision Outcome

Chosen option: "type and payload only", because it is the smallest envelope every consumer can read
unconditionally. Every chat event carries exactly two components: its type and its payload. Anything
a consumer needs in order to act belongs inside the payload, where it is versioned with the event.

### Consequences

* Good, because a consumer branches on one field and never on the envelope shape
* Bad, because cross-cutting concerns have no envelope slot and must be modelled per event
ADR
mkdir -p src/chat
cat > src/chat/ChatMessagePosted.java <<'JAVA'
package chat;

/** Published whenever a participant posts a message in a room. */
public record ChatMessagePosted(String type, MessagePayload payload) {

    public static ChatMessagePosted of(MessagePayload payload) {
        return new ChatMessagePosted("chat.message.posted", payload);
    }
}
JAVA
