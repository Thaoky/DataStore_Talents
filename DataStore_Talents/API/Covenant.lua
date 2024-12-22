--[[ 
	This file keeps track of a character's soulbinds
	Expansion Features / 9.0 - Shadowlands
--]]
if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return end

local addonName, addon = ...
local thisCharacter
local conduits, conduitSpecs, soulbinds, reasons

local DataStore, pairs, C_Covenants, C_Soulbinds = DataStore, pairs, C_Covenants, C_Soulbinds

local bit64 = LibStub("LibBit64")

local cov = Enum.CovenantType
local recommendedCovenant = {
	--[[ fields : 
	main,  					best overall choice that works in all situations
	single,  				best choice for single target
	aoe,						best choice for aoe builds
	raid, 					best choice for raid
	mythic, 					best choice for mythic +
	torghast, 				best choice for Torghast
	choice1 & choice2 	when 2 choices are equivalent, then use both fields !
	--]]

	["MAGE"] = {
		{ main = cov.NightFae }, -- Arcane
		{ main = cov.NightFae }, -- Fire
		{ main = cov.NightFae, single = cov.Venthyr }, -- Frost
	},
	["PRIEST"] = {
		{ raid = cov.Venthyr, mythic = cov.Kyrian }, -- Discipline
		{ main = cov.Necrolord }, -- Holy
		{ raid = cov.Kyrian, mythic = cov.Necrolord }, -- Shadow
	},	
	["WARLOCK"] = {
		{ raid = cov.Kyrian, mythic = cov.NightFae }, -- Affliction
		{ choice1 = cov.NightFae, choice2 = cov.Necrolord }, -- Demonology
		{ raid = cov.Necrolord, mythic = cov.Kyrian, torghast = cov.NightFae}, -- Destruction
	},	
	
	-- Leather
	["DEMONHUNTER"] = {
		{ raid = cov.Venthyr, mythic = cov.Kyrian, torghast = cov.Venthyr}, -- Havoc
		{ main = cov.Kyrian }, -- Vengeance
	},
	["ROGUE"] = {
		{ mythic = cov.NightFae, choice1 = cov.Kyrian, choice2 = cov.Venthyr }, -- Assassination
		{ mythic = cov.NightFae, choice1 = cov.Kyrian, choice2 = cov.Venthyr }, -- Outlaw
		{ raid = cov.Kyrian, mythic = cov.NightFae }, -- Subtlety
	},
	["DRUID"] = {
		{ main = cov.NightFae, mythic = cov.Kyrian }, -- Balance
		{ main = cov.NightFae }, -- Feral
		{ main = cov.NightFae }, -- Guardian
		{ main = cov.NightFae }, -- Restoration
	},
	["MONK"] = {
		{ main = cov.Kyrian, mythic = cov.NightFae }, -- Brewmaster
		{ raid = cov.Kyrian, mythic = cov.NightFae, torghast = cov.Necrolord }, -- Mistweaver
		{ raid = cov.Kyrian, mythic = cov.Necrolord, torghast = cov.NightFae }, -- Windwalker
	},
	
	-- Mail
	["HUNTER"] = {
		{ main = cov.NightFae }, -- Beast Mastery
		{ main = cov.NightFae, mythic = cov.Kyrian }, -- Marksmanship
		{ main = cov.NightFae }, -- Survival
	},
	["SHAMAN"] = {
		{ raid = cov.Necrolord, mythic = cov.Necrolord, torghast = cov.NightFae }, -- Elemental
		{ main = cov.Venthyr }, -- Enhancement
		{ raid = cov.Necrolord, mythic = cov.Venthyr, torghast = cov.Kyrian }, -- Restoration
	},	
	["EVOKER"] = {
		{ main = cov.NightFae }, -- Devastation
		{ main = cov.NightFae }, -- Preservation
		{ main = cov.NightFae }, -- Augmentation
	},
	
	-- Plate
	["DEATHKNIGHT"] = {
		{ raid = cov.Kyrian, mythic = cov.Venthyr }, -- Blood
		{ raid = cov.NightFae, mythic = cov.NightFae, choice1 = cov.Necrolord, choice2 = cov.Venthyr }, -- Frost
		{ main = cov.Necrolord }, -- Unholy
	},
	["WARRIOR"] = {
		{ main = cov.Venthyr, mythic = cov.Kyrian }, -- Arms
		{ main = cov.Venthyr, mythic = cov.Kyrian }, -- Fury
		{ main = cov.Kyrian, mythic = cov.NightFae }, -- Protection
	},
	["PALADIN"] = {
		{ main = cov.Kyrian }, -- Holy
		{ main = cov.Kyrian, raid = cov.Venthyr }, -- Protection
		{ main = cov.Kyrian }, -- Retribution
	},
}

