#!/bin/bash

# Load Env
export PGPORT=1921
export PGUSER=sky_pg_cluster
export PGDBNAME=sky_pg_cluster
export PGDATA=/opt/database/pg94/pg_root
export LANG=en_US.utf8
export PGHOME=/opt/pgsql
export LD_LIBRARY_PATH=$PGHOME/lib:/lib64:/usr/lib64:/usr/local/lib64:/lib:/usr/lib:/usr/local/lib
export PATH=/opt/pgbouncer/bin:$PGHOME/bin:$PGPOOL_HOME/bin:$PATH:.

MONITOR_LOG="/tmp/pg_monitor.log"
SQL1="update cluster_status set last_alive = now();"
SQL2='select 1;'

# 如果是备库,则退出，此脚本不检查备库存活状态
standby_flg=`psql -p $PGPORT -U postgres -At -c "select pg_is_in_recovery();"`
if [ ${standby_flg} == 't' ]; then
    echo -e "`date +%F\ %T`: This is a standby database, exit!\n" >> $MONITOR_LOG
    exit 0
fi

# 主库上更新 cluster_state 表
echo $SQL1 | psql -At -h 127.0.0.1 -p $PGPORT -U $PGUSER -d $PGDBNAME >> $MONITOR_LOG


# 判断主库是否可用
echo $SQL2 | psql -At -h 127.0.0.1 -p $PGPORT -U $PGUSER -d $PGDBNAME 
if [ $? -eq 0 ]; then
   echo -e "`date +%F\ %T`:  Primary db is health."  >> $MONITOR_LOG
   exit 0
else
   echo -e "`date +%F\ %T`:  Attention: Primary db is not health!" >> $MONITOR_LOG
   exit 1
fi

  
