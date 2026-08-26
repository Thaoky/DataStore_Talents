-- Only valid for expansions that use talent trees
if LE_EXPANSION_LEVEL_CURRENT >= LE_EXPANSION_MISTS_OF_PANDARIA then return end

local addonName, addon = ...
local thisCharacter

local specializations
local specInfos

local DataStore = DataStore
local GetSpecialization, GetSpecializationInfo = GetSpecialization, GetSpecializationInfo

local bit64 = LibStub("LibBit64")
local isCataclysm = (LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CATACLYSM)
local isBurningCrusade = (LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_BURNING_CRUSADE)
local isClassic = (LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC)

local BACKGROUND_PATH = "Interface\\TalentFrame\\"
-- This table saved reference data required to rebuild a talent tree for a class when logged in under another class.
-- The API does not provide that ability, but saving and reusing is fine

local ReferenceDB_Defaults = {
	global = {
		['*'] = {							-- "englishClass" like "MAGE", "DRUID" etc..
			Version = nil,					-- build number under which this class ref was saved
			Locale = nil,					-- locale under which this class ref was saved
			Specializations = {
				['*'] = {					-- tree name
					id = nil,
					icon = nil,
					name = nil,
					talents = {},			-- name, icon, max rank etc..for talent x in this tree
				},
			},
			
			-- For non-retail
			Order = nil,
			Trees = {
				['*'] = {					-- tree name
					icon = nil,
					background = nil,
					talents = {},			-- name, icon, max rank etc..for talent x in this tree
					prereqs = {}			-- prerequisites
				},
			}
		},
	}
}

-- ** Utility functions **
local currentVersion = select(4, GetBuildInfo())

local function SetClassReferenceTalentDefaults(className)
	addon.ref.global[className] = {}
	for k,v in pairs(ReferenceDB_Defaults.global['*']) do
		addon.ref.global[className][k] = type(v) == type({}) and {} or v
	end

	local ref = addon.ref.global[className]
	--ref.Version = GetVersion()
	ref.Version = currentVersion
	ref.Locale = GetLocale()
end

local function SetTreeReferenceDefaults(treeTable, treeName)
	treeTable[treeName] = {}
	for k,v in pairs(ReferenceDB_Defaults.global['*'].Trees['*']) do
		treeTable[treeName][k] = type(v) == type({}) and {} or v
	end
end

local function Initialize_Specialization(char, specGroup)
	-- Wipe old structure data
	char.TalentTrees = nil
	char.PointsSpent = nil
	-- Reset the structure
	char.SpecGroup = char.SpecGroup or {}
	char.SpecGroup[specGroup] = char.SpecGroup[specGroup] or {} -- create the SpecGroup
	char.SpecGroup[specGroup].TalentTrees = char.SpecGroup[specGroup].TalentTrees or {}
end

-- *** Scanning functions ***
local function GetNumTalentSpecGroups()
	-- Returns the number of talent groups available to the player (2 with dual talent specialization)
	-- Both the global and the C_SpecializationInfo versions may be missing depending on the client, so stay defensive.
	if C_SpecializationInfo and C_SpecializationInfo.GetNumSpecGroups then
		local ok, num = pcall(C_SpecializationInfo.GetNumSpecGroups)
		if ok and type(num) == "number" and num > 0 then return num end
	end

	if GetNumTalentGroups then
		local ok, num = pcall(GetNumTalentGroups)
		if ok and type(num) == "number" and num > 0 then return num end
	end

	return 1
end

local function ScanSpecGroup(char, specGroup, classID, ref, order, scanReference)
	-- Scans one talent group (1 = primary, 2 = secondary/dual spec) into char.SpecGroup[specGroup]
	-- scanReference : also rebuild the class reference data (identical for all talent groups, so only done once)
	Initialize_Specialization(char, specGroup)

	local specGroupData = char.SpecGroup[specGroup]
	local points = {}

	-- Cleared upfront : if the scan fails midway, the group is left flagged as "no data" rather than half stale
	specGroupData.PointsSpent = nil

	for tabNum = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) do						-- all tabs
		local _, name, _, icon, _, _, _, background = C_SpecializationInfo.GetSpecializationInfo(tabNum)

		local ti		-- ti for talent info
		if scanReference then
			order[tabNum] = name
			SetTreeReferenceDefaults(ref.Trees, name)
			ti = ref.Trees[name]
			ti.background = background
			ti.icon = icon
		end

		local tree = specGroupData.TalentTrees[name] or {}
		specGroupData.TalentTrees[name] = tree
		wipe(tree)

		-- The points spent in a tree are the sum of the ranks of its talents. Deducing them rather than
		-- reading them from the API is what allows the inactive talent group to be scanned as well.
		local pointsSpent = 0

		local query = {["specializationIndex"] = tabNum, ["target"] = "player", ["talentIndex"] = 1, ["groupIndex"] = specGroup}
		local talentInfo = C_SpecializationInfo.GetTalentInfo(query)
		while talentInfo ~= nil do -- loop the tree
			local index = query.talentIndex

			if scanReference then
				ti.talents[index] = format("%s|%s|%s|%s|%s", talentInfo.name, talentInfo.icon, talentInfo.tier, talentInfo.column, talentInfo.maxRank)

				local prereqTier, prereqColumn = GetTalentPrereqs(tabNum, index)		-- talent prerequisites
				if prereqTier and prereqColumn then
					ti.prereqs[index] = format("%s|%s", prereqTier, prereqColumn)
				end
			end

			tree[index] = talentInfo.rank
			pointsSpent = pointsSpent + (talentInfo.rank or 0)

			query.talentIndex = index + 1
			talentInfo = C_SpecializationInfo.GetTalentInfo(query)
		end

		points[tabNum] = pointsSpent
	end

	specGroupData.PointsSpent = table.concat(points, ",")
