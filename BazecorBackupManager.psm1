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

function Save-DefyLayouts {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateScript({
            if ((Test-Path $_ -PathType Leaf) -and $_ -match '\.json$') {
                return $true
            } else {
                throw "The filename must exist and have a .json extension."
            }
        })]
        [string]$filename
    )

    # Extract the keyboard name from the filename
    $keyboardName = [System.IO.Path]::GetFileNameWithoutExtension($filename) -replace '.*-(.*)', '$1'

    # Check if jq is installed
    if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-Error "jq is not installed. Please install jq (e.g. using 'winget install jqlang.jq') and try again."
        return
    }

    # Helper function to extract data using jq
    function Get-JqData {
        param (
            [string]$filter
        )
        return & jq -r $filter $filename
    }

    # Extract and format keymap data
    Write-Output "Extracting and formatting keymap data..."
    $keymapData = Get-JqData '.backup[] | select(.command == \"keymap.custom\") | .data'
    $formattedKeymap = Format-DefyKeyMap -data $keymapData
    $keymapFile = "keymap-$keyboardName.txt"
    Write-Output "Writing keymap data to $keymapFile"
    $formattedKeymap | Out-File -FilePath $keymapFile -Encoding utf8

    # Extract and format colormap data
    Write-Output "Extracting and formatting colormap data..."
    $colormapData = Get-JqData '.backup[] | select(.command == \"colormap.map\") | .data'
    $formattedColormap = Format-DefyColorMap -data $colormapData
    $colormapFile = "colormap-$keyboardName.txt"
    Write-Output "Writing colormap data to $colormapFile"
    $formattedColormap | Out-File -FilePath $colormapFile -Encoding utf8

    # Extract and format palette data
    Write-Output "Extracting and formatting palette data..."
    $paletteData = Get-JqData '.backup[] | select(.command == \"palette\") | .data'
    $formattedPalette = Format-DefyPalette -data $paletteData
    $paletteFile = "palette-$keyboardName.txt"
    Write-Output "Writing palette data to $paletteFile"
    $formattedPalette | Out-File -FilePath $paletteFile -Encoding utf8

    # Add the files to git
    git add $keymapFile, $colormapFile, $paletteFile
}

function Sync-BazecorBackups {
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
			# Do some post-processing to extract the keymap/colormap/palette into a more readble format
			Save-DefyLayouts $newFileName

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

function Format-DefyKeyMap {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$data
    )

    # Split the data string into an array of integers
    $keys = $data -split ' ' | ForEach-Object { [int]$_ }

    # Initialize variables
    $layers = 10
    $rows = 5
    $cols = 16
    $maxLength = 5  # Maximum length of the integer codes (65535 has 5 digits)
    $spaceBetweenKeys = 1  # Space between keycodes
    $extraSpace = " " * (($maxLength + $spaceBetweenKeys) * 4)  # Four keycodes worth of space including spaces between keycodes
    $output = ""

    # Process each layer
    for ($layer = 0; $layer -lt $layers; $layer++) {
        if ($layer -gt 0) {
            $output += "`n"  # Add a blank line between layers
        }

        # Add header for the layer
        $layerHeader = "Layer $($layer + 1)"
        $output += $layerHeader + "`n"
        $output += "-" * $layerHeader.Length + "`n"

        # Process each row in the layer
        for ($row = 0; $row -lt $rows; $row++) {
            if ($row -lt 4) {
                $line = ""

                # Process each key in the row
                for ($col = 0; $col -lt $cols; $col++) {
                    $index = ($layer * $rows * $cols) + ($row * $cols) + $col
                    $key = $keys[$index]
                    if ($col -eq 8) {
                        $line += " " * $maxLength  # Add extra space between the two halves
                    }
                    $line += "{0,${maxLength}} " -f $key
                }

                $output += $line.TrimEnd() + "`n"
            } else {
                # Special handling for the last row
                $leftSubrow1 = $extraSpace
                $leftSubrow2 = ""
                $rightSubrow1 = ""
                $rightSubrow2 = ""

                for ($col = 0; $col -lt 8; $col++) {
                    $index = ($layer * $rows * $cols) + ($row * $cols) + $col
                    $key = $keys[$index]
                    if ($col -lt 4) {
                        $leftSubrow1 += "{0,${maxLength}} " -f $key
                    } else {
                        $leftSubrow2 = "{0,${maxLength}} " -f $key + $leftSubrow2
                    }
                }

                $leftSubrow2 = $extraSpace + $leftSubrow2  # Add extra space after constructing the second left subrow

                for ($col = 8; $col -lt 16; $col++) {
                    $index = ($layer * $rows * $cols) + ($row * $cols) + $col
                    $key = $keys[$index]
                    if ($col -lt 12) {
                        $rightSubrow2 = "{0,${maxLength}} " -f $key + $rightSubrow2
                    } else {
                        $rightSubrow1 += "{0,${maxLength}} " -f $key
                    }
                }

                $output += $leftSubrow1.TrimEnd() + " " * ($maxLength + $spaceBetweenKeys) + $rightSubrow1.TrimEnd() + "`n"
                $output += $leftSubrow2.TrimEnd() + " " * ($maxLength + $spaceBetweenKeys) + $rightSubrow2.TrimEnd() + "`n"
            }
        }
    }

    return $output.TrimEnd()
}

