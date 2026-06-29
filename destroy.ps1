# snaPDF - Safe Destroy Script
# Run this instead of running terragrunt destroy directly

Write-Host "=== Step 1: Connect kubectl to dev cluster ===" -ForegroundColor Cyan
aws eks update-kubeconfig --region us-east-1 --name snapdf-dev
if ($LASTEXITCODE -ne 0) {
    Write-Host "Could not connect to cluster - it may already be destroyed. Skipping kubectl steps." -ForegroundColor Yellow
} else {
    Write-Host "=== Step 2: Delete Kubernetes services and ingresses ===" -ForegroundColor Cyan
    Write-Host "    (These create real AWS load balancers that must be gone before VPC can be deleted)"
    kubectl delete svc --all -n dev 2>$null
    kubectl delete ingress --all -n dev 2>$null
    kubectl delete svc --all -n staging 2>$null
    kubectl delete ingress --all -n staging 2>$null
}

Write-Host "=== Step 3: Get VPC ID ===" -ForegroundColor Cyan
$VPC_ID = aws ec2 describe-vpcs --filters "Name=tag:Name,Values=snapdf-dev-vpc" --query "Vpcs[0].VpcId" --output text
if ($VPC_ID -eq "None" -or $VPC_ID -eq "") {
    Write-Host "VPC not found - may already be destroyed. Skipping ENI cleanup." -ForegroundColor Yellow
} else {
    Write-Host "    VPC ID: $VPC_ID"

    Write-Host "=== Step 4: Wait for AWS load balancers to be deleted ===" -ForegroundColor Cyan
    $maxAttempts = 12
    $attempt = 0
    do {
        $lbCount = aws elbv2 describe-load-balancers --query "length(LoadBalancers[?VpcId=='$VPC_ID'])" --output text
        if ($lbCount -ne "0") {
            Write-Host "    $lbCount load balancer(s) still exist, waiting 15s..."
            Start-Sleep -Seconds 15
        }
        $attempt++
    } while ($lbCount -ne "0" -and $attempt -lt $maxAttempts)

    Write-Host "=== Step 5: Delete orphaned network interfaces (ENIs) in the VPC ===" -ForegroundColor Cyan
    Write-Host "    (EKS and ALB leave behind ENIs that block subnet deletion)"
    $enis = aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" --query "NetworkInterfaces[*].NetworkInterfaceId" --output json | ConvertFrom-Json
    if ($enis.Count -eq 0) {
        Write-Host "    No orphaned ENIs found."
    } else {
        foreach ($eni in $enis) {
            Write-Host "    Deleting ENI: $eni"
            aws ec2 delete-network-interface --network-interface-id $eni
        }
    }
}

Write-Host "=== Step 6: Destroy all infrastructure ===" -ForegroundColor Cyan
Set-Location infra/environments/dev
terragrunt run-all destroy

Write-Host "=== Done ===" -ForegroundColor Green
