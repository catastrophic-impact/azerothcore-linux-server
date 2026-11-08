package main

import (
	"fmt"
	"os"
	"strings"
	"time"
)

// runCLI handles `acore-admin <cmd>` for scripting/installer use. Returns true if handled.
func runCLI(args []string) bool {
	if len(args) == 0 {
		return false
	}
	var err error
	switch args[0] {
	case "start":
		err = startAll()
	case "stop":
		err = stopAll(5)
	case "stop-game": // graceful world+auth stop, MySQL stays up (for backups)
		if err = stopWorld(5); err == nil {
			err = stopAuth()
		}
	case "client-patch": // build zip + tar.gz of our client addons for unpacking into a WoW client folder
		var out string
		out, err = buildClientPatch()
		if err == nil {
			fmt.Println(out)
		}
	case "custom-sql": // apply custom-sql/*.sql now (needs MySQL up); also done automatically on every start
		err = applyCustomSQL()
	case "start-mysql":
		err = startMySQL()
	case "status":
		fmt.Printf("%+v\n", status())
	case "backup": // backup [full|player] [label]
		kind := "full"
		if len(args) > 1 {
			kind = args[1]
		}
		label := ""
		if len(args) > 2 {
			label = strings.Join(args[2:], " ")
		}
		var n string
		n, err = makeBackup(kind, label)
		if err == nil {
			fmt.Println("created", n)
		}
	case "snapshot-fresh": // installer: store the master snapshot backups/fresh (once, MySQL up, before player accounts exist)
		err = snapshotFresh()
	case "reset": // reset to the fresh-install state (same as the TUI Server tab, key R); needs --yes
		if len(args) < 2 || args[1] != "--yes" {
			err = fmt.Errorf("this replaces ALL databases with the fresh-install snapshot; run `reset --yes` to confirm")
			break
		}
		var msg string
		msg, err = resetServer()
		if err == nil {
			fmt.Println(msg)
		}
	case "list":
		for _, b := range listBackups() {
			fmt.Printf("%s  %s  %s\n", b.Name, human(b.Size), strings.Join(b.Dbs, ","))
		}
	case "restore": // restore <set> [db,db,...]
		if len(args) < 2 {
			err = fmt.Errorf("usage: restore <set> [db,db]")
			break
		}
		var dbs []string
		if len(args) > 2 {
			dbs = strings.Split(args[2], ",")
		} else {
			for _, b := range listBackups() {
				if b.Name == args[1] {
					dbs = b.Dbs
				}
			}
		}
		var safety string
		safety, err = restoreBackup(args[1], dbs)
		if err == nil {
			_ = safety
			fmt.Println("restored (no automatic backup is taken; create one first if you need it)")
		}
	case "console": // console <worldserver command...>
		err = worldCmd(strings.Join(args[1:], " "))
	case "sql": // sql <query>  (prints result)
		var out string
		out, err = sql(strings.Join(args[1:], " "))
		fmt.Println(out)
	case "wait-ready": // wait-ready [seconds]: until worldserver prints its ready line
		secs := 2400
		if len(args) > 1 {
			fmt.Sscanf(args[1], "%d", &secs)
		}
		err = fmt.Errorf("worldserver not ready after %ds (see logs/world.out)", secs)
		for i := 0; i < secs; i += 3 {
			if strings.Contains(strings.Join(tailFile(p("logs", "world.out"), 400), "\n"), "ready...") {
				err = nil
				break
			}
			if !status().World {
				err = fmt.Errorf("worldserver exited during startup (see logs/world.out)")
				break
			}
			time.Sleep(3 * time.Second)
		}
	case "confs": // generate missing confs; `confs reset` rebuilds ALL from stock + config-overrides (discards manual edits)
		err = applyOverridesMode(len(args) > 1 && args[1] == "reset")
	case "modules": // modules apply | undo | list
		sub := ""
		if len(args) > 1 {
			sub = args[1]
		}
		var msg string
		switch sub {
		case "apply":
			msg, err = applyModules("")
		case "undo":
			msg, err = undoModules()
		case "enable", "disable":
			man := loadManifest()
			for i := range man.Mods {
				if len(args) > 2 && man.Mods[i].Name == args[2] {
					man.Mods[i].Enabled = sub == "enable"
				}
			}
			err = man.save()
		default:
			for _, e := range loadManifest().Mods {
				fmt.Printf("%-30s enabled=%v built=%v\n", e.Name, e.Enabled, e.Built)
			}
		}
		if msg != "" {
			fmt.Println(msg)
		}
	default:
		return false
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
	return true
}
