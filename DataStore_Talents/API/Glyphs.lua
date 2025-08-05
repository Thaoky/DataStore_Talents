local addonName, addon = ...
local thisCharacter
local DataStore = DataStore

local bit64 = LibStub("LibBit64")
--local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local isCataclysm = (LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CATACLYSM)

-- *** Scanning functions ***
--local function ScanGlyphs(cleanLoad)
local function ScanGlyphs(cleanLoad)
	if not _G["GetNumGlyphs"] then return end -- Don't bother if glyphs aren't available

	local knownGlyphs = {}
	for i=1, GetNumGlyphs() do
		name, glyphType, isKnown, icon, glyphId, glyphLink, spec, specMatches, excluded = GetGlyphInfo(i)
		--print(name, glyphType, isKnown, icon, glyphId, glyphLink, spec, specMatches, excluded)
		if glyphId then
			knownGlyphs[glyphId] = isKnown
			DataStore_Talents_Glyphs[name] = glyphId
		end
	end
	thisCharacter.Glyphs = knownGlyphs
end

-- ** Mixins **
local function _ParseGlyphInfo(itemID)
	itemName, _, _, _, _, itemType, itemSubType, _, _, _, _, classID, subclassID = C_Item.GetItemInfo(itemID)
	if itemType == "Glyph" then
		glyphName = string.gsub(itemName, "Glyph of ", "")
		gName, theCount = string.gsub(itemName, "Glyph of the ", "") -- There are some slightly modified glyph names
		if theCount > 0 then glyphName = gName end

		return glyphName, subclassID
	end
	return nil, nil
end

local function _IsGlyphKnown(characterID, itemID)
	--print("characterID: "..characterID, itemID)
	if not characterID or not itemID then return false, false end

	-- Get the glyph name, ID, and character known glyphs
	local glyphName, glyphClassID = _ParseGlyphInfo(itemID)
	if not glyphName then return false, false end

	local glyphID = DataStore_Talents_Glyphs[glyphName]
	local selectedCharacter = DataStore_Talents_Characters[characterID]

	if selectedCharacter and selectedCharacter["Glyphs"] then
		local charGlyphs = selectedCharacter["Glyphs"]
		if charGlyphs[glyphID] ~= nil then
			return charGlyphs[glyphID], true
		end
	end
	return false, false
end

AddonFactory:OnAddonLoaded(addonName, function()
	DataStore:RegisterTables({
		addon = addon,
		rawTables = {
			"DataStore_Talents_Glyphs"
		},
		characterIdTables = {
			["DataStore_Talents_Characters"] = {
				IsGlyphKnown = _IsGlyphKnown
			},
		}
	})

	thisCharacter = DataStore:GetCharacterDB("DataStore_Talents_Characters", true)
	thisCharacter.Glyphs = thisCharacter.Glyphs or {}

	DataStore_Talents_Glyphs = DataStore_Talents_Glyphs or {}
	ScanGlyphs()	-- only for debug
end)

AddonFactory:OnPlayerLogin(function()
	addon:ListenTo("PLAYER_ALIVE", ScanGlyphs)
	if isCataclysm then
		addon:ListenTo("CHARACTER_POINTS_CHANGED", ScanGlyphs)
	end
end)
