// CRIMP, a hangboard timer for Garmin watches
// Copyright (C) 2026 Jan-Frode Myklebust
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version. It is
// distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Title of the top-level menu: app name with a smaller subtitle underneath.
class AppTitle extends WatchUi.Drawable {
    function initialize() {
        Drawable.initialize({});
    }

    function draw(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.42, Graphics.FONT_MEDIUM, "CRIMP", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.78, Graphics.FONT_XTINY, "hangboard", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class HangboardApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var menu = new WatchUi.Menu2({:title => new AppTitle()});
        var folders = Programs.folders();
        for (var i = 0; i < folders.size(); i++) {
            var programs = folders[i].programs;
            // A folder with one program starts it directly, so show what it runs.
            var sub = (programs.size() == 1) ? programs[0].summary() : programs.size() + " programs";
            menu.addItem(new WatchUi.MenuItem(folders[i].name, sub, i, {}));
        }
        return [menu, new FolderMenuDelegate()];
    }
}

// Open a program on its description screen; the workout starts from there.
function startProgram(program as Program) as Void {
    var view = new DescriptionView(program);
    WatchUi.pushView(view, new DescriptionDelegate(view), WatchUi.SLIDE_LEFT);
}

// Top-level menu: pick a folder. A folder with a single program skips the second menu.
class FolderMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var folder = Programs.folders()[item.getId() as Number];
        if (folder.programs.size() == 1) {
            startProgram(folder.programs[0]);
            return;
        }
        var menu = new WatchUi.Menu2({:title => folder.name});
        for (var i = 0; i < folder.programs.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(folder.programs[i].name, folder.programs[i].summary(), i, {}));
        }
        WatchUi.pushView(menu, new ProgramMenuDelegate(folder), WatchUi.SLIDE_LEFT);
    }
}

// Second-level menu: pick a program inside the folder and start it.
class ProgramMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _folder as ProgramFolder;

    function initialize(folder as ProgramFolder) {
        Menu2InputDelegate.initialize();
        _folder = folder;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        startProgram(_folder.programs[item.getId() as Number]);
    }
}
