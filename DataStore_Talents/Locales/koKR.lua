local addonName = ...
local L = AddonFactory:SetLocale(addonName, "koKR")
if not L then return end

L["AUTO_UPDATE_DISABLED"] = "퀘스트 기록은 비거나 오래된 현 상태로 유지됩니다."
L["AUTO_UPDATE_ENABLED"] = "캐릭터의 퀘스트 기록은 그 캐릭터로 접속할 때마다 갱신됩니다."
L["AUTO_UPDATE_LABEL"] = "기록 자동 갱신"
L["AUTO_UPDATE_TITLE"] = "퀘스트 기록 자동 갱신"
L["DAILY_QUESTS_RESET_LABEL"] = "일일 퀘스트 초기화 시간"
L["TRACK_TURNINS_DISABLED"] = "퀘스트 기록은 비거나 오래된 현 상태로 유지됩니다."
L["TRACK_TURNINS_DISABLED"] = "미션 기록은 현재 상태로 유지됩니다. 비어 있거나 최신 상태가 아닐 수 있습니다."
L["TRACK_TURNINS_ENABLED"] = "완료된 미션은 기록되어 계속 유효하게 유지됩니다."
L["TRACK_TURNINS_LABEL"] = "미션 완료 추적"
L["TRACK_TURNINS_TITLE"] = "미션 완료 추적"
