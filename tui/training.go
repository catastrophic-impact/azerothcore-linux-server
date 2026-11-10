package main

import (
	"fmt"
	"os"
	"strings"
)

// Free training: two switches that zero the gold cost of (a) every class-trainer spell and (b) the five riding skills.
// Only prices change: level, faction, race, quest and rank requirements stay enforced by the core.
// The original prices live in acore_world.dc_trainer_cost_backup (filled before the first change, never overwritten),
// so OFF restores them exactly. State: config/training.conf (class_free=, riding_free=; missing file/key = free).
// Not touched: weapon masters, pet trainers, profession trainers, mount spells.
const (
	ridingSpells = "33388,33391,34090,34091,54197" // Apprentice, Journeyman, Expert, Artisan, Cold Weather Flying
	trainerTable = "acore_world.trainer_spell"
	costBackup   = "acore_world.dc_trainer_cost_backup"
)

type trainingState struct{ Class, Riding bool }

func trainingConf() string { return p("config", "training.conf") }

func readTraining() trainingState {
	st := trainingState{true, true}
	b, err := os.ReadFile(trainingConf())
	if err != nil {
		return st
	}
	for _, l := range strings.Split(string(b), "\n") {
		k, v, ok := strings.Cut(strings.TrimSpace(l), "=")
		if !ok {
			continue
		}
		on := strings.TrimSpace(v) != "0"
		switch strings.TrimSpace(k) {
		case "class_free":
			st.Class = on
		case "riding_free":
			st.Riding = on
		}
	}
	return st
}

func writeTraining(st trainingState) error {
	b2i := func(b bool) string {
		if b {
			return "1"
		}
		return "0"
	}
	return os.WriteFile(trainingConf(), []byte("class_free="+b2i(st.Class)+"\nriding_free="+b2i(st.Riding)+"\n"), 0o644)
}

// applyTrainingSQL brings the trainer prices in line with the saved switches. Idempotent; needs MySQL up and an imported world DB.
func applyTrainingSQL() error {
	if freshDB() {
		return nil
	}
	if o, err := sql("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='acore_world' AND table_name='trainer_spell'"); err != nil || strings.TrimSpace(o) != "1" {
		return nil // world DB not imported yet
	}
	st := readTraining()
	cost := func(free bool) string {
		if free {
			return "0"
		}
		return "b.MoneyCost"
	}
	q := fmt.Sprintf(`CREATE TABLE IF NOT EXISTS %[1]s (TrainerId INT UNSIGNED NOT NULL, SpellId INT UNSIGNED NOT NULL, MoneyCost INT UNSIGNED NOT NULL, PRIMARY KEY (TrainerId, SpellId));
INSERT IGNORE INTO %[1]s SELECT ts.TrainerId, ts.SpellId, ts.MoneyCost FROM %[2]s ts JOIN acore_world.trainer t ON t.Id = ts.TrainerId WHERE t.Type = 0 OR (t.Type = 1 AND ts.SpellId IN (%[3]s));
UPDATE %[2]s ts JOIN acore_world.trainer t ON t.Id = ts.TrainerId JOIN %[1]s b ON b.TrainerId = ts.TrainerId AND b.SpellId = ts.SpellId SET ts.MoneyCost = %[4]s WHERE t.Type = 0;
UPDATE %[2]s ts JOIN acore_world.trainer t ON t.Id = ts.TrainerId JOIN %[1]s b ON b.TrainerId = ts.TrainerId AND b.SpellId = ts.SpellId SET ts.MoneyCost = %[5]s WHERE t.Type = 1 AND ts.SpellId IN (%[3]s);`,
		costBackup, trainerTable, ridingSpells, cost(st.Class), cost(st.Riding))
	if out, err := sql(q); err != nil {
		return fmt.Errorf("training prices: %s", strings.TrimSpace(out))
	}
	return nil
}

// setTraining saves the switches, applies them, and reloads the trainers of a running world (no restart needed).
func setTraining(st trainingState) (string, error) {
	if err := startMySQL(); err != nil {
		return "", err
	}
	if err := writeTraining(st); err != nil {
		return "", err
	}
	if err := applyTrainingSQL(); err != nil {
		return "", err
	}
	msg := "saved"
	if status().World {
		if err := worldCmd("reload trainer"); err != nil {
			return "", err
		}
		msg = "applied to the running server (trainers reloaded)"
	} else {
		msg = "saved; applies when the server starts"
	}
	return fmt.Sprintf("class training free: %v, riding training free: %v (%s)", st.Class, st.Riding, msg), nil
}
