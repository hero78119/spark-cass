sudo docker stop $(sudo docker ps -a -q) && sudo docker rm $(sudo docker ps -a -q)
sudo docker run -p 192.168.0.105:2222:22 -p 192.168.0.105:8080:8080 -d --name cass1 jonas/cassspark bash start
sudo docker run -d --name cass2 --link cass1:seed jonas/cassspark bash start seed
sudo docker run -d --name cass3 --link cass1:seed jonas/cassspark bash start seed
sudo docker run -d --name cass4 --link cass1:seed jonas/cassspark bash start seed
# sudo docker run -d --name cass4 --link cass1:seed jonas/cassspark bash start seed

MASTER_HOSTNAME=`sudo docker run -it --rm --net container:cass1 jonas/cassspark  hostname`
MASTER_IP=`sudo sh ips.sh | grep cass1 | awk -F" " '{print $1}'`
SLAVE_IPS=`sudo sh ips.sh | awk -F" " '{print $1}' |tr '\n' ',' | sed 's/,$//'`
SLAVE_IPS_SLAVES=`sudo sh ips.sh | awk -F" " '{print $1}' |tr '\n' '\n' | sed 's/\n$//'`
pri_key=`cat ~/.ssh/id_rsa`

echo $MASTER_IP
echo $SLAVE_IPS

sed "6s/.*/\"ipList\": \"$MASTER_IP\",/" ./account-management-deploy-system/res/config.json > ./account-management-deploy-system/res/config.json_new
mv ./account-management-deploy-system/res/config.json_new ./account-management-deploy-system/res/config.json
sed "13s/.*/\"ipList\": \"$SLAVE_IPS\",/" ./account-management-deploy-system/res/config.json > ./account-management-deploy-system/res/config.json_new
mv ./account-management-deploy-system/res/config.json_new ./account-management-deploy-system/res/config.json

# sed -i -e "s/^listen_address.*/listen_address: $IP/"            $CONFIG/cassandra.yaml

cd account-management-deploy-system

sleep 20;

# start spark master 
python ./src/Main.py --task=exeShellCmd --cmd="echo '$pri_key' > ~/.ssh/id_rsa; chmod 600 ~/.ssh/id_rsa ; echo $SLAVE_IPS > /usr/local/spark/conf/slaves; sed 's/,/\\n/g' /usr/local/spark/conf/slaves > /usr/local/spark/conf/slaves_tmp; mv /usr/local/spark/conf/slaves_tmp /usr/local/spark/conf/slaves; echo \"SPARK_MASTER_IP=$MASTER_IP,SPARK_WORKER_INSTANCES=2\" >> /usr/local/spark/conf/spark-env.sh; sed 's/,/\\n/g' /usr/local/spark/conf/spark-env.sh > /usr/local/spark/conf/spark-env.sh_tmp; mv /usr/local/spark/conf/spark-env.sh_tmp /usr/local/spark/conf/spark-env.sh; /usr/local/spark/sbin/start-all.sh"  --envs=master
# start spark slave 0
# python ./src/Main.py --task=exeShellCmd --cmd="/usr/local/spark/sbin/start-slave.sh spark://$MASTER_HOSTNAME:7077"  --envs=slave

cd -