-- *** Scanning functions ***
local function ScanSoulbinds()
	local charID = DataStore.ThisCharID
	
	reasons[charID] = reasons[charID] or {}
	conduits[charID] = conduits[charID] or {}
	soulbinds[charID] = soulbinds[charID] or {}
	conduitSpecs[charID] = conduitSpecs[charID] or {}
	
	-- How this works : Conduits is the list of items on the right panel that can be "socketed" in the talent tree (the Soulbinds)
	-- So scan the conduits first
	-- Then scan the soulbinds, which contain the info on which the conduit is installed. 
	-- Base soulbind information is always available, so only save the installed conduits.
	
	-- Scan conduit collection
	for typeName, typeID in pairs(Enum.SoulbindConduitType) do 
		-- Enum.SoulbindConduitType : "Finesse" = 0, "Potency" = 1 .. 
		-- (source: https://wow.gamepedia.com/API_C_Soulbinds.GetConduitCollection)
	
		for _, info in pairs(C_Soulbinds.GetConduitCollection(typeID)) do
			conduits[charID][info.conduitID] = info.conduitType		-- bits 0-1 (2 bits) Finesse = 0 .. Flex = 3
				+ bit64:LeftShift(info.conduitRank, 2)					-- bits 2-5 (4 bits)
				+ bit64:LeftShift(info.conduitItemLevel, 6)			-- bits 6-14 (9 bits)
				+ bit64:LeftShift(info.conduitItemID, 15)				-- bits 15+
			
			conduitSpecs[charID][info.conduitID] = info.conduitSpecName	-- Fire, Frost, etc.. 
		end
	end	

	thisCharacter.activeSoulbindID = C_Soulbinds.GetActiveSoulbindID()
	
	local covenantID = C_Covenants.GetActiveCovenantID()
	local covenantData = C_Covenants.GetCovenantData(covenantID)
		
	-- Scan all soulbinds of this covenant, not just the active one
	for _, soulbindID in pairs(covenantData.soulbindIDs) do
	
		-- Get the soulbind data
		local data = C_Soulbinds.GetSoulbindData(soulbindID)
		
		-- Loop on the tree nodes
		for _, node in pairs(data.tree.nodes) do
			
			-- Source : https://wow.gamepedia.com/API_C_Soulbinds.GetSoulbindData
			-- State is of Enum.SoulbindNodeState ("Unavailable" = 0, "Unselected" = 1, "Selectable" = 2, "Selected" = 3)
			-- conduitID = 0 : no conduit is installed on this node
			-- spellID = 0 : it's not a spell, but a conduitID, always available, don't save it
			
			soulbinds[charID][node.ID] = node.state					-- bits 0-1 (2 bits)
				+ bit64:LeftShift(node.conduitType and 1 or 0, 2)	-- bit 2 (1 bit) has conduit type ?
				+ bit64:LeftShift(node.conduitType or 0, 3)				-- bits 3-4 (2 bits) Finesse = 0 .. Flex = 3
				+ bit64:LeftShift(node.conduitRank or 0, 5)		-- bits 5-8 = ranks 1 to 15 (4 bits) (ilevel 145 to 330 : https://www.wowhead.com/guide/soulbind-conduits-types-ranks-sources#conduit-ranks)
				+ bit64:LeftShift(node.conduitID, 9)				-- bits 9+ = conduit id
			
			reasons[charID][node.ID] = node.playerConditionReason		--  Ex: "Requires Renown 10"
		end
	end
end

-- *** Event Handlers ***
local function OnInteractionEnded()
	addon:StopListeningTo("SOULBIND_FORGE_INTERACTION_ENDED")
	addon:StopListeningTo("SOULBIND_ACTIVATED")
	addon:StopListeningTo("SOULBIND_NODE_LEARNED")
	addon:StopListeningTo("SOULBIND_CONDUIT_INSTALLED")
	addon:StopListeningTo("SOULBIND_CONDUIT_UNINSTALLED")
	addon:StopListeningTo("SOULBIND_PENDING_CONDUIT_CHANGED")
end

local function OnInteractionStarted()
	ScanSoulbinds()
	
	addon:ListenTo("SOULBIND_FORGE_INTERACTION_ENDED", OnInteractionEnded)
	addon:ListenTo("SOULBIND_ACTIVATED", ScanSoulbinds)
	addon:ListenTo("SOULBIND_NODE_LEARNED", ScanSoulbinds)
	addon:ListenTo("SOULBIND_CONDUIT_INSTALLED", ScanSoulbinds)
	addon:ListenTo("SOULBIND_CONDUIT_UNINSTALLED", ScanSoulbinds)
	addon:ListenTo("SOULBIND_PENDING_CONDUIT_CHANGED", ScanSoulbinds)	
end


-- ** Mixins **
local function _GetConduitInfo(characterID, conduitID)
	local character = conduits[characterID]
	if not character then return end
	
	local conduit = character[conduitID]
	if not conduit then return end
	
	local specs = conduitSpecs[characterID]
	local specName = specs and specs[conduitID]
	
	return bit64:GetBits(conduit, 0, 2),	-- conduit type
			bit64:RightShift(conduit, 15),	-- conduit itemID
			bit64:GetBits(conduit, 6, 9),		-- ilevel
			bit64:GetBits(conduit, 2, 4),		-- rank
			specName									-- specName (Fire, Frost, etc..)
end

local function _GetActiveSoulbindName(character)
	-- low level characters have no soulbind yet
	if not character.activeSoulbindID or character.activeSoulbindID == 0 then return "" end
	
	local data = C_Soulbinds.GetSoulbindData(character.activeSoulbindID)
	local name = (data) and data.name
	
	return name or ""		-- because data.name could still be nil
end

local function _GetSoulbindInfo(characterID, nodeID)
	local character = soulbinds[characterID]
	if not character then return end
	
	local soulbind = character[nodeID]
	if not soulbind then return end
	
	local characterReasons = reasons[characterID]
	local reason = characterReasons and characterReasons[nodeID]

	return bit64:GetBits(soulbind, 0, 2),	-- bits 0-1 state
			bit64:RightShift(soulbind, 9),	-- conduit id
			bit64:GetBits(soulbind, 5, 4),	-- rank
			bit64:TestBit(soulbind, 2),		-- has type ? true/false
			bit64:GetBits(soulbind, 3, 2),	-- type
			reason									-- reason Ex: "Requires Renown 10"
end

local function _GetRecommendedCovenant(class, specialization)
	if recommendedCovenant[class] then
		return recommendedCovenant[class][specialization]
	end
end

AddonFactory:OnAddonLoaded(addonName, function() 
	DataStore:RegisterTables({
		addon = addon,
		characterTables = {
			["DataStore_Talents_Covenant"] = {
				GetActiveSoulbindID = function(character) return character.activeSoulbindID end,
				GetActiveSoulbindName = _GetActiveSoulbindName,
			},
		},
		characterIdTables = {
			["DataStore_Talents_Conduits"] = {
				GetConduits = function(characterID) return conduits[characterID] end,
				GetConduitInfo = _GetConduitInfo,
			},
			["DataStore_Talents_Soulbinds"] = {
				GetSoulbinds = function(characterID) return soulbinds[characterID] end,
				GetSoulbindInfo = _GetSoulbindInfo,
			},
			["DataStore_Talents_Reasons"] = {},
			["DataStore_Talents_ConduitSpecs"] = {},
		}
	})
	
	thisCharacter = DataStore:GetCharacterDB("DataStore_Talents_Covenant", true)
	conduits = DataStore_Talents_Conduits
	soulbinds = DataStore_Talents_Soulbinds
	reasons = DataStore_Talents_Reasons
	conduitSpecs = DataStore_Talents_ConduitSpecs
	
	DataStore:RegisterMethod(addon, "GetRecommendedCovenant", _GetRecommendedCovenant)
end)

AddonFactory:OnPlayerLogin(function()
	addon:ListenTo("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(event, interactionType)
		if interactionType == Enum.PlayerInteractionType.Soulbind then
			OnInteractionStarted()
		end
	end)
end)
