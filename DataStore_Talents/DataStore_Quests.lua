--[[	*** DataStore_Quests ***
Written by : Thaoky, EU-Marécages de Zangar
July 8th, 2009
--]]

if not DataStore then return end

local addonName, addon = ...
local thisCharacter
local allCharacters
local questInfos
local questColors
local questTitles
local options

local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

local DataStore, pairs, tonumber, time, format, strsplit, TableInsert, TableConcat = DataStore, pairs, tonumber, time, format, strsplit, table.insert, table.concat
local GetNumQuestLogEntries, GetQuestLogSelection, SelectQuestLogEntry, GetQuestLogTitle, GetQuestTagInfo = GetNumQuestLogEntries, GetQuestLogSelection, SelectQuestLogEntry, GetQuestLogTitle, GetQuestTagInfo
local GetQuestLink, GetQuestFactionGroup, GetQuestObjectiveInfo, ExpandQuestHeader, CollapseQuestHeader = GetQuestLink, GetQuestFactionGroup, GetQuestObjectiveInfo, ExpandQuestHeader, CollapseQuestHeader
local GetNumQuestLogChoices, GetQuestLogChoiceInfo, GetQuestLogItemLink = GetNumQuestLogChoices, GetQuestLogChoiceInfo, GetQuestLogItemLink
local GetNumQuestLogRewards, GetQuestLogRewardInfo, GetQuestLogRewardMoney = GetNumQuestLogRewards, GetQuestLogRewardInfo, GetQuestLogRewardMoney
local C_QuestLog, C_TaskQuest, C_QuestInfoSystem, C_CovenantCallings = C_QuestLog, C_TaskQuest, C_QuestInfoSystem, C_CovenantCallings

local L = AddonFactory:GetLocale(addonName)
local bit64 = LibStub("LibBit64")

local emissaryQuests = {
	-- 7.0 Legion / EXPANSION_NAME6
	[42420] = 6, -- Court of Farondis
	[42421] = 6, -- Nightfallen
	[42422] = 6, -- The Wardens
	[42233] = 6, -- Highmountain Tribes
	[42234] = 6, -- Valarjar
	[42170] = 6, -- Dreamweavers
	[43179] = 6, -- Kirin Tor
	[48642] = 6, -- Argussian Reach
	[48641] = 6, -- Armies of Legionfall
	[48639] = 6, -- Army of the Light
	
	-- 8.0 Battle for Azeroth / EXPANSION_NAME7
	[50604] = 7, -- Tortollan Seekers 
	[50562] = 7, -- Champions of Azeroth
	[50599] = 7, -- Proudmoore Admiralty
	[50600] = 7, -- Order of Embers
	[50601] = 7, -- Storm's Wake
	[50605] = 7, -- Alliance War Effort
	[50598] = 7, -- Zandalari Empire
	[50603] = 7, -- Voldunai
	[50602] = 7, -- Talanji's Expedition
	[50606] = 7, -- Horde War Effort
	[56119] = 7, -- The Waveblade Ankoan
	[56120] = 7, -- The Unshackled
}


-- *** Common API ***
local API_GetNumQuestLogEntries = isRetail and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries
local API_GetSelectedQuest = isRetail and C_QuestLog.GetSelectedQuest or GetQuestLogSelection
local API_SetSelectedQuest = isRetail and C_QuestLog.SetSelectedQuest or SelectQuestLogEntry
local API_DailyFrequency = isRetail and Enum.QuestFrequency.Daily or LE_QUEST_FREQUENCY_DAILY
local API_WeeklyFrequency = isRetail and Enum.QuestFrequency.Weekly or LE_QUEST_FREQUENCY_WEEKLY
local API_GetQuestInfo
local API_GetQuestTagInfo

if isRetail then
	API_GetQuestInfo = function(index) 
			local info = C_QuestLog.GetInfo(index)
			if not info then return nil end
			-- isComplete : always nil in retail ? needs checking
		
			return info.title, info.level, info.groupSize, info.isHeader, info.isCollapsed, info.isComplete,
				info.frequency or 0, info.questID, info.isTask, info.isBounty, info.isStory, info.isHidden, info.suggestedGroup
		end
	API_GetQuestTagInfo = function(questID)
			local info = C_QuestLog.GetQuestTagInfo(questID) or {}
			return info.tagID
		end
