# Alternative Clipboard History Export using Registry and File System
# This method works in both Windows PowerShell 5.1 and PowerShell 7+

# Function to get pinned clipboard items from file system
Function Get-PinnedClipboardItems {
    $pinnedPath = "$env:LOCALAPPDATA\Microsoft\Windows\Clipboard\Pinned"
    $pinnedItems = @()

    Write-Host "   Checking pinned items at: $pinnedPath" -ForegroundColor White

    if (Test-Path $pinnedPath) {
        $pinnedFolders = Get-ChildItem -Path $pinnedPath -Directory -ErrorAction SilentlyContinue

        Write-Host "   Found $($pinnedFolders.Count) pinned item folders" -ForegroundColor White

        foreach ($folder in $pinnedFolders) {
            try {
                $metadataFile = Get-ChildItem -Path $folder.FullName -Filter "*.metadata" -ErrorAction SilentlyContinue | Select-Object -First 1
                $contentFile = Get-ChildItem -Path $folder.FullName -Filter "*.content" -ErrorAction SilentlyContinue | Select-Object -First 1
                $allFiles = Get-ChildItem -Path $folder.FullName -File -ErrorAction SilentlyContinue

                $pinnedItem = [PSCustomObject]@{
                    ID = $folder.Name
                    FolderPath = $folder.FullName
                    CreatedTime = $folder.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                    ModifiedTime = $folder.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    Content = ""
                    ContentType = "Pinned Item"
                    IsPinned = $true
                    FilesCount = $allFiles.Count
                    MetadataFile = if ($metadataFile) { $metadataFile.FullName } else { "Not found" }
                    ContentFile = if ($contentFile) { $contentFile.FullName } else { "Not found" }
                    RawContent = ""
                }

                # Try to read content from various file types
                $contentRead = $false

                # Try .content file first
                if ($contentFile -and $contentFile.Length -lt 10MB) {
                    try {
                        $content = Get-Content -Path $contentFile.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                        if ($content) {
                            $pinnedItem.Content = if ($content.Length -gt 1000) { $content.Substring(0, 1000) + "..." } else { $content }
                            $pinnedItem.RawContent = $content
                            $contentRead = $true
                        }
                    } catch {
                        # Try binary read
                        try {
                            $bytes = [System.IO.File]::ReadAllBytes($contentFile.FullName)
                            $pinnedItem.Content = "[Binary content - $($bytes.Length) bytes]"
                            $pinnedItem.ContentType = "Pinned Item (Binary)"
                            $contentRead = $true
                        } catch {
                            $pinnedItem.Content = "[Error reading content file]"
                        }
                    }
                }

                # Try other files if .content didn't work
                if (!$contentRead) {
                    foreach ($file in $allFiles) {
                        if ($file.Length -lt 1MB) {
                            try {
                                $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                                if ($content -and $content.Trim().Length -gt 0) {
                                    $pinnedItem.Content = if ($content.Length -gt 1000) { $content.Substring(0, 1000) + "..." } else { $content }
                                    $pinnedItem.RawContent = $content
                                    $pinnedItem.ContentType = "Pinned Item (from $($file.Name))"
                                    $contentRead = $true
                                    break
                                }
                            } catch {
                                # Try next file
                                continue
                            }
                        }
                    }
                }

                # Try to read metadata if available
                if ($metadataFile) {
                    try {
                        $metadata = Get-Content -Path $metadataFile.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                        if ($metadata) {
                            $pinnedItem.ContentType += " (with metadata)"
                        }
                    } catch {
                        # Metadata reading failed, keep default
                    }
                }

                $pinnedItems += $pinnedItem
            }
            catch {
                Write-Host "   Error processing folder: $($folder.Name)" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "   Pinned items folder not found" -ForegroundColor Yellow
    }

    return $pinnedItems
}

# Function to get clipboard history from Activities database
Function Get-ClipboardFromActivities {
    param(
        [string]$DatabasePath = "$env:LOCALAPPDATA\ConnectedDevicesPlatform\L.$env:USERNAME\ActivitiesCache.db"
    )

    if (!(Test-Path $DatabasePath)) {
        Write-Warning "Activities database not found at: $DatabasePath"
        return $null
    }

    # Check if sqlite3 is available
    $sqlite3Path = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if (!$sqlite3Path) {
        Write-Warning "sqlite3 not found. Installing sqlite3 via chocolatey or download manually."
        Write-Host "You can install sqlite3 by running: choco install sqlite" -ForegroundColor Yellow
        return $null
    }

    try {
        # Query to get clipboard data from Activities database
        $query = @"
SELECT
    json_extract(payload, '$.clipboardPayload') as clipboard_data,
    json_extract(payload, '$.pinnedStatus') as pinned_status,
    start_time,
    end_time,
    created_in_cloud,
    activity_type,
    id
FROM Activity
WHERE activity_type = 'Clipboard'
ORDER BY start_time DESC
"@

        $tempFile = [System.IO.Path]::GetTempFileName()
        $query | Out-File -FilePath $tempFile -Encoding UTF8

        # Execute SQLite query
        $result = & sqlite3 $DatabasePath ".read $tempFile" 2>&1
        Remove-Item $tempFile -Force

        if ($result) {
            return $result
        }
    }
    catch {
        Write-Error "Error querying Activities database: $($_.Exception.Message)"
    }

    return $null
}

# Function to get clipboard history from Windows API using C#
Function Get-ClipboardHistoryViaCSharp {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class ClipboardHistory
{
    [DllImport("user32.dll")]
    public static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll")]
    public static extern bool CloseClipboard();

    [DllImport("user32.dll")]
    public static extern uint EnumClipboardFormats(uint format);

    [DllImport("user32.dll")]
    public static extern IntPtr GetClipboardData(uint uFormat);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll")]
    public static extern bool GlobalUnlock(IntPtr hMem);

    [DllImport("kernel32.dll")]
    public static extern int GlobalSize(IntPtr hMem);

    public static string GetClipboardText()
    {
        if (!OpenClipboard(IntPtr.Zero))
            return null;

        try
        {
            IntPtr handle = GetClipboardData(1); // CF_TEXT = 1
            if (handle == IntPtr.Zero)
                return null;

            IntPtr pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero)
                return null;

            try
            {
                int size = GlobalSize(handle);
                byte[] buffer = new byte[size];
                Marshal.Copy(pointer, buffer, 0, size);
                return Encoding.UTF8.GetString(buffer).TrimEnd('\0');
            }
            finally
            {
                GlobalUnlock(handle);
            }
        }
        finally
        {
            CloseClipboard();
        }
    }
}
"@

    return [ClipboardHistory]::GetClipboardText()
}

# Function to get clipboard history from registry settings
Function Get-ClipboardSettings {
    $regPath = "HKCU:\Software\Microsoft\Clipboard"

    if (Test-Path $regPath) {
        $clipboardSettings = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        return $clipboardSettings
    }

    return $null
}

# Function to get clipboard history from roaming folder
Function Get-ClipboardFromRoaming {
    $clipboardPath = "$env:APPDATA\Microsoft\Clipboard"

    if (Test-Path $clipboardPath) {
        $clipboardFiles = Get-ChildItem -Path $clipboardPath -Recurse -File -ErrorAction SilentlyContinue

        $clipboardData = @()
        foreach ($file in $clipboardFiles) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                if ($content) {
                    $clipboardData += [PSCustomObject]@{
                        FileName = $file.Name
                        FilePath = $file.FullName
                        LastModified = $file.LastWriteTime
                        Size = $file.Length
                        Content = if ($content.Length -gt 1000) { $content.Substring(0, 1000) + "..." } else { $content }
                    }
                }
            }
            catch {
                # Skip files that can't be read
            }
        }

        return $clipboardData
    }

    return $null
}

