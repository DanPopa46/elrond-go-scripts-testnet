#!/bin/bash
set -e

#Color to the people
RED='\x1B[0;31m'
CYAN='\x1B[0;36m'
GREEN='\x1B[0;32m'
NC='\x1B[0m'

#Make script aware of its location
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"

source $SCRIPTPATH/config/variables.cfg
source $SCRIPTPATH/config/functions.cfg

echo -e
echo -e "${CYAN}Elrond MainNet scripts options:${NC}"
echo -e
echo -e "${GREEN}1) ${CYAN}install${GREEN} - Regular install process for validator nodes${NC}"
echo -e "${GREEN}2) ${CYAN}observers${GREEN} - Observers and proxy install option${NC}"
echo -e "${GREEN}3) ${CYAN}upgrade${GREEN} - Run the upgrade process for the installed nodes${NC}"
echo -e "${GREEN}4) ${CYAN}upgrade_proxy${GREEN} - Run the upgrade process for the installed proxy${NC}"
echo -e "${GREEN}5) ${CYAN}remove_db${GREEN} - Remove the nodes databases (individual node selection)${NC}"
echo -e "${GREEN}6) ${CYAN}start${GREEN} - Start all the installed nodes (will also start elrond-proxy if installed)${NC}"
echo -e "${GREEN}7) ${CYAN}stop${GREEN} - Stop all the installed nodes (will also stop elrond-proxy if installed)${NC}"
echo -e "${GREEN}8) ${CYAN}cleanup${GREEN} - Remove everything from the host${NC}"
echo -e "${GREEN}9) ${CYAN}github_pull${GREEN} - Get latest version of scripts from github (with variables backup)${NC}"
echo -e "${GREEN}10) ${CYAN}quit${GREEN} - Exit this menu${NC}"
echo -e

COLUMNS=12
PS3="Please select an action:"
options=("install" "observers" "upgrade" "upgrade_proxy" "remove_db" "start" "stop" "cleanup" "github_pull" "quit")

select opt in "${options[@]}"
do

case $opt in

'install')
  read -p "How many nodes do you want to run ? : " NUMBEROFNODES
  re='^[0-9]+$'
  if ! [[ $NUMBEROFNODES =~ $re ]] && [ "$NUMBEROFNODES" -gt 0 ]
  then
      NUMBEROFNODES = 1
  fi
  
  #Check if CUSTOM_HOME exists
  if ! [ -d "$CUSTOM_HOME" ]; then echo -e "${RED}Please configure your variables first ! (variables.cfg --> CUSTOM_HOME & CUSTOM_USER)${NC}"; exit; fi

  prerequisites

  #Keep track of how many nodes you've started on the machine
  echo "$NUMBEROFNODES" > $CUSTOM_HOME/.numberofnodes
  paths
  go_lang
  #If repos are present and you run install again this will clean up for you :D
  if [ -d "$GOPATH/src/github.com/ElrondNetwork/elrond-go" ]; then echo -e "${RED}--> Repos present. Either run the upgrade command or cleanup & install again...${NC}"; echo -e; exit; fi
  mkdir -p $GOPATH/src/github.com/ElrondNetwork
  git_clone
  build_node
  build_keygen
  
  #Run the install process for each node
  for i in $(seq 1 $NUMBEROFNODES); 
        do 
         INDEX=$(( $i - 1 ))
         WORKDIR="$CUSTOM_HOME/elrond-nodes/node-$INDEX"
         install
         install_utils
         node_name
         keys
         systemd
       done
       
  sudo chown -R $CUSTOM_USER: $CUSTOM_HOME/elrond-nodes
  break
  ;;

'observers')
  #Install observers for all shards
  NUMBEROFNODES=4
  
  #Check if CUSTOM_HOME exists
  if ! [ -d "$CUSTOM_HOME" ]; then echo -e "${RED}Please configure your variables first ! (variables.cfg --> CUSTOM_HOME & CUSTOM_USER)${NC}"; exit; fi

  prerequisites

  #Keep track of how many nodes you've started on the machine
  echo "$NUMBEROFNODES" > $CUSTOM_HOME/.numberofnodes
  paths
  go_lang
  #If repos are present and you run install again this will clean up for you :D
  if [ -d "$GOPATH/src/github.com/ElrondNetwork/elrond-go" ]; then echo -e "${RED}--> Repos present. Either run the upgrade command or cleanup & install again...${NC}"; echo -e; exit; fi
  mkdir -p $GOPATH/src/github.com/ElrondNetwork
  git_clone
  git_clone_proxy
  build_node
  build_keygen
  
  #Run the install process for each observer
  for i in $(seq 1 $NUMBEROFNODES); 
        do 
         INDEX=$(( $i - 1 ))
         WORKDIR="$CUSTOM_HOME/elrond-nodes/node-$INDEX"
         install
         install_utils
         node_name
         observer_keys
         systemd
         if [[ "$INDEX" == 3 ]]; then
                       sed -i 's/DestinationShardAsObserver = "disabled"/DestinationShardAsObserver = "metachain"/' $WORKDIR/config/prefs.toml
                  else 
                  sed -i 's/DestinationShardAsObserver = "disabled"/DestinationShardAsObserver = "'$INDEX'"/' $WORKDIR/config/prefs.toml
            fi
       done
  sudo chown -R $CUSTOM_USER: $CUSTOM_HOME/elrond-nodes
  
  #Install & configure elrond-proxy
  elrond_proxy
  proxy_config
  break
  ;;

