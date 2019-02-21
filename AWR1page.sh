#!/usr/bin/awk -f
#
# AWR1page: check time consistency of AWR reports
#
# 1/ get and convert times to AAS=Avg Active Sessions
# 2/ organize by data source (cols) and measurement (rows) 
# 3/ TODO: check for known symptoms of issues
#
BEGIN {
  _abort = 0   # flag used to signal abort in END
  secsep = "=========================================="
  ASHsamplesecs = 10  # seconds for eash ASH sample
  NA = "N/A"   # data not available 
}
{
# data prep for funny files
gsub(/\r/,"",$0) # remove Windows ctl-M chars
gsub(/\f/,"",$0) # remove Windows ctl-L chars
}
####################################################
# Main program: 
# check for section header and call
# section-specific function
#
# OS Stats
$0 ~ "^Operating System Statistics" && $0 !~ /Detail/ {
  osstat()
}
# OS Stats - Detail (get LOAD per snap)
$0 ~ "^Operating System Statistics - Detail" {
  osload()
}
# Time Model
$0 ~ "^Time Model Statistics" {
  timemodel()
}
# Foreground Wait Class times
$0 ~ "^Foreground Wait Class" {
  fgwaitclass()
}
# Wait Class times
$0 ~ "^Wait Classes by Total Wait Time" {
  waitclass()
}
# ASH activity over time (BG and FG together)
$0 ~ "^Activity Over Time" {
  ashtime()
}
# basic INFO from top section of report
$0 ~ "^WORKLOAD REPOSITORY report" {
  baseinfo()
}
# some miscellaneous items
$0 ~ "^user calls" && NF == 5 {
  calls = $3; gsub(/,/,"",calls);
  MISC["user calls"] = calls
}
#
#####################################
# data scraping functions
#
# build OSSTAT data array
function osstat() {
  printIfdump("**loading: OSSTAT")
  while ($0 !~ "^Statistic") {getlineM()}  # skip to table header
  getlineM();getlineM()                       # skip to table data
  while (NF > 1) {
    if ($2 ~ "[0-9,]+") { gsub(/,/,"",$2) } # de-comma numbers 
    OSSTAT[$1] = $2                     # array of values
    getlineM()
  }
  # convert all _TIME values to seconds (from centi-seconds)
  for (key in OSSTAT) {
    if (key ~ /_TIME$/) {OSSTAT[key]=OSSTAT[key]/100}
  }
}
# Host load per snapshot
function osload(tot, count, avg, got, val) {
  printIfdump("**loading: OSLOAD")
  while ($0 !~ "^Snap Time") {getlineM()}  # skip to table header
  getlineM();getlineM()
  tot = 0; count = 0; avg = 0           # initialize summary data
  while (NF > 1) {
    got = match($0,"^[0-9]*-[A-Za-z ]*[0-9]*:[0-9]*:[0-9]*") # DATE field
    if (got > 0) {
      key = substr($0,RSTART,RLENGTH)
      val = $3; gsub(/,/,"",val)    # date in $1 and $2, remove commas
      OSLOAD[key] = val
      tot += val; count += 1
    }
    getlineM()
  }
  if (count > 0) {avg = tot / count} else {avg = -1} # -1 = null
  OSLOAD["AVERAGE"] = avg               # avgerage load row
}
# Time Model data array
function timemodel(got, tmkey, tmval) {
  printIfdump("**loading: TIMEMODEL")
  while ($0 !~ "^Statistic Name") {getlineM()} # skip to table head
  getlineM();getlineM()
  while (NF > 1) {
    got = match($0,"^[a-zA-Z /()]+")
    if (got > 0) {
      tmkey = substr($0,RSTART,RLENGTH)  # key string
      gsub(/[ \t]+$/,"",tmkey)       # trim trailing whitespace     
      got = match($0,"[0-9.,]+")     # find first numeric - time in secs
      if (got > 0) {
        tmval = substr($0,RSTART,RLENGTH)
        TIMEMODEL[tmkey] = tmval
      }
    }
    getlineM()
  }
  decomma(TIMEMODEL)
}
# FG wait class time array
function fgwaitclass(got, fwkey, chunk, t_beg, fwval, tot) {
  printIfdump("**loading: FGWAITCLASS")
  while ($0 !~ "^Wait Class") {getlineM()}
  got = match($0,/Time \(s\)/)   # find fixed position of time field
  if (got > 0) {t_beg = RSTART+RLENGTH - 15} 
     else {print $0;abort("fgwaitclass:1")}  # could not locate time field position
  getlineM();getlineM()
  tot = 0                              # initialize
  while (NF > 1) {
    if ($0 ~ "^DB CPU") {getlineM()}      # skip, in time model data
    got = match($0,"^[A-Za-z \/]+")
    if (got > 0) {
      fwkey = substr($0,RSTART,RLENGTH) # key
      gsub(/[ \t]+$/,"",fwkey)       # trim trailing whitespace     
      chunk = substr($0, t_beg,15)   # get substring time value
      got = match(chunk,"[0-9\.,]+")
      if (got > 0) {fwval = substr(chunk,RSTART,RLENGTH); gsub(/,/,"",fwval)} # de-comma
        else {abort("fgwaitclass:2")}
      FGWAITCLASS[fwkey] = fwval
      tot += fwval             # increment total time
    } 
    getlineM()
  }
  FGWAITCLASS["TOTAL"] = tot   # add total time to array
  FGWAITCLASS["TOTAL I/O"] = FGWAITCLASS["System I/O"]+FGWAITCLASS["User I/O"]+0 # add I/O values
}
# Wait class (all) time array
function waitclass(got, wkey, chunk, t_beg, wval, tot) {
  printIfdump("**loading: WAITCLASS")
  while ($0 !~ "^Wait Class ") {getlineM()}
  got = match($0,/Time \(sec\)/)   # find fixed position of time field
  if (got > 0) {t_beg = RSTART+RLENGTH - 15} 
     else {print got; print $0;abort("waitclass:1")}  # could not locate time field position
  getlineM();getlineM()
  tot = 0                              # initialize
  while (NF > 1) {
    if ($0 ~ "^DB CPU") {getlineM()}      # skip, in time model data
    got = match($0,"^[A-Za-z \/]+")
    if (got > 0) {
      wkey = substr($0,RSTART,RLENGTH) # key
      gsub(/[ \t]+$/,"",wkey)       # trim trailing whitespace     
      chunk = substr($0, t_beg,15)   # get substring time value
      got = match(chunk,"[0-9\.,]+")
      if (got > 0) {wval = substr(chunk,RSTART,RLENGTH); gsub(/,/,"",wval)} # de-comma
        else {abort("waitclass:2")}
      WAITCLASS[wkey] = wval
      tot += wval             # increment total time
    } 
    getlineM()
  }
  WAITCLASS["TOTAL"] = tot   # add total time to array
  WAITCLASS["TOTAL I/O"] = WAITCLASS["System I/O"]+WAITCLASS["User I/O"]+0 # add I/O values
}
# ASH activity over time
function ashtime(got,slotC_b,slotC_e,event_b,event_e,totsecs,slotcount,eventcount,chunk \
         ,ashval,ashkey,noncpu) {
  printIfdump("**loading: ASHTIME")
  while ($0 !~ "^Slot Time") {getlineM()}    # move to table header line
  got = match($0,"Count")
  if (got > 0) {slotC_b = RSTART-3; slotC_e = RLENGTH+3} # slot count bounds
    else {abort("ashtime:1")}               # should not happen
  got = match($0,"Event[ ]+Count")   # event + event count bounds
  if (got > 0) {event_b = RSTART; event_e = RLENGTH}
    else {abort("ashtime:2")}               # also should not happen
  getlineM();getlineM()                           # move to first row in table
  totsecs = 0; slotcount = 0; eventcount = 0
  while (NF > 1) {
    got = match($0,"\([0-9\.]+ min\)")      # find slot durations in min
    if (got > 0) {
      chunk = substr($0,RSTART,RLENGTH)     # slot duration text chunk
      got = match(chunk,"[0-9\.,]+")         # find the time (min)
        if (got > 0) {
          mins = substr(chunk,RSTART,RLENGTH); gsub(/,/,"",mins) # de-comma
          totsecs += mins*60
        }
        else {abort("ashtime:3")}   # should not happen unless slots not in mins
    }
    # slot count
    chunk = substr($0,slotC_b,slotC_e) # process slot count chunk
    gsub(/,/,"",chunk)                 # de-comma
    got = match(chunk,"[0-9]+")
    if (got > 0) {
      slotcount += substr(chunk,RSTART,RLENGTH) # count slot samples  
    }
    # event name
    chunk = substr($0,event_b,event_e)
    got = match(chunk,"[A-Za-z \(\)\+\-]+")  # find event name
    if (got > 0) {
      ashkey = substr(chunk,RSTART,RLENGTH) # get event name
      gsub(/[ \t]+$/,"",ashkey)       # trim trailing whitespace
    }
    else {abort("ashtime:4")}        # should not happen
    # event count
    got = match(chunk,/[0-9]+$/)
    if (got > 0) {
      ashval = substr(chunk,RSTART,RLENGTH)
      ASHTIME[ashkey] += ashval*ASHsamplesecs    # add time in secs to event 
      eventcount += ashval                       # increment event count
    }
    else {abort("ashtime:5")}
  getlineM()
  }
  # add other event seconds and ASH elapsed to array
  ASHTIME["other events"] = (slotcount - eventcount)*ASHsamplesecs
  # compute sum of non-CPU sample time
  for (ashkey in ASHTIME) {if (ashkey !~ /CPU/) {noncpu += ASHTIME[ashkey]} }
  # add non-CPU and total elapsed to ASH array
  ASHTIME["NON CPU"] = noncpu  
  ASHTIME["ASH ELAPSED"] = totsecs
}

