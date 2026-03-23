local addon, ns = ...
local L = ns.L

local AceSerializer = LibStub("AceSerializer-3.0")
local LibBase64 = LibStub("LibBase64-1.0")
local LibDeflate = LibStub("LibDeflate")

-- Namespace exports (populated by other files)
ns.Export = {}
ns.Import = {}
ns.Cleanup = {}

-- Main options table — tabs for Export, Import, Cleanup
local options = {
    type = "group",
    name = L["DataManager"],
    childGroups = "tab",
    args = {
        -- Populated by Export.lua, Import.lua, Cleanup.lua
    },
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent(event)

    local Config = GatherMate2:GetModule("Config")
    if Config then
        Config:RegisterModule(L["DataManager"], options)
    end
end)

-- Make options accessible to other files
ns.options = options
