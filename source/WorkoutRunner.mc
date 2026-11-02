// CRIMP, a hangboard timer for Garmin watches
// Copyright (C) 2026 Jan-Frode Myklebust
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version. It is
// distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

enum {
    PHASE_PREP,
    PHASE_HANG,
    PHASE_REST,
    PHASE_DONE
}

const PREP_SEC = 10;
const WARN_SEC = 3;
const TICK_MS = 200;

class WorkoutStep {
    var phase as Number;
    var durSec as Number;
    var label as String or Null;        // overrides the default phase title
    var counters as Array<Counter>;     // enclosing named repeats, innermost first

    function initialize(phase as Number, durSec as Number, label as String or Null, counters as Array<Counter>) {
        self.phase = phase;
        self.durSec = durSec;
        self.label = label;
        self.counters = counters;
    }

    // "Rep 2/4   Set 1/3" (outermost first); empty if the step is not inside a named repeat.
    function progressText() as String {
        var text = "";
        for (var i = counters.size() - 1; i >= 0; i--) {
            text += counters[i].name + " " + counters[i].index + "/" + counters[i].total;
            if (i > 0) {
                text += "   ";
            }
        }
        return text;
    }

    function title() as String {
        if (label != null) {
            return label;
        }
        switch (phase) {
            case PHASE_HANG:
                return "HANG";
            case PHASE_REST:
                return "REST";
            case PHASE_PREP:
                return "GET READY";
            default:
                return "";
        }
    }
}

// Runs a Program as a flat list of timed steps. Time is measured with
// System.getTimer() so the countdown does not drift with timer jitter.
class WorkoutRunner {
    var program as Program;
    var steps as Array<WorkoutStep>;
    var index as Number = 0;

    private var _session as ActivityRecording.Session or Null = null;
    private var _timer as Timer.Timer;
    private var _stepStartMs as Number = 0;
    private var _paused as Boolean = false;
    private var _pausedRemainingMs as Number = 0;
    private var _lastWarnSec as Number = -1;

    function initialize(program as Program) {
        self.program = program;
        steps = buildSteps(program);
        _timer = new Timer.Timer();
    }

    // Program steps with a get-ready countdown in front and a DONE marker at the end.
    private function buildSteps(p as Program) as Array<WorkoutStep> {
        var no = [] as Array<Counter>;
        var list = [new WorkoutStep(PHASE_PREP, PREP_SEC, null, no)] as Array<WorkoutStep>;
        list.addAll(p.steps);
        list.add(new WorkoutStep(PHASE_DONE, 0, null, no));
        return list;
    }

    function start() as Void {
        startRecording();
        beginStep(0, false);
        _timer.start(method(:onTick), TICK_MS, true);
    }

    // Leaves the workout. A finished workout is already saved; quitting early saves
    // what was done so far, unless the get-ready countdown was never passed.
    function stop() as Void {
        _timer.stop();
        stopRecording(index > 0);
    }

    private function startRecording() as Void {
        if (_session == null && ActivityRecording has :createSession) {
            _session = ActivityRecording.createSession({
                :name => program.name,
                :sport => Activity.SPORT_TRAINING,
                :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
            });
            _session.start();
        }
    }

    private function stopRecording(save as Boolean) as Void {
        var session = _session;
        if (session != null) {
            _session = null;
            if (session.isRecording()) {
                session.stop();
            }
            if (save) {
                session.save();
            } else {
                session.discard();
            }
        }
    }

    function currentStep() as WorkoutStep {
        return steps[index];
    }

    function nextStep() as WorkoutStep or Null {
        return (index + 1 < steps.size()) ? steps[index + 1] : null;
    }

    function isDone() as Boolean {
        return currentStep().phase == PHASE_DONE;
    }

    function isPaused() as Boolean {
        return _paused;
    }

    // Milliseconds left in the current step.
    function remainingMs() as Number {
        if (isDone()) {
            return 0;
        }
        if (_paused) {
            return _pausedRemainingMs;
        }
        var rem = currentStep().durSec * 1000 - (System.getTimer() - _stepStartMs);
        return rem > 0 ? rem : 0;
    }

    // Whole seconds to display (rounded up so 0 only shows at the very end).
    function remainingSec() as Number {
        return (remainingMs() + 999) / 1000;
    }

    function togglePause() as Void {
        if (isDone()) {
            return;
        }
        if (_paused) {
            _stepStartMs = System.getTimer() - (currentStep().durSec * 1000 - _pausedRemainingMs);
            _paused = false;
            if (_session != null) {
                _session.start();
            }
        } else {
            _pausedRemainingMs = remainingMs();
            _paused = true;
            if (_session != null) {
                _session.stop();
            }
        }
    }

    function skipForward() as Void {
        if (!isDone()) {
            beginStep(index + 1, true);
        }
    }

    function skipBack() as Void {
        // Restart the current step, or go to the previous one if it just began.
        var elapsedMs = currentStep().durSec * 1000 - remainingMs();
        var target = (elapsedMs < 2000 && index > 0) ? index - 1 : index;
        beginStep(target, true);
    }

    function onTick() as Void {
        if (!_paused && !isDone()) {
            var rem = remainingMs();
            if (rem <= 0) {
                // Carry over any overshoot so steps stay aligned with wall time.
                var overshoot = System.getTimer() - _stepStartMs - currentStep().durSec * 1000;
                beginStep(index + 1, true);
                if (!isDone() && overshoot > 0 && overshoot < 1000) {
                    _stepStartMs -= overshoot;
                }
            } else {
                warnIfNeeded();
            }
        }
        WatchUi.requestUpdate();
    }

    private function beginStep(newIndex as Number, alert as Boolean) as Void {
        index = newIndex;
        _stepStartMs = System.getTimer();
        if (_paused && _session != null && !isDone()) {
            _session.start();   // skipping while paused resumes the clock, so resume recording too
        }
        _paused = false;
        _lastWarnSec = -1;
        if (isDone()) {
            _timer.stop();
            // Save as soon as the workout finishes, not when the user leaves the screen.
            stopRecording(true);
        } else if (currentStep().phase == PHASE_HANG && _session != null) {
            _session.addLap();   // a new lap at the start of every hang
        }
        if (alert) {
            signalPhaseStart(currentStep().phase);
        }
    }

    private function warnIfNeeded() as Void {
        var sec = remainingSec();
        if (sec <= WARN_SEC && sec >= 1 && sec != _lastWarnSec) {
            _lastWarnSec = sec;
            beep(Attention.TONE_LOUD_BEEP);
            buzz(40, 100);
        }
    }

    private function signalPhaseStart(phase as Number) as Void {
        if (phase == PHASE_HANG) {
            beep(Attention.TONE_START);
            buzz(100, 600);
        } else if (phase == PHASE_DONE) {
            beep(Attention.TONE_SUCCESS);
            buzz(100, 1000);
        } else {
            beep(Attention.TONE_STOP);
            buzz(60, 300);
        }
    }

    private function beep(tone as Attention.Tone) as Void {
        if (Attention has :playTone) {
            Attention.playTone(tone);
        }
    }

    private function buzz(strength as Number, ms as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(strength, ms)]);
        }
    }
}
