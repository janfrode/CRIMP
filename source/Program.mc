// CRIMP, a hangboard timer for Garmin watches
// Copyright (C) 2026 Jan-Frode Myklebust
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version. It is
// distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.Lang;
import Toybox.WatchUi;

// Where a step sits inside a named repeat, e.g. "Rep 2/4".
class Counter {
    var name as String;
    var index as Number;
    var total as Number;

    function initialize(name as String, index as Number, total as Number) {
        self.name = name;
        self.index = index;
        self.total = total;
    }
}

// One hangboard workout, flattened to a list of timed steps.
class Program {
    var name as String;
    var steps as Array<WorkoutStep>;

    function initialize(name as String, steps as Array<WorkoutStep>) {
        self.name = name;
        self.steps = steps;
    }

    function summary() as String {
        var hangs = 0;
        var totalSec = 0;
        for (var i = 0; i < steps.size(); i++) {
            totalSec += steps[i].durSec;
            if (steps[i].phase == PHASE_HANG) {
                hangs++;
            }
        }
        return hangs + " hangs, " + ((totalSec + 30) / 60) + " min";
    }
}

// A named group of programs, shown as a "folder" in the top-level menu.
class ProgramFolder {
    var name as String;
    var programs as Array<Program>;

    function initialize(name as String, programs as Array<Program>) {
        self.name = name;
        self.programs = programs;
    }
}

// Loads programs from resources/programs/programs.json.
// The format is documented in docs/program-format.md and checked by
// scripts/check_programs.py (run automatically by `just build`).
module Programs {
    function folders() as Array<ProgramFolder> {
        var data = WatchUi.loadResource(Rez.JsonData.Programs) as Dictionary;
        var result = [] as Array<ProgramFolder>;
        var folderList = data["folders"] as Array;
        for (var f = 0; f < folderList.size(); f++) {
            var folder = folderList[f] as Dictionary;
            var programs = [] as Array<Program>;
            var programList = folder["programs"] as Array;
            for (var p = 0; p < programList.size(); p++) {
                var prog = programList[p] as Dictionary;
                var steps = [] as Array<WorkoutStep>;
                expand(prog["steps"] as Array, [] as Array<Counter>, steps);
                programs.add(new Program(prog["name"] as String, steps));
            }
            result.add(new ProgramFolder(folder["name"] as String, programs));
        }
        return result;
    }

    // Walks the step tree and appends plain steps to `out` in running order.
    // `counters` holds the enclosing repeats, innermost first.
    function expand(nodes as Array, counters as Array<Counter>, out as Array<WorkoutStep>) as Void {
        for (var i = 0; i < nodes.size(); i++) {
            var node = nodes[i] as Dictionary;
            if (node.hasKey("repeat")) {
                var total = node["repeat"] as Number;
                var name = node["name"] as String or Null;
                for (var n = 1; n <= total; n++) {
                    var inner = counters;
                    if (name != null) {
                        inner = [new Counter(name, n, total)] as Array<Counter>;
                        inner.addAll(counters);
                    }
                    expand(node["do"] as Array, inner, out);
                    if (n < total && node.hasKey("between")) {
                        expand(node["between"] as Array, inner, out);
                    }
                }
            } else {
                var phase = (node["type"] as String).equals("hang") ? PHASE_HANG : PHASE_REST;
                out.add(new WorkoutStep(phase, node["sec"] as Number, node["label"] as String or Null, counters));
            }
        }
    }
}