else
	API_GetQuestInfo = function(index) 
			local title, level, groupSize, isHeader, isCollapsed, isComplete, frequency, questID,
					_, _, _, _, isTask, isBounty, isStory, isHidden = GetQuestLogTitle(index)
			
			-- isComplete : 1 if the quest is completed, -1 if the quest is failed, nil otherwise
			
			-- 2019/09/01 groupSize = "Dungeon", "Raid" in Classic, not numeric !! => 0
			-- temporary fix: set it to 0 (3rd return value)
			return title, level, 0, isHeader, isCollapsed, isComplete,
					frequency, questID, isTask, isBounty, isStory, isHidden, 0
		end
	API_GetQuestTagInfo = function(questID)
			return GetQuestTagInfo(questID)
		end
end

-- *** Utility functions ***
local function GetQuestTitle(questID)
	-- retail
	if isRetail then return C_QuestLog.GetTitleForQuestID(questID) end
	
	-- non-retail
	if questTitles then return questTitles[questID] end
end


local function SetQuestInfo(questID, isDaily, isWeekly, isTask, isBounty, isStory, isHidden, isSolo, groupSize, level)

	local link = GetQuestLink and GetQuestLink(questID)
	if not link then return end

	-- local inputString = "|cffffff00|Hquest:76317:2699|h[Call of the Dream]|h|r"
	local color, _, questInfo = link:match("|c(%x+)|Hquest:(%d+):(-?%d+)|h")
	
	local colorID = DataStore:StoreToSetAndList(questColors, color)
	questInfo = tonumber(questInfo)
	
	-- 2024/06/24 : Fix for Cataclysm, not sure yet if it applies to Retail
	-- questInfo can be equal to -1 for quests that seem to have no level (like holiday quests)
	-- Set it to 0, and adjust when rebuilding the link
	if questInfo < 0 then
		questInfo = 0
	end
	
	local tagID = API_GetQuestTagInfo(questID) or 0

	questInfos[questID] = colorID 			-- bits 0-3, 4 bits = quest color (16 should be more than enough..)
		+ bit64:LeftShift(tagID, 4)			-- bits 4-13, 10 bits = quest tag (1024, to be safe, current highest is 278 (10.2, Jan. 2024))
		+ bit64:LeftShift(isDaily, 14)		-- bit 14 : isDaily
		+ bit64:LeftShift(isWeekly, 15)		-- bit 15 : isWeekly
		+ bit64:LeftShift(isTask, 16)			-- bit 16 : isTask
		+ bit64:LeftShift(isBounty, 17)		-- bit 17 : isBounty
		+ bit64:LeftShift(isStory, 18)		-- bit 18 : isStory
		+ bit64:LeftShift(isHidden, 19)		-- bit 19 : isHidden
		+ bit64:LeftShift(isSolo, 20)			-- bit 20 : isSolo
		+ bit64:LeftShift(groupSize, 21)		-- bit 21-23 : groupSize, 3 bits, shouldn't exceed 5
		+ bit64:LeftShift(level, 24)			-- bit 24-31 : level
		+ bit64:LeftShift(questInfo, 32)		-- bits 32+, n bits = info about the quest, Blizzard's encoding, no idea what it means, but necessary to rebuild the quest link.
end

local function BuildQuestLink(questID)
	local data = questInfos[questID]
	if not data then return end
	
	local title = GetQuestTitle(questID)
	if not title then return end
	
	local color = bit64:GetBits(data, 0, 4)
	local info = bit64:RightShift(data, 32)
	
	-- 2024/06/24 : Fix for Cataclysm, not sure yet if it applies to Retail
	-- questInfo can be equal to -1 for quests that seem to have no level (like holiday quests)
	-- Set it to 0, and adjust when rebuilding the link
	if info == 0 then
		info = -1
	end
	
	-- Ex: "|cffffff00|Hquest:65436:2573|h[The Dragon Isles Await]|h|r"
	return format("|c%s|Hquest:%d:%d|h[%s]|h|r", color, questID, info, title)
end

local function DailyResetDropDown_OnClick(self)
	-- set the new reset hour
	local newHour = self.value
	
	options.DailyResetHour = newHour
	UIDropDownMenu_SetSelectedValue(DataStore_Quests_DailyResetDropDown, newHour)
