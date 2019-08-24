function Invoke-DropNet() { 
<#
    .SYNOPSIS
	    Terminates network connections (TCP) automatically.

	    Author: Eviatar Gerzi (@g3rzi)
		License: Free
		Required Dependencies: None
		Optional Dependencies: None
			
		Version 1.0: 23.08.2019

    .DESCRIPTION
        Show all the TCP connections and allows you to use it 
        to close any network connection each time it is being established.

        Reuirements: For closing the connection you need have admin privileges

    .PARAMETER PID
        Filter connections by PID of the process

    .PARAMETER LocalPort
        Filter connections by LocalPort

    .PARAMETER RemotePort
        Filter connections by RemotePort

    .PARAMETER LocalIPAddress
        Filter connections by LocalIPAddress

    .PARAMETER RemoteIPAddress
        Filter connections by RemoteIPAddress

    .PARAMETER State
        Filter connections by State

    .PARAMETER AutoClose
        Will loop over the connections until exiting and close them

    .PARAMETER Milliseconds
        How much time to wait before running again on all the connections (default: 300 milliseconds)

    .EXAMPLE
        # Closing any network connection with local port 6666 and state "ESTABLISHED"
        Invoke-DropNet -AutoClose -LocalPort 6666 -State "ESTABLISHED"
#>

    [CmdletBinding()]
	param
	(
        [int]$ProcessID = $null,
	[int]$LocalPort = $null,
        [int]$RemotePort = $null,
        [string]$LocalIPAddress = $null,
        [string]$RemoteIPAddress = $null,
        [string]$State,
	[switch]$AutoClose,
        [int]$Milliseconds = 300,
        [switch]$GetConnections
	)

    if($State){
        $State = $State.ToUpper()
    }

    $code = @"
    using System;
    using System.Collections;
    using System.Collections.Generic;
    using System.Net.Sockets;
    using System.Runtime.InteropServices;
    using System.Text;

    namespace ConnectionKiller
    {
        public class Program
        {
            // Taken from https://github.com/yromen/repository/tree/master/DNProcessKiller
            // It part from the Disconnecter class. 
            // In case of nested class use "+" like that [ConnectionKiller.Program+Disconnecter]::Connections()

            /// <summary> 
            /// Enumeration of the states 
            /// </summary> 
            public enum State
            {
                /// <summary> All </summary> 
                All = 0,
                /// <summary> Closed </summary> 
                Closed = 1,
                /// <summary> Listen </summary> 
                Listen = 2,
                /// <summary> Syn_Sent </summary> 
                Syn_Sent = 3,
                /// <summary> Syn_Rcvd </summary> 
                Syn_Rcvd = 4,
                /// <summary> Established </summary> 
                Established = 5,
                /// <summary> Fin_Wait1 </summary> 
                Fin_Wait1 = 6,
                /// <summary> Fin_Wait2 </summary> 
                Fin_Wait2 = 7,
                /// <summary> Close_Wait </summary> 
                Close_Wait = 8,
                /// <summary> Closing </summary> 
                Closing = 9,
                /// <summary> Last_Ack </summary> 
                Last_Ack = 10,
                /// <summary> Time_Wait </summary> 
                Time_Wait = 11,
                /// <summary> Delete_TCB </summary> 
                Delete_TCB = 12
            }

            /// <summary> 
            /// Connection info 
            /// </summary> 
            private struct MIB_TCPROW
            {
                public int dwState;
                public int dwLocalAddr;
                public int dwLocalPort;
                public int dwRemoteAddr;
                public int dwRemotePort;
            }

            //API to change status of connection 
            [DllImport("iphlpapi.dll")]
            //private static extern int SetTcpEntry(MIB_TCPROW tcprow); 
            private static extern int SetTcpEntry(IntPtr pTcprow);

            //Convert 16-bit value from network to host byte order 
            [DllImport("wsock32.dll")]
            private static extern int ntohs(int netshort);

            //Convert 16-bit value back again 
            [DllImport("wsock32.dll")]
            private static extern int htons(int netshort);

            /// <summary> 
            /// Close a connection by returning the connectionstring 
            /// </summary> 
            /// <param name="connectionstring"></param> 
            public static void CloseConnection(string localAddress, int localPort, string remoteAddress, int remotePort)
            {
                try
                {
                    //if (parts.Length != 4) throw new Exception("Invalid connectionstring - use the one provided by Connections.");
                    string[] locaddr = localAddress.Split('.');
                    string[] remaddr = remoteAddress.Split('.');

                    //Fill structure with data 
                    MIB_TCPROW row = new MIB_TCPROW();
                    row.dwState = 12;
                    byte[] bLocAddr = new byte[] { byte.Parse(locaddr[0]), byte.Parse(locaddr[1]), byte.Parse(locaddr[2]), byte.Parse(locaddr[3]) };
                    byte[] bRemAddr = new byte[] { byte.Parse(remaddr[0]), byte.Parse(remaddr[1]), byte.Parse(remaddr[2]), byte.Parse(remaddr[3]) };
                    row.dwLocalAddr = BitConverter.ToInt32(bLocAddr, 0);
                    row.dwRemoteAddr = BitConverter.ToInt32(bRemAddr, 0);
                    row.dwLocalPort = htons(localPort);
                    row.dwRemotePort = htons(remotePort);

                    //Make copy of the structure into memory and use the pointer to call SetTcpEntry 
                    IntPtr ptr = GetPtrToNewObject(row);
                    int ret = SetTcpEntry(ptr);

                    if (ret == -1) throw new Exception("Unsuccessful");
                    if (ret == 65) throw new Exception("User has no sufficient privilege to execute this API successfully");
                    if (ret == 87) throw new Exception("Specified port is not in state to be closed down");
                    if (ret == 317) throw new Exception("The function is unable to set the TCP entry since the application is running non-elevated");
                    if (ret != 0) throw new Exception("Unknown error (" + ret + ")");

                }
                catch (Exception ex)
                {
                    throw new Exception("CloseConnection failed (" + localAddress + ":" + localPort + "->" +  remoteAddress + ":" + remotePort + ")! [" + ex.GetType().ToString() + "," + ex.Message + "]");
                }
            }

            private static IntPtr GetPtrToNewObject(object obj)
            {
                IntPtr ptr = Marshal.AllocCoTaskMem(Marshal.SizeOf(obj));
                Marshal.StructureToPtr(obj, ptr, false);
                return ptr;
            }
        }
    }

"@


    $location = [PsObject].Assembly.Location
    $compileParams = New-Object System.CodeDom.Compiler.CompilerParameters
    $assemblyRange = @("System.dll", $location)
    $compileParams.ReferencedAssemblies.AddRange($assemblyRange)
    $compileParams.GenerateInMemory = $True
    Add-Type -TypeDefinition $code -CompilerParameters $compileParams -passthru -Language CSharp | Out-Null

    $connections = Get-NetTCPConnection

    function Close-Connection($connection){
        
        [ConnectionKiller.Program]::CloseConnection($connection.LocalAddress, $connection.LocalPort, $connection.RemoteAddress, $connection.RemotePort)
    }

    function Find-Connections($Connections, [int]$LocalPort, [int]$RemotePort, [string]$LocalIPAddress, [string]$RemoteIPAddress, [string]$State, [int]$ProcessID){
        
        $filteredConnections = $Connections
        if(($ProcessID -ne $null) -and ($ProcessID -ne "")){
            $filteredConnections = $filteredConnections | Where-Object {$_.OwningProcess -eq $ProcessID}
        }
        if(($LocalPort -ne $null) -and ($LocalPort -ne "")){
            $filteredConnections = $filteredConnections | Where-Object {$_.LocalPort -eq $LocalPort}
        }
        if(($RemotePort -ne $null) -and ($RemotePort -ne "")){
            $filteredConnections = $filteredConnections | Where-Object {$_.RemotePort -eq $RemotePort}
        }
        if(($LocalIPAddress -ne $null) -and ($LocalIPAddress -ne "")){
            $filteredConnections = $filteredConnections | Where-Object {$_.LocalIPAddress -eq $LocalIPAddress}
        }
        if(($RemoteIPAddress -ne $null) -and ($RemoteIPAddress -ne "")){
            $filteredConnections = $filteredConnections | Where-Object {$_.RemoteIPAddress -eq $RemoteIPAddress}
        }
        if(($State -ne $null) -and ($State -ne "")){
            $filteredConnections = $filteredConnections | Where-Object {$_.State -eq $State}
        }

        return $filteredConnections
    }

    
    #$global:IsFirstProcess = $true

    # http://blogs.microsoft.co.il/scriptfanatic/2011/02/10/how-to-find-running-processes-and-their-port-number/
    function Print-Connection($connection){
        $connection = Get-ConnectionWithProcessName $connection
        Write-Output $connection | ft `
                 @{Name="PID";Expression = { $_.PID }; Alignment="center" },
                 @{Name="ProcessName";Expression = { $_.ProcessName }; Alignment="center" },
                 @{Name="LocalAddress";Expression = { $_.LocalAddress }; Alignment="center" },
                 @{Name="LocalPort";Expression = { $_.LocalPort }; Alignment="center" },
                 @{Name="RemoteAddress";Expression = { $_.RemoteAddress }; Alignment="center" },
                 @{Name="RemotePort";Expression = { $_.RemotePort }; Alignment="center" },
                 @{Name="State";Expression = { $_.State }; Alignment="center" }`
        <#
        if($isFirstProcess){
            $global:IsFirstProcess = $false
            Write-Output $connection | ft `
                 @{Name="PID";Expression = { $_.PID }; Alignment="center" },
                 @{Name="ProcessName";Expression = { $_.ProcessName }; Alignment="center" },
                 @{Name="LocalAddress";Expression = { $_.LocalAddress }; Alignment="center" },
                 @{Name="LocalPort";Expression = { $_.LocalPort }; Alignment="center" },
                 @{Name="RemoteAddress";Expression = { $_.RemoteAddress }; Alignment="center" },
                 @{Name="RemotePort";Expression = { $_.RemotePort }; Alignment="center" },
                 @{Name="State";Expression = { $_.State }; Alignment="center" }`
                 
         } else {
             Write-Output $connection | ft -HideTableHeaders
         }
         #>
    }


    function Get-ConnectionWithProcessName($connection)
    {
         $properties = 'PID', 'ProcessName', 'LocalAddress', 'LocalPort' 
         $properties += 'RemoteAddress','RemotePort','State'
         $newConnection = New-Object PSObject -Property @{ 
            PID = $connection.OwningProcess
            ProcessName = (Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue).Name 
            #Protocol = $item[0] 
            LocalAddress = $connection.LocalAddress 
            LocalPort = $connection.LocalPort 
            RemoteAddress = $connection.RemoteAddress 
            RemotePort = $connection.RemotePort 
            State = $connection.State
        } | Select-Object -Property $properties

        return $newConnection
    }

    if($AutoClose){
        Write-Host "[*] Dropping connections"

        while($true){
            # Refreshing the connections
            $connections = Get-NetTCPConnection
            $filteredConnections = Find-Connections -Connections $connections -LocalPort $LocalPort -RemotePort $RemotePort -LocalIPAddress $LocalIPAddress -RemoteIPAddress $RemoteIPAddress -State $State -ProcessID $ProcessID
            foreach($connection in $filteredConnections){
                Print-Connection $connection
                try{
                    Close-Connection $connection
                }
                catch [Exception]
                {
                    Write-Host $_.Exception.Message -ForegroundColor Yellow
                }
            }

            Start-Sleep -Milliseconds $Milliseconds
        }

    }
    Else
    {            
        #  Sort-Object -Property LocalPort
        $formatedConnections  = New-Object System.Collections.ArrayList

        $connections | ForEach-Object { 
            #$item = Get-ConnectionWithProcessName $_

            $_ | Add-Member -Type NoteProperty -Name 'PID' -Value $_.OwningProcess
            # Performance Issue
            # Need to initialize the Get-Process to dictionary and use it
            #$_ | Add-Member -Type NoteProperty -Name 'ProcessName' -Value (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name 
            [void]$formatedConnections.Add($_)
        } 

        $connections | Sort-Object LocalPort | ft PID,ProcessName,LocalAddress,LocalPort,RemoteAddress,RemotePort,State
    }
}
