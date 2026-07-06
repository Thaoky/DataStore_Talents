if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return end

--[[ 
This file keeps track of a character's weekly quests.
--]]

local addonName, addon = ...

local weeklies
local options

local DataStore, pairs, time, date, TableInsert, TableRemove = DataStore, pairs, time, date, table.insert, table.remove
local C_QuestLog, C_DateAndTime, GetQuestID = C_QuestLog, C_DateAndTime, GetQuestID

local weeklyWorldQuests = {
	-- Legion : https://www.wowhead.com/broken-isles-world-bosses-guide
	[43512] = true,		-- Ana-Mouz
	[43193] = true,		-- Calamir
	[43448] = true,		-- Drugon the Frostblood
	[43985] = true,		-- Flotsam
	[42819] = true,		-- Humongris
	[43192] = true,		-- Levantus
	[43513] = true,		-- Na'zak the Fiend
	[42270] = true,		-- Nithogg
	[42779] = true,		-- Shar'thos
	[42269] = true,		-- The Soultakers
	[44287] = true,		-- Withered J'im
	
	-- BfA : https://www.wowhead.com/world-bosses-in-battle-for-azeroth
	[52196] = true,		-- Dunegorger Kraulok
	[52169] = true,		-- Ji'arak
	[52181] = true,		-- T'zane
	[52166] = true,		-- Warbringer Yenajz
	[52163] = true,		-- Azurethos, The Winged Typhoon
	[52157] = true,		-- Hailstone Construct
	
	-- Shadowlands
	[61813] = true,		-- Bastion - Valinor, the Light of Eons
	[61814] = true,		-- Revendreth - Nurgash Muckformed
	[61815] = true,		-- Ardenweald - Oranomonos the Everbranching
	[61816] = true,		-- Maldraxxus - Mortanis
	[64531] = true,		-- The Maw - Mor'geth
	[65143] = true,		-- Zereth Mortis - Antros
	
	-- Dragonflight : https://www.wowhead.com/guide/world-bosses-dragonflight
	[69927] = true,		-- The Azure Span - Bazual
	[69928] = true,		-- Thaldraszus - Liskanoth
	[69929] = true,		-- Ohn'ahran Plains - Strunraan
	[69930] = true,		-- The Waking Shores - Basrikron
	-- [] = true,		-- Zaralek Cavern - The Zaqali Elders ?
	[76367] = true,		-- Emerald Dream - Aurostor 
	
	-- The War Within
	[81630] = true,		-- Isle of Dorn - Kordac
	[82653] = true,		-- The Ringing Deeps - Aggregation of Horrors
	[81653] = true,		-- Hammerfall - Shurrai
	[81624] = true,		-- City of Threads - Orta, the Broken Mountain
	[80184] = true,		-- PvP : Random Battlegrounds
	[80186] = true,		-- PvP : Epic Battlegrounds
	[80187] = true,		-- PvP : Arena Skirmishes
	[80189] = true,		-- PvP : Rated Battlegrounds
	[81793] = true,		-- Sparks of War: Isle of Dorn
	[81794] = true,		-- Sparks of War: The Ringing Deeps
	[81795] = true,		-- Sparks of War: Hallowfall
	[81796] = true,		-- Sparks of War: Azj-Kahet

	[82787] = true,		-- Special Assignment: Rise of the Colossals
	[82355] = true,		-- Special Assignment: Cinderbee Surge
	[83229] = true,		-- Special Assignment: When the Deeps Stir

}

local function InsertQuest(questID, title)
	local charID = DataStore.ThisCharID
	weeklies[charID] = weeklies[charID] or {}

	TableInsert(weeklies[charID], {
		title = title,
		id = questID,
		timestamp = time(),
		expiresIn = C_DateAndTime.GetSecondsUntilWeeklyReset()
	})		
end

-- *** Event Handlers ***
local function OnQuestTurnedIn(event, questID, xpReward, moneyReward)
	if weeklyWorldQuests[questID] then
		InsertQuest(questID, C_QuestLog.GetTitleForQuestID(questID))
	end
end

-- ** Mixins **
local function _GetWeekliesHistory(characterID)
	return weeklies[characterID]
end

local function _GetWeekliesHistorySize(characterID)
	return weeklies[characterID] and #weeklies[characterID] or 0
end

local function _GetWeekliesHistoryInfo(characterID, index)
	if weeklies[characterID] then
		local quest = weeklies[characterID][index]
		return quest.id, quest.title, quest.timestamp
	end
end

local function ClearExpiries()
	-- this function will clear all the dailies from the day(s) before (or same day, but before the reset hour)

	local timeTable = {}

	timeTable.year = date("%Y")
	timeTable.month = date("%m")
	timeTable.day = date("%d")
	timeTable.hour = options.DailyResetHour
	timeTable.min = 0

	local now = time()
	local resetTime = time(timeTable)

	-- gap is positive if reset time was earlier in the day (ex: it is now 9am, reset was at 3am) => simply make sure that:
	--		the elapsed time since the quest was turned in is bigger than  (ex: 10 hours ago)
	--		the elapsed time since the last reset (ex: 6 hours ago)

	-- gap is negative if reset time is later on the same day (ex: it is 1am, reset is at 3am)
	--		the elapsed time since the quest was turned in is bigger than
	--		the elapsed time since the last reset 1 day before

	local gap = now - resetTime
	gap = (gap < 0) and (86400 + gap) or gap	-- ex: it's 1am, next reset is in 2 hours, so previous reset was (24 + (-2)) = 22 hours ago

	for _, quests in pairs(weeklies) do
		-- browse history backwards, to avoid messing up the indexes when removing
		for i = #quests, 1, -1 do
			local quest = quests[i]

			if quest.timestamp and quest.expiresIn and (now - quest.timestamp) > quest.expiresIn then
				TableRemove(quests, i)
			end
		end
	end
end

AddonFactory:OnAddonLoaded(addonName, function() 
	DataStore:RegisterTables({
		addon = addon,
		characterIdTables = {
			["DataStore_Quests_Weeklies"] = {
				GetWeekliesHistory = _GetWeekliesHistory,
				GetWeekliesHistorySize = _GetWeekliesHistorySize,
				GetWeekliesHistoryInfo = _GetWeekliesHistoryInfo,
			},
		}
	})
	
	weeklies = DataStore_Quests_Weeklies
end)

AddonFactory:OnPlayerLogin(function()
	options = DataStore_Quests_Options
	
	addon:ListenTo("QUEST_TURNED_IN", OnQuestTurnedIn)
	
	ClearExpiries()
end)

-- *** Hooks ***
-- GetQuestReward is the function that actually turns in a quest
hooksecurefunc("GetQuestReward", function(choiceIndex)
	-- 2019/09/09 : questID is valid, even in Classic
	local questID = GetQuestID() -- returns the last displayed quest dialog's questID

	if not options.TrackTurnIns or not questID or not QuestIsWeekly() then return end

	-- track weekly quests turn-ins
	InsertQuest(questID, GetTitleText())
end)
