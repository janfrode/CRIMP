// CRIMP, a hangboard timer for Garmin watches
// Copyright (C) 2026 Jan-Frode Myklebust
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version. It is
// distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class WorkoutView extends WatchUi.View {
    private var _runner as WorkoutRunner;

    function initialize(runner as WorkoutRunner) {
        View.initialize();
        _runner = runner;
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var step = _runner.currentStep();

        dc.setColor(Graphics.COLOR_WHITE, phaseColor(step.phase));
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        if (step.phase == PHASE_DONE) {
            dc.drawText(w / 2, h * 0.38, Graphics.FONT_LARGE, "DONE", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(w / 2, h * 0.58, Graphics.FONT_SMALL, _runner.program.name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Phase title
        var title = step.title();
        if (_runner.isPaused()) {
            title = "PAUSED";
        }
        dc.drawText(w / 2, h * 0.17, Graphics.FONT_MEDIUM, title, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Big countdown
        dc.drawText(w / 2, h * 0.45, Graphics.FONT_NUMBER_THAI_HOT, formatTime(_runner.remainingSec()), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Progress of the enclosing repeats, e.g. "Set 1/3   Rep 2/4"
        dc.drawText(w / 2, h * 0.70, Graphics.FONT_SMALL, step.progressText(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // What comes next
        var next = _runner.nextStep();
        if (next != null) {
            dc.drawText(w / 2, h * 0.83, Graphics.FONT_TINY, "Next: " + nextLabel(next), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    private function phaseColor(phase as Number) as Number {
        switch (phase) {
            case PHASE_HANG:
                return Graphics.COLOR_DK_GREEN;
            case PHASE_REST:
                return Graphics.COLOR_BLUE;
            case PHASE_PREP:
                return Graphics.COLOR_ORANGE;
            default:
                return Graphics.COLOR_DK_GRAY;
        }
    }

    private function nextLabel(step as WorkoutStep) as String {
        if (step.phase == PHASE_DONE) {
            return "Finish";
        }
        return step.title() + " " + formatTime(step.durSec);
    }

    private function formatTime(totalSec as Number) as String {
        if (totalSec >= 60) {
            return (totalSec / 60) + ":" + (totalSec % 60).format("%02d");
        }
        return totalSec.toString();
    }
}

class WorkoutDelegate extends WatchUi.BehaviorDelegate {
    private var _runner as WorkoutRunner;

    function initialize(runner as WorkoutRunner) {
        BehaviorDelegate.initialize();
        _runner = runner;
    }

    // START / tap: pause and resume (or leave when finished).
    function onSelect() as Boolean {
        if (_runner.isDone()) {
            _runner.stop();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else {
            _runner.togglePause();
            WatchUi.requestUpdate();
        }
        return true;
    }

    // DOWN: skip to the next step.
    function onNextPage() as Boolean {
        _runner.skipForward();
        WatchUi.requestUpdate();
        return true;
    }

    // UP: restart the current step, or go back one if it just began.
    function onPreviousPage() as Boolean {
        _runner.skipBack();
        WatchUi.requestUpdate();
        return true;
    }

    // BACK: confirm before abandoning a running workout.
    function onBack() as Boolean {
        if (_runner.isDone()) {
            _runner.stop();
            return false;
        }
        WatchUi.pushView(
            new WatchUi.Confirmation("Quit workout?"),
            new QuitConfirmDelegate(_runner),
            WatchUi.SLIDE_UP
        );
        return true;
    }
}

class QuitConfirmDelegate extends WatchUi.ConfirmationDelegate {
    private var _runner as WorkoutRunner;

    function initialize(runner as WorkoutRunner) {
        ConfirmationDelegate.initialize();
        _runner = runner;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            _runner.stop();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }
}
