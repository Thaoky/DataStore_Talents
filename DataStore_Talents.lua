--[[	*** DataStore_Talents ***
Written by : Thaoky, EU-Marécages de Zangar
June 23rd, 2009
--]]
if not DataStore then return end

local addonName = "DataStore_Talents"

_G[addonName] = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")

local addon = _G[addonName]
local enum = DataStore.Enum

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
				activeSpecIndex = nil,
				activeSpecName = nil,
				activeSpecRole = nil,
				
				-- ** Expansion Stuff / 7.0 - Legion **
				EquippedArtifact = nil,				-- name of the currently equipped artifact
				ArtifactKnowledge = nil,
				ArtifactKnowledgeMultiplier = nil,
				Artifacts = {
					['*'] = {
						rank = 0,
						pointsRemaining = 0,
					}
				},
				
				-- ** Expansion Features / 9.0 - Shadowlands **
				Conduits = {},			-- The list of available conduits that can be installed on the soulbinds.
				Soulbinds = {},
				activeSoulbindID = 0,
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

--[[
Source : http://www.icy-veins.com/
Last update : 05/01/2021 (9.0)

Note: The priorities come from Icy Veins, although I have not respected them 100%, based on my own experience, view, and discussions with guild mates.
They are meant to be an indication for classes you do not play too often, 
and I do not wish to enter religious discussions about who is right or wrong, or about which stat is actually better :)

ex: in some cases, Icy Veins indicated that the primary stat (STR, INT, ..) has a lesser priority than mastery or crit .. 
well, I still kept the primary stat as #1 in the list, because in most cases, you WILL have this stat on each item.

And if you reach the point where this difference matters, then you probably don't need the information any more, 
because you supposedly already know your class well enough.
--]]

