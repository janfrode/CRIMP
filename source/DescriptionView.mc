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

// First screen of a program: its name and description. UP/DOWN scroll long text, START begins.
// Nothing is started or recorded until START is pressed.
class DescriptionView extends WatchUi.View {
    private var _program as Program;
    private var _lines as Array<String> or Null = null;
    private var _first as Number = 0;       // index of the first visible line
    private var _visible as Number = 1;     // how many lines fit
    private var _font as Graphics.FontType = Graphics.FONT_TINY;

    function initialize(program as Program) {
        View.initialize();
        _program = program;
    }

    function program() as Program {
        return _program;
    }

    function scroll(delta as Number) as Void {
        if (_lines == null) {
            return;
        }
        var maxFirst = _lines.size() - _visible;
        if (maxFirst < 0) {
            maxFirst = 0;
        }
        _first += delta;
        if (_first > maxFirst) {
            _first = maxFirst;
        }
        if (_first < 0) {
            _first = 0;
        }
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Narrow column so text stays inside a round screen.
        var textW = (w * 0.72).toNumber();
        if (_lines == null) {
            _lines = wrap(dc, _program.description, _font, textW);
        }
        var lines = _lines as Array<String>;

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.13, Graphics.FONT_SMALL, _program.name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var lineH = dc.getFontHeight(_font);
        var top = (h * 0.24).toNumber();
        var bottom = (h * 0.80).toNumber();
        _visible = (bottom - top) / lineH;
        if (_visible < 1) {
            _visible = 1;
        }
        scroll(0);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < _visible && _first + i < lines.size(); i++) {
            dc.drawText(w / 2, top + i * lineH, _font, lines[_first + i], Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Scroll hints
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var cx = w / 2;
        if (_first > 0) {
            dc.fillPolygon([[cx - 6, top - 2], [cx + 6, top - 2], [cx, top - 9]]);
        }
        if (_first + _visible < lines.size()) {
            dc.fillPolygon([[cx - 6, bottom + 2], [cx + 6, bottom + 2], [cx, bottom + 9]]);
        }

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.90, Graphics.FONT_XTINY, "START", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Greedy word wrap. A word wider than the column is left on a line of its own.
    private function wrap(dc as Dc, text as String, font as Graphics.FontType, maxW as Number) as Array<String> {
        var lines = [] as Array<String>;
        var line = "";
        var word = "";
        var chars = text.toCharArray();
        for (var i = 0; i <= chars.size(); i++) {
            var atEnd = (i == chars.size());
            if (!atEnd && chars[i] != ' ') {
                word += chars[i].toString();
                continue;
            }
            if (word.length() > 0) {
                var candidate = (line.length() == 0) ? word : line + " " + word;
                if (line.length() > 0 && dc.getTextWidthInPixels(candidate, font) > maxW) {
                    lines.add(line);
                    line = word;
                } else {
                    line = candidate;
                }
                word = "";
            }
        }
        if (line.length() > 0) {
            lines.add(line);
        }
        return lines;
    }
}

class DescriptionDelegate extends WatchUi.BehaviorDelegate {
    private var _view as DescriptionView;

    function initialize(view as DescriptionView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // START / tap: begin the workout, replacing this screen so BACK later returns to the menu.
    function onSelect() as Boolean {
        var runner = new WorkoutRunner(_view.program());
        runner.start();
        WatchUi.switchToView(new WorkoutView(runner), new WorkoutDelegate(runner), WatchUi.SLIDE_LEFT);
        return true;
    }

    function onNextPage() as Boolean {
        _view.scroll(1);
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.scroll(-1);
        WatchUi.requestUpdate();
        return true;
    }
}
