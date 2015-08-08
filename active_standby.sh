#/bin/bash

# 环境变量
export PGPORT=1921
export PGUSER=sky_pg_cluster
export PG_OS_USER=pg94
export PGDBNAME=sky_pg_cluster
export PGDATA=/opt/database/pg94/pg_root
export LANG=en_US.utf8
export PGHOME=/opt/pgsql
export LD_LIBRARY_PATH=$PGHOME/lib:/lib64:/usr/lib64:/usr/local/lib64:/lib:/usr/lib:/usr/local/lib
export PATH=/opt/pgbouncer/bin:$PGHOME/bin:$PGPOOL_HOME/bin:$PATH:.

# 配置信息, LAG_MINUTES 配置允许的延迟时间
LAG_MINUTES=3
HOST_IP=`hostname -i`
NOTICE_EMAIL="francs3@163.com"
FAILOVE_LOG='/tmp/failover.log'

SQL1="select 'this_is_standby' as cluster_role from ( select pg_is_in_recovery() as std ) t where t.std is true;"
SQL2="select 'standby_in_allowed_lag' as cluster_lag from cluster_status where now()-last_alive < interval '$LAG_MINUTES min';"

# 配置 fence 设备地址和用户密码
FENCE_IP=192.168.1.21
FENCE_USER=xxxx
FENCE_PWD=xxxx

# VIP 已发生漂移，记录到日志文件
echo -e "`date +%F\ %T`: keepalived VIP switchover!" >> $FAILOVE_LOG

# VIP 已漂移，邮件通知
#echo -e "`date +%F\ %T`: ${HOST_IP}/${PGPORT} VIP 发生漂移，需排查问题！\n\nAuthor: francs(DBA)" | mutt -s "Error: 数据库 VIP 发生漂移 " ${NOTICE_EMAIL}


# pg_failover 函数，用于主库故障时激活从库
pg_failover()
{
# FENCE_STATUS 表示 fence 后成功标志，1 表示失败，0 表示成功
# PROMOTE_STATUS 表示激活备库成功标志，1 表示失败，0 表示成功
FENCE_STATUS=1
PROMOTE_STATUS=1

# 激活备库前需 Fence 关闭主库
for ((k=0;k<10;k++))
do
# fence命令, 设备不同的话, fence命令可能不一样.
  ipmitool -I lanplus -L OPERATOR -H $FENCE_IP -U $FENCE_USER -P $FENCE_PWD power reset
  if [ $? -eq 0 ]; then
    echo -e "`date +%F\ %T`: fence primary db host success."
    FENCE_STATUS=0
    break
  fi
sleep 1
done

if [ $FENCE_STATUS -ne 0 ]; then
  echo -e "`date +%F\ %T`: fence failed. Standby will not promote, please fix it manually."
return $FENCE_STATUS
fi

# 激活备库
su - $PG_OS_USER -c "pg_ctl promote"
if [ $? -eq 0 ]; then
   echo -e "`date +%F\ %T`: `hostname` promote standby success. " 
   PROMOTE_STATUS=0
fi

if [ $PROMOTE_STATUS -ne 0 ]; then
  echo -e "`date +%F\ %T`: promote standby failed."
  return $PROMOTE_STATUS
fi

 echo -e "`date +%F\ %T`: pg_failover() function call success."
 return 0
}


# 故障切换过程
# standby是否正常的标记(is in recovery), CNT=1 表示正常.
CNT=`echo $SQL1 | psql -At -h 127.0.0.1 -p $PGPORT -U $PGUSER -d $PGDBNAME -f - | grep -c this_is_standby`
echo -e "CNT: $CNT"
# 判断 standby lag 是否在接受范围内的标记, LAG=1 表示正常.
LAG=`echo $SQL2 | psql -At -h 127.0.0.1 -p $PGPORT -U $PGUSER -d $PGDBNAME | grep -c standby_in_allowed_lag`
echo -e "LAG: $LAG"

if [ $CNT -eq 1 ] && [ $LAG -eq 1 ]; then
  pg_failover >> $FAILOVE_LOG
  if [ $? -ne 0 ]; then
    echo -e "`date +%F\ %T`: pg_failover failed." >> $FAILOVE_LOG
    exit 1
  fi 
else
  echo -e "`date +%F\ %T`: `hostname` standby is not ok or laged far $LAG_MINUTES mintues from primary , failover not allowed! " >> $FAILOVE_LOG
  exit 1
fi


# 判断是否要进入failover过程
# 1. standby 正常 (is in recovery)
# 2. standby lag 在接受范围内 

# failover过程
# 1. fence 关闭主服务器
# 2. 激活standby数据库