local statPriority = {
	-- Cloth
	["MAGE"] = {
		{ SPELL_STAT4_NAME, STAT_CRITICAL_STRIKE, STAT_MASTERY, STAT_VERSATILITY, SPELL_HASTE }, -- Arcane
		{ SPELL_STAT4_NAME, SPELL_HASTE, STAT_VERSATILITY, STAT_MASTERY, STAT_CRITICAL_STRIKE }, -- Fire
		{ SPELL_STAT4_NAME, STAT_CRITICAL_STRIKE, SPELL_HASTE, STAT_VERSATILITY, STAT_MASTERY }, -- Frost
	},
	["PRIEST"] = {
		{ SPELL_STAT4_NAME, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_VERSATILITY, STAT_MASTERY }, -- Discipline
		{ SPELL_STAT4_NAME, STAT_MASTERY, STAT_CRITICAL_STRIKE, STAT_VERSATILITY, SPELL_HASTE }, -- Holy
		{ SPELL_STAT4_NAME, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_VERSATILITY, STAT_MASTERY }, -- Shadow
	},	
	["WARLOCK"] = {
		{ SPELL_STAT4_NAME, STAT_MASTERY, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_VERSATILITY }, -- Affliction
		{ SPELL_STAT4_NAME, SPELL_HASTE, STAT_MASTERY, STAT_CRITICAL_STRIKE, STAT_VERSATILITY }, -- Demonology
		{ SPELL_STAT4_NAME, SPELL_HASTE, STAT_MASTERY, STAT_CRITICAL_STRIKE, STAT_VERSATILITY }, -- Destruction
	},	
	
	-- Leather
	["DEMONHUNTER"] = {
		{ SPELL_STAT2_NAME, SPELL_HASTE, STAT_VERSATILITY, STAT_CRITICAL_STRIKE, STAT_MASTERY }, -- Havoc
		{ SPELL_STAT2_NAME, SPELL_HASTE, STAT_VERSATILITY, STAT_CRITICAL_STRIKE, STAT_MASTERY }, -- Vengeance
	},
	["ROGUE"] = {
		{ SPELL_STAT2_NAME, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_VERSATILITY, STAT_MASTERY }, -- Assassination
		{ SPELL_STAT2_NAME, STAT_VERSATILITY, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_MASTERY }, -- Outlaw
		{ SPELL_STAT2_NAME, STAT_VERSATILITY, STAT_CRITICAL_STRIKE, SPELL_HASTE, STAT_MASTERY }, -- Subtlety
	},
	["DRUID"] = {
		{ SPELL_STAT4_NAME, STAT_MASTERY, SPELL_HASTE, STAT_VERSATILITY, STAT_CRITICAL_STRIKE }, -- Balance
		{ SPELL_STAT2_NAME, STAT_CRITICAL_STRIKE, STAT_MASTERY, STAT_VERSATILITY, SPELL_HASTE }, -- Feral
		{ SPELL_STAT2_NAME, STAT_VERSATILITY, STAT_MASTERY, SPELL_HASTE, STAT_CRITICAL_STRIKE }, -- Guardian
		{ SPELL_STAT4_NAME, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_MASTERY, STAT_VERSATILITY }, -- Restoration
	},
	["MONK"] = {
		{ SPELL_STAT2_NAME, STAT_VERSATILITY, STAT_MASTERY, STAT_CRITICAL_STRIKE, SPELL_HASTE }, -- Brewmaster
		{ SPELL_STAT4_NAME, STAT_CRITICAL_STRIKE, STAT_VERSATILITY, SPELL_HASTE, STAT_MASTERY }, -- Mistweaver
		{ SPELL_STAT2_NAME, STAT_VERSATILITY, STAT_MASTERY, STAT_CRITICAL_STRIKE, SPELL_HASTE }, -- Windwalker
	},
	
	-- Mail
	["HUNTER"] = {
		{ SPELL_STAT2_NAME, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_VERSATILITY, STAT_MASTERY }, -- Beast Mastery
		{ SPELL_STAT2_NAME, STAT_CRITICAL_STRIKE, STAT_MASTERY, STAT_VERSATILITY, SPELL_HASTE }, -- Marksmanship
		{ SPELL_STAT2_NAME, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_VERSATILITY, STAT_MASTERY }, -- Survival
	},
	["SHAMAN"] = {
		{ SPELL_STAT4_NAME, STAT_VERSATILITY, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_MASTERY }, -- Elemental
		{ SPELL_STAT2_NAME, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_VERSATILITY, STAT_MASTERY }, -- Enhancement
		{ SPELL_STAT4_NAME, STAT_VERSATILITY, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_MASTERY }, -- Restoration
	},	
	["EVOKER"] = {
		{ SPELL_STAT4_NAME, STAT_MASTERY, STAT_HASTE, STAT_CRITICAL_STRIKE, STAT_VERSATILITY }, -- Devastation
		{ SPELL_STAT4_NAME, STAT_CRITICAL_STRIKE, STAT_VERSATILITY, STAT_HASTE, STAT_MASTERY }, -- Preservation (M+)
	},
	
	-- Plate
	["DEATHKNIGHT"] = {
		{ SPELL_STAT1_NAME, STAT_VERSATILITY, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_MASTERY }, -- Blood
		{ SPELL_STAT1_NAME, STAT_MASTERY, STAT_CRITICAL_STRIKE, STAT_VERSATILITY, SPELL_HASTE }, -- Frost
		{ SPELL_STAT1_NAME, STAT_MASTERY, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_VERSATILITY }, -- Unholy
	},
	["WARRIOR"] = {
		{ SPELL_STAT1_NAME, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_MASTERY, STAT_VERSATILITY }, -- Arms
		{ SPELL_STAT1_NAME, SPELL_HASTE, STAT_MASTERY, STAT_CRITICAL_STRIKE, STAT_VERSATILITY }, -- Fury
		{ SPELL_STAT1_NAME, SPELL_HASTE, STAT_VERSATILITY, STAT_MASTERY, STAT_CRITICAL_STRIKE }, -- Protection
	},
	["PALADIN"] = {
		{ SPELL_STAT4_NAME, SPELL_HASTE, STAT_MASTERY, STAT_VERSATILITY, STAT_CRITICAL_STRIKE }, -- Holy
		{ SPELL_STAT1_NAME, SPELL_HASTE, STAT_MASTERY, STAT_VERSATILITY, STAT_CRITICAL_STRIKE }, -- Protection
		{ SPELL_STAT1_NAME, SPELL_HASTE, STAT_CRITICAL_STRIKE, STAT_VERSATILITY, STAT_MASTERY }, -- Retribution
	},
}

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


-- *** Utility functions ***
local bAnd = bit.band
local RShift = bit.rshift
local LShift = bit.lshift

local function GetVersion()
	local _, version = GetBuildInfo()
	return tonumber(version)
end