end

local function GetSpecInfo_TalentTrees()
	-- Scan the talents
	local char = thisCharacter
	local englishClass, classID = UnitClassBase("player")
	char.Class = englishClass
	char.lastUpdate = time()

	-- Don't scan anything more for low level characters, but to be sure the entry is created in the DB, at least store the class
	local level = UnitLevel("player")
	-- Talent information is now available even when the character can't see it
	--if not level or level < 10 then return end		-- don't scan anything for low level characters

	local currentSpecGroup = C_SpecializationInfo.GetActiveSpecGroup() or 1
	char.CurrentSpecGroup = currentSpecGroup

	-- Start the reference tree
	-- Reset the talent trees if the version was changed (who knows what they changed)
	if not addon.ref.global[englishClass] or addon.ref.global[englishClass].Version ~= currentVersion then
		SetClassReferenceTalentDefaults(englishClass)
	end
	local ref = addon.ref.global[englishClass]		-- point to global.["MAGE"]
	local order = {}									-- order of the talent tabs

	-- Scan the active group first, it is the one that rebuilds the class reference
	ScanSpecGroup(char, currentSpecGroup, classID, ref, order, true)

	-- .. then the other talent groups (dual talent specialization).
	-- Reading an inactive group relies on the 'groupIndex' query field, so failing there must not lose the active group.
	for specGroup = 1, GetNumTalentSpecGroups() do
		if specGroup ~= currentSpecGroup then
			pcall(ScanSpecGroup, char, specGroup, classID, ref, order, false)
		end
	end

	-- Reference information
	ref["Order"] = table.concat(order, ",")
end

-- *** Event Handlers ***
local function OnPlayerAlive()
	-- This now gets the class reference and the current character talents
	GetSpecInfo_TalentTrees()
end

-- ** Mixins **
local function _GetReferenceTable()
	return addon.ref.global
end

local function _GetClassReference(class)
	if type(class) == "string" then
		return addon.ref.global[class]
	end
end

local function _IsClassKnown(class)
	class = class or ""	-- if by any chance nil is passed, trap it to make sure the function does not fail, but returns nil anyway
	
	local ref = _GetClassReference(class)
	if ref and (ref.Locale or ref.Order) then		-- if the Locale field is not nil, we have data for this class (or .Order for non-retail)
		return true
	end
end

local function _ImportClassReference(class, data)
	assert(type(class) == "string")
	assert(type(data) == "table")

	addon.ref.global[class] = data
end

-- ** Mixins - Non-Retail **
local function _GetClassTrees(class)
	assert(type(class) == "string")

	local ref = _GetClassReference(class)
	local order = ref.Order
	if order then
		return order:gmatch("([^,]+)")
	end
	-- to do, add a return value that does not require validity testing by the caller
end

local function _GetTreeReference(class, tree)
	assert(type(class) == "string")
	assert(type(tree) == "string")
	return addon.ref.global[class].Trees[tree]
end

local function _GetTreeInfo(class, tree)
	local t = _GetTreeReference(class, tree)

	if t then
		if t.background and tonumber(t.background) then -- Return the fileID instead of a file path
			return t.icon, t.background
		end
		return t.icon, format("%s%s", BACKGROUND_PATH, t.background)
	end
end

local function _GetTreeNameByID(class, id)
	-- returns the name of tree "id" for a given class
	assert(type(class) == "string")
	
	local index = 1
	for name in _GetClassTrees(class) do
		if index == id then
			return name
		end
		index = index + 1
	end
end

local function _GetTalentLink(id, rank, name)
	return format("|cff4e96f7|Htalent:%s:%s|h[%s]|h|r", id, (rank-1), name)
end

local function _GetNumTalents(class, tree)
	-- returns the number of talents in a given tree
	local t = _GetTreeReference(class, tree)

	if t then
		return #t.talents
	end
end

local function _GetTalentInfo_NonRetail(class, tree, index)
	local t = _GetTreeReference(class, tree)
	local talentInfo = t.talents[index]
	
	if not talentInfo then return end
	
	-- "Improved Frostbolt|135846|1|2|5", -- [2]
	local name, icon, tier, column, maximumRank	= strsplit("|", talentInfo)
	
	-- 0 used to be tonumber(id), keep for compatibility
	return 0, name, icon, tonumber(tier), tonumber(column), tonumber(maximumRank)
