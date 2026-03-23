local addon, ns = ...
local L = ns.L

-----------------------------------------------------------
-- Import Preview
-----------------------------------------------------------

function ns.Import.AnalyzeImportData(data)
    local results = {}

    for _, nodeType in ipairs(GatherMate2.db_types) do
        if data[nodeType] then
            local total, new, existing = 0, 0, 0
            local locked = GatherMate2.db.profile.dbLocks[nodeType] or false

            for zone, nodes in pairs(data[nodeType]) do
                local existingZone = GatherMate2.gmdbs[nodeType][zone]
                for coord, nodeId in pairs(nodes) do
                    total = total + 1
                    if existingZone and existingZone[coord] then
                        existing = existing + 1
                    else
                        new = new + 1
                    end
                end
            end

            if total > 0 then
                results[nodeType] = {
                    total = total,
                    new = new,
                    existing = existing,
                    locked = locked,
                }
            end
        end
    end

    return results
end

-----------------------------------------------------------
-- Import Execution
-----------------------------------------------------------

function ns.Import.ExecuteImport(data, typeFilter)
    local imported = 0

    for _, nodeType in ipairs(GatherMate2.db_types) do
        if typeFilter[nodeType] and data[nodeType] then
            for zone, nodes in pairs(data[nodeType]) do
                local existingZone = GatherMate2.gmdbs[nodeType][zone]
                for coord, nodeId in pairs(nodes) do
                    if not (existingZone and existingZone[coord]) then
                        GatherMate2:InjectNode2(zone, coord, nodeType, nodeId)
                        imported = imported + 1
                    end
                end
            end
        end
    end

    return imported
end

-----------------------------------------------------------
-- Import State & UI
-----------------------------------------------------------

local importState = {
    data = nil,
    analysis = nil,
    meta = nil,
    typeFilter = {},
}

local function ClearImportState()
    importState.data = nil
    importState.analysis = nil
    importState.meta = nil
    wipe(importState.typeFilter)
end

local function GetPreviewText()
    if not importState.analysis then
        return ""
    end

    local lines = {}
    local meta = importState.meta
    if meta then
        if meta.source then
            lines[#lines + 1] = "Source: |cff00ff00" .. meta.source .. "|r"
        end
        if meta.timestamp then
            lines[#lines + 1] = "Date: |cff00ff00" .. date("%Y-%m-%d %H:%M", meta.timestamp) .. "|r"
        end
        if meta.scope then
            lines[#lines + 1] = "Scope: |cff00ff00" .. meta.scope .. "|r"
        end
        lines[#lines + 1] = ""
    end

    local totalNew = 0
    for _, nodeType in ipairs(GatherMate2.db_types) do
        local info = importState.analysis[nodeType]
        if info then
            local status = ""
            if info.locked then
                status = " |cffff0000(Locked)|r"
            end
            lines[#lines + 1] = L["ImportSummaryLine"]:format(
                ns.GetNodeTypeDisplayName(nodeType),
                info.total,
                info.new,
                info.existing
            ) .. status
            if importState.typeFilter[nodeType] and not info.locked then
                totalNew = totalNew + info.new
            end
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Total to import: |cff00ff00" .. totalNew .. "|r new nodes"

    return table.concat(lines, "\n")
end

function ns.Import.OnStringPasted(str)
    ClearImportState()

    local success, data = ns.Decode(str)
    if not success then
        print("|cffff6060" .. addon .. ":|r " .. data)
        return
    end

    importState.data = data
    importState.meta = data._meta
    importState.analysis = ns.Import.AnalyzeImportData(data)

    for nodeType, info in pairs(importState.analysis) do
        importState.typeFilter[nodeType] = not info.locked
    end

    LibStub("AceConfigRegistry-3.0"):NotifyChange("GM2/Data Manager")
end

-----------------------------------------------------------
-- AceConfig Options Table
-----------------------------------------------------------

local importArgs = {
    openDialog = {
        type = "execute",
        order = 1,
        width = "double",
        name = L["OpenImportDialog"],
        desc = L["OpenImportDialogDesc"],
        func = function()
            ClearImportState()
            StaticPopup_Show("GM2DM_IMPORT")
        end,
    },
    preview = {
        type = "description",
        order = 10,
        name = function() return GetPreviewText() end,
        fontSize = "medium",
        hidden = function() return importState.analysis == nil end,
    },
}

for i, nodeType in ipairs(GatherMate2.db_types) do
    importArgs["toggle_" .. nodeType] = {
        type = "toggle",
        order = 20 + i,
        name = ns.GetNodeTypeDisplayName(nodeType),
        get = function() return importState.typeFilter[nodeType] end,
        set = function(_, val) importState.typeFilter[nodeType] = val end,
        hidden = function()
            return not importState.analysis or not importState.analysis[nodeType]
        end,
        disabled = function()
            return importState.analysis and importState.analysis[nodeType]
                and importState.analysis[nodeType].locked
        end,
    }
end

importArgs.doImport = {
    type = "execute",
    order = 90,
    width = "full",
    name = function()
        if not importState.analysis then return L["Import"] end
        local totalNew = 0
        for nodeType, info in pairs(importState.analysis) do
            if importState.typeFilter[nodeType] and not info.locked then
                totalNew = totalNew + info.new
            end
        end
        return L["ImportConfirm"]:format(totalNew)
    end,
    func = function()
        if not importState.data then return end
        local count = ns.Import.ExecuteImport(importState.data, importState.typeFilter)
        print("|cff00ff00" .. addon .. ":|r " .. L["ImportSuccess"]:format(count))
        ClearImportState()
        if ns.Cleanup.Refresh then ns.Cleanup.Refresh() end
        LibStub("AceConfigRegistry-3.0"):NotifyChange("GM2/Data Manager")
    end,
    hidden = function() return importState.analysis == nil end,
    disabled = function()
        if not importState.analysis then return true end
        for nodeType, enabled in pairs(importState.typeFilter) do
            if enabled and importState.analysis[nodeType]
                and not importState.analysis[nodeType].locked then
                return false
            end
        end
        return true
    end,
}

ns.options.args.import = {
    type = "group",
    order = 2,
    name = L["Import"],
    args = importArgs,
}
