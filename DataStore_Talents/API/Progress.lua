if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return end

--[[ 
This file keeps track of a character's progress in various quest lines.
--]]

local addonName, addon = ...
local thisCharacter
local options

local DataStore, pairs, ceil, TableInsert = DataStore, pairs, ceil, table.insert
local C_QuestLog, C_Covenants, C_CampaignInfo = C_QuestLog, C_Covenants, C_CampaignInfo

local bit64 = LibStub("LibBit64")

local storylines = {
	-- 9.0 Torghast
	["Torghast"] = { 62932, 62935, 62938, 60139, 62966, 62969, 60146, 62836, 61730 },
	-- 9.1 Chains of Domination
	["9.1"] = { 63639, 64555, 63902, 63727, 63622, 63656, 64437, 63593, 64314 },
	-- 9.2 Secrets of the First Ones
	["9.2"] = { 64958, 64825, 65305, 64844, 64813, 65328, 65238 },
	
	-- 10.0 The Dreamer
	["10.0"] = { 66392, 66185, 66186, 66188, 66189, 66394, 66397, 66635, 66398, 66399, 66400, 66401, 66402 },
	-- 10.1 Embers of Neltharion
	["10.1"] = { 73156, 75644, 72965, 75145, 74563, 72930, 75417 },
	-- 10.1.5 Fractures in Time
	["10.1.5"] = { 76140, 76141, 76142, 76143, 76144, 76145, 76146, 76147 },
	-- 10.2 Guardians of the Dream
	["10.2"] = { 75923, 77283, 76443, 77178, 76337, 76401, 76283 },
}

local covenantCampaignIDs = {
	[Enum.CovenantType.Kyrian] = 119,
	[Enum.CovenantType.Venthyr] = 113,
	[Enum.CovenantType.NightFae] = 117,
	[Enum.CovenantType.Necrolord] = 115
}

local covenantCampaignQuestChapters = {
	-- These are the quest id's of the last quest in each chapter
	[Enum.CovenantType.Kyrian] = { 57904, 60272, 58798, 58181, 61878, 58571, 61697, 62555, 62557 },			-- https://www.wowhead.com/guides/kyrian-covenant-campaign-story-rewards
	[Enum.CovenantType.Venthyr] = { 62921, 60272, 59343, 57893, 58444, 59233, 58395, 57646, 58407 },		-- https://www.wowhead.com/guides/venthyr-covenant-campaign-story-rewards
	[Enum.CovenantType.NightFae] = { 62899, 60272, 59242, 59821, 59071, 61171, 58452, 59866, 60108 },		-- https://www.wowhead.com/guides/night-fae-covenant-campaign-story-rewards
	[Enum.CovenantType.Necrolord] = { 59609, 60272, 57648, 58820, 59894, 57636, 58624, 61761, 62406 },		-- https://www.wowhead.com/guides/necrolords-covenant-campaign-story-rewards
}


-- *** Utility functions ***
local function _SetQuestCompleted(history, questID)
	local bitPos = (questID % 64)
	local index = ceil(questID / 64)
		
	history[index] = bit64:SetBit((history[index] or 0), bitPos)
end

local function GetStorylineProgress(storyline)
	local count = 0
	local chapters = storylines[storyline]

	if chapters then
		-- loop through the quest id's of the last quest of each chapter, and check if it is flagged completed
		for _, questID in pairs(chapters) do
			if C_QuestLog.IsQuestFlaggedCompleted(questID) then
				count = count + 1
			end
		end
	end

	return count
end

local function GetCompletionStatus(index, progress)
	-- completed will be true/false or nil
	-- ex: progress is 3/9
	-- 1 & 2 are true (completed)
	-- 3 is false (ongoing, but not completed yet)
	-- 4+ = nil (not yet started)

	if (index <= progress) then return true end
	if (index == progress + 1) and (progress ~= 0) then return false end
end

-- *** Scanning functions ***
local function ScanStorylineProgress(storyline)
	-- Ex: ["9.2"] = 6 (only save if > 0)
	local progress = GetStorylineProgress(storyline)
	thisCharacter.Storylines[storyline] = progress > 0 and progress or nil
end

local function ScanCovenantCampaignProgress()
	-- Get the covenant ID, exit if invalid
	local covenantID = C_Covenants.GetActiveCovenantID()
	if covenantID == Enum.CovenantType.None then return end

	local count = 0
	
	-- loop through the quest id's of the last quest of each chapter, and check if it is flagged completed
	for _, questID in pairs(covenantCampaignQuestChapters[covenantID]) do
		if C_QuestLog.IsQuestFlaggedCompleted(questID) then
			count = count + 1
		end
	end
	
	thisCharacter.CovenantInfo = C_Covenants.GetActiveCovenantID()			-- bits 0-3 = Active Covenant ID (0 = None)
		+ bit64:LeftShift(count, 4)													-- bits 4+ = progress
end