'upgrade')
  paths
  #Check to see if scripts have been updated
  cd $SCRIPTPATH
  CURRENT_SCRIPTS_COMMIT=$(git show | grep commit | awk '{print $2}')
  
      if [ $LATEST_SCRIPTS_COMMIT == $CURRENT_SCRIPTS_COMMIT ]; then
          echo "Strings are equal"
          cd $GOPATH/src/github.com/ElrondNetwork/elrond-config-testnet
          INSTALLED_CONFIGS=$(git status | grep HEAD | awk '{print $4}')
          echo -e
          echo -e "${GREEN}Local version for configs: ${CYAN}tags/$INSTALLED_CONFIGS${NC}"
          echo -e
          echo -e "${GREEN}Github version of configs: ${CYAN}$CONFIGVER${NC}"
          echo -e
          echo -e "${GREEN}Release notes for the latest version:${NC}"
          echo -e "${GREEN}$RELEASENOTES${NC}"  
          echo -e 
          read -p "Do you want to go on with the upgrade (Default No) ? (Yy/Nn)" yn
          echo -e
  
          case $yn in
               [Yy]* )
                 #Remove previously cloned repos
                 if [ -d "$GOPATH/src/github.com/ElrondNetwork/elrond-go" ]; then sudo rm -rf $GOPATH/src/github.com/ElrondNetwork/elrond-*; echo -e; echo -e "${RED}--> Repos present. Removing and fetching again...${NC}"; echo -e; fi
                   git_clone
                   build_node
                   build_keygen
                 if ! [ -d "$CUSTOM_HOME/elrond-utils" ]; then mkdir -p $CUSTOM_HOME/elrond-utils; fi
                   install_utils
  
                 INSTALLEDNODES=$(cat $CUSTOM_HOME/.numberofnodes)
  
                 #Run the update process for each node
                 for i in $(seq 1 $INSTALLEDNODES);
                      do
                        UPDATEINDEX=$(( $i - 1 ))
                        UPDATEWORKDIR="$CUSTOM_HOME/elrond-nodes/node-$UPDATEINDEX"
                        cp -f $UPDATEWORKDIR/config/prefs.toml $UPDATEWORKDIR/config/prefs.toml.save
        
                        sudo systemctl stop elrond-node-$UPDATEINDEX
                        update
                        mv $UPDATEWORKDIR/config/prefs.toml.save $UPDATEWORKDIR/config/prefs.toml
                        echo -e
                        echo -e "${CYAN}--> elrond-node-$UPDATEINDEX upgraded. Don't forget to start it...${NC}"
                        echo -e
                    done
                  ;;
            
                [Nn]* )
                  echo -e "${GREEN}Fine ! Skipping upgrade on this machine...${NC}"
                  ;;
            
                * )
                  echo -e "${GREEN}I'll take that as a no then... moving on...${NC}"
                  ;;
            esac
  
        else
          echo -e "${RED}You do not have the latest version of the elrond-go-scripts-testnet !!!${NC}"
          echo -e "${RED}Please run ${CYAN}./script.sh github_pull${RED} before running the upgrade command...${NC}"
       fi
  break
  ;;

'upgrade_proxy')
  paths
  echo -e
  echo -e "${GREEN}This option will rebuild your proxy from the latest github code.${NC}"
  echo -e
  read -p "Do you want to go on with the upgrade (Default No) ? (Yy/Nn)" yn
  echo -e

  case $yn in
       [Yy]* )
         #Remove previously cloned repo
         if [ -d "$GOPATH/src/github.com/ElrondNetwork/elrond-proxy-go" ]; then sudo rm -rf $GOPATH/src/github.com/ElrondNetwork/elrond-proxy-go; echo -e; echo -e "${RED}--> Repo present. Removing and fetching again...${NC}"; echo -e; fi
           git_clone_proxy
           pidof proxy >/dev/null && sudo service elrond-proxy stop
           #Remove old proxy folder & service
           if [ -e /etc/systemd/system/elrond-proxy.service ]; then sudo rm /etc/systemd/system/elrond-proxy.service; fi
           sudo systemctl daemon-reload
           if [ -d $CUSTOM_HOME/elrond-proxy/ ]; then sudo rm -rf $CUSTOM_HOME/elrond-proxy/; fi
           
           #Rebuild the proxy & run the config for it again
           elrond_proxy
           proxy_config

           #Restart the new proxy
           sudo systemctl start elrond-proxy
          ;;
    
        [Nn]* )
          echo -e "${GREEN}Fine ! Skipping proxy upgrade on this machine...${NC}"
          ;;
    
        * )
          echo -e "${GREEN}I'll take that as a no then... moving on...${NC}"
          ;;
    esac
  break
  ;;

