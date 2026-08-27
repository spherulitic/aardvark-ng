# .TOU Tournament File Format

A human-readable specification of the `.tou` tournament file format as read by
`scripts/migrate.pl` and `scripts/correct_and_verify.pl`. This document
describes the format as the code actually parses it today, including the
quirks. If the spec and the code disagree, the code is the bug — change one and
update the other.

Real examples throughout are taken from the fixtures under
`test/tou/aardvark/2020/USA/`.

---

## 1. Overall file layout

A `.tou` file has this structure:

```
<tournament header line>          (line 1)
*<division name>                  (e.g. *C, *D, *A, *PREMIER)
0                                 (ignored sentinel line)
<player row 1>
<player row 2>
...
<player row N>
*<division name>
0
<player row 1>
...
*** END OF FILE ***
```

### 1.1 Tournament header (line 1)

The first line carries the tournament date and name. It is matched with:

```
^\*.(\d\d).(\d\d).(\d\d\d\d) (.*)$
```

For example:

```
*M20.01.2020 Crescent City Cup
*M05.12.2010 Causeway Challenge
*M23.01.2011 Northern Ireland Championship
```

| capture | meaning |
|---|---|
| `.` after `*` | type marker (e.g. `M`), ignored |
| `(\d\d)` | day |
| `.` | separator — the regex uses `.`, so *any single character* is accepted; convention is `.` |
| `(\d\d)` | month |
| `.` | separator |
| `(\d\d\d\d)` | year |
| `(.*)` | tournament name |

The date is rebuilt as `$3 . $2 . $1` → `YYYYMMDD`. So `20.01.2020` is **20
January 2020** (stored `20200120`), `05.12.2010` is 5 December 2010, and
`23.01.2011` is 23 January 2011.

Caveat: because the separators are matched by `.`, a file that omits a
separator (e.g. `*M2001.2020 ...`) does **not** match and is skipped with
"malformed .tou header". (`test/tou/aardvark/2020/USA/3.tou` is such a file.)

### 1.2 Division headers

A division begins with `*` followed by the division name (the rest of the
line, whitespace-trimmed). Division names may be single letters (`*C`, `*D`)
or words (`*PREMIER`, `*MASTERS`, `*OPEN`). The header line (1.1) is not
treated as a division header.

### 1.3 The `0` line

Each division header is followed by a line containing only a `0`:

```
*C
                                      0
Michael McKenna      2524  26  385 +15 ...
```

The parser ignores this line (it matches neither a division header nor a
player row).

### 1.4 End marker

The file ends with a line containing `END OF FILE`:

```
*** END OF FILE ***
```

### 1.5 Blank lines

Blank lines (and lines with only whitespace) are ignored everywhere.

---

## 2. Player rows

Each player row encodes the player's name followed by one score/opponent pair
per round:

```
<name> <score1> <opp1> <score2> <opp2> ... <scoreN> <oppN>
```

- Round 1 is the **leftmost** pair; round N the **rightmost**. The parser
  reads the pairs from the **end** of the line (last two tokens = round N),
  so the name is whatever tokens remain at the front.
- Each pair is two tokens: `<score> <+opp>` — a score token followed by an
  opponent-number token.
- Opponent numbers are **1-based within the division**, assigned by player-row
  order (first row = 1, second = 2, ...). They are not global.
- The opponent token may carry an optional `+` prefix (`+15`). The `+` is a
  first-move marker ("this player opened"); it appears on exactly one side of
  ~99% of games. `migrate.pl` strips it and never stores it.
- There is **no rating token**: every numeric token belongs to a round pair.
  Verified: every player row in the corpus has an even token count
  (40 tokens = 20 rounds, 90 = 45 rounds, 26 = 13 rounds).
- All player rows in a division must contain the **same** number of round
  pairs; a shorter row is a missed-games error (see §4.4).

Example row (`2.tou`, division C, player 1):

```
Michael McKenna      2524  26  385 +15  398  +9  289  19 2464 +24  ...
```

Round 1: score `2524` (→ 524, a win — see §3), opponent `26`.
Round 2: score `385`, opponent `+15` (opened).
Round 3: score `398`, opponent `+9`.

---

## 3. Score encoding

Each score token is stored with an offset that encodes the game result:

| result | winner stores | loser stores |
|---|---|---|
| win | `real + 2000` | `real` (plain) |
| draw | `real + 1000` | `real + 1000` |
| loss | `real` (plain) | `real` (plain) |

