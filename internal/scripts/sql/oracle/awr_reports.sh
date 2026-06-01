#!/usr/bin/bash
#bash ./dba_oracle_awr.sh -f 20110312070000 -t 20110312090000 -p html
# ********************************
# * dba_oracle_awr.sh
# ********************************
# Usage: dba_oracle_awr.sh 
#          -f [from time]
#          -t [to time]
#          -p [report type, html or text]
#
#         time format: 'yyyymmddhh24miss'.
#         E.g 20110304170000 means 05:00:00pm, Mar 04, 2011
#
#
#
# **********************
# get parameters
# **********************
#  while getopts ":f:t:p" opt
#  do
#    case $opt in
#    f) from=$OPTARG
#       ;;
#    t) to=$OPTARG
 #      ;;
 #   p) type=$OPTARG
#       type=$(echo $type|tr "[:upper:]" "[:lower:]")
#       ;;
#   echo "$0: invalid option -$OPTARG">&2
#       exit 1
#       ;;
#    esac
#done
#if [ "$from" = "" ]
#then
#  echo "from time (-f} needed"
#  echo "program exiting..."
#  exit 1
#fi
from=$1
to=$2
type=$3
if [ "$to" = "" ]
then
  echo "to time (-t) needed"
  echo "program exiting..."
  exit 1
fi


sqlplus="${ORACLE_HOME}/bin/sqlplus"
echo $sqlplus

if [ "$type" = "" ]
then
  type="html"
fi

# ********************
# trim function
# ********************
#function trim()
#{
#  local result
#  result=`echo $1|sed 's/^ *//g' | sed 's/ *$//g'`
#  echo $result
#}


# *******************************
# get begin and end snapshot ID
# *******************************
define_dur()
{
begin_id=`$sqlplus -s / as sysdba<<EOF
  set pages 0
  set head off
  set feed off
  select max(SNAP_ID) from DBA_HIST_SNAPSHOT where
    BEGIN_INTERVAL_TIME<=to_date($from,'yyyymmddhh24miss');
EOF`

ret_code=$?
if [ "$ret_code" != "0" ]
then
  echo "sqlplus failed with code $ret_code"
  echo "program exiting..."
  exit 10
fi

end_id=`$sqlplus -s /as sysdba<<EOF
  set pages 0
  set head off
  set feed off
  select min(SNAP_ID) from DBA_HIST_SNAPSHOT where
    END_INTERVAL_TIME>=to_date($to,'yyyymmddhh24miss');
  spool off
EOF`

ret_code=$?
if [ "$ret_code" != "0" ]
then
  echo "sqlplus failed with code $ret_code"
  echo "program exiting..."
  exit 10
fi

#begin_id=$(trim ${begin_id})
#end_id=$(trim ${end_id})
# echo "begin_id: $begin_id  end_id: $end_id"
}

# *******************************
# generate AWR report
# *******************************
generate_awr()
{
  awrsql="${oracle_home}/rdbms/admin/awrrpt.sql"
  if [ ! -e $awrsql ]
  then
    echo "awrrpt.sql does not exist, exiting..."
    exit 20
  fi

  tmp1_id=${begin_id}
  #echo "begin_id is: $begin_id"
  #echo "tmp1_id is: $tmp1_id"
  while [ ${tmp1_id} -lt ${end_id} ]
  do
    let tmp2_id=${tmp1_id}+1
    tmp1_file=`$sqlplus -s /as sysdba<<EOF
  set pages 0
  set head off
  set feed off
  select to_char(END_INTERVAL_TIME,'yyyymmddhh24') from DBA_HIST_SNAPSHOT where snap_id=&tmp1_id;
  spool off
EOF`
    if [ $type = "text" ]
    then
      report_name="awrrpt_${instance}_${tmp1_file}.txt"
    else
      report_name="awrrpt_${instance}_${tmp1_file}.html"
    fi
    #echo $report_name

$sqlplus -s / as sysdba>/dev/null<<EOF
      set term off
      define report_type=$type
      define num_days=1
      define begin_snap=${tmp1_id}
      define end_snap=${tmp2_id}
      define report_name=${report_name}
      @${oracle_home}/rdbms/admin/awrrpt.sql
      exit;
EOF

    tmp1_id=${tmp2_id}
  done
}

# *******************************
# main routing
# *******************************
define_dur
generate_awr
