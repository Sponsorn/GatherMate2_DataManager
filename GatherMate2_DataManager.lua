local addon, ns = ...
local L = ns.L

local AceSerializer = LibStub("AceSerializer-3.0")
local LibBase64 = LibStub("LibBase64-1.0")
local LibDeflate = LibStub("LibDeflate")

-- GatherMate2's locale for node type display names
local gm2L = LibStub("AceLocale-3.0"):GetLocale("GatherMate2", false)

function ns.GetNodeTypeDisplayName(nodeType)
    return gm2L and gm2L[nodeType] or nodeType
end

-- Namespace exports (populated by other files)
ns.Export = {}
ns.Import = {}
ns.Cleanup = {}

-----------------------------------------------------------
-- Data Access: Zone Enumeration & Grouping
-----------------------------------------------------------

local storageTagNames = {}
local groupedDataCache = nil

local function DiscoverStorageTags()
    wipe(storageTagNames)
    local numAddons = C_AddOns.GetNumAddOns()
    for i = 1, numAddons do
        local name = C_AddOns.GetAddOnInfo(i)
        local tag = C_AddOns.GetAddOnMetadata(name, "X-GM2-Storage-Tag")
        if tag then
            local title = C_AddOns.GetAddOnMetadata(name, "Title") or tag
            title = title:gsub("^GatherMate2:%s*Storage for%s*", "")
            storageTagNames[tag] = title
        end
    end
end

function ns.GetGroupDisplayName(storagePrefix)
    if storagePrefix == "base" then
        return L["BaseStorage"]
    end
    return storageTagNames[storagePrefix] or storagePrefix
end

function ns.GetGroupedData()
    if groupedDataCache then
        return groupedDataCache
    end

    DiscoverStorageTags()

    local grouped = {}

    local function ensureGroup(prefix)
        if not grouped[prefix] then
            grouped[prefix] = {
                zones = {},
                totalCount = 0,
                displayName = ns.GetGroupDisplayName(prefix),
            }
        end
        return grouped[prefix]
    end

    local function ensureZone(group, mapId)
        if not group.zones[mapId] then
            local mapInfo = C_Map.GetMapInfo(mapId)
            if not mapInfo or not mapInfo.name or mapInfo.name == "" then
                return nil
            end
            if mapInfo.mapType and mapInfo.mapType > 3 then
                return nil
            end
            group.zones[mapId] = {
                name = mapInfo.name,
                types = {},
                totalCount = 0,
            }
        end
        return group.zones[mapId]
    end

    local function processStorage(storagePrefix, storage, nodeType)
        for zone, data in pairs(storage) do
            local count = 0
            for _ in pairs(data) do
                count = count + 1
            end
            if count > 0 then
                local group = ensureGroup(storagePrefix)
                local zoneData = ensureZone(group, zone)
                if zoneData then
                    zoneData.types[nodeType] = (zoneData.types[nodeType] or 0) + count
                    zoneData.totalCount = zoneData.totalCount + count
                    group.totalCount = group.totalCount + count
                end
            end
        end
    end

    for _, nodeType in ipairs(GatherMate2.db_types) do
        local db_meta = GatherMate2.gmdbs[nodeType]
        if db_meta and db_meta.__gm2_base_storage then
            processStorage("base", db_meta.__gm2_base_storage, nodeType)
            if db_meta.__gm2_storage_map then
                for storagePrefix, storage in pairs(db_meta.__gm2_storage_map) do
                    processStorage(storagePrefix, storage, nodeType)
                end
            end
        end
    end

    groupedDataCache = grouped
    return grouped
end

function ns.RefreshGroupedData()
    groupedDataCache = nil
    return ns.GetGroupedData()
end

function ns.GetSortedGroupKeys(grouped)
    local keys = {}
    for k in pairs(grouped) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        if a == "base" then return false end
        if b == "base" then return true end
        return a > b
    end)
    return keys
end

