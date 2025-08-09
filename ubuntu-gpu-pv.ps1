$vmobject = Get-VM | Out-GridView -Title "Select VM to setup GPU-P" -OutputMode Single
$vmName = $vmobject.Name

# region choose gpu
$dev = Get-PnpDevice -Class Display -Status OK | Out-GridView -Title "Select Card to setup GPU-P" -OutputMode Single

$props = $dev | Get-PnpDeviceProperty
$pnpinf = ($props | where { $_.KeyName -eq "DEVPKEY_Device_DriverInfPath" }).Data
$infsection = ($props | where { $_.KeyName -eq "DEVPKEY_Device_DriverInfSection" }).Data
$cbsinf = (Get-WindowsDriver -Online | where { $_.Driver -eq "$pnpinf" }).OriginalFileName
If (-not $cbsinf) {
	Write-Host "Device not supported: $dev, inf: $pnpinf, cbs: $cbsinf"
	return;
}

$gpuName = $dev.FriendlyName
$path = $dev.InstanceId.replace('\', '#').ToLower()
$pvs = Get-VMHostPartitionableGpu
$targetGpu = $null
foreach ($pv in $pvs) {
	$name = $pv.Name.ToLower()
	echo "$name"
	if ($name.contains($path)) {
		$targetGpu = $pv
		$path = $pv.Name
	}
}

echo "============================"
echo "Using: $gpuName, pnpinf: $pnpinf, path: $path"
echo "============================"
# endregion choose gpu

# region setup GPU-PV
Write-Host "Stopping VM"
$vmobject | Stop-VM

Write-Host "Configuring GPU-PV for VM"
$vmobject | Remove-VMGpuPartitionAdapter
$vmobject | Add-VMGpuPartitionAdapter -InstancePath "$path"
$vmobject | Set-VMGpuPartitionAdapter  `
	-MinPartitionVRAM $targetGpu.MinPartitionVRAM `
	-MaxPartitionVRAM $targetGpu.MaxPartitionVRAM `
	-OptimalPartitionVRAM $targetGpu.OptimalPartitionVRAM `
	-MinPartitionEncode $targetGpu.MinPartitionEncode `
	-MaxPartitionEncode $targetGpu.MaxPartitionEncode `
	-OptimalPartitionEncode $targetGpu.OptimalPartitionEncode `
	-MinPartitionDecode $targetGpu.MinPartitionDecode `
	-MaxPartitionDecode $targetGpu.MaxPartitionDecode `
	-OptimalPartitionDecode $targetGpu.OptimalPartitionDecode `
	-MinPartitionCompute $targetGpu.MinPartitionCompute `
	-MaxPartitionCompute $targetGpu.MaxPartitionCompute `
	-OptimalPartitionCompute $targetGpu.OptimalPartitionCompute
$vmobject | Set-VM -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1Gb -HighMemoryMappedIoSpace 32GB
# endregion setup GPU-PV


Start-VM $vmName
Start-Sleep -m 10000

$vmIpAddr = Read-Host "Input the vm IP address, should be reachable within WSL" 
$userName = Read-Host "Input vm admin user name, should have sudoers group" 
$remoteAddr = "$userName@$vmIpAddr"

echo ""
echo "Onclick GPU-PV for Ubuntu: using $remoteAddr"
echo "------------------------"


#Copy public key to remote to enable ssh login password free
wsl ssh $remoteAddr -T "mkdir -p ~/.ssh;touch ~/.ssh/authorized_keys"
wsl bash -c "cat ~/.ssh/id_rsa.pub | ssh $remoteAddr -T 'cat >> ~/.ssh/authorized_keys'"

#Copy drivers
wsl ssh $remoteAddr "sudo -S mkdir -p $(echo /usr/lib/wsl/drivers/)"
wsl scp -r /usr/lib/wsl/lib $remoteAddr\:~
wsl scp -r /usr/lib/wsl/drivers $remoteAddr\:~
wsl ssh $remoteAddr "sudo -S mv ~/lib/* /usr/lib;sudo -S ln -s /lib/libd3d12core.so /lib/libD3D12Core.so;sudo -S mv ~/drivers/* /usr/lib/wsl/drivers"


#Install dxgknrl module
wsl scp -r ./dxgkrnl.sh $remoteAddr\:~
wsl ssh $remoteAddr "chmod +x ~/dxgkrnl.sh;sudo -S ~/dxgkrnl.sh"

echo "ALL DONE, ENJOY"
