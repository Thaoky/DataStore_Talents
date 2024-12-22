--[[	*** DataStore_Talents ***
Written by : Thaoky, EU-Marécages de Zangar
June 23rd, 2009
--]]
if not DataStore then return end

local addonName, addon = ...
local thisCharacter

local DataStore = DataStore

local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

local enum = DataStore.Enum
local bit64 = LibStub("LibBit64")

local AddonDB_Defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"] 
				lastUpdate = nil,
				Class = nil,							-- englishClass
				
				-- ** Non-retail **
				PointsSpent = "",		-- "51,5,15 ...	" 	3 numbers for primary spec, 3 for secondary, comma separated
				TalentTrees = {
					['*'] = {		-- "Fire"	= Mage Fire tree, secondary
						['*'] = 0
					}
				},				
				
				-- ** Retail **
				Specializations = {},

			}
		}
	}
}

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

-- *** Utility functions ***
local bAnd = bit.band
local RShift = bit.rshift
local LShift = bit.lshift

local function GetVersion()
	local _, version = GetBuildInfo()
	return tonumber(version)
end

local BACKGROUND_PATH = "Interface\\TalentFrame\\"

-- *** Scanning functions ***
local function ScanTalents_NonRetail()
	local char = addon.ThisCharacter
	local _, englishClass = UnitClass("player")
	char.Class = englishClass
	char.lastUpdate = time()

	-- Don't scan anything more for low level characters, but to be sure the entry is created in the DB, at least store the class
	local level = UnitLevel("player")
	if not level or level < 15 then return end		-- don't scan anything for low level characters
	
	wipe(char.TalentTrees)
	
	local points = {}

	for tabNum = 1, GetNumTalentTabs() do						-- all tabs
		local name, _, pointsSpent = GetTalentTabInfo(tabNum)
		table.insert(points, pointsSpent)
		
		for talentNum = 1, GetNumTalents(tabNum) do			-- all talents
			local _, _, _, _, currentRank = GetTalentInfo(tabNum, talentNum)

			char.TalentTrees[name][talentNum] = currentRank
		end
	end
	
	char.PointsSpent = table.concat(points, ",")
end

local function ScanTalentReference_NonRetail()
	local level = UnitLevel("player")
	if not level or level < 10 then return end		-- don't scan anything for low level characters
	
	local _, englishClass = UnitClass("player")
	local ref = addon.ref.global[englishClass]		-- point to global.["MAGE"]

	local order = {}									-- order of the talent tabs	
	
	-- first talent tree, gather reference + user specific
	for tabNum = 1, GetNumTalentTabs() do
		local talentTabName, _, _, fileName = GetTalentTabInfo(tabNum)
		order[tabNum] = talentTabName
		
		local ti = ref.Trees[talentTabName]		-- ti for talent info

		ti.background = fileName
			
		for talentNum = 1, GetNumTalents(tabNum) do
			local nameTalent, iconPath, tier, column, _, maximumRank = GetTalentInfo(tabNum, talentNum)
			ti.talents[talentNum] = format("%s|%s|%s|%s|%s", nameTalent, iconPath, tier, column, maximumRank)
			
			prereqTier, prereqColumn = GetTalentPrereqs(tabNum, talentNum)		-- talent prerequisites
			if prereqTier and prereqColumn then
				ti.prereqs[talentNum] = format("%s|%s", prereqTier, prereqColumn)
			end
		end
	end
	
	-- save the order of talent tabs, this is necessary because the order of talent tabs is not the same as that of spell tabs in all languages/classes
	-- it is fine in enUS, but not in frFR (druid at least did not match)
	ref["Order"] = table.concat(order, ",")
	
	for i = 2, 4 do
		local name, icon = GetSpellTabInfo(i)		-- skip spell tab 1, it's the general tab
		
		-- the icon may be nil on a low level char. 
		-- Example : rogue lv 2
			-- GetSpellTabInfo(1) returns the General tab
			-- GetSpellTabInfo(2) returns the Assassination tab
			-- GetSpellTabInfo(3) returns the Combat tab
			-- GetSpellTabInfo(4) returns nil, instead of Subtelty
		if name and icon then
			local ti = ref.Trees[name]		-- ti for talent info
			ti.icon = icon
		end
	end	
end


