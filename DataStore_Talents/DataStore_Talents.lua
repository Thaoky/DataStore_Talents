--[[	*** DataStore_Talents ***
Written by : Thaoky, EU-Marécages de Zangar
June 23rd, 2009
--]]
if not DataStore then return end

local addonName, addon = ...
local thisCharacter

local DataStore = DataStore

local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local isMists = LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_MISTS_OF_PANDARIA
local isCataclysm = (LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CATACLYSM)
local isBurningCrusade = (LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_BURNING_CRUSADE)
local isClassic = (LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC)

-- GetNumSpecGroups is available in Classic/TBC, but throws an error when used
-- GetNumTalentGroups is available in Mists, but throws an error when used
local function _GetNumSpecGroups()
	if isClassic or isBurningCrusade then
		return GetNumTalentGroups()
	end
	return GetNumSpecGroups()
end

local enum = DataStore.Enum
local bit64 = LibStub("LibBit64")

local AddonDB_Defaults = {
	global = {
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"] 
				lastUpdate = nil,
				Class = nil,							-- englishClass
				
				-- ** Non-retail **
				--[[
				PointsSpent = "",		-- "51,5,15 ...	" 	3 numbers for primary spec, 3 for secondary, comma separated
				TalentTrees = {
					['*'] = {		-- "Fire"	= Mage Fire tree, secondary
						['*'] = 0
					}
				},
				]]
				
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
				},
				
				-- ** Retail **
				Specializations = {},

			}
		}
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



-- *** Scanning functions ***
local function GetSpecInfo_Mists()
	-- Non-retail does not know specializations, roles, etc..
	-- So just scan, and the active spec is the one with the most points.
	local _, highestSpecName, _, _, highestSpecPoints = GetTalentTabInfo(1)
	local highestSpecIndex = 1
	
	for tabNum = 2, GetNumTalentTabs() do						-- all tabs
		local _, name, _, _, pointsSpent = GetTalentTabInfo(tabNum)
		
		if pointsSpent and pointsSpent > highestSpecPoints then
			highestSpecName = name
			highestSpecPoints = pointsSpent
			highestSpecIndex = tabNum
		end
	end

	return highestSpecIndex, highestSpecName, 0
end

local function GetSpecInfo_Cataclysm()
	-- Non-retail does not know specializations, roles, etc..
	-- So just scan, and the active spec is the one with the most points.
	local _, highestSpecName, _, _, highestSpecPoints = GetTalentTabInfo(1)
	local highestSpecIndex = 1
	
	for tabNum = 2, GetNumTalentTabs() do						-- all tabs
		local _, name, _, _, pointsSpent = GetTalentTabInfo(tabNum)
		
		if pointsSpent and pointsSpent > highestSpecPoints then
			highestSpecName = name
			highestSpecPoints = pointsSpent
			highestSpecIndex = tabNum
		end
	end

	return highestSpecIndex, highestSpecName, 0
end

local function GetSpecInfo_Burning_Crusade()
	-- Non-retail does not know specializations, roles, etc..
	-- So just scan, and the active spec is the one with the most points.
	local _, highestSpecName, _, _, highestSpecPoints = GetTalentTabInfo(1)
	local highestSpecIndex = 1
	
	for tabNum = 2, GetNumTalentTabs() do						-- all tabs
		local _, name, _, _, pointsSpent = GetTalentTabInfo(tabNum)
		
		if pointsSpent and pointsSpent > highestSpecPoints then
			highestSpecName = name
			highestSpecPoints = pointsSpent
			highestSpecIndex = tabNum
		end
	end

	return highestSpecIndex, highestSpecName, 0
end

function Test()
	local query = {
		["specializationIndex"] = 1,
		["target"] = "player",
		["talentIndex"] = 1
	}

	local talentInfo = C_SpecializationInfo.GetTalentInfo(query)
	while talentInfo ~= nil do -- loop the tree
		print("-- Spec", query["specializationIndex"])
		while talentInfo ~= nil do -- loop the tree
			print(talentInfo.name)
			query["talentIndex"] = query["talentIndex"] + 1
			talentInfo = C_SpecializationInfo.GetTalentInfo(query)
		end
		query["specializationIndex"] = query["specializationIndex"] + 1
		query["talentIndex"] = 1
		talentInfo = C_SpecializationInfo.GetTalentInfo(query)
	end
end

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




-- ** Mixins **

-- ** Mixins - Non-Retail **

-- ** Mixins - Retail **

local PublicMethods = {}

--[[
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
	--PublicMethods.GetTalentRank = _GetTalentRank
	--PublicMethods.GetNumPointsSpent = _GetNumPointsSpent
	PublicMethods.GetTalentPrereqs = _GetTalentPrereqs
	--PublicMethods.GetMainSpecialization = _GetMainSpecialization
end
]]

AddonFactory:OnAddonLoaded(addonName, function()
	--DataStore:RegisterMethod(addon, publicMethod, actualMethod)
	DataStore:RegisterMethod(addon, "GetNumSpecGroups", _GetNumSpecGroups)
	----[[
	DataStore:RegisterModule({
		addon = addon,
		addonName = addonName,
		--[[
		characterTables = {
			["DataStore_Talents_Characters"] = {
				GetTalentRank = _GetTalentRank,
				GetNumPointsSpent = _GetNumPointsSpent,
				GetMainSpecialization = _GetMainSpecialization
			},
		}
		]]
	})
	--]]
--[[
	if not isRetail then
		for publicMethod, actualMethod in pairs(PublicMethods) do
			DataStore:RegisterMethod(addon, publicMethod, actualMethod)
		end

		DataStore_TalentsDB = DataStore_TalentsDB or {}
		DataStore_TalentsRefDB = DataStore_TalentsRefDB or ReferenceDB_Defaults
		--DataStore_TalentsRefDB = ReferenceDB_Defaults --DAC DEBUG!!

		addon.ref = DataStore_TalentsRefDB
		thisCharacter = DataStore:GetCharacterDB("DataStore_Talents_Characters", true)
	end
	]]

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
	--[[
	addon:ListenTo("PLAYER_ENTERING_WORLD", OnPlayerAlive)
	addon:ListenTo("CHARACTER_POINTS_CHANGED", OnPlayerAlive)
	addon:ListenTo("PLAYER_TALENT_UPDATE", OnPlayerAlive)
	]]
	-- addon:RegisterEvent("PLAYER_ALIVE", OnPlayerAlive)
	
	-- if isRetail then
		-- addon:RegisterEvent("PLAYER_TALENT_UPDATE", ScanTalents_Retail)
		-- addon:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", OnPlayerSpecializationChanged)
		
	-- else
		-- addon:RegisterEvent("CHARACTER_POINTS_CHANGED", ScanTalents_NonRetail)
	-- end
end)
