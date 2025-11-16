
class ObjectHelpers {

    # --------- Convert object to hashtable----------
    [object]ConvertToHashtable([object]$inputObject) {
        if ($null -eq $inputObject) { return $null }

        # If it's a dictionary, process it as a hashtable
        if ($inputObject -is [System.Collections.IDictionary]) {
            $output = @{}
            foreach ($key in $inputObject.Keys) {
                $output[$key] = $this.ConvertToHashtable($inputObject[$key])
            }
            return $output
        }

        # If it's an array or collection (BUT NOT a string)
        if ($inputObject -is [System.Collections.IEnumerable] -and -not ($inputObject -is [string])) { return $inputObject }

        #If it's a PSObject or PSCustomObject - convert it to a hashtable
        if ($inputObject -is [psobject]) {
            $output = @{}
            foreach ($property in $inputObject.PSObject.Properties) {
                if ($property.IsGettable) {
                    try {
                        $output[$property.Name] = $this.ConvertToHashtable($property.Value)
                    }
                    catch {
                        $output[$property.Name] = $null
                    }
                }
            }
            return $output
        }

        # Otherwise, return the object as-is
        return $inputObject
    }
}