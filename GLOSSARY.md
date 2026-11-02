# Coin Collector

A small 2D platformer in which the player collects coins in a one-screen level while avoiding traps, and whose every action is recorded as an analyzable event stream.

## Language

**Session**:
One run of the game program, from launch to closing the window. Contains one or more Rounds.
_Avoid_: Run, execution, game

**Round**:
One play of the level, from its start until every coin has been collected or the window is closed. A Round has no time limit and can contain several Attempts.
_Avoid_: Match, game, partida

**Attempt**:
One go at the level inside a Round. A new Attempt begins at the start of the Round and after every Death.
_Avoid_: Life, try

**Level**:
The layout of Solids, Traps and Coins that every Attempt of a Round plays through. Level 0 is hand-made; every other Level is generated from a Seed.
_Avoid_: Map, stage, fase

**Seed**:
The integer that determines a generated Level. The same Seed always gives the same Level, and 0 stands for the hand-made one.
_Avoid_: Level id, random number

**Player**:
The square the user moves and makes jump.
_Avoid_: Character, avatar

**Coin**:
A collectible at a fixed place in its Level. A Round is complete when all of them have been collected in a single Attempt.
_Avoid_: Pickup, token

**Solid**:
A part of the Level the Player can stand on and cannot pass through.
_Avoid_: Wall, obstacle, platform

**Trap**:
A fixed hazard that kills the Player on contact.
_Avoid_: Spike, enemy, obstacle

**Pit**:
A gap in the ground. Falling below the Level kills the Player.
_Avoid_: Hole, void

**Death**:
The Player touching a Trap or falling into a Pit. It ends the Attempt and starts a new one.
_Avoid_: Game over, hit

**Event**:
One recorded fact about what happened in a Session, with a type and a payload.
_Avoid_: Log entry, record, action

**Event stream**:
The ordered sequence of Events produced by Sessions, stored one Event per line.
_Avoid_: Log file, dataset

**Schema**:
The definition of which Event types exist and which fields each one carries. Versioned by `schema_version`.
_Avoid_: Format, spec
