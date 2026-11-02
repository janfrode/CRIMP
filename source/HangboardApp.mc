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
            var count = folders[i].programs.size();
            menu.addItem(new WatchUi.MenuItem(folders[i].name, count + " programs", i, {}));
        }
        return [menu, new FolderMenuDelegate()];
    }
}

// Top-level menu: pick a folder.
class FolderMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var folder = Programs.folders()[item.getId() as Number];
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
        var program = _folder.programs[item.getId() as Number];
        var runner = new WorkoutRunner(program);
        runner.start();
        WatchUi.pushView(new WorkoutView(runner), new WorkoutDelegate(runner), WatchUi.SLIDE_LEFT);
    }
}