local function GetArtifactName()
	-- local info = C_ArtifactUI.GetEquippedArtifactArtInfo()
	local info = C_ArtifactUI.GetArtifactArtInfo()
	if info then 
		return info.titleName
	end
	-- return select(2, C_ArtifactUI.GetArtifactArtInfo())
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
	local _, specName, _, _, role = GetSpecializationInfo(specIndex)
	
	char.activeSpecIndex = specIndex
	char.activeSpecName = specName
	char.activeSpecRole = role
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

local function ScanSoulbinds()
	local char = addon.ThisCharacter
	
	-- How this works : Conduits is the list of items on the right panel that can be "socketed" in the talent tree (the Soulbinds)
	-- So scan the conduits first
	-- Then scan the soulbinds, which contain the info on which the conduit is installed. 
	-- Base soulbind information is always available, so only save the installed conduits.
	
	-- Scan conduit collection
	for typeName, typeID in pairs(Enum.SoulbindConduitType) do 
		-- Enum.SoulbindConduitType : "Finesse" = 0, "Potency" = 1 .. 
		-- (source: https://wow.gamepedia.com/API_C_Soulbinds.GetConduitCollection)
	
		for _, info in pairs(C_Soulbinds.GetConduitCollection(typeID)) do
			char.Conduits[info.conduitID] = format("%s|%s|%s|%s|%s",
				info.conduitType, 			-- finesse, potency, etc..
				info.conduitItemID,
				info.conduitItemLevel, 
				info.conduitRank, 
				info.conduitSpecName	or ""		-- Fire, Frost, etc.. 
			)
		end
	end	

	char.activeSoulbindID = C_Soulbinds.GetActiveSoulbindID()
	
	local covenantID = C_Covenants.GetActiveCovenantID()
	local covenantData = C_Covenants.GetCovenantData(covenantID)
		
	-- Scan all soulbinds of this covenant, not just the active one
	for _, soulbindID in pairs(covenantData.soulbindIDs) do
	
		-- Get the soulbind data
		local soulbinds = C_Soulbinds.GetSoulbindData(soulbindID)
		
		-- Loop on the tree nodes
		for _, node in pairs(soulbinds.tree.nodes) do
			
			-- Source : https://wow.gamepedia.com/API_C_Soulbinds.GetSoulbindData
			-- State is of Enum.SoulbindNodeState ("Unavailable" = 0, "Unselected" = 1, "Selectable" = 2, "Selected" = 3)
			-- conduitID = 0 : no conduit is installed on this node
			-- spellID = 0 : it's not a spell, but a conduitID, always available, don't save it
			
			char.Soulbinds[node.ID] = format("%s|%s|%s|%s|%s",
				node.state,
				node.conduitID,
				node.conduitRank or 0,
				node.conduitType or -1,					-- Explicitly pass a -1 to say there is no conduit type, because 0 = Finesse
				node.playerConditionReason or ""		--  Ex: "Requires Renown 10"
			)
		end
	end
end

-- *** Event Handlers ***
local function OnPlayerAlive()
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
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

local function _GetStatPriority(class, specialization)
	if statPriority[class] then
		return statPriority[class][specialization]
	end
end

local function _GetRecommendedCovenant(class, specialization)
	if recommendedCovenant[class] then
		return recommendedCovenant[class][specialization]
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

local function _GetActiveSpecInfo(character)
	return character.activeSpecName or "", character.activeSpecIndex, character.activeSpecRole
end

local function _IterateTalentTiers(callback)
	for tierIndex, level in ipairs(enum.TalentTiersSorted) do
		callback(tierIndex, level)
	end
end

-- ** Artifact **
local function _GetArtifactKnowledgeLevel(character)
	return character.ArtifactKnowledge or 0
end

local function _GetArtifactKnowledgeMultiplier(character)
	return character.ArtifactKnowledgeMultiplier or 0
end

local function _GetEquippedArtifact(character)
	return character.EquippedArtifact
end

local function _GetEquippedArtifactRank(character)
	local rank = 0
	
	local equippedArtifact = character.EquippedArtifact
	if equippedArtifact then
		local info = character.Artifacts[equippedArtifact]
		if info and info.rank then
			rank = info.rank
		end
	end
	
	return rank
end

local function _GetEquippedArtifactPower(character)
	local power = 0
	
	local equippedArtifact = character.EquippedArtifact
	if equippedArtifact then
		local info = character.Artifacts[equippedArtifact]
		if info and info.pointsRemaining then
			power = info.pointsRemaining
		end
	end
	
	return power
end

local function _GetEquippedArtifactTier(character)
	local tier = 0
	
	local equippedArtifact = character.EquippedArtifact
	if equippedArtifact then
		local info = character.Artifacts[equippedArtifact]
		if info and info.tier then
			tier = info.tier
		end
	end
	
	return tier
end

local function _GetKnownArtifacts(character)
	return character.Artifacts
end

local function _GetNumArtifactTraitsPurchasableFromXP(currentRank, xpToSpend, currentTier)
	-- this function is exactly the same as 
	-- MainMenuBar_GetNumArtifactTraitsPurchasableFromXP (from MainMenuBar.lua)
	-- but just in case it's not loaded or changes later.. I'll keep it here
	-- Usage: 
	--		DataStore:GetNumArtifactTraitsPurchasableFromXP(1, 945)
	--    artifact is currently at rank 1, and we have 945 points to spend
	
	local numPoints = 0
	local xpForNextPoint = C_ArtifactUI.GetCostForPointAtRank(currentRank, currentTier)

	while xpToSpend >= xpForNextPoint and xpForNextPoint > 0 do
		xpToSpend = xpToSpend - xpForNextPoint

		currentRank = currentRank + 1
		numPoints = numPoints + 1

		xpForNextPoint = C_ArtifactUI.GetCostForPointAtRank(currentRank, currentTier)
	end
	
	-- ex: with rank 1 and 945 points, we have enough points for 2 traits, and 320 / 350 in the last rank
	return numPoints, xpToSpend, xpForNextPoint
end


-- ** Covenant **
local function _GetConduits(character)
	return character.Conduits
end

local function _GetConduitInfo(character, conduitID)
	if not character.Conduits[conduitID] then return end
	
	local conduitType, itemID, iLevel, rank, specName = strsplit("|", character.Conduits[conduitID])
	return tonumber(conduitType), tonumber(itemID), tonumber(iLevel), tonumber(rank), specName
end

local function _GetActiveSoulbindID(character)
	return character.activeSoulbindID
end

local function _GetActiveSoulbindName(character)
	-- low level characters have no soulbind yet
	if not character.activeSoulbindID or character.activeSoulbindID == 0 then return "" end
	
	local data = C_Soulbinds.GetSoulbindData(character.activeSoulbindID)
	local name = (data) and data.name
	
	return name or ""		-- because data.name could still be nil
end

local function _GetSoulbinds(character)
	return character.Soulbinds
end

local function _GetSoulbindInfo(character, nodeID)
	if not character.Soulbinds[nodeID] then return end
	
	local state, conduitID, conduitRank, conduitType, reason = strsplit("|", character.Soulbinds[nodeID])
	return tonumber(state), tonumber(conduitID), tonumber(conduitRank), tonumber(conduitType), reason
end


local PublicMethods = {
	GetReferenceTable = _GetReferenceTable,
	GetClassReference = _GetClassReference,
	IsClassKnown = _IsClassKnown,
	ImportClassReference = _ImportClassReference,
}

if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	PublicMethods.GetSpecializationInfo = _GetSpecializationInfo
	PublicMethods.GetStatPriority = _GetStatPriority
	PublicMethods.GetRecommendedCovenant = _GetRecommendedCovenant
	PublicMethods.GetTalentInfo = _GetTalentInfo_Retail
	PublicMethods.GetSpecializationTierChoice = _GetSpecializationTierChoice
	PublicMethods.GetActiveSpecInfo = _GetActiveSpecInfo
	PublicMethods.IterateTalentTiers = _IterateTalentTiers
	PublicMethods.GetArtifactKnowledgeLevel = _GetArtifactKnowledgeLevel
	PublicMethods.GetArtifactKnowledgeMultiplier = _GetArtifactKnowledgeMultiplier
	PublicMethods.GetEquippedArtifact = _GetEquippedArtifact
	PublicMethods.GetEquippedArtifactRank = _GetEquippedArtifactRank
	PublicMethods.GetEquippedArtifactPower = _GetEquippedArtifactPower
	PublicMethods.GetEquippedArtifactTier = _GetEquippedArtifactTier
	PublicMethods.GetKnownArtifacts = _GetKnownArtifacts
	PublicMethods.GetNumArtifactTraitsPurchasableFromXP = _GetNumArtifactTraitsPurchasableFromXP
	PublicMethods.GetConduits = _GetConduits
	PublicMethods.GetConduitInfo = _GetConduitInfo
	PublicMethods.GetActiveSoulbindID = _GetActiveSoulbindID
	PublicMethods.GetActiveSoulbindName = _GetActiveSoulbindName
	PublicMethods.GetSoulbinds = _GetSoulbinds
	PublicMethods.GetSoulbindInfo = _GetSoulbindInfo
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


function addon:OnInitialize()
	addon.db = LibStub("AceDB-3.0"):New(addonName .. "DB", AddonDB_Defaults)
	addon.ref = LibStub("AceDB-3.0"):New(addonName .. "RefDB", ReferenceDB_Defaults)

	DataStore:RegisterModule(addonName, addon, PublicMethods)

	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		DataStore:SetCharacterBasedMethod("GetSpecializationTierChoice")
		DataStore:SetCharacterBasedMethod("GetArtifactKnowledgeLevel")
		DataStore:SetCharacterBasedMethod("GetArtifactKnowledgeMultiplier")
		DataStore:SetCharacterBasedMethod("GetEquippedArtifact")
		DataStore:SetCharacterBasedMethod("GetEquippedArtifactRank")
		DataStore:SetCharacterBasedMethod("GetEquippedArtifactPower")
		DataStore:SetCharacterBasedMethod("GetEquippedArtifactTier")
		DataStore:SetCharacterBasedMethod("GetKnownArtifacts")
		DataStore:SetCharacterBasedMethod("GetConduits")
		DataStore:SetCharacterBasedMethod("GetConduitInfo")
		DataStore:SetCharacterBasedMethod("GetActiveSoulbindID")
		DataStore:SetCharacterBasedMethod("GetActiveSoulbindName")
		DataStore:SetCharacterBasedMethod("GetSoulbinds")
		DataStore:SetCharacterBasedMethod("GetSoulbindInfo")
		DataStore:SetCharacterBasedMethod("GetActiveSpecInfo")
	else
		DataStore:SetCharacterBasedMethod("GetTalentRank")
		DataStore:SetCharacterBasedMethod("GetNumPointsSpent")
		DataStore:SetCharacterBasedMethod("GetMainSpecialization")
	end
end

function addon:OnEnable()
	addon:RegisterEvent("PLAYER_ALIVE", OnPlayerAlive)
	
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		addon:RegisterEvent("PLAYER_TALENT_UPDATE", ScanTalents_Retail)
		addon:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", OnPlayerSpecializationChanged)
		addon:RegisterEvent("SOULBIND_FORGE_INTERACTION_STARTED")
	else
		addon:RegisterEvent("CHARACTER_POINTS_CHANGED", ScanTalents_NonRetail)
	end
end

function addon:OnDisable()
	addon:UnregisterEvent("PLAYER_ALIVE")
	
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		addon:UnregisterEvent("PLAYER_TALENT_UPDATE")
		addon:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		addon:UnregisterEvent("SOULBIND_FORGE_INTERACTION_STARTED")
		addon:UnregisterEvent("SOULBIND_FORGE_INTERACTION_ENDED")
	else
		addon:UnregisterEvent("CHARACTER_POINTS_CHANGED")
	end
end

-- *** Event Handlers ***
function addon:SOULBIND_FORGE_INTERACTION_STARTED()
	ScanSoulbinds()
	
	addon:RegisterEvent("SOULBIND_FORGE_INTERACTION_ENDED")
	addon:RegisterEvent("SOULBIND_ACTIVATED", ScanSoulbinds)
	addon:RegisterEvent("SOULBIND_NODE_LEARNED", ScanSoulbinds)
	addon:RegisterEvent("SOULBIND_CONDUIT_INSTALLED", ScanSoulbinds)
	addon:RegisterEvent("SOULBIND_CONDUIT_UNINSTALLED", ScanSoulbinds)
	addon:RegisterEvent("SOULBIND_PENDING_CONDUIT_CHANGED", ScanSoulbinds)	
end

function addon:SOULBIND_FORGE_INTERACTION_ENDED()
	addon:UnregisterEvent("SOULBIND_FORGE_INTERACTION_ENDED")
	addon:UnregisterEvent("SOULBIND_ACTIVATED")
	addon:UnregisterEvent("SOULBIND_NODE_LEARNED")
	addon:UnregisterEvent("SOULBIND_CONDUIT_INSTALLED")
	addon:UnregisterEvent("SOULBIND_CONDUIT_UNINSTALLED")
	addon:UnregisterEvent("SOULBIND_PENDING_CONDUIT_CHANGED")
end