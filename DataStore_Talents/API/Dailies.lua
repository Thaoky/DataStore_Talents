local addonName, addon = ...

--[[ 
This file keeps track of a character's daily quests.
--]]

local dailies
local options

local DataStore, pairs, time, date, TableInsert, TableRemove = DataStore, pairs, time, date, table.insert, table.remove
local C_DateAndTime, GetQuestID = C_DateAndTime, GetQuestID
local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local isCata = (WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC)

local function InsertQuest(questID, title)
	local charID = DataStore.ThisCharID
	dailies[charID] = dailies[charID] or {}

	TableInsert(dailies[charID], {
		title = title,
		id = questID,
		timestamp = time(),
		expiresIn = C_DateAndTime.GetSecondsUntilDailyReset()
		-- https://wowpedia.fandom.com/wiki/API_C_DateAndTime.GetSecondsUntilDailyReset
	})		
end

-- *** Event Handlers ***
local function OnQuestTurnedIn(event, questID, xpReward, moneyReward)
	local questTitle = "Unknown Quest"
	if isRetail then
		questTitle = C_QuestLog.GetTitleForQuestID(questID)
	else
		questTitle = C_QuestLog.GetQuestInfo(questID)
	end

	if QuestIsDaily() then
		InsertQuest(questID, questTitle)
	end
end
-- ** Mixins **
local function _GetDailiesHistory(characterID)
	return dailies[characterID]
end

local function _GetDailiesHistorySize(characterID)
	return dailies[characterID] and #dailies[characterID] or 0
end

local function _GetDailiesHistoryInfo(characterID, index)
	if dailies[characterID] then
		local quest = dailies[characterID][index]
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

	for _, quests in pairs(dailies) do
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
			["DataStore_Quests_Dailies"] = {
				GetDailiesHistory = _GetDailiesHistory,
				GetDailiesHistorySize = _GetDailiesHistorySize,
				GetDailiesHistoryInfo = _GetDailiesHistoryInfo,
			},
		}
	})

	dailies = DataStore_Quests_Dailies
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

	if options.TrackTurnIns and questID and (isRetail or isCata) then

		-- track daily quests turn-ins
		if QuestIsDaily() or DataStore:IsEmissaryQuest(questID) then
			-- I could not find a function to test if a quest is emissary, so their id's are tracked manually
			
			InsertQuest(questID, GetTitleText())
		end
	end
	
	AddonFactory:Broadcast("DATASTORE_QUEST_TURNED_IN", questID)		-- trigger the DS event
end)
