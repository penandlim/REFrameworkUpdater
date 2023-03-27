# Set API URL
$apiUrl = "https://api.github.com/repos/praydog/REFramework/actions/artifacts?per_page=100"


# Function to download a file
function Download-File($url, $output) {
    try {
        Write-Host "Downloading file from $url..."
        Invoke-WebRequest -Uri $url -OutFile $output
        Write-Host "Download successful!"
    }
    catch {
        Write-Host "Error: Failed to download the file." -ForegroundColor Red
        exit 1
    }
}

# Function to get user selection.
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



# Get latest artifact
try {
    Write-Host "Fetching artifacts from GitHub API..."
    $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing
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
$timestamp = $latestArtifact.updated_at.Split("T")[0].Replace("-", "")
$commitHash = $latestArtifact.workflow_run.head_sha.substring(0, 7)
$zipFile = ".reframework_$($latestArtifact.name)_$($latestArtifact.workflow_run.head_branch)_$($timestamp)_$($commitHash).zip"
if ($zipFile) {
    $currentArtifactNameAndBranch = $zipFile.Split("_")[1..2] -join "#"
    $commitHash = $zipFile.Split("_")[4].Replace(".zip", "")
    Write-Host "The latest version is from $currentArtifactNameAndBranch with commit hash $commitHash." -ForegroundColor Yellow
}

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
        Expand-Archive -Path $zipFile -DestinationPath . -Force
        Write-Host "Update successful!" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Failed to extract and update the files." -ForegroundColor Red
        exit 1
    }
}

# Wait for user input before closing
Write-Host "Press any key to exit..." -ForegroundColor White
$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
