# Valkyrious Revive — Game Rules

## Overview
A 1v1 real-time strategy card game. Two players deploy cards onto a shared battlefield, capture territory, and win by advancing a card into the opponent's base area.

---

## Board

### Physical Layout (Logic Only — not shown in-game)
```
  ┌──────────────────────────────┐
  │  ENEMY BASE  (logic trigger) │  ← hidden, not rendered
  ├─────────┬─────────┬──────────┤
  │  R1C1   │  R1C2   │  R1C3   │
  ├─────────┼─────────┼──────────┤
  │  R2C1   │  R2C2   │  R2C3   │
  ├─────────┼─────────┼──────────┤
  │  R3C1   │  R3C2   │  R3C3   │
  ├─────────┴─────────┴──────────┤
  │  OWNER BASE  (logic trigger) │  ← hidden, not rendered
  └──────────────────────────────┘
```

- **Only the 3×3 grid (R1–R3) is rendered on screen** — base zones are invisible.
- Win condition is triggered internally when a card's next step would enter a base zone.

### Player Perspective
Each player always sees the board **from their own side** — their deploy row is always at the **bottom of the screen**:

```
  Owner's screen:        Enemy's screen:
  ┌─────────────┐        ┌─────────────┐
  │ R1 (enemy)  │        │ R3 (owner)  │  ← opponent row at top
  │ R2 (middle) │        │ R2 (middle) │
  │ R3 (self)   │        │ R1 (self)   │  ← own row at bottom
  └─────────────┘        └─────────────┘
```

### Visibility Rules

| Element | Own screen | Opponent screen |
|---------|-----------|-----------------|
| Own hand cards | ✓ Full view | ✗ Hidden (card backs only) |
| Own cost bar (value + fill level) | ✓ Yes | ✓ Yes |
| Opponent cost bar (value + fill level) | ✓ Yes | ✓ Yes |
| All cards on field | ✓ Yes | ✓ Yes |
| Deploy marks on cells | ✓ Yes | ✓ Yes |

### Cell Mark Defaults
- Each cell can hold a **deploy mark** from owner, enemy, or both simultaneously
- **R1** starts with enemy mark; **R3** starts with owner mark; **R2** starts with no mark

---

## Deck & Hand

| Attribute | Value |
|-----------|-------|
| Cards in hand | 4 |
| Cards in deck | 4 |
| **Total cards** | **8** |

Cards are numbered 1–8. At game start:
- **Hand**: cards 1, 2, 3, 4
- **Deck**: cards 5, 6, 7, 8

### Draw Mechanic
When a card is played from hand, the **top card of the deck fills that hand slot immediately**, and the **played card is added to the bottom of the deck**.

> **The total card pool is always exactly 8** — cards cycle between hand, deck, and field. The deck never drops below or exceeds 4 cards when the hand is full; the full circuit is: Hand (4) + Deck (4) = 8 at all times (excluding cards currently on the field).

**Example sequence:**
```
Initial:  Hand [1, 2, 3, 4]   Deck [5, 6, 7, 8]

Play card 2 →
          Hand [1, 5, 3, 4]   Deck [6, 7, 8, 2]   Field: {2}

Play card 4 →
          Hand [1, 5, 3, 6]   Deck [7, 8, 2, 4]   Field: {2, 4}
```

- Cards on the field are temporarily removed from the hand/deck pool.
- When a field card is **destroyed**, it is **permanently removed** from the game (does not return to deck).
- The deck shrinks only when field cards are destroyed; it never exceeds its starting size.

---

## Cost System

| Attribute | Value |
|-----------|-------|
| Max cost | 10 |
| Regen rate (0:00–1:30 remaining) | +1 per **3 seconds** |
| Regen rate (1:30–0:00 remaining) | +1 per **1.5 seconds** |
| Starting cost | 0 |

- Cost regenerates automatically in real time.
- When the match timer drops to **1:30**, the regen rate **doubles** (3s → 1.5s per cost).
- Each card has a **cost value**; the player must have enough cost to deploy it.
- Cost is deducted immediately on deployment.

---

## Card Stats

Each card has:
- **ATK** — damage dealt per attack
- **HP** — health points; card is destroyed when HP ≤ 0
- **Cost** — mana required to deploy

---

## Area Capture (Deploy Mark)

Capture is **not** about changing cell color — it means adding a **deploy mark** that allows a player to place cards in that cell.

| Player | Can deploy in | Can capture |
|--------|--------------|-------------|
| Owner | R2, R3 only | R2, R3 only |
| Enemy | R1, R2 only | R1, R2 only |

- Each player is limited to **2 rows adjacent to their own base**.
- A cell can hold **marks from both players simultaneously** — capturing does not remove the opponent's mark.
- A card that **remains in a cell for 4 continuous seconds** adds its owner's deploy mark to that cell.
- Default marks: R1 = enemy mark, R3 = owner mark, R2 = no mark.

---

## Deployment Rules

- A player may only deploy a card into a cell that has **their own deploy mark**.
- A cell must be **empty** (or have a queue slot available, see Card Queuing below) to deploy into.
- Deployment costs the card's cost value from the cost bar.

---

## Card Movement

1. After a card is placed, an **8-second countdown** begins.
2. When the countdown reaches 0 **and no enemy is adjacent**, the card **advances one row** toward the opponent.
   - Owner cards move up: R3 → R2 → R1 → **Enemy Base (WIN)**
   - Enemy cards move down: R1 → R2 → R3 → **Owner Base (WIN)**
3. A card always advances into the **same column**.
4. After advancing, the 8-second countdown restarts.

---



## Combat