local function ScanTalents_Retail()
	local char = addon.ThisCharacter
	local _, englishClass = UnitClass("player")
	char.Class = englishClass
	char.lastUpdate = time()

	-- Don't scan anything more for low level characters, but to be sure the entry is created in the DB, at least store the class
	local level = UnitLevel("player")
	if not level or level < 10 then return end		
	
	local ref = addon.ref.global[englishClass]
	ref.Version = GetVersion()
	ref.Locale = GetLocale()
	
	local attrib = 0
	local offset = 0
	
	for tier = 1, GetMaxTalentTier() do
		for column = 1, 3 do
			local _, _, _, isSelected = GetTalentInfo(tier, column, 1)		-- param 3 = spec group, always 1 since 7.0
			
			if isSelected then
				-- basically save each tier on 2 bits : 00 = no talent on this tier, 01 = column 1, 10 = column 2, 11 = column 3
				attrib = attrib + LShift(column, offset)
				
				break		-- selected talent found on this line, quit this inner-loop
			end
		end
		
		offset = offset + 2		-- each rank takes 2 bits (values 0 to 3)
	end
	
	local specIndex = GetSpecialization()

	char.Specializations[specIndex] = attrib
end

local function ScanTalentReference_Retail()
	local level = UnitLevel("player")
	if not level or level < 15 then return end		-- don't scan anything for low level characters
	
	local _, englishClass = UnitClass("player")
	local ref = addon.ref.global[englishClass]		-- point to global.["MAGE"]
	
	ref.Version = GetVersion()
	ref.Locale = GetLocale()

	local currentSpec = GetSpecialization()
	local _, _, classID = UnitClass("player")
	
	for specIndex = 1, GetNumSpecializations() do
		ref.Specializations[specIndex] = ref.Specializations[specIndex] or {}
		local specRef = ref.Specializations[specIndex]
		local specID = GetSpecializationInfo(specIndex)
		
		specRef.id = specID
		
		-- Scan the talent tree, only for the current spec
		if specIndex == currentSpec then
			wipe(specRef.talents)
			
			for tier = 1, GetMaxTalentTier() do
				for column = 1, 3 do
					local talentID = GetTalentInfo(tier, column, 1)		-- param 3 = spec group, always 1 since 7.0
					-- Retrieve info with : GetTalentInfoByID(talentID)
					
					table.insert(specRef.talents, talentID)
				end
			end
		end
	end
end


-- *** Event Handlers ***
local function OnPlayerAlive()
	if isRetail then
		ScanTalents_Retail()
		ScanTalentReference_Retail()
	else
		ScanTalents_NonRetail()
		ScanTalentReference_NonRetail()
	end
end

local function OnPlayerSpecializationChanged()
	ScanTalents_Retail()
	ScanTalentReference_Retail()
end


-- ** Mixins **
local function _GetReferenceTable()
	return addon.ref.global
end

local function	_GetClassReference(class)
	if type(class) == "string" then
		return addon.ref.global[class]
	end
end

local function _IsClassKnown(class)
	class = class or ""	-- if by any chance nil is passed, trap it to make sure the function does not fail, but returns nil anyway
	
	local ref = _GetClassReference(class)
	if ref.Locale or ref.Order then		-- if the Locale field is not nil, we have data for this class (or .Order for non-retail)
		return true
	end
end

local function _ImportClassReference(class, data)
	assert(type(class) == "string")
	assert(type(data) == "table")
	
	addon.ref.global[class] = data
end

-- ** Mixins - Non-Retail **
local function _GetTreeReference(class, tree)
	assert(type(class) == "string")
	assert(type(tree) == "string")
	return addon.ref.global[class].Trees[tree]
end

local function _GetClassTrees(class)
	assert(type(class) == "string")
	
	local ref = _GetClassReference(class)
	local order = ref.Order
	if order then
		return order:gmatch("([^,]+)")
	end
	-- to do, add a return value that does not require validity testing by the caller
end

local function _GetTreeInfo(class, tree)
	local t = _GetTreeReference(class, tree)
	
	if t then
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

local function _GetTalentRank(character, tree, index)
	return character.TalentTrees[tree][index]
end

local function _GetNumPointsSpent(character, tree)
	local index = 1
	for treeName in _GetClassTrees(character.Class) do
		if treeName == tree then
			break
		end
		index = index + 1
	end
	
	if index == 4 then return end				-- = 4 means tree was not found
	
	-- index = index + ((specNum-1) * 3)
	
	return select(index, strsplit(",", character.PointsSpent)) or 0
end
	
local function _GetTalentPrereqs(class, tree, index)
	local t = _GetTreeReference(class, tree)
	local prereq = t.prereqs[index]
		
	if prereq then
		local prereqTier, prereqColumn = strsplit("|", prereq)
		return tonumber(prereqTier), tonumber(prereqColumn)
	end
