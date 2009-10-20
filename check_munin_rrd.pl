#!/usr/bin/perl -w
# $Id: check_munin_rrd.pl
# 2007/05/20 01:40:47
#
# check_munin_rrd.pl Copyright (C) 2007 Julien Rottenberg <julien@rottenberg.info>
#
# check_munin_rrd.pl can check various modules via rrd objects.
#
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# you should have received a copy of the GNU General Public License
# along with this program (or with Nagios);  if not, write to the
# Free Software Foundation, Inc., 59 Temple Place - Suite 330,
# Boston, MA 02111-1307, USA

# Globals
my $PROGNAME = "check_munin_rrd.pl";
use POSIX qw(strftime);
use RRDs;
use Getopt::Long;
use File::Find ();

use vars qw($opt_V $opt_v $opt_h $opt_w $opt_c $opt_h $opt_M $opt_d $opt_H $opt_D $PROGNAME);

use lib "/usr/lib64/nagios/plugins" ;
use utils qw(%ERRORS &print_revision &support &usage);

# Munin specific
my $datadir = "/var/lib/munin";
my $rrdpath = undef;
my $cf      = "AVERAGE"; # munin stores its data in this CF for the latest.

# check_munin_rrd specific
my $DEBUG       = 0;
my $REVISION    = "1.1";
my $hostname    = undef;
my $domain      = undef;
my $module      = undef;


# nagios specific
my $status          = '0';
my $problem_on_name = undef;
my $problem_value   = undef;


sub in ($$);
$ENV{'BASH_ENV'}='';
$ENV{'ENV'}='';
$ENV{'PATH'}='';
$ENV{'LC_ALL'}='C';



Getopt::Long::Configure('bundling');
GetOptions
       ("V"   => \$opt_V, "version"     => \$opt_V,
        "h"   => \$opt_h, "help"        => \$opt_h,
        "v"   => \$opt_v, "verbose"     => \$opt_v,
        "w=i" => \$opt_w, "warning=i"   => \$opt_w,
        "c=i" => \$opt_c, "critical=i"  => \$opt_c,
        "d=s" => \$opt_d, "domain=s"    => \$opt_d,
        "D=s" => \$opt_D, "datadir=s"   => \$opt_D,
        "M=s" => \$opt_M, "module=s"    => \$opt_M,
        "H=s" => \$opt_H, "hostname=s"  => \$opt_H);


# check if everything is ok
check_parameters();


## Open suggested directory
if (-d $datadir."/".$domain) {
    $rrdpath = $datadir."/".$domain;
    printf "rrdpath : $rrdpath\n" if $DEBUG;

} else {
        printf ("No such directory $datadir/$domain\n");
        exit $ERRORS{"CRITICAL"};
}