'remove_db')
  paths
  echo -e
  echo -e "${RED}This action will completly erase the DBs and logs of your nodes !${NC}"  
  echo -e 
  read -p "Do you want to go on with the DB erase (Default No) ? (Yy/Nn)" yn
  echo -e
  case $yn in
       [Yy]* )

         INSTALLEDNODES=$(cat $CUSTOM_HOME/.numberofnodes)
         #Run the cleaning process for each node
         for i in $(seq 1 $INSTALLEDNODES);
             do
               UPDATEINDEX=$(( $i - 1 ))
               UPDATEWORKDIR="$CUSTOM_HOME/elrond-nodes/node-$UPDATEINDEX"
               
               echo -e "${GREEN}Stopping Elrond Node-$UPDATEINDEX binary...${NC}"
               
               sudo systemctl stop elrond-node-$UPDATEINDEX
               cleanup

               echo -e "${RED}Warning! The nodes will not be automatically restarted after the DB is removed!"
               echo -e
           done
            ;;
            
       [Nn]* )
          echo -e "${GREEN}Fine ! Skipping DB cleanup on this machine...${NC}"
            ;;
            
           * )
           echo -e "${GREEN}I'll take that as a no then... moving on...${NC}"
            ;;
      esac
  break
  ;;

'start')
  NODESTOSTART=$(cat $CUSTOM_HOME/.numberofnodes)
  for i in $(seq 1 $NODESTOSTART);
      do
        STARTINDEX=$(( $i - 1 ))
        echo -e
        echo -e "${GREEN}Starting Elrond Node-$STARTINDEX binary on host ${CYAN}$HOST${GREEN}...${NC}"
        echo -e
        sudo systemctl start elrond-node-$STARTINDEX
      done
  if [ -e /etc/systemd/system/elrond-proxy.service ]; then
                                        echo -e
                                        echo -e "${GREEN}Starting the Elrond Proxy service on host ${CYAN}$HOST${GREEN}...${NC}"
                                        echo -e
                                        sudo systemctl start elrond-proxy
            fi
  break
  ;;

'stop')
  NODESTOSTOP=$(cat $CUSTOM_HOME/.numberofnodes)
  for i in $(seq 1 $NODESTOSTOP);
      do
        STOPINDEX=$(( $i - 1 ))
        echo -e
        echo -e "${GREEN}Stopping Elrond Node-$STOPINDEX binary on host ${CYAN}$HOST${GREEN}...${NC}"
        echo -e
        sudo systemctl stop elrond-node-$STOPINDEX
      done
  if [ -e /etc/systemd/system/elrond-proxy.service ]; then
                                        echo -e
                                        echo -e "${GREEN}Stopping the Elrond Proxy service on host ${CYAN}$HOST${GREEN}...${NC}"
                                        echo -e
                                        sudo systemctl stop elrond-proxy
            fi
  break
  ;;

