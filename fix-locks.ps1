# Run this if terragrunt destroy crashes and leaves a stuck state lock
# Usage: .\fix-locks.ps1 <lock-id>
# The lock ID is shown in the error message when destroy fails
#
# Example:
#   .\fix-locks.ps1 97825a7e-5f01-1a17-f67e-af9c35b281e8

param(
    [Parameter(Mandatory=$true)]
    [string]$LockId
)

$modules = @("vpc", "eks", "rds", "sqs", "s3", "iam", "addons")

foreach ($module in $modules) {
    $path = "infra/environments/dev/$module"
    if (Test-Path $path) {
        Write-Host "Trying to unlock $module..." -ForegroundColor Cyan
        Push-Location $path
        terragrunt force-unlock -force $LockId 2>$null
        Pop-Location
    }
}

Write-Host "Done - you can now run destroy again." -ForegroundColor Green
