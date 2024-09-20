# My Keyboard Layouts
I recently got my first programmable split ergonomic mechanical keyboard (a [Dygma Defy](https://dygma.com/dygma-defy)) and I wanted to keep track of all the changes I've made to the layers and the config and things. I made a PowerShell module with a helper function that uses `jq` to remove the neuron ID from a few different places in the backup json files. The full backup files are a bit harder to read, and so I think I'll at least periodically export the layers individually from Bazecor so that I can see things better. I might find a way to convert the backup files into a more readable format, but for now I just want to get things tracked.
To use the helper cmdlet in PowerShell:
1. `winget install jqlang.jq` (unless `jq` is already installed)
1. `Remove-NeuronIdFromBackupJson "path/to/input.json" "path/to/output.json"`
