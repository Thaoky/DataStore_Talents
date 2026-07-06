local addonName = ...
local L = AddonFactory:SetLocale(addonName, "frFR")
if not L then return end

L["AUTO_UPDATE_DISABLED"] = "L'historique de quêtes restera dans son état actuel, soit vide ou obsolète."
L["AUTO_UPDATE_ENABLED"] = "L'historique de quêtes d'un personnage sera rafraîchi à chaque connexion de ce personnage."
L["AUTO_UPDATE_LABEL"] = "Mise à jour automatique de l'historique"
L["AUTO_UPDATE_TITLE"] = "Mise à jour automatique de l'historique de quêtes"
L["DAILY_QUESTS_RESET_LABEL"] = "Réinitialiser les quêtes journalières à"
L["TRACK_TURNINS_DISABLED"] = "L'historique de quêtes restera dans son état actuel, soit vide ou obsolète."
L["TRACK_TURNINS_ENABLED"] = "Les validations de quêtes sont sauvées dans l'historique, afin d'assurer qu'il soit toujours valide."
L["TRACK_TURNINS_LABEL"] = "Suivre les validations de quêtes"
L["TRACK_TURNINS_TITLE"] = "Suivre les validations de quêtes"
