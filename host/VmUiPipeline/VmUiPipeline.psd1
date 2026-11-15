@{
    RootModule        = 'VmUiPipeline.psm1'
    ModuleVersion     = '0.1.0'
    CompatiblePSEditions = @('Desktop', 'Core')
    GUID              = '29410136-c239-46d0-8892-0d56597ebc5e'
    Author            = 'VmUiPipeline contributors'
    CompanyName       = 'VmUiPipeline contributors'
    Copyright         = '(c) Files Community and VmUiPipeline contributors. MPL-2.0.'
    Description       = 'Run Windows desktop UI automation tests inside VM interactive sessions.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Import-VmUiPipelineConfig',
        'Invoke-VmUiPipeline',
        'New-VmUiPipelineSummary',
        'ConvertTo-VmUiPipelineJUnit',
        'Write-VmUiPipelineMarkdownReport'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('windows', 'ui-automation', 'vmware', 'winui', 'wpf', 'testing')
            ProjectUri = 'https://github.com/wangjiati/vm-ui-pipeline'
            LicenseUri = 'https://github.com/wangjiati/vm-ui-pipeline/blob/main/LICENSE'
        }
    }
}