'cleanup')
  paths
  echo -e 
  read -p "Do you want to delete installed nodes (Default No) ? (Yy/Nn)" yn
  echo -e
  case $yn in
       [Yy]* )
          echo -e "${RED}OK ! Cleaning everything !${NC}"
          
          if [[ -f $CUSTOM_HOME/.numberofnodes ]]; then
            NODESTODESTROY=$(cat $CUSTOM_HOME/.numberofnodes)
                for i in $(seq 1 $NODESTODESTROY);
                    do
                        KILLINDEX=$(( $i - 1 ))
                          echo -e
                          echo -e "${GREEN}Stopping Elrond Node-$KILLINDEX binary on host ${CYAN}$HOST${GREEN}...${NC}"
                          echo -e
                          if [ -e /etc/systemd/system/elrond-node-$KILLINDEX.service ]; then sudo systemctl stop elrond-node-$KILLINDEX; fi
                          echo -e "${GREEN}Erasing unit file and node folder for Elrond Node-$KILLINDEX...${NC}"
                          echo -e
                          if [ -e /etc/systemd/system/elrond-node-$KILLINDEX.service ]; then sudo rm /etc/systemd/system/elrond-node-$KILLINDEX.service; fi
                          if [ -d $CUSTOM_HOME/elrond-nodes/node-$KILLINDEX ]; then sudo rm -rf $CUSTOM_HOME/elrond-nodes/node-$KILLINDEX; fi
                    done
          fi
          
            #Stop and remove the elrond-proxy service if present
            if [ -e /etc/systemd/system/elrond-proxy.service ]; then sudo systemctl stop elrond-proxy; fi
            if [ -e /etc/systemd/system/elrond-proxy.service ]; then sudo rm /etc/systemd/system/elrond-proxy.service; fi
            if [ -d $CUSTOM_HOME/elrond-proxy/ ]; then sudo rm -rf $CUSTOM_HOME/elrond-proxy/; fi

            #Reload systemd after deleting node units
            sudo systemctl daemon-reload
            
            echo -e
            echo -e "${GREEN}Removing elrond utils...${NC}"
            echo -e      
            
            if ps -all | grep -q termui; then killall termui; sleep 2; fi
            if [[ -e $CUSTOM_HOME/elrond-utils/termui ]]; then rm $CUSTOM_HOME/elrond-utils/termui; fi
              
            if ps -all | grep -q logviewer; then killall logviewer; sleep 2; fi
            if [[ -e $CUSTOM_HOME/elrond-utils/logviewer ]]; then rm $CUSTOM_HOME/elrond-utils/logviewer; fi
            
            rm -rf $CUSTOM_HOME/elrond-utils && rm -rf $CUSTOM_HOME/elrond-nodes
            
            echo -e "${GREEN}Removing paths from .profile on host ${CYAN}$HOST${GREEN}...${NC}"
            echo -e
            sed -i 'N;$!P;$!D;$d' ~/.profile
            
            echo -e "${GREEN}Removing cloned elrond-go & elrond-configs repos from host ${CYAN}$HOST${GREEN}...${NC}"
            echo -e      
            if [ -d "$GOPATH/src/github.com/ElrondNetwork/elrond-go" ]; then sudo rm -rf $GOPATH/src/github.com/ElrondNetwork/elrond-*; fi      
            ;;
            
       [Nn]* )
          echo -e "${GREEN}Fine ! Skipping cleanup on this machine...${NC}"
            ;;
            
           * )
           echo -e "${GREEN}I'll take that as a no then... moving on...${NC}"
            ;;
      esac
  break
  ;;

'github_pull')
  #First backup variables.cfg
  variables_backup
  echo -e "${GREEN}---> Fetching the latest version of the sripts...${NC}"
  echo -e
  #First let's check if the repo is accesible
  REPO_STATUS=$(curl -I "https://github.com/ElrondNetwork/elrond-go-scripts-mainnet" 2>&1 | awk '/HTTP\// {print $2}')
  cd $SCRIPTPATH
  if [ "$REPO_STATUS" -eq "200" ]; then
                                #Now let's fetch the latest version of the scripts
                                echo -e "${GREEN}---> elrond-go-scripts-mainnet is reachable ! Pulling latest version...${NC}"
                                git reset --hard HEAD
                                git pull
                      else echo -e "${RED}---> elrond-go-scripts-mainnet on Github not reachable !${NC}"
              fi
  #Restore custom variables after repo pull
  echo -e "${GREEN}---> Restoring your config files${NC}"
  echo -e
  variables_restore
  echo -e "${GREEN}---> Finished fetching scripts...${NC}"
  echo -e
  break
  ;;

'get_logs')
  #Get journalctl logs from all the nodes
  NODELOGS=$(cat $CUSTOM_HOME/.numberofnodes)
  LOGSTIME=$(date "+%Y%m%d-%H%M")
  LOGSOFFSET=8080
  
  #Make sure the log path exists
  mkdir -p $CUSTOM_HOME/elrond-logs
  
  for i in $(seq 1 $NODELOGS);
      do
        LOGSINDEX=$(( $i - 1 ))
        LOGSAPIPORT=$(( $LOGSOFFSET + $LOGSINDEX ))
        echo -e
        echo -e "${GREEN}Getting logs for Elrond Node-$LOGSINDEX binary...${NC}"
        echo -e
        LOGSPUBLIC=$(curl -s http://127.0.0.1:$LOGSAPIPORT/node/status | jq -r .data.metrics.erd_public_key_block_sign | head -c 12)
        sudo journalctl --unit elrond-node-$LOGSINDEX >> $CUSTOM_HOME/elrond-logs/elrond-node-$LOGSINDEX-$LOGSPUBLIC.log
      done

  #Compress the logs and erase files
  cd $CUSTOM_HOME/elrond-logs/ && tar -zcvf elrond-node-logs-$LOGSTIME.tar.gz *.log && rm *.log
  break 
  ;;

'quit')
  echo -e
  echo -e "${GREEN}---> Exiting scripts menu...${NC}"
  echo -e
  break
  ;;

esac

done