local addonName = ...
local L = AddonFactory:SetLocale(addonName, "zhCN")
if not L then return end

-- Translated using ChatGPT, please advise if you notice a mistake.
L["AUTO_UPDATE_DISABLED"] = "任务记录将保持当前状态，无论是空白还是过时的。"
L["AUTO_UPDATE_ENABLED"] = "角色的任务记录将在每次登录该角色时更新。"
L["AUTO_UPDATE_LABEL"] = "任务记录自动更新"
L["AUTO_UPDATE_TITLE"] = "任务记录自动更新"
L["DAILY_QUESTS_RESET_LABEL"] = "每日任务重置于"
L["TRACK_TURNINS_DISABLED"] = "任务记录将保持当前状态，无论是空白还是过时的。"
L["TRACK_TURNINS_ENABLED"] = "已完成的任务会保存在记录中，以确保其始终有效。"
L["TRACK_TURNINS_LABEL"] = "追踪任务完成情况"
L["TRACK_TURNINS_TITLE"] = "追踪任务完成情况"
