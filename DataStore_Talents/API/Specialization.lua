-- Only valid for expansions that use specializations
if LE_EXPANSION_LEVEL_CURRENT <= LE_EXPANSION_MISTS_OF_PANDARIA then return end

local addonName, addon = ...
local specializations
local specInfos

local DataStore = DataStore
local GetSpecialization, GetSpecializationInfo = GetSpecialization, GetSpecializationInfo

local bit64 = LibStub("LibBit64")
local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local isMists = LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_MISTS_OF_PANDARIA
local isCataclysm = (LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CATACLYSM)
local isBurningCrusade = (LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_BURNING_CRUSADE)
local isClassic = (LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC)

local BACKGROUND_PATH = "Interface\\TalentFrame\\"

-- *** Scanning functions ***
local function GetSpecInfo_Retail()
	local specID = C_SpecializationInfo.GetSpecialization()
	local _, specName, _, _, role = C_SpecializationInfo.GetSpecializationInfo(specID)

	local roleID = DataStore:StoreToSetAndList(specInfos.Roles, role)

	return specID, specName, roleID
end

local heroTalentsDB = nil

local function ScanHeroTalents()
	-- Fix #93: Scan hero talent spec (War Within+)
	if not C_ClassTalents or not C_ClassTalents.GetActiveHeroTalentSpec then return end
	local success, heroSpecID = pcall(C_ClassTalents.GetActiveHeroTalentSpec)
	if not success or not heroSpecID then
		if heroTalentsDB then
			heroTalentsDB[DataStore.ThisCharID] = nil
		end
		return
	end
	
	local heroSpecName = nil
	if C_Traits and C_Traits.GetSubTreeInfo and C_ClassTalents.GetActiveConfigID then
		local success2, configID = pcall(C_ClassTalents.GetActiveConfigID)
		if success2 and configID then
			local success3, subTreeInfo = pcall(C_Traits.GetSubTreeInfo, configID, heroSpecID)
			if success3 and subTreeInfo and subTreeInfo.name then
				heroSpecName = subTreeInfo.name
			end
		end
	end
	if not heroSpecName then
		heroSpecName = format("Hero %d", heroSpecID)
	end
	
	if heroTalentsDB then
		local heroNameID = DataStore:StoreToSetAndList(specInfos.HeroNames, heroSpecName)
		-- Store heroSpecID in bits 0-12, heroNameID in bits 13+
		heroTalentsDB[DataStore.ThisCharID] = heroSpecID + bit64:LeftShift(heroNameID, 13)
	end
end

local function ScanSpecialization()
	local specID, specName, roleID
	
	specID, specName, roleID = GetSpecInfo_Retail()

	if not specName then return end -- No specializations for this character

	local nameID = DataStore:StoreToSetAndList(specInfos.Names, specName)

	specializations[DataStore.ThisCharID] = specID 	-- bits 0-2 : active spec index
		+ bit64:LeftShift(roleID, 3)						-- bits 3-4 : role id (damage/tank/heal)
		+ bit64:LeftShift(nameID, 5)						-- bits 5+  : spec name index

	ScanHeroTalents()
end

local function OnPlayerSpecializationChanged()
	ScanTalents_Retail()
	ScanTalentReference_Retail()
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

-- ** Mixins - Retail **
local function _GetActiveSpecInfo(characterID)
	local info = specializations[characterID]
	local specID, nameID, roleID

	if info then
		specID = bit64:GetBits(info, 0, 3)
		roleID = bit64:GetBits(info, 3, 2)
		nameID = bit64:GetBits(info, 5, 6)
	end

	local specName = specInfos.Names.List[nameID]
	local specRole = specInfos.Roles.List[roleID]

	return specName or "", specID or 0, specRole or ""
end

local function _GetHeroTalentSpec(characterID)
	-- Fix #93: Get hero talent spec name
	if not heroTalentsDB then return nil end
	local info = heroTalentsDB[characterID]
	if not info then return nil end
	local heroSpecID = bit64:GetBits(info, 0, 13)
	local heroNameID = bit64:GetBits(info, 13, 12)
	local heroName = specInfos.HeroNames and specInfos.HeroNames.List and specInfos.HeroNames.List[heroNameID]
	return heroName or (heroSpecID and format("Hero %d", heroSpecID)) or nil, heroSpecID
end

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

-- ** Mixins - Non-Retail **

--

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
	PublicMethods.GetHeroTalentSpec = _GetHeroTalentSpec
else
	PublicMethods.GetTreeReference = _GetTreeReference
	PublicMethods.GetClassTrees = _GetClassTrees
	PublicMethods.GetTreeInfo = _GetTreeInfo
	PublicMethods.GetTreeNameByID = _GetTreeNameByID
	PublicMethods.GetTalentLink = _GetTalentLink
	PublicMethods.GetNumTalents = _GetNumTalents
	PublicMethods.GetTalentInfo = _GetTalentInfo_NonRetail
	PublicMethods.GetTalentPrereqs = _GetTalentPrereqs
end

AddonFactory:OnAddonLoaded(addonName, function()
	DataStore:RegisterTables({
		addon = addon,
		rawTables = {
			"DataStore_Talents_SpecializationInfos",
			"DataStore_Talents_HeroTalents"
		},
		characterIdTables = {
			["DataStore_Talents_Specializations"] = {
				GetActiveSpecInfo = _GetActiveSpecInfo,
			},
			["DataStore_Talents_HeroTalents"] = {
				GetHeroTalentSpec = _GetHeroTalentSpec,
			},
		}
	})

	if not isRetail then
		for publicMethod, actualMethod in pairs(PublicMethods) do
			DataStore:RegisterMethod(addon, publicMethod, actualMethod)
		end
	end

	-- This table contains the specialization infos that are character specific
	specializations = DataStore_Talents_Specializations
	thisCharacter = specializations
	heroTalentsDB = DataStore_Talents_HeroTalents

	-- This table contains the specialization infos that are shared across all characters
	specInfos = DataStore_Talents_SpecializationInfos
	specInfos.Names = specInfos.Names or {}
	specInfos.Roles = specInfos.Roles or {}
	specInfos.HeroNames = specInfos.HeroNames or {}
		
	DataStore:CreateSetAndList(specInfos.Names)
	DataStore:CreateSetAndList(specInfos.Roles)
	DataStore:CreateSetAndList(specInfos.HeroNames)
end)

AddonFactory:OnPlayerLogin(function()
	addon:ListenTo("PLAYER_ENTERING_WORLD", ScanSpecialization)
	addon:ListenTo("PLAYER_ALIVE", ScanSpecialization)
	if isRetail or isMists then
		addon:ListenTo("PLAYER_SPECIALIZATION_CHANGED", ScanSpecialization)
	else
		addon:ListenTo("CHARACTER_POINTS_CHANGED", ScanSpecialization)
	end
end)