function ns.GetSortedZoneIds(group)
    local ids = {}
    for mapId in pairs(group.zones) do
        ids[#ids + 1] = mapId
    end
    table.sort(ids, function(a, b)
        return (group.zones[a].name or "") < (group.zones[b].name or "")
    end)
    return ids
end

-----------------------------------------------------------
-- Serialization / Deserialization
-----------------------------------------------------------

local FORMAT_VERSION = 1

function ns.CollectExportData(typeFilter, zoneFilter, storageFilter, scopeLabel)
    local data = {}
    local counts = {}
    local hasData = false

    for _, nodeType in ipairs(GatherMate2.db_types) do
        if typeFilter[nodeType] then
            local db_meta = GatherMate2.gmdbs[nodeType]
            if db_meta and db_meta.__gm2_base_storage then
                local nodeData = {}

                local function collectFromStorage(prefix, storage)
                    if storageFilter and prefix ~= storageFilter then return end
                    for zone, zoneNodes in pairs(storage) do
                        if not zoneFilter or zoneFilter[zone] then
                            nodeData[zone] = CopyTable(zoneNodes)
                            hasData = true
                        end
                    end
                end

                collectFromStorage("base", db_meta.__gm2_base_storage)
                if db_meta.__gm2_storage_map then
                    for prefix, storage in pairs(db_meta.__gm2_storage_map) do
                        collectFromStorage(prefix, storage)
                    end
                end

                if next(nodeData) then
                    data[nodeType] = nodeData
                    local count = 0
                    for _, zoneNodes in pairs(nodeData) do
                        for _ in pairs(zoneNodes) do
                            count = count + 1
                        end
                    end
                    counts[nodeType] = count
                end
            end
        end
    end

    if not hasData then return nil end

    local playerName = UnitName("player")
    local realmName = GetRealmName()

    data._meta = {
        version = FORMAT_VERSION,
        timestamp = time(),
        source = playerName .. "-" .. realmName,
        counts = counts,
        scope = scopeLabel or "all",
    }

    return data
end

function ns.Encode(data)
    local serialized = AceSerializer:Serialize(data)
    if not serialized then return nil end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then return nil end

    local encoded = LibBase64.Encode(compressed)
    return encoded
end

function ns.Decode(str)
    if not str or str == "" then
        return false, L["ImportFailed"]
    end

    local decoded = LibBase64.Decode(str)
    if not decoded then
        return false, L["ImportFailed"]
    end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return false, L["ImportFailed"]
    end

    local success, data = AceSerializer:Deserialize(decompressed)
    if not success or not data then
        return false, L["ImportFailed"]
    end

    if not data._meta then
        return false, L["ImportFailed"]
    end
    if data._meta.version and data._meta.version > FORMAT_VERSION then
        return false, L["ImportVersionError"]
    end

    return true, data
end

-----------------------------------------------------------
-- StaticPopup Definitions
-----------------------------------------------------------

local exportString = { value = "" }

StaticPopupDialogs["GM2DM_EXPORT"] = {
    text = L["ExportStringCopy"],
    button1 = OKAY,
    hasEditBox = 1,
    editBoxWidth = 360,
    OnShow = function(self)
        self.editBox:SetText(exportString.value)
        self.editBox:SetFocus()
        self.editBox:HighlightText()
    end,
    OnHide = function(self)
        self.editBox:SetText("")
        exportString.value = ""
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
}

function ns.ShowExportString(encoded)
    exportString.value = encoded
    StaticPopup_Show("GM2DM_EXPORT")
end

StaticPopupDialogs["GM2DM_IMPORT"] = {
    text = L["PasteString"],
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = 1,
    editBoxWidth = 360,
    OnShow = function(self)
        self.editBox:SetText("")
        self.editBox:SetFocus()
        self.editBox:SetScript("OnTextChanged", nil)
    end,
    OnAccept = function(self)
        local str = self.editBox:GetText()
        if ns.Import.OnStringPasted then
            ns.Import.OnStringPasted(str)
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local str = self:GetText()  -- self is the editbox, not the dialog
        if ns.Import.OnStringPasted then
            ns.Import.OnStringPasted(str)
        end
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    OnHide = function(self)
        self.editBox:SetText("")
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
}

StaticPopupDialogs["GM2DM_CONFIRM"] = {
    text = "%s",
    button1 = OKAY,
    button2 = CANCEL,
    OnAccept = function(self, callback)
        if callback then callback() end
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
}

function ns.ShowConfirm(text, callback)
    local dialog = StaticPopup_Show("GM2DM_CONFIRM", text)
    if dialog then
        dialog.data = callback
    end
end

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
