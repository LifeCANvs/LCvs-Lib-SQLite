#!/usr/bin/tclsh
#
# Run this script using TCLSH to do a speed comparison between
# various versions of SQLite and PostgreSQL and MySQL
#

# Run a test
#
set cnt 0
proc runtest {title sqlfile} {
  global cnt
  incr cnt
  puts "<h2>Test $cnt: $title</h2>"
  set fd [open $sqlfile r]
  set sql [string trim [read $fd [file size $sqlfile]]]
  close $fd
  set sx [split $sql \n]
  set n [llength $sx]
  if {$n>8} {
    set sql {}
    for {set i 0} {$i<3} {incr i} {append sql [lindex $sx $i]<br>\n}
    append sql  "<i>... [expr {$n-6}] lines omitted</i><br>\n"
    for {set i [expr {$n-3}]} {$i<$n} {incr i} {
      append sql [lindex $sx $i]<br>\n
    }
  } else {
    regsub -all \n [string trim $sql] <br> sql
  }
  puts "<blockquote>"
  puts "$sql"
  puts "</blockquote><table border=0 cellpadding=0 cellspacing=5>"
  set format {<tr><td>%s</td><td align="right">%.3f</td></tr>}
  set t [time "exec psql drh <$sqlfile" 1]
  set t [expr {[lindex $t 0]/1000000.0}]
  puts [format $format PostgreSQL: $t]
  set t [time "exec mysql drh <$sqlfile" 1]
  set t [expr {[lindex $t 0]/1000000.0}]
  puts [format $format MySQL: $t]
#  set t [time "exec ./sqlite232 s232.db <$sqlfile" 1]
#  set t [expr {[lindex $t 0]/1000000.0}]
#  puts [format $format {SQLite 2.3.2:} $t]
#  set t [time "exec ./sqlite-100 s100.db <$sqlfile" 1]
#  set t [expr {[lindex $t 0]/1000000.0}]
#  puts [format $format {SQLite 2.4 (cache=100):} $t]
  set t [time "exec ./sqlite240 s2k.db <$sqlfile" 1]
  set t [expr {[lindex $t 0]/1000000.0}]
  puts [format $format {SQLite 2.4 (cache=2000):} $t]
  set t [time "exec ./sqlite240 sns.db <$sqlfile" 1]
  set t [expr {[lindex $t 0]/1000000.0}]
  puts [format $format {SQLite 2.4 (nosync):} $t]
  puts "</table>"
}

# Initialize the environment
#
expr srand(1)
catch {exec /bin/sh -c {rm -f s*.db}}
set fd [open clear.sql w]
puts $fd {
  drop table t1;
  drop table t2;
}
close $fd
catch {exec psql drh <clear.sql}
catch {exec mysql drh <clear.sql}
set fd [open 2kinit.sql w]
puts $fd {PRAGMA cache_size=2000; PRAGMA synchronous=on;}
close $fd
exec ./sqlite240 s2k.db <2kinit.sql
set fd [open nosync-init.sql w]
puts $fd {PRAGMA cache_size=2000; PRAGMA synchronous=off;}
close $fd
exec ./sqlite240 sns.db <nosync-init.sql
set ones {zero one two three four five six seven eight nine
          ten eleven twelve thirteen fourteen fifteen sixteen seventeen
          eighteen nineteen}
set tens {{} ten twenty thirty forty fifty sixty seventy eighty ninety}
proc number_name {n} {
  if {$n>=1000} {
    set txt "[number_name [expr {$n/1000}]] thousand"
    set n [expr {$n%1000}]
  } else {
    set txt {}
  }
  if {$n>100} {
    append txt " [lindex $::ones [expr {$n/100}]] hundred"
    set n [expr {$n%100}]
  }
  if {$n>19} {
    append txt " [lindex $::tens [expr {$n/10}]]"
    set n [expr {$n%10}]
  }
  if {$n>0} {
    append txt " [lindex $::ones $n]"
  }
  set txt [string trim $txt]
  if {$txt==""} {set txt zero}
  return $txt
}

