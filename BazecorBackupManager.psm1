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
	& jq $jqFilter $InputFile > $OutputFile
}
