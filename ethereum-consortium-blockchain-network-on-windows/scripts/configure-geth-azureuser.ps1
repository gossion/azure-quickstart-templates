#!/bin/bash

# Utility function to exit with message
function unsuccessful_exit($err) {

    echo "FATAL: Exiting script due to: $err";
    exit 1;
}


function sha256sum([string]$string)
{
	$oSHA256=[System.Security.Cryptography.SHA256]::Create()
    $utf8 = new-object -TypeName System.Text.UTF8Encoding
	$sSHA256=[System.BitConverter]::ToString($oSHA256.ComputeHash($utf8.GetBytes($string))).Replace("-","").ToLower()
	return($sSHA256)
}


echo "===== Initializing geth installation =====";
date;

############
# Parameters
############
# Validate that all arguments are supplied
if ( $args.Count -lt 10 ) {
    unsuccessful_exit "Insufficient parameters supplied."
}

$AZUREUSER=$args[0];
$PASSWD=$args[1];
$PASSPHRASE=$args[2];
$ARTIFACTS_URL_PREFIX=$args[3];
$NETWORK_ID=$args[4];
$MAX_PEERS=$args[5];
$NODE_TYPE=$args[6];       # (0=Transaction node; 1=Mining node )
$GETH_IPC_PORT=$args[7];
$NUM_BOOT_NODES=$args[8];
$NUM_MN_NODES=$args[9];
$MN_NODE_PREFIX=$args[10];
$SPECIFIED_GENESIS_BLOCK=$args[11];
$MN_NODE_SEQNUM=$args[12];   #Only supplied for NODE_TYPE=1
$NUM_TX_NODES=$args[12];     #Only supplied for NODE_TYPE=0
$TX_NODE_PREFIX=$args[13];   #Only supplied for NODE_TYPE=0
$ADMIN_SITE_PORT=$args[14];  #Only supplied for NODE_TYPE=0

$MINER_THREADS=1;
# Difficulty constant represents ~15 sec. block generation for one node
$DIFFICULTY_CONSTANT=0x3333;

$HOMEDIR="c:\users\$AZUREUSER";
$VMNAME=hostname;
$GETH_HOME="$HOMEDIR\.ethereum";
mkdir -force $GETH_HOME;
$ETHERADMIN_HOME="$HOMEDIR\etheradmin";
mkdir -force $ETHERADMIN_HOME
$GETH_LOG_FILE_PATH="$HOMEDIR\geth.log";
$GENESIS_FILE_PATH="$HOMEDIR\genesis.json";
$GETH_CFG_FILE_PATH="$HOMEDIR\geth.ps1";
$NODEKEY_FILE_PATH="$GETH_HOME\nodekey";


###################
## Scale difficulty
###################
## Target difficulty scales with number of miners
$DIFFICULTY="0x{0:x}" -f ($DIFFICULTY_CONSTANT * $NUM_MN_NODES)

###############
## Install node
###############

Invoke-WebRequest -Uri https://nodejs.org/dist/v8.9.1/node-v8.9.1-x64.msi -OutFile node-v8.9.1-x64.msi
.\node-v8.9.1-x64.msi /qn
$env:Path = "C:\Program Files\nodejs;" + $env:Path

###############
## Install geth
###############

Invoke-WebRequest -Uri https://gethstore.blob.core.windows.net/builds/geth-windows-amd64-1.7.3-4bb3c89d.exe -OutFile geth-windows-amd64-1.7.3-4bb3c89d.exe
.\geth-windows-amd64-1.7.3-4bb3c89d.exe  /S /v/qn
$env:Path = "C:\Program Files\Geth\;" + $env:Path
$GETH="C:\Program Files\Geth\geth.exe"


##############
## Build node keys and node IDs
##############

echo "===== Starting node key and node ID generation =====";
$NODE_KEYS = New-Object System.Collections.ArrayList
$NODE_IDS = New-Object System.Collections.ArrayList
echo "NUM_BOOT_NODES: $NUM_BOOT_NODES"
for($i=0; $i -lt $NUM_BOOT_NODES; $i++) {
	$BOOT_NODE_HOSTNAME="$MN_NODE_PREFIX$i";
    $sha = sha256sum -string $BOOT_NODE_HOSTNAME
	$NODE_KEYS.Add($sha)

    $sb = [scriptblock]::Create("cmd /c geth.exe --nodekeyhex $sha  2>&1")
	$job = Start-Job -ScriptBlock $sb
    
	for ($j=0; $j -lt 5;$j++) {
        sleep 5

        $output = Receive-Job -id $job.Id
        echo "output: $output"
        if($output -match '(?<=\/\/).*(?=@)') {
            # example: INFO [12-01|09:23:00] UDP listener up                          self=enode://1444044cb4163d0d540906e4619264ac248b3fee5d591ed49c494e6e480aacd64fb47673970684015364b7e487d22457a44b55f16bce3af16c0f6c1e3d08698d@[::]:30303
            $s = echo $output | Select-String -Pattern '(?<=\/\/).*(?=@)'
            $id = (($s[0] -split '\/\/')[1] -split '@')[0]
            $NODE_IDS.Add($id)
            Stop-Process -name geth
            break  ##BUG here, why it not break
        }

        echo "Can not get enode, loop again"
	}
}

