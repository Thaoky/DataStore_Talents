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

	local currentSpecGroup = C_SpecializationInfo.GetActiveSpecGroup()
	char.CurrentSpecGroup = currentSpecGroup
	
	Initialize_Specialization(char, currentSpecGroup)

	-- Start the reference tree
	-- Reset the talent trees if the version was changed (who knows what they changed)
	if not addon.ref.global[englishClass] or addon.ref.global[englishClass].Version ~= currentVersion then
		SetClassReferenceTalentDefaults(englishClass)
	end
	local ref = addon.ref.global[englishClass]		-- point to global.["MAGE"]
	local order = {}									-- order of the talent tabs	

	-- See how many specs we need to scan
	--print(DataStore:GetNumSpecGroups())

	local points = {}

	for tabNum = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) do						-- all tabs
		local specId, name, description, icon, role, primaryStat, pointsSpent, background, previewPointsSpent, isUnlocked = C_SpecializationInfo.GetSpecializationInfo(tabNum)

		-- Reference information
		order[tabNum] = name
		SetTreeReferenceDefaults(ref.Trees, name)
		local ti = ref.Trees[name]		-- ti for talent info
		ti.background = background
		ti.icon = icon
		----

		table.insert(points, pointsSpent)
		char.SpecGroup[currentSpecGroup].TalentTrees[name] = char.SpecGroup[currentSpecGroup].TalentTrees[name] or {}

		local query = {["specializationIndex"] = tabNum, ["target"] = "player", ["talentIndex"] = 1}
		local talentInfo = C_SpecializationInfo.GetTalentInfo(query)
		while talentInfo ~= nil do -- loop the tree
			ti.talents[query.talentIndex] = format("%s|%s|%s|%s|%s", talentInfo.name, talentInfo.icon, talentInfo.tier, talentInfo.column, talentInfo.maxRank)

			local prereqTier, prereqColumn = GetTalentPrereqs(tabNum, query.talentIndex)		-- talent prerequisites
			if prereqTier and prereqColumn then
				ti.prereqs[query.talentIndex] = format("%s|%s", prereqTier, prereqColumn)
			end

			char.SpecGroup[currentSpecGroup].TalentTrees[name][ query["talentIndex"] ] = talentInfo.rank
			query["talentIndex"] = query["talentIndex"] + 1
			talentInfo = C_SpecializationInfo.GetTalentInfo(query)
		end
	end

	char.SpecGroup[currentSpecGroup].PointsSpent = table.concat(points, ",")
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

local function _GetTalentRank(character, tree, index, specGroup)
	if not character.SpecGroup then return nil end
	return character.SpecGroup[specGroup or 1].TalentTrees[tree][index]
end

local function _GetNumPointsSpent(character, tree, specGroup)
	local index = 1
	--for treeName in _GetClassTrees(character.Class) do
	for treeName in DataStore:GetClassTrees(character.Class) do
		if treeName == tree then
			break
		end
		index = index + 1
	end
	
	if index == 4 then return end				-- = 4 means tree was not found
	
	-- index = index + ((specNum-1) * 3)
	if not character.SpecGroup then return 0 end
	return select(index, strsplit(",", character.SpecGroup[specGroup or 1].PointsSpent or "")) or 0
end

local function _GetActiveSpecInfo(character)
	local index = 1
	local numPoints = 0
	local mainTree = NONE
	-- These can be updated by brute force in non-specialization versions
	local specID, specRole = 0, ""

	if not character.CurrentSpecGroup then return mainTree end

	-- Low level alts may not have any data yet ..
	if character.SpecGroup[character.CurrentSpecGroup].PointsSpent then
		local points = {strsplit(",", character.SpecGroup[character.CurrentSpecGroup].PointsSpent)}
		for treeName, v in _GetClassTrees(character.Class) do
			points[index] = tonumber(points[index])
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
				GetTalentRank = _GetTalentRank,
				GetNumPointsSpent = _GetNumPointsSpent,
				GetActiveSpecInfo = _GetActiveSpecInfo
			},
		}
	})

	DataStore_TalentsDB = DataStore_TalentsDB or {}
	DataStore_TalentsRefDB = DataStore_TalentsRefDB or ReferenceDB_Defaults

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
end)