# Baisc info from top section of AWR report
function baseinfo(got, platform, InstStart, elap, dbtime) {
  printIfdump("**loading: BASEINFO")
  while ($0 !~ "^DB Name") {getlineM()}
  # position to first data row
  getlineM();getlineM()
  # first group of positional values, should be easy
  if ($2 ~ /[0-9]+/) {BASEINFO["DB ID"] = $2} else {abort("baseinfo:1")}
  if ($4 ~ /[0-9]?[0-9]/) {BASEINFO["Inst Num"] = $4} else {abort("baseinfo:2")}
  if ($8 ~ /(YES|NO)/) {BASEINFO["RAC"] = $8} else {abort("baseinfo:2.1")}
  InstStart = $5" "$6;
  if (InstStart ~ /[0-9]+-[A-Z][a-z]+-[0-9]+ [0-9]+:[0-9]+/) {
    BASEINFO["Inst Start"] = InstStart
  } 
  else {abort("baseinfo:3")
  }
  if ($7 ~ /[0-9\.]+/) {BASEINFO["Release"] = $7} else {abort("baseinfo:4")}
  # find the platform field
  while ($0 !~ /^Host Name/) {getlineM()} # go to next header line
  got = match($0,"Platform")
  if (got > 0) {getlineM();getlineM()} else {abort("baseinfo:5")}
  platform = substr($0,RSTART,35)  # use RSTART from "Platform" match
  gsub(/[ \t]+$/,"",platform);
  BASEINFO["Platform"] = platform
  #
  while ($0 !~ /Begin Snap:/) {getlineM()}  # move to next line of data
  if ($0 ~ /Begin Snap:/) {
    BASEINFO["Begin Snap"] = $3
    BASEINFO["Begin Sessions"] = $6
    getlineM()
  }
  else {abort("baseinfo:6")\
  }
  if ($0 ~ /End Snap:/) {
    BASEINFO["End Snap"] = $3
    BASEINFO["End Sessions"] = $6
    getlineM()
  }
  else {abort("baseinfo:7")
  }
  # get elapsed time in seconds
  if ($1 ~ /Elapsed:/ && $3 ~ /(mins)/) {
    elap = $2; gsub(/,/,"",elap);       # de-comma
    BASEINFO["Elapsed Time"] = elap * 60  # 60 seconds/min
    getlineM()
  }
  else {abort("baseinfo:8")
  } 
  # get DB Time (redundant with Time Model data
  if ($0 ~ /DB Time:/ && $4 ~ /(mins)/) {
    dbtime = $3; gsub(/,/,"",dbtime)    # de-comma
    BASEINFO["DB Time"] = dbtime * 60  # 60 seconds/min
  }
  else {abort("baseinfo:9")
  }
}
#########################################
# the report function
#
function report( tmd_exists \
, ash_exists \
, wtc_exists \
, fgw_exists \
, osl_exists \
, oss_exists \
, bsi_exists \
, msc_exists \
, bsi_elapsed \
, bsi_platform \
, bsi_release \
, bsi_rac    \
, bsi_snaps \
, bsi_endsess \
, bsi_elapmin \
, oss_cores \
, oss_cpus \
, oss_threads \
, oss_oscpu \
, oss_usrcpu \
, oss_syscpu \
, oss_iowait \
, oss_cpuwait \
, oss_rmcpu \
, tmd_totaas \
, tmd_totcpu \
, tmd_fgcpu \
, tmd_bgcpu \
, tmd_totwait \
, tmd_bgwait \
, tmd_fgwait \
, osl_load \
,   wtc_totwait \
,   wtc_bgwait \
,   wtc_iowait \
,   wtc_schwait \
, fgw_totwait \
, fgw_totio \
,   ash_elapsed \
,   ash_totaas \
,   ash_cpu \
,   ash_wait \
,    msc_usrcalls \
,    mc_oss \
,    mc_tmd \
,    mc_ash \
,    mc_usrcallsec ) 
{
  # BEGIN function
  # some formatting variables
  rptline = "===================="
  rptline = rptline rptline rptline rptline rptline rptline
  dotline = rptline
  gsub("=",".",dotline)
  cols = "%-40s%-20s%-20s%-20s%-20s"
  col2 = "%-100s%-20s"
  percore = "[%.2f:%.2f]"

  # boolean test variables to detect missing sections, FALSE (0)
  # when the corresponding sections have not been entered
  tmd_exists = length(TIMEMODEL)
  ash_exists = length(ASHTIME)
  wtc_exists = length(WAITCLASS)
  fgw_exists = length(FGWAICLASS)
  osl_exists = length(OSSLOAD)
  oss_exists = length(OSSTAT)
  bsi_exists = length(BASEINFO)
  msc_exists = length(MISC)

  # establish report variables by source array
  # BASEINFO
  bsi_elapsed  = BASEINFO["Elapsed Time"]
  bsi_platform = BASEINFO["Platform"]
  bsi_release  = BASEINFO["Release"]
  bsi_rac      = BASEINFO["RAC"]
  bsi_snaps    = BASEINFO["End Snap"] - BASEINFO["Begin Snap"]
  bsi_endsess  = BASEINFO["End Sessions"]
  bsi_elapmin  = bsi_elapsed/60
  
  # OSSTAT
  oss_cores = OSSTAT["NUM_CPU_CORES"]
  oss_cpus  = OSSTAT["NUM_CPUS"]
  oss_threads = oss_cpus/oss_cores
  oss_oscpu = OSSTAT["BUSY_TIME"]/bsi_elapsed  # AAS
  oss_usrcpu = OSSTAT["USER_TIME"]/bsi_elapsed # AAS
  oss_syscpu = OSSTAT["SYS_TIME"]/bsi_elapsed  # AAS
  oss_iowait = OSSTAT["IOWAIT_TIME"]/bsi_elapsed # AAS

  if (oss_cores >0) {CORES = oss_cores}  # CORES is globally available, used by Fpercore 

  # conditional vals not in all reports
  if (OSSTAT["OS_CPU_WAIT_TIME"] == "") {oss_cpuwait = "N/A"}
  else {oss_cpuwait = OSSTAT["OS_CPU_WAIT_TIME"]/bsi_elapsed} # AAS

  if (OSSTAT["RSRC_MGR_CPU_WAIT_TIME"] == "") {oss_rmcpu = "N/A"}
  else {oss_rmcpu = OSSTAT["RSRC_MGR_CPU_WAIT_TIME"]/bsi_elapsed} # AAS

  # TIMEMODEL
  tmd_totaas = (TIMEMODEL["background elapsed time"]+TIMEMODEL["DB time"])/bsi_elapsed # AAS
  tmd_totcpu = (TIMEMODEL["DB CPU"]+TIMEMODEL["background cpu time"])/bsi_elapsed   # AAS
  tmd_fgcpu = TIMEMODEL["DB CPU"]/bsi_elapsed               # AAS
  tmd_bgcpu = TIMEMODEL["background cpu time"]/bsi_elapsed # AAS

  # time model total cpu missing sometimes so use BG + FG for total cpu
  tmd_totwait = ((TIMEMODEL["background elapsed time"]+TIMEMODEL["DB time"]) - \
                 (TIMEMODEL["DB CPU"]+TIMEMODEL["background cpu time"]))/bsi_elapsed # AAS

  tmd_bgwait = (TIMEMODEL["background elapsed time"] - TIMEMODEL["background cpu time"])/bsi_elapsed # AAS
  tmd_fgwait = (TIMEMODEL["DB time"] - TIMEMODEL["DB CPU"])/bsi_elapsed  #AAS

  # OSLOAD
  osl_load = OSLOAD["AVERAGE"]

  # WAITCLASS (data not in all AWR reports)
  if (wtc_exists) {
    wtc_totwait = WAITCLASS["TOTAL"]/bsi_elapsed # AAS
    wtc_bgwait = (WAITCLASS["TOTAL"] - FGWAITCLASS["TOTAL"])/bsi_elapsed # AAS, derived from 2 sources
    wtc_iowait = WAITCLASS["TOTAL I/O"]/bsi_elapsed  # AAS
    wtc_schwait = WAITCLASS["Scheduler"]/bsi_elapsed # ASS
  }
  else {
    wtc_totwait = NA
    wtc_bgwait = NA
    wtc_iowait = NA
    wtc_schwait = NA
  }

  # FGWAITCLASS
  fgw_totwait = FGWAITCLASS["TOTAL"]/bsi_elapsed # AAS
  fgw_totio = FGWAITCLASS["TOTAL I/O"]/bsi_elapsed # AAS

  # ASHTIME (data not in all AWR reports)
  if (ash_exists) {
    ash_elapsed = ASHTIME["ASH ELAPSED"]
    ash_totaas = (ASHTIME["NON CPU"]+ASHTIME["CPU + Wait for CPU"])/ash_elapsed # AAS
    ash_cpu = ASHTIME["CPU + Wait for CPU"]/ash_elapsed   # AAS
    ash_wait = ASHTIME["NON CPU"]/ash_elapsed # AAS
  }
  else {
    ash_elapsed = NA
    ash_totaas  = NA
    ash_cpu = NA
    ash_wait = NA
  }

  # MISC array and derived mc_ (micro-call) values
  if (msc_exists) {
    msc_usrcalls = MISC["user calls"]
    mc_oss = 1000*OSSTAT["BUSY_TIME"]/msc_usrcalls          # convert to milliseconds
    mc_tmd = 1000*tmd_totcpu/msc_usrcalls
    mc_usrcallsec = msc_usrcalls/bsi_elapsed 
    if (ash_exists ) {
      mc_ash = 1000*ASHTIME["CPU + Wait for CPU"]/msc_usrcalls
    }
    else {mc_ash = NA }  # if no ASH data
   }
   else {
     msc_usrcalls = NA
     mc_oss = NA
     mc_tmd = NA
     mc_ash = NA
     mc_usrcallsec = NA
   }
  
  #
  # format and print report lines
  # 
  print "\nAWR1page\n"
  line = sprintf("%-120s","    file: "basename(FILENAME))
  print line
  line = sprintf(col2,"platform: "bsi_platform,"        cores: "oss_cores) 
  print line
  line = sprintf(col2,"     RAC: "bsi_rac,"         cpus: "oss_cpus)
  print line
  line = sprintf(col2," release: "bsi_release," threads/core: "oss_threads)
  print line
  bsi_elapmin = sprintf("%.2f",bsi_elapmin)
  line = sprintf(col2," elapsed: "bsi_elapmin" (min)","sessions(end): "bsi_endsess)
  print line
  print "   snaps: "bsi_snaps"\n\n"
  print rptline
  # header line of report
  line = sprintf(cols, "               measure", "|      OSSSTAT", \
                       "|    TIME MODEL","|       ASH", \
                       "|    WAIT CLASS")
  print line ; print rptline
  # HOST line
  osl_load = Fpercore(osl_load)
  line = sprintf(cols,"HOST      LOAD"," "osl_load,"","","")
  print line"\n"
  # CPU BUSY line
  oss_oscpu = Fpercore(oss_oscpu)
  line = sprintf(cols,"               CPU BUSY","     "oss_oscpu,"","","")
  print line
  # USER and SYS lines
  oss_usrcpu = sprintf("%.2f",oss_usrcpu)
  line = sprintf(cols,"                         USER","              "oss_usrcpu,"","","")
  print line
  oss_syscpu = sprintf("%.2f",oss_syscpu)
  line = sprintf(cols,"                          SYS","              "oss_syscpu,"","","")
  print line"\n"
  # IOWAIT and OS_CPU_WAIT
  oss_iowait = Fpercore(oss_iowait)
  line = sprintf(cols,"               IOWAIT","     "oss_iowait,"","","")
  print line
  oss_cpuwait = Fpercore(oss_cpuwait)
  line = sprintf(cols,"               OS_CPU_WAIT","     "oss_cpuwait,"","","")
  print line
  print dotline
  # ORACLE section
  line = sprintf(cols,"ORACLE","","","",""); print line
  # AVG ACTIVE SESSIONS
  tmd_totaas = Fpercore(tmd_totaas)
  ash_totaas = Fpercore(ash_totaas)
  line = sprintf(cols,"AVERAGE ACTIVE SESSIONS (BG+FG)",""," "tmd_totaas," "ash_totaas,"")
  print line"\n"
  # ORA CPU
  tmd_totcpu = Fpercore(tmd_totcpu)
  ash_cpu = Fpercore(ash_cpu)
  line = sprintf(cols,"               CPU","","     "tmd_totcpu,"     "ash_cpu,"")
  print line
  # FG + BG CPU detail
  tmd_fgcpu = sprintf("%.2f",tmd_fgcpu)
  tmd_bgcpu = sprintf("%.2f",tmd_bgcpu)
  line = sprintf(cols,"                    FG","","              "tmd_fgcpu,"","")
  print line
  line = sprintf(cols,"                    BG","","              "tmd_bgcpu,"","")
  print line
  # Res Mgr CPU wait from OSSSTAT
  if (oss_rmcpu != "N/A") {oss_rmcpu = sprintf("%.2f",oss_rmcpu)}
  line = sprintf(cols,"                    RSRC_MGR_CPU_WAIT","              "oss_rmcpu,"","","")
  print line"\n"
  # WAIT section
  tmd_totwait = Fpercore(tmd_totwait)
  ash_wait = Fpercore(ash_wait)
  wtc_totwait = Fpercore(wtc_totwait)
  #
  line = sprintf(cols,"               WAIT","","     "tmd_totwait,"     "ash_wait,"     "wtc_totwait)
  print line
  # FG and BG wait breakdown
  tmd_fgwait = sprintf("%.2f",tmd_fgwait)
  fgw_totwait = sprintf("%.2f",fgw_totwait)
  line = sprintf(cols,"                    FG","","              "tmd_fgwait,"","              "fgw_totwait)
  print line
  tmd_bgwait = sprintf("%.2f",tmd_bgwait)
  if (wtc_bgwait != "N/A") {
    wtc_bgwait = sprintf("%.2f",wtc_bgwait) # asterisk denotes derived value
  }
  line = sprintf(cols,"                    BG","","              "tmd_bgwait,"","             *"wtc_bgwait)
  print line
  if (wtc_iowait != "N/A") {
    wtc_iowait = sprintf("%.2f",wtc_iowait)
  }
  fgw_totio = sprintf("%.2f",fgw_totio)
  line = sprintf(cols,"                    IOWAIT","","","","          "wtc_iowait)
  print line
  line = sprintf(cols,"                          FG","","","","              "fgw_totio)
  print line
  if (wtc_schwait != "N/A") {
    wtc_schwait = sprintf("%.2f",wtc_schwait)
  }
  line = sprintf(cols,"                    Scheduler","","","", "          "wtc_schwait)
  print line
  print dotline
  line = sprintf(cols,"MISC","","","","")
  print line
  if (msc_exists) {
    if (ash_exists) {
      mc_ash = sprintf("%.2f",mc_ash);
    }
    mc_oss = sprintf("%.2f",mc_oss);
    mc_tmd = sprintf("%.2f",mc_tmd);
  }
  line = sprintf(cols,"          CPU per call (ms)","            "mc_oss,"             "mc_tmd,"             "mc_ash,"")
  print line
  mc_usrcallsec = sprintf("%.2f",mc_usrcallsec)
  line = sprintf(cols,"             user calls/sec",mc_usrcallsec,"","","")
  print line"\n"
}
#########################################
# utility functions
#
# special getline that removes ctl-M (Windows)
function getlineM(x) {
  getline;
  x = gsub(/\r/,"",$0)
}
# abort with message
function abort(msg) {
  _abort = 1; print "abort: "msg; exit
}
# print array for debugging
# added check for null-key issues, print MISSING!!
function printArray(Array,Name) {
  print Name
  for (key in Array) {
    if (Array[key] == "") {
      printf("%42s\t%35s\n", ":"key":","MISSING!!")
    }
    else { printf("%42s\t%35s\n", ":"key":",Array[key])}
  }
  print secsep
}
# remove commas from all values in array
function decomma(Array) {
  for (key in Array) 
    gsub(/,/,"",Array[key])
}
# print message if dumping data, used for data load fcns
function printIfdump(msg) {
  if (dump == "true") {print msg}
}
# basename function found on StackOverflow
function basename(file, a, n) {
    n = split(file, a, "/")
    return a[n]
}
# format per-core entries
function Fpercore(value, percore) {
  percore = "[%.2f:%.2f]"
  if (value != "N/A") {
    value = sprintf(percore,value,value/CORES) # format using CORES global
  }
  return value
}
# dump the data arrays
function dumpdata() {
  # first run report in case it extends arrays
  report()
  print "dumping data for file: "basename(FILENAME)
  print secsep
  printArray(BASEINFO,"BASEINFO (secs for DB/elapsed time)")
  printArray(OSSTAT,"OSSTAT (secs for _TIME vals)")
  printArray(OSLOAD,"OSLOAD")
  printArray(TIMEMODEL,"TIMEMODEL (secs)")
  printArray(FGWAITCLASS,"FGWAITCLASS (secs)")
  printArray(WAITCLASS,"WAITCLASS (secs)")
  printArray(ASHTIME,"ASHTIME (secs)")
  printArray(MISC,"MISC")
}
END {
  if (_abort == 1) {exit}  # exit in main branches to END, need to exit again
  # debug: dump data arrays
  if (dump == "true") {
    dumpdata()           # dumpdata if asked, or do report
  }
  else {report()}
}
