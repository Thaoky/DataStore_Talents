-- Only valid for expansions that use talent rows
if LE_EXPANSION_LEVEL_CURRENT < LE_EXPANSION_MISTS_OF_PANDARIA or LE_EXPANSION_LEVEL_CURRENT > LE_EXPANSION_SHADOWLANDS then return end

local addonName, addon = ...
local thisCharacter

local specializations
local specInfos

local DataStore = DataStore
local GetSpecialization, GetSpecializationInfo = GetSpecialization, GetSpecializationInfo

local bit64 = LibStub("LibBit64")

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
				},
			},
			Talents = {
				['*'] = {}	-- row with indices of 1-3 with talentID as value
			},
		},
	}
}
--[[
				CurrentSpecGroup = 1, 		-- default to the first (or only) specialization group 
				SpecGroup = {
					['*'] = { 				-- 1 or 2, depending on dual talent spec availability
						PointsSpent = "",	-- "51,5,15 ...	" 	3 numbers for primary spec, 3 for secondary, comma separated
						SpecName = "",
						SpecIndex = "",		-- Index in the 'Order'
						TalentTrees = {		-- Classic/Burning Crusade
							['*'] = {		-- "Fire"	= Mage Fire tree, secondary
								['*'] = 0
							}
						},
						TalentRows = {
							['*'] = 0		-- [Row] [column selected]
						},
					},
--]]

-- ** Utility functions **
local currentVersion = select(4, GetBuildInfo())

local function SetClassReferenceTalentDefaults(className)
	addon.ref.global[className] = {}
	for k,v in pairs(ReferenceDB_Defaults.global['*']) do
		addon.ref.global[className][k] = type(v) == type({}) and {} or v
	end

	local ref = addon.ref.global[className]
	ref.Version = currentVersion
	ref.Locale = GetLocale()
end

local function Initialize_Specialization(char, specGroup)
	-- Wipe old structure data
	char.TalentTrees = nil
	char.PointsSpent = nil
	-- Reset the structure
	char.SpecGroup = char.SpecGroup or {}
	char.SpecGroup[specGroup] = char.SpecGroup[specGroup] or {} -- create the SpecGroup
	char.SpecGroup[specGroup].TalentRows = char.SpecGroup[specGroup].TalentRows or {}
end

-- *** Scanning functions ***
local function GetSpecInfo_TalentRows()
	-- Scan the talents
	local char = thisCharacter
	local englishClass, classID = UnitClassBase("player")
	char.Class = englishClass
	char.lastUpdate = time()

	-- Talent information is now available even when the character can't see it
	-- Don't scan anything more for low level characters, but to be sure the entry is created in the DB, at least store the class
	--local level = UnitLevel("player")
	--if not level or level < 10 then return end		-- don't scan anything for low level characters

	local currentSpecGroup = C_SpecializationInfo.GetActiveSpecGroup()
	char.CurrentSpecGroup = currentSpecGroup
	Initialize_Specialization(char, currentSpecGroup)
	char.SpecGroup[currentSpecGroup].SpecIndex = C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization())

	-- Start the reference tree
	-- Reset the talent trees if the version was changed (who knows what they changed)
	if not addon.ref.global or not addon.ref.global[englishClass] or addon.ref.global[englishClass].Version ~= currentVersion then
		SetClassReferenceTalentDefaults(englishClass)
	end
	local ref = addon.ref.global[englishClass]		-- point to global.["MAGE"]

	-- Talents are now spec-agnostic
	local query = {["specializationIndex"] = 1, ["target"] = "player", ["tier"] = 1, ["column"] = 1}
	for tier = 1, 6 do
		ref.Talents[tier] = {}
		for column = 1, 3 do
			query.tier = tier
			query.column = column
			local talentInfo = C_SpecializationInfo.GetTalentInfo(query)

			ref.Talents[tier][column] = talentInfo.talentID

			-- Assume only a known talent should be saved (selected may be while choosing in the UI)
			if talentInfo.known then
				char.SpecGroup[currentSpecGroup].TalentRows[tier] = talentInfo.talentID
			end
		end
	end

	char.SpecGroup[currentSpecGroup].Glyphs = char.SpecGroup[currentSpecGroup].Glyphs or {}
	for socket = 1, GetNumGlyphSockets() do
		local enabled, glyphType, glyphIndex, glyphSpellID, iconFile, glyphID = GetGlyphSocketInfo(socket, currentSpecGroup)
		--print(enabled, glyphType, glyphIndex, glyphSpellID, iconFile, glyphID) --DAC
		if glyphID then
			local name, glyphType, isKnown, icon, spellID, link = C_GlyphInfo.GetGlyphInfoByID(glyphID)
			--print(name, glyphType, isKnown, icon, spellID, link)
			char.SpecGroup[currentSpecGroup].Glyphs[socket] = glyphID
		end
	end
end

-- *** Event Handlers ***
local function OnPlayerAlive()
	-- This now gets the class reference and the current character talents
	GetSpecInfo_TalentRows()
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

local function _GetClassTalentsReference(class)
	local ref = _GetClassReference(class)
	if ref and ref.Talents then
		return ref.Talents
	end
	return nil
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
local function _GetTalents(character, specGroup)
	--print(DevTools_Dump(character))
	return character.SpecGroup[specGroup or character.CurrentSpecGroup].TalentRows or {}
end

local function _GetSelectedTalent(character, specGroup, tier)
	return character.SpecGroup[specGroup or character.CurrentSpecGroup].TalentRows[tier]
end

local function _GetSpecIndex(character, specGroup)
	return character.SpecGroup[specGroup or character.CurrentSpecGroup].SpecIndex
end

local PublicMethods = {
	GetReferenceTable = _GetReferenceTable,
	GetClassReference = _GetClassReference,
	GetClassTalentsReference = _GetClassTalentsReference,
	IsClassKnown = _IsClassKnown,
	ImportClassReference = _ImportClassReference,
}

AddonFactory:OnAddonLoaded(addonName, function()
	DataStore:RegisterTables({
		addon = addon,
		characterTables = {
			["DataStore_Talents_Characters"] = {
				GetTalents = _GetTalents,
				GetSelectedTalent = _GetSelectedTalent,
				GetSpecIndex = _GetSpecIndex
			},
		}
	})

	DataStore_TalentsRefDB = DataStore_TalentsRefDB or ReferenceDB_Defaults
	if not DataStore_TalentsRefDB.global then DataStore_TalentsRefDB = ReferenceDB_Defaults end

	addon.ref = DataStore_TalentsRefDB
	if not addon.ref.global then
		addon.ref.global = {}
	end
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
