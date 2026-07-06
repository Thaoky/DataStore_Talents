if not DataStore then return end

local addonName, addon = ...

function addon:SetupOptions()
	local f = DataStore.Frames.QuestsOptions

	DataStore:AddOptionCategory(f, addonName, "DataStore")
	
	-- restore saved options to gui
	local options = DataStore_Quests_Options
	
	f.TrackTurnIns:SetChecked(options.TrackTurnIns)
	f.AutoUpdateHistory:SetChecked(options.AutoUpdateHistory)
end
