package main

import (
	"errors"
	"os"
	"path/filepath"
)

// Fresh-install master snapshot: backups/fresh, taken by the installer after the first boot and before any player accounts exist.
// "Reset server" restores all four databases from it. It can't be deleted from the TUI.

const freshSet = "fresh"

func freshDir() string { return filepath.Join(backupDir(), freshSet) }

func haveFresh() bool {
	for _, b := range listBackups() {
		if b.Name == freshSet {
			return true
		}
	}
	return false
}

// snapshotFresh: full backup (MySQL must be up) stored as backups/fresh. Refuses to overwrite an existing master.
func snapshotFresh() error {
	if haveFresh() {
		return errors.New("backups/fresh already exists; it is the master copy and is never overwritten")
	}
	name, err := makeBackup("full", "fresh-install master snapshot")
	if err != nil {
		return err
	}
	return os.Rename(filepath.Join(backupDir(), name), freshDir())
}

// resetServer stops the game and auth servers (MySQL stays up), then restores every database from the master snapshot.
// No automatic backup: the TUI asks the user whether to create one first.
func resetServer() (string, error) {
	if !haveFresh() {
		return "", errors.New("cannot find the master backup (backups/fresh): this server has no fresh-install snapshot, so it cannot be reset")
	}
	return withServersStopped(5, true, func() (string, error) {
		var dbs []string
		for _, b := range listBackups() {
			if b.Name == freshSet {
				dbs = b.Dbs
			}
		}
		if _, err := restoreBackup(freshSet, dbs); err != nil {
			return "", err
		}
		return "server reset to fresh install; create accounts on the Accounts tab.", nil
	})
}
