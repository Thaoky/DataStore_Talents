local addonName = ...
local L = AddonFactory:SetLocale(addonName, "esMX")
if not L then return end

L["AUTO_UPDATE_DISABLED"] = "El historial de misiones permanecerá en su estado actual, ya sea vacío o desactualizado."
L["AUTO_UPDATE_ENABLED"] = "El historial de misiones de un personaje se actualizará cada vez que inicies sesión con ese personaje."
L["AUTO_UPDATE_LABEL"] = "Actualización automática del historial"
L["AUTO_UPDATE_TITLE"] = "Actualización automática del historial de misiones"
L["DAILY_QUESTS_RESET_LABEL"] = "Restablecer misiones diarias en"
L["TRACK_TURNINS_DISABLED"] = "El historial de misiones permanecerá en su estado actual, ya sea vacío o desactualizado."
L["TRACK_TURNINS_ENABLED"] = "Las misiones entregadas se guardan en el historial, para asegurarse de que siga siendo válida constantemente."
L["TRACK_TURNINS_LABEL"] = "Seguimiento de entregas de misiones"
L["TRACK_TURNINS_TITLE"] = "Seguimiento de entregas de misiones"
