# Initialise environment and variables

## Add environment
Add-AzEnvironment -Name "AzureStackUser" -ArmEndpoint $ArmEndpoint

## Login
Connect-AzAccount -EnvironmentName "AzureStackUser"

# Get location of Azure Stack Hub
$Location = (Get-AzLocation).Location

# Input Variables
$RGName = "MyResourceGroup"
$VMName = "MyVM"

# Retrieve virtual machine details
$OldVM = Get-AzVM -ResourceGroupName $RGName -Name $VMName

# Remove the VM, keeping the disks
Write-Output -InputObject "Removing old virtual machine"
Remove-AzVM -Name $VMName -ResourceGroupName $RGName -Force

# Create OS managed disk
Write-Output -InputObject "Creating OS managed disk"
$OSDiskConfig = New-AzDiskConfig -AccountType "StandardLRS" -Location $Location -DiskSizeGB $OldVM.StorageProfile.OsDisk.DiskSizeGB `
    -SourceUri $OldVM.StorageProfile.OsDisk.Vhd.Uri -CreateOption "Import"
$OSDisk = New-AzDisk -DiskName "$($OldVM.Name)_$($OldVM.StorageProfile.OsDisk.Name)" -Disk $OSDiskConfig -ResourceGroupName $RGName

# Create data managed disks
if ($OldVM.StorageProfile.DataDisks) {
    $DataDiskArray = @()
    foreach ($DataDisk in $OldVM.StorageProfile.DataDisks) {
        Write-Output -InputObject "Creating data managed disk"
        $DataDiskConfig = New-AzDiskConfig -AccountType "StandardLRS" -Location $Location -DiskSizeGB $DataDisk.DiskSizeGB `
            -SourceUri $DataDisk.Vhd.Uri -CreateOption "Import"
        $DataDiskArray += New-AzDisk -DiskName "$($OldVM.Name)_$($DataDisk.Name)" -Disk $DataDiskConfig -ResourceGroupName $RGName
    }
}

# Create new virtual machine config
$NewVMConfig = New-AzVMConfig -VMName $VMName -VMSize $OldVM.HardwareProfile.VmSize

# Add OS disk to the new virtual machine config
if ($OldVM.OSProfile.LinuxConfiguration) {
    $NewVMConfig = Set-AzVMOSDisk -VM $NewVMConfig -ManagedDiskId $OSDisk.Id -CreateOption "Attach" -Linux
}
else {
    $NewVMConfig = Set-AzVMOSDisk -VM $NewVMConfig -ManagedDiskId $OSDisk.Id -CreateOption "Attach" -Windows
}

# Add data disk(s) to the new virtual machine config
$Lun = 0
foreach ($Disk in $DataDiskArray) {
    $NewVMConfig = Add-AzVMDataDisk -VM $NewVMConfig -ManagedDiskId $Disk.Id -CreateOption Attach -Lun $Lun -DiskSizeInGB $Disk.DiskSizeGB
    $Lun++
}

# Add network interface card(s) to the new virtual machine config
foreach ($Nic in $OldVM.NetworkProfile.NetworkInterfaces) {
    if ($Nic.Primary -eq $true -or $Nic.Primary -eq $null) {
        $NewVMConfig = Add-AzVMNetworkInterface -VM $NewVMConfig -Id $Nic.Id -Primary
    }
    else {
        $NewVMConfig = Add-AzVMNetworkInterface -VM $NewVMConfig -Id $Nic.Id
    }
}

# Create the new virtual machine
Write-Output -InputObject "Creating new virtual machine"
New-AzVM -VM $NewVMConfig -ResourceGroupName $RGName -Location $Location
Get-AzVM -ResourceGroupName $RGName -Name $VMName
Write-Output -InputObject "The virtual machine has been created successfully"