end

local function _GetMainSpecialization(character)
	local index = 1
	local numPoints = 0
	local mainTree = NONE
	
	-- Low level alts may not have any data yet ..
	if not character.PointsSpent or character.PointsSpent == "" or not character.Class then
		return mainTree
	end
	
	local points = {strsplit(",", character.PointsSpent)}
	
	for treeName in _GetClassTrees(character.Class) do
		points[index] = tonumber(points[index])
		
		if points[index] > numPoints then
			mainTree = treeName
			numPoints = points[index]
		end
		index = index + 1
	end
	
	return mainTree
end


-- ** Mixins - Retail **
local function _GetSpecializationReference(class, spec)
	assert(type(class) == "string")
	assert(type(spec) == "number")
	
	return addon.ref.global[class].Specializations[spec]
end

local function _GetSpecializationInfo(class, specialization)
	local spec = _GetSpecializationReference(class, specialization)
	if spec and spec.id then 
		return GetSpecializationInfoByID(spec.id)
	end
end

local function _GetTalentInfo_Retail(class, specialization, row, column)
	local spec = _GetSpecializationReference(class, specialization)
	if not spec then return end
	
	local index = ((row - 1) * 3) + column		-- ex: row 2, column 1 = index 4
	local talentID = spec.talents[index]
	
	if talentID then
		-- id, name, texture, ...
		return GetTalentInfoByID(talentID)
	end
end

local function _GetSpecializationTierChoice(character, specialization, row)
	local attrib = character.Specializations[specialization]
	
	if attrib then
		return bAnd(RShift(attrib, (row-1)*2), 3)
	end
end

local function _IterateTalentTiers(callback)
	for tierIndex, level in ipairs(enum.TalentTiersSorted) do
		callback(tierIndex, level)
	end
end


local PublicMethods = {
	GetReferenceTable = _GetReferenceTable,
	GetClassReference = _GetClassReference,
	IsClassKnown = _IsClassKnown,
	ImportClassReference = _ImportClassReference,
}

if isRetail then
	PublicMethods.GetSpecializationInfo = _GetSpecializationInfo
	PublicMethods.GetTalentInfo = _GetTalentInfo_Retail
	PublicMethods.GetSpecializationTierChoice = _GetSpecializationTierChoice

	PublicMethods.IterateTalentTiers = _IterateTalentTiers

else
	PublicMethods.GetTreeReference = _GetTreeReference
	PublicMethods.GetClassTrees = _GetClassTrees
	PublicMethods.GetTreeInfo = _GetTreeInfo
	PublicMethods.GetTreeNameByID = _GetTreeNameByID
	PublicMethods.GetTalentLink = _GetTalentLink
	PublicMethods.GetNumTalents = _GetNumTalents
	PublicMethods.GetTalentInfo = _GetTalentInfo_NonRetail
	PublicMethods.GetTalentRank = _GetTalentRank
	PublicMethods.GetNumPointsSpent = _GetNumPointsSpent
	PublicMethods.GetTalentPrereqs = _GetTalentPrereqs
	PublicMethods.GetMainSpecialization = _GetMainSpecialization
end

AddonFactory:OnAddonLoaded(addonName, function() 
	DataStore:RegisterModule({
		addon = addon,
		addonName = addonName,
		characterTables = {
			["DataStore_Talents_Characters"] = {

			},
		}
	})


	-- addon.db = LibStub("AceDB-3.0"):New(addonName .. "DB", AddonDB_Defaults)
	-- addon.ref = LibStub("AceDB-3.0"):New(addonName .. "RefDB", ReferenceDB_Defaults)

	-- DataStore:RegisterModule(addonName, addon, PublicMethods)

	-- if isRetail then
		-- DataStore:SetCharacterBasedMethod("GetSpecializationTierChoice")

	-- else
		-- DataStore:SetCharacterBasedMethod("GetTalentRank")
		-- DataStore:SetCharacterBasedMethod("GetNumPointsSpent")
		-- DataStore:SetCharacterBasedMethod("GetMainSpecialization")
	-- end
end)

AddonFactory:OnPlayerLogin(function() 
	-- addon:RegisterEvent("PLAYER_ALIVE", OnPlayerAlive)
	
	-- if isRetail then
		-- addon:RegisterEvent("PLAYER_TALENT_UPDATE", ScanTalents_Retail)
		-- addon:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", OnPlayerSpecializationChanged)
		
	-- else
		-- addon:RegisterEvent("CHARACTER_POINTS_CHANGED", ScanTalents_NonRetail)
	-- end
end)