end

local function DailyResetDropDown_Initialize(self)
	local info = UIDropDownMenu_CreateInfo()
	
	local selectedHour = options.DailyResetHour
	
	for hour = 0, 23 do
		info.value = hour
		info.text = format(TIMEMANAGER_TICKER_24HOUR, hour, 0)
		info.func = DailyResetDropDown_OnClick
		info.checked = (hour == selectedHour)
	
		UIDropDownMenu_AddButton(info)
	end
end

local function GetQuestTagID(questID, isComplete)
	local data = questInfos[questID]
	if not data then return end
	
	-- bits 4-13, 10 bits = quest tag
	local tagID = bit64:GetBits(data, 4, 10)
	
	if tagID ~= 0 then
		-- if there is a tagID, process it
		if tagID == QUEST_TAG_ACCOUNT then
			local factionGroup = GetQuestFactionGroup(questID)
			if factionGroup then
				return (factionGroup == LE_QUEST_FACTION_HORDE) and "HORDE" or "ALLIANCE"
			else
				return QUEST_TAG_ACCOUNT
			end
		end
		return tagID	-- might be raid/dungeon..
	end

	-- needs checking, this does not apply to retail
	-- old version was always nil in retail
	-- if isComplete and isComplete ~= 0 then
		-- return (isComplete < 0) and "FAILED" or "COMPLETED"
	-- end
	
	if isComplete then
		return "COMPLETED"
	end
	

	-- at this point, isComplete is either nil or 0
	if bit64:TestBit(data, 14) then return "DAILY" end		-- isDaily ?
	if bit64:TestBit(data, 15) then return "WEEKLY" end	-- isWeekly ?
end

local function InjectCallingsAsEmissaries()
	-- simply loop through all characters, and add the callings to the emissaries table
	for _, character in pairs(allCharacters) do
		
		if character.Callings then
			for questID, _ in pairs(character.Callings) do
				emissaryQuests[questID] = 8	-- 8 as Shadowlands is EXPANSION_NAME8
				
				-- if the calling quest has not yet been taken at the npc (so it is only still in the Callings list)
				-- the it will not be enough to just inject it, since the quest log won't find the quest and populate the data.

				if not character.Emissaries[questID] then
					local questTitle = C_TaskQuest.GetQuestInfoByQuestID(questID)
					local objective, _, _, numFulfilled, numRequired = GetQuestObjectiveInfo(questID, 1, false)
					
					character.Emissaries[questID] = format("%d|%d|%d|%s|%d|%s", numFulfilled, numRequired, 
						C_TaskQuest.GetQuestTimeLeftMinutes(questID), objective or " ", time(), questTitle)
				end
			end
		end
	end
end

-- *** Scanning functions ***
local headersState = {}

local function SaveHeaders()
	local headerCount = 0		-- use a counter to avoid being bound to header names, which might not be unique.

	for i = API_GetNumQuestLogEntries(), 1, -1 do		-- 1st pass, expand all categories
		local _, _, _, isHeader, isCollapsed = API_GetQuestInfo(i)
	
		if isHeader then
			headerCount = headerCount + 1
			if isCollapsed then
				ExpandQuestHeader(i)
				headersState[headerCount] = true
			end
		end
	end
end

local function RestoreHeaders()
	local headerCount = 0
	for i = API_GetNumQuestLogEntries(), 1, -1 do
		local _, _, _, isHeader = API_GetQuestInfo(i)
		
		if isHeader then
			headerCount = headerCount + 1
			if headersState[headerCount] then
				CollapseQuestHeader(i)
			end
		end
	end
	wipe(headersState)
end

local function ScanChoices(rewards, questID)
	-- rewards = out parameter

	-- these are the actual item choices proposed to the player
	for i = 1, GetNumQuestLogChoices(questID) do
		local _, _, numItems, _, isUsable = GetQuestLogChoiceInfo(i)
		isUsable = isUsable and 1 or 0	-- this was 1 or 0, in WoD, it is a boolean, convert back to 0 or 1
		local link = GetQuestLogItemLink("choice", i)
		if link then
			local id = tonumber(link:match("item:(%d+)"))
			if id then
				TableInsert(rewards, format("c|%d|%d|%d", id, numItems, isUsable))
			end
		end
	end
