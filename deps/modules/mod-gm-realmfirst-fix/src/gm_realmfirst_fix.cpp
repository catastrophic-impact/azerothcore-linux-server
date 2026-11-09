#include "AccountMgr.h"
#include "Log.h"
#include "Player.h"
#include "ScriptMgr.h"

namespace
{
    bool IsRealmFirstAchievement(AchievementEntry const* achievement)
    {
        if (!achievement)
            return false;

        return (achievement->flags & (ACHIEVEMENT_FLAG_REALM_FIRST_REACH | ACHIEVEMENT_FLAG_REALM_FIRST_KILL)) != 0;
    }

    bool ShouldBlockRealmFirstFor(Player const* player)
    {
        if (!player || !player->GetSession())
            return false;

        // Block for active GM mode and for any non-player account security level.
        // Security-level check covers early login/loading windows when GM mode may not yet be toggled on.
        return player->IsGameMaster() || !AccountMgr::IsPlayerAccount(player->GetSession()->GetSecurity());
    }

    class GMRealmFirstFixPlayerScript : public PlayerScript
    {
    public:
        GMRealmFirstFixPlayerScript() : PlayerScript("GMRealmFirstFixPlayerScript") { }

        bool OnPlayerBeforeAchievementComplete(Player* player, AchievementEntry const* achievement) override
        {
            if (!IsRealmFirstAchievement(achievement) || !ShouldBlockRealmFirstFor(player))
                return true;

            LOG_INFO("module.gm_realmfirst_fix", "Blocked realm-first achievement {} for player {} (guid: {}).",
                achievement->ID, player->GetName(), player->GetGUID().ToString());
            return false;
        }

        bool OnPlayerBeforeCriteriaProgress(Player* player, AchievementCriteriaEntry const* criteria) override
        {
            if (!criteria || !ShouldBlockRealmFirstFor(player))
                return true;

            AchievementEntry const* achievement = sAchievementStore.LookupEntry(criteria->referredAchievement);
            if (!IsRealmFirstAchievement(achievement))
                return true;

            LOG_DEBUG("module.gm_realmfirst_fix", "Blocked realm-first criteria {} for player {} (guid: {}).",
                criteria->ID, player->GetName(), player->GetGUID().ToString());
            return false;
        }
    };
}

void AddGMRealmFirstFixScripts()
{
    new GMRealmFirstFixPlayerScript();
}
