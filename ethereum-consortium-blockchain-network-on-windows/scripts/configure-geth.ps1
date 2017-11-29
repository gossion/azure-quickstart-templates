
#############
# Parameters
#############
# Validate that all arguments are supplied
if ($args.Count -lt 4) {
    echo "Insufficient parameters supplied. Exiting"; 
    exit 1; 
}

echo "args: .\configure-geth.ps1 $args" >> c:\eth.log

$AZUREUSER=$($args[0]);
$ARTIFACTS_URL_PREFIX=$($args[3])

############
## Constants
############
$HOMEDIR="c:\users\$AZUREUSER";
mkdir $HOMEDIR
$CONFIG_LOG_FILE_PATH="$HOMEDIR\config.log";

##############
## Get the script for running as Azure user
##############

cp -force * "$HOMEDIR"

###################################
## Initiate loop for error checking
###################################
cd "$HOMEDIR";
$cmd = "$HOMEDIR\configure-geth-azureuser.ps1 '$($args[0])' '$($args[1])' '$($args[2])' '$($args[3])' '$($args[4])' '$($args[5])' '$($args[6])' '$($args[7])' '$($args[8])' '$($args[9])' '$($args[10])' '$($args[11])' '$($args[12])' '$($args[13])' '$($args[14])' >> $CONFIG_LOG_FILE_PATH 2>&1"
echo "cmd: powershell $cmd"
Invoke-Expression $cmd

echo "Exit: configure-geth.ps1!"