end

local function ScanRewards(rewards)
	-- rewards = out parameter

	-- these are the rewards given anyway
	for i = 1, GetNumQuestLogRewards() do
		local _, _, numItems, _, isUsable = GetQuestLogRewardInfo(i)
		isUsable = isUsable and 1 or 0	-- this was 1 or 0, in WoD, it is a boolean, convert back to 0 or 1
		
		local link = GetQuestLogItemLink("reward", i)
		if link then
			local id = tonumber(link:match("item:(%d+)"))
			if id then
				TableInsert(rewards, format("r|%d|%d|%d", id, numItems, isUsable))
			end
		end
	end
end

local function ScanRewardSpells(rewards, questID)
	-- rewards = out parameter

	for _, spellID in ipairs(C_QuestInfoSystem.GetQuestRewardSpells(questID) or {}) do
		if spellID and spellID > 0 then
			local spellInfo = C_QuestInfoSystem.GetQuestRewardSpellInfo(questID, spellID);
			
			if spellInfo and (spellInfo.isTradeskill or spellInfo.isSpellLearned) then
				TableInsert(rewards, format("s|%d", spellID))
			end
		end
	end
end

local function ScanQuests()
	local char = thisCharacter
	local quests = char.Quests
	local headers = char.QuestHeaders
	local rewards = char.Rewards
	local emissaries = char.Emissaries

	wipe(quests)
	wipe(headers)
	wipe(rewards)
	
	-- wipe(emissaries)
	-- We do not want to delete all emissaries, some may have just been injected
	for questID, expansionLevel in pairs(emissaryQuests) do
		-- if they are not from shadowlands .. then they may be wiped
		if expansionLevel < 8 then
			emissaries[questID] = nil
		end
	end

	local currentSelection = API_GetSelectedQuest()		-- save the currently selected quest
	SaveHeaders()

	local rewardsCache = {}
	local lastHeaderIndex = 0
	local lastQuestIndex = 0
	
	for i = 1, API_GetNumQuestLogEntries() do

		local title, level, groupSize, isHeader, isCollapsed, isComplete, 
				frequency, questID, isTask, isBounty, isStory, isHidden, suggestedGroup	= API_GetQuestInfo(i)
		if title then -- Blizzard sometimes returns nil for quest info. Assume a quest without a title means no information is available
			if isHeader then
				TableInsert(headers, title or "")
				lastHeaderIndex = lastHeaderIndex + 1
			else
				API_SetSelectedQuest(isRetail and questID or i)
				
				local value = (isComplete and isComplete > 0) and 1 or 0		-- bit 0 : isComplete
				value = value 
						+ bit64:LeftShift(lastHeaderIndex, 1)						-- bits 1-5 : index of the header (zone) to which this quest belongs
						+ bit64:LeftShift(questID, 6)									-- bits 6-23 : questID
						+ bit64:LeftShift(GetQuestLogRewardMoney(), 24)			-- bits 24+ : money
				
				TableInsert(quests, value)
				lastQuestIndex = lastQuestIndex + 1
				
				if not isRetail then
					questTitles[questID] = title
				end

				SetQuestInfo(questID,
					(frequency == API_DailyFrequency) and 1 or 0,
					(frequency == API_WeeklyFrequency) and 1 or 0,
					isTask and 1 or 0,
					isBounty and 1 or 0,
					isStory and 1 or 0,
					isHidden and 1 or 0,
					(groupSize == 0) and 1 or 0,
					suggestedGroup, level)

				-- is the quest an emissary quest ?
				-- Note: this will also process callings, since they were injected earlier
				if emissaryQuests[questID] then
					local objective, _, _, numFulfilled, numRequired = GetQuestObjectiveInfo(questID, 1, false)
					emissaries[questID] = format("%d|%d|%d|%s|%d|%s", numFulfilled, numRequired, C_TaskQuest.GetQuestTimeLeftMinutes(questID), objective or "", time(), title)
				end

				wipe(rewardsCache)
				ScanChoices(rewardsCache, questID)
				ScanRewards(rewardsCache)
				ScanRewardSpells(rewardsCache, questID)

				if #rewardsCache > 0 then
					rewards[lastQuestIndex] = TableConcat(rewardsCache, ",")
				end
			end
		end
	end

	RestoreHeaders()
	API_SetSelectedQuest(currentSelection)		-- restore the selection to match the cursor, must be properly set if a user abandons a quest

	char.lastUpdate = time()
	
	AddonFactory:Broadcast("DATASTORE_QUESTLOG_SCANNED", char)
