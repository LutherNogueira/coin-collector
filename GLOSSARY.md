# Coin Collector

A small 2D game in which the player collects coins while avoiding obstacles, and whose every action is recorded as an analyzable event stream.

## Language

**Session**:
One run of the game program, from launch to closing the window. Contains one or more Rounds.
_Avoid_: Run, execution, game

**Round**:
One play of the arena, from its start until the player dies or time runs out.
_Avoid_: Match, game, level, partida

**Player**:
The square the user moves around the arena.
_Avoid_: Character, avatar

**Coin**:
A collectible that appears at a random place in the arena, one at a time. Collecting it scores a point.
_Avoid_: Pickup, token

**Obstacle**:
A red square that crosses the arena in a straight line and kills the Player on contact.
_Avoid_: Enemy, hazard

**Death**:
The Player touching an Obstacle, which ends the Round immediately.
_Avoid_: Game over, hit

**Event**:
One recorded fact about what happened in a Session, with a type and a payload.
_Avoid_: Log entry, record, action

**Event stream**:
The ordered sequence of Events produced by Sessions, stored one Event per line.
_Avoid_: Log file, dataset

**Schema**:
The definition of which Event types exist and which fields each one carries.
_Avoid_: Format, spec
