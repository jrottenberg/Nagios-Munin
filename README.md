

Check servers state via munin generated RRDs data
=================================================


Setup 
-----


1. Add a new command in nagios 

      # check munin ###  module / warn / crit  
      define command {  
          command_name    check_munin  
          command_line    $USER1$/check_munin_rrd.pl -H $HOSTNAME$ -M $ARG1$ -w $ARG2$ -c $ARG3$   
      }

1. Define services

      # check the disks  
      define service {  
          use                  generic-service  
          hostgroup_name       my_group  
          service_description  DISK_munin  
          check_command        check_munin!df!75!90  
      }
      # check the load  
      define service {  
          use                  generic-service  
          hostgroup_name       my_group  
          service_description  LOAD_munin  
          check_command        check_munin!load!4!8  
      }    


1. [Fork it][1]




[1]: git://github.com/jrottenberg/Nagios-Munin.git