local function ScanQuests()
	ScanCovenantCampaignProgress()
	
	ScanStorylineProgress("Torghast")
	ScanStorylineProgress("9.1")
	ScanStorylineProgress("9.2")
	ScanStorylineProgress("10.0")
	ScanStorylineProgress("10.1")
	ScanStorylineProgress("10.1.5")
	ScanStorylineProgress("10.2")
end


-- ** Mixins **
local function _GetCovenantCampaignProgress(character)
	return character.CovenantInfo
		and bit64:RightShift(character.CovenantInfo, 4)		-- bits 4+ = progress
		or 0
end

local function _GetCovenantCampaignLength(character)
	if not character.CovenantInfo then return 0 end

	local covenantID = bit64:GetBits(character.CovenantInfo, 0, 4)		-- bits 0-3 = covenantID
	if covenantID == Enum.CovenantType.None then return 0 end
	
	local campaignID = covenantCampaignIDs[covenantID]				-- get the campaign ID of that character's covenant
	local chapters = C_CampaignInfo.GetChapterIDs(campaignID)	-- get the chapters of that campaign (always available for all covenants)
	
	return #chapters
end

local function _GetCovenantCampaignChaptersInfo(character)
	local chaptersInfo = {}
	if not character.CovenantInfo then return chaptersInfo end
	
	local covenantID = bit64:GetBits(character.CovenantInfo, 0, 4)		-- bits 0-3 = covenantID
	if covenantID == Enum.CovenantType.None then return chaptersInfo end
	
	local campaignID = covenantCampaignIDs[covenantID]				-- get the campaign ID of that character's covenant
	local chapters = C_CampaignInfo.GetChapterIDs(campaignID)	-- get the chapters of that campaign (always available for all covenants)
	

	for index, id in ipairs(chapters) do
		local info = C_CampaignInfo.GetCampaignChapterInfo(id)
		local progress = _GetCovenantCampaignProgress(character)
		
		TableInsert(chaptersInfo, { 
			name = info.name, 
			completed = GetCompletionStatus(index, progress)
		})
	end
	
	return chaptersInfo
end

local function _GetStorylineProgress(character, storyline)
	return character.Storylines[storyline] or 0
end

local function _GetStorylineLength(storyline)
	return storylines[storyline] and #storylines[storyline] or 0
end

local function _GetCampaignChaptersInfo(character, campaignID, storyline)
	local chaptersInfo = {}
	local progress = _GetStorylineProgress(character, storyline)
	
	-- Get the chapters of that campaign (always available for all covenants)
	-- Or get the quest ID's (ex: for Torghast)
	local chapters = campaignID
		and C_CampaignInfo.GetChapterIDs(campaignID)
		or storylines[storyline]
	
	-- Get the chapter name of a given id (step in the campaign or the questID)
	local GetChapterName = campaignID
		and function(id) return C_CampaignInfo.GetCampaignChapterInfo(id).name end
		or function(id) return C_QuestLog.GetTitleForQuestID(id) or "querying.." end

	for index, id in ipairs(chapters) do
		local chapterName = GetChapterName(id)
		
		TableInsert(chaptersInfo, { 
			name = chapterName, 
			completed = GetCompletionStatus(index, progress)
		})
	end
	
	return chaptersInfo
end


AddonFactory:OnAddonLoaded(addonName, function() 
	DataStore:RegisterTables({
		addon = addon,
		characterTables = {
			["DataStore_Quests_Progress"] = {
				GetCovenantCampaignProgress = _GetCovenantCampaignProgress,
				GetCovenantCampaignLength = _GetCovenantCampaignLength,
				GetCovenantCampaignChaptersInfo = _GetCovenantCampaignChaptersInfo,
				GetStorylineProgress = _GetStorylineProgress,
				GetCampaignChaptersInfo = _GetCampaignChaptersInfo,
			},
		}
	})
	
	DataStore:RegisterMethod(addon, "GetStorylineLength", _GetStorylineLength)
	
	thisCharacter = DataStore:GetCharacterDB("DataStore_Quests_Progress", true)
	thisCharacter.Storylines = thisCharacter.Storylines or {}
end)

AddonFactory:OnPlayerLogin(function()
	addon:ListenTo("PLAYER_ALIVE", ScanQuests)
	addon:ListenTo("UNIT_QUEST_LOG_CHANGED", function() 
		-- triggered when accepting/validating a quest .. but too soon to refresh data
		
		-- so register for this one
		addon:ListenTo("QUEST_LOG_UPDATE", function()
			-- .. and unregister it right away, since we only want it to be processed once 
			-- (and it's triggered way too often otherwise)
			addon:StopListeningTo("QUEST_LOG_UPDATE", "Cov")
			ScanQuests()
		
		end, "Cov")	-- Give a tag to ensure uniqueness when removing (2 lines above)
	end)
	addon:ListenTo("WORLD_QUEST_COMPLETED_BY_SPELL", ScanQuests)
end)
