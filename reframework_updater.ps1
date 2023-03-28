# Set API URL
$repoUrl = "https://api.github.com/repos/praydog/REFramework"
$apiUrl = "$repoUrl/actions/artifacts?per_page=100"
# Personal Access Token for GitHub API authentication
# Replace *** with your own token, which can be generated at https://github.com/settings/tokens (Generate new token > Personal access tokens (classic))
# It should be granted the "repo" scope (public_repo, repo:status, repo_deployment) for downloading artifacts from public repositories
$personalAccessToken = "****************************************"
# Headers
$headers = @{
    "Authorization" = "Bearer $personalAccessToken"
}

# Function to fetch the changelog between two commits
function Get-Changelog($base, $head) {
    try {
        $changelogApiUrl = "$repoUrl/compare/$base...$head"
        $changelogResponse = Invoke-WebRequest -Uri $changelogApiUrl -UseBasicParsing -Headers $headers
        $commits = ($changelogResponse | ConvertFrom-Json).commits
    }
    catch {
        Write-Host "Error: Failed to fetch the changelog from GitHub." -ForegroundColor Red
        exit 1
    }
    return $commits
}

# Function to download a file from a given URL and save it to the specified output path
function Download-File($url, $output) {
    try {
        Write-Host "Downloading file from $url..."
        Invoke-WebRequest -Uri $url -OutFile $output -Headers $headers
        Write-Host "Download successful!"
    }
    catch {
        Write-Host "Error: Failed to download the file." -ForegroundColor Red
        exit 1
    }
}

# Function to let the user select a game from the grouped artifacts
function Select-Game($artifacts) {
    $selectedIndex = 0
    $groupedArtifacts = $artifacts | Sort-Object -Property @{Expression = "workflow_run.head_branch"; Ascending = $true }, @{Expression = "name"; Ascending = $true } | Group-Object -Property { $_.name + "#" + $_.workflow_run.head_branch }
    $selected = $false
    $artifactNameAndBranch = ""

    while (-not $selected) {
        Clear-Host
        Write-Host "Select the game you want to update:" -ForegroundColor Cyan

        for ($i = 0; $i -lt $groupedArtifacts.Count; $i++) {
            $artifactNameAndBranch = $groupedArtifacts[$i].Name

            if ($i -eq $selectedIndex) {
                Write-Host "> $artifactNameAndBranch" -ForegroundColor Yellow
            }
            else {
                Write-Host "  $artifactNameAndBranch"
            }
        }

        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").VirtualKeyCode
        switch ($key) {
            40 { $selectedIndex++; if ($selectedIndex -ge $groupedArtifacts.Count) { $selectedIndex = 0 } } # Down arrow
            38 { $selectedIndex--; if ($selectedIndex -lt 0) { $selectedIndex = $groupedArtifacts.Count - 1 } } # Up arrow
            13 { $selected = $true } # Enter
        }
    }

    return $groupedArtifacts[$selectedIndex]
}

# Function to let the user select files and folders from a list of items
function Select-FilesAndFolders($items) {
    $selectedIndex = 0
    $selectedItems = @()
    
    while ($true) {
        Clear-Host
        Write-Host "Select files or folders to copy and overwrite (use arrow keys to navigate, space to select, and enter to confirm):" -ForegroundColor Cyan
        Write-Host "(Recommneded for DLSS Upscalar setup: dinput8.dll only)" -ForegroundColor Cyan
        
        for ($i = 0; $i -lt $items.Count; $i++) {
            $item = $items[$i]
            $isSelected = $selectedItems.Contains($i)
            
            if ($i -eq $selectedIndex) {
                if ($isSelected) {
                    Write-Host ">* $($item.Name)" -ForegroundColor Yellow
                }
                else {
                    Write-Host ">  $($item.Name)"
                }
            }
            else {
                if ($isSelected) {
                    Write-Host " * $($item.Name)" -ForegroundColor Yellow
                }
                else {
                    Write-Host "   $($item.Name)"
                }
            }
        }
        
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").VirtualKeyCode
        switch ($key) {
            40 { $selectedIndex++; if ($selectedIndex -ge $items.Count) { $selectedIndex = 0 } } # Down arrow
            38 { $selectedIndex--; if ($selectedIndex -lt 0) { $selectedIndex = $items.Count - 1 } } # Up arrow
            32 {
                # Space
                if ($selectedItems.Contains($selectedIndex)) {
                    $selectedItems = $selectedItems | Where-Object { $_ -ne $selectedIndex }
                }
                else {
                    $selectedItems += $selectedIndex
                }
            }
            13 { return $items[$selectedItems] } # Enter
        }
    }
}