So the stored magnitude of the token carries the result:
**`+2000` offset = win, `+1000` offset = draw, no offset = loss.**

`migrate.pl` decodes a score with (in order):

1. `opp == own number` **or** `score == 1350` → this is a bye; a placeholder
   score of `50` is set (the bye value is then derived from the raw token —
   see §4).
2. else `score > 1900` → `score -= 2000`
3. else `score > 1000` → `score -= 1000`
4. else the score is unchanged.

Win/loss/draw is determined by comparing the two decoded scores: higher wins,
lower loses, equal is a draw (recorded as `+0.5` win and `+0.5` loss for each
player).

Because real Scrabble scores are always below 1000, the bands never collide:
a winning score of 1–999 is stored as 2001–2999 (decodes via `-2000`), a
drawing score of 1–900 as 1001–1900 (decodes via `-1000`), and a losing score
as-is. The draw band boundary (raw `1900`) means a draw must be ≤ 900 to
round-trip — effectively never an issue.

### 3.1 Forfeits (negative scores)

A losing score may be **negative**. It appears in the file either literally
(`-54`) or, when the source tool wrote the `2-<n>` shorthand, as `2000 + score`
so it decodes back to the negative. The validator/corrector rewrites a `2-<n>`
token (e.g. `2-10`) to `1990`, which `migrate.pl` then decodes as `-10`.

Forfeits are the one case where a winning player's score is stored **plain**
rather than with the `+2000` offset (there is no need to offset when the loser
scored negative).

### 3.2 Empirical check

The `+2000`/`+1000`/`+0` rule holds for every non-bye game in the clean
fixtures (≈50,000 games across `2.tou`, `4.tou`, `19.tou`, etc. — zero
violations). The only exceptions are deliberately corrupted fixture variants
and forfeit games.

---

## 4. Byes, forfeits, and missed games

A round counts as a **bye** when any of these is true:

- the opponent number equals the player's own number (self-pairing), or
- the raw score token is `1350`, or
- the opponent's name contains `BYE` after sanitizing (uppercase, strip
  non-A-Z). `RUSSELLBYERS` is the one exempt name. Names like `Bye Player` or
  `ZzBye` are therefore ghosts.

Byes are **unrated**: they never touch a player's rating or win/loss rating
record. Their *value* is decided by the player's **raw** (still-encoded) score
token:

| raw score | meaning | recorded result | spread |
|---|---|---|---|
| `> 2000` | bye-win (unrated win) | `+1` | `0` |
| `< 1000` | bye-loss / **forfeit** (unrated loss) | `-1` | `0` |
| `1000–2000` (incl. `1350`) | half-bye | `0` (plus `+0.5`/`+0.5` win/loss) | `0` |

Note the bye bands use `> 2000` / `< 1000`, which differ slightly from the
game-decode thresholds (`> 1900` / `> 1000`). The leading `2` in a `2xxx`
bye-win is only a **marker**: the trailing digits are never used, and the round
never changes the player's cumulative spread (see §4.5).

For all bye forms, the opponent's score is forced to `0`, the game is stored
`0–0` in the DB, and no `player_results` row is created for the ghost side.

### 4.1 The canonical bye: `1350` with self-pairing

The default/canonical bye is written with **score `1350`** and **opponent =
own player number**:

```
Rik Kennedy           356  23  399 +20  438  16 2410 +17  378  25 2373 +24  340  12 2449  27 1350   7 2504 +26 2406 +13 2417 +21 2449  15
```

Rik Kennedy (player 7) has a bye in round 9: score `1350`, opponent `7`.
`1350` = `1000 + 350`, i.e. it sits in the `+1000` (draw) band, so a plain
1350-bye is worth **0.5**. `Constants::DEFAULT_BYE_SCORE = 1350`, and this is
the only bye form the corrector ever writes and the only form found in clean
real data — so in practice every genuine bye is worth 0.5.

The two other bands are the "proper" indicators for games where the outcome is
explicit: a full bye-win is stored as `2xxx` (e.g. `2050`), a forfeit loss as a
plain/negative value below 1000. All three bands appear in the (corrupt)
`18.tou` ghost games; 1350 is the default used when no proper indicator is
present.

### 4.2 Named ghosts (`*BYE*` players)

A bye can instead be encoded as a real (fake) player row whose name contains
`BYE`, e.g. `18.tou`:

