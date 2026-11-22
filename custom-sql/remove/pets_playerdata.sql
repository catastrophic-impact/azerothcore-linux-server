-- Pet Battles PLAYER DATA: every player's pets, teams, followers and settings. NOT UNDOABLE: take a backup first.
-- Run with:  custom-sql/apply.sh --remove-data pets --yes -- <mysql arguments>      (stop the server and delete the scripts first)
USE acore_characters;
DROP TABLE IF EXISTS dc_battlepet;
DROP TABLE IF EXISTS dc_battleteam;
DROP TABLE IF EXISTS dc_battleplayer;
DROP TABLE IF EXISTS dc_battlefollower;