echo "NODE_KEYS: $NODE_KEYS"
echo "NODE_IDS: $NODE_IDS"

if ($NODE_IDS.Count -eq 0) {
    echo "Can not get enode, quit"
}

$PASSWD_FILE="$GETH_HOME\passwd.info";
echo  $PASSWD $PASSWD > $PASSWD_FILE;
#
$PRIV_KEY = "265d682756b26ae9260ab34043641633d451be86246408259b898b68b998f989"
$ETHERBASE_ADDRESS= "ab6fbcafe14c47dba44ae9eb7673137418e36280" #geth --datadir $GETH_HOME --password $PASSWD_FILE account import $HOMEDIR/priv_genesis.key | grep -oP '\{\K[^}]+'`
$PRIV_KEY | Set-Content $HOMEDIR\priv_genesis.key;
Get-Content $PASSWD_FILE | geth.exe --datadir $GETH_HOME account import $HOMEDIR\priv_genesis.key




#	##############################################
#	# Setup Genesis file and pre-allocated account
#	##############################################
echo "===== Starting genesis file creation =====";

cd $HOMEDIR
Invoke-WebRequest -Uri $ARTIFACTS_URL_PREFIX/genesis-template.json -OutFile genesis-template.json
(Get-Content $HOMEDIR\genesis-template.json) -replace "#DIFFICULTY", $DIFFICULTY | Set-Content $HOMEDIR\genesis.json
(Get-Content $HOMEDIR\genesis.json) -replace "#PREFUND_ADDRESS", $ETHERBASE_ADDRESS | Set-Content $HOMEDIR\genesis.json
(Get-Content $HOMEDIR\genesis.json) -replace "#NETWORKID", $NETWORK_ID | Set-Content $HOMEDIR\genesis.json


#
###################
## Extract gasLimit from genesis.json, needed for miner option targetgaslimit 
$GASLIMIT="0x4c4b40"


echo "===== Completed genesis file and pre-allocated account creation =====";
#
cd $HOMEDIR
Invoke-WebRequest -Uri $ARTIFACTS_URL_PREFIX/scripts/start-private-blockchain.ps1 -OutFile start-private-blockchain.ps1
#
#####################
## Initialize geth for private network
#####################
echo "===== Starting initialization of geth for private network =====";
if (($NODE_TYPE -eq 1)  -and  ($MN_NODE_SEQNUM -lt $NUM_BOOT_NODES)) {
    $NODE_KEYS[$MN_NODE_SEQNUM] | Set-Content $NODEKEY_FILE_PATH;
}
#
##################
## Initialize geth
##################
#
## Clear out old chaindata
#rm $GETH_HOME/geth/chaindata -r -Force
mkdir -Force $GETH_HOME/geth/chaindata
geth.exe --datadir $GETH_HOME -verbosity 6 init $GENESIS_FILE_PATH >> $GETH_LOG_FILE_PATH 2>&1;

