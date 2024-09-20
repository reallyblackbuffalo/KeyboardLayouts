function Remove-NeuronIdFromBackupJson {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory=$true)]
		[ValidateScript({
			if ((Test-Path $_ -PathType Leaf) -and $_ -match '\.json$') {
				$true
			} else {
				throw "InputFile must exist and have a .json extension."
			}
		})]
		[string]$InputFile,

		[Parameter(Mandatory=$true)]
		[ValidateScript({
			$parentDir = Split-Path $_ -Parent
			if (($parentDir -eq $null -or $parentDir -eq "") -or (Test-Path $parentDir -PathType Container)) {
				if ($_ -match '\.json$') {
					$true
				} else {
					throw "OutputFile must have a .json extension."
				}
			} else {
				throw "OutputFile's directory must exist."
			}
		})]
		[string]$OutputFile
	)

	if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
		Write-Error "jq is not installed. Please install jq (e.g. using 'winget install jqlang.jq') and try again."
		exit 1
	}

	Write-Output "Removing neuron ID from $InputFile and saving to $OutputFile"
	$jqFilter = 'del(.neuronID) | del(.neuron.id) | del(.neuron.device.chipId)'
	& jq $jqFilter $InputFile | Out-File $OutputFile -Encoding utf8
}

function Copy-BazecorBackups {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateScript({ Test-Path $_ -PathType Container })]
		[string]$BackupsPath,

		[Parameter(Mandatory = $false)]
		[datetime]$LastBackupDate
	)

	# Get all .json files in the Backups directory, sorted by name (oldest first)
	$files = Get-ChildItem -Path $BackupsPath -Filter *.json -File | Sort-Object Name

	# Loop through each file
	foreach ($file in $files) {
		# Extract the timestamp from the file name
		$timestamp = $file.Name -replace '^(.*?)\-.*$', '$1'

		# Convert the timestamp to a datetime object
		$fileDate = [datetime]::ParseExact($timestamp, "yyyyMMddHHmmss", $null)

		# Skip files with a timestamp on or before the last backup date if provided
		if ($LastBackupDate -and $fileDate -le $LastBackupDate) {
			continue
		}

		# Extract the rest of the filename
		$keyboardName = $file.Name -replace '^[0-9]{14}\-(.*)\.json$', '$1'

		# Define the new filename with the .json extension
		$newFileName = "fullBackup-$keyboardName.json"

		# Call the Remove-NeuronIdFromBackupJson cmdlet
		Remove-NeuronIdFromBackupJson -InputFile $file.FullName -OutputFile $newFileName

		# Check if there are any changes to commit
		if (git status --porcelain | Select-String $newFileName) {
			# Format the timestamp to a more human-readable format
			$formattedTimestamp = $fileDate.ToString("yyyy-MM-dd HH:mm:ss")

			# Add the file to the Git staging area
			git add $newFileName

			# Commit the file
			git commit -m "Backup of $keyboardName layout exported by Bazecor on $formattedTimestamp"
		} else {
			Write-Output "No changes to commit for $file.Name"
		}
	}
}
