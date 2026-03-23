local L, addon, ns = {}, ...
ns.L = setmetatable(L, {
    __index = function(t, k)
        local v = tostring(k)
        rawset(t, k, v)
        return v
    end,
})

-- General
L["DataManager"] = "Data Manager"

-- Export
L["Export"] = "Export"
L["ExportAll"] = "Export All"
L["ExportByExpansion"] = "Export by Expansion"
L["ExportByZone"] = "Export by Zone"
L["ExportStringCreate"] = "Create Export String"
L["ExportStringCopy"] = "Copy export string with Ctrl+C"
L["NoDataToExport"] = "No data to export for the selected types."

-- Import
L["Import"] = "Import"
L["OpenImportDialog"] = "Open Import Dialog"
L["OpenImportDialogDesc"] = "Click to open the import dialog. Paste an export string to import node data."
L["PasteString"] = "Paste the export string here with Ctrl+V"
L["ImportPreview"] = "Import Preview"
L["ImportConfirm"] = "Import %d new nodes?"
L["ImportSuccess"] = "Successfully imported %d new nodes."
L["ImportFailed"] = "Could not decode import string. Make sure you copied the entire string."
L["ImportVersionError"] = "This string was created with a newer version of GatherMate2 Data Manager."
L["ImportNoData"] = "No data selected for import."
L["TypeLocked"] = "%s (Locked)"
L["ImportSummaryLine"] = "%s: %d nodes (%d new, %d existing)"

-- Cleanup
L["Cleanup"] = "Cleanup"
L["DatabaseStats"] = "Database Statistics"
L["SelectiveWipe"] = "Selective Wipe"
L["ScanClean"] = "Scan & Clean"
L["DeleteSelected"] = "Delete Selected"
L["DeleteConfirm"] = "Delete %d %s nodes from %s? This cannot be undone."
L["DeleteAllConfirm"] = "Delete ALL %s data (%d nodes)? This cannot be undone."
L["DeleteSuccess"] = "Deleted %d nodes."
L["DeprecatedScan"] = "Scan for Deprecated Nodes"
L["DeprecatedFound"] = "Found %d deprecated nodes."
L["DeprecatedNone"] = "No deprecated nodes found."
L["DeprecatedClean"] = "Remove Deprecated Nodes"
L["DuplicateCleanup"] = "Run Duplicate Cleanup"
L["DuplicateWarning"] = "This will remove duplicate nodes that are too close together. GatherMate2 will print results when finished."
L["RefreshData"] = "Refresh Data"
L["TotalStats"] = "Total: %s nodes across %d groups"
L["BaseStorage"] = "Classic \226\128\148 Shadowlands"
