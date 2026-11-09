# ![logo](https://raw.githubusercontent.com/azerothcore/azerothcore.github.io/master/images/logo-github.png) AzerothCore

# mod-gm-realmfirst-fix

AzerothCore module that blocks Realm First achievements for GM accounts.

## What It Does

- Blocks completion of achievements flagged as Realm First (REALM_FIRST_REACH and REALM_FIRST_KILL) for:
  - characters currently in GM mode (IsGameMaster)
  - any account with security level above SEC_PLAYER

This avoids cases where GM/admin accounts can accidentally take Realm First achievements.

## Requirements

- AzerothCore 3.3.5a (WotLK), current master/main.

## Installation

1. Place module in your AzerothCore source under: modules/mod-gm-realmfirst-fix
2. Re-run CMake.
3. Rebuild and install core.
4. Restart worldserver.

## Notes

- The module uses PlayerScript hooks:
  - OnPlayerBeforeAchievementComplete
  - OnPlayerBeforeCriteriaProgress
- No SQL is required.

## Credits

- Elgracia operations/customization team.
- [Haeniken](https://github.com/Haeniken)