```
Bye Player           2447 +21 1381  20  379  +2 2538  12 2553 +19  ...
```

Any real player paired against the ghost gets a bye. The ghost row must still
reciprocate the pairings (opponent-of-opponent checks apply); the ghost's own
results are computed then dropped (`is_bye = 1`, deleted), the ghost is skipped
when reading the `.STS` metadata, and the ghost's score in any round is
irrelevant (overwritten to `0`).

Trap: a ghost whose name does **not** contain `BYE` (e.g. `Deleted Player` in
`18.tou`) is *not* treated as a bye and produces a real (bogus) game.

### 4.3 Forfeits

A forfeit is a round against a bye/ghost where the player's raw score is below
1000 — recorded as a plain loss (`result -1`). Negative scores are the clearest
sign (`18.tou`):

```
Jason Broersma        338   4  365 +10  352  16 2477 +25 2472 +22 -54  26  317 +12  ...
```

Round 6 for Jason Broersma (player 23): score `-54`, opponent `26` (Jason
Tsang Wai Yin). Jason Tsang wins with plain `284` (no `+2000` offset — see
§3.1). A malformed `2-10` token in the same fixture (`Jeremy Jeffers`, round 6)
is rewritten to `1990` by the corrector and decodes to `-10`.

### 4.4 Missed games

A missed game appears as a player row with **fewer round pairs** than the
division's tournament length — typically a mid-tournament dropout, e.g.
`18.tou` (the division plays 20 rounds):

```
Ifedayo Obisesan      371   1 2389 +13  354  12  45
```

`correct_and_verify.pl` detects the short row, builds a pairing matrix,
and fills the earliest feasible empty slot in each round with a default bye
(`[1350, own number]`), shifting later rounds right if needed. It then
re-validates, corrects pairings, and rewrites the file in place. If the matrix
cannot be completed it reports "cannot fill the division, not enough info" and
the file is skipped.

Invalid opponent numbers (`0`, `> num_players`) and pairings that cannot be
resolved are likewise converted to self-pairing byes by the corrector.

### 4.5 Spread and byes

For ordinary games, each player's cumulative **spread** is the running total of
`decoded own score − decoded opponent score` per round: winning `2xxx` against
`yyy` adds `+xxx`, losing adds the negative margin, and a draw adds `0`
(migrate.pl:1394, 1441).

Bye and forfeit rounds contribute **zero** to the spread, whatever their value.
The code forces the opponent's score to `0` (migrate.pl:1376), skips the ghost
side's spread update entirely (migrate.pl:1392–1395), and resets the player's
score to `0` *before* the accumulator runs (migrate.pl:1436–1441), so the round
adds `0 − 0 = 0`. A `2xxx` bye-win therefore does not add `+xxx`, and a
forfeit does not subtract anything — spread stays a pure point-differential
measure of real games. Ranking breaks ties by `wins + byes`, then spread.

---

## 5. Validation rules enforced by migrate.pl

- The header must match the date regex (§1.1), else "malformed .tou header" and
  the file is skipped.
- A sibling `.STS` (preferred) or `.STA` must exist, else the file is skipped.
  `.ST4` is used only for rating deviations when the `.STS` lacks them.
- Every player row in a division must have the same number of rounds, else
  "inconsistent number of tournament games".
- Round-by-round symmetry: the opponent-of-opponent must equal the player's own
  number in every round, else "opponent of opponent is not player".
- Names must match between the `.tou` and the `.STS`/`.STA` (and `.ST4` when
  used). Names are compared after `sanitize()` (uppercase, strip non-A-Z);
  `*BYE*` ghosts are excluded. Missing names on either side → file skipped.
- A player name may appear only once per division; a player switching divisions
  mid-tournament gets a `WARNING` and is tracked under a
  `<division>-<name>` key.

---

## 6. Companion files (brief)

The `.tou` holds only game data. Player metadata comes from the sibling file:

- **`.STS`** (preferred) / **`.STA`** (legacy): one comma/`|`-delimited record
  per player with country, name, expected wins, start/end rating, and world and
  national ranks (optionally rating deviations). Used to create/update `players`
  rows and tournament results; `*BYE*` names are skipped.
- **`.ST4`**: rating-deviation source when the `.STS` lacks them.

Names throughout are normalized with `sanitize()` (uppercase, strip non-A-Z)
and `make_pretty()` (underscore → space); `inputs/duplicates.txt` maps alternate
spellings to a canonical name.
