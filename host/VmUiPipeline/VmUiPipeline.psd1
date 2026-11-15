@{
    RootModule        = 'VmUiPipeline.psm1'
    ModuleVersion     = '0.1.4'
    CompatiblePSEditions = @('Desktop', 'Core')
    GUID              = '29410136-c239-46d0-8892-0d56597ebc5e'
    Author            = 'VmUiPipeline 贡献者'
    CompanyName       = 'VmUiPipeline 贡献者'
    Copyright         = '(c) Files Community 与 VmUiPipeline 贡献者。MPL-2.0。'
    Description       = '在虚拟机交互式会话中运行 Windows 桌面 UI 自动化测试。'
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