<#
Here's the layout for the colormap (a bit messy, but it works)
        XX XX XX                                              YY YY YY
      XX       XX XX                                      YY YY       YY
 XX XX             XX XX XX XX                  YY YY YY YY             YY YY
XX  JJ  JJ JJ JJ JJ JJ   JJ  XX XX          YY YY  KK   KK KK KK KK KK  KK  YY
XX  JJ  JJ JJ JJ JJ JJ   JJ      XX        YY      KK   KK KK KK KK KK  KK  YY
XX  JJ  JJ JJ JJ JJ JJ   JJ      XX        YY      KK   KK KK KK KK KK  KK  YY
XX  JJ  JJ JJ JJ JJ JJ           XX        YY           KK KK KK KK KK  KK  YY
XX                JJ JJ JJ JJ    XX        YY    KK KK KK KK                YY
XX                JJ JJ JJ JJ      XX    YY      KK KK KK KK                YY
XX                             XX            YY                             YY
XX                             XX            YY                             YY
XX                             XX            YY                             YY
XX                             XX            YY                             YY
XX                             XX            YY                             YY
XX                             XX            YY                             YY
XX                             XX            YY                             YY
XX                             XX            YY                             YY
XX                             XX            YY                             YY
 XX XX XX XX XX XX XX XX XX XX                YY YY YY YY YY YY YY YY YY YY
#>

function Format-DefyColorMap {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory=$true)]
		[string]$data
	)

	# Split the data string into an array of integers
	$colorIndices = $data -split ' ' | ForEach-Object { [int]$_ }

	# Initialize variables
    $layers = 10
	$numKeysPerSide = 35
	$numUnderglowPerSide = 53
	$overallIndex = 0
    $output = ""

	# Define the layout
	$layout = @"
        X24X X23X X22X                                              Y24Y Y23Y Y22Y
      X25X       X21X X20X                                      Y20Y Y21Y       Y25Y
 X27X X26X             X19X X18X X17X X16X                  Y16Y Y17Y Y18Y Y19Y             Y26Y Y27Y
