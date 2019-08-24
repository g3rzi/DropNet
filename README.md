[![License][license-img]][license]

# Invoke-DropNet
Show all the TCP connections and allows you to close any network connection each time it is being established based on a given parameters.


![alt text](https://github.com/g3rzi/DropNet/blob/assets/Invoke-DropNet.gif)

## Requirements
Admin privileges to close the network connection. Otherwise it will also be able to show you the connections status.

## Basic Usage
-	Open PowerShell and run:
	- `Import-Module .\Invoke-Dropnet.ps1` or copy & paste KetshashInvoke-DropNet.ps1 content to PowerShell session
	- `Invoke-DropNet <arguments>`

## Invoke-DropNet
##### Parameters:
* __AutoClose__ - Will loop over the connections until exiting and close them. 
* __Milliseconds__ - How much time to wait before running again on all the connections (default: 300 milliseconds). 
* __ProcessID__ - Filter connections by PID of the process.  
* __LocalPort__ - Filter connections by PID of the process.
* __RemotePor__ - Filter connections by RemotePort.
* __LocalIPAddress__ - Filter connections by LocalIPAddress. 
* __RemoteIPAddress__ - Filter connections by RemoteIPAddress. 
* __State__ - Filter connections by State. 



##### Example:
```powershell
Invoke-DropNet -AutoClose -LocalPort 6666 -State "ESTABLISHED"
```


[license-img]: https://img.shields.io/github/license/g3rzi/DropNet.svg
[license]: https://github.com/g3rzi/DropNet/blob/master/LICENSE
