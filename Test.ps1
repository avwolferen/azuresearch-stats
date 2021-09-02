if ($false) {
    Connect-AzAccount    
}

Get-AzContext -ListAvailable | Out-GridView -PassThru | Select-AzContext

.\Get-AzureSearchIndexes.ps1 -outputDirectory '.\'