# Main execution
Write-Host "Attempting to retrieve clipboard history using multiple methods..." -ForegroundColor Yellow

# Method 1: Try Activities database
Write-Host "`n1. Checking Activities database..." -ForegroundColor Cyan
$activitiesData = Get-ClipboardFromActivities
if ($activitiesData) {
    Write-Host "   Activities data found!" -ForegroundColor Green
}

# Method 2: Try current clipboard content
Write-Host "`n2. Getting current clipboard content..." -ForegroundColor Cyan
$currentClipboard = Get-ClipboardHistoryViaCSharp
if ($currentClipboard) {
    Write-Host "   Current clipboard: $($currentClipboard.Substring(0, [Math]::Min(50, $currentClipboard.Length)))..." -ForegroundColor Green
}

# Method 3: Try registry settings
Write-Host "`n3. Checking clipboard settings..." -ForegroundColor Cyan
$clipboardSettings = Get-ClipboardSettings
if ($clipboardSettings) {
    Write-Host "   Clipboard settings found!" -ForegroundColor Green
}

# Method 4: Try roaming folder
Write-Host "`n4. Checking roaming clipboard folder..." -ForegroundColor Cyan
$roamingData = Get-ClipboardFromRoaming
if ($roamingData) {
    Write-Host "   Roaming clipboard files found: $($roamingData.Count)" -ForegroundColor Green
}

