local addonName, addon = ...

--[[ 
This file keeps track of a character's quest history.
--]]

local thisCharacter
local options

local DataStore, pairs, ceil, time = DataStore, pairs, ceil, time
local GetQuestsCompleted, GetBuildInfo, GetQuestID = GetQuestsCompleted, GetBuildInfo, GetQuestID
local C_QuestLog, C_Timer = C_QuestLog, C_Timer
local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

local bit64 = LibStub("LibBit64")

-- *** Utility functions ***
local function _SetQuestCompleted(history, questID)
	local bitPos = (questID % 64)
	local index = ceil(questID / 64)
		
	history[index] = bit64:SetBit((history[index] or 0), bitPos)
end

-- *** Scanning functions ***
local function GetQuestHistory_Common()
	-- In retail, the questID is the value in the returned table
	if isRetail then
		return C_QuestLog.GetAllCompletedQuestIDs()
	end

	-- In Classic and WotLK, the questID is the key ..
	local quests = {}
	GetQuestsCompleted(quests)	
	
	-- .. so let's normalize that
	return DataStore:HashToSortedArray(quests)
end

local function RefreshQuestHistory()
	local history = thisCharacter.Quests
	wipe(history)
	
	local quests = GetQuestHistory_Common()

	--[[	In order to save memory, we'll save the completion status of 64 quests into one number (by setting bits 0 to 63)
		Ex:
			in history[1] , we'll save quests 0 to 63		(note: questID 0 does not exist, we're losing one bit, doesn't matter :p)
			in history[2] , we'll save quests 64 to 127
			...
			index = questID / 64 (rounded up)
			bit position = questID % 64
	--]]

	local count = 0
	local index, bitPos
	
	for _, questID in pairs(quests) do
		_SetQuestCompleted(history, questID)
		count = count + 1
	end

	local _, version = GetBuildInfo()				-- save the current build, to know if we can requery and expect immediate execution
	thisCharacter.Build = version
	thisCharacter.Size = count
	thisCharacter.LastUpdate = time()

	if queryVerbose then
		addon:Print("Quest history successfully retrieved!")
		queryVerbose = nil
	end
end

-- ** Mixins **
local queryVerbose

local function _QueryQuestHistory()
	queryVerbose = true
	RefreshQuestHistory()		-- this call triggers "QUEST_QUERY_COMPLETE"
end

local function _GetQuestHistory(character)
	return character.Quests
end

local function _GetQuestHistoryInfo(character)
	-- return the size of the history, the timestamp, and the build under which it was saved
	return character.Size, character.LastUpdate, character.Build
end

local function _IsQuestCompletedBy(character, questID)
	local bitPos = (questID % 64)
	local index = ceil(questID / 64)

	if character.Quests[index] then
		return bit64:TestBit(character.Quests[index], bitPos)		-- nil = not completed (not in the table), true = completed
	end
end

AddonFactory:OnAddonLoaded(addonName, function() 
	DataStore:RegisterTables({
		addon = addon,
		characterTables = {
			["DataStore_Quests_History"] = {
				GetQuestHistory = _GetQuestHistory,
				GetQuestHistoryInfo = _GetQuestHistoryInfo,
				IsQuestCompletedBy = _IsQuestCompletedBy,
			},
		}
	})
	
	DataStore:RegisterMethod(addon, "QueryQuestHistory", _QueryQuestHistory)
	
	thisCharacter = DataStore:GetCharacterDB("DataStore_Quests_History", true)
	thisCharacter.Quests = thisCharacter.Quests or {}
end)

AddonFactory:OnPlayerLogin(function()
	options = DataStore_Quests_Options
	
	if options.AutoUpdateHistory then			-- if history has been queried at least once, auto update it at logon (fast operation - already in the game's cache)
		C_Timer.After(5, RefreshQuestHistory)	-- refresh quest history 5 seconds later, to decrease the load at startup
	end
end)

-- *** Hooks ***
-- GetQuestReward is the function that actually turns in a quest
hooksecurefunc("GetQuestReward", function(choiceIndex)
	-- 2019/09/09 : questID is valid, even in Classic
	local questID = GetQuestID() -- returns the last displayed quest dialog's questID

	if not DataStore_Quests_Options.TrackTurnIns or not questID then return end

	-- mark the current quest ID as completed
	_SetQuestCompleted(thisCharacter.Quests, questID)
end)
