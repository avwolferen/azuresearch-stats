#Requires -Module Az.Search

[CmdletBinding(SupportsShouldProcess = $true)]
param (

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]]$resourceGroupName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]]$outputDirectory
)

$azContext = Get-AzContext
$allIndexStatistics = @()

$dateStr = '{0:yyyyMMdd}' -f $Date

if ($resourceGroupName) {
    $resourceGroups = @($resourceGroupName);
    $resultFileName = Join-Path $outputDirectory "AzureSearchStatistics-$dateStr-$resourceGroupName.csv"
}
else {
    #$resourceGroups = (Get-AzResourceGroup -Location 'West Europe' | Where-Object { $_.Tags.Platform -eq 'Sitecore' }).ResourceGroupName;
    $resourceGroups = (Get-AzResourceGroup).ResourceGroupName;
    $resultFileName = Join-Path $outputDirectory "AzureSearchStatistics-$dateStr-$($azContext.Subscription.Name).csv"
}

foreach ($resourceGroup in $resourceGroups) {   
    Write-Output "Processing $resourceGroup"

    $azureSearches = Get-AzResource -ResourceGroupName $resourceGroup | Where-Object { $_.ResourceType -eq 'microsoft.search/searchservices' }    

    if (!$azureSearches) {
        Write-Output "$resourceGroup does not contain Azure Search"
        continue        
    }

    foreach ($azureSearch in $azureSearches) {
        Write-Output "  Processing $($azureSearch.Name)"
        $adminKeys = Get-AzSearchAdminKeyPair          -ResourceGroupName $resourceGroup -ServiceName $azureSearch.Name

        $azureSearchApiUriTemplate = "https://$($azureSearch.Name).search.windows.net/action?api-version=2020-06-30"
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("api-key", $adminKeys.Primary)

        try {
            $response = Invoke-WebRequest -Uri $azureSearchApiUriTemplate.Replace("action", "indexes") -UseBasicParsing -Headers $headers -Method 'get'
            $indexes = $response | ConvertFrom-Json
        }
        catch {
            write-error $_.Exception.Message
        }

        foreach ($index in $indexes.value) {
            $indexName = $index.name
            $indexFields = $index.fields
            $indexStatistics = $null;

            Write-Output "    Getting statistics for $indexName"

            try {
                $response = Invoke-WebRequest -Uri $azureSearchApiUriTemplate.Replace("action", "indexes/$indexName/stats") -UseBasicParsing -Headers $headers -Method 'get'
                $indexStatistics = $response | ConvertFrom-Json
            }
            catch {
                Write-Error $_.Exception.Message
            }

            if ($indexStatistics) {
                $allIndexStatistics += 
                ([PSCustomObject]@{
                        resourceGroup = $resourceGroup
                        indexName     = $indexName
                        fieldCount    = $indexFields.Length
                        documentCount = $indexStatistics.documentCount
                        storageSize   = $indexStatistics.storageSize
                    })
            }
        }    
    }
}

$allIndexStatistics | Format-Table
if ($outputDirectory) {
    $allIndexStatistics | Export-Csv -Path $resultFileName -NoTypeInformation
}