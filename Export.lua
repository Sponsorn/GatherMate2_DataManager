local addon, ns = ...
local L = ns.L

local typeSelected = {}

-- Initialize all types as selected
for _, nodeType in ipairs(GatherMate2.db_types) do
    typeSelected[nodeType] = true
end

local function GetSelectedTypes()
    local selected = {}
    for nodeType, enabled in pairs(typeSelected) do
        if enabled then
            selected[nodeType] = true
        end
    end
    return selected
end

local function MakeTypeToggle(nodeType, order)
    return {
        type = "toggle",
        order = order,
        name = ns.GetNodeTypeDisplayName(nodeType),
        get = function() return typeSelected[nodeType] end,
        set = function(_, val) typeSelected[nodeType] = val end,
    }
end

-----------------------------------------------------------
-- Export All
-----------------------------------------------------------

local exportAllArgs = {}

for i, nodeType in ipairs(GatherMate2.db_types) do
    exportAllArgs[nodeType] = MakeTypeToggle(nodeType, i)
end

exportAllArgs.create = {
    type = "execute",
    order = 99,
    width = "full",
    name = L["ExportStringCreate"],
    func = function()
        local data = ns.CollectExportData(GetSelectedTypes(), nil, nil, "all")
        if not data then
            print("|cffff6060" .. addon .. ":|r " .. L["NoDataToExport"])
            return
        end
        local encoded = ns.Encode(data)
        if encoded then
            ns.ShowExportString(encoded)
        end
    end,
}

-----------------------------------------------------------
-- Export by Expansion
-----------------------------------------------------------

local function BuildExportByExpansion()
    local grouped = ns.GetGroupedData()
    local sortedKeys = ns.GetSortedGroupKeys(grouped)
    local args = {}

    for order, prefix in ipairs(sortedKeys) do
        local group = grouped[prefix]
        local groupArgs = {}

        for i, nodeType in ipairs(GatherMate2.db_types) do
            local hasData = false
            for _, zoneData in pairs(group.zones) do
                if zoneData.types[nodeType] then
                    hasData = true
                    break
                end
            end
            if hasData then
                groupArgs[nodeType] = MakeTypeToggle(nodeType, i)
            end
        end

        groupArgs.create = {
            type = "execute",
            order = 99,
            width = "full",
            name = L["ExportStringCreate"],
            func = function()
                local zoneFilter = {}
                for mapId in pairs(group.zones) do
                    zoneFilter[mapId] = true
                end
                local scopeLabel = "expansion:" .. group.displayName
                local data = ns.CollectExportData(GetSelectedTypes(), zoneFilter, nil, scopeLabel)
                if not data then
                    print("|cffff6060" .. addon .. ":|r " .. L["NoDataToExport"])
                    return
                end
                local encoded = ns.Encode(data)
                if encoded then
                    ns.ShowExportString(encoded)
                end
            end,
        }

        args["group_" .. prefix] = {
            type = "group",
            order = order,
            name = group.displayName .. " (" .. group.totalCount .. ")",
            args = groupArgs,
        }
    end

    return args
end

-----------------------------------------------------------
-- Export by Zone
-----------------------------------------------------------

local function BuildExportByZone()
    local grouped = ns.GetGroupedData()
    local sortedKeys = ns.GetSortedGroupKeys(grouped)
    local args = {}
    local orderCounter = 1

    for _, prefix in ipairs(sortedKeys) do
        local group = grouped[prefix]

        -- Expansion header (visual separator)
        args["header_" .. prefix] = {
            type = "header",
            order = orderCounter,
            name = group.displayName,
        }
        orderCounter = orderCounter + 1

        local sortedZones = ns.GetSortedZoneIds(group)
        for _, mapId in ipairs(sortedZones) do
            local zoneData = group.zones[mapId]
            local zoneArgs = {}

            for i, nodeType in ipairs(GatherMate2.db_types) do
                if zoneData.types[nodeType] then
                    zoneArgs[nodeType] = MakeTypeToggle(nodeType, i)
                end
            end

            zoneArgs.create = {
                type = "execute",
                order = 99,
                width = "full",
                name = L["ExportStringCreate"],
                func = function()
                    local zoneFilter = { [mapId] = true }
                    local scopeLabel = "zone:" .. zoneData.name
                    local data = ns.CollectExportData(GetSelectedTypes(), zoneFilter, nil, scopeLabel)
                    if not data then
                        print("|cffff6060" .. addon .. ":|r " .. L["NoDataToExport"])
                        return
                    end
                    local encoded = ns.Encode(data)
                    if encoded then
                        ns.ShowExportString(encoded)
                    end
                end,
            }

            args["zone_" .. mapId] = {
                type = "group",
                order = orderCounter,
                name = zoneData.name .. " (" .. zoneData.totalCount .. ")",
                args = zoneArgs,
            }
            orderCounter = orderCounter + 1
        end
    end

    return args
end

-----------------------------------------------------------
-- Register into main options
-----------------------------------------------------------

ns.options.args.export = {
    type = "group",
    order = 1,
    name = L["Export"],
    childGroups = "tab",
    args = {
        exportAll = {
            type = "group",
            order = 1,
            name = L["ExportAll"],
            inline = true,
            args = exportAllArgs,
        },
        exportByExpansion = {
            type = "group",
            order = 2,
            name = L["ExportByExpansion"],
            childGroups = "tree",
            args = {},
        },
        exportByZone = {
            type = "group",
            order = 3,
            name = L["ExportByZone"],
            childGroups = "tree",
            args = {},
        },
    },
}

-- Export init/refresh — rebuilds tree args from current grouped data
function ns.Export.Init()
    ns.options.args.export.args.exportByExpansion.args = BuildExportByExpansion()
    ns.options.args.export.args.exportByZone.args = BuildExportByZone()
end