# Method 5: Get pinned clipboard items
Write-Host "`n5. Checking pinned clipboard items..." -ForegroundColor Cyan
$pinnedItems = Get-PinnedClipboardItems
if ($pinnedItems) {
    Write-Host "   Pinned items found: $($pinnedItems.Count)" -ForegroundColor Green
}

# Export results
$exportData = @()

if ($activitiesData) {
    $exportData += [PSCustomObject]@{
        Source = "Activities Database"
        Data = $activitiesData -join "`n"
        Timestamp = Get-Date
        IsPinned = $false
    }
}

if ($currentClipboard) {
    $exportData += [PSCustomObject]@{
        Source = "Current Clipboard"
        Data = $currentClipboard
        Timestamp = Get-Date
        IsPinned = $false
    }
}

if ($clipboardSettings) {
    $exportData += [PSCustomObject]@{
        Source = "Registry Settings"
        Data = ($clipboardSettings | Out-String)
        Timestamp = Get-Date
        IsPinned = $false
    }
}

if ($roamingData) {
    foreach ($item in $roamingData) {
        $exportData += [PSCustomObject]@{
            Source = "Roaming File: $($item.FileName)"
            Data = $item.Content
            Timestamp = $item.LastModified
            IsPinned = $false
        }
    }
}

if ($pinnedItems) {
    foreach ($item in $pinnedItems) {
        $exportData += [PSCustomObject]@{
            Source = "Pinned Item: $($item.ID)"
            Data = $item.Content
            Timestamp = $item.CreatedTime
            IsPinned = $true
            FolderPath = $item.FolderPath
            FilesCount = $item.FilesCount
        }
    }
}

# Export to files
if ($exportData.Count -gt 0) {
    $csvPath = "$env:USERPROFILE\Desktop\ClipboardHistory_Complete_Alternative.csv"
    $jsonPath = "$env:USERPROFILE\Desktop\ClipboardHistory_Complete_Alternative.json"

    $exportData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8

    # Export pinned items separately if found
    $pinnedOnly = $exportData | Where-Object { $_.IsPinned -eq $true }
    if ($pinnedOnly) {
        $pinnedCsvPath = "$env:USERPROFILE\Desktop\ClipboardHistory_PinnedOnly_Alternative.csv"
        $pinnedOnly | Export-Csv -Path $pinnedCsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Pinned items CSV: $pinnedCsvPath" -ForegroundColor White
    }

    Write-Host "`nExport completed!" -ForegroundColor Green
    Write-Host "Complete CSV file: $csvPath" -ForegroundColor White
    Write-Host "Complete JSON file: $jsonPath" -ForegroundColor White
    Write-Host "Total items exported: $($exportData.Count)" -ForegroundColor White
    Write-Host "Pinned items: $(($exportData | Where-Object { $_.IsPinned -eq $true }).Count)" -ForegroundColor White
    Write-Host "Regular items: $(($exportData | Where-Object { $_.IsPinned -eq $false }).Count)" -ForegroundColor White
}
else {
    Write-Host "`nNo clipboard data found using any method." -ForegroundColor Red
    Write-Host "This could mean:" -ForegroundColor Yellow
    Write-Host "- Clipboard history is disabled" -ForegroundColor Yellow
    Write-Host "- No items in clipboard history" -ForegroundColor Yellow
    Write-Host "- Insufficient permissions" -ForegroundColor Yellow
}

# Display summary
Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "Activities Database: $(if ($activitiesData) { 'Found' } else { 'Not found' })" -ForegroundColor White
Write-Host "Current Clipboard: $(if ($currentClipboard) { 'Found' } else { 'Not found' })" -ForegroundColor White
Write-Host "Registry Settings: $(if ($clipboardSettings) { 'Found' } else { 'Not found' })" -ForegroundColor White
Write-Host "Roaming Files: $(if ($roamingData) { "$($roamingData.Count) files" } else { 'Not found' })" -ForegroundColor White
Write-Host "Pinned Items: $(if ($pinnedItems) { "$($pinnedItems.Count) items" } else { 'Not found' })" -ForegroundColor White