X28X  J0J  J1J J2J J3J J4J J5J   J6J  X15X X14X          Y14Y Y15Y  K6K   K5K K4K K3K K2K K1K  K0K  Y28Y
X29X  J7J  J8J J9J J10J J11J J12J   J13J      X13X        Y13Y      K13K   K12K K11K K10K K9K K8K  K7K  Y29Y
X30X  J14J  J15J J16J J17J J18J J19J   J20J      X12X        Y12Y      K20K   K19K K18K K17K K16K K15K  K14K  Y30Y
X31X  J21J  J22J J23J J24J J25J J26J           X11X        Y11Y           K26K K25K K24K K23K K22K  K21K  Y31Y
X32X                J27J J28J J29J J30J    X10X        Y10Y    K30K K29K K28K K27K                Y32Y
X33X                J34J J33J J32J J31J      X9X    Y9Y      K31K K32K K33K K34K                Y33Y
X34X                             X8X            Y8Y                             Y34Y
X35X                             X7X            Y7Y                             Y35Y
X36X                             X6X            Y6Y                             Y36Y
X37X                             X5X            Y5Y                             Y37Y
X38X                             X4X            Y4Y                             Y38Y
X39X                             X3X            Y3Y                             Y39Y
X40X                             X2X            Y2Y                             Y40Y
X41X                             X1X            Y1Y                             Y41Y
X42X                             X0X            Y0Y                             Y42Y
 X43X X44X X45X X46X X47X X48X X49X X50X X51X X52X                Y52Y Y51Y Y50Y Y49Y Y48Y Y47Y Y46Y Y45Y Y44Y Y43Y
"@

    # Process each layer
    for ($layer = 0; $layer -lt $layers; $layer++) {
        if ($layer -gt 0) {
            $output += "`n"  # Add a blank line between layers
        }

        # Add header for the layer
        $layerHeader = "Layer $($layer + 1)"
        $output += $layerHeader + "`n"
        $output += "-" * $layerHeader.Length + "`n"

		# Make a copy of the layout
		$currentLayout = $layout

		# Left side keys
		for ($i = 0; $i -lt $numKeysPerSide; $i++) {
			$placeholder = "J${i}J"
			$replacement = "{0,2}" -f $colorIndices[$overallIndex]
			$currentLayout = $currentLayout -replace $placeholder, $replacement
			$overallIndex++
		}

		# Right side keys
		for ($i = 0; $i -lt $numKeysPerSide; $i++) {
			$placeholder = "K${i}K"
			$replacement = "{0,2}" -f $colorIndices[$overallIndex]
			$currentLayout = $currentLayout -replace $placeholder, $replacement
			$overallIndex++
		}

		# Left side underglow
		for ($i = 0; $i -lt $numUnderglowPerSide; $i++) {
			$placeholder = "X${i}X"
			$replacement = "{0,2}" -f $colorIndices[$overallIndex]
			$currentLayout = $currentLayout -replace $placeholder, $replacement
			$overallIndex++
		}

		# Right side underglow
		for ($i = 0; $i -lt $numUnderglowPerSide; $i++) {
			$placeholder = "Y${i}Y"
			$replacement = "{0,2}" -f $colorIndices[$overallIndex]
			$currentLayout = $currentLayout -replace $placeholder, $replacement
			$overallIndex++
		}

		$output += $currentLayout + "`n"
		$output += "`n" + "{0,2}" -f $colorIndices[$overallIndex] + " " + "{0,2}" -f $colorIndices[$overallIndex + 1]+ "`n"
		$overallIndex += 2
	}

    return $output.TrimEnd()
}

function Format-DefyPalette {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$data
    )

    # Split the input data into an array of color values
    $colors = $data -split ' '

    # Check if the number of color values is correct
    if ($colors.Count -ne 64) {
        Write-Error "The input data must contain exactly 64 values (16 colors in RGBW format)."
        return
    }

    # Initialize an empty string to hold the result
    $result = ""

    # Iterate over each color and format the output
    for ($i = 0; $i -lt 16; $i++) {
        $index = $i * 4
        $r = [int]$colors[$index]
        $g = [int]$colors[$index + 1]
        $b = [int]$colors[$index + 2]
        $w = [int]$colors[$index + 3]

        # Convert RGBW to RGB
        $r = [math]::Min($r + $w, 255)
        $g = [math]::Min($g + $w, 255)
        $b = [math]::Min($b + $w, 255)

        # Create the header and dashed line
        $header = "Index $i"
        $dashes = "-" * $header.Length

        # Append the formatted color information to the result string
        $result += "$header`n$dashes`nR: $r, G: $g, B: $b`n`n"
    }

    # Return the result string
    return $result
}
