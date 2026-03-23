local addon, ns = ...
local L = ns.L

-----------------------------------------------------------
-- Database Statistics
-----------------------------------------------------------

local function FormatNumber(n)
    if n < 1000 then return tostring(n) end
    return format("%s,%03d", FormatNumber(floor(n / 1000)), n % 1000)
end

local function BuildStatsText()
    local grouped = ns.GetGroupedData()
    local sortedKeys = ns.GetSortedGroupKeys(grouped)
    local lines = {}
    local grandTotal = 0
    local groupCount = 0

    for _, prefix in ipairs(sortedKeys) do
        local group = grouped[prefix]
        if group.totalCount > 0 then
            groupCount = groupCount + 1
            grandTotal = grandTotal + group.totalCount

            lines[#lines + 1] = "|cff00aaff" .. group.displayName .. ":|r " .. FormatNumber(group.totalCount) .. " nodes"

            local typeCounts = {}
            for _, zoneData in pairs(group.zones) do
                for nodeType, count in pairs(zoneData.types) do
                    typeCounts[nodeType] = (typeCounts[nodeType] or 0) + count
                end
            end

            local parts = {}
            for _, nodeType in ipairs(GatherMate2.db_types) do
                if typeCounts[nodeType] then
                    parts[#parts + 1] = ns.GetNodeTypeDisplayName(nodeType) .. ": " .. FormatNumber(typeCounts[nodeType])
                end
            end
            if #parts > 0 then
                lines[#lines + 1] = "  " .. table.concat(parts, "  |  ")
            end
            lines[#lines + 1] = ""
        end
    end

    lines[#lines + 1] = L["TotalStats"]:format(FormatNumber(grandTotal), groupCount)

    return table.concat(lines, "\n")
end

-----------------------------------------------------------
-- Selective Wipe
-----------------------------------------------------------

local function WipeZoneType(nodeType, mapId)
    local db_meta = GatherMate2.gmdbs[nodeType]
    if not db_meta or not db_meta.__gm2_base_storage then return 0 end
    if GatherMate2.db.profile.dbLocks[nodeType] then return 0 end

    local count = 0

    if db_meta.__gm2_base_storage[mapId] then
        for _ in pairs(db_meta.__gm2_base_storage[mapId]) do
            count = count + 1
        end
        db_meta.__gm2_base_storage[mapId] = nil
    end

    if db_meta.__gm2_storage_map then
        for _, storage in pairs(db_meta.__gm2_storage_map) do
            if storage[mapId] then
                for _ in pairs(storage[mapId]) do
                    count = count + 1
                end
                storage[mapId] = nil
            end
        end
    end

    return count
end

local function WipeGroupTypes(storagePrefix, typeFilter)
    local grouped = ns.GetGroupedData()
    local group = grouped[storagePrefix]
    if not group then return 0 end

    local totalDeleted = 0
    for mapId in pairs(group.zones) do
        for nodeType in pairs(typeFilter) do
            if typeFilter[nodeType] then
                totalDeleted = totalDeleted + WipeZoneType(nodeType, mapId)
            end
        end
    end

    return totalDeleted
end

local function WipeZoneTypes(mapId, typeFilter)
    local totalDeleted = 0
    for nodeType, enabled in pairs(typeFilter) do
        if enabled then
            totalDeleted = totalDeleted + WipeZoneType(nodeType, mapId)
        end
    end
    return totalDeleted
end

-----------------------------------------------------------
-- Deprecated Node Scan
-----------------------------------------------------------

local deprecatedCount = nil

local function ScanDeprecated()
    local count = 0

    for _, nodeType in ipairs(GatherMate2.db_types) do
        local db_meta = GatherMate2.gmdbs[nodeType]
        if db_meta and db_meta.__gm2_base_storage then
            local function scanStorage(storage)
                for zone, data in pairs(storage) do
                    for coord, nodeId in pairs(data) do
                        if not GatherMate2:GetNameForNode(nodeType, nodeId) then
                            count = count + 1
                        end
                    end
                end
            end

            scanStorage(db_meta.__gm2_base_storage)
            if db_meta.__gm2_storage_map then
                for _, storage in pairs(db_meta.__gm2_storage_map) do
                    scanStorage(storage)
                end
            end
        end
    end

    deprecatedCount = count
    return count
end

local function CleanDeprecated()
    local removed = 0

    for _, nodeType in ipairs(GatherMate2.db_types) do
        local db_meta = GatherMate2.gmdbs[nodeType]
        if db_meta and db_meta.__gm2_base_storage then
            local function cleanStorage(storage)
                for zone, data in pairs(storage) do
                    for coord, nodeId in pairs(data) do
                        if not GatherMate2:GetNameForNode(nodeType, nodeId) then
                            data[coord] = nil
                            removed = removed + 1
                        end
                    end
                    if not next(data) then
                        storage[zone] = nil
                    end
                end
            end

            cleanStorage(db_meta.__gm2_base_storage)
            if db_meta.__gm2_storage_map then
                for _, storage in pairs(db_meta.__gm2_storage_map) do
                    cleanStorage(storage)
                end
            end
        end
    end

    deprecatedCount = 0
    return removed
end

-----------------------------------------------------------
-- Selective Wipe State
-----------------------------------------------------------

local wipeTypeSelected = {}
for _, nodeType in ipairs(GatherMate2.db_types) do
    wipeTypeSelected[nodeType] = false
end

-----------------------------------------------------------
-- Build Selective Wipe Tree
-----------------------------------------------------------

local function BuildWipeTree()
    local grouped = ns.GetGroupedData()
    local sortedKeys = ns.GetSortedGroupKeys(grouped)
    local args = {}
    local orderCounter = 1

    for _, prefix in ipairs(sortedKeys) do
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
                local locked = GatherMate2.db.profile.dbLocks[nodeType] or false
                groupArgs[nodeType] = {
                    type = "toggle",
                    order = i,
                    name = locked
                        and L["TypeLocked"]:format(ns.GetNodeTypeDisplayName(nodeType))
                        or ns.GetNodeTypeDisplayName(nodeType),
                    get = function() return wipeTypeSelected[nodeType] end,
                    set = function(_, val) wipeTypeSelected[nodeType] = val end,
                    disabled = function() return locked end,
                }
            end
        end

        groupArgs.delete = {
            type = "execute",
            order = 99,
            width = "full",
            name = L["DeleteSelected"],
            func = function()
                local filter = {}
                for nt, sel in pairs(wipeTypeSelected) do
                    if sel then filter[nt] = true end
                end
                if not next(filter) then return end

                ns.ShowConfirm(
                    "Delete selected node types from " .. group.displayName .. "? This cannot be undone.",
                    function()
                        local deleted = WipeGroupTypes(prefix, filter)
                        print("|cff00ff00" .. addon .. ":|r " .. L["DeleteSuccess"]:format(deleted))
                        GatherMate2:SendMessage("GatherMate2Cleanup")
                        for nt in pairs(wipeTypeSelected) do
                            wipeTypeSelected[nt] = false
                        end
                        ns.Cleanup.Refresh()
                    end
                )
            end,
            disabled = function()
                for _, sel in pairs(wipeTypeSelected) do
                    if sel then return false end
                end
                return true
            end,
        }

        -- Per-zone entries within this group
        local sortedZones = ns.GetSortedZoneIds(group)
        for zi, mapId in ipairs(sortedZones) do
            local zoneData = group.zones[mapId]
            local zoneArgs = {}

            for ii, nodeType in ipairs(GatherMate2.db_types) do
                if zoneData.types[nodeType] then
                    local locked = GatherMate2.db.profile.dbLocks[nodeType] or false
                    zoneArgs[nodeType] = {
                        type = "toggle",
                        order = ii,
                        name = locked
                            and L["TypeLocked"]:format(ns.GetNodeTypeDisplayName(nodeType))
                            or ns.GetNodeTypeDisplayName(nodeType),
                        get = function() return wipeTypeSelected[nodeType] end,
                        set = function(_, val) wipeTypeSelected[nodeType] = val end,
                        disabled = function() return locked end,
                    }
                end
            end

            zoneArgs.delete = {
                type = "execute",
                order = 99,
                width = "full",
                name = L["DeleteSelected"],
                func = function()
                    local filter = {}
                    for nt, sel in pairs(wipeTypeSelected) do
                        if sel then filter[nt] = true end
                    end
                    if not next(filter) then return end

                    ns.ShowConfirm(
                        "Delete selected node types from " .. zoneData.name .. "? This cannot be undone.",
                        function()
                            local deleted = WipeZoneTypes(mapId, filter)
                            print("|cff00ff00" .. addon .. ":|r " .. L["DeleteSuccess"]:format(deleted))
                            for nt in pairs(wipeTypeSelected) do wipeTypeSelected[nt] = false end
                            GatherMate2:SendMessage("GatherMate2Cleanup")
                            ns.Cleanup.Refresh()
                        end
                    )
                end,
                disabled = function()
                    for _, sel in pairs(wipeTypeSelected) do
                        if sel then return false end
                    end
                    return true
                end,
            }

            groupArgs["zone_" .. mapId] = {
                type = "group",
                order = 100 + zi,
                name = zoneData.name .. " (" .. zoneData.totalCount .. ")",
                args = zoneArgs,
            }
        end

        args["group_" .. prefix] = {
            type = "group",
            order = orderCounter,
            name = group.displayName .. " (" .. group.totalCount .. ")",
            childGroups = "tree",
            args = groupArgs,
        }
        orderCounter = orderCounter + 1
    end

    return args
end

-----------------------------------------------------------
-- Wipe by Type (all zones)
-----------------------------------------------------------

local function BuildWipeByTypeArgs()
    local args = {}

    for i, nodeType in ipairs(GatherMate2.db_types) do
        local locked = GatherMate2.db.profile.dbLocks[nodeType] or false
        local totalCount = 0
        local grouped = ns.GetGroupedData()
        for _, group in pairs(grouped) do
            for _, zoneData in pairs(group.zones) do
                totalCount = totalCount + (zoneData.types[nodeType] or 0)
            end
        end

        if totalCount > 0 then
            args["wipe_" .. nodeType] = {
                type = "execute",
                order = i,
                width = "double",
                name = locked
                    and L["TypeLocked"]:format(ns.GetNodeTypeDisplayName(nodeType) .. " (" .. totalCount .. ")")
                    or ns.GetNodeTypeDisplayName(nodeType) .. " (" .. totalCount .. ")",
                disabled = function() return locked end,
                func = function()
                    ns.ShowConfirm(
                        L["DeleteAllConfirm"]:format(ns.GetNodeTypeDisplayName(nodeType), totalCount),
                        function()
                            GatherMate2:ClearDB(nodeType)
                            print("|cff00ff00" .. addon .. ":|r " .. L["DeleteSuccess"]:format(totalCount))
                            GatherMate2:SendMessage("GatherMate2Cleanup")
                            ns.Cleanup.Refresh()
                        end
                    )
                end,
            }
        end
    end

    return args
end

-----------------------------------------------------------
-- Cleanup Options Table
-----------------------------------------------------------

ns.options.args.cleanup = {
    type = "group",
    order = 3,
    name = L["Cleanup"],
    childGroups = "tab",
    args = {
        stats = {
            type = "group",
            order = 1,
            name = L["DatabaseStats"],
            args = {
                statsText = {
                    type = "description",
                    order = 1,
                    name = function() return BuildStatsText() end,
                    fontSize = "medium",
                },
                refresh = {
                    type = "execute",
                    order = 2,
                    name = L["RefreshData"],
                    func = function()
                        ns.Cleanup.Refresh()
                    end,
                },
            },
        },
        wipe = {
            type = "group",
            order = 2,
            name = L["SelectiveWipe"],
            childGroups = "tree",
            args = {},
        },
        wipeByType = {
            type = "group",
            order = 3,
            name = "Wipe by Type",
            args = {},
        },
        scan = {
            type = "group",
            order = 4,
            name = L["ScanClean"],
            args = {
                scanDeprecated = {
                    type = "execute",
                    order = 1,
                    width = "double",
                    name = L["DeprecatedScan"],
                    func = function()
                        ScanDeprecated()
                        LibStub("AceConfigRegistry-3.0"):NotifyChange("GM2/Data Manager")
                    end,
                },
                deprecatedResult = {
                    type = "description",
                    order = 2,
                    name = function()
                        if deprecatedCount == nil then return "" end
                        if deprecatedCount == 0 then
                            return "|cff00ff00" .. L["DeprecatedNone"] .. "|r"
                        end
                        return "|cffff6060" .. L["DeprecatedFound"]:format(deprecatedCount) .. "|r"
                    end,
                    fontSize = "medium",
                    hidden = function() return deprecatedCount == nil end,
                },
                cleanDeprecated = {
                    type = "execute",
                    order = 3,
                    width = "double",
                    name = L["DeprecatedClean"],
                    func = function()
                        ns.ShowConfirm(
                            "Remove " .. deprecatedCount .. " deprecated nodes? This cannot be undone.",
                            function()
                                local removed = CleanDeprecated()
                                print("|cff00ff00" .. addon .. ":|r " .. L["DeleteSuccess"]:format(removed))
                                ns.Cleanup.Refresh()
                            end
                        )
                    end,
                    hidden = function() return not deprecatedCount or deprecatedCount == 0 end,
                },
                spacer = {
                    type = "description",
                    order = 10,
                    name = "\n",
                },
                duplicateHeader = {
                    type = "description",
                    order = 11,
                    name = L["DuplicateWarning"],
                    fontSize = "medium",
                },
                runDuplicateCleanup = {
                    type = "execute",
                    order = 12,
                    width = "double",
                    name = L["DuplicateCleanup"],
                    func = function()
                        ns.ShowConfirm(
                            L["DuplicateWarning"],
                            function()
                                GatherMate2:CleanupDB()
                                ns.Cleanup.Refresh()
                            end
                        )
                    end,
                },
            },
        },
    },
}

-----------------------------------------------------------
-- Init & Refresh
-----------------------------------------------------------

function ns.Cleanup.Init()
    ns.options.args.cleanup.args.wipe.args = BuildWipeTree()
    ns.options.args.cleanup.args.wipeByType.args = BuildWipeByTypeArgs()
end

function ns.Cleanup.Refresh()
    ns.RefreshGroupedData()
    ns.options.args.cleanup.args.wipe.args = BuildWipeTree()
    ns.options.args.cleanup.args.wipeByType.args = BuildWipeByTypeArgs()
    deprecatedCount = nil
    if ns.Export.Init then ns.Export.Init() end
    LibStub("AceConfigRegistry-3.0"):NotifyChange("GM2/Data Manager")
end