#echo "===== Completed initialization of geth for private network =====";
#
######################
## Setup admin website
######################
if( $NODE_TYPE -eq 0 ) {# TX nodes only
	echo "===== Starting admin website setup =====";
	mkdir  $ETHERADMIN_HOME\views\layouts;
	cd $ETHERADMIN_HOME\views\layouts;
	Invoke-WebRequest -Uri ${ARTIFACTS_URL_PREFIX}/scripts/etheradmin/main.handlebars -OutFile main.handlebars
	cd $ETHERADMIN_HOME\views;
	Invoke-WebRequest -Uri ${ARTIFACTS_URL_PREFIX}/scripts/etheradmin/etheradmin.handlebars -OutFile etheradmin.handlebars
	Invoke-WebRequest -Uri ${ARTIFACTS_URL_PREFIX}/scripts/etheradmin/etherstartup.handlebars -OutFile etherstartup.handlebars
	cd $ETHERADMIN_HOME;
	Invoke-WebRequest -Uri ${ARTIFACTS_URL_PREFIX}/scripts/etheradmin/package.json -OutFile package.json
	Invoke-WebRequest -Uri ${ARTIFACTS_URL_PREFIX}/scripts/etheradmin/npm-shrinkwrap.json -OutFile npm-shrinkwrap.json
    npm install

	Invoke-WebRequest -Uri ${ARTIFACTS_URL_PREFIX}/scripts/etheradmin/app.js -OutFile app.js
	mkdir $ETHERADMIN_HOME\public;
	cd $ETHERADMIN_HOME\public;
	Invoke-WebRequest -Uri ${ARTIFACTS_URL_PREFIX}/scripts/etheradmin/skeleton.css -OutFile skeleton.css
	echo "===== Completed admin website setup =====";
}
#
##########################
## Generate boot node URLs
#####################
echo "===== Starting bootnode URL generation =====";
$BOOTNODE_URLS="";
for ($i=0; $i -le ($NUM_BOOT_NODES - 1); $i++) {
    $BOOTNODE_URLS = "${BOOTNODE_URLS}enode://$($NODE_IDS[$i])@#${MN_NODE_PREFIX}${i}#:${GETH_IPC_PORT}";
    if ( $i -le $(($NUM_BOOT_NODES - 2)) ) {
        $BOOTNODE_URLS="${BOOTNODE_URLS} --bootnodes ";
    }
}
echo "BOOTNODE_URLS: $BOOTNODE_URLS"
echo "===== Completed bootnode URL generation =====";
#
###################
## Create conf file
###################
"`$HOMEDIR=`"$HOMEDIR`"" > $GETH_CFG_FILE_PATH;
"`$IDENTITY=`"$VMNAME`"" >> $GETH_CFG_FILE_PATH;
"`$NETWORK_ID=$NETWORK_ID" >> $GETH_CFG_FILE_PATH;
"`$MAX_PEERS=$MAX_PEERS" >> $GETH_CFG_FILE_PATH;
"`$NODE_TYPE=$NODE_TYPE" >> $GETH_CFG_FILE_PATH;
"`$BOOTNODE_URLS=`"$BOOTNODE_URLS`"" >> $GETH_CFG_FILE_PATH;
"`$MN_NODE_PREFIX=`"$MN_NODE_PREFIX`"" >> $GETH_CFG_FILE_PATH;
"`$NUM_BOOT_NODES=$NUM_BOOT_NODES" >> $GETH_CFG_FILE_PATH;
"`$MINER_THREADS=$MINER_THREADS" >> $GETH_CFG_FILE_PATH;
"`$GETH_HOME=`"$GETH_HOME`"" >> $GETH_CFG_FILE_PATH;
"`$GETH_LOG_FILE_PATH=`"$GETH_LOG_FILE_PATH`"" >> $GETH_CFG_FILE_PATH;
"`$GASLIMIT=$GASLIMIT" >> $GETH_CFG_FILE_PATH;
#
if ( $NODE_TYPE -eq 0 ) { #TX node
"`$ETHERADMIN_HOME=`"$ETHERADMIN_HOME`"" >> $GETH_CFG_FILE_PATH;
"`$ETHERBASE_ADDRESS=`"$ETHERBASE_ADDRESS`"" >> $GETH_CFG_FILE_PATH;
"`$NUM_MN_NODES=$NUM_MN_NODES" >> $GETH_CFG_FILE_PATH;
"`$TX_NODE_PREFIX=`"$TX_NODE_PREFIX`"" >> $GETH_CFG_FILE_PATH;
"`$NUM_TX_NODES=$NUM_TX_NODES" >> $GETH_CFG_FILE_PATH;
"`$ADMIN_SITE_PORT=`"$ADMIN_SITE_PORT`"" >> $GETH_CFG_FILE_PATH;
}

netsh advfirewall firewall add rule name="Open Port 8545" dir=in action=allow protocol=TCP localport=8545
netsh advfirewall firewall add rule name="Open Port 8545" dir=in action=allow protocol=UDP localport=8545
netsh advfirewall firewall add rule name="Open Port 3000" dir=in action=allow protocol=TCP localport=3000

#
###########################################
## Setup rc.local for service start on boot
###########################################
#echo "===== Setting up rc.local for restart on VM reboot =====";
#echo -e '#!/bin/bash' "\nsudo -u $AZUREUSER /bin/bash $HOMEDIR/start-private-blockchain.sh $GETH_CFG_FILE_PATH $PASSWD" | sudo tee /etc/rc.local 2>&1 1>/dev/null
#if [ $? -ne 0 ]; then
#	unsuccessful_exit "failed to setup rc.local for restart on VM reboot";
#fi
#echo "===== Completed setting up rc.local for restart on VM reboot =====";

echo "schtasks /create /tn "start-geth" /sc onstart /delay 0000:30 /rl highest /ru system /tr `"powershell.exe -file $HOMEDIR\start-private-blockchain.ps1 $GETH_CFG_FILE_PATH $PASSWD`""
schtasks /create /tn "start-geth" /sc onstart /delay 0000:30 /rl highest /ru system /tr "powershell.exe -file $HOMEDIR\start-private-blockchain.ps1 $GETH_CFG_FILE_PATH $PASSWD"

echo "schtasks /run /tn `"start-geth`""
schtasks /run /tn "start-geth"

echo "Exit: configure-geth-azureuser.ps1!";