end

local function ScanCallings(bountyInfo)
	if not bountyInfo or not C_CovenantCallings.AreCallingsUnlocked() then return end

	local char = thisCharacter
	char.Callings = (#bountyInfo > 0) and {} or nil
	
	for _, bounty in pairs(bountyInfo) do
		local questID = bounty.questID
		local timeRemaining = C_TaskQuest.GetQuestTimeLeftMinutes(questID) or 0
		
		char.Callings[questID] = format("%s|%s", timeRemaining, bounty.icon)
	end
	
	InjectCallingsAsEmissaries()
end


-- *** Event Handlers ***
local function OnPlayerAlive()
	ScanQuests()
end

local function OnQuestLogUpdate()
	addon:StopListeningTo("QUEST_LOG_UPDATE")		-- .. and unregister it right away, since we only want it to be processed once (and it's triggered way too often otherwise)
	ScanQuests()
end

local function OnUnitQuestLogChanged()			-- triggered when accepting/validating a quest .. but too soon to refresh data
	addon:ListenTo("QUEST_LOG_UPDATE", OnQuestLogUpdate)		-- so register for this one ..
end

local function OnCovenantCallingsUpdated(event, bountyInfo)
	-- source: https://wow.gamepedia.com/COVENANT_CALLINGS_UPDATED
	ScanCallings(bountyInfo)
end


-- ** Mixins **
local function _GetEmissaryQuests()
	return emissaryQuests
end

local function _IsEmissaryQuest(questID)
	return emissaryQuests[questID] and true or false
end

local function _GetEmissaryQuestInfo(character, questID)
	local quest = character.Emissaries[questID]
	if not quest then return end

	local numFulfilled, numRequired, timeLeft, objective, timeSaved, questName = strsplit("|", quest)

	numFulfilled = tonumber(numFulfilled) or 0
	numRequired = tonumber(numRequired) or 0
	timeLeft = (tonumber(timeLeft) or 0) * 60		-- we want the time left to be in seconds
	
	if timeLeft > 0 then
		local secondsSinceLastUpdate = time() - character.lastUpdate
		if secondsSinceLastUpdate > timeLeft then		-- if the info has expired ..
			character.Emissaries[questID] = nil			-- .. clear the entry
			return
		end
		
		timeLeft = timeLeft - secondsSinceLastUpdate
	end

	local expansionLevel = emissaryQuests[questID]
	
	return numFulfilled, numRequired, timeLeft, objective, questName, expansionLevel
end

local function _GetQuestGroupSize(questID)
	local data = questInfos[questID]
	
	-- bit 21-23 : groupSize, 3 bits, shouldn't exceed 5
	return data and bit64:GetBits(data, 21, 3) or 0
end

local function _GetQuestName(questID)
	return GetQuestTitle(questID) or "querying.."
end

local function _GetQuestLevel(questID)
	local data = questInfos[questID]
	
	-- bit 24-31 : level
	return data and bit64:GetBits(data, 24, 8) or 0
end

local function _GetQuestLogSize(character)
	return #character.Quests
end

local function _GetQuestLogID(character, index)
	local quest = character.Quests[index]
	
	-- bits 6-23 : questID
	return quest and bit64:GetBits(quest, 6, 18) or 0
end

local function _GetQuestLogTag(character, index)
	local quest = character.Quests[index]
	if not quest then return end		

	local questID = bit64:GetBits(quest, 6, 18)
	local isComplete = bit64:TestBit(quest, 0)
	
	return GetQuestTagID(questID, isComplete)
end

local function _GetQuestLogLink(character, index)
	return BuildQuestLink(_GetQuestLogID(character, index))
end

local function _IsQuestCompleted(character, index)
	local quest = character.Quests[index]
	
	-- bit 0 : isComplete
	return quest and bit64:TestBit(quest, 0)
end

local function QuestBit(questID, bit)
	local data = questInfos[questID]
	return data and bit64:TestBit(data, bit)
end

local function _GetQuestHeaders(character)
	return character.QuestHeaders
end

local function _GetQuestLogMoney(character, index)
	local info = character.Quests[index]
	return info and bit64:RightShift(info, 24) or 0
end

local function _GetQuestLogNumRewards(character, index)
	local reward = character.Rewards[index]
	
	-- returns the number of rewards (=count of ^ +1)
	return reward 
		and select(2, gsub(reward, ",", ",")) + 1 
		or 0
end

local function _GetQuestLogRewardInfo(character, index, rewardIndex)
	local reward = character.Rewards[index]
	if not reward then return end

	local i = 1
	for v in reward:gmatch("([^,]+)") do
		if rewardIndex == i then
			local rewardType, id, numItems, isUsable = strsplit("|", v)

			numItems = tonumber(numItems) or 0
			isUsable = (isUsable and isUsable == 1) and true or nil

			return rewardType, tonumber(id), numItems, isUsable
		end
		i = i + 1
	end
end

local function _IsCharacterOnQuest(character, questID)
	for index, quest in ipairs(character.Quests) do
		local id = bit64:GetBits(quest, 6, 18)
		
		if questID == id then
			return true, index		-- return 'true' if the id was found, also return the index at which it was found
		end
	end
	
	-- Callings will be empty for non-retail, we can leave it as is.
	-- If not in the quest log, it may be a Calling (even not yet accepted and not yet in the quest log)
	if character.Callings then
		for callingQuestID, _ in pairs(character.Callings) do
			if questID == callingQuestID then
				return true, nil
			end
		end
	end
end

local function _GetCharactersOnQuest(questName, player, realm, account)
	-- Get the characters of the current realm that are also on a given quest
	local out = {}
	account = account or DataStore.ThisAccount
	realm = realm or DataStore.ThisRealm

	for id, character in pairs(allCharacters) do
		local accountName, realmName, characterName = DataStore:GetCharacterInfoByID(id)

		-- all players except the one passed as parameter on that account & that realm
		if account == accountName and realm == realmName and player ~= characterName then
			-- Loop through quests..
			for index, quest in ipairs(character.Quests) do
				local questID = bit64:GetBits(quest, 6, 18)
				
				if questName == _GetQuestName(questID) then		-- same quest found ?
					TableInsert(out, DataStore:GetCharacterKey(id))
				end
			end
		end
	end

	return out
end

local function _IterateQuests(character, category, callback)
	-- category : category index (or 0 for all)
	
	-- Loop through quests..
	for index, quest in ipairs(character.Quests) do
		local headerIndex = bit64:GetBits(quest, 1, 5)		-- bits 1-5 : index of the header (zone) to which this quest belongs
		
		-- filter quests that are in the right category
		if (category == 0) or (category == headerIndex) then
			local stop = callback(index)
			if stop then return end		-- exit if the callback returns true
		end
	end
end

local function _GetQuestLink(questID, questTitle)
	if questID and questTitle then
		-- Ex: "|cffffff00|Hquest:65436:2573|h[The Dragon Isles Await]|h|r"
		return format("|cffffff00|Hquest:%d:-1|h[%s]|h|r", questID, questTitle)
	end
end

AddonFactory:OnAddonLoaded(addonName, function()
	DataStore:RegisterModule({
		addon = addon,
		addonName = addonName,
		rawTables = {
			"DataStore_Quests_Infos",
			"DataStore_Quests_Colors",
			"DataStore_Quests_Options"
		},
		characterTables = {
			["DataStore_Quests_Characters"] = {
				GetQuestLogSize = _GetQuestLogSize,
				GetQuestHeaders = _GetQuestHeaders,
				GetQuestLogID = _GetQuestLogID,
				GetQuestLogTag = _GetQuestLogTag,
				GetQuestLogLink = _GetQuestLogLink,
				GetQuestLogMoney = _GetQuestLogMoney,
				GetQuestLogNumRewards = _GetQuestLogNumRewards,
				GetQuestLogRewardInfo = _GetQuestLogRewardInfo,
				GetEmissaryQuestInfo = isRetail and _GetEmissaryQuestInfo,
				IsQuestCompleted = _IsQuestCompleted,
				IsCharacterOnQuest = _IsCharacterOnQuest,
				IterateQuests = _IterateQuests,
			},
		},
	})

	DataStore:RegisterMethod(addon, "IsQuestDaily", function(questID) return QuestBit(questID, 14) end)
	DataStore:RegisterMethod(addon, "IsQuestWeekly", function(questID) return QuestBit(questID, 15) end)
	DataStore:RegisterMethod(addon, "IsQuestTask", function(questID) return QuestBit(questID, 16) end)
	DataStore:RegisterMethod(addon, "IsQuestBounty", function(questID) return QuestBit(questID, 17) end)
	DataStore:RegisterMethod(addon, "IsQuestStory", function(questID) return QuestBit(questID, 18) end)
	DataStore:RegisterMethod(addon, "IsQuestHidden", function(questID) return QuestBit(questID, 19) end)
	DataStore:RegisterMethod(addon, "IsQuestSolo", function(questID) return QuestBit(questID, 20) end)

	DataStore:RegisterMethod(addon, "GetQuestName", _GetQuestName)
	DataStore:RegisterMethod(addon, "GetQuestLevel", _GetQuestLevel)
	DataStore:RegisterMethod(addon, "GetQuestGroupSize", _GetQuestGroupSize)
	DataStore:RegisterMethod(addon, "GetCharactersOnQuest", _GetCharactersOnQuest)
	DataStore:RegisterMethod(addon, "GetQuestLink", _GetQuestLink)

	if isRetail then
		DataStore:RegisterMethod(addon, "IsEmissaryQuest", _IsEmissaryQuest)
		DataStore:RegisterMethod(addon, "GetEmissaryQuests", _GetEmissaryQuests)
	end

	thisCharacter = DataStore:GetCharacterDB("DataStore_Quests_Characters", true)
	thisCharacter.Quests = thisCharacter.Quests or {}
	thisCharacter.QuestHeaders = thisCharacter.QuestHeaders or {}
	thisCharacter.Rewards = thisCharacter.Rewards or {}
	thisCharacter.Emissaries = thisCharacter.Emissaries or {}
	
	-- Quest titles cannot be retrieved with C_QuestLog in Cataclym
	if not isRetail then
		DataStore_Quests_Titles = DataStore_Quests_Titles or {}
		questTitles = DataStore_Quests_Titles
	end
		
	allCharacters = DataStore_Quests_Characters
	questInfos = DataStore_Quests_Infos
	
	questColors = DataStore:CreateSetAndList(DataStore_Quests_Colors)
end)

AddonFactory:OnPlayerLogin(function()
	options = DataStore:SetDefaults("DataStore_Quests_Options", {
		AutoUpdateHistory = true,	-- if history has been queried at least once, auto update it at logon (fast operation - already in the game's cache)
		TrackTurnIns = true,			-- by default, save the ids of completed quests in the history
		DailyResetHour = 3,			-- Reset dailies at 3am (default value)
	})

	addon:ListenTo("PLAYER_ALIVE", OnPlayerAlive)
	addon:ListenTo("UNIT_QUEST_LOG_CHANGED", OnUnitQuestLogChanged)
	
	if isRetail then
		addon:ListenTo("WORLD_QUEST_COMPLETED_BY_SPELL", ScanQuests)
		addon:ListenTo("COVENANT_CALLINGS_UPDATED", OnCovenantCallingsUpdated)
	
		InjectCallingsAsEmissaries()
	else
		addon:SetupOptions()

		-- Daily Reset Drop Down & label
		local frame = DataStore.Frames.QuestsOptions.DailyResetDropDownLabel
		frame:SetText(format("|cFFFFFFFF%s:", L["DAILY_QUESTS_RESET_LABEL"]))

		frame = DataStore_Quests_DailyResetDropDown
		UIDropDownMenu_SetWidth(frame, 60)

		-- This line causes tainting, do not use as is
		-- UIDropDownMenu_Initialize(frame, DailyResetDropDown_Initialize)
		frame.displayMode = "MENU"
		frame.initialize = DailyResetDropDown_Initialize
		
		UIDropDownMenu_SetSelectedValue(frame, options.DailyResetHour)
	end
end)