# TEST 1
#
set fd [open test1.sql w]
puts $fd "CREATE TABLE t1(a INTEGER, b INTEGER, c VARCHAR(100));"
for {set i 1} {$i<=1000} {incr i} {
  set r [expr {int(rand()*100000)}]
  puts $fd "INSERT INTO t1 VALUES($i,$r,'[number_name $r]');"
}
close $fd
runtest {1000 INSERTs} test1.sql

# TEST 2
#
set fd [open test2.sql w]
puts $fd "BEGIN;"
puts $fd "CREATE TABLE t2(a INTEGER, b INTEGER, c VARCHAR(100));"
for {set i 1} {$i<=25000} {incr i} {
  set r [expr {int(rand()*500000)}]
  puts $fd "INSERT INTO t2 VALUES($i,$r,'[number_name $r]');"
}
puts $fd "COMMIT;"
close $fd
runtest {25000 INSERTs in a transaction} test2.sql

# TEST 3
#
set fd [open test3.sql w]
for {set i 0} {$i<100} {incr i} {
  set lwr [expr {$i*100}]
  set upr [expr {($i+10)*100}]
  puts $fd "SELECT count(*), avg(b) FROM t2 WHERE b>=$lwr AND b<$upr;"
}
close $fd
runtest {100 SELECTs without an index} test3.sql

# TEST 4
#
set fd [open test4.sql w]
puts $fd {CREATE INDEX i2a ON t2(a);}
puts $fd {CREATE INDEX i2b ON t2(b);}
close $fd
runtest {Creating an index} test4.sql

# TEST 5
#
set fd [open test5.sql w]
for {set i 0} {$i<5000} {incr i} {
  set lwr [expr {$i*100}]
  set upr [expr {($i+1)*100}]
  puts $fd "SELECT count(*), avg(b) FROM t2 WHERE b>=$lwr AND b<$upr;"
}
close $fd
runtest {5000 SELECTs with an index} test5.sql

# TEST 6
#
set fd [open test6.sql w]
puts $fd "BEGIN;"
for {set i 0} {$i<100} {incr i} {
  set lwr [expr {$i*10}]
  set upr [expr {($i+1)*10}]
  puts $fd "UPDATE t1 SET b=b*2 WHERE a>=$lwr AND a<$upr;"
}
puts $fd "COMMIT;"
close $fd
runtest {100 UPDATEs without an index} test6.sql


# TEST 7
set fd [open test7.sql w]
puts $fd "BEGIN;"
for {set i 1} {$i<=25000} {incr i} {
  puts $fd "UPDATE t2 SET b=b+a WHERE a=$i;"
}
puts $fd "COMMIT;"
close $fd
runtest {25000 UPDATEs with an index} test7.sql

# TEST 8
set fd [open test8.sql w]
puts $fd "BEGIN;"
puts $fd "INSERT INTO t1 SELECT * FROM t2;"
puts $fd "INSERT INTO t2 SELECT * FROM t1;"
puts $fd "COMMIT;"
close $fd
runtest {INSERTs from a SELECT} test8.sql

# TEST 9
#
set fd [open test9.sql w]
puts $fd {DELETE FROM t2 WHERE c LIKE '%fifty%';}
close $fd
runtest {DELETE without an index} test9.sql

# TEST 10
#
set fd [open test10.sql w]
puts $fd {DELETE FROM t2 WHERE a>10 AND a<20000;}
close $fd
runtest {DELETE with an index} test10.sql

# TEST 11
#
set fd [open test11.sql w]
puts $fd {INSERT INTO t2 SELECT * FROM t1;}
close $fd
runtest {A big INSERT after a big DELETE} test11.sql

# TEST 12
#
set fd [open test12.sql w]
puts $fd {BEGIN;}
puts $fd {DELETE FROM t1;}
for {set i 1} {$i<=1000} {incr i} {
  set r [expr {int(rand()*100000)}]
  puts $fd "INSERT INTO t1 VALUES($i,$r,'[number_name $r]');"
}
puts $fd {COMMIT;}
close $fd
runtest {A big DELETE followed by many small INSERTs} test12.sql

# TEST 13
#
set fd [open test13.sql w]
puts $fd {DROP TABLE t1;}
puts $fd {DROP TABLE t2;}
close $fd
runtest {DROP TABLE} test13.sql