my $response_text       = '';
print "Opening $rrdpath/$hostname-$module-*-g.rrd\n" if $DEBUG;
my @rrd = <$rrdpath/$hostname-$module-*.rrd>;
printf ($#rrd+1 ." rrd(s) found\n") if  $DEBUG;

# we didn't find any rrd there...
if ($#rrd < 0) { 
    printf("\nSearch for $hostname-$module-*.rrd on $datadir\n") if $DEBUG;
    # Let's try a search before to fail
    sub wanted {
            if ( $File::Find::name =~ "$hostname-$module-([-_0-9a-z]*)\.rrd" ) {
                printf("FOUND : $File::Find::name\n") if $DEBUG;
                push (@rrd, $File::Find::name);
            }
    }            
    File::Find::find(\&wanted, $datadir); 
    if ($#rrd < 0) { 
        printf ("No such files $rrdpath/$hostname-$module-*.rrd  Are you sure the domain defined in munin is correct ?\n");
        exit $ERRORS{"CRITICAL"}; 
    }    
}

printf ($#rrd+1 ." rrd(s) found\n") if  $DEBUG;
foreach (@rrd) {
    my $current_rrd = $_;
    print "\nDoing : $current_rrd\n" if $DEBUG;
    if ($current_rrd =~ /$hostname-$module-(\w+)-[a-z]\.rrd$/im) {
        my $component = sanitize($1);  # Let's have a nicer output, 
                                    #some lines from Munin are not useful var_run for module df for example
        printf($component) if $DEBUG;
        if ($component ne "") {
            my $mtime = (stat( $current_rrd ))[9];
            printf $mtime if $DEBUG; 
            my $now_string  = time; 
            printf "\n$now_string \n" if $DEBUG;
            my $seconds_diff = $now_string - $mtime;
            if ($seconds_diff > 600) {
                my $formated_mtime = strftime "%d-%b-%Y %H:%M:%S %Z", localtime($mtime);
                print "Problem on $current_rrd : data are too old, $formated_mtime\n";
                exit $ERRORS{"UNKNOWN"};
            }
            print "Module_part : $component\n" if $DEBUG;
            my $value = get_last_rrd_data($current_rrd);
            print "$component : $value\n" if $DEBUG;
            if (($value> $opt_w) && ($status ne 2)) {
                $status = "1";
                $problem_on_name = $component;
                $problem_value = $value;
            }
            if ( $value > $opt_c){
                $status = "2";
                $problem_on_name = $component;
                $problem_value = $value;
            }
            $response_text .= "$component: $value ";
            print "Response text : $response_text\n" if $DEBUG;
        }    
        else {
            printf "Nothing to do \n" if $DEBUG;
        }
    }
}


if ($status eq 1) {
       print "$problem_on_name value $problem_value, is above warning treshold $opt_w\n";
       $status = $ERRORS{"WARNING"};

} elsif ($status eq 2) {
       print "$problem_on_name value $problem_value,  is above critical treshold $opt_c\n";
       $status = $ERRORS{"CRITICAL"};

} else {
       print "$response_text  \n";
       $status = $ERRORS{"OK"};
}


exit $status;

##
###
### Functions
###
##


# Decypher the rrd black box ^^
sub get_last_rrd_data {
    my $rrdfile = shift;
    my $last = RRDs::last($rrdfile) or die "get last value failed ($RRDs::error)";
    my $start = $last - 300; # Damn rrd ! we may get two values, the one we want and 0.0, we will focus on the first ;-)
    my ($rrdstart, $step, $names, $data) =  RRDs::fetch($rrdfile, "--start=$start", "--end=$last", $cf) or die "fetch failed ($RRDs::error)";

    my $line;
    my $val;
    my $value;
    my $d_start = $start;
    foreach $line (@$data) {
        print "@ $d_start: "  if $DEBUG;
        $d_start += $step;
        foreach $val (@$line) { 
            if ( ! $val ) { 
                print "(undef)\n" if $DEBUG;
            }
            else {
                 print "$val \n"  if $DEBUG;
                 $value = $val;
            }
        }
    }
    if ( ! $value ) {
        print "(undef)\n" if $DEBUG;
    }
    else {
        return sprintf ("%2.1f",$value); # more human readable format
    }
}


# sanitize for human readable output
sub sanitize {
    my $var = shift;
    if ($opt_M eq "df") {
            if (($var !~ m/dev/ ) || ($var =~ m/udev/) || ($var =~ m/shm/)) {   # Get rid of non physical drives
                    $var = "";
            }
            else {
                    $var =~ s/\_/\//g;
            }
    }
    return $var;
}



# That one check parameters
sub check_parameters {
    # Basic checks
    if ($opt_V) {
             print_revision($PROGNAME,'$Revision: '.$REVISION.' $');
             exit $ERRORS{'UNKNOWN'};
    }

    if ($opt_h) {
             print_help ();
             print_revision($PROGNAME,'$Revision: '.$REVISION. ' $');
             exit $ERRORS{'UNKNOWN'};
    }

    if ($opt_v) {
        $DEBUG = 1;
    }

    if (!defined($opt_H))   {
            print "Hostname requested !\n";
            print_usage();
            exit $ERRORS{"UNKNOWN"}
    } else {
            $hostname = $opt_H if (utils::is_hostname($opt_H));
            ($hostname) || usage("Invalid hostname or address : $opt_H\n");
            printf "Hostname : $hostname\n" if $DEBUG;
            if ($hostname =~ /([^\.\/]+\.[^\.\/]+)$/m) {
                $domain = $1;
                printf "Computed Domain : $domain\n" if $DEBUG;
            }
    }

    if (defined($opt_D))    {
            $datadir = $opt_D;
            printf "Datadir : $datadir\n" if $DEBUG;
    }

    if (defined($opt_M))    {
            $module = $opt_M;
            printf "Module : $module\n" if $DEBUG;
    } else {
            print "Which module do you want to check ?\n";
            print_usage();
            exit $ERRORS{"UNKNOWN"};
    }

    if (defined($opt_d))    {
            $domain = $opt_d;
    } else {
                if (!defined($domain)) {
                        print "I can't guess your domain, please add the domain manually\n";
                        print_usage();
                        exit $ERRORS{"UNKNOWN"};
                }
    }

    printf "Domain : $domain\n" if $DEBUG;

    # Check warnings and critical
    if (!defined($opt_w) || !defined($opt_c)) {
         print "put warning and critical info !\n";
         print_usage();
         exit $ERRORS{"UNKNOWN"};
    }

} # end check_options


sub print_usage () {
   print "Usage: $0  -H <host> -M <Module> [-d <domain>] -w <warn level> -c <crit level> [-V] [-D <datadir>]\n";
}


sub print_help () {
  print "\nMonitor server via Munin-node pulled data\n";
  print_usage();
  print <<EOT;
-h, --help
       print this help message
-H, --hostname=HOST
       name or IP address of host to check
-M, --module=MUNIN MODULE
       Munin module value to fetch
-d, --domain=DOMAIN
       Domain as defined in munin
-w, --warn=INTEGER
       warning level
-c, --crit=INTEGER
       critical level
-v  --verbose
       Be verbose
-V, --version
       prints version number
-D, --datadir
       In case your datadir for munin is not /var/lib/munin
EOT
}