### Trigger
Combat is triggered when a card's **countdown reaches 0** and an **enemy card is in an adjacent cell** (up, down, left, right). The card **always chooses to attack** over advancing.

### Attack Resolution
- Both cards deal their ATK as damage to the opponent's HP **simultaneously** (at the moment the attacking card's countdown hits 0).
- Cards with HP ≤ 0 are **destroyed** and removed from the field.
- Surviving cards **retain their remaining HP**.

### Post-Combat Countdown
| Outcome | Owner countdown | Enemy countdown |
|---------|----------------|-----------------|
| Owner wins (enemy destroyed) | Restart **8s** | — destroyed |
| Enemy wins (owner destroyed) | — destroyed | **Continue** remaining time |
| Both survive | Restart **8s** | **Continue** remaining time |
| Both destroyed | — | — |

**Example:**
```
State: Enemy card has 3s remaining. Owner card countdown reaches 0.
→ Combat triggers immediately.

  Enemy:  ATK 2 / HP 2
  Owner:  ATK 2 / HP 3

  Enemy HP = 2 − 2 = 0  → DESTROYED
  Owner HP = 3 − 2 = 1  → SURVIVED → restarts 8s countdown
```

```
State: Enemy 3s remaining, Owner countdown reaches 0. Both survive.
  → Enemy continues with 3s remaining
  → Owner restarts with 8s
```

### Attack Directions
- A card checks **all 4 adjacent cells** (up, down, left, right) for enemies.
- If any adjacent cell has an enemy, **attack triggers** when countdown reaches 0.
- **Priority**: attack > advance.

---

## Global Action Pause

Whenever **any action occurs on the field** (card deployed, card moves, combat resolves, or any other field event), the **entire game pauses for 0.5 seconds** before resuming.

- This applies to all timers: card countdowns, cost regen, match timer.
- Both players are affected equally.
- Pause does not stack (simultaneous events share a single 0.5s pause).

---

## Card Queuing

A player may **drag a hand card onto a field cell** that currently contains a card (own or enemy) with **less than 2 seconds remaining** on its countdown. This reserves a queue slot on that cell.

### Queue Rules
- The queued card will deploy into that cell **as soon as it becomes empty** (after the occupying card moves, advances, or is destroyed).
- Cost is **checked at the moment of deployment** — if the player no longer has sufficient cost when the slot opens, the queued card is **auto-cancelled** and returned to hand.
- Multiple cards can be queued on different cells simultaneously, as long as current cost covers all pending deployments.
- A cell can only hold **one queued card per player** at a time.

### Queue Priority (when both players queue for the same cell)
| Situation | Priority |
|-----------|----------|
| One player queues first | First to queue wins |
| Both queue at the same time | **Cell's current mark owner** gets priority |
| Cell has marks from both / neither | Coin flip (random) |

---

## Win Condition

The game ends **immediately** when:
- An **owner card** advances into the **Enemy Base** → **Owner wins**
- An **enemy card** advances into the **Owner Base** → **Enemy wins**

---

## Match Timer & Overtime

- Each match has a **3:00 minute** game clock.
- At **1:30** remaining, cost regen rate doubles.

### When Timer Reaches 0:00 — Overtime
- **No new cards** can be deployed by either player.
- All cards currently on the field **continue acting** (countdown, movement, combat) normally.
- The game continues until one of the following end conditions is met:

| End Condition | Result |
|--------------|--------|
| A card enters the opponent's Base | That card's owner **wins** |
| One side has **0 cards on field** | The other side **wins** |
| Both sides reach **0 cards simultaneously** | **Draw** |

---

## Card Lifecycle Summary

```
Deploy from hand (pay cost)  →  next deck card fills hand slot  →  played card → bottom of deck
    ↓
Placed in own starter row (R3 / R1)
    ↓
[4s] → captures current cell
    ↓
[8s countdown ticking...]
    ↓
Countdown = 0?
 ├─ Adjacent enemy exists? → ATTACK (simultaneous damage)
 │       ├─ Owner survives → restart 8s
 │       ├─ Enemy survives → continue remaining time
 │       └─ Both destroyed → removed from field
 └─ No enemy → ADVANCE one row (same column)
         ├─ Reached opponent Base → GAME OVER (attacker wins)
         └─ Continue in new cell → restart 8s countdown
```

---

## UI Layout (Reference: `docs/ui-reference.png`)

Layout is **portrait** (576×1024). See attached reference image.

```
┌─────────────────────────────────────────┐
│ [💎 7] [Card1][Card2][Card3][Card4]      │  ← Enemy mana + 4 hand cards (faces hidden)
│              [Deployed card: Yosty]      │  ← Enemy field card in R1
├──────────────────────────────────────────┤
│  ┌───────┬───────┬───────┐               │
│  │       │       │       │  ← R1         │
│  ├───────┼───────┼───────┤               │
│  │       │       │  [4▲] │  ← R2  field  │
│  ├───────┼───────┼───────┤               │
│  │       │       │       │  ← R3         │
│  └───────┴───────┴───────┘               │
├──────────────────────────────────────────┤
│  03:00   [CardPreview]                   │  ← Timer + next card preview
│                         (replay only →)  │  ← x1 / ⏸ / ✕ hidden in live play
├──────────────────────────────────────────┤
│ [💎 7] [Card1][Card2][Card3][Card4]      │  ← Owner mana + 4 hand cards (visible)
└─────────────────────────────────────────┘
```

### Replay Controls (Record View Only)
The following controls appear **only when viewing a recorded match replay** — they are **not shown during live gameplay**:

| Button | Function |
|--------|----------|
| `x1` | Playback speed (toggle x1 / x2 / x3) |
| `⏸` | Pause replay |
| `✕` | Exit replay |
