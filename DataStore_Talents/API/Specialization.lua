local addonName, addon = ...
local specializations
local specInfos

local DataStore = DataStore
local GetSpecialization, GetSpecializationInfo = GetSpecialization, GetSpecializationInfo

local bit64 = LibStub("LibBit64")

-- *** Scanning functions ***
local function ScanSpecialization()
	local char = addon.ThisCharacter
	
	local specID = GetSpecialization()
	local _, specName, _, _, role = GetSpecializationInfo(specID)
	
	local nameID = DataStore:StoreToSetAndList(specInfos.Names, specName)
	local roleID = DataStore:StoreToSetAndList(specInfos.Roles, role)
	
	specializations[DataStore.ThisCharID] = specID 	-- bits 0-2 : active spec index
		+ bit64:LeftShift(roleID, 3)						-- bits 3-4 : role id (damage/tank/heal)
		+ bit64:LeftShift(nameID, 5)						-- bits 5+  : spec name index
end

-- ** Mixins **
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


DataStore:OnAddonLoaded(addonName, function()
	DataStore:RegisterTables({
		addon = addon,
		rawTables = {
			"DataStore_Talents_SpecializationInfos"
		},
		characterIdTables = {
			["DataStore_Talents_Specializations"] = {
				GetActiveSpecInfo = _GetActiveSpecInfo,
			},
		}
	})

	-- This table contains the specialization infos that are character specific
	specializations = DataStore_Talents_Specializations

	-- This table contains the specialization infos that are shared across all characters
	specInfos = DataStore_Talents_SpecializationInfos
	specInfos.Names = specInfos.Names or {}
	specInfos.Roles = specInfos.Roles or {}
		
	DataStore:CreateSetAndList(specInfos.Names)
	DataStore:CreateSetAndList(specInfos.Roles)
end)

DataStore:OnPlayerLogin(function()
	addon:ListenTo("PLAYER_ALIVE", ScanSpecialization)
	addon:ListenTo("PLAYER_SPECIALIZATION_CHANGED", ScanSpecialization)
end)