# Function to check for updates and perform the update if necessary
function CheckAndUpdate($previousCommitHash, $commitHash) {
    # Compare commit hash
    if ($previousCommitHash -eq $commitHash) {
        # If the zip file exists, don't update
        Write-Host "No updates required. If you think this is an error, remove any zip files starting with .reframework" -ForegroundColor Green
    }
    else {
        # Else, download the file
        Write-Host "New version detected. Updating..." -ForegroundColor Yellow
        # Remove any previously downloaded .reframework zip files
        Get-ChildItem -Path . -Include .reframework*.zip | Remove-Item -Force
        Download-File -url $latestArtifact.archive_download_url -output $zipFile

        try {
            # Extract outer zip file
            Write-Host "Extracting $zipFile..."
            Expand-Archive -Path $zipFile -DestinationPath "$($ENV:Temp)/reframeworkUpdater/" -Force -Verbose:$true

            # Extract inner zip file
            # Assumes the inner zip file matches the artifact name
            $innerZipFile = "$($artifactName).zip"
            Write-Host "Extracting $innerZipFile..."
            Expand-Archive -LiteralPath "$($ENV:Temp)/reframeworkUpdater/$innerZipFile" -DestinationPath "$($ENV:Temp)/reframeworkUpdater/" -Force -Verbose:$true

            # Select files and folders to copy
            $innerZipPath = "$($ENV:Temp)/reframeworkUpdater/"
            $items = Get-ChildItem -Path $innerZipPath | Where-Object { $_.Name -ne $innerZipFile }
            $selectedItems = Select-FilesAndFolders -items $items

            if ($selectedItems.Count -gt 0) {
                Write-Host "Copying selected files and folders to the game directory..."
                foreach ($item in $selectedItems) {
                    $sourcePath = Join-Path -Path $innerZipPath -ChildPath $item.Name
                    $destinationPath = Join-Path -Path (Get-Location) -ChildPath $item.Name
                    if ($item -is [System.IO.DirectoryInfo]) {
                        Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force -Verbose
                    }
                    else {
                        Copy-Item -Path $sourcePath -Destination $destinationPath -Force -Verbose
                    }
                }
            }

            Write-Host "Update successful!" -ForegroundColor Green
        }
        catch {
            Write-Host "Error: Failed to extract and update the files." -ForegroundColor Red
            exit 1
        }
    }
}

# Get latest artifact
try {
    Write-Host "Fetching artifacts from GitHub API..."
    $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -Headers $headers
    $artifacts = ($response | ConvertFrom-Json).artifacts
    $artifacts = $artifacts | ForEach-Object {
        $artifact = $_
        $artifact | Add-Member -MemberType NoteProperty -Name "repo_branch" -Value $artifact.workflow_run.head_branch
        return $artifact
    }
}
catch {
    Write-Host "Error: Failed to fetch the artifacts from GitHub." -ForegroundColor Red
    exit 1
}

# Load or create configuration
$configFile = ".\reframework_updater.config"
if (Test-Path $configFile) {
    $artifactNameAndBranch = Get-Content $configFile
    Write-Output "Config file loaded: $artifactNameAndBranch"
}
else {
    Write-Output "No config file found. Selecting game..."
    $artifactNameAndBranch = (Select-Game -artifacts $artifacts).Name
    Write-Output "You selected $artifactNameAndBranch"
    Write-Output "Saving it to $configFile ..."
    Set-Content -Path $configFile -Value $artifactNameAndBranch
}

$artifactName, $branchName = $artifactNameAndBranch -split '#'
$latestArtifact = $artifacts | Where-Object { $_.name -eq $artifactName -and $_.repo_branch -eq $branchName } | Select-Object -First 1

if ($null -eq $latestArtifact) {
    Write-Host "Error: No artifacts found for the selected game: $artifactNameAndBranch." -ForegroundColor Red
    exit 1
}

# Get previous zip file if it exists. Then infer the commit hash.
$previousZipFile = Get-ChildItem -Path . -Filter .reframework_*.zip | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($previousZipFile) {
    $previousArtifactNameAndBranch = $previousZipFile.Name.Split("_")[1..2] -join "#"
    $previousCommitHash = $previousZipFile.Name.Split("_")[4].Replace(".zip", "")
    Write-Host "The current local version is from $previousArtifactNameAndBranch with commit hash $previousCommitHash." -ForegroundColor Yellow
}
else {
    Write-Host "No local version found." -ForegroundColor Red
}

# Determine the zip file path for the new commit hash
$timestamp = (Get-Date -Date $latestArtifact.updated_at).ToString("yyyyMMdd")
$commitHash = $latestArtifact.workflow_run.head_sha.substring(0, 7)
$zipFile = ".reframework_$($latestArtifact.name)_$($latestArtifact.workflow_run.head_branch)_$($timestamp)_$($commitHash).zip"
if ($zipFile) {
    $currentArtifactNameAndBranch = $zipFile.Split("_")[1..2] -join "#"
    $commitHash = $zipFile.Split("_")[4].Replace(".zip", "")
    Write-Host "The latest version is from $currentArtifactNameAndBranch with commit hash $commitHash released on $timestamp." -ForegroundColor Yellow
}

# Fetch and display changelog
if ($previousCommitHash -and $previousCommitHash -ne "") {
    if ($previousCommitHash -ne $commitHash) {
        Write-Host "Fetching changelog between commits $previousCommitHash and $commitHash..." -ForegroundColor Cyan
        $changelog = Get-Changelog -base $previousCommitHash -head $commitHash
        if ($changelog.Count -gt 0) {
            Write-Host "Changelog:" -ForegroundColor Green
            foreach ($commit in $changelog) {
                Write-Host "  - $($commit.commit.message) (Commit: $($commit.sha.substring(0, 7)), Author: $($commit.commit.author.name), Date: $($commit.commit.author.date))"
            }
        }
        else {
            Write-Host "No changes found between commits $previousCommitHash and $commitHash" -ForegroundColor Yellow
        }
        Write-Host "Press any key to continue..." -ForegroundColor White
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    else {
        Write-Host "No updates found, the local version is up to date with commit $previousCommitHash." -ForegroundColor Green
    }
}
else {
    Write-Host "No local version found, skipping changelog." -ForegroundColor Red
}

# Check for updates
CheckAndUpdate -previousCommitHash $previousCommitHash -commitHash $commitHash

# Wait for user input before closing
Write-Host "Press any key to exit..." -ForegroundColor White
$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
