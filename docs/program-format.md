# Program format

Training programs live in [`resources/programs/programs.json`](../resources/programs/programs.json).
They are compiled into the app, so after editing the file, rebuild and reinstall (`just run`).

## Structure

```
file     { "format": 1, "folders": [ folder, ... ] }
folder   { "name": "...", "source": "...", "programs": [ program, ... ] }
program  { "name": "...", "description": "...", "steps": [ node, ... ] }
node     step | repeat
```

`source` is an optional note for humans; the app ignores it.

`description` is required. It is the first screen when a program is opened on the watch (what the session is,
how to prepare), shown before the get-ready countdown. Keep it to a few sentences; it is word-wrapped and
scrolls with UP/DOWN when it does not fit.

### step

A single timed block.

| key     | required | meaning |
|---------|----------|---------|
| `type`  | yes      | `"hang"` (green) or `"rest"` (blue) |
| `sec`   | yes      | duration in seconds, integer >= 1 |
| `label` | no       | replaces the title on screen, e.g. `"SET REST"` instead of `"REST"` |

### repeat

Runs `do` several times.

| key       | required | meaning |
|-----------|----------|---------|
| `repeat`  | yes      | number of times, integer >= 1 |
| `do`      | yes      | list of nodes to run each time |
| `between` | no       | list of nodes run **between** repetitions, not after the last one |
| `name`    | no       | shows progress on screen, e.g. `"Rep"` gives `Rep 2/4` |

Repeats nest up to 4 levels deep. With several named repeats, the outermost comes first on screen:
`Set 2/3   Rep 4/4`.

`between` is what turns "hang, rest, hang, rest" into "hang, rest, hang" without a trailing rest.
A 10-second get-ready countdown is added before every program automatically.

## Example

"10 second hang, 30 second rest, 4 reps, 2 minute rest, 3 sets":

```json
{
  "name": "Week 1",
  "description": "10 s hang, 30 s rest, 4 reps per set, 3 sets, 2 min set rest.",
  "steps": [
    {
      "repeat": 3, "name": "Set",
      "do": [
        { "repeat": 4, "name": "Rep",
          "do":      [ { "type": "hang", "sec": 10 } ],
          "between": [ { "type": "rest", "sec": 30 } ] }
      ],
      "between": [ { "type": "rest", "sec": 120, "label": "SET REST" } ]
    }
  ]
}
```

Steps do not have to sit inside a repeat. A max-hang program with different loads could be a plain list:

```json
{ "name": "Max hangs", "description": "Three max hangs with long rests.", "steps": [
    { "type": "hang", "sec": 10 }, { "type": "rest", "sec": 180 },
    { "type": "hang", "sec": 10 }
] }
```

## Checking your changes

```sh
python3 scripts/check_programs.py                    # validate, one line per program
python3 scripts/check_programs.py --show "Week 1"    # print every step of a program
```

`just build` runs the validation first, so a malformed file fails the build instead of crashing on the watch.