end

local function _GetTalentPrereqs(class, tree, index)
	local t = _GetTreeReference(class, tree)
	local prereq = t.prereqs[index]
		
	if prereq then
		local prereqTier, prereqColumn = strsplit("|", prereq)
		return tonumber(prereqTier), tonumber(prereqColumn)
	end
end

local function GetSpecGroupData(character, specGroup)
	-- Returns the saved data of a given talent group, nil if that group was never scanned
	specGroup = specGroup or character.CurrentSpecGroup
	if not specGroup or not character.SpecGroup then return end

	return character.SpecGroup[specGroup]
end

local function _HasSpecGroup(character, specGroup)
	-- Returns true if talents were saved for this talent group (ex: a character without dual spec has no group 2)
	local data = GetSpecGroupData(character, specGroup)

	return (data and data.PointsSpent and data.PointsSpent ~= "") and true or false
end

local function _GetTalentRank(character, tree, index, specGroup)
	local data = GetSpecGroupData(character, specGroup)
	if not data or not data.TalentTrees then return end

	local talents = data.TalentTrees[tree]
	return talents and talents[index]
end

local function _GetNumPointsSpent(character, tree, specGroup)
	local data = GetSpecGroupData(character, specGroup)
	if not data then return 0 end

	local index = 1
	--for treeName in _GetClassTrees(character.Class) do
	for treeName in DataStore:GetClassTrees(character.Class) do
		if treeName == tree then
			break
		end
		index = index + 1
	end

	if index == 4 then return 0 end			-- = 4 means tree was not found
	-- index = index + ((specNum-1) * 3)

	-- select() returns every value from 'index' onwards, so keep only the first one before converting
	local points = select(index, strsplit(",", data.PointsSpent or ""))
	return tonumber(points) or 0
end

local function _GetActiveSpecInfo(character)
	local index = 1
	local numPoints = 0
	local mainTree = NONE
	-- These can be updated by brute force in non-specialization versions
	local specID, specRole = 0, ""

	local data = GetSpecGroupData(character)

	-- Low level alts may not have any data yet ..
	if data and data.PointsSpent then
		local points = {strsplit(",", data.PointsSpent)}
		for treeName, v in _GetClassTrees(character.Class) do
			points[index] = tonumber(points[index]) or 0
			if points[index] > numPoints then
				mainTree = treeName
				numPoints = points[index]
			end
			index = index + 1
		end
	end

	return mainTree or "", specID, specRole
end


local PublicMethods = {
	GetReferenceTable = _GetReferenceTable,
	GetClassReference = _GetClassReference,
	IsClassKnown = _IsClassKnown,
	ImportClassReference = _ImportClassReference,
}

PublicMethods.GetTreeReference = _GetTreeReference
PublicMethods.GetClassTrees = _GetClassTrees
PublicMethods.GetTreeInfo = _GetTreeInfo
PublicMethods.GetTreeNameByID = _GetTreeNameByID
PublicMethods.GetTalentLink = _GetTalentLink
PublicMethods.GetNumTalents = _GetNumTalents
PublicMethods.GetTalentInfo = _GetTalentInfo_NonRetail
PublicMethods.GetTalentPrereqs = _GetTalentPrereqs

AddonFactory:OnAddonLoaded(addonName, function()
	--[[
	DataStore:RegisterModule({
		addon = addon,
		addonName = addonName,
		characterTables = {
			["DataStore_Talents_Characters"] = {
				GetTalentRank = _GetTalentRank,
				GetNumPointsSpent = _GetNumPointsSpent,
				GetActiveSpecInfo = _GetActiveSpecInfo
			},
		}
	})
	--]]
	DataStore:RegisterTables({
		addon = addon,
		characterTables = {
			["DataStore_Talents_Characters"] = {
				HasSpecGroup = _HasSpecGroup,
				GetTalentRank = _GetTalentRank,
				GetNumPointsSpent = _GetNumPointsSpent,
				GetActiveSpecInfo = _GetActiveSpecInfo
			},
		}
	})

	DataStore_TalentsDB = DataStore_TalentsDB or {}
	DataStore_TalentsRefDB = DataStore_TalentsRefDB or ReferenceDB_Defaults
	if not DataStore_TalentsRefDB.global then DataStore_TalentsRefDB = ReferenceDB_Defaults end

	addon.ref = DataStore_TalentsRefDB
	thisCharacter = DataStore:GetCharacterDB("DataStore_Talents_Characters", true)

	for publicMethod, actualMethod in pairs(PublicMethods) do
		DataStore:RegisterMethod(addon, publicMethod, actualMethod)
	end
end)

AddonFactory:OnPlayerLogin(function()
	addon:ListenTo("PLAYER_ENTERING_WORLD", OnPlayerAlive)
	addon:ListenTo("CHARACTER_POINTS_CHANGED", OnPlayerAlive)
	addon:ListenTo("PLAYER_TALENT_UPDATE", OnPlayerAlive)
	addon:ListenTo("ACTIVE_TALENT_GROUP_CHANGED", OnPlayerAlive)		-- dual spec swap
end)
