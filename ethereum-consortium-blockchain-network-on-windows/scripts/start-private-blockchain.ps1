#!/bin/bash


function Get-HostToIP($hostname) {     
    $result = [system.Net.Dns]::GetHostByName($hostname)     
    $result.AddressList | ForEach-Object {$_.IPAddressToString } 
} 

#############
# Parameters
#############
if ( $args.Count -lt 2 ) {
    echo "Incomplete parameters supplied. usage: start config-file-path ethereum-account-passwd";
    exit 1;
}

$GETH_CFG=$args[0];
$PASSWD=$args[1];

# Load config variables
if ( !(Test-Path $GETH_CFG) ) {
    echo "Config file not found. Exiting"
    exit 1
}
. $GETH_CFG

# Ensure that at least one bootnode is up
# If not, wait 5 seconds then retry
$FOUND_BOOTNODE=$false
$ips = New-Object System.Collections.Hashtable

for ($i=0; $i -le ($NUM_BOOT_NODES - 1); $i++) {
    for ($j=0; $j -lt 5; $j++) {
        $hostname = "$MN_NODE_PREFIX$i"
        echo "hostname: $hostname"
        $result = Get-HostToIP($hostname)
        if ($result -ne $null) {
            $ip = $result
            echo "ip: $ip"
 
	    	$ips[$hostname] = $ip
	    	break
        }
        sleep 5
    }
}
echo "ips: $ips" >> "$HOMEDIR\start.log"

foreach ($ip in $ips.GetEnumerator()) {
    $BOOTNODE_URLS = $BOOTNODE_URLS.Replace("#$($ip.Name)#", $($ip.Value))
} 

$ETHERADMIN_LOG_FILE_PATH="$HOMEDIR\etheradmin.log";

# Get IP address for geth RPC binding
$ipV4 = Test-Connection -ComputerName (hostname) -Count 1  | Select IPV4Address
$IPADDR = $ipV4.IPV4Address.IPAddressToString

# Only mine on mining nodes
if  ( $NODE_TYPE -ne 0 ) {
  $MINE_OPTIONS="--mine --minerthreads $MINER_THREADS --targetgaslimit $GASLIMIT";
} else {
  $FAST_SYNC="--fast";
}

$VERBOSITY=4;

$env:Path = "C:\Program Files\Geth\;" + $env:Path
$env:Path = "C:\Program Files\nodejs;" + $env:Path

sleep 5

echo "===== Starting geth node =====";
$geth_cmd = "geth.exe --datadir $GETH_HOME -verbosity $VERBOSITY --bootnodes $BOOTNODE_URLS --maxpeers $MAX_PEERS --nat none --networkid $NETWORK_ID --identity $IDENTITY $MINE_OPTIONS $FAST_SYNC --rpc --rpcaddr $IPADDR --rpccorsdomain `"*`" > $GETH_LOG_FILE_PATH 2>&1"
echo "cmd: $geth_cmd" >> "$HOMEDIR\start.log"
$process = Start-Process -FilePath "geth.exe" -ArgumentList "--datadir $GETH_HOME -verbosity $VERBOSITY --bootnodes $BOOTNODE_URLS --maxpeers $MAX_PEERS --nat none --networkid $NETWORK_ID --identity $IDENTITY $MINE_OPTIONS $FAST_SYNC --rpc --rpcaddr $IPADDR --rpccorsdomain `"*`"" -NoNewWindow -PassThru -RedirectStandardOutput "$HOMEDIR\geth.log" -RedirectStandardError "$HOMEDIR\geth.err.log"

echo "===== Started geth node =====";

# Startup admin site on TX VMs
if ($NODE_TYPE -eq 0 ) {
  cd $ETHERADMIN_HOME;

  npm install express
  sleep 120 #wait for geth to bootup

  echo "===== Starting admin webserver =====";

  $node_cmd = "node.exe app.js $ADMIN_SITE_PORT \\.\pipe\geth.ipc $ETHERBASE_ADDRESS $PASSWD $MN_NODE_PREFIX $NUM_MN_NODES $TX_NODE_PREFIX $NUM_TX_NODES $NUM_BOOT_NODES"
  echo "cmd: $node_cmd" >> "$HOMEDIR\start.log"
  $process = Start-Process -FilePath "node.exe" -ArgumentList "app.js $ADMIN_SITE_PORT \\.\pipe\geth.ipc $ETHERBASE_ADDRESS $PASSWD $MN_NODE_PREFIX $NUM_MN_NODES $TX_NODE_PREFIX $NUM_TX_NODES $NUM_BOOT_NODES" -NoNewWindow -PassThru -RedirectStandardOutput "$HOMEDIR\etheradmin.log" -RedirectStandardError "$HOMEDIR\etheradmin.err.log"
  
  echo "===== Started admin webserver =====";
